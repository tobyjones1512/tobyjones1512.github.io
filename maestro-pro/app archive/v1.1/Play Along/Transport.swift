import Accelerate
import AVFoundation
import Observation
import QuartzCore

/// The clock. With a backing track the audio file is the master; without one, the display link is.
/// A sound source the transport starts, stops and keeps in time but can't play itself (Apple Music).
protocol ExternalTrack: AnyObject {
    var duration: Double { get }
    var isPlaying: Bool { get }
    var currentTime: Double { get }
    var rate: Float { get set }
    var enabled: Bool { get set }
    func play(from seconds: Double)
    func pause()
}

@Observable final class Transport {
    private(set) var beat: Double = 0
    private(set) var isPlaying = false
    /// Counts down the last bar before bar 1: the count-in, or the end of the intro (4, 3, 2, 1, then nil).
    private(set) var countIn: Int?

    var tempo: Double = 100 { didSet { if isPlaying && !followingTrack { reanchor() }; if !remote, !lyricsClock, tempo != oldValue { together?.send(.tempo(tempo)) } } }
    /// A lyrics screen: the clock is in seconds (60 BPM), so Play Together lines up by time in the song, not by bar.
    var lyricsClock = false
    var speed: Double = 1 { didSet { external?.rate = Float(speed); player?.rate = Float(speed); for e in extras.values { e.player.rate = Float(speed) }; if isPlaying && !followingTrack { reanchor() }; if !remote, speed != oldValue { together?.send(.speed(speed)) } } }
    /// Track sync, in seconds. Positive: the first bar (the intro's, if there is one) sits this far into the
    /// recording, skipping silence. Negative: the recording starts this long after the first bar.
    var offset: Double = 0 { didSet { if isPlaying, player != nil { startTrack(at: beat) } } }
    /// The first backing track is heard (the others have their own switches).
    var trackEnabled = true { didSet { applyTrackLevels() } }
    /// All the backing tracks are silenced for now (while recording), without changing their switches.
    var tracksMuted = false { didSet { applyTrackLevels() } }
    /// Any backing track at all, the first or another.
    var hasAnyTrack: Bool { hasTrack || !extras.isEmpty || external != nil }
    /// Keyframed speed, pitch and level for the backing track (the editor's lanes).
    var automation = TrackEdit() { didSet { player?.edit = automation.isEmpty ? nil : automation } }
    /// Where the backing track is, in seconds into the recording (nil with no track).
    var trackTime: Double? {
        guard let player else { return nil }
        // Reading the beat is what makes a view showing this redraw with the clock; the track's own time can't be observed.
        let b = beat
        return followingTrack && player.isPlaying ? player.currentTime : offset + trackBeats(b) * 60 / tempo
    }
    func trackTime(forBeat b: Double) -> Double { offset + trackBeats(b) * 60 / tempo }
    /// Moves the score to where the recording's `t` falls.
    func seek(toTrackTime t: Double) { seek(to: (t - offset) * tempo / 60 + start) }
    var trackLength: Double? { player?.duration }
    /// Key change applied to the backing track, in semitones.
    var trackSemitones = 0 { didSet { player?.semitones = trackSemitones; for e in extras.values { e.player.semitones = trackSemitones } } }
    var metronome = false
    var countInEnabled = true
    /// Empty bars before bar 1 (an intro to wait through). They run on negative beats.
    var leadInBars = 0 { didSet { if !isPlaying, beat <= 0 { beat = start } } }

    var timeline = Timeline() { didSet { playable = timeline.notes.filter { $0.pitch != nil }.sorted { $0.sounds < $1.sounds }; cursor = playableIndex(beat) } }
    /// The instrument that plays the score (Off: only the backing track and metronome sound).
    var instrument = Instrument(rawValue: UserDefaults.standard.string(forKey: "instrument") ?? "") ?? .off {
        didSet {
            UserDefaults.standard.set(instrument.rawValue, forKey: "instrument")
            synth.stop()
            cursor = playableIndex(beat)
        }
    }
    /// An instrument for particular staves, in place of the main one (nil, or missing, = the main instrument).
    var staffInstruments: [Instrument?] = []
    func instrument(forStaff s: Int) -> Instrument { (s < staffInstruments.count ? staffInstruments[s] : nil) ?? instrument }

    /// Semitones the score is written above where it sounds (the player's instrument key); removed before playing.
    var soundingShift = 0
    var instrumentVolume = 0.8 { didSet { applyInstrumentLevel() } }
    /// This score's own level for the built-in instrument and for the backing track, in decibels (0 = unchanged).
    var instrumentGainDB = 0.0 { didSet { applyInstrumentLevel() } }
    var trackGainDB = 0.0 { didSet { player?.gainDB = Float(trackGainDB) } }
    /// The equaliser every backing track plays through (nil: straight through).
    var trackEQ: TrackEQ? { didSet { player?.eq = trackEQ; for e in extras.values { e.player.eq = trackEQ } } }
    private func applyInstrumentLevel() { synth.volume = silenceInstrument ? 0 : Float(instrumentVolume * pow(10, instrumentGainDB / 20)) }
    /// The instrument is muted (not changed) while the player is being recorded, so it isn't picked up by the microphone.
    var silenceInstrument = false { didSet { applyInstrumentLevel() } }
    /// The microphone is in use, so playback has to leave the audio session able to record.
    @ObservationIgnored var wantsInput = false
    /// While a recording is being reviewed: which notes to light green and red (nil otherwise).
    var review: ReviewLit?
    /// Notes a written review is pointing at (lit blue).
    var focus: Set<Int> = []
    private(set) var hasTrack = false
    /// The file the first backing track is playing from (the plain recording, or the copy with the singer cut down).
    private(set) var trackURL: URL?
    /// Length of the backing track in seconds.
    var trackDuration: Double? { player?.duration }
    private var player: TrackPlayer?
    /// The other backing tracks. The first one is the clock; these follow it.
    private final class Extra { let player: TrackPlayer; let url: URL; var offset: Double; var enabled: Bool; init(_ p: TrackPlayer, _ u: URL, _ o: Double, _ e: Bool) { player = p; url = u; offset = o; enabled = e } }
    @ObservationIgnored private var extras: [UUID: Extra] = [:]
    /// A song from Apple Music that plays along, started and kept in time with the clock.
    @ObservationIgnored private(set) var external: ExternalTrack?
    @ObservationIgnored private(set) var externalID: String?
    @ObservationIgnored private var externalOffset = 0.0
    @ObservationIgnored private var externalCheck = 0.0
    var externalDuration: Double? { external?.duration }

    func setExternal(_ track: ExternalTrack?, id: String?, offset: Double) {
        if external !== track { external?.pause() }
        external = track; externalID = id; externalOffset = offset
        track?.rate = Float(speed)
        track?.enabled = !tracksMuted && (track?.enabled ?? true)
        if isPlaying, track != nil { startTrack(at: beat) }
    }

    func setExternalEnabled(_ on: Bool) { external?.enabled = on && !tracksMuted }
    func setExternalOffset(_ o: Double) { externalOffset = o }

    struct ExtraSpec { var id: UUID, url: URL, offset: Double, enabled: Bool, gainDB: Double }

    /// Sets which other backing tracks there are (new ones are loaded, missing ones dropped, the rest just updated).
    func setExtras(_ specs: [ExtraSpec]) {
        let was = isPlaying
        for id in extras.keys where !specs.contains(where: { $0.id == id }) { extras[id]?.player.pause(); extras[id] = nil }
        var added = false
        for s in specs {
            if let e = extras[s.id], e.url == s.url {
                e.offset = s.offset; e.enabled = s.enabled; e.player.gainDB = Float(s.gainDB)
            } else if let p = TrackPlayer(url: s.url) {
                extras[s.id]?.player.pause()
                p.rate = Float(speed); p.semitones = trackSemitones; p.gainDB = Float(s.gainDB); p.eq = trackEQ
                extras[s.id] = Extra(p, s.url, s.offset, s.enabled)
                added = true
            }
        }
        applyTrackLevels()
        if was, added { startTrack(at: beat) }
    }

    private func applyTrackLevels() {
        player?.enabled = trackEnabled && !tracksMuted
        if tracksMuted { external?.enabled = false }
        for e in extras.values { e.player.enabled = e.enabled && !tracksMuted }
    }
    /// False once the track has run out (or before it starts), so a short track never cuts the score off.
    @ObservationIgnored private var followingTrack = false
    /// The other device when playing together: commands go to it, and its commands come back through `apply`.
    @ObservationIgnored weak var together: Together?
    @ObservationIgnored private var remote = false
    @ObservationIgnored private var startAt = 0.0   // clock time a scheduled start begins; nothing sounds before it
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private let synth = Synth()
    @ObservationIgnored private var playable: [NoteEvent] = []
    @ObservationIgnored private var cursor = 0   // next note in `playable` to sound
    @ObservationIgnored private var anchor = (time: 0.0, beat: 0.0)
    @ObservationIgnored private var lastClick = Int.min
    @ObservationIgnored private let clickHi = Transport.click(freq: 1760)
    @ObservationIgnored private let clickLo = Transport.click(freq: 1175)

    init() {
        // Starting points from Settings; each score can still change them.
        metronome = Pref.bool("defaultMetronome", false)
        countInEnabled = Pref.bool("defaultCountIn", true)
        speed = Pref.double("defaultSpeed", 1)
        instrumentVolume = Pref.double("defaultVolume", 0.8)
    }

    var seconds: Double { beat * 60 / tempo }
    var length: Double { timeline.length }
    /// Length of a lead-in bar: the first full bar, so a pickup doesn't shorten the intro.
    var leadBar: Double { timeline.measures.count > 1 ? timeline.measures[1].duration : timeline.measures.first?.duration ?? 4 }
    /// Where playback begins: the first lead-in bar, or bar 1.
    var start: Double { -Double(leadInBars) * leadBar }

    func setTrack(_ url: URL?) {
        pause()
        player = url.flatMap { TrackPlayer(url: $0) }
        trackURL = url
        player?.rate = Float(speed)
        player?.gainDB = Float(trackGainDB)
        player?.eq = trackEQ
        player?.semitones = trackSemitones
        player?.edit = automation.isEmpty ? nil : automation
        applyTrackLevels()
        hasTrack = player != nil
    }

    func toggle() { isPlaying ? pause() : play() }

    /// Switches the audio session on away from the main thread, before any engine starts: an engine starting with the
    /// session off switches it on itself, on the main thread, and the screen stalls.
    static func activateSession() async {
        await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback && session.category != .playAndRecord { try? session.setCategory(.playback, mode: .default) }
            try? session.setActive(true)
        }.value
    }

    /// Sounds one note on the score's instrument (the piano if it is off), without moving the clock.
    func preview(_ midi: Int, seconds: Double) {
        Task.detached(priority: .userInitiated) { try? AVAudioSession.sharedInstance().setActive(true) }
        synth.play(midi, seconds: seconds, as: instrument == .off ? .piano : instrument)
    }

    /// A section of the score to go round and round, in beats (nil: play on to the end).
    var loop: Range<Double>?

    private func playableIndex(_ b: Double) -> Int {
        playable.firstIndex { $0.sounds >= b - 0.001 } ?? playable.count
    }

    /// Sounds the notes the clock has just passed. A note long overdue (after a stall) is skipped.
    private func playNotes() {
        while cursor < playable.count, playable[cursor].sounds <= beat {
            let n = playable[cursor]
            cursor += 1
            if beat - n.sounds < 0.5 { synth.play(n.pitch! - soundingShift, seconds: n.duration * 60 / (tempo * speed), as: instrument(forStaff: n.staff), velocity: Float(n.velocity)) }
        }
    }

    func play() {
        guard !isPlaying, length > 0 else { return }
        // Free only reads the music.
        guard Store.shared.allows(.performer) else { return Store.shared.present(.performer, "Playback") }
        if beat >= length - 0.01 { beat = start }
        var from = beat
        if player == nil, countInEnabled, beat >= 0 {   // the intro bars already count you in
            from -= (timeline.measureIndex(at: beat).map { timeline.measures[$0].duration } ?? 4).rounded()
        }
        if let together, together.connected {
            // Start both devices at the same moment, a second ahead so the message arrives first.
            let at = CACurrentMediaTime() + 1
            together.send(.play(bar: barPosition(from), sec: songTime(from), at: at, tempo: tempo, speed: speed))
            begin(from: from, at: at)
        } else {
            begin(from: from, at: nil)
        }
    }

    /// Starts the clock at a beat, now or at a given clock time.
    private func begin(from b: Double, at when: Double?) {
        guard length > 0 else { return }
        // Publish state before touching the audio session, which can trigger a synchronous UI pass.
        isPlaying = true
        #if DEBUG
        let simulatedInput = wantsInput && UserDefaults.standard.string(forKey: "fakepitch") != nil   // the Simulator stalls opening a microphone it doesn't have
        #else
        let simulatedInput = false
        #endif
        if !simulatedInput {
            // With Apple Music playing along, the app's own sounds have to mix with it instead of cutting it off (and being cut off).
            let mix: AVAudioSession.CategoryOptions = external != nil ? [.mixWithOthers] : []
            let needsInput = wantsInput
            Task.detached(priority: .userInitiated) {
                if needsInput { try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers]) }
                else { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: mix) }
                try? AVAudioSession.sharedInstance().setActive(true)
            }
        }
        beat = b
        startAt = when ?? 0
        if player != nil || !extras.isEmpty || external != nil { startTrack(at: b, at: when) }
        lastClick = Int(beat.rounded(.up)) - 1
        cursor = playableIndex(beat)
        anchor = (when ?? CACurrentMediaTime(), beat)
        link?.invalidate()
        let link = CADisplayLink(target: self, selector: #selector(step))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        step()
    }

    func pause() {
        if !remote, isPlaying { together?.send(.pause(bar: barPosition(beat), sec: songTime(beat))) }
        halt()
    }

    private func halt() {
        synth.stop()
        player?.pause()
        for e in extras.values { e.player.pause() }
        external?.pause()
        link?.invalidate()
        link = nil
        isPlaying = false
        countIn = nil
        startAt = 0
        beat = max(start, beat)
    }

    /// How much slower than the opening tempo the score is playing here (2 = half speed), from its tempo marks.
    var tempoRatio: Double {
        guard timeline.warpedApplied, let i = timeline.measureIndex(at: beat), i < timeline.stretch.count else { return 1 }
        return timeline.stretch[i]
    }

    /// The score has tempo marks that change the pace.
    var hasTempoMarks: Bool { timeline.stretch.contains { abs($0 - 1) > 0.001 } }

    /// Where a beat is as a bar position (2.5 is halfway through bar 3, in the order bars are played), which is
    /// what two different parts of the same piece have in common. Before bar 1, in bars of the intro.
    func barPosition(_ b: Double) -> Double {
        guard b >= 0, let i = timeline.measureIndex(at: b) else { return b / leadBar }
        let m = timeline.measures[i]
        return Double(i) + (b - m.start) / m.duration
    }

    func beat(atBar p: Double) -> Double {
        let ms = timeline.measures
        guard p >= 0, !ms.isEmpty else { return p * leadBar }
        let i = min(Int(p), ms.count - 1)
        return ms[i].start + min(p - Double(i), 1) * ms[i].duration
    }

    /// Seconds into the song at a beat: the recording's own time when there is one, otherwise from bar 1.
    // ponytail: tempo marks aren't followed here, so a score without a recording and with tempo changes drifts from lyrics.
    func songTime(_ b: Double) -> Double { hasTrack ? offset + trackBeats(b) * 60 / tempo : b * 60 / tempo }
    func beat(atSong t: Double) -> Double { hasTrack ? (t - offset) * tempo / 60 + start : t * tempo / 60 }

    /// Where the other device's position lands here: by seconds if either side is lyrics, otherwise by bar.
    private func beat(atBar bar: Double, sec: Double) -> Double {
        lyricsClock || together?.remoteLyrics == true ? beat(atSong: sec) : beat(atBar: bar)
    }

    func seek(to b: Double) {
        let b = max(start, min(b, length))
        if let together, together.connected, !remote {
            // Moving while playing restarts both devices together half a second from now.
            let at = isPlaying ? CACurrentMediaTime() + 0.5 : 0
            together.send(.seek(bar: barPosition(b), sec: songTime(b), playing: isPlaying, at: at))
            if isPlaying { halt(); begin(from: b, at: at); return }
        }
        if isPlaying {
            countIn = nil
            beat = b
            if player != nil || !extras.isEmpty || external != nil { startTrack(at: b) }
            lastClick = Int(b.rounded(.up)) - 1
            reanchor()
        } else {
            beat = b
        }
        synth.stop()
        cursor = playableIndex(beat)
    }

    /// A command from the other device. Times in it are already on this device's clock.
    func apply(_ message: SyncMessage) {
        remote = true
        defer { remote = false }
        switch message {
        case .play(let bar, let sec, let at, let t, let s):
            if isPlaying { halt() }
            if !lyricsClock, together?.remoteLyrics != true { tempo = t }
            speed = s
            begin(from: beat(atBar: bar, sec: sec), at: at)
        case .pause(let bar, let sec):
            halt()
            beat = max(start, min(beat(atBar: bar, sec: sec), length))
            cursor = playableIndex(beat)
        case .seek(let bar, let sec, let playing, let at):
            halt()
            beat = max(start, min(beat(atBar: bar, sec: sec), length))
            cursor = playableIndex(beat)
            if playing { begin(from: beat, at: at) }
        case .tempo(let t): if !lyricsClock, together?.remoteLyrics != true { tempo = t }
        case .speed(let s): speed = s
        default: break
        }
    }

    /// The host says the music is at this beat now; snap back if this device has drifted.
    func resync(toBar bar: Double, sec: Double, age: Double) {
        let expected = beat(atBar: bar, sec: sec) + age * tempo / 60 * speed
        guard isPlaying, !followingTrack, CACurrentMediaTime() >= startAt, abs(expected - beat) * 60 / tempo > 0.012 else { return }
        anchor = (CACurrentMediaTime(), expected)
        beat = expected
        lastClick = Int(beat.rounded(.up)) - 1
        cursor = playableIndex(beat)
        synth.stop()
    }

    func skipBar(_ delta: Int) {
        let starts = (0..<leadInBars).map { start + Double($0) * leadBar } + timeline.measures.map(\.start)
        guard let i = starts.lastIndex(where: { $0 <= beat + 0.001 }) else { return seek(to: start) }
        // Going back from inside a bar lands on its downbeat first, like Logic.
        let target = delta < 0 && beat - starts[i] > 0.5 ? i : i + delta
        seek(to: starts[max(0, min(starts.count - 1, target))])
    }

    /// The first bar is wherever the track is right now, minus how far into the score we are.
    func markBarOneHere() -> Double? {
        guard let player, followingTrack, player.isPlaying else { return nil }
        return player.currentTime - trackBeats(beat) * 60 / tempo
    }

    /// The tempo that puts the nearest barline exactly here in the recording, measured from bar 1.
    /// Fixes a score that slowly drifts behind or ahead of the track.
    func tempoLockedHere() -> Double? {
        guard let player, followingTrack, player.isPlaying, let i = timeline.measureIndex(at: beat) else { return nil }
        let m = timeline.measures[i], elapsed = player.currentTime - offset
        let bar = trackBeats(beat - m.start < m.duration / 2 ? m.start : m.end)
        guard beat >= 0, bar > 0, elapsed > 0.5 else { return nil }
        return (bar * 60 / elapsed * 100).rounded() / 100
    }

    private func startTrack(at b: Double, at when: Double? = nil) {
        // A scheduled start begins the sound at the agreed time, less what the speaker adds.
        let at = when.map { $0 - AVAudioSession.sharedInstance().outputLatency + (together?.nudge ?? 0) }
        if let player {
            let t = offset + trackBeats(b) * 60 / tempo
            followingTrack = t >= 0 && t < player.duration
            if followingTrack { player.play(from: t, at: at) } else { player.pause() }
        }
        for e in extras.values {
            let t = e.offset + trackBeats(b) * 60 / tempo
            if t >= 0, t < e.player.duration { e.player.play(from: t, at: at) } else { e.player.pause() }
        }
        if let x = external {
            let t = externalOffset + trackBeats(b) * 60 / tempo
            if t >= 0, t < x.duration, x.enabled { x.play(from: t) } else { x.pause() }
        }
    }

    private func reanchor() { anchor = (CACurrentMediaTime(), beat) }

    /// Beats from the first bar, intro included: the track starts with the first intro bar.
    private func trackBeats(_ b: Double) -> Double { b - start }

    @objc private func step() {
        if CACurrentMediaTime() < startAt { return }   // a scheduled start isn't due yet
        if followingTrack, let player, player.isPlaying {
            if !automation.isEmpty { player.refresh(at: player.currentTime) }
            beat = (player.currentTime - offset) * tempo / 60 + start
        } else {
            if followingTrack { followingTrack = false; reanchor() }
            beat = anchor.beat + (CACurrentMediaTime() - anchor.time) * tempo / 60 * speed
            // A delayed track comes in as the score crosses its start (seeks elsewhere go through startTrack).
            if let player, isPlaying, case let t = offset + trackBeats(beat) * 60 / tempo, t >= 0, t < 0.25, !player.isPlaying {
                player.play(from: t)
                followingTrack = true
            }
        }
        if let loop, isPlaying, beat >= loop.upperBound - 0.001 { seek(to: loop.lowerBound); return }
        // Another track that starts later than the score comes in as the score crosses its start.
        for e in extras.values where isPlaying && !e.player.isPlaying {
            let t = e.offset + trackBeats(beat) * 60 / tempo
            if t >= 0, t < 0.25 { e.player.play(from: t) }
        }
        // Apple Music can't be scheduled to the sample, so it is looked at now and then: started if it is due and not
        // playing, and moved back into time if it has drifted.
        if let x = external, isPlaying, x.enabled, CACurrentMediaTime() - externalCheck > 1.5 {
            externalCheck = CACurrentMediaTime()
            let t = externalOffset + trackBeats(beat) * 60 / tempo
            if t >= 0, t < x.duration {
                if !x.isPlaying { x.play(from: t) } else if abs(x.currentTime - t) > 0.7 { x.play(from: t) }
            }
        }
        playNotes()
        let c = beat < 0 && -beat <= leadBar ? Int((-beat).rounded(.up)) : nil   // only the last bar before bar 1
        if c != countIn { countIn = c }
        let whole = Int(beat.rounded(.down))
        if whole > lastClick {
            lastClick = whole
            if metronome || (beat < 0 && player == nil) {
                let downbeat = whole < 0 ? whole % max(1, Int(leadBar.rounded())) == 0 : timeline.measures.contains { Int($0.start.rounded()) == whole }
                let c = downbeat ? clickHi : clickLo
                c?.currentTime = 0
                c?.play()
            }
        }
        if beat >= length { beat = length; pause() }
    }

    /// A short decaying sine blip, built in memory so there are no audio assets to ship.
    private static func click(freq: Double) -> AVAudioPlayer? {
        let rate = 44_100.0, n = 2_200
        var pcm = Data(capacity: n * 2)
        for i in 0..<n {
            let t = Double(i) / rate
            let s = sin(2 * .pi * freq * t) * exp(-t * 60) * 0.6
            withUnsafeBytes(of: Int16(s * Double(Int16.max)).littleEndian) { pcm.append(contentsOf: $0) }
        }
        var wav = Data("RIFF".utf8)
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { wav.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { wav.append(contentsOf: $0) } }
        u32(36 + pcm.count); wav.append(contentsOf: Data("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(Int(rate)); u32(Int(rate) * 2); u16(2); u16(16)
        wav.append(contentsOf: Data("data".utf8)); u32(pcm.count); wav.append(pcm)
        let p = try? AVAudioPlayer(data: wav)
        p?.prepareToPlay()
        return p
    }
}

// MARK: - Backing track

/// Plays the track through AVAudioEngine so practice speed and key change independently.
final class TrackPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let shifter = AVAudioUnitTimePitch()
    private let level = AVAudioUnitEQ(numberOfBands: TrackEQ.maxBands)   // the equaliser; its overall gain is the track's level
    private let file: AVAudioFile
    private var from = 0.0, last = 0.0, wanted = false
    private var observer: NSObjectProtocol?
    let duration: Double

    init?(url: URL) {
        guard let f = try? AVAudioFile(forReading: url), f.length > 0 else { return nil }
        file = f
        duration = Double(f.length) / f.processingFormat.sampleRate
        engine.attach(node)
        engine.attach(shifter)
        engine.attach(level)
        engine.connect(node, to: shifter, format: f.processingFormat)
        engine.connect(shifter, to: level, format: f.processingFormat)
        engine.connect(level, to: engine.mainMixerNode, format: f.processingFormat)
        applyEQ()   // every band bypassed until an equaliser is set
        // No engine.prepare() here: it activates the audio session on the main thread as the score opens. start() prepares anyway.
        // A route change (headphones in or out) stops the engine; carry on from the same spot.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, wanted else { return }
            play(from: last)
        }
    }

    deinit { observer.map(NotificationCenter.default.removeObserver) }

    /// The speed and key the player has chosen; the track's keyframes move them from there as it plays.
    var rate: Float = 1 { didSet { refresh() } }
    var semitones = 0 { didSet { refresh() } }
    var edit: TrackEdit? { didSet { refresh() } }
    /// Switched off, the track keeps running in time but is not heard.
    var enabled = true { didSet { refresh() } }
    /// Overall level of the track in decibels, from -60 (nearly silent) to +12.
    var gainDB: Float = 0 { didSet { applyLevel() } }
    var eq: TrackEQ? { didSet { applyEQ() } }

    private func applyLevel() {
        let output = eq?.on == true ? Float(eq!.outputGain) : 0
        level.globalGain = max(-60, min(24, gainDB + output))
    }

    private func applyEQ() {
        let nyquist = Float(file.processingFormat.sampleRate / 2)
        for (i, p) in level.bands.enumerated() {
            guard let eq, eq.on, i < eq.bands.count, eq.bands[i].on else { p.bypass = true; continue }
            let band = eq.bands[i]
            p.filterType = switch band.kind {
            case .lowCut: .highPass
            case .lowShelf: .lowShelf
            case .bell: .parametric
            case .notch: .bandStop
            case .highShelf: .highShelf
            case .highCut: .lowPass
            }
            p.frequency = min(Float(band.frequency), nyquist * 0.98)
            p.gain = Float(band.gain)
            p.bandwidth = Float(band.octaves)
            p.bypass = false
        }
        applyLevel()
    }

    /// Sets speed, pitch and level for a place in the recording.
    func refresh(at t: Double? = nil) {
        let t = t ?? last
        let tempo = edit.map { $0.value(.tempo, at: t) } ?? 1
        shifter.rate = max(1.0 / 32, min(32, rate * Float(tempo)))
        shifter.pitch = Float((Double(semitones) + (edit.map { $0.value(.pitch, at: t) } ?? 0)) * 100)
        node.volume = enabled ? Float(edit.map { $0.value(.volume, at: t) } ?? 1) : 0
    }

    /// Seconds into the file, from what the engine has rendered.
    var currentTime: Double {
        guard node.isPlaying, let rt = node.lastRenderTime, let pt = node.playerTime(forNodeTime: rt) else { return from }
        last = from + max(0, Double(pt.sampleTime)) / pt.sampleRate
        return last
    }

    /// Playing and not yet past the end.
    var isPlaying: Bool { node.isPlaying && currentTime < duration }

    /// `at`: a CACurrentMediaTime to start sounding at; nil starts now.
    func play(from t: Double, at when: Double? = nil) {
        node.stop()
        let rate = file.processingFormat.sampleRate
        let start = AVAudioFramePosition(max(0, t) * rate)
        guard start < file.length else { wanted = false; return }
        from = Double(start) / rate
        last = from
        refresh(at: from)
        node.scheduleSegment(file, startingFrame: start, frameCount: AVAudioFrameCount(file.length - start), at: nil)
        if !engine.isRunning { try? engine.start() }
        if let when { node.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: max(when, CACurrentMediaTime() + 0.02)))) } else { node.play() }
        wanted = true
    }

    func pause() {
        wanted = false
        node.stop()
    }
}

// MARK: - Waveform for the sync editor

nonisolated struct Waveform: Sendable {
    var peaks: [Float]          // 0...1 per bin
    var duration: Double
    var firstSound: Double      // seconds of leading silence

    static func load(_ url: URL, bins: Int = 360) -> Waveform? {
        guard let file = try? AVAudioFile(forReading: url),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil, let ch = buf.floatChannelData?[0] else { return nil }
        let n = Int(buf.frameLength), rate = file.processingFormat.sampleRate
        guard n > 0 else { return nil }
        let per = max(1, n / bins)
        var peaks = [Float](repeating: 0, count: bins)
        for i in 0..<bins where i * per < n {
            vDSP_maxmgv(ch + i * per, 1, &peaks[i], vDSP_Length(min(per, n - i * per)))
        }
        let top = max(peaks.max() ?? 1, 0.0001)
        // First sample louder than about -34 dB counts as the start of the music.
        var first = 0
        while first < n, abs(ch[first]) < 0.02 { first += 1 }
        return Waveform(peaks: peaks.map { $0 / top }, duration: Double(n) / rate, firstSound: Double(min(first, n)) / rate)
    }
}
