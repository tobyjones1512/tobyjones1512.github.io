import AVFoundation
import Observation
import QuartzCore

/// Listens to the microphone and says which note is being played or sung. Used by the tuner and by Wait for Me.
@Observable final class PitchListener {
    /// The latest pitch in hertz (nil when nothing pitched is sounding), and how loud the input is (0...1).
    private(set) var hz: Double?
    private(set) var level = 0.0
    private(set) var running = false
    private(set) var failure: String?
    /// Called for every analysed stretch of sound: its pitch and the clock time it was heard at.
    @ObservationIgnored var onFrame: ((Double?, Double) -> Void)?
    @ObservationIgnored private var stopRequested = false
    /// Frames before this clock time are ignored, so the app doesn't listen to its own reference notes.
    @ObservationIgnored var mutedUntil = 0.0
    /// Made when listening starts and dropped when it stops, so nothing of the microphone is held (or torn down late) otherwise.
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var tapInstalled = false
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var test: Task<Void, Never>?

    /// The tuning of the A above middle C, from Settings.
    static var a4: Double { Pref.double("tunerA4", 440) }
    /// RMS below this is treated as silence. Settings > Listening > Microphone Sensitivity. (A tablet's own microphone is quiet.)
    static var gate: Float { Float(0.0004 + (1 - Pref.double("micSensitivity", 0.6)) * 0.02) }

    /// Whether the microphone may be used: asks the first time, and says how to turn it on when it was refused.
    static func allowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    /// `recordingTo`: also keep the sound, as a compressed file there.
    func start(recordingTo url: URL? = nil) async {
        guard !running else { return }
        stopRequested = false
        failure = nil
        #if DEBUG
        if let m = UserDefaults.standard.string(forKey: "fakepitch").flatMap(Double.init) { simulate(midi: m); return }
        #endif
        guard await Self.allowed() else {
            failure = String(localized: "Maestro Pro needs the microphone to hear you. Turn it on in the Settings app under Maestro Pro, or on a Mac in System Settings, Privacy and Security, Microphone.")
            return
        }
        guard !running, !stopRequested else { return }
        do {
            try await Task.detached(priority: .userInitiated) {
                let s = AVAudioSession.sharedInstance()
                try s.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
                try s.setActive(true)
            }.value
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CocoaError(.featureUnsupported) }
            let file = url.flatMap { try? AVAudioFile(forWriting: $0, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000]) }
            Self.install(on: input, format: format, gate: Self.gate, listener: self, file: file)
            tapInstalled = true
            self.engine = engine
            // A change of route or audio category stops the engine and takes the microphone with it: let go of it cleanly.
            changeObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.release() }
            }
            engine.prepare()
            try engine.start()
            running = true
        } catch {
            release()
            failure = String(localized: "The microphone couldn’t be started.")
        }
    }

    func stop() {
        stopRequested = true
        test?.cancel(); test = nil
        release()
    }

    /// Takes the tap off and drops the engine, safely whatever state it was left in.
    private func release() {
        if let o = changeObserver { NotificationCenter.default.removeObserver(o); changeObserver = nil }
        if let e = engine {
            if tapInstalled { e.inputNode.removeTap(onBus: 0) }
            if e.isRunning { e.stop() }
        }
        tapInstalled = false
        engine = nil
        running = false
        hz = nil; level = 0
    }

    /// Stops listening for a while (a reference note is sounding).
    func mute(for seconds: Double) { mutedUntil = CACurrentMediaTime() + seconds; hz = nil }

    fileprivate func receive(_ hz: Double?, level: Double, at time: Double) {
        if time < mutedUntil { self.hz = nil; self.level = 0; return }
        self.hz = hz; self.level = level
        onFrame?(hz, time)
    }

    /// The tap runs on the audio thread, so it is built outside the main actor.
    private nonisolated static func install(on node: AVAudioInputNode, format: AVAudioFormat, gate: Float, listener: PitchListener, file: AVAudioFile?) {
        let analyzer = PitchAnalyzer(rate: format.sampleRate, gate: gate)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak listener] buffer, _ in
            guard let ch = buffer.floatChannelData?[0] else { return }
            if let file { try? file.write(from: buffer) }
            let now = CACurrentMediaTime()
            let results = analyzer.process(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
            guard !results.isEmpty else { return }
            guard let listener else { return }
            Task { @MainActor in
                for r in results { listener.receive(r.hz, level: r.level, at: now - r.age) }
            }
        }
    }

    #if DEBUG
    /// Test hook (-fakepitch 69): pretends a steady note is being played, with a little wobble.
    private func simulate(midi: Double) {
        running = true
        test = Task { @MainActor in
            var i = 0.0
            while !Task.isCancelled {
                i += 1
                receive(Pitch.hz(midi + sin(i / 5) * 0.04, a4: Self.a4), level: 0.3, at: CACurrentMediaTime())
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
    #endif
}
