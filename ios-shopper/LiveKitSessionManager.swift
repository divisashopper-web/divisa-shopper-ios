import Foundation
import LiveKit

@MainActor
final class LiveKitSessionManager: ObservableObject {
    @Published private(set) var roomStateText = "Sin sesión"
    @Published private(set) var isConnected = false
    @Published private(set) var activeCameraSource: CameraSource?

    let room = Room()
    private let tokenService = TokenService()
    private var localCameraTrack: LocalVideoTrack?

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

    /// Publica una cámara del iPhone sin abandonar la sala.
    /// Al cambiar frontal/trasera, LiveKit reemplaza la captura manteniendo la llamada.
    func useIPhoneCamera(_ source: CameraSource) async throws {
        guard source == .iPhoneBack || source == .iPhoneFront else { return }

        if localCameraTrack == nil {
            let position: CameraPosition = source == .iPhoneFront ? .front : .back
            let options = CameraCaptureOptions(position: position)
            let track = LocalVideoTrack.createCameraTrack(
                name: "iphone-camera",
                options: options
            )
            try await room.localParticipant.publish(videoTrack: track)
            localCameraTrack = track
            activeCameraSource = source
            return
        }

        guard let capturer = localCameraTrack?.capturer as? CameraCapturer else { return }
        let desiredPosition: CameraPosition = source == .iPhoneFront ? .front : .back
        try await capturer.setCameraPosition(position: desiredPosition)
        activeCameraSource = source
    }

    /// Apaga la captura del iPhone pero mantiene viva la sala LiveKit.
    /// Esto permite pasar a Ray-Ban Meta sin tumbar audio ni sesión.
    func stopIPhoneCamera() async {
        guard let track = localCameraTrack else { return }
        do {
            try await room.localParticipant.unpublish(publication: track)
        } catch {
            // La desconexión de una fuente no debe tumbar la sesión.
        }
        localCameraTrack = nil
        activeCameraSource = nil
    }

    func disconnect() async {
        await room.disconnect()
        localCameraTrack = nil
        activeCameraSource = nil
        isConnected = false
        roomStateText = "Sin sesión"
    }
}
