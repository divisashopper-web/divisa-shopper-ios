import Foundation
import AVFoundation
import LiveKit

@MainActor
final class LiveKitSessionManager: ObservableObject {
    @Published private(set) var roomStateText = "Sin sesión"
    @Published private(set) var isConnected = false
    @Published private(set) var activeCameraSource: CameraSource?

    let room = Room()
    private let tokenService = TokenService()
    private var localCameraTrack: LocalVideoTrack?
    private var localCameraPublication: LocalTrackPublication?
    private var iPhoneRecordingProcessor: IPhoneRecordingVideoProcessor?
    private let metaBridge = MetaToLiveKitBridge()
    private var metaPublication: LocalTrackPublication?
    private lazy var roomObserver = RoomConnectionObserver { [weak self] state in
        Task { @MainActor in self?.applyRoomState(state) }
    }

    init() {
        room.add(delegate: roomObserver)
    }

    private func applyRoomState(_ state: RoomConnectionObserver.State) {
        switch state {
        case .connected:
            isConnected = true
            roomStateText = "Sesión conectada"
        case .reconnecting:
            roomStateText = "Reconectando…"
        case .disconnected:
            isConnected = false
            roomStateText = "Sin conexión"
        }
    }

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
    func useIPhoneCamera(_ source: CameraSource, recorder: LocalVideoRecorder? = nil) async throws {
        guard source == .iPhoneBack || source == .iPhoneFront else { return }

        if localCameraTrack == nil {
            let position: AVCaptureDevice.Position = source == .iPhoneFront ? .front : .back
            let options = CameraCaptureOptions(position: position)
            let processor = recorder.map { IPhoneRecordingVideoProcessor(recorder: $0) }
            iPhoneRecordingProcessor = processor
            let track = await LocalVideoTrack.createCameraTrack(
                name: "iphone-camera",
                options: options,
                processor: processor
            )
            let publication = try await room.localParticipant.publish(videoTrack: track)
            localCameraTrack = track
            localCameraPublication = publication
            activeCameraSource = source
            return
        }

        guard let capturer = localCameraTrack?.capturer as? CameraCapturer else { return }
        let desiredPosition: AVCaptureDevice.Position = source == .iPhoneFront ? .front : .back
        _ = try await capturer.set(cameraPosition: desiredPosition)
        activeCameraSource = source
    }

    /// Publica los fotogramas de las gafas en la misma sala privada.
    func useRayBanVideo() async throws {
        if metaPublication != nil { return }
        let track = metaBridge.prepareTrack()
        do {
            metaPublication = try await room.localParticipant.publish(videoTrack: track)
            activeCameraSource = .rayBanMeta
        } catch {
            metaBridge.reset()
            throw error
        }
    }

    func pushRayBanFrame(_ pixelBuffer: CVPixelBuffer) {
        guard metaPublication != nil else { return }
        metaBridge.push(pixelBuffer: pixelBuffer)
    }

    func stopRayBanVideo() async {
        if let publication = metaPublication {
            try? await room.localParticipant.unpublish(publication: publication)
        }
        metaPublication = nil
        metaBridge.reset()
        if activeCameraSource == .rayBanMeta { activeCameraSource = nil }
    }

    /// Apaga la captura del iPhone pero mantiene viva la sala LiveKit.
    /// Esto permite pasar a Ray-Ban Meta sin tumbar audio ni sesión.
    func stopIPhoneCamera() async {
        guard localCameraTrack != nil, let publication = localCameraPublication else { return }
        do {
            try await room.localParticipant.unpublish(publication: publication)
        } catch {
            // La desconexión de una fuente no debe tumbar la sesión.
        }
        localCameraTrack = nil
        localCameraPublication = nil
        iPhoneRecordingProcessor = nil
        activeCameraSource = nil
    }

    func disconnect() async {
        await room.disconnect()
        metaPublication = nil
        metaBridge.reset()
        localCameraTrack = nil
        localCameraPublication = nil
        iPhoneRecordingProcessor = nil
        activeCameraSource = nil
        isConnected = false
        roomStateText = "Sin sesión"
    }
}
