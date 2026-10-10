import AVFoundation
import Foundation

/// Captura el micrófono activo del shopper para la pista local.
/// Si las Ray-Ban exponen su micrófono Bluetooth HFP, iOS puede usar esa ruta.
@MainActor
final class LocalAudioCapture {
    private let engine = AVAudioEngine()
    private var onBuffer: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    private var tapInstalled = false

    func start(onBuffer: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        stop()
        self.onBuffer = onBuffer

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .videoChat, options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)

        if let bluetooth = session.availableInputs?.first(where: { $0.portType == .bluetoothHFP }) {
            try? session.setPreferredInput(bluetooth)
        }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        // LiveKit already owns/configures the call audio session. Reusing the
        // same AVAudioEngine input tap can trigger an AVFAudio assertion and
        // terminate the app. Install it defensively and track its lifecycle.
        if !tapInstalled {
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
                Task { @MainActor in self?.onBuffer?(buffer, time) }
            }
            tapInstalled = true
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        onBuffer = nil
    }
}
