import AVFoundation
import CoreMedia
import Foundation

/// Grabación local V1 independiente de LiveKit.
/// Escribe los fotogramas que llegan al iPhone en un archivo local aunque la red se interrumpa.
@MainActor
final class LocalVideoRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var lastRecordingName: String?
    @Published private(set) var recordings: [URL] = []
    @Published private(set) var lastRecordingSegments: [URL] = []
    @Published private(set) var lastProtectedSegmentURL: URL?

    private var isFinalizingSegment = false
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var startTime: CMTime?
    private var audioInput: AVAssetWriterInput?
    private let audioCapture = LocalAudioCapture()
    private var recordingWallClock: Date?
    private var activeSegmentSource: CameraSource?
    private var segmentNumber = 0
    private var segmentFiles: [URL] = []
    private var sessionIdentifier = ""

    init() {
        refreshRecordings()
    }

    func start(source: CameraSource) {
        // finishWriting() suspende el MainActor: impedir que otra sesión
        // sobrescriba writer/segmentFiles mientras el MOV anterior se cierra.
        guard !isRecording, !isFinalizingSegment else { return }
        writer = nil
        input = nil
        audioInput = nil
        startTime = nil
        recordingWallClock = nil
        lastRecordingURL = nil
        lastRecordingName = nil
        recordingWallClock = Date()
        sessionIdentifier = UUID().uuidString.prefix(8).description
        segmentNumber = 0
        segmentFiles = []
        lastRecordingSegments = []
        lastProtectedSegmentURL = nil
        activeSegmentSource = source
        isRecording = true
        // V1 diagnostic/stability path: record video only.
        // LiveKit owns the active call audio session. Starting a second
        // microphone capture here was crashing the app on the physical iPhone.
        // Audio will be reintroduced only after video recording is proven stable.
    }


    /// Recibe fotogramas crudos de la cámara del iPhone (vía LiveKit VideoProcessor).
    func append(pixelBuffer: CVPixelBuffer, timeStampNs: Int64, source: CameraSource) {
        guard isRecording, !isFinalizingSegment, activeSegmentSource == source else { return }

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

        append(sampleBuffer, source: source)
    }

    /// Protege inmediatamente el material ya capturado cuando una cámara se interrumpe.
    /// La grabación lógica continúa activa; cuando vuelvan fotogramas de la misma
    /// fuente se abrirá automáticamente un segmento nuevo.
    @discardableResult
    func archiveCurrentSegmentForInterruption() async -> Bool {
        guard isRecording else { return false }
        // Una finalización anterior puede estar suspendida en finishWriting.
        // Esperar su resultado antes de interpretar writer == nil como éxito.
        let wasFinalizing = isFinalizingSegment
        guard writer != nil || wasFinalizing else { return true }
        let expectedSegmentURL = lastRecordingURL
        await finishCurrentSegment()
        lastRecordingSegments = segmentFiles
        lastProtectedSegmentURL = segmentFiles.last
        refreshRecordings()
        // Si ya estaba finalizando, otro solicitante pudo haber registrado
        // el archivo antes de que esta operación empezara a esperar.
        guard let expectedSegmentURL else { return false }
        return segmentFiles.contains(expectedSegmentURL)
    }

    /// Finaliza el archivo anterior antes de recibir fotogramas de otra cámara.
    /// LiveKit permanece conectado; solamente cambia el segmento local.
    func transitionRecording(to source: CameraSource) async {
        guard isRecording, activeSegmentSource != source else { return }
        await finishCurrentSegment()
        // stop() puede haberse ejecutado durante finishWriting(). No
        // reactivar una fuente después de finalizar la grabación lógica.
        guard isRecording else { return }
        activeSegmentSource = source
    }

    private var segmentFinalizationWaiters: [CheckedContinuation<Void, Never>] = []

    private func finishCurrentSegment() async {
        // Otra transición o stop() puede entrar mientras finishWriting()
        // está suspendido. Esperar el cierre real antes de informar éxito.
        if isFinalizingSegment {
            await withCheckedContinuation { continuation in
                segmentFinalizationWaiters.append(continuation)
            }
            return
        }
        isFinalizingSegment = true
        defer {
            isFinalizingSegment = false
            let waiters = segmentFinalizationWaiters
            segmentFinalizationWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        input?.markAsFinished()
        if let writer {
            await writer.finishWriting()
            if writer.status == .completed, let url = lastRecordingURL {
                segmentFiles.append(url)
            }
        }
        writer = nil
        input = nil
        audioInput = nil
        startTime = nil
    }

    func append(_ sampleBuffer: CMSampleBuffer, source: CameraSource) {
        guard isRecording, !isFinalizingSegment, activeSegmentSource == source, CMSampleBufferDataIsReady(sampleBuffer) else { return }

        if writer == nil {
            guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format)
            guard dimensions.width > 0, dimensions.height > 0 else { return }

            do {
                let recordingsDirectory = try recordingsDirectory()
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                segmentNumber += 1
                let fileName = "DIVISA_SHOPPER_\(formatter.string(from: Date()))_\(sessionIdentifier)_parte\(segmentNumber).mov"
                let url = recordingsDirectory.appendingPathComponent(fileName)

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
                // No iniciar un segmento MOV con un timestamp inválido.
                // Dejar que el siguiente frame válido intente abrirlo.
                guard pts.isValid, pts.isNumeric else {
                    writer.cancelWriting()
                    return
                }
                writer.startSession(atSourceTime: pts)
                self.writer = writer
                self.input = input
                self.startTime = pts
                self.lastRecordingURL = url
                self.lastRecordingName = url.lastPathComponent
                // La ruta V1 graba solo video. No añadir entradas de audio
                // después de startWriting(): AVAssetWriter requiere que
                // todas las entradas se configuren antes de comenzar.
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


    private func recordingsDirectory() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("DIVISA SHOPPER", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        return directory
    }


    func refreshRecordings() {
        do {
            let directory = try recordingsDirectory()
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            recordings = urls
                .filter { $0.pathExtension.lowercased() == "mov" }
                .sorted { lhs, rhs in
                    let leftDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let rightDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return leftDate > rightDate
                }
        } catch {
            recordings = []
        }
    }

    func deleteRecording(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
        if lastRecordingURL == url {
            lastRecordingURL = nil
            lastRecordingName = nil
        }
        refreshRecordings()
    }

    func stop() async {
        guard isRecording else { return }
        isRecording = false
        // No independent microphone capture while LiveKit owns call audio.
        await finishCurrentSegment()
        activeSegmentSource = nil
        lastRecordingSegments = segmentFiles
        recordingWallClock = nil
        refreshRecordings()
    }
}

