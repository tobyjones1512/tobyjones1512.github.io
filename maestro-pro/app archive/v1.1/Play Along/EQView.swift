import SwiftUI

/// The backing tracks' equaliser for one score, heard as you change it and saved when you're done.
struct EQSheet: View {
    let item: ScoreItem
    let transport: Transport
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var eq: TrackEQ

    init(item: ScoreItem, transport: Transport) {
        self.item = item
        self.transport = transport
        _eq = State(initialValue: item.trackEQ ?? .flat)
    }

    var body: some View {
        NavigationStack {
            ScrollView { EQEditor(eq: $eq).padding() }
                .navigationTitle("Backing Track EQ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { transport.trackEQ = item.trackEQ; dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            if var current = library.items.first(where: { $0.id == item.id }) {
                                current.trackEQ = eq.isFlat ? nil : eq
                                library.save(current)
                            }
                            dismiss()
                        }
                    }
                }
                .onChange(of: eq) { _, new in transport.trackEQ = new }
        }
        .pageSheet()
    }
}

/// Bands on a frequency graph (drag a handle: sideways for frequency, up and down for gain), the chosen band's
/// settings below, presets and an output level.
struct EQEditor: View {
    @Binding var eq: TrackEQ
    @State private var selected: UUID?

    private var selectedIndex: Int? { eq.bands.firstIndex { $0.id == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Toggle("Equaliser On", isOn: $eq.on).fixedSize()
                Spacer()
                Menu {
                    ForEach(TrackEQ.presets, id: \.name) { p in
                        Button(p.name) { eq = p.eq; selected = nil }
                    }
                } label: { Label("Presets", systemImage: "slider.horizontal.3") }
                Button("Reset", systemImage: "arrow.counterclockwise") { eq = .flat; selected = nil }
            }

            EQGraph(eq: $eq, selected: $selected)
                .frame(height: 240)
                .opacity(eq.on ? 1 : 0.45)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(eq.bands.enumerated()), id: \.element.id) { i, band in
                        Button { selected = selected == band.id ? nil : band.id } label: {
                            VStack(spacing: 2) {
                                Text("\(i + 1) · \(band.kind.rawValue)").font(.caption.weight(.semibold))
                                Text(Self.hz(band.frequency)).font(.caption2.monospacedDigit())
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(selected == band.id ? Theme.accent.opacity(0.3) : Color.secondary.opacity(0.12), in: .rect(cornerRadius: 8))
                            .opacity(band.on ? 1 : 0.45)
                        }
                        .buttonStyle(.plain)
                    }
                    if eq.bands.count < TrackEQ.maxBands {
                        Button("Add Band", systemImage: "plus") {
                            let band = EQBand(kind: .bell, frequency: 2_000)
                            eq.bands.append(band)
                            selected = band.id
                        }
                    }
                }
            }

            if let i = selectedIndex {
                BandControls(band: $eq.bands[i], number: i + 1) {
                    eq.bands.remove(at: i)
                    selected = nil
                }
            } else {
                Text("Choose a band above, or drag a handle on the graph.").font(.callout).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("Output Level"); Spacer(); Text(Self.db(eq.outputGain)).monospacedDigit().foregroundStyle(.secondary) }
                Slider(value: $eq.outputGain, in: -12...12, step: 0.5)
            }
        }
        .tint(Theme.accent)
    }

    static func hz(_ f: Double) -> String { f >= 1_000 ? String(format: f >= 10_000 ? "%.0f kHz" : "%.1f kHz", f / 1_000) : String(format: "%.0f Hz", f) }
    static func db(_ g: Double) -> String { String(format: "%+.1f dB", g) }
}

/// One band's settings.
private struct BandControls: View {
    @Binding var band: EQBand
    let number: Int
    let delete: () -> Void

    /// Frequency on a log scale, so each octave gets the same room.
    private var logFrequency: Binding<Double> {
        Binding { log10(band.frequency) } set: { band.frequency = pow(10, $0).rounded() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Band \(number)").font(.headline)
                Spacer()
                Toggle("On", isOn: $band.on).fixedSize()
                Button("Delete", systemImage: "trash", role: .destructive, action: delete).labelStyle(.iconOnly)
            }
            Picker("Type", selection: $band.kind) {
                ForEach(EQBand.Kind.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            row("Frequency", EQEditor.hz(band.frequency)) { Slider(value: logFrequency, in: log10(20)...log10(20_000)) }
            if band.kind.hasGain {
                row("Gain", EQEditor.db(band.gain)) { Slider(value: $band.gain, in: -24...24, step: 0.5) }
            }
            if band.kind.hasWidth {
                row("Width (Q)", String(format: "%.2f", band.q)) { Slider(value: $band.q, in: 0.1...10) }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    private func row(_ title: LocalizedStringKey, _ value: String, @ViewBuilder slider: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text(value).monospacedDigit().foregroundStyle(.secondary) }
            slider()
        }
    }
}

/// The response curve from 20 Hz to 20 kHz, ±24 dB, with a handle for each band.
private struct EQGraph: View {
    @Binding var eq: TrackEQ
    @Binding var selected: UUID?
    private let range = 24.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { ctx, size in
                    // Grid: octaves-ish frequencies across, every 6 dB up and down.
                    for f in [50.0, 100, 200, 500, 1_000, 2_000, 5_000, 10_000] {
                        let x = Self.x(f, size.width)
                        ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(.secondary.opacity(0.18)))
                        ctx.draw(Text(EQEditor.hz(f).replacingOccurrences(of: ".0", with: "")).font(.caption2).foregroundStyle(.secondary), at: CGPoint(x: x, y: size.height - 8))
                    }
                    for db in stride(from: -18.0, through: 18, by: 6) {
                        let y = y(db, size.height)
                        ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) },
                                   with: .color(.secondary.opacity(db == 0 ? 0.45 : 0.18)))
                    }
                    // The curve, filled to the 0 dB line.
                    var curve = Path()
                    let steps = 240
                    for k in 0...steps {
                        let x = size.width * Double(k) / Double(steps)
                        let point = CGPoint(x: x, y: y(eq.response(at: Self.f(x, size.width)), size.height))
                        if k == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
                    }
                    var fill = curve
                    fill.addLine(to: CGPoint(x: size.width, y: y(0, size.height)))
                    fill.addLine(to: CGPoint(x: 0, y: y(0, size.height)))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .color(Theme.accent.opacity(0.15)))
                    ctx.stroke(curve, with: .color(Theme.accent), lineWidth: 2.5)
                }
                ForEach(Array(eq.bands.enumerated()), id: \.element.id) { i, band in
                    let point = CGPoint(x: Self.x(band.frequency, size.width), y: y(band.kind.hasGain ? band.gain : band.response(at: band.frequency), size.height))
                    Text("\(i + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(selected == band.id ? .black : .white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(selected == band.id ? Theme.accent : Color.gray.opacity(band.on ? 0.85 : 0.4)))
                        .position(point)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                            selected = band.id
                            eq.bands[i].frequency = min(20_000, max(20, Self.f(g.location.x, size.width))).rounded()
                            if band.kind.hasGain { eq.bands[i].gain = (min(range, max(-range, db(g.location.y, size.height))) * 2).rounded() / 2 }
                        })
                        .accessibilityLabel("Band \(i + 1), \(band.kind.rawValue), \(EQEditor.hz(band.frequency))")
                }
            }
        }
        .background(Color.black.opacity(0.25), in: .rect(cornerRadius: 12))
        .clipShape(.rect(cornerRadius: 12))
    }

    static func x(_ f: Double, _ width: Double) -> Double { width * log(f / 20) / log(1_000) }
    static func f(_ x: Double, _ width: Double) -> Double { 20 * pow(1_000, x / width) }
    private func y(_ db: Double, _ height: Double) -> Double { height / 2 - min(range, max(-range, db)) / range * (height / 2 - 14) }
    private func db(_ y: Double, _ height: Double) -> Double { (height / 2 - y) / (height / 2 - 14) * range }
}
