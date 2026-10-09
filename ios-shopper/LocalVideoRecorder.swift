import AVFoundation
import CoreMedia
import Foundation

/// Grabación local V1 independiente de LiveKit.
/// Escribe los fotogramas que llegan al iPhone en un archivo local aunque la red se interrumpa.
@MainActor
final class LocalVideoRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var lastRecordingURL: URL?

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var startTime: CMTime?

    func start() {
        guard !isRecording else { return }
        writer = nil
        input = nil
        startTime = nil
        lastRecordingURL = nil
        isRecording = true
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        if writer == nil {
            guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format)
            guard dimensions.width > 0, dimensions.height > 0 else { return }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("DIVISA_SHOPPER_\(UUID().uuidString).mov")

            do {
                let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
                let settings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: Int(dimensions.width),
                    AVVideoHeightKey: Int(dimensions.height)
                ]
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                input.expectsMediaDataInRealTime = true
                guard writer.canAdd(input) else { return }
                writer.add(input)
                guard writer.startWriting() else { return }

                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                writer.startSession(atSourceTime: pts)
                self.writer = writer
                self.input = input
                self.startTime = pts
                self.lastRecordingURL = url
            } catch {
                return
            }
        }

        guard let input, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }

    func stop() async {
        guard isRecording else { return }
        isRecording = false
        input?.markAsFinished()
        if let writer {
            await writer.finishWriting()
        }
        writer = nil
        input = nil
        startTime = nil
    }
}
