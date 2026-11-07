import AVFoundation
import Observation
import SwiftUI

// Record yourself playing a score, then play it back with the notes lit: green where you should be, red where you were.

@Observable final class RecordSession {
    private(set) var active = false
    private(set) var failure: String?
    let listener = PitchListener()
    @ObservationIgnored private(set) var clock0 = 0.0
    @ObservationIgnored private var frames: [TakeFrame] = []
    @ObservationIgnored private weak var transport: Transport?
    @ObservationIgnored private var take = Take()
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var metronome = false
    /// Called with the finished take (already analysed), or nil when it was too short to keep.
    @ObservationIgnored var onFinish: ((Take?) -> Void)?

    func begin(_ transport: Transport, folder: URL, muteTracks: Bool = false) async {
        guard !active else { return }
        self.transport = transport; self.folder = folder
        transport.pause()
        failure = nil; frames = []
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        take = Take(tempo: transport.tempo, speed: transport.speed, a4: PitchListener.a4)
        take.audio = "\(take.id.uuidString).m4a"
        // The instrument and the click would be heard by the microphone; the backing track can't be helped (headphones).
        transport.wantsInput = true
        transport.silenceInstrument = true
        transport.tracksMuted = muteTracks
        metronome = transport.metronome
        transport.metronome = false
        listener.onFrame = { [weak self] hz, time in self?.add(hz, at: time) }
        await listener.start(recordingTo: folder.appending(path: take.audio!))
        guard listener.running else {
            failure = listener.failure
            restore()
            return
        }
        clock0 = CACurrentMediaTime()
        active = true
        UIApplication.shared.isIdleTimerDisabled = true
        transport.play()
    }

    /// Stops and keeps the take (the transport stopping, for any reason, ends it too).
    func finish() {
        guard active else { return }
        active = false
        listener.stop()
        restore()
        UIApplication.shared.isIdleTimerDisabled = false
        let url = folder.map { $0.appending(path: take.audio ?? "") }
        guard frames.count >= 20, frames.contains(where: { $0.midi != nil }) else {
            if let url { try? FileManager.default.removeItem(at: url) }
            failure = String(localized: "That take was too short or silent to keep.")
            onFinish?(nil)
            return
        }
        take.frames = frames
        take.duration = frames.last?.t ?? 0
        onFinish?(take)
    }

    func stop() { guard active else { return }; transport?.pause(); finish() }

    private func restore() {
        transport?.wantsInput = false
        transport?.silenceInstrument = false
        transport?.tracksMuted = false
        transport?.metronome = metronome
    }

    private func add(_ hz: Double?, at time: Double) {
        guard active, let transport else { return }
        // Where the score was when this stretch of sound was in the middle (the pitch is for the middle of its window).
        let centre = time - 0.043
        let rate = transport.tempo * transport.speed / 60
        let beat = transport.beat - (CACurrentMediaTime() - centre) * rate
        let t = centre - clock0
        guard t >= 0 else { return }
        frames.append(TakeFrame(t: t, beat: beat, midi: hz.map { Float(Pitch.midi($0, a4: PitchListener.a4)) }))
    }
}

@Observable final class ReviewSession {
    private(set) var active = false
    private(set) var take: Take?
    private(set) var time = 0.0
    private(set) var playing = false
    private(set) var lit = ReviewLit()
    private(set) var summary: (hit: Int, total: Int)?
    private(set) var staffCount = 1
    var staff = 0 { didSet { if active, oldValue != staff { rebuild() } } }
    @ObservationIgnored private var judge: TakeJudge?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var clockStart = (wall: 0.0, at: 0.0)
    @ObservationIgnored private weak var transport: Transport?

    var duration: Double { take?.duration ?? 0 }
    private(set) var focusRef: ReviewRef?

    /// The facts about the open take, with each bar of the piece as it was played.
    func makeFacts() -> ReviewFacts? {
        guard let transport, let take, let judge else { return nil }
        let spans = transport.timeline.measures.map { BarSpan(number: $0.bar + 1, start: $0.start, end: $0.end) }
        return judge.facts(take, bars: spans)
    }

    /// Points at a place a written review mentions: lights its notes blue, and moves the recording and the page to the moment it was played.
    func focus(_ ref: ReviewRef, facts: ReviewFacts) {
        guard let take, let judge, let transport else { return }
        let from: Double, to: Double
        switch ref {
        case .bar(let n): guard let b = facts.bars.first(where: { $0.number == n }) else { return }; (from, to) = (b.start, b.end)
        case .bars(let a, let z):
            guard let s = facts.bars.first(where: { $0.number == a }), let e = facts.bars.last(where: { $0.number == z }) else { return }
            (from, to) = (s.start, e.end)
        case .note(let id): guard let n = judge.notes.first(where: { $0.id == id }) else { return }; (from, to) = (n.start, n.end)
        }
        pause()
        focusRef = ref
        transport.focus = Set(judge.notes.filter { $0.start >= from - 0.0001 && $0.start < to - 0.0001 }.map(\.id))
        scrub(to: take.time(atBeat: from))
    }

    func clearFocus() { focusRef = nil; transport?.focus = [] }

    func open(_ take: Take, audio: URL?, transport: Transport) {
        close()
        self.transport = transport
        transport.pause()
        self.take = take
        player = audio.flatMap { try? AVAudioPlayer(contentsOf: $0) }
        player?.prepareToPlay()
        let staves = Set(transport.timeline.notes.filter { $0.pitch != nil && !$0.grace }.map(\.staff))
        staffCount = (staves.max() ?? 0) + 1
        if !staves.contains(staff) { staff = staves.min() ?? 0 }
        active = true
        rebuild()
        scrub(to: 0)
    }

    func close() {
        pause()
        active = false
        transport?.review = nil
        clearFocus()
        take = nil; judge = nil; player = nil
    }

    /// The judge is rebuilt when the part or the strictness changes.
    func rebuild() {
        guard let transport, let take else { return }
        judge = TakeJudge(events: transport.timeline.notes, staff: staffCount > 1 ? staff : nil, anyOctave: Pref.bool("practiceAnyOctave", false),
                          slack: Pref.double("reviewSlack", 0.3), tolerance: Pref.double("practiceTolerance", 30) / 100)
        summary = judge?.summary(take)
        update(force: true)
    }

    func play() {
        guard active, !playing, let take else { return }
        clearFocus()
        if time >= take.duration - 0.05 { scrub(to: 0) }
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.currentTime = time
        player?.play()
        clockStart = (CACurrentMediaTime(), time)
        playing = true
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func pause() {
        player?.pause()
        link?.invalidate(); link = nil
        playing = false
    }

    func toggle() { playing ? pause() : play() }

    func scrub(to t: Double) {
        time = max(0, min(t, duration))
        player?.currentTime = time
        clockStart = (CACurrentMediaTime(), time)
        update(force: true)
    }

    @objc private func tick() {
        guard let take else { return }
        time = player?.isPlaying == true ? player!.currentTime : clockStart.at + CACurrentMediaTime() - clockStart.wall
        if time >= take.duration { time = take.duration; pause() }
        update(force: false)
    }

    private func update(force: Bool) {
        guard let take, let judge, let transport else { return }
        var l = judge.lit(take, at: time)
        transport.seek(to: max(transport.start, l.beat))   // the page follows where the score was
        l.beat = 0
        if force || l != lit { lit = l; transport.review = l }
    }
}

/// The strip above the transport bar while recording.
struct RecordPanel: View {
    let session: RecordSession
    let transport: Transport

    var body: some View {
        HStack(spacing: 14) {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let s = max(0, CACurrentMediaTime() - session.clock0)
                HStack(spacing: 8) {
                    Circle().fill(.red).frame(width: 12, height: 12).opacity(transport.beat < 0 ? 0.35 : 1)
                    Text(String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)).font(.system(.title3, design: .monospaced, weight: .semibold)).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(transport.beat < 0 ? String(localized: "Get ready…") : String(localized: "Recording. Play the score.")).font(.system(.callout, weight: .semibold)).foregroundStyle(.white)
                ProgressView(value: session.listener.level).tint(.red)
                if transport.hasAnyTrack {
                    HStack(spacing: 6) {
                        Image(systemName: transport.tracksMuted ? "speaker.slash" : "exclamationmark.triangle.fill").foregroundStyle(transport.tracksMuted ? Color.secondary : Color.orange)
                        Text(transport.tracksMuted ? String(localized: "The backing track is muted for this recording.") : String(localized: "The microphone can hear the backing track. Mute it or use headphones."))
                            .font(.caption2).foregroundStyle(.secondary)
                        Button(transport.tracksMuted ? "Unmute" : String(localized: "Mute It")) { transport.tracksMuted.toggle() }
                            .font(.caption2.weight(.semibold)).buttonStyle(.bordered).controlSize(.mini)
                    }
                } else {
                    Text("The instrument and the click are muted while you record.").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Button { session.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                .buttonStyle(KeyStyle()).keyTint(.red)
        }
        .padding(14)
        .metalPlate(radius: 16)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: 640)
    }
}

/// The strip above the transport bar while a take is being reviewed.
struct ReviewPanel: View {
    let session: ReviewSession
    let transport: Transport
    let takes: [Take]
    var staves: [String] = []
    let open: (Take) -> Void
    let delete: (Take) -> Void
    let again: () -> Void
    let written: () -> Void
    @AppStorage("reviewSlack") private var slack = 0.3
    @AppStorage("practiceTolerance") private var tolerance = 30.0
    @AppStorage("practiceAnyOctave") private var anyOctave = false
    private let green = Color(red: 0.45, green: 0.95, blue: 0.5)
    private let red = Color(red: 1.0, green: 0.38, blue: 0.34)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button { session.toggle() } label: { Image(systemName: session.playing ? "pause.fill" : "play.fill").frame(width: 22, height: 22) }
                    .buttonStyle(KeyStyle()).accessibilityLabel(session.playing ? "Pause" : String(localized: "Play the recording"))
                Slider(value: Binding { session.time } set: { session.scrub(to: $0) }, in: 0...max(session.duration, 0.1)).tint(Theme.accent)
                Text(String(format: "%d:%02d", Int(session.time) / 60, Int(session.time) % 60)).font(.system(.callout, design: .monospaced)).foregroundStyle(.white)
                Button(action: written) { Image(systemName: "sparkles").frame(width: 22, height: 22) }
                    .buttonStyle(KeyStyle()).keyTint(Theme.accent).accessibilityLabel("Written review")
                menu
                Button { session.close() } label: { Image(systemName: "xmark").frame(width: 22, height: 22) }
                    .buttonStyle(KeyStyle()).accessibilityLabel("Close the review")
            }
            HStack(spacing: 14) {
                legend(green, "Where you should be")
                legend(red, "What you played, when it was wrong or late")
                Spacer(minLength: 0)
                if let stray = session.lit.stray { Text("You played \(Pitch.name(Int(stray.rounded())))").font(.caption.weight(.semibold)).foregroundStyle(red) }
                if let s = session.summary, s.total > 0 {
                    Text("\(s.hit) of \(s.total) notes (\(Int((Double(s.hit) / Double(s.total) * 100).rounded()))%)").font(.caption.weight(.bold)).foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .metalPlate(radius: 16)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: 640)
    }

    private func legend(_ color: Color, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 5) { Circle().fill(color).frame(width: 9, height: 9); Text(text).font(.caption2).foregroundStyle(.secondary) }
    }

    private var menu: some View {
        Menu {
            Section("Recordings") {
                ForEach(takes) { t in
                    Button(t.date.formatted(date: .abbreviated, time: .shortened), systemImage: t.id == session.take?.id ? "checkmark" : "waveform") { open(t) }
                }
            }
            if session.staffCount > 1 {
                Picker("Part to Judge", selection: Bindable(session).staff) {
                    ForEach(0..<session.staffCount, id: \.self) { Text($0 < staves.count && !staves[$0].isEmpty ? staves[$0] : String(localized: "Staff \($0 + 1)")).tag($0) }
                }
            }
            Picker("Timing", selection: $slack) {
                Text("Strict").tag(0.15); Text("Normal").tag(0.3); Text("Relaxed").tag(0.6)
            }
            .onChange(of: slack) { session.rebuild() }
            Picker("In Tune Within", selection: $tolerance) {
                Text("±15¢ (strict)").tag(15.0); Text("±30¢").tag(30.0); Text("±50¢ (relaxed)").tag(50.0)
            }
            .onChange(of: tolerance) { session.rebuild() }
            Toggle("Any Octave", isOn: $anyOctave).onChange(of: anyOctave) { session.rebuild() }
            Button("Record Again", systemImage: "record.circle") { again() }
            if let t = session.take { Button("Delete This Recording", systemImage: "trash", role: .destructive) { delete(t) } }
        } label: { Image(systemName: "ellipsis.circle").frame(width: 28, height: 22) }
        .buttonStyle(KeyStyle())
        .menuActionDismissBehavior(.disabled)
        .accessibilityLabel("Review options")
    }
}
