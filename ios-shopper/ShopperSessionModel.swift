import Foundation

@MainActor
final class ShopperSessionModel: ObservableObject {
    enum ConnectionState: String {
        case idle = "Lista"
        case connecting = "Conectando"
        case connected = "Cliente conectado"
        case reconnecting = "Reconectando"
        case disconnected = "Sin conexión"
    }

    @Published var connectionState: ConnectionState = .idle
    @Published var selectedCamera: CameraSource = .iPhoneBack
    @Published var isMuted = false
    @Published var isRecording = false
    @Published var clientVideoAvailable = false
    @Published var statusMessage = "Preparada para iniciar sesión"
    @Published var recordingElapsedSeconds = 0
    @Published var isUsingBackupCamera = false
    @Published var preferredCamera: CameraSource = .iPhoneBack
    @Published var isEndingSession = false
    @Published var recordingSaveError: String?

    private var recordingTimer: Timer?

    let tokenEndpoint = URL(string: "https://divisa-shopper-ios.onrender.com/token")!
    let liveKit = LiveKitSessionManager()
    let metaWearables = MetaWearablesManager()
    let localRecorder = LocalVideoRecorder()

    init() {
        configureMetaFrameRoutes()
    }

    private func configureMetaFrameRoutes() {
        metaWearables.onPixelBuffer = { [weak self] buffer in
            self?.liveKit.pushRayBanFrame(buffer)
        }
        metaWearables.onVideoSampleBuffer = { [weak self] sampleBuffer in
            self?.localRecorder.append(sampleBuffer)
        }
        metaWearables.onStreamingChanged = { [weak self] streaming in
            guard let self, !streaming, self.selectedCamera == .rayBanMeta,
                  self.connectionState == .connected else { return }
            self.fallbackToIPhoneCamera()
        }
    }

    private func fallbackToIPhoneCamera() {
        statusMessage = "Ray-Ban desconectada · activando iPhone trasera…"
        Task {
            do {
                try await liveKit.useIPhoneCamera(.iPhoneBack, recorder: localRecorder)
                await liveKit.stopRayBanVideo()
                selectedCamera = .iPhoneBack
                isUsingBackupCamera = true
                statusMessage = isRecording
                    ? "Grabando · respaldo iPhone trasera activo"
                    : "Respaldo iPhone trasera activo"
            } catch {
                statusMessage = "Ray-Ban desconectada · error al activar respaldo: \(error.localizedDescription)"
            }
        }
    }

    func selectCamera(_ source: CameraSource) {
        preferredCamera = source
        selectedCamera = source
        isUsingBackupCamera = false

        guard connectionState == .connected else {
            statusMessage = "Fuente preparada: \(source.rawValue)"
            return
        }

        Task {
            do {
                switch source {
                case .iPhoneBack, .iPhoneFront:
                    // Publica primero el iPhone; luego retira Ray-Ban para evitar huecos.
                    try await liveKit.useIPhoneCamera(source, recorder: localRecorder)
                    if metaWearables.isStreaming {
                        await liveKit.stopRayBanVideo()
                        metaWearables.stopRayBanPreview()
                    }
                    statusMessage = isRecording
                        ? "Grabando · \(source.rawValue) activa"
                        : "Transmitiendo: \(source.rawValue)"
                case .rayBanMeta:
                    // Arranca primero la nueva fuente y solo después retira el iPhone.
                    // Así la sala y la grabación permanecen vivas durante la transición.
                    try await liveKit.useRayBanVideo()
                    await metaWearables.startRayBanPreview()
                    guard metaWearables.isStreaming else {
                        await liveKit.stopRayBanVideo()
                        statusMessage = "Ray-Ban no disponible · continúa cámara iPhone"
                        return
                    }
                    await liveKit.stopIPhoneCamera()
                    statusMessage = isRecording
                        ? "Grabando · Ray-Ban Meta activa"
                        : metaWearables.status
                }
            } catch {
                statusMessage = "No se pudo cambiar la cámara: \(error.localizedDescription)"
            }
        }
    }

    func retryPreferredCamera() {
        guard connectionState == .connected, preferredCamera == .rayBanMeta, isUsingBackupCamera else { return }
        statusMessage = "Buscando Ray-Ban Meta…"
        Task {
            do {
                try await liveKit.useRayBanVideo()
                await metaWearables.startRayBanPreview()
                guard metaWearables.isStreaming else {
                    await liveKit.stopRayBanVideo()
                    statusMessage = "Ray-Ban aún no disponible · continúa iPhone trasera"
                    return
                }
                await liveKit.stopIPhoneCamera()
                selectedCamera = .rayBanMeta
                isUsingBackupCamera = false
                statusMessage = isRecording ? "Grabando · Ray-Ban Meta recuperada" : "Ray-Ban Meta recuperada"
            } catch {
                statusMessage = "Ray-Ban aún no disponible · continúa respaldo iPhone"
            }
        }
    }

    func startSession() {
        guard connectionState != .connecting && connectionState != .connected else { return }

        connectionState = .connecting
        statusMessage = "Solicitando acceso a la sesión…"

        Task {
            do {
                try await liveKit.connect(
                    roomName: "divisa-shopper-prueba",
                    identity: "shopper-iphone",
                    displayName: "DIVISA SHOPPER"
                )
                connectionState = .connected
                isMuted = false

                if selectedCamera == .iPhoneBack || selectedCamera == .iPhoneFront {
                    try await liveKit.useIPhoneCamera(selectedCamera, recorder: localRecorder)
                    statusMessage = "Sesión conectada · \(selectedCamera.rawValue)"
                } else {
                    try await liveKit.useRayBanVideo()
                    await metaWearables.startRayBanPreview()
                    if metaWearables.isStreaming {
                        statusMessage = metaWearables.status
                    } else {
                        await liveKit.stopRayBanVideo()
                        statusMessage = "Ray-Ban no disponible · activando respaldo iPhone…"
                        try await liveKit.useIPhoneCamera(.iPhoneBack, recorder: localRecorder)
                        selectedCamera = .iPhoneBack
                        preferredCamera = .rayBanMeta
                        isUsingBackupCamera = true
                        statusMessage = "Sesión conectada · respaldo iPhone trasera activo"
                    }
                }
            } catch {
                connectionState = .disconnected
                statusMessage = "No se pudo conectar: \(error.localizedDescription)"
            }
        }
    }

    func endSession() {
        guard !isEndingSession else { return }
        isEndingSession = true
        statusMessage = isRecording ? "Guardando grabación antes de cerrar…" : "Finalizando sesión…"
        Task {
            if isRecording {
                await localRecorder.stop()
                isRecording = false
                stopRecordingTimer()
                guard localRecorder.lastRecordingURL != nil else {
                    recordingSaveError = "No se pudo confirmar el archivo. La sesión seguirá conectada para proteger la compra."
                    statusMessage = "Grabación no confirmada · sesión continúa conectada"
                    isEndingSession = false
                    return
                }
            }
            metaWearables.stopRayBanPreview()
            await liveKit.disconnect()
            connectionState = .idle
            clientVideoAvailable = false
            isUsingBackupCamera = false
            statusMessage = "Sesión finalizada"
            isEndingSession = false
        }
    }

    func toggleMute() {
        let newMutedState = !isMuted

        Task {
            do {
                try await liveKit.setMicrophone(enabled: !newMutedState)
                isMuted = newMutedState
                statusMessage = newMutedState ? "Micrófono silenciado" : "Micrófono activo"
            } catch {
                statusMessage = "No se pudo cambiar el micrófono: \(error.localizedDescription)"
            }
        }
    }

    var recordingTimeText: String {
        let hours = recordingElapsedSeconds / 3600
        let minutes = (recordingElapsedSeconds % 3600) / 60
        let seconds = recordingElapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func startRecordingTimer() {
        recordingElapsedSeconds = 0
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recordingElapsedSeconds += 1 }
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    func toggleRecording() {
        if isRecording {
            Task {
                await localRecorder.stop()
                isRecording = false
                stopRecordingTimer()
                if localRecorder.lastRecordingURL != nil {
                    statusMessage = "Grabación local guardada"
                } else {
                    recordingSaveError = "No se pudo confirmar el archivo de la grabación."
                    statusMessage = "Revisa la grabación antes de continuar"
                }
            }
        } else {
            localRecorder.start()
            isRecording = true
            startRecordingTimer()
            statusMessage = "Grabando localmente · \(selectedCamera.rawValue)"
        }
    }
}
