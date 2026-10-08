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

    func selectCamera(_ source: CameraSource) {
        selectedCamera = source
        statusMessage = "Fuente: \(source.rawValue)"
        // El adaptador concreto cambia la pista de video sin abandonar la sala LiveKit.
    }

    func startSession() {
        connectionState = .connecting
        statusMessage = "Solicitando acceso a la sesión…"
        // Próximo paso: solicitar token y conectar Room de LiveKit.
    }

    func endSession() {
        connectionState = .idle
        isRecording = false
        clientVideoAvailable = false
        statusMessage = "Sesión finalizada"
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func toggleRecording() {
        isRecording.toggle()
    }
}
