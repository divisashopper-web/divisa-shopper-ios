import Foundation
import MWDATCore
import MWDATCamera
import UIKit

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

            listenerTokens.add(
                stream.videoFramePublisher.listen { [weak self] frame in
                    guard let image = frame.makeUIImage() else { return }
                    Task { @MainActor in
                        self?.previewImage = image
                    }
                }
            )

            listenerTokens.add(
                stream.statePublisher.listen { [weak self] state in
                    Task { @MainActor in
                        self?.isStreaming = state == .streaming
                        self?.status = state == .streaming
                            ? "Ray-Ban transmitiendo"
                            : "Ray-Ban: \(state)"
                    }
                }
            )

            stream.start()
        } catch {
            status = "Error Ray-Ban: \(error.localizedDescription)"
        }
    }

    func stopRayBanPreview() {
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
