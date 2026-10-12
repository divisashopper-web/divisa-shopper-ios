import Foundation
import CoreVideo
import LiveKit

/// Copia cada fotograma de la cámara del iPhone hacia la grabación local
/// y devuelve el mismo frame intacto para que LiveKit lo siga transmitiendo.
final class IPhoneRecordingVideoProcessor: NSObject, VideoProcessor, @unchecked Sendable {
    weak var recorder: LocalVideoRecorder?
    var source: CameraSource = .iPhoneBack

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
            let frameSource = source
            let timeStampNs = frame.timeStampNs
            Task { @MainActor [weak recorder] in
                recorder?.append(pixelBuffer: pixelBuffer, timeStampNs: timeStampNs, source: frameSource)
            }
        }
        return frame
    }
}
