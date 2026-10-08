import Foundation
import CoreVideo
import LiveKit

/// Mantiene separada la fuente Ray-Ban de la sala LiveKit.
/// La sesión puede continuar aunque las gafas se desconecten.
@MainActor
final class MetaToLiveKitBridge: ObservableObject {
    private(set) var capturer: BufferCapturer?
    private(set) var track: LocalVideoTrack?

    func prepareTrack() -> LocalVideoTrack {
        let capturer = BufferCapturer()
        self.capturer = capturer
        let track = LocalVideoTrack.createTrack(name: "rayban-meta", capturer: capturer)
        self.track = track
        return track
    }

    func push(pixelBuffer: CVPixelBuffer) {
        capturer?.capture(pixelBuffer)
    }

    func reset() {
        capturer = nil
        track = nil
    }
}
