import AVFoundation
import Observation
import SwiftUI

// Wait for Me: the score holds still on a note until you play it, in tune, for long enough, and then moves on to the next.

@Observable final class PracticeSession {
    struct Target { var start: Double; var beats: Double; var pitches: [Int] }

    private(set) var active = false
    private(set) var finished = false
    private(set) var targets: [Target] = []
    private(set) var index = 0
    private(set) var verdict = NoteJudge.Verdict.silent
    /// What is being played now, as a fractional MIDI note (nil when silent).
    private(set) var heard: Double?
    private(set) var accuracy = 1.0
    private(set) var averageCents = 0.0
    private(set) var message: String?
    /// The part followed when the score has more than one staff.
    var staff = 0 { didSet { if active, oldValue != staff { rebuild(from: transport?.beat ?? 0) } } }
    private(set) var staffCount = 1
    let listener = PitchListener()
    @ObservationIgnored private var judge = NoteJudge()
    @ObservationIgnored private weak var transport: Transport?

    var current: Target? { targets.indices.contains(index) ? targets[index] : nil }
    var progress: Double { if case .good(let p) = verdict { p } else { 0 } }

    func begin(_ transport: Transport) async {
        guard !active else { return }
        self.transport = transport
        transport.pause()
        finished = false; message = nil
        let staves = Set(transport.timeline.notes.filter { $0.pitch != nil && !$0.grace }.map(\.staff))
        staffCount = (staves.max() ?? 0) + 1
        if !staves.contains(staff) { staff = staves.min() ?? 0 }
        rebuild(from: transport.beat)
        guard !targets.isEmpty else { message = String(localized: "There are no notes to follow in this score."); return }
        active = true
        transport.wantsInput = true   // playing must not take the microphone's audio session away while it is listening
        UIApplication.shared.isIdleTimerDisabled = true
        listener.onFrame = { [weak self] hz, time in self?.handle(hz, at: time) }
        await listener.start()
    }

    func stop() {
        guard active || listener.running else { return }
        active = false
        listener.stop()   // the microphone goes first; only then can the audio session change
        transport?.wantsInput = false
        if transport?.isPlaying == true { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default) }
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func restart() { judge.resetScore(); finished = false; rebuild(from: 0); if !listener.running { Task { await listener.start() } } }
    func skip() { move(to: index + 1) }
    func back() { move(to: index - 1) }

    /// Plays the wanted note so you can hear what to aim for (the microphone is switched off while it sounds).
    func hint() {
        guard let t = current, let p = t.pitches.first, let transport else { return }
        let seconds = min(2, max(0.6, t.beats * 60 / (transport.tempo * transport.speed)))
        listener.mute(for: seconds + 0.5)
        transport.preview(p, seconds: seconds)
    }

    private func rebuild(from beat: Double) {
        guard let transport else { return }
        let notes = transport.timeline.notes.filter { $0.pitch != nil && !$0.grace && !$0.isRest && (staffCount < 2 || $0.staff == staff) }
        var groups: [Target] = []
        for n in notes.sorted(by: { $0.start < $1.start }) {
            let p = n.pitch! - transport.soundingShift
            if let last = groups.last, abs(last.start - n.start) < 0.01 {
                groups[groups.count - 1].pitches.append(p)
                groups[groups.count - 1].beats = min(last.beats, n.duration)
            } else {
                groups.append(Target(start: n.start, beats: n.duration, pitches: [p]))
            }
        }
        targets = groups
        move(to: groups.firstIndex { $0.start >= beat - 0.001 } ?? 0)
    }

    /// Parks the score on a note and asks for it.
    private func move(to i: Int) {
        guard let transport, !targets.isEmpty else { return }
        if i >= targets.count { finish(); return }
        index = max(0, i)
        finished = false
        let t = targets[index]
        judge.tolerance = Pref.double("practiceTolerance", 30) / 100
        judge.holdFraction = Pref.double("practiceHold", 0.8)
        judge.anyOctave = Pref.bool("practiceAnyOctave", false)
        judge.aim(at: t.pitches, seconds: t.beats * 60 / (transport.tempo * transport.speed))
        verdict = .silent
        transport.seek(to: t.start)
    }

    private func finish() {
        finished = true
        stats()
        listener.stop()
        transport?.wantsInput = false
        UIApplication.shared.isIdleTimerDisabled = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func stats() { accuracy = judge.accuracy; averageCents = judge.averageCents }

    private func handle(_ hz: Double?, at time: Double) {
        guard active, !finished else { return }
        heard = hz.map { Pitch.midi($0, a4: PitchListener.a4) }
        verdict = judge.feed(heard, at: time)
        if verdict == .done {
            stats()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            move(to: index + 1)
        }
    }
}

/// The strip above the transport bar while Wait for Me is on.
struct PracticePanel: View {
    let session: PracticeSession
    let transport: Transport
    var staves: [String] = []
    @AppStorage("practiceTolerance") private var tolerance = 30.0
    @AppStorage("practiceHold") private var hold = 0.8
    @AppStorage("practiceAnyOctave") private var anyOctave = false
    @AppStorage("instrumentKey") private var instrumentKey = InstrumentKey.concert.rawValue

    private var written: Int { (InstrumentKey(rawValue: instrumentKey) ?? .concert).offset }
    private let green = Color(red: 0.45, green: 0.95, blue: 0.5)

    var body: some View {
        VStack(spacing: 10) {
            if session.finished { finished } else { running }
            if let failure = session.listener.failure ?? session.message {
                Label(failure, systemImage: "mic.slash").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(14)
        .metalPlate(radius: 16)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: 640)
        .accessibilityElement(children: .contain)
    }

    private var running: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("PLAY").font(.system(size: 9, weight: .heavy)).tracking(1.5).foregroundStyle(.secondary)
                    LCDText(text: session.current.map { $0.pitches.sorted().map { Pitch.name($0 + written) }.joined(separator: " ") } ?? "--", size: 30)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(DisplayGlass(radius: 7))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(status).font(.system(.callout, weight: .semibold)).foregroundStyle(statusColor).contentTransition(.opacity)
                    PitchStrip(cents: cents, tolerance: tolerance, good: isGood)
                        .frame(height: 14)
                    ProgressView(value: session.progress).tint(green)
                        .animation(.linear(duration: 0.08), value: session.progress)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    key("speaker.wave.2", String(localized: "Hear the note")) { session.hint() }
                    key("backward.end.fill", String(localized: "Previous note")) { session.back() }.disabled(session.index == 0)
                    key("forward.end.fill", String(localized: "Skip this note")) { session.skip() }
                    options
                    key("xmark", String(localized: "Stop Wait for Me")) { session.stop() }
                }
            }
            Text("Note \(session.index + 1) of \(session.targets.count)").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var finished: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 30)).foregroundStyle(green)
            VStack(alignment: .leading, spacing: 2) {
                Text("You played all \(session.targets.count) notes").font(.headline).foregroundStyle(.white)
                Text("Accuracy \(Int((session.accuracy * 100).rounded()))%, \(Int(session.averageCents.rounded()))¢ from the note on average")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Again") { session.restart() }.buttonStyle(KeyStyle())
            Button("Done") { session.stop() }.buttonStyle(KeyStyle()).lit(true)
        }
    }

    private var options: some View {
        Menu {
            if session.staffCount > 1 {
                Picker("Part to Follow", selection: Bindable(session).staff) {
                    ForEach(0..<session.staffCount, id: \.self) { Text($0 < staves.count && !staves[$0].isEmpty ? staves[$0] : String(localized: "Staff \($0 + 1)")).tag($0) }
                }
            }
            Picker("In Tune Within", selection: $tolerance) {
                Text("±15¢ (strict)").tag(15.0); Text("±30¢").tag(30.0); Text("±50¢ (relaxed)").tag(50.0)
            }
            Picker("Hold for", selection: $hold) {
                Text("Half the length").tag(0.5); Text("Most of it").tag(0.8); Text("All of it").tag(1.0)
            }
            Toggle("Any Octave", isOn: $anyOctave)
            Button("Start Again", systemImage: "arrow.counterclockwise") { session.restart() }
        } label: {
            Image(systemName: "slider.horizontal.3").frame(width: 28, height: 22)
        }
        .buttonStyle(KeyStyle())
        .menuActionDismissBehavior(.disabled)
        .accessibilityLabel("Wait for Me options")
    }

    private func key(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 22, height: 22) }
            .buttonStyle(KeyStyle())
            .accessibilityLabel(label)
            .help(label)
    }

    // MARK: Reading the verdict

    private var cents: Double? {
        guard let h = session.heard, let t = session.current else { return nil }
        let d = t.pitches.map { p -> Double in
            var d = h - Double(p)
            if anyOctave { d -= 12 * (d / 12).rounded() }
            return d
        }.min { abs($0) < abs($1) } ?? 0
        return abs(d) < 1 ? d * 100 : nil
    }

    private var isGood: Bool { if case .good = session.verdict { true } else { false } }

    private var status: String {
        switch session.verdict {
        case .silent: session.listener.running ? String(localized: "Play the note") : String(localized: "Starting the microphone…")
        case .good: String(localized: "Hold it")
        case .off(let c): c > 0 ? String(localized: "A little sharp, \(Int(abs(c).rounded()))¢") : String(localized: "A little flat, \(Int(abs(c).rounded()))¢")
        case .wrong(let h): String(localized: "That’s \(Pitch.name(Int(h.rounded())))")
        case .done: String(localized: "Got it")
        }
    }

    private var statusColor: Color {
        switch session.verdict {
        case .good, .done: green
        case .off: Theme.accent
        case .wrong: .orange
        case .silent: .white.opacity(0.85)
        }
    }
}

/// A flat meter from 50 cents flat to 50 sharp with the in-tune zone shaded.
private struct PitchStrip: View {
    let cents: Double?
    let tolerance: Double
    let good: Bool

    var body: some View {
        Canvas { ctx, size in
            let mid = size.width / 2, scale = size.width / 100
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 4, width: size.width, height: size.height - 8), cornerRadius: 3), with: .color(.black.opacity(0.55)))
            ctx.fill(Path(CGRect(x: mid - tolerance * scale, y: 4, width: tolerance * 2 * scale, height: size.height - 8)), with: .color(.green.opacity(0.28)))
            ctx.fill(Path(CGRect(x: mid - 0.5, y: 2, width: 1, height: size.height - 4)), with: .color(.white.opacity(0.5)))
            if let cents {
                let x = mid + max(-50, min(50, cents)) * scale
                ctx.fill(Path(ellipseIn: CGRect(x: x - 5, y: size.height / 2 - 5, width: 10, height: 10)), with: .color(good ? .green : Theme.accent))
            }
        }
        .animation(.easeOut(duration: 0.08), value: cents)
        .accessibilityHidden(true)
    }
}
