import SwiftUI

/// Floating transport: scrubber on top, controls and the position display below.
struct TransportBar: View {
    let transport: Transport
    let item: ScoreItem
    /// Lyrics with no sheet music: no metronome or tempo, and the lines stand in for bars.
    var lyricsOnly = false
    @AppStorage("largeControls") private var largeControls = false

    var body: some View {
        VStack(spacing: 12) {
            Scrubber(transport: transport)
            // Narrow columns (sidebar and inspector both open) drop the secondary readouts.
            ViewThatFits(in: .horizontal) {
                controls(compact: false)
                controls(compact: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: largeControls ? 690 : 820)
        .metalPlate(radius: 14, screws: true)
        .environment(\.colorScheme, .dark)   // the faceplate is always graphite, whatever the app's light or dark
        .scaleEffect(largeControls ? 1.18 : 1, anchor: .bottom)
        .padding(.bottom, largeControls ? 14 : 0)
    }

    private func controls(compact: Bool) -> some View {
        @Bindable var transport = transport
        return HStack(spacing: compact ? 8 : 18) {
            HStack(spacing: compact ? 0 : 6) {
                if !compact { TransportButton(symbol: "backward.end.fill", label: String(localized: "Go to Beginning")) { transport.seek(to: transport.start) } }
                TransportButton(symbol: "backward.fill", label: String(localized: "Previous Bar")) { transport.skipBar(-1) }
                PlayButton(transport: transport)
                TransportButton(symbol: "forward.fill", label: String(localized: "Next Bar")) { transport.skipBar(1) }
            }
            PositionDisplay(transport: transport, showTime: !compact, lyrics: lyricsOnly)
                .fixedSize()
                .frame(maxWidth: .infinity)
            if lyricsOnly { KeyChip(transport: transport, item: item) }
            if !lyricsOnly { HStack(spacing: 6) {
                Button { transport.metronome.toggle() } label: {
                    Image(systemName: transport.metronome ? "metronome.fill" : "metronome")
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 24, height: 30)
                }
                .buttonStyle(KeyStyle())
                .lit(transport.metronome)
                .help("Metronome (K)")
                .accessibilityLabel("Metronome")
                if !compact { TempoChip(transport: transport, item: item) }
            } }
        }
    }
}

private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.5), value: configuration.isPressed)
    }
}

private struct TransportButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var taps = 0

    var body: some View {
        Button { taps += 1; action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 34, height: 34)
                .contentShape(.rect)
        }
        .buttonStyle(KeyStyle(radius: 10))
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The big key: a round brass-rimmed button that sinks when pressed and lights its lamp while playing.
private struct PlayButton: View {
    let transport: Transport

    var body: some View {
        Button { transport.toggle() } label: {
            Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 58, height: 58)
        }
        .buttonStyle(DomeStyle(lit: transport.isPlaying))
        .help("Play or Pause (Space)")
        .accessibilityLabel(transport.isPlaying ? "Pause" : "Play")
    }
}

private struct DomeStyle: ButtonStyle {
    let lit: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .foregroundStyle(lit ? Theme.accent : Color(white: 0.92))
            .shadow(color: .black.opacity(0.8), radius: 0, y: -0.7)
            .background {
                ZStack {
                    // The bezel: a brass ring, bright where the light hits it.
                    Circle().fill(LinearGradient(colors: [Color(red: 0.95, green: 0.8, blue: 0.5), Color(red: 0.5, green: 0.36, blue: 0.14)], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.65), radius: 3, y: 3)
                    // The key itself, a dished black rubber dome.
                    Circle().fill(RadialGradient(colors: pressed ? [Color(white: 0.15), Color(white: 0.07)] : [Color(white: 0.34), Color(white: 0.1)], center: .init(x: 0.38, y: 0.3), startRadius: 1, endRadius: 40))
                        .padding(4)
                        .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1).padding(4))
                    // The lamp under the dome shows round its rim while playing.
                    if lit { Circle().strokeBorder(Theme.accent.opacity(0.85), lineWidth: 2).padding(6.5) }
                    Grain(kind: .grain, opacity: 0.35).clipShape(Circle().inset(by: 4))
                }
            }
            .scaleEffect(pressed ? 0.975 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// The LCD: bar and beat large, time underneath.
private struct PositionDisplay: View {
    let transport: Transport
    var showTime = true
    var lyrics = false

    var body: some View {
        let t = transport.timeline
        let beat = max(transport.start, transport.beat)
        let index = t.measureIndex(at: beat) ?? 0
        let m = t.measures.isEmpty ? nil : t.measures[index]
        // Intro bars count up to bar 1 as −3, −2, −1.
        let introBar = beat < 0 ? Int((-beat / transport.leadBar).rounded(.up)) : nil
        let bar = introBar.map { -$0 } ?? (m?.bar ?? index) + 1
        let beatInBar = introBar.map { Int(beat + Double($0) * transport.leadBar) + 1 } ?? m.map { Int(beat - $0.start) + 1 } ?? 1
        let secs = transport.seconds + 0.0   // adding zero turns −0.0 into 0.0
        HStack(alignment: .bottom, spacing: 16) {
            lcdField(lyrics ? "LINE" : "BAR", bar < 0 ? "−\(-bar)" : "\(bar)", width: 3, dim: bar < 0, size: 28)
            if !lyrics { lcdField("BEAT", "\(max(1, beatInBar))", width: 2, size: 28) }
            if showTime {
                lcdField("TIME", String(format: "%d:%04.1f", Int(max(0, secs)) / 60, max(0, secs).truncatingRemainder(dividingBy: 60)), width: 6, size: 18)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.clear).recessed(radius: 9, tint: Color(red: 0.04, green: 0.03, blue: 0.02)) }
        .overlay { DisplayGlass() }
        .animation(.snappy(duration: 0.22), value: bar)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(lyrics ? String(localized: "Line \(bar)") : bar < 0 ? String(localized: "Intro, \(-bar) bars to go, beat \(beatInBar)") : String(localized: "Bar \(bar), beat \(beatInBar)"))
    }

    /// One field of the display: a small engraved caption over digits with the unlit segments behind them.
    private func lcdField(_ caption: String, _ value: String, width: Int, dim: Bool = false, size: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(caption).font(.system(size: 8.5, weight: .bold)).tracking(1.4).foregroundStyle(Theme.accent.opacity(0.55))
            ZStack(alignment: .trailing) {
                Text(String(repeating: "8", count: max(width, value.count))).foregroundStyle(Theme.accent.opacity(0.07))
                Text(value).foregroundStyle(dim ? Theme.accent.opacity(0.55) : Theme.accent)
            }
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .contentTransition(.numericText())
        }
    }
}

/// Tap to type a new tempo.
private struct TempoChip: View {
    @Environment(Library.self) private var library
    let transport: Transport
    let item: ScoreItem
    @State private var editing = false

    var body: some View {
        // The tempo as it is now: the one set (or tapped), the practice speed, and any change of pace the score marks.
        let shown = Int((transport.tempo * transport.speed / transport.tempoRatio).rounded())
        Button { editing = true } label: {
            HStack(spacing: 3) {
                Text("\u{E1D5}").font(.custom("Bravura", size: 17)).baselineOffset(-4)
                Text("= \(shown)")
                    .contentTransition(.numericText(value: Double(shown)))
                    .animation(.snappy, value: shown)
            }
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundStyle(transport.speed == 1 ? Theme.accent.opacity(0.8) : Theme.accent)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .recessed(radius: 8, tint: Color(red: 0.04, green: 0.03, blue: 0.02))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Set Tempo")
        #if DEBUG
        .onAppear { if CommandLine.arguments.contains("-taptempo") { editing = true } }
        #endif
        .accessibilityLabel("Tempo \(shown) beats per minute")
        .accessibilityHint("Double-tap to type a tempo.")
        .popover(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tempo").font(.headline)
                if let own = library.items.first(where: { $0.id == item.id })?.scoreTempo {
                    // The score's own tempo is the default; a tempo of your own is optional.
                    Toggle(isOn: Binding { library.items.first { $0.id == item.id }?.customTempo == true } set: { on in
                        if on { library.setTempo(transport.tempo + (abs(transport.tempo - own) < 0.01 ? 1 : 0), for: item); transport.tempo = library.items.first { $0.id == item.id }?.tempo ?? transport.tempo }
                        else if let s = library.useScoreTempo(for: item) { transport.tempo = s }
                    }) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Custom Tempo")
                            Text(library.items.first { $0.id == item.id }?.customTempo == true ? String(localized: "The score says \(Int(own.rounded()))") : String(localized: "Using the score's \(Int(own.rounded()))")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                TempoField(tempo: Binding { library.items.first { $0.id == item.id }?.tempo ?? item.tempo } set: { t in
                    library.setTempo(t, for: item)
                    transport.tempo = t
                }, autofocus: true)
                Divider()
                TapTempoPad(current: transport.tempo, autofocus: false) { t in
                    library.setTempo(t, for: item)
                    transport.tempo = t
                }
                if transport.hasTempoMarks, !transport.hasTrack {
                    Toggle("Ignore the Score’s Tempo Changes", isOn: Binding { item.ignoreTempoMarks == true } set: { on in
                        guard var current = library.items.first(where: { $0.id == item.id }) else { return }
                        current.ignoreTempoMarks = on ? true : nil
                        library.save(current)
                    })
                    .font(.callout)
                    if transport.tempoRatio != 1 { Text("This sets the opening tempo; the score’s marks change it from there.").font(.caption).foregroundStyle(.secondary) }
                }
                if transport.speed != 1 {
                    Text("Practice speed \(Int((transport.speed * 100).rounded()))% plays it at \(shown).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(width: 340)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// Progress with a tick per bar; drag or tap to move.
private struct Scrubber: View {
    let transport: Transport
    @State private var dragging = false

    var body: some View {
        let t = transport.timeline
        let from = transport.start, span = max(t.length - from, 0.0001)
        let progress = t.length > 0 ? max(0, min(1, (transport.beat - from) / span)) : 0
        let starts = (0..<transport.leadInBars).map { from + Double($0) * transport.leadBar } + t.measures.map(\.start)
        GeometryReader { g in
            let w = g.size.width, knob: CGFloat = 20
            ZStack(alignment: .leading) {
                // The slot the fader runs in, with a mark for each bar down its side.
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(.clear).frame(height: 7)
                    .recessed(radius: 3, tint: Color(red: 0.04, green: 0.03, blue: 0.02))
                    .frame(maxHeight: .infinity)
                Canvas { ctx, size in
                    for s in starts.dropFirst() {
                        let x = size.width * (s - from) / span
                        ctx.fill(Path(CGRect(x: x, y: size.height / 2 + 6, width: 0.75, height: 3)), with: .color(.white.opacity(0.3)))
                    }
                }
                // The lit part of the slot: a strip of amber LEDs.
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.75), Theme.accent], startPoint: .top, endPoint: .bottom))
                    .frame(width: max(0, (w - 4) * progress), height: 3)
                    .padding(.leading, 2)
                    .frame(maxHeight: .infinity)
                // The fader knob: a metal cap with a groove across it.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.86), Color(white: 0.46)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(.black.opacity(0.55), lineWidth: 0.75))
                    .overlay(Rectangle().fill(.black.opacity(0.55)).frame(width: 1.5, height: 11))
                    .overlay(Rectangle().fill(.white.opacity(0.55)).frame(width: 0.75, height: 11).offset(x: 1.2))
                    .frame(width: knob * 0.62, height: dragging ? 24 : 22)
                    .shadow(color: .black.opacity(0.65), radius: 2.5, y: 2)
                    .offset(x: (w - knob * 0.62) * progress)
                    .frame(maxHeight: .infinity)
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !dragging { withAnimation(.easeOut(duration: 0.1)) { dragging = true } }
                    transport.seek(to: from + max(0, min(1, v.location.x / w)) * span)
                }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.15)) { dragging = false } })
        }
        .frame(height: 26)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(Int(progress * 100)) percent")
        .accessibilityAdjustableAction { dir in transport.skipBar(dir == .increment ? 1 : -1) }
    }
}

/// Moves the backing track up or down in semitones: a recording is pitch-shifted, karaoke music is transposed.
private struct KeyChip: View {
    @Environment(Library.self) private var library
    let transport: Transport
    let item: ScoreItem
    @State private var editing = false

    private var semitones: Int { library.items.first { $0.id == item.id }?.transpose ?? 0 }
    private func label(_ n: Int) -> String { n == 0 ? String(localized: "Original key") : n > 0 ? (n == 1 ? String(localized: "Up 1 semitone") : String(localized: "Up \(n) semitones")) : (n == -1 ? String(localized: "Down 1 semitone") : String(localized: "Down \(-n) semitones")) }

    var body: some View {
        let n = semitones
        Button { editing = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "tuningfork")
                Text(n == 0 ? "Key" : n > 0 ? "+\(n)" : "−\(-n)").monospacedDigit()
            }
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundStyle(n == 0 ? Theme.accent.opacity(0.6) : Theme.accent)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .recessed(radius: 8, tint: Color(red: 0.04, green: 0.03, blue: 0.02))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Change the key of the backing")
        .accessibilityLabel("Key: \(label(n))")
        .accessibilityHint("Double-tap to change the key.")
        .popover(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Key").font(.headline)
                NumberStepper(title: "Semitones", value: Binding { Double(semitones) } set: { set(Int($0)) }, range: -12...12, signed: true)
                HStack {
                    Button("Down a Tone") { set(max(-12, semitones - 2)) }
                    Button("Up a Tone") { set(min(12, semitones + 2)) }
                    Button("Reset") { set(0) }.disabled(semitones == 0)
                }
                .buttonStyle(.bordered).lineLimit(1).font(.callout)
                Text(transport.hasTrack ? String(localized: "The recording is pitch-shifted without changing its speed.") : String(localized: "The karaoke music plays higher or lower."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(width: 280)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func set(_ n: Int) {
        guard var current = library.items.first(where: { $0.id == item.id }) else { return }
        current.transpose = n == 0 ? nil : n
        current.shiftTrack = nil
        library.save(current)
        transport.trackSemitones = n
        transport.soundingShift = -n
    }
}
