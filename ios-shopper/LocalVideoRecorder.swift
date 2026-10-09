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
    private var audioInput: AVAssetWriterInput?
    private let audioCapture = LocalAudioCapture()
    private var recordingWallClock: Date?

    func start() {
        guard !isRecording else { return }
        writer = nil
        input = nil
        audioInput = nil
        startTime = nil
        recordingWallClock = nil
        lastRecordingURL = nil
        recordingWallClock = Date()
        isRecording = true
        try? audioCapture.start { [weak self] buffer, _ in
            self?.appendAudio(buffer)
        }
    }


    /// Recibe fotogramas crudos de la cámara del iPhone (vía LiveKit VideoProcessor).
    func append(pixelBuffer: CVPixelBuffer, timeStampNs: Int64) {
        guard isRecording else { return }

        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else { return }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: timeStampNs, timescale: 1_000_000_000),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else { return }

        append(sampleBuffer)
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
                self.configureAudioInputIfNeeded(format: nil)
            } catch {
                return
            }
        }

        guard let input, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }


    private func configureAudioInputIfNeeded(format: AVAudioFormat?) {
        guard audioInput == nil, let writer else { return }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000
        ]
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        audio.expectsMediaDataInRealTime = true
        if writer.canAdd(audio) {
            writer.add(audio)
            audioInput = audio
        }
    }

    private func appendAudio(_ buffer: AVAudioPCMBuffer) {
        guard isRecording, let writer, writer.status == .writing else { return }
        configureAudioInputIfNeeded(format: buffer.format)
        guard let audioInput, audioInput.isReadyForMoreMediaData,
              let wallClock = recordingWallClock else { return }

        let pts = CMTime(seconds: Date().timeIntervalSince(wallClock), preferredTimescale: 44_100)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: CMTimeValue(buffer.frameLength), timescale: CMTimeScale(buffer.format.sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let asbd = buffer.format.streamDescription
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else { return }

        let audioBufferList = buffer.mutableAudioBufferList
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(buffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else { return }

        guard CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: audioBufferList
        ) == noErr else { return }

        audioInput.append(sampleBuffer)
    }

    func stop() async {
        guard isRecording else { return }
        isRecording = false
        audioCapture.stop()
        input?.markAsFinished()
        audioInput?.markAsFinished()
        if let writer {
            await writer.finishWriting()
        }
        writer = nil
        input = nil
        startTime = nil
    }
}
