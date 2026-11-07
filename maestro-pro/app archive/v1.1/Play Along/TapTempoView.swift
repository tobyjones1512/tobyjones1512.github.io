import QuartzCore
import SwiftUI

/// Tap a key in time with the beat: a few taps and the tempo appears. The space bar taps too while the key is focused.
struct TapTempoPad: View {
    /// The tempo now, shown until taps give a new one.
    var current: Double
    var autofocus = true
    let apply: (Double) -> Void
    @Environment(Library.self) private var library
    @State private var tap = TapTempo()
    @State private var bpm: Double?
    @State private var flash = false
    @FocusState private var focused: Bool

    private var tempo: Double? { bpm.map { min(300, max(20, ($0 * 10).rounded() / 10)) } }

    var body: some View {
        VStack(spacing: 12) {
            Button(action: hit) {
                VStack(spacing: 4) {
                    Image(systemName: "hand.tap").font(.system(size: 26))
                    Text("TAP").font(.system(size: 13, weight: .heavy)).tracking(2)
                }
                .frame(width: 150, height: 84)
            }
            .buttonStyle(KeyStyle(radius: 16))
            .lit(flash)
            .focused($focused)
            .onKeyPress(.space) { hit(); return .handled }
            .accessibilityHint("Tap in time with the beat.")

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                LCDText(text: String(Int((tempo ?? current).rounded())), size: 40, color: tempo == nil ? Theme.accent.opacity(0.55) : Theme.accent)
                Text("BPM").font(.system(.caption, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .frame(minWidth: 150)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(DisplayGlass(radius: 9))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int((tempo ?? current).rounded())) beats per minute")

            HStack {
                Button("Start Again") { tap.reset(); bpm = nil }.disabled(tap.count == 0)
                Spacer()
                Text(tempo == nil ? (tap.count == 0 ? String(localized: "Tap twice to start") : String(localized: "Keep tapping")) : String(localized: "Set as you tap")).font(.caption).foregroundStyle(.secondary)
            }
            Text("Tap in time with the beat. The tempo shows from the second tap and improves with every tap. With a keyboard you can press the space bar while the button is focused.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { focused = autofocus; library.typing = true; Analytics.track("tap_tempo_opened") }   // the space bar belongs to this key while it is open
        .onDisappear { library.typing = false }
    }

    private func hit() {
        bpm = tap.tap(at: CACurrentMediaTime())
        if let tempo { apply(tempo) }   // set as soon as there is one, so nothing is left unconfirmed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        flash = true
        Task { try? await Task.sleep(for: .milliseconds(110)); flash = false }
    }
}

/// A button that opens the tap pad in a popover.
struct TapTempoButton: View {
    var current: Double = 100
    let apply: (Double) -> Void
    @State private var open = false

    var body: some View {
        Button { open = true } label: { Label("Tap Tempo…", systemImage: "hand.tap") }
            .popover(isPresented: $open) {
                TapTempoPad(current: current) { apply($0) }
                    .padding(16)
                    .presentationCompactAdaptation(.popover)
            }
    }
}
