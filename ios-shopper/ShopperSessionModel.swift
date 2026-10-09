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
    }

    func selectCamera(_ source: CameraSource) {
        selectedCamera = source

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
                    statusMessage = metaWearables.status
                }
            } catch {
                connectionState = .disconnected
                statusMessage = "No se pudo conectar: \(error.localizedDescription)"
            }
        }
    }

    func endSession() {
        Task {
            if isRecording {
                await localRecorder.stop()
                isRecording = false
            }
            metaWearables.stopRayBanPreview()
            await liveKit.disconnect()
            connectionState = .idle
            clientVideoAvailable = false
            statusMessage = "Sesión finalizada"
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

    func toggleRecording() {
        if isRecording {
            Task {
                await localRecorder.stop()
                isRecording = false
                statusMessage = "Grabación local detenida"
            }
        } else {
            localRecorder.start()
            isRecording = true
            statusMessage = "Grabando localmente · \(selectedCamera.rawValue)"
        }
    }
}
