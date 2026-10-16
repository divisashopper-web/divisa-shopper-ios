import Foundation
import MWDATCore
import MWDATCamera
import UIKit
import CoreMedia
import CoreImage
import VideoToolbox

@MainActor
final class MetaWearablesManager: ObservableObject {
    @Published private(set) var registrationStatus = "Sin consultar"
    @Published private(set) var detectedGlasses = 0
    @Published private(set) var activeGlassesAvailable = false
    @Published private(set) var deviceCompatibilitySummary = "Sin comprobar"
    @Published private(set) var firmwareUpdateRequired = false
    @Published private(set) var attemptNumber = 0
    @Published private(set) var lastAttemptResult = "Sin pruebas"
    @Published private(set) var lastAttemptStage = "Sin iniciar"
    @Published private(set) var attemptEvents: [String] = []

    private func trace(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        attemptEvents.append("\(timestamp) · \(message)")
        if attemptEvents.count > 24 { attemptEvents.removeFirst(attemptEvents.count - 24) }
        lastAttemptStage = message
    }
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var status = "Ray-Ban sin conectar"
    @Published private(set) var isStreaming = false
    @Published private(set) var hasReceivedFrame = false
    @Published private(set) var diagnostic = "Cámara no iniciada"
    @Published private(set) var pipelineStage = "Meta inactivo"
    @Published private(set) var sdkSessionState = "Sin iniciar"
    @Published private(set) var sdkStreamState = "Sin iniciar"
    @Published private(set) var lastSDKError = "Ninguno"
    @Published private(set) var receivedFrameCount = 0
    @Published private(set) var lastFrameReceivedAt: Date?
    @Published private(set) var framesWithImageBuffer = 0
    @Published private(set) var framesWithoutImageBuffer = 0
    @Published private(set) var previewImageCount = 0
    @Published private(set) var previewFallbackCount = 0
    @Published private(set) var streamFreezeCount = 0
    @Published private(set) var firstFrameTimeoutDiagnostic: String?

    // No inicializar el SDK de Meta al abrir la app. Acceder solo cuando
    // el usuario solicita registrar o conectar las gafas.
    private var wearables: any WearablesInterface { Wearables.shared }
    private lazy var deviceSelector = AutoDeviceSelector(wearables: wearables)
    private var activeDeviceMonitor: Task<Void, Never>?
    private var compatibilityTokens: [DeviceIdentifier: AnyListenerToken] = [:]
    private var deviceCompatibility: [DeviceIdentifier: Compatibility] = [:]
    private let sessionErrorTokens = ListenerTokenBag()
    private var deviceSession: DeviceSession?
    private var camera: Camera?
    private var stream: MWDATCamera.Stream?
    private var frameCount = 0
    private let previewCIContext = CIContext()
    private var hevcDecoder: VTDecompressionSession?
    private var hevcFormat: CMFormatDescription?
    private var firstFrameTime: CMTime?
    private var sessionStateTask: Task<Void, Never>?
    private var frameWatchdogTask: Task<Void, Never>?
    private let listenerTokens = ListenerTokenBag()
    private var streamGeneration: UInt = 0
    private var registrationMonitor: Task<Void, Never>?
    private var deviceMonitor: Task<Void, Never>?

    init() {
        registrationStatus = String(describing: wearables.registrationState)
        detectedGlasses = wearables.devices.count
        monitorCompatibility(devices: wearables.devices)
        registrationMonitor = Task { [weak self] in
            guard let self else { return }
            for await state in self.wearables.registrationStateStream() {
                self.registrationStatus = String(describing: state)
            }
        }
        activeDeviceMonitor = Task { [weak self] in
            guard let self else { return }
            for await activeId in self.deviceSelector.activeDeviceStream() {
                self.activeGlassesAvailable = activeId != nil
                if activeId == nil && self.detectedGlasses > 0 {
                    self.diagnostic = "Meta registra gafas, pero AutoDeviceSelector no encuentra un dispositivo activo elegible"
                }
            }
        }
        deviceMonitor = Task { [weak self] in
            guard let self else { return }
            for await devices in self.wearables.devicesStream() {
                self.detectedGlasses = devices.count
                self.monitorCompatibility(devices: devices)
            }
        }
    }

    // Igual que WearablesViewModel oficial de CameraAccess:
    // contar dispositivos no significa que sean compatibles o seleccionables.
    private func monitorCompatibility(devices: [DeviceIdentifier]) {
        let current = Set(devices)
        compatibilityTokens = compatibilityTokens.filter { current.contains($0.key) }
        deviceCompatibility = deviceCompatibility.filter { current.contains($0.key) }
        for id in devices {
            guard compatibilityTokens[id] == nil,
                  let device = wearables.deviceForIdentifier(id) else { continue }
            let compatibility = device.compatibility()
            deviceCompatibility[id] = compatibility
            let name = device.nameOrId()
            let token = device.addCompatibilityListener { [weak self] compatibility in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.deviceCompatibility[id] = compatibility
                    self.updateCompatibilitySummary()
                    self.trace("Compatibilidad \(name): \(compatibility)")
                }
            }
            compatibilityTokens[id] = token
        }
        updateCompatibilitySummary()
    }

    private func updateCompatibilitySummary() {
        firmwareUpdateRequired = deviceCompatibility.values.contains(.deviceUpdateRequired)
        if deviceCompatibility.isEmpty {
            deviceCompatibilitySummary = "Sin dispositivo compatible evaluado"
        } else {
            deviceCompatibilitySummary = deviceCompatibility.values.map { String(describing: $0) }.joined(separator: ", ")
        }
    }

    deinit {
        registrationMonitor?.cancel()
        deviceMonitor?.cancel()
        activeDeviceMonitor?.cancel()
    }

    // Salidas puras del motor Meta. Este tipo no conoce LiveKit ni AVAssetWriter.
    // El coordinador decide después qué hacer con el frame oficial recibido.
    // La prueba de CameraAccess debe quedarse en Meta, sin callbacks del coordinador.
    var standaloneCameraTest = false
    var onFrame: ((CMSampleBuffer) -> Void)?
    var onStreamingChanged: ((Bool) -> Void)?

    func registerGlasses() async {
        pipelineStage = "Registro · abriendo flujo oficial Meta"
        diagnostic = "Solicitando registro de las Ray-Ban"
        do {
            try await wearables.startRegistration()
            registrationStatus = String(describing: wearables.registrationState)
            diagnostic = "Registro Meta solicitado · estado SDK: \(registrationStatus) · autoriza en Meta y regresa"
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
            registrationStatus = String(describing: wearables.registrationState)
            detectedGlasses = wearables.devices.count
            diagnostic = "Retorno Meta procesado · registro SDK: \(registrationStatus) · gafas detectadas: \(detectedGlasses)"
            status = "Retorno de Meta recibido · comprobando registro"
        } catch {
            diagnostic = "Error procesando retorno Meta: \(error.localizedDescription)"
            status = "No se pudo completar el registro Ray-Ban"
        }
    }

    // CameraAccess usa HEVC y lo decodifica solo para la vista previa local.
    // No se entrega ningún frame a LiveKit desde esta ruta de imagen.
    private func decodeHEVCPreview(_ sample: CMSampleBuffer) -> UIImage? {
        guard CMSampleBufferGetDataBuffer(sample) != nil,
              let format = CMSampleBufferGetFormatDescription(sample) else { return nil }
        if let previous = hevcFormat, !CMFormatDescriptionEqual(previous, otherFormatDescription: format) {
            if let decoder = hevcDecoder { VTDecompressionSessionInvalidate(decoder) }
            hevcDecoder = nil
        }
        if hevcDecoder == nil {
            var decoder: VTDecompressionSession?
            let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA]
            let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                formatDescription: format, decoderSpecification: nil,
                imageBufferAttributes: attrs as CFDictionary,
                outputCallback: nil, decompressionSessionOut: &decoder)
            guard status == noErr, let decoder else { return nil }
            hevcDecoder = decoder
            hevcFormat = format
        }
        guard let decoder = hevcDecoder else { return nil }
        nonisolated(unsafe) var output: CVPixelBuffer?
        let result = VTDecompressionSessionDecodeFrame(decoder, sampleBuffer: sample,
            flags: [], infoFlagsOut: nil) { status, _, buffer, _, _ in
                if status == noErr { output = buffer }
            }
        guard result == noErr, let output else { return nil }
        let ciImage = CIImage(cvPixelBuffer: output)
        guard let cgImage = previewCIContext.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Etapa 1 CameraAccess: prepara una DeviceSession y espera confirmación
    /// de Meta. No publica LiveKit, no graba y no toca la cámara del iPhone.
    private func startDeviceSession(generation: UInt) async throws -> DeviceSession? {
        trace("Creando DeviceSession; elegible: \(activeGlassesAvailable); compatibilidad: \(deviceCompatibilitySummary)")
        pipelineStage = "1/5 · Creando DeviceSession Meta"
        diagnostic = "Iniciando sesión oficial CameraAccess…"
        guard !Task.isCancelled, streamGeneration == generation else { return nil }
        pipelineStage = "2/5 · Creando DeviceSession"
        let session = try wearables.createSession(deviceSelector: deviceSelector)
        deviceSession = session

        sessionErrorTokens.clear()
        session.errorPublisher.listen { [weak self] error in
            Task { @MainActor in
                guard let self, self.streamGeneration == generation else { return }
                self.lastSDKError = String(describing: error)
                self.trace("Error DeviceSession: \(error)")
                self.lastAttemptResult = "Falló DeviceSession: \(error)"
                self.diagnostic = "Error de DeviceSession Meta: \(error.localizedDescription)"
                self.status = self.diagnostic
            }
        }.store(in: sessionErrorTokens)
        let stateStream = session.stateStream()
        sdkSessionState = "Iniciando"
        diagnostic = "Iniciando sesión de gafas…"
        do {
            try session.start()
        } catch {
            // No dejar una DeviceSession fallida retenida como si estuviera activa.
            session.stop()
            if streamGeneration == generation {
                deviceSession = nil
            }
            trace("session.start() falló: \(error)")
            lastAttemptResult = "Falló inicio Meta: \(error)"
            throw error
        }

        // Limitar la espera: si Meta nunca confirma .started, detener
        // DeviceSession para desbloquear stateStream y mostrar diagnóstico.
        // El temporizador pertenece a esta generación y se cancela al salir.
        let startupTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self,
                  self.streamGeneration == generation else { return }
            self.trace("DeviceSession agotó espera de 30 s")
            self.lastAttemptResult = "Tiempo agotado esperando DeviceSession"
            self.diagnostic = "Meta no inició DeviceSession en 30 s · revisa conexión y autorización"
            self.status = "Tiempo de espera agotado al conectar Ray-Ban"
            session.stop()
        }
        defer { startupTimeout.cancel() }

        for await state in stateStream {
            guard !Task.isCancelled, streamGeneration == generation else {
                // Una nueva conexión puede invalidar este intento mientras
                // el SDK espera estados. Cerrar únicamente la sesión antigua.
                session.stop()
                if streamGeneration == generation {
                    deviceSession = nil
                }
                return nil
            }
            sdkSessionState = String(describing: state)
            trace("DeviceSession: \(state)")
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
        session.stop()
        if streamGeneration == generation {
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
            videoCodec: .hvc1,
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
        sdkStreamState = "Iniciando"
        diagnostic = "Cámara Meta asignada · esperando fotogramas"

        stream.videoFramePublisher.listen { [weak self] frame in
            let pixelBuffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer)
            let image = frame.makeUIImage()
            Task { @MainActor in
                guard let self, self.streamGeneration == generation else { return }
                let decodedImage = image ?? self.decodeHEVCPreview(frame.sampleBuffer)
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
                    self.diagnostic = "Meta envía frames, pero sin CVPixelBuffer listo · recibidos: \(self.frameCount) · sin imagen: \(self.framesWithoutImageBuffer)"
                }
                // La vista previa y el grabador deben basarse en la misma
                // muestra válida; una UIImage aislada no confirma que exista
                // un sampleBuffer listo para guardar.
                if (pixelBuffer != nil && CMSampleBufferDataIsReady(frame.sampleBuffer)) || decodedImage != nil {
                    // Algunos frames RAW traen CVPixelBuffer válido aunque
                    // makeUIImage() no genere una vista previa. Renderizar
                    // ese mismo buffer sin modificar la muestra del SDK.
                    let visibleImage: UIImage?
                    if let decodedImage {
                        visibleImage = decodedImage
                    } else if let pixelBuffer {
                        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                        if let cgImage = self.previewCIContext.createCGImage(ciImage, from: ciImage.extent) {
                            visibleImage = UIImage(cgImage: cgImage)
                            self.previewFallbackCount += 1
                        } else {
                            visibleImage = nil
                        }
                    } else {
                        visibleImage = nil
                    }
                    if let visibleImage {
                        self.previewImage = visibleImage
                        self.hasReceivedFrame = true
                        self.lastFrameReceivedAt = Date()
                        self.previewImageCount += 1
                        self.pipelineStage = "5/5 · Imagen visible recibida"
                        if self.previewImageCount == 1 {
                            self.trace("Primer fotograma visible recibido desde Ray-Ban")
                            self.lastAttemptResult = "Éxito: imagen real recibida de las gafas"
                        }
                    } else {
                        self.diagnostic = "Meta entrega CVPixelBuffer válido, pero falla la conversión a imagen · frames: \(self.framesWithImageBuffer)"
                    }
                    if !self.standaloneCameraTest { self.onFrame?(frame.sampleBuffer) }
                }
            }
        }.store(in: listenerTokens)

        stream.statePublisher.listen { [weak self] state in
            Task { @MainActor in
                guard let self, self.streamGeneration == generation else { return }
                self.sdkStreamState = String(describing: state)
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
                self.lastSDKError = String(describing: error)
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
            let startedAt = Date()
            var reportedMissingFirstFrame = false
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                guard let self, self.streamGeneration == generation else { return }
                // El primer bloqueo real puede ocurrir ANTES de recibir
                // cualquier frame. No confundir estado .streaming con video.
                if !self.hasReceivedFrame {
                    if !reportedMissingFirstFrame &&
                       Date().timeIntervalSince(startedAt) >= 15 {
                        reportedMissingFirstFrame = true
                        self.diagnostic = self.receivedFrameCount > 0
                            ? "Meta envió \(self.receivedFrameCount) frames, pero ninguno tiene imagen utilizable tras 15 s"
                            : "CameraStream abierto durante 15 s sin recibir fotogramas · comprobar autorización y gafas"
                        self.firstFrameTimeoutDiagnostic = self.diagnostic
                        self.pipelineStage = "4/5 · Esperando primer frame Meta"
                    }
                    continue
                }
                guard self.isStreaming, let last = self.lastFrameReceivedAt else { continue }
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
            // CameraAccess requests permission only after DeviceSession is started.
            pipelineStage = "3/5 · Verificando permiso de cámara Meta"
            if try await wearables.checkPermissionStatus(.camera) != .granted {
                diagnostic = "Meta solicita permiso de cámara; regresa a DIVISA SHOPPER después de autorizar"
                guard try await wearables.requestPermission(.camera) == .granted else {
                    status = "Permiso de cámara Meta no concedido"
                    return false
                }
            }
            guard !Task.isCancelled, streamGeneration == generation, session.state == .started else {
                diagnostic = "La sesión Meta ya no está iniciada después de solicitar permiso"
                return false
            }
            try startCameraStream(session: session, generation: generation)
            let recovered = await waitUntilFirstFrame(timeoutSeconds: 20)
            // Una conexión más reciente puede empezar durante esta espera.
            // Nunca cerrar su cámara desde el intento de recuperación antiguo.
            guard !Task.isCancelled, streamGeneration == generation else { return false }
            if !recovered {
                // No dejar activa una cámara sin frames mientras el
                // coordinador intenta reconstruir DeviceSession.
                stopCameraStream()
                pipelineStage = "Fallo de imagen Meta tras 20 s"
                diagnostic = "CameraStream reiniciado, pero Meta no entregó imagen válida en 20 s"
                status = "Ray-Ban sin imagen tras reiniciar cámara"
            }
            return recovered
        } catch {
            // Si otra conexión reemplazó este intento, su CameraStream y
            // sus diagnósticos pertenecen a la generación nueva.
            guard !Task.isCancelled, streamGeneration == generation else { return false }
            let failure = "Error reiniciando CameraStream: \(error.localizedDescription)"
            stopCameraStream()
            diagnostic = failure
            status = failure
            return false
        }
    }

    /// Orquestación de conveniencia: conserva un solo botón en DIVISA SHOPPER,
    /// pero internamente sesión y cámara son dos etapas independientes.
    func startRayBanPreview() async {
        // Cerrar la cámara anterior ANTES de capturar la generación nueva.
        // stopCameraStream() incrementa streamGeneration; capturarla antes
        // invalidaba inmediatamente el intento y bloqueaba DeviceSession.
        stopCameraStream()
        attemptNumber += 1
        attemptEvents = []
        lastAttemptResult = "Intento #\(attemptNumber) en curso"
        trace("Inicio de prueba independiente #\(attemptNumber)")
        let generation = streamGeneration
        hasReceivedFrame = false
        previewImage = nil
        sdkSessionState = "Sin iniciar"
        sdkStreamState = "Sin iniciar"
        lastSDKError = "Ninguno"
        frameCount = 0
        receivedFrameCount = 0
        framesWithImageBuffer = 0
        framesWithoutImageBuffer = 0
        previewImageCount = 0
        previewFallbackCount = 0
        firstFrameTimeoutDiagnostic = nil
        lastFrameReceivedAt = nil
        firstFrameTime = nil
        // Reutilizar el cierre oficial de cámara para notificar al
        // coordinador si el stream anterior estaba transmitiendo. Así
        // puede archivar el MOV antes de conectar una sesión distinta.
        // Si el coordinador ya está cambiando de fuente, su propia
        // protección de transición evita una recuperación duplicada.
        deviceSession?.stop()
        deviceSession = nil
        pipelineStage = "1/5 · Iniciando conexión Meta"
        diagnostic = "Cámara anterior cerrada · iniciando autorización y DeviceSession"
        status = "Conectando Ray-Ban…"

        do {
            guard let session = try await startDeviceSession(generation: generation) else {
                if lastAttemptResult.contains("en curso") { lastAttemptResult = "DeviceSession no inició" }
                trace("No se abrió CameraStream: DeviceSession no disponible")
                return
            }
            // Una segunda solicitud o un cierre puede invalidar esta operación
            // mientras el SDK espera autorización o conexión de las gafas.
            guard !Task.isCancelled, streamGeneration == generation else { return }
            // Igual que CameraAccess: permiso después de DeviceSession.started.
            pipelineStage = "3/5 · Permiso de cámara Meta"
            if try await wearables.checkPermissionStatus(.camera) != .granted {
                diagnostic = "Solicitando autorización de cámara en Meta AI"
                guard try await wearables.requestPermission(.camera) == .granted else {
                    status = "Permiso de cámara Meta no concedido"
                    return
                }
            }
            guard !Task.isCancelled, streamGeneration == generation,
                  session.state == .started else {
                diagnostic = "DeviceSession dejó de estar iniciada durante la autorización Meta"
                return
            }
            trace("DeviceSession iniciada; permiso confirmado; abriendo CameraStream")
            try startCameraStream(session: session, generation: generation)
            lastAttemptResult = "CameraStream solicitado; esperando imagen"
        } catch {
            // Un intento antiguo no debe reemplazar el diagnóstico de una
            // conexión más reciente ni el estado de una sesión ya cerrada.
            guard !Task.isCancelled, streamGeneration == generation else { return }
            let failure = "Error de inicio Meta: \(error.localizedDescription)"
            lastSDKError = String(describing: error)
            trace("Error de inicio: \(error)")
            lastAttemptResult = "Falló: \(error)"
            // Si addCamera/startCameraStream falla después de crear la
            // DeviceSession, liberar todo el intento incompleto. No dejar
            // una sesión parcialmente iniciada para la próxima conexión.
            stopRayBanPreview()
            pipelineStage = "Fallo al iniciar cámara Meta"
            diagnostic = failure
            status = failure
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
        // No borrar lastAttemptStage, lastAttemptResult ni attemptEvents.
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
