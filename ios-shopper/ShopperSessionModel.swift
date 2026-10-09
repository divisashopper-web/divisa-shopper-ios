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

    init() {
        metaWearables.onPixelBuffer = { [weak self] buffer in
            self?.liveKit.pushRayBanFrame(buffer)
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
                    if liveKit.activeCameraSource == .rayBanMeta {
                        await liveKit.stopRayBanVideo()
                        metaWearables.stopRayBanPreview()
                        metaWearables.onPixelBuffer = { [weak self] buffer in
                            self?.liveKit.pushRayBanFrame(buffer)
                        }
                    }
                    try await liveKit.useIPhoneCamera(source)
                    statusMessage = "Transmitiendo: \(source.rawValue)"
                case .rayBanMeta:
                    await liveKit.stopIPhoneCamera()
                    try await liveKit.useRayBanVideo()
                    await metaWearables.startRayBanPreview()
                    statusMessage = metaWearables.status
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
                    try await liveKit.useIPhoneCamera(selectedCamera)
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
            metaWearables.stopRayBanPreview()
            await liveKit.disconnect()
            connectionState = .idle
            isRecording = false
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
        isRecording.toggle()
        statusMessage = isRecording
            ? "Grabación marcada como activa (motor local pendiente)"
            : "Grabación detenida"
    }
}
