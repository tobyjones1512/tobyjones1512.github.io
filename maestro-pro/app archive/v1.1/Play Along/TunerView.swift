import AVFoundation
import Observation
import SwiftUI

// The tuner: which note you are playing, how far from it, and a hold-a-steady-note exercise that times how long you stay in tune.

/// What the tuner shows, worked out from the stream of pitches.
@Observable final class TunerModel {
    private(set) var note: Int?            // the note nearest what is sounding
    private(set) var cents = 0.0           // smoothed distance from it
    private(set) var hz: Double?
    private(set) var holdTime = 0.0        // seconds in tune on one note
    private(set) var best = 0.0
    private(set) var completed = 0         // times the goal was reached
    private(set) var goalHit = false
    private(set) var history: [(t: Double, cents: Double, note: Int)] = []
    @ObservationIgnored private var lastTime = 0.0
    @ObservationIgnored private var silence = 0.0
    @ObservationIgnored private var off = 0.0

    /// How steady the pitch has been over the last two seconds (standard deviation, in cents), nil when there isn't enough.
    var steadiness: Double? {
        guard let note, let now = history.last?.t else { return nil }
        let recent = history.filter { $0.note == note && now - $0.t < 2 }.map(\.cents)
        guard recent.count >= 6 else { return nil }
        let mean = recent.reduce(0, +) / Double(recent.count)
        return (recent.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(recent.count)).squareRoot()
    }

    func reset() { note = nil; hz = nil; holdTime = 0; best = 0; completed = 0; goalHit = false; history = []; cents = 0 }

    /// `target`: the note being held (nil: whichever note you are on). `tolerance` in cents, `goal` in seconds.
    func feed(_ hz: Double?, at time: Double, a4: Double, target: Int?, tolerance: Double, goal: Double) {
        let dt = min(0.2, max(0, time - lastTime))
        lastTime = time
        guard let hz else {
            silence += dt
            if silence > 0.5 { note = nil; self.hz = nil; holdTime = 0; goalHit = false }
            return
        }
        silence = 0
        let m = Pitch.midi(hz, a4: a4)
        var n = target ?? Int(m.rounded())
        if abs(m - Double(n)) > 1 { n = Int(m.rounded()) }   // playing some other note than the target: show that one
        let raw = (m - Double(n)) * 100
        if n != note { holdTime = 0; goalHit = false; cents = raw }
        note = n; self.hz = hz
        cents = abs(raw - cents) > 60 ? raw : cents + (raw - cents) * 0.4
        history.append((time, raw, n))
        history.removeAll { time - $0.t > 8 }
        if abs(raw) <= tolerance, target == nil || n == target {
            holdTime += dt; off = 0; best = max(best, holdTime)
        } else {
            off += dt
            if off > 0.35 { holdTime = 0; goalHit = false }
        }
        if holdTime >= goal, !goalHit {
            goalHit = true; completed += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

/// A steady tone at an exact frequency, built in memory (a sine with a few overtones so it is easy to hear on a phone speaker).
nonisolated enum ToneMaker {
    static func player(hz: Double, seconds: Double = 3) -> AVAudioPlayer? {
        let rate = 44_100.0, n = Int(rate * seconds)
        var pcm = Data(capacity: n * 2)
        for i in 0..<n {
            let t = Double(i) / rate
            let env = min(1, t / 0.04) * min(1, (seconds - t) / 0.15)
            let s = (sin(2 * .pi * hz * t) + 0.3 * sin(4 * .pi * hz * t) + 0.12 * sin(6 * .pi * hz * t)) * 0.3 * env
            withUnsafeBytes(of: Int16(max(-1, min(1, s)) * Double(Int16.max)).littleEndian) { pcm.append(contentsOf: $0) }
        }
        var wav = Data("RIFF".utf8)
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { wav.append(contentsOf: $0) } }
        func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { wav.append(contentsOf: $0) } }
        u32(36 + pcm.count); wav.append(contentsOf: Data("WAVEfmt ".utf8))
        u32(16); u16(1); u16(1); u32(Int(rate)); u32(Int(rate) * 2); u16(2); u16(16)
        wav.append(contentsOf: Data("data".utf8)); u32(pcm.count); wav.append(pcm)
        return try? AVAudioPlayer(data: wav)
    }
}

struct TunerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = TunerModel()
    @State private var listener = PitchListener()
    @State private var target: Int?
    @State private var tone: AVAudioPlayer?
    @AppStorage("tunerTolerance") private var tolerance = 10.0
    @AppStorage("tunerGoal") private var goal = 10.0
    @AppStorage("tunerA4") private var a4 = 440.0
    @AppStorage("instrumentKey") private var instrumentKey = InstrumentKey.concert.rawValue

    private var written: Int { (InstrumentKey(rawValue: instrumentKey) ?? .concert).offset }
    private var inTune: Bool { model.note != nil && abs(model.cents) <= tolerance && (target == nil || model.note == target) }

    var body: some View {
        NavigationStack {
            ZStack {
                StageBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        readout
                        trace
                        hold
                        controls
                    }
                    .frame(maxWidth: 560)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Tuner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task {
            listener.onFrame = { hz, time in model.feed(hz, at: time, a4: a4, target: target, tolerance: tolerance, goal: goal) }
            await listener.start()
        }
        .onDisappear { listener.stop(); tone?.stop() }
        .onChange(of: target) { model.reset() }
    }

    // MARK: Pieces

    private var readout: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                LCDText(text: model.note.map { Pitch.name($0) } ?? "--", size: 64, color: inTune ? Color(red: 0.45, green: 0.95, blue: 0.5) : Theme.accent)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    LCDText(text: model.note == nil ? "--¢" : String(format: "%+.0f¢", model.cents), size: 24, color: inTune ? Color(red: 0.45, green: 0.95, blue: 0.5) : Theme.accent)
                    Text(model.hz.map { String(format: "%.1f Hz", $0) } ?? " ")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    if written != 0, let n = model.note {
                        Text("Written \(Pitch.name(n + written))").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
            TuningDial(cents: model.note == nil ? nil : model.cents, tolerance: tolerance)
                .frame(height: 150)
            if let failure = listener.failure {
                Label(failure, systemImage: "mic.slash").font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center)
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    .buttonStyle(KeyStyle())
            } else {
                // So it is plain that the microphone is working, even when no note is clear yet.
                HStack(spacing: 8) {
                    Image(systemName: listener.running ? "mic.fill" : "mic").foregroundStyle(listener.running ? Theme.accent : .secondary)
                    ProgressView(value: listener.level).tint(Theme.accent)
                }
                .accessibilityLabel(listener.running ? String(localized: "Microphone on") : String(localized: "Starting the microphone"))
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black)
            DisplayGlass(radius: 12)
        }
        .recessed(radius: 12)
        .environment(\.colorScheme, .dark)
    }

    private var trace: some View {
        Canvas { ctx, size in
            let mid = size.height / 2, scale = size.height / 110
            ctx.fill(Path(CGRect(x: 0, y: mid - tolerance * scale, width: size.width, height: tolerance * 2 * scale)), with: .color(.green.opacity(0.18)))
            for c in [-50.0, 0, 50] {
                var p = Path(); p.move(to: CGPoint(x: 0, y: mid - c * scale)); p.addLine(to: CGPoint(x: size.width, y: mid - c * scale))
                ctx.stroke(p, with: .color(.white.opacity(c == 0 ? 0.35 : 0.12)), lineWidth: 0.7)
            }
            guard let now = model.history.last?.t else { return }
            var path = Path(), started = false, previousNote = -1
            for h in model.history {
                let pt = CGPoint(x: size.width - (now - h.t) / 8 * size.width, y: mid - max(-60, min(60, h.cents)) * scale)
                if started, h.note == previousNote { path.addLine(to: pt) } else { path.move(to: pt) }
                started = true; previousNote = h.note
            }
            ctx.stroke(path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 76)
        .padding(8)
        .background(Color.black)
        .recessed(radius: 10)
        .accessibilityHidden(true)
    }

    private var hold: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 7)
                Circle().trim(from: 0, to: min(1, model.holdTime / goal))
                    .stroke(model.goalHit ? Color(red: 0.45, green: 0.95, blue: 0.5) : Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: model.holdTime)
                Text(String(format: "%.1f", model.holdTime)).font(.system(.title3, design: .monospaced, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.goalHit ? String(localized: "Held for \(Int(goal)) seconds") : String(localized: "Hold a steady note")).font(.headline).foregroundStyle(.white)
                Text(target == nil ? String(localized: "Play any note and keep it in tune for \(Int(goal)) seconds.") : String(localized: "Keep \(Pitch.name(target!)) in tune for \(Int(goal)) seconds."))
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    stat("Best", String(format: "%.1fs", model.best))
                    stat("Steadiness", model.steadiness.map { String(format: "±%.0f¢", $0) } ?? "--")
                    stat("Goals", "\(model.completed)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .metalPlate()
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.callout, design: .monospaced, weight: .semibold)).foregroundStyle(Theme.accent)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Note to Hold") {
                Picker("Note to Hold", selection: $target) {
                    Text("Any Note").tag(Int?.none)
                    ForEach(36...96, id: \.self) { Text(Pitch.name($0)).tag(Int?.some($0)) }
                }
                .labelsHidden()
            }
            Picker("Tolerance", selection: $tolerance) {
                Text("Strict ±5¢").tag(5.0); Text("Normal ±10¢").tag(10.0); Text("Relaxed ±20¢").tag(20.0)
            }
            .pickerStyle(.segmented)
            LabeledContent("Goal") {
                Picker("Goal", selection: $goal) {
                    ForEach([5.0, 10, 20, 30], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
                }
                .labelsHidden()
            }
            Stepper(value: $a4, in: 415...466, step: 1) { LabeledContent("A =", value: "\(Int(a4)) Hz") }
            HStack {
                Button(action: playReference) { Label("Play Reference Note", systemImage: "speaker.wave.2") }
                    .buttonStyle(KeyStyle())
                Button { model.reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(KeyStyle())
            }
        }
        .tint(Theme.accent)
        .padding(16)
        .metalPlate()
        .environment(\.colorScheme, .dark)
    }

    private func playReference() {
        let midi = target ?? model.note ?? 69
        guard let p = ToneMaker.player(hz: Pitch.hz(Double(midi), a4: a4)) else { return }
        listener.mute(for: 3.4)
        tone = p
        p.play()
    }
}

/// A half-circle dial from 50 cents flat to 50 sharp, with the in-tune zone marked and a needle.
private struct TuningDial: View {
    let cents: Double?
    let tolerance: Double

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height - 8), r = min(size.width / 2 - 10, size.height - 22)
            // Angles measured from straight up: 0 cents points up.
            func tip(_ cents: Double, _ radius: CGFloat) -> CGPoint {
                let a = cents / 50 * 62 * .pi / 180
                return CGPoint(x: c.x + sin(a) * radius, y: c.y - cos(a) * radius)
            }
            var zone = Path()
            zone.addArc(center: c, radius: r - 2, startAngle: .degrees(-90 - tolerance / 50 * 62), endAngle: .degrees(-90 + tolerance / 50 * 62), clockwise: false)
            ctx.stroke(zone, with: .color(.green.opacity(0.55)), style: StrokeStyle(lineWidth: 8))
            for k in stride(from: -50, through: 50, by: 10) {
                let major = k % 50 == 0 || k == 0
                var p = Path(); p.move(to: tip(Double(k), r - (major ? 18 : 12))); p.addLine(to: tip(Double(k), r))
                ctx.stroke(p, with: .color(.white.opacity(major ? 0.85 : 0.45)), lineWidth: major ? 2 : 1)
            }
            ctx.draw(Text("♭").font(.title3).foregroundStyle(.white.opacity(0.7)), at: tip(-50, r - 34))
            ctx.draw(Text("♯").font(.title3).foregroundStyle(.white.opacity(0.7)), at: tip(50, r - 34))
            let shown = max(-55, min(55, cents ?? 0))
            var needle = Path(); needle.move(to: c); needle.addLine(to: tip(shown, r - 6))
            ctx.stroke(needle, with: .color(cents == nil ? .gray.opacity(0.5) : Theme.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14)), with: .color(Color(red: 0.8, green: 0.62, blue: 0.3)))
        }
        .animation(.easeOut(duration: 0.1), value: cents)
        .accessibilityLabel(cents.map { String(format: "%.0f cents %@", abs($0), $0 < 0 ? "flat" : "sharp") } ?? String(localized: "No note"))
    }
}
