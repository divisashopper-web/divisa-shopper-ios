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
            try session.start()
            for await state in session.stateStream() {
                if state == .started { break }
            }

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
                        if let image {
                            self?.previewImage = image
                            self?.hasReceivedFrame = true
                            self?.diagnostic = "Primer fotograma recibido"
                            self?.onPreviewImage?(image)
                        }
                        if let pixelBuffer { self?.onPixelBuffer?(pixelBuffer) }
                        self?.onVideoSampleBuffer?(frame.sampleBuffer)
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
        camera?.stop()
        deviceSession?.stop()
        stream = nil
        camera = nil
        deviceSession = nil
        previewImage = nil
        isStreaming = false
        hasReceivedFrame = false
        status = "Ray-Ban sin conectar"
        diagnostic = "Cámara detenida"
    }
}
