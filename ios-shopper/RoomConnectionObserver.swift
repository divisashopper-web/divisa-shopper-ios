import Foundation
import LiveKit

/// Traduce los eventos de red de LiveKit a estados simples para la interfaz.
/// LiveKit realiza sus intentos de reconexión; este observador evita tratar
/// una caída temporal como si el shopper hubiera terminado la sesión.
final class RoomConnectionObserver: NSObject, RoomDelegate, @unchecked Sendable {
    enum State {
        case connected
        case reconnecting
        case disconnected
    }

    private let onState: @Sendable (State) -> Void

    init(onState: @escaping @Sendable (State) -> Void) {
        self.onState = onState
    }

    func roomDidConnect(_ room: Room) {
        onState(.connected)
    }

    func roomIsReconnecting(_ room: Room) {
        onState(.reconnecting)
    }

    func roomDidReconnect(_ room: Room) {
        onState(.connected)
    }

    func room(_ room: Room, didStartReconnectWithMode reconnectMode: ReconnectMode) {
        onState(.reconnecting)
    }

    func room(_ room: Room, didCompleteReconnectWithMode reconnectMode: ReconnectMode) {
        onState(.connected)
    }

    func room(
        _ room: Room,
        didUpdateConnectionState connectionState: LiveKit.ConnectionState,
        from oldConnectionState: LiveKit.ConnectionState
    ) {
        switch connectionState {
        case .connected:
            onState(.connected)
        case .reconnecting:
            onState(.reconnecting)
        case .disconnected:
            onState(.disconnected)
        default:
            break
        }
    }
}
