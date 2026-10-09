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
                    try await liveKit.useIPhoneCamera(source)
                    statusMessage = "Transmitiendo: \(source.rawValue)"
                case .rayBanMeta:
                    await liveKit.stopIPhoneCamera()
                    statusMessage = "Sala activa. Preparando Ray-Ban Meta…"
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
                    statusMessage = "Sesión conectada · preparando Ray-Ban Meta"
                }
            } catch {
                connectionState = .disconnected
                statusMessage = "No se pudo conectar: \(error.localizedDescription)"
            }
        }
    }

    func endSession() {
        Task {
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
