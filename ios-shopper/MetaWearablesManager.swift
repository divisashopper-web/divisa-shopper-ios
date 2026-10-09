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

    private let wearables = Wearables.shared
    private var deviceSession: DeviceSession?
    private var camera: Camera?
    private var stream: MWDATCamera.Stream?
    private let listenerTokens = ListenerTokenBag()

    /// Fotogramas crudos para LiveKit; la vista previa sigue siendo independiente.
    var onPixelBuffer: ((CVPixelBuffer) -> Void)?
    var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)?
    var onStreamingChanged: ((Bool) -> Void)?

    func registerGlasses() async {
        do {
            try await wearables.startRegistration()
        } catch {
            status = "No se pudo iniciar el registro: \(error.localizedDescription)"
        }
    }

    func startRayBanPreview() async {
        do {
            if try await wearables.checkPermissionStatus(.camera) != .granted {
                let permission = try await wearables.requestPermission(.camera)
                guard permission == .granted else {
                    status = "Permiso de cámara Ray-Ban no concedido"
                    return
                }
            }

            let selector = AutoDeviceSelector(wearables: wearables)
            let session = try wearables.createSession(deviceSelector: selector)
            self.deviceSession = session

            try session.start()
            for await state in session.stateStream() {
                if state == .started { break }
            }

            let config = StreamConfiguration(
                videoCodec: .raw,
                resolution: .medium,
                frameRate: 24
            )

            guard let camera = try session.addCamera(config: config) else {
                status = "Las gafas están conectadas, pero la cámara no está disponible"
                return
            }

            self.camera = camera
            let stream = camera.stream
            self.stream = stream

            stream.videoFramePublisher.listen { [weak self] frame in
                    let image = frame.makeUIImage()
                    let pixelBuffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer)
                    Task { @MainActor in
                        if let image { self?.previewImage = image }
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

            stream.start()
        } catch {
            status = "Error Ray-Ban: \(error.localizedDescription)"
        }
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
        status = "Ray-Ban sin conectar"
    }
}
