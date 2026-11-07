import SwiftUI

/// What the chord view draws: one cell per bar of the score, with its chords and repeat marks.
struct ChordChartModel {
    struct Bar: Identifiable {
        let id: Int                                  // the bar's index in the score
        var chords: [(tick: Int, name: String)]
        var length: Int
        var repeatStart = false, repeatEnd = 0
        var endings: [Int] = []
        var words: [String] = []                     // jumps and signs printed on the bar
    }
    var bars: [Bar]
    var fromFile: Bool
    /// The bars in the order they are played (repeats and jumps), to follow playback.
    var order: [Int]

    init(_ score: ParsedScore) {
        let chart = Chords.chart(for: score)
        fromFile = chart.fromFile
        order = score.playOrder
        bars = score.measures.indices.map { i in
            let flats = ScoreEdit.key(at: i, in: score) < 0
            let f = score.measures[i].flow
            var words: [String] = []
            if f.segno { words.append("𝄋") }
            if f.coda { words.append("⊕") }
            let jumps = ["To Coda", "D.C.", "D.S.", "Fine"]
            words += score.measures[i].marks.filter { mark in !mark.dynamic && jumps.contains { mark.text.hasPrefix($0) } }.map(\.text)
            return Bar(id: i, chords: chart.bars[i].map { ($0.tick, $0.chord?.name(flats: flats) ?? "N.C.") }, length: score.measures[i].length,
                       repeatStart: f.repeatStart, repeatEnd: f.repeatEnd, endings: f.endings, words: words)
        }
    }
}

/// The piece as a chart of chords, a cell for each bar, following playback. Tap a bar to play from it.
struct ChordChartView: View {
    let model: ChordChartModel
    let transport: Transport
    let zoom: Double
    let follow: Bool
    let seek: (Int) -> Void

    /// Which bar of the score is sounding now.
    private var current: Int {
        let i = max(0, Int(transport.barPosition(transport.beat).rounded(.down)))
        return model.order.indices.contains(i) ? model.order[i] : min(i, max(0, model.bars.count - 1))
    }

    /// Which chord of the current bar is sounding now.
    private var currentChord: Int {
        let bar = model.bars[min(current, model.bars.count - 1)]
        let pos = transport.barPosition(transport.beat)
        let tick = (pos - pos.rounded(.down)) * Double(bar.length)
        return bar.chords.lastIndex { Double($0.tick) <= tick + 0.001 } ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let columns = max(1, min(8, Int(geo.size.width / (140 * max(zoom, 0.6)))))
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.fromFile ? String(localized: "Chord symbols from the score") : String(localized: "Chords worked out from the notes"))
                            .font(.footnote).foregroundStyle(.secondary)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                            ForEach(model.bars) { bar in
                                // One cell for each chord, so none is bundled with its neighbour.
                                ForEach(0..<max(1, bar.chords.count), id: \.self) { i in
                                    cell(bar, i, active: bar.id == current && i == (bar.chords.count > 1 ? currentChord : 0)).id("\(bar.id).\(i)")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 190)
                }
                .onChange(of: current) { _, bar in if follow { withAnimation(.smooth) { proxy.scrollTo("\(bar).0", anchor: .center) } } }
            }
        }
    }

    private func cell(_ bar: ChordChartModel.Bar, _ i: Int, active: Bool) -> some View {
        let first = i == 0, last = i >= bar.chords.count - 1
        let name = bar.chords.indices.contains(i) ? bar.chords[i].name : nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(first ? "\(bar.id + 1)" : " ").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                if first, !bar.endings.isEmpty { Text(bar.endings.map(String.init).joined(separator: ",") + ".").font(.caption2).foregroundStyle(Theme.accent) }
                if first { ForEach(bar.words, id: \.self) { Text($0).font(.caption2).foregroundStyle(Theme.accent) } }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                if first, bar.repeatStart { Text("‖:").font(.system(size: 22 * zoom, weight: .bold)).foregroundStyle(Theme.accent) }
                if let name {
                    Text(name)
                        .font(.system(size: 28 * zoom, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.5).lineLimit(1)
                        .foregroundStyle(active ? Theme.accent : (name == "N.C." ? Color.secondary : Color.primary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else { Spacer() }
                if last, bar.repeatEnd > 0 { Text(":‖").font(.system(size: 22 * zoom, weight: .bold)).foregroundStyle(Theme.accent) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 64 * zoom, alignment: .topLeading)
        .background(active ? Theme.accent.opacity(0.16) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(active ? Theme.accent : Color.white.opacity(0.1), lineWidth: active ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { seek(bar.id) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bar \(bar.id + 1): " + (name ?? "no chord"))
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
