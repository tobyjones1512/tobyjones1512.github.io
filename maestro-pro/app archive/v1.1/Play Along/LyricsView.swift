import SwiftUI

/// Lyrics in the manner of Apple Music: the line being sung is big and bright, the rest recede, each syllable fills
/// as it is sung, and stressed syllables swell. Everything that moves can be turned down or off.
struct LyricsView: View {
    let doc: LyricsDocument
    let transport: Transport
    /// Lyric times are seconds of content (a lyrics file) rather than beats (a score's own words).
    var seconds = false

    @AppStorage("lyricsSize") private var size = 1.0
    @AppStorage("lyricsAnimate") private var animate = true
    @AppStorage("lyricsStrength") private var strength = "gentle"
    @AppStorage("lyricsProgress") private var progress = true
    @AppStorage("lyricsBlur") private var blur = true
    @AppStorage("lyricsBreakBar") private var breakBar = false
    @AppStorage("lyricsBold") private var bold = true
    @AppStorage("lyricsFont") private var design = "rounded"
    @AppStorage("lyricsAlign") private var align = "leading"
    @AppStorage("lyricsPartForceLeft") private var partForceLeft = false
    @AppStorage("lyricsPartColor1") private var partHex1 = ""
    @AppStorage("lyricsPartColor2") private var partHex2 = ""
    @AppStorage("lyricsPartColor3") private var partHex3 = ""
    @AppStorage("reduceMotion") private var reduceMotionSetting = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var active = -1
    /// The line a break in the singing leads up to, while that break is under way.
    @State private var pause: Int?
    @State private var userScrolledAt: Date?

    private var partMode: Bool { doc.partCount >= 2 && align != "center" && !partForceLeft }

    private func lineAlign(_ i: Int) -> TextAlignment? {
        guard partMode, doc.lines[i].part > 0 else { return nil }
        let line = doc.lines[i]
        let sim = doc.lines.contains { $0.part > 0 && $0.part != line.part && $0.start < line.end && $0.end > line.start }
        if sim { return .center }
        // Singer 1 on the left, singer 2 on the right, singer 3 and everyone together in the middle.
        switch line.part {
        case 1: return .leading
        case 2: return .trailing
        default: return .center
        }
    }

    private func lineColor(_ i: Int) -> Color? {
        guard partMode else { return nil }
        let part = doc.lines[i].part
        guard part > 0 else { return nil }
        let hex = [1: partHex1, 2: partHex2, 3: partHex3][part] ?? ""
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }

    /// Breaks in the singing long enough to show the dots: before a line, from where the last one ended.
    private var gaps: [Int: (from: Double, to: Double)] {
        let minimum = seconds ? 5.0 : 5.0 * transport.tempo / 60   // five seconds, in whatever the lyrics are timed in
        var out: [Int: (Double, Double)] = [:]
        for i in doc.lines.indices {
            // When one singer's lyrics are shown, their rest begins as the other singer's line does.
            let from = doc.lines[i].restFrom ?? (i == 0 ? 0 : doc.lines[i - 1].end)
            if doc.lines[i].start - from >= (doc.lines[i].restFrom == nil ? minimum : minimum * 0.4) { out[i] = (from, doc.lines[i].start) }
        }
        return out
    }

    /// A different singer takes over from the line before.
    private func singerChanges(at i: Int) -> Bool { i > 0 && doc.partCount >= 2 && doc.lines[i].part != doc.lines[i - 1].part }

    private var calm: Bool { reduceMotionSetting || systemReduceMotion }
    private var style: LyricStyle {
        // Without a time for each word, the syllables are only spaced out evenly: light whole lines and keep them still.
        let animate = animate && doc.wordTimed, progress = progress && doc.wordTimed
        return LyricStyle(size: size, amplitude: animate && !calm ? (strength == "full" ? 0.13 : 0.07) : 0, animated: animate && !calm, progress: progress,
                   blur: blur && !calm, bar: breakBar, bold: bold, design: ["rounded": .rounded, "serif": .serif, "mono": .monospaced][design] ?? .default, textAlign: align == "center" ? .center : .leading)
    }

    var body: some View {
        let style = style
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 120)
                    ForEach(doc.lines.indices, id: \.self) { i in
                        if let gap = gaps[i] {
                            InterludeView(from: gap.from, to: gap.to, transport: transport, seconds: seconds, style: style)
                                .id("gap\(i)")
                        }
                        LyricLineView(line: doc.lines[i], isActive: i == active, distance: abs(i - (active >= 0 ? active : pause ?? -1)), transport: transport, seconds: seconds, style: style, textAlign: lineAlign(i), partColor: lineColor(i)) {
                            transport.seek(to: seconds ? doc.lines[i].start * transport.tempo / 60 : doc.lines[i].start)
                            if !transport.isPlaying { transport.play() }
                            userScrolledAt = nil
                        }
                        .id(i)
                        .padding(.top, gaps[i] != nil ? 0 : doc.lines[i].breakBefore ? 64 * size : singerChanges(at: i) ? 30 * size : 0)
                    }
                    Color.clear.frame(height: 360)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: partMode ? .infinity : 900)   // singers use the whole width: right is the right edge, centre the centre
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in userScrolledAt = .now })
            .onChange(of: pause) { _, i in
                guard let i, userScrolledAt.map({ Date.now.timeIntervalSince($0) >= 4 }) ?? true else { return }
                withAnimation(calm ? nil : .smooth(duration: 1.0)) { proxy.scrollTo("gap\(i)", anchor: UnitPoint(x: 0.5, y: 0.3)) }
            }
            .onChange(of: active) { _, i in
                // A line that has just started wins the scroll back from a reader who wandered off.
                guard i >= 0 else { return }
                if let t = userScrolledAt, Date.now.timeIntervalSince(t) < 4 { return }
                withAnimation(calm ? nil : .smooth(duration: 1.0)) { proxy.scrollTo(i, anchor: UnitPoint(x: 0.5, y: 0.3)) }
            }
            .background { ActiveTracker(doc: doc, transport: transport, seconds: seconds, gaps: gaps, active: $active, pause: $pause) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lyrics")
    }
}

/// How the lyrics look and move, from the settings.
struct LyricStyle {
    var size: Double
    /// How much a stressed syllable grows (0 = not at all).
    var amplitude: CGFloat
    /// Whether anything animates: swelling syllables and the scale of lines.
    var animated: Bool
    /// Whether each syllable fills as it's sung (off: the whole line lights at once).
    var progress: Bool
    var blur: Bool
    /// A bar that fills across a break in the singing, in place of the three dots.
    var bar = false
    var bold: Bool
    var design: Font.Design
    var textAlign: TextAlignment
    var font: Font { .system(size: 40 * size, weight: bold ? .bold : .semibold, design: design) }

    func scaled(_ factor: Double) -> LyricStyle {
        var s = self
        s.size *= factor
        return s
    }
}

/// Watches the clock and reports which line is current (or which break in the singing is under way), so only this
/// small view redraws every frame.
private struct ActiveTracker: View {
    let doc: LyricsDocument
    let transport: Transport
    let seconds: Bool
    let gaps: [Int: (from: Double, to: Double)]
    @Binding var active: Int
    @Binding var pause: Int?

    var body: some View {
        let t = seconds ? transport.seconds : transport.beat
        let i = doc.lines.lastIndex { $0.start <= t + 0.05 } ?? -1
        // In a long break the last line lets go and the dots take over, a beat after it ends.
        let breakAt = gaps.first { t >= $0.value.from + (seconds ? 0.5 : 0.8) && t < $0.value.to }?.key
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: breakAt != nil ? -1 : i, initial: true) { _, n in active = n }
            .onChange(of: breakAt, initial: true) { _, n in pause = n }
    }
}

/// Three dots that fill in one after another across a break in the singing, then give way to the next line.
private struct InterludeView: View {
    let from: Double, to: Double
    let transport: Transport
    let seconds: Bool
    let style: LyricStyle

    var body: some View {
        let t = seconds ? transport.seconds : transport.beat
        let lead = seconds ? 0.5 : 0.8
        let start = from + lead
        let progress = max(0, min(1, (t - start) / max(to - start - (seconds ? 0.4 : 0.6), 0.1)))
        let inside = t >= start - 0.2 && t < to
        let dot = 0.42 * 40 * style.size
        Group {
            if style.bar {
                Capsule().fill(Color.primary.opacity(0.28))
                    .overlay(alignment: .leading) { GeometryReader { Capsule().fill(Color.primary).frame(width: $0.size.width * progress) } }
                    .frame(width: dot * 9, height: dot * 0.5)
            } else {
                HStack(spacing: dot * 0.55) {
                    ForEach(0..<3, id: \.self) { k in
                        let fill = max(0, min(1, progress * 3 - Double(k)))
                        // Each dot swells gently while it is the one filling.
                        let filling = fill > 0 && fill < 1
                        Circle()
                            .fill(Color.primary.opacity(0.28 + 0.72 * fill))
                            .frame(width: dot, height: dot)
                            .scaleEffect(style.animated && filling ? 1.18 : 1)
                            .animation(.spring(response: 0.7, dampingFraction: 0.65), value: filling)
                    }
                }
            }
        }
        // Breathes while waiting, shrinks away as the next line comes.
        .scaleEffect(inside ? (style.animated ? 1 + 0.05 * sin(t * 2.2) : 1) * (progress > 0.97 ? 0.85 : 1) : 0.7)
        .opacity(inside && progress < 0.99 ? 1 : 0)
        .animation(.smooth(duration: 0.8), value: inside && progress < 0.99)
        .frame(maxWidth: .infinity, alignment: style.textAlign == .center ? .center : .leading)
        .frame(height: 64 * style.size)
        .accessibilityElement()
        .accessibilityLabel("Instrumental break")
    }
}

private struct LyricLineView: View {
    let line: LyricLine
    let isActive: Bool
    let distance: Int
    let transport: Transport
    let seconds: Bool
    let style: LyricStyle
    var textAlign: TextAlignment? = nil   // nil = use style.textAlign
    var partColor: Color? = nil
    let tap: () -> Void

    private let soft = Animation.smooth(duration: 0.9)

    var body: some View {
        let split = line.splitBacking
        VStack(spacing: 4 * style.size) {
            // Words in brackets (backing vocals) at half the size, above the line.
            if let backing = split.backing { layer(backing, style: style.scaled(0.5)) }
            if !split.main.syllables.isEmpty { layer(split.main, style: style) }
        }
        .padding(.vertical, 11 * style.size)
        .scaleEffect(style.animated && !isActive ? 0.93 : 1, anchor: { switch textAlign ?? style.textAlign { case .center: .center; case .trailing: .trailing; default: .leading } }())
        .blur(radius: style.blur && !isActive ? min(5, CGFloat(distance) * 1.2) : 0)
        .animation(soft, value: isActive)
        .animation(soft, value: distance)
        .contentShape(.rect)
        .onTapGesture(perform: tap)
        .accessibilityElement()
        .accessibilityLabel(line.text)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Jumps to this line.")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func layer(_ line: LyricLine, style: LyricStyle) -> some View {
        let align = textAlign ?? style.textAlign
        let space = 0.28 * 40 * style.size
        return ZStack(alignment: align == .center ? .center : align == .trailing ? .trailing : .leading) {
            // Resting lines: all dim, blurred by distance.
            WrapLayout(spacing: space, alignment: align) {
                ForEach(Array(Self.words(line).enumerated()), id: \.offset) { _, w in Text(w).font(style.font) }
            }
            .foregroundStyle(.primary.opacity(0.34))
            .opacity(isActive ? 0 : 1)
            // The line being sung, and its neighbours either side so the hand-over fades rather than cuts.
            if distance <= 1 {
                SungLine(line: line, transport: transport, seconds: seconds, style: style, space: space, live: isActive, textAlign: align, baseColor: partColor ?? .primary)
                    .opacity(isActive ? 1 : 0)
            }
        }
    }

    private static func words(_ line: LyricLine) -> [String] {
        var out: [String] = [], current = ""
        for s in line.syllables { current += s.text; if s.wordEnd { out.append(current); current = "" } }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

/// Each syllable fills left to right over its own time, and stressed ones grow.
private struct SungLine: View {
    let line: LyricLine
    let transport: Transport
    let seconds: Bool
    let style: LyricStyle
    let space: CGFloat
    /// The line is the current one; a neighbour is drawn at rest (nothing sung yet, or everything).
    let live: Bool
    var textAlign: TextAlignment = .leading
    var baseColor: Color = .primary

    var body: some View {
        let t = seconds ? transport.seconds : transport.beat
        let words = Self.words(of: line)
        WrapLayout(spacing: space, alignment: textAlign) {
            ForEach(words.indices, id: \.self) { w in
                HStack(spacing: 0) {
                    ForEach(words[w].indices, id: \.self) { i in
                        SyllableText(syllable: words[w][i], time: t, style: style, live: live, baseColor: baseColor)
                    }
                }
            }
        }
    }

    static func words(of line: LyricLine) -> [[LyricSyllable]] {
        var out: [[LyricSyllable]] = [], current: [LyricSyllable] = []
        for s in line.syllables { current.append(s); if s.wordEnd { out.append(current); current = [] } }
        if !current.isEmpty { out.append(current) }
        return out
    }
}

private struct SyllableText: View {
    let syllable: LyricSyllable
    let time: Double
    let style: LyricStyle
    let live: Bool
    var baseColor: Color = .primary

    /// A syllable that sounds right now. Its swell is a spring, eased in and out, not tied to how far along it is.
    private var sounding: Bool { live && time >= syllable.start - 0.04 && time < syllable.end }

    var body: some View {
        let length = max(syllable.end - syllable.start, 0.05)
        let p = style.progress ? max(0, min(1, (time - syllable.start) / length)) : 1
        let lit = baseColor, dim = baseColor.opacity(0.34)
        // Stressed syllables grow; the rest rise a little, so the line breathes with the singing.
        let lift = sounding ? (syllable.stressed ? style.amplitude : style.amplitude * 0.3) : 0
        Text(syllable.text)
            .font(style.font)
            .foregroundStyle(fill(live ? p : 1, lit: lit, dim: dim))
            .scaleEffect(1 + lift, anchor: .bottom)
            .offset(y: -lift * 18)
            .shadow(color: lit.opacity(lift > 0 ? 0.4 : 0), radius: lift > 0 ? 10 : 0)
            .animation(style.animated ? .spring(response: 0.75, dampingFraction: 0.62) : nil, value: sounding)
    }

    private func fill(_ p: Double, lit: Color, dim: Color) -> AnyShapeStyle {
        if p <= 0 { return AnyShapeStyle(dim) }
        if p >= 1 { return AnyShapeStyle(lit) }
        let edge = 0.09   // a soft edge to the fill rather than a hard one
        return AnyShapeStyle(LinearGradient(stops: [.init(color: lit, location: 0), .init(color: lit, location: max(0, p - edge)),
                                                    .init(color: dim, location: min(1, p + edge)), .init(color: dim, location: 1)],
                                            startPoint: .leading, endPoint: .trailing))
    }
}

/// Words flowing left to right and wrapping, like text.
struct WrapLayout: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 0
    var alignment: TextAlignment = .leading

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let w = s.sizeThatFits(.unspecified).width
            if x + w > width, !rows[rows.count - 1].isEmpty { rows.append([]); x = 0 }
            rows[rows.count - 1].append(i)
            x += w + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var height: CGFloat = 0
        let all = rows(subviews, width: width)
        for row in all {
            height += row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
        }
        height += lineSpacing * CGFloat(max(0, all.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            let sizes = row.map { subviews[$0].sizeThatFits(.unspecified) }
            let used = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, row.count - 1))
            var x: CGFloat
            switch alignment {
            case .center:  x = bounds.minX + max(0, (bounds.width - used) / 2)
            case .trailing: x = bounds.minX + max(0, bounds.width - used)
            case .leading:  x = bounds.minX
            @unknown default: x = bounds.minX
            }
            let h = sizes.map(\.height).max() ?? 0
            for (k, i) in row.enumerated() {
                subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(sizes[k]))
                x += sizes[k].width + spacing
            }
            y += h + lineSpacing
        }
    }
}
