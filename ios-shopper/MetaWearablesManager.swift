import Foundation
import MWDATCore
import MWDATCamera
import UIKit
import CoreMedia
import CoreVideo

@MainActor
final class MetaWearablesManager: ObservableObject {
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var status = "Ray-Ban sin conectar"
    @Published private(set) var isStreaming = false
    @Published private(set) var hasReceivedFrame = false
    @Published private(set) var diagnostic = "Cámara no iniciada"

    // No inicializar el SDK de Meta al abrir la app. Acceder solo cuando
    // el usuario solicita registrar o conectar las gafas.
    private var wearables: any WearablesInterface { Wearables.shared }
    private var deviceSession: DeviceSession?
    private var camera: Camera?
    private var stream: MWDATCamera.Stream?
    private var frameCount = 0
    private var firstFrameTime: CMTime?
    private var sessionStateTask: Task<Void, Never>?
    private let listenerTokens = ListenerTokenBag()

    /// Fotogramas crudos para LiveKit; la vista previa sigue siendo independiente.
    var onPixelBuffer: ((CVPixelBuffer) -> Void)?
    var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)?
    var onStreamingChanged: ((Bool) -> Void)?
    var onPreviewImage: ((UIImage) -> Void)?

    func registerGlasses() async {
        do {
            try await wearables.startRegistration()
        } catch {
            status = "No se pudo iniciar el registro: \(error.localizedDescription)"
        }
    }

    func startRayBanPreview() async {
        hasReceivedFrame = false
        previewImage = nil
        diagnostic = "Solicitando permiso Meta…"
        frameCount = 0
        firstFrameTime = nil
        sessionStateTask?.cancel()
        sessionStateTask = nil
        // Soltar cualquier sesión anterior antes de volver a reservar la cámara.
        camera?.stop()
        deviceSession?.stop()
        stream = nil
        camera = nil
        deviceSession = nil
        listenerTokens.clear()
        do {
            if try await wearables.checkPermissionStatus(.camera) != .granted {
                let permission = try await wearables.requestPermission(.camera)
                guard permission == .granted else {
                    status = "Permiso de cámara Ray-Ban no concedido"
                    return
                }
            }

            diagnostic = "Permiso concedido · creando sesión Meta"
            let selector = AutoDeviceSelector(wearables: wearables)
            let session = try wearables.createSession(deviceSelector: selector)
            self.deviceSession = session

            diagnostic = "Iniciando sesión de gafas…"
            // Meta recomienda suscribirse ANTES de start() para no perder la
            // transición inicial. Conservamos además el observador durante toda
            // la compra para distinguir paused de stopped.
            let stateStream = session.stateStream()
            try session.start()
            var sessionStarted = false
            for await state in stateStream {
                diagnostic = "Estado de sesión Meta: \(state)"
                if state == .started {
                    sessionStarted = true
                    break
                }
                if state == .stopped {
                    status = "Meta detuvo la sesión antes de activar la cámara"
                    return
                }
            }
            guard sessionStarted else {
                status = "Meta no pudo iniciar la sesión con las gafas"
                return
            }
            diagnostic = "Sesión Meta iniciada · abriendo cámara…"

            let config = StreamConfiguration(
                videoCodec: .raw,
                resolution: .low,
                frameRate: 24
            )

            guard let camera = try session.addCamera(config: config) else {
                status = "Las gafas están conectadas, pero la cámara no está disponible"
                return
            }

            diagnostic = "Cámara Meta asignada · esperando fotogramas"
            self.camera = camera
            let stream = camera.stream
            self.stream = stream

            stream.videoFramePublisher.listen { [weak self] frame in
                    let image = frame.makeUIImage()
                    let pixelBuffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer)
                    Task { @MainActor in
                        self?.frameCount += 1
                        if let image {
                            self?.previewImage = image
                            self?.hasReceivedFrame = true
                            self?.diagnostic = "Video Ray-Ban recibido · fotogramas: \(self?.frameCount ?? 0)"
                            self?.onPreviewImage?(image)
                        }
                        if let pixelBuffer { self?.onPixelBuffer?(pixelBuffer) }
                        // Re-crear el sample buffer con una línea de tiempo local que
                        // AVAssetWriter pueda guardar de forma fiable. Los timestamps
                        // nativos de las gafas no pertenecen necesariamente al reloj del iPhone.
                        if let self, let pixelBuffer {
                            let pts = CMTime(value: CMTimeValue(self.frameCount), timescale: 24)
                            var formatDescription: CMVideoFormatDescription?
                            if CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &formatDescription) == noErr,
                               let formatDescription {
                                var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 24), presentationTimeStamp: pts, decodeTimeStamp: .invalid)
                                var normalized: CMSampleBuffer?
                                if CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: formatDescription, sampleTiming: &timing, sampleBufferOut: &normalized) == noErr,
                                   let normalized {
                                    self.onVideoSampleBuffer?(normalized)
                                }
                            }
                        }
                    }
                }.store(in: listenerTokens)

            stream.statePublisher.listen { [weak self] state in
                    Task { @MainActor in
                        let streaming = state == .streaming
                        self?.isStreaming = streaming
                        self?.onStreamingChanged?(streaming)
                        self?.status = streaming
                            ? "Ray-Ban transmitiendo"
                            : "Ray-Ban: \(state)"
                    }
                }
            .store(in: listenerTokens)

            stream.errorPublisher.listen { [weak self] error in
                Task { @MainActor in
                    self?.diagnostic = "Error SDK Meta: \(error.localizedDescription)"
                    self?.status = self?.diagnostic ?? "Error SDK Meta"
                }
            }.store(in: listenerTokens)

            diagnostic = "Solicitando inicio de video Meta (baja resolución)"
            stream.start()

            sessionStateTask?.cancel()
            sessionStateTask = Task { [weak self, weak session] in
                guard let session else { return }
                for await state in session.stateStream() {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard let self else { return }
                        switch state {
                        case .paused:
                            self.diagnostic = "Sesión Meta pausada · esperando reanudación"
                        case .started:
                            if self.hasReceivedFrame {
                                self.diagnostic = "Sesión Meta activa · video disponible"
                            }
                        case .stopped:
                            self.diagnostic = "Sesión Meta detenida · se requiere nueva sesión"
                            self.isStreaming = false
                            self.onStreamingChanged?(false)
                        default:
                            break
                        }
                    }
                }
            }
        } catch {
            diagnostic = "Error de inicio Meta: \(error.localizedDescription)"
            status = diagnostic
        }
    }

    /// No considerar Ray-Ban lista solo porque el SDK diga "streaming".
    /// Para DIVISA SHOPPER la cámara está lista únicamente después de recibir
    /// al menos un fotograma real.
    func waitUntilFirstFrame(timeoutSeconds: Double = 12) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if hasReceivedFrame { return true }
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return false }
        }
        return hasReceivedFrame
    }

    /// Espera el estado real del stream antes de decidir si usar el respaldo.
    /// Evita interpretar como fallo el tiempo normal de conexión de las gafas.
    func waitUntilStreaming(timeoutSeconds: Double = 12) async -> Bool {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if isStreaming { return true }
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return false }
        }
        return isStreaming
    }

    func stopRayBanPreview() {
        listenerTokens.clear()
        sessionStateTask?.cancel()
        sessionStateTask = nil
        camera?.stop()
        deviceSession?.stop()
        stream = nil
        camera = nil
        deviceSession = nil
        previewImage = nil
        isStreaming = false
        hasReceivedFrame = false
        frameCount = 0
        firstFrameTime = nil
        status = "Ray-Ban sin conectar"
        diagnostic = "Cámara detenida"
    }
}
