import Foundation
import UIKit
import CoreMedia

private enum CameraSourceError: Error {
    case rayBanNoFrames
}

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
    @Published var isSwitchingCamera = false
    @Published var rayBanPreviewImage: UIImage?
    @Published var rayBanFramesReady = false
    @Published var isCameraRecoveryWaiting = false

    private var recordingTimer: Timer?
    private var lastIPhoneFrameAt: Date?
    private var iPhoneFrameWatchdogTask: Task<Void, Never>?
    private var iPhoneSegmentInterrupted = false
    private var cameraRecoveryDeadlineTask: Task<Void, Never>?
    private var metaInterruptionPending = false

    let tokenEndpoint = URL(string: "https://divisa-shopper-ios.onrender.com/token")!
    let liveKit = LiveKitSessionManager()
    let metaWearables = MetaWearablesManager()
    let localRecorder = LocalVideoRecorder()

    init() {
        configureMetaFrameRoutes()
        configureIPhoneFrameWatchdog()
    }

    private func configureIPhoneFrameWatchdog() {
        liveKit.onIPhoneFrameReceived = { [weak self] source in
            guard let self, self.liveKit.activeCameraSource == source else { return }
            self.lastIPhoneFrameAt = Date()
            if self.iPhoneSegmentInterrupted {
                self.iPhoneSegmentInterrupted = false
                self.statusMessage = "Video iPhone recuperado · nuevo segmento al recibir imagen"
            }
        }
        iPhoneFrameWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                guard self.isRecording,
                      let active = self.liveKit.activeCameraSource,
                      active == .iPhoneBack || active == .iPhoneFront,
                      let last = self.lastIPhoneFrameAt,
                      Date().timeIntervalSince(last) >= 4,
                      !self.iPhoneSegmentInterrupted,
                      !self.isSwitchingCamera,
                      !self.isEndingSession else { continue }
                self.iPhoneSegmentInterrupted = true
                let protected = await self.localRecorder.archiveCurrentSegmentForInterruption()
                if protected {
                    self.statusMessage = "Interrupción iPhone · segmento MOV protegido"
                } else {
                    self.recordingSaveError = "No se pudo confirmar el cierre del segmento iPhone interrumpido."
                    self.statusMessage = "Interrupción iPhone · revisa la grabación"
                }
            }
        }
    }


    private func configureMetaFrameRoutes() {
        // Único punto de unión: el motor Meta entrega un frame oficial y el
        // coordinador decide preview, LiveKit y grabación. El motor iPhone
        // permanece completamente ajeno al SDK de Meta.
        metaWearables.onFrame = { [weak self] sampleBuffer in
            guard let self else { return }
            // El SDK puede entregar muestras HEVC comprimidas sin CVPixelBuffer.
            // No declarar lista la cámara ni publicar/grabar muestras sin imagen
            // decodificada; primero se validará la ruta oficial CameraAccess.
            guard CMSampleBufferDataIsReady(sampleBuffer),
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return
            }
            self.rayBanFramesReady = true
            self.rayBanPreviewImage = self.metaWearables.previewImage
            self.liveKit.pushRayBanFrame(pixelBuffer)

            // Guardar los fotogramas locales de Meta sin depender del estado de publicación de LiveKit.
            // El grabador conoce su fuente activa y rechaza por sí mismo
            // muestras de otra cámara. No depender del picker, que cambia
            // después de la transición y puede descartar el primer frame.
            // Durante la protección de un segmento interrumpido, no admitir
            // frames tardíos en el archivo anterior ni abrir uno nuevo hasta
            // completar la ventana de recuperación.
            guard self.isRecording, !self.metaInterruptionPending else { return }
            self.localRecorder.append(sampleBuffer, source: .rayBanMeta)
        }
        metaWearables.onStreamingChanged = { [weak self] streaming in
            guard let self, !streaming, self.selectedCamera == .rayBanMeta,
                  self.connectionState == .connected,
                  !self.isSwitchingCamera, !self.isEndingSession,
                  self.metaWearables.hasReceivedFrame,
                  !self.metaInterruptionPending else { return }
            self.metaInterruptionPending = true
            // Una sola tarea serializa el cierre del MOV y la recuperación.
            // Nunca reiniciar CameraStream mientras finishWriting sigue activo.
            Task { [weak self] in
                guard let self else { return }
                if self.isRecording {
                    let protected = await self.localRecorder.archiveCurrentSegmentForInterruption()
                    // El usuario puede detener la grabación o finalizar la
                    // sesión mientras finishWriting() está suspendido.
                    // No sobrescribir el estado de esas acciones posteriores.
                    guard self.connectionState == .connected,
                          self.selectedCamera == .rayBanMeta,
                          !self.isEndingSession else {
                        self.metaInterruptionPending = false
                        return
                    }
                    if protected {
                        if self.isRecording {
                            self.statusMessage = "Segmento Ray-Ban protegido · esperando recuperación"
                        }
                    } else if self.isRecording {
                        self.recordingSaveError = "No se pudo confirmar el cierre del segmento Ray-Ban interrumpido."
                    }
                }

                // El SDK puede emitir estados transitorios starting/paused.
                // La espera solo comienza después de proteger el archivo.
                try? await Task.sleep(for: .seconds(3))
                guard self.connectionState == .connected,
                      self.selectedCamera == .rayBanMeta,
                      !self.metaWearables.isStreaming,
                      !self.isSwitchingCamera,
                      !self.isEndingSession else {
                    self.metaInterruptionPending = false
                    return
                }
                // El MOV anterior ya terminó. Permitir que el primer frame
                // recuperado cree el nuevo segmento, incluso mientras
                // waitUntilFirstFrame todavía espera confirmación del SDK.
                // recoverRayBanStream marca isSwitchingCamera sin suspenderse,
                // por lo que otra interrupción no inicia recuperación paralela.
                self.metaInterruptionPending = false
                await self.recoverRayBanStream()
            }
        }
    }

    private func recoverRayBanStream() async {
        guard !isSwitchingCamera && !isEndingSession else { return }
        isSwitchingCamera = true
        statusMessage = "Ray-Ban en recuperación · la llamada continúa…"
        defer { isSwitchingCamera = false }

        await liveKit.stopRayBanVideo()
        rayBanFramesReady = false
        rayBanPreviewImage = nil

        // Primer intento: recuperar solo CameraStream y conservar DeviceSession.
        // Si Meta sigue conectado, evitamos registrar/recrear toda la sesión.
        do {
            try await liveKit.useRayBanVideo()
            if await metaWearables.restartCameraStream() {
                liveKit.confirmRayBanActive()
                await localRecorder.transitionRecording(to: .rayBanMeta)
                cameraRecoveryDeadlineTask?.cancel()
                cameraRecoveryDeadlineTask = nil
                isCameraRecoveryWaiting = false
                selectedCamera = .rayBanMeta
                isUsingBackupCamera = false
                statusMessage = isRecording ? "Grabando · Ray-Ban recuperada" : "Ray-Ban recuperada · sesión continúa"
                return
            }

            // Segundo intento: si la DeviceSession ya no sirve, reconstruir
            // completamente el motor Meta.
            metaWearables.stopRayBanPreview()
            await metaWearables.startRayBanPreview()
            if await metaWearables.waitUntilFirstFrame(timeoutSeconds: 20) {
                liveKit.confirmRayBanActive()
                await localRecorder.transitionRecording(to: .rayBanMeta)
                cameraRecoveryDeadlineTask?.cancel()
                cameraRecoveryDeadlineTask = nil
                isCameraRecoveryWaiting = false
                selectedCamera = .rayBanMeta
                isUsingBackupCamera = false
                statusMessage = isRecording ? "Grabando · Ray-Ban recuperada" : "Ray-Ban recuperada · sesión continúa"
                return
            }
        } catch {
            statusMessage = "Ray-Ban no respondió · preparando cámara de respaldo…"
        }

        await liveKit.stopRayBanVideo()
        metaWearables.stopRayBanPreview()

        // No forzar inmediatamente otra cámara. El shopper dispone de una
        // ventana operativa para acomodar el iPhone, una cámara externa o
        // volver a intentar Meta. La llamada y el audio siguen conectados.
        isSwitchingCamera = false
        isCameraRecoveryWaiting = true
        statusMessage = "Estamos cambiando de cámara · la sesión continúa"
        cameraRecoveryDeadlineTask?.cancel()
        cameraRecoveryDeadlineTask = Task { [weak self] in
            // Sumado al intento inicial, mantiene el cambio dentro de un máximo
            // aproximado de tres minutos sin dejar la sesión abandonada.
            try? await Task.sleep(for: .seconds(160))
            guard !Task.isCancelled, let self,
                  self.connectionState == .connected,
                  self.selectedCamera == .rayBanMeta,
                  !self.metaWearables.isStreaming,
                  !self.isEndingSession,
                  !self.isSwitchingCamera else { return }
            self.isCameraRecoveryWaiting = false
            self.fallbackToIPhoneCamera()
        }
    }

    private func fallbackToIPhoneCamera() {
        guard !isSwitchingCamera && !isEndingSession else { return }
        isSwitchingCamera = true
        statusMessage = "Ray-Ban desconectada · activando iPhone trasera…"
        Task {
            defer { isSwitchingCamera = false }
            do {
                try await liveKit.useIPhoneCamera(.iPhoneBack, recorder: localRecorder)
                await localRecorder.transitionRecording(to: .iPhoneBack)
                await liveKit.stopRayBanVideo()
                metaWearables.stopRayBanPreview()
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
        // Una selección durante otra transición no debe cancelar el plazo
        // de respaldo automático ni dejar la sesión esperando indefinidamente.
        guard !isSwitchingCamera && !isEndingSession else { return }
        cameraRecoveryDeadlineTask?.cancel()
        cameraRecoveryDeadlineTask = nil
        isCameraRecoveryWaiting = false
        preferredCamera = source

        guard connectionState == .connected else {
            selectedCamera = source
            isUsingBackupCamera = false
            statusMessage = "Fuente preparada: \(source.rawValue)"
            return
        }

        isSwitchingCamera = true
        Task {
            defer { isSwitchingCamera = false }
            do {
                switch source {
                case .iPhoneBack, .iPhoneFront:
                    // Publica primero el iPhone; luego retira Ray-Ban para evitar huecos.
                    try await liveKit.useIPhoneCamera(source, recorder: localRecorder)
                    await localRecorder.transitionRecording(to: source)
                    // Cerrar siempre la ruta Meta: puede existir una sesión aunque ya no marque streaming.
                    await liveKit.stopRayBanVideo()
                    metaWearables.stopRayBanPreview()
                    selectedCamera = source
                    isUsingBackupCamera = false
                    statusMessage = isRecording
                        ? "Grabando · \(source.rawValue) activa"
                        : "Transmitiendo: \(source.rawValue)"
                case .rayBanMeta:
                    // Arranca primero la nueva fuente y solo después retira el iPhone.
                    // Así la sala y la grabación permanecen vivas durante la transición.
                    try await liveKit.useRayBanVideo()
                    rayBanFramesReady = false
                    rayBanPreviewImage = nil
                    await metaWearables.startRayBanPreview()
                    guard await metaWearables.waitUntilFirstFrame() else {
                        await liveKit.stopRayBanVideo()
                        metaWearables.stopRayBanPreview()
                        statusMessage = "Ray-Ban no disponible · continúa cámara iPhone"
                        return
                    }
                    liveKit.confirmRayBanActive()
                    await localRecorder.transitionRecording(to: .rayBanMeta)
                    await liveKit.stopIPhoneCamera()
                    selectedCamera = .rayBanMeta
                    isUsingBackupCamera = false
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
        guard connectionState == .connected, preferredCamera == .rayBanMeta, isUsingBackupCamera, !isSwitchingCamera, !isEndingSession else { return }
        isSwitchingCamera = true
        statusMessage = "Buscando Ray-Ban Meta…"
        Task {
            defer { isSwitchingCamera = false }
            do {
                try await liveKit.useRayBanVideo()
                rayBanFramesReady = false
                rayBanPreviewImage = nil
                await metaWearables.startRayBanPreview()
                guard await metaWearables.waitUntilFirstFrame() else {
                    await liveKit.stopRayBanVideo()
                    metaWearables.stopRayBanPreview()
                    statusMessage = "Ray-Ban aún no disponible · continúa iPhone trasera"
                    return
                }
                liveKit.confirmRayBanActive()
                await localRecorder.transitionRecording(to: .rayBanMeta)
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
        guard connectionState != .connecting && connectionState != .connected &&
              !isEndingSession && !isSwitchingCamera && !isFinalizingLocalRecording else { return }

        // Cada compra comienza con estado limpio; no arrastrar avisos o respaldo de la sesión anterior.
        recordingSaveError = nil
        metaInterruptionPending = false
        isUsingBackupCamera = false
        isSwitchingCamera = false
        isCameraRecoveryWaiting = false
        cameraRecoveryDeadlineTask?.cancel()
        cameraRecoveryDeadlineTask = nil
        recordingElapsedSeconds = 0
        lastIPhoneFrameAt = nil
        iPhoneSegmentInterrupted = false
        rayBanFramesReady = false
        rayBanPreviewImage = nil

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
                    // La cámara Ray-Ban es una fuente opcional: un fallo del SDK Meta
                    // nunca debe tumbar una sala LiveKit que ya está conectada.
                    do {
                        try await liveKit.useRayBanVideo()
                        await metaWearables.startRayBanPreview()
                        if await metaWearables.waitUntilFirstFrame() {
                            liveKit.confirmRayBanActive()
                            await localRecorder.transitionRecording(to: .rayBanMeta)
                            statusMessage = metaWearables.status
                        } else {
                            throw CameraSourceError.rayBanNoFrames
                        }
                    } catch {
                        await liveKit.stopRayBanVideo()
                        metaWearables.stopRayBanPreview()
                        statusMessage = "Ray-Ban sin video · activando respaldo iPhone…"
                        do {
                            try await liveKit.useIPhoneCamera(.iPhoneBack, recorder: localRecorder)
                            await localRecorder.transitionRecording(to: .iPhoneBack)
                            selectedCamera = .iPhoneBack
                            preferredCamera = .rayBanMeta
                            isUsingBackupCamera = true
                            statusMessage = "Sesión conectada · respaldo iPhone trasera activo"
                        } catch {
                            statusMessage = "Sesión conectada · sin video: \(error.localizedDescription)"
                        }
                    }
                }
            } catch {
                // Solo un fallo real de TOKEN/LIVEKIT/MICRÓFONO debe marcar la llamada
                // como desconectada. Los fallos de cámara se aíslan arriba.
                connectionState = .disconnected
                statusMessage = "No se pudo conectar: \(error.localizedDescription)"
            }
        }
    }

    func endSession() {
        guard !isEndingSession && !isSwitchingCamera && !isFinalizingLocalRecording else {
            if isSwitchingCamera { statusMessage = "Espera a que termine el cambio de cámara" }
            if isFinalizingLocalRecording { statusMessage = "Espera a que termine de guardarse la grabación" }
            return
        }
        isEndingSession = true
        let needsRecordingFinalization = isRecording
        statusMessage = needsRecordingFinalization ? "Guardando grabación antes de cerrar…" : "Finalizando sesión…"
        if needsRecordingFinalization {
            // Cerrar la entrada de frames antes de suspendernos en finishWriting.
            isRecording = false
            isFinalizingLocalRecording = true
            stopRecordingTimer()
        }
        Task {
            if needsRecordingFinalization {
                await localRecorder.stop()
                isFinalizingLocalRecording = false
                guard !localRecorder.lastRecordingSegments.isEmpty else {
                    recordingSaveError = "No se pudo confirmar el archivo. La sesión seguirá conectada para proteger la compra."
                    statusMessage = "Grabación no confirmada · sesión continúa conectada"
                    isEndingSession = false
                    return
                }
            }
            cameraRecoveryDeadlineTask?.cancel()
            cameraRecoveryDeadlineTask = nil
            isCameraRecoveryWaiting = false
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
        guard connectionState == .connected, !isEndingSession, !isSwitchingCamera else { return }
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

    private var isFinalizingLocalRecording = false

    func toggleRecording() {
        // La fuente que realmente publica LiveKit manda sobre cualquier estado
        // transitorio del Picker. Así el respaldo iPhone puede grabar aunque
        // Ray-Ban haya fallado segundos antes.
        // Stopping a local recording must remain possible even if LiveKit drops.
        // Only starting a new recording requires an active client session.
        guard !isEndingSession, !isSwitchingCamera, !isFinalizingLocalRecording else { return }
        if isRecording {
            // Cerrar la compuerta de entrada antes de esperar finishWriting:
            // los frames tardíos no deben abrir otro MOV mientras se detiene.
            isRecording = false
            isFinalizingLocalRecording = true
            stopRecordingTimer()
            Task {
                defer { isFinalizingLocalRecording = false }
                await localRecorder.stop()
                if !localRecorder.lastRecordingSegments.isEmpty {
                    statusMessage = "Grabación local guardada"
                } else {
                    recordingSaveError = "No se pudo confirmar el archivo de la grabación."
                    statusMessage = "Revisa la grabación antes de continuar"
                }
            }
        } else {
            guard connectionState == .connected else {
                statusMessage = "Conecta la sesión antes de iniciar una grabación"
                return
            }
            let actualSource = liveKit.activeCameraSource ?? selectedCamera
            if actualSource == .rayBanMeta && !rayBanFramesReady {
                statusMessage = "Ray-Ban sin imagen real · grabación bloqueada"
                recordingSaveError = "Las Ray-Ban todavía no están entregando video. La grabación no se inició."
                return
            }
            recordingSaveError = nil
            localRecorder.start(source: actualSource)
            iPhoneSegmentInterrupted = false
            lastIPhoneFrameAt = nil
            isRecording = true
            startRecordingTimer()
            statusMessage = "Grabando localmente · \((liveKit.activeCameraSource ?? selectedCamera).rawValue)"
        }
    }
}
