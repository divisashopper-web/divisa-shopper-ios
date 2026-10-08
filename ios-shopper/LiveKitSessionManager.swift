import Foundation
import LiveKit

@MainActor
final class LiveKitSessionManager: ObservableObject {
    @Published private(set) var roomStateText = "Sin sesión"
    @Published private(set) var isConnected = false

    let room = Room()
    private let tokenService = TokenService()

    func connect(roomName: String, identity: String, displayName: String) async throws {
        roomStateText = "Solicitando acceso"
        let credentials = try await tokenService.token(room: roomName, identity: identity, name: displayName)
        roomStateText = "Conectando"
        try await room.connect(url: credentials.url, token: credentials.token)
        isConnected = true
        roomStateText = "Sesión conectada"
        try await room.localParticipant.setMicrophone(enabled: true)
    }

    func setMicrophone(enabled: Bool) async throws {
        try await room.localParticipant.setMicrophone(enabled: enabled)
    }

    func disconnect() async {
        await room.disconnect()
        isConnected = false
        roomStateText = "Sin sesión"
    }
}
