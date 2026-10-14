import Foundation
import MWDATCore
import MWDATCamera
import UIKit
import CoreMedia

@MainActor
final class MetaWearablesManager: ObservableObject {
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var status = "Ray-Ban sin conectar"
    @Published private(set) var isStreaming = false
    @Published private(set) var hasReceivedFrame = false
    @Published private(set) var diagnostic = "Cámara no iniciada"
    @Published private(set) var pipelineStage = "Meta inactivo"
    @Published private(set) var receivedFrameCount = 0
    @Published private(set) var lastFrameReceivedAt: Date?
    @Published private(set) var framesWithImageBuffer = 0
    @Published private(set) var framesWithoutImageBuffer = 0
    @Published private(set) var previewImageCount = 0
    @Published private(set) var streamFreezeCount = 0

    // No inicializar el SDK de Meta al abrir la app. Acceder solo cuando
    // el usuario solicita registrar o conectar las gafas.
    private var wearables: any WearablesInterface { Wearables.shared }
    private var deviceSession: DeviceSession?
    private var camera: Camera?
    private var stream: MWDATCamera.Stream?
    private var frameCount = 0
    private var firstFrameTime: CMTime?
    private var sessionStateTask: Task<Void, Never>?
    private var frameWatchdogTask: Task<Void, Never>?
    private let listenerTokens = ListenerTokenBag()
    private var streamGeneration: UInt = 0

    // Salidas puras del motor Meta. Este tipo no conoce LiveKit ni AVAssetWriter.
    // El coordinador decide después qué hacer con el frame oficial recibido.
    var onFrame: ((CMSampleBuffer) -> Void)?
    var onStreamingChanged: ((Bool) -> Void)?

    func registerGlasses() async {
        pipelineStage = "Registro · abriendo flujo oficial Meta"
        diagnostic = "Solicitando registro de las Ray-Ban"
        do {
            try await wearables.startRegistration()
            diagnostic = "Registro Meta iniciado · completa la autorización y vuelve a DIVISA SHOPPER"
        } catch {
            diagnostic = "Error de registro Meta: \(error.localizedDescription)"
            status = "No se pudo iniciar el registro: \(error.localizedDescription)"
        }
    }

    /// Punto único para entregar a Wearables el callback oficial de registro.
    /// La App solo reenvía la URL; el motor Meta conserva el diagnóstico.
    func handleRegistrationCallback(_ url: URL) async {
        pipelineStage = "Registro · procesando retorno Meta"
        diagnostic = "Procesando autorización de las Ray-Ban…"
        do {
            _ = try await wearables.handleUrl(url)
            diagnostic = "Retorno Meta aceptado · listo para crear DeviceSession"
            status = "Ray-Ban registrada"
        } catch {
            diagnostic = "Error procesando retorno Meta: \(error.localizedDescription)"
            status = "No se pudo completar el registro Ray-Ban"
        }
    }

    /// Etapa 1 CameraAccess: prepara una DeviceSession y espera confirmación
    /// de Meta. No publica LiveKit, no graba y no toca la cámara del iPhone.
    private func startDeviceSession(generation: UInt) async throws -> DeviceSession? {
        pipelineStage = "1/5 · Permiso de cámara Meta"
        diagnostic = "Solicitando permiso Meta…"
        if try await wearables.checkPermissionStatus(.camera) != .granted {
            let permission = try await wearables.requestPermission(.camera)
            guard permission == .granted else {
                // La autorización abre Meta AI y puede terminar después de
                // que el usuario haya iniciado otra conexión.
                guard !Task.isCancelled, streamGeneration == generation else { return nil }
                status = "Permiso de cámara Ray-Ban no concedido"
                return nil
            }
        }

        // El permiso puede abrir una pantalla externa y tardar. Si el usuario
        // canceló o inició otra prueba, no crear una sesión obsoleta.
        guard !Task.isCancelled, streamGeneration == generation else { return nil }

        pipelineStage = "2/5 · Creando DeviceSession"
        diagnostic = "Permiso concedido · creando sesión Meta"
        let selector = AutoDeviceSelector(wearables: wearables)
        let session = try wearables.createSession(deviceSelector: selector)
        deviceSession = session

        let stateStream = session.stateStream()
        diagnostic = "Iniciando sesión de gafas…"
        do {
            try session.start()
        } catch {
            // No dejar una DeviceSession fallida retenida como si estuviera activa.
            session.stop()
            if streamGeneration == generation {
                deviceSession = nil
            }
            throw error
        }

        // Limitar la espera: si Meta nunca confirma .started, detener
        // DeviceSession para desbloquear stateStream y mostrar diagnóstico.
        // El temporizador pertenece a esta generación y se cancela al salir.
        let startupTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self,
                  self.streamGeneration == generation else { return }
            self.diagnostic = "Meta no inició DeviceSession en 30 s · revisa conexión y autorización"
            self.status = "Tiempo de espera agotado al conectar Ray-Ban"
            session.stop()
        }
        defer { startupTimeout.cancel() }

        for await state in stateStream {
            guard !Task.isCancelled, streamGeneration == generation else { return nil }
            // No ocultar la causa original cuando el watchdog detiene
            // la sesión y el SDK publica posteriormente el estado .stopped.
            if status != "Tiempo de espera agotado al conectar Ray-Ban" {
                diagnostic = "Estado de sesión Meta: \(state)"
            }
            if state == .started {
                // Una confirmación tardía no debe reactivar una sesión
                // que ya superó el límite de espera de conexión.
                guard status != "Tiempo de espera agotado al conectar Ray-Ban" else {
                    session.stop()
                    return nil
                }
                pipelineStage = "3/5 · DeviceSession iniciada"
                return session
            }
            if state == .stopped {
                if status != "Tiempo de espera agotado al conectar Ray-Ban" {
                    status = "Meta detuvo la sesión antes de activar la cámara"
                }
                // Liberar la sesión detenida antes de ofrecer un nuevo intento.
                if streamGeneration == generation {
                    deviceSession = nil
                }
                return nil
            }
        }
        // Si el AsyncStream termina sin .started, no conservar una sesión
        // que nunca llegó a estar lista para CameraStream.
        if streamGeneration == generation {
            session.stop()
            deviceSession = nil
            diagnostic = "DeviceSession terminó sin confirmar estado iniciado"
            status = "Ray-Ban no confirmó la conexión"
        }
        return nil
    }

    /// Etapa 2 CameraAccess: abre exclusivamente la cámara de la DeviceSession
    /// ya iniciada y conecta sus publishers oficiales.
    private func startCameraStream(session: DeviceSession, generation: UInt) throws {
        pipelineStage = "4/5 · Abriendo CameraStream"
        diagnostic = "Sesión Meta iniciada · abriendo cámara…"
        let config = StreamConfiguration(
            videoCodec: .raw,
            resolution: .low,
            frameRate: 24
        )

        guard let camera = try session.addCamera(config: config) else {
            let message = "Las gafas están conectadas, pero la cámara no está disponible"
            status = message
            throw NSError(
                domain: "DIVISAShopper.MetaCamera",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        self.camera = camera
        let stream = camera.stream
        self.stream = stream
        diagnostic = "Cámara Meta asignada · esperando fotogramas"

        stream.videoFramePublisher.listen { [weak self] frame in
            let pixelBuffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer)
            let image = frame.makeUIImage()
            Task { @MainActor in
                guard let self, self.streamGeneration == generation else { return }
                self.frameCount += 1
                self.receivedFrameCount = self.frameCount
                // El watchdog debe medir la última imagen realmente utilizable,
                // no cualquier muestra recibida (puede llegar HEVC sin pixel buffer).
                if pixelBuffer != nil && CMSampleBufferDataIsReady(frame.sampleBuffer) {
                    self.lastFrameReceivedAt = Date()
                    self.framesWithImageBuffer += 1
                    self.hasReceivedFrame = true
                    self.pipelineStage = "5/5 · Primer frame recibido"
                    self.diagnostic = "Video Ray-Ban recibido · fotogramas: \(self.frameCount)"
                } else {
                    self.framesWithoutImageBuffer += 1
                    self.diagnostic = "Meta entrega frame sin imagen decodificada · fotograma \(self.frameCount)"
                }
                // La vista previa y el grabador deben basarse en la misma
                // muestra válida; una UIImage aislada no confirma que exista
                // un sampleBuffer listo para guardar.
                if pixelBuffer != nil && CMSampleBufferDataIsReady(frame.sampleBuffer) {
                    if let image {
                        self.previewImage = image
                        self.previewImageCount += 1
                        self.pipelineStage = "5/5 · Imagen visible recibida"
                    }
                    self.onFrame?(frame.sampleBuffer)
                }
            }
        }.store(in: listenerTokens)

        stream.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                guard let self, self.streamGeneration == generation else { return }
                let streaming = state == .streaming
                let wasStreaming = self.isStreaming
                self.isStreaming = streaming
                if wasStreaming && !streaming {
                    // El SDK dejó de transmitir: cerrar el segmento activo
                    // antes de intentar recuperar la cámara.
                    self.onStreamingChanged?(false)
                }
                if streaming {
                    if !wasStreaming {
                        self.onStreamingChanged?(true)
                    }
                    self.status = "Ray-Ban transmitiendo"
                    if !self.hasReceivedFrame {
                        self.diagnostic = "Meta indica streaming · esperando primer fotograma"
                    }
                } else {
                    self.status = "Ray-Ban: \(state)"
                    self.diagnostic = "Estado del video Meta: \(state)"
                }
            }
        }.store(in: listenerTokens)

        stream.errorPublisher.listen { [weak self] error in
            Task { @MainActor in
                guard let self, self.streamGeneration == generation else { return }
                self.diagnostic = "Error SDK Meta: \(error.localizedDescription)"
                self.status = self.diagnostic
                if self.isStreaming {
                    self.isStreaming = false
                    self.onStreamingChanged?(false)
                }
            }
        }.store(in: listenerTokens)

        diagnostic = "Solicitando inicio de video Meta (baja resolución)"
        stream.start()
        observeSessionLifecycle(session, generation: generation)
        startFrameWatchdog(generation: generation)
    }

    /// Igual que CameraAccess, vigila que el stream no quede marcado como
    /// activo mientras dejan de llegar fotogramas. No toca LiveKit ni iPhone.
    private func startFrameWatchdog(generation: UInt) {
        frameWatchdogTask?.cancel()
        frameWatchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.streamGeneration == generation else { return }
                guard self.isStreaming, self.hasReceivedFrame,
                      let last = self.lastFrameReceivedAt else { continue }
                if Date().timeIntervalSince(last) >= 2 {
                    self.streamFreezeCount += 1
                    self.diagnostic = "Stream Meta activo pero sin frames por 2 s · corte \(self.streamFreezeCount)"
                    self.status = "Ray-Ban sin fotogramas"
                    self.isStreaming = false
                    self.onStreamingChanged?(false)
                    return
                }
            }
        }
    }

    private func observeSessionLifecycle(_ session: DeviceSession, generation: UInt) {
        sessionStateTask?.cancel()
        sessionStateTask = Task { [weak self, weak session] in
            guard let session else { return }
            for await state in session.stateStream() {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.streamGeneration == generation else { return }
                    switch state {
                    case .paused:
                        self.diagnostic = "Sesión Meta pausada · esperando reanudación"
                        let wasStreaming = self.isStreaming
                        self.isStreaming = false
                        if wasStreaming {
                            self.onStreamingChanged?(false)
                        }
                    case .started:
                        if self.hasReceivedFrame {
                            self.diagnostic = "Sesión Meta activa · video disponible"
                        }
                    case .stopped:
                        self.diagnostic = "Sesión Meta detenida · se requiere nueva sesión"
                        let wasStreaming = self.isStreaming
                        self.isStreaming = false
                        if wasStreaming {
                            self.onStreamingChanged?(false)
                        }
                    default:
                        break
                    }
                }
            }
        }
    }

    /// Reabre únicamente CameraStream sobre una DeviceSession que continúa
    /// activa. Es la recuperación preferida antes de destruir/recrear la sesión.
    func restartCameraStream() async -> Bool {
        guard let session = deviceSession else {
            diagnostic = "No existe DeviceSession para reiniciar solamente el video"
            return false
        }

        stopCameraStream()
        // stopCameraStream ya invalida la generación anterior.
        let generation = streamGeneration
        hasReceivedFrame = false
        previewImage = nil
        frameCount = 0
        firstFrameTime = nil

        do {
            try startCameraStream(session: session, generation: generation)
            let recovered = await waitUntilFirstFrame(timeoutSeconds: 20)
            if !recovered {
                diagnostic = "CameraStream reiniciado, pero Meta no entregó imagen válida en 20 s"
                status = "Ray-Ban sin imagen tras reiniciar cámara"
            }
            return recovered
        } catch {
            diagnostic = "Error reiniciando CameraStream: \(error.localizedDescription)"
            status = diagnostic
            return false
        }
    }

    /// Orquestación de conveniencia: conserva un solo botón en DIVISA SHOPPER,
    /// pero internamente sesión y cámara son dos etapas independientes.
    func startRayBanPreview() async {
        streamGeneration &+= 1
        let generation = streamGeneration
        hasReceivedFrame = false
        previewImage = nil
        frameCount = 0
        receivedFrameCount = 0
        framesWithImageBuffer = 0
        framesWithoutImageBuffer = 0
        previewImageCount = 0
        lastFrameReceivedAt = nil
        firstFrameTime = nil
        sessionStateTask?.cancel()
        sessionStateTask = nil
        frameWatchdogTask?.cancel()
        frameWatchdogTask = nil
        // Primero cancelar las suscripciones: no recibir estados tardíos
        // mientras se cierran la cámara y la sesión anterior.
        listenerTokens.clear()
        camera?.stop()
        deviceSession?.stop()
        stream = nil
        camera = nil
        deviceSession = nil

        do {
            guard let session = try await startDeviceSession(generation: generation) else { return }
            // Una segunda solicitud o un cierre puede invalidar esta operación
            // mientras el SDK espera autorización o conexión de las gafas.
            guard !Task.isCancelled, streamGeneration == generation else { return }
            try startCameraStream(session: session, generation: generation)
        } catch {
            // Un intento antiguo no debe reemplazar el diagnóstico de una
            // conexión más reciente ni el estado de una sesión ya cerrada.
            guard !Task.isCancelled, streamGeneration == generation else { return }
            diagnostic = "Error de inicio Meta: \(error.localizedDescription)"
            status = diagnostic
        }
    }

    /// No considerar Ray-Ban lista solo porque el SDK diga "streaming".
    /// Para DIVISA SHOPPER la cámara está lista únicamente después de recibir
    /// al menos un fotograma real.
    func waitUntilFirstFrame(timeoutSeconds: Double = 12) async -> Bool {
        let expectedGeneration = streamGeneration
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            guard !Task.isCancelled, streamGeneration == expectedGeneration else { return false }
            if hasReceivedFrame { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return !Task.isCancelled && streamGeneration == expectedGeneration && hasReceivedFrame
    }

    /// Espera el estado real del stream antes de decidir si usar el respaldo.
    /// Evita interpretar como fallo el tiempo normal de conexión de las gafas.
    func waitUntilStreaming(timeoutSeconds: Double = 12) async -> Bool {
        let expectedGeneration = streamGeneration
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            guard !Task.isCancelled, streamGeneration == expectedGeneration else { return false }
            if isStreaming { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return !Task.isCancelled && streamGeneration == expectedGeneration && isStreaming
    }

    /// Detiene solo el video. Mantiene DeviceSession disponible para
    /// reabrir CameraStream sin volver a registrar/reconectar las gafas.
    func stopCameraStream() {
        // Avisar al coordinador antes de cerrar el stream: si se estaban
        // grabando fotogramas Meta, debe finalizar el segmento actual.
        let wasStreaming = isStreaming
        streamGeneration &+= 1
        // Cada CameraStream instala también un observador de DeviceSession.
        // Cancelarlo al detener la cámara evita acumular observadores al
        // reiniciar el stream sobre la misma sesión.
        sessionStateTask?.cancel()
        sessionStateTask = nil
        listenerTokens.clear()
        if wasStreaming {
            isStreaming = false
            onStreamingChanged?(false)
        }
        frameWatchdogTask?.cancel()
        frameWatchdogTask = nil
        camera?.stop()
        stream = nil
        camera = nil
        previewImage = nil
        isStreaming = false
        hasReceivedFrame = false
        frameCount = 0
        receivedFrameCount = 0
        framesWithImageBuffer = 0
        framesWithoutImageBuffer = 0
        lastFrameReceivedAt = nil
        firstFrameTime = nil
        pipelineStage = deviceSession == nil ? "Meta inactivo" : "3/5 · DeviceSession iniciada"
        diagnostic = deviceSession == nil ? "Cámara detenida" : "Video Meta detenido · sesión de gafas conservada"
    }

    /// Cierre completo del motor Meta: video + DeviceSession.
    func stopRayBanPreview() {
        stopCameraStream()
        streamGeneration &+= 1
        sessionStateTask?.cancel()
        sessionStateTask = nil
        deviceSession?.stop()
        deviceSession = nil
        previewImage = nil
        isStreaming = false
        hasReceivedFrame = false
        frameCount = 0
        firstFrameTime = nil
        status = "Ray-Ban sin conectar"
        pipelineStage = "Meta inactivo"
        diagnostic = "Cámara detenida"
    }
}
