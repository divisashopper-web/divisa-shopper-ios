import Foundation
import CoreVideo
import LiveKit

/// Copia cada fotograma de la cámara del iPhone hacia la grabación local
/// y devuelve el mismo frame intacto para que LiveKit lo siga transmitiendo.
final class IPhoneRecordingVideoProcessor: NSObject, VideoProcessor {
    weak var recorder: LocalVideoRecorder?

    init(recorder: LocalVideoRecorder) {
        self.recorder = recorder
    }

    func process(frame: VideoFrame) -> VideoFrame? {
        let pixelBuffer: CVPixelBuffer?
        if let cv = frame.buffer as? CVPixelVideoBuffer {
            pixelBuffer = cv.pixelBuffer
        } else {
            pixelBuffer = nil
        }

        if let pixelBuffer {
            Task { @MainActor [weak recorder] in
                recorder?.append(pixelBuffer: pixelBuffer, timeStampNs: frame.timeStampNs)
            }
        }
        return frame
    }
}
