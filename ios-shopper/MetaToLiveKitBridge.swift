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
        let track = LocalVideoTrack.createBufferTrack(name: "rayban-meta", source: .camera)
        self.capturer = track.capturer as? BufferCapturer
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
