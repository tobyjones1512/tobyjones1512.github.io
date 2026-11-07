import CoreGraphics
import Foundation

// Optical reading of PDF sheet music: staves, barlines, noteheads, stems, beams/flags, dots and rests,
// turned into exact rhythms. A bar whose note values don't add up to the metre (tuplets, unusual
// engraving) falls back to timing from horizontal spacing, and the timeline reports how many bars
// were read exactly.
// Pitch comes from each head's place on the staff, read through the clef, key signature and the bar's accidentals.
// ponytail: no tuplets, repeats, grace notes or 32nds+; those bars use the spacing fallback. No ties, double
// sharps/flats, or accidentals staggered far left in a crowded chord (those notes take the key's pitch).

nonisolated struct ReadSystem {
    var page: Int
    var rect: CGRect
    var staffTops: [CGFloat]
    var space: CGFloat
    var measures: [ReadMeasure]
    var clefs: [Clef] = []
    var key = 0
}

/// One notehead or rest, in page points. Duration is in quarter notes; nil means a whole-bar rest.
nonisolated struct ReadEvent {
    var rect: CGRect
    var stem: CGRect?
    var staff: Int
    var duration: Double?
    var isRest: Bool
    /// A printed accidental just left of the head: −1 flat, 0 natural, 1 sharp.
    var accidental: Int? = nil
}

nonisolated struct ReadMeasure {
    var x0: CGFloat, x1: CGFloat
    var events: [ReadEvent]
    var flow = Flow()
}

nonisolated enum SheetReader {
    static let scale: CGFloat = 2   // pixels per point

    static func read(_ doc: CGPDFDocument) -> [ReadSystem] {
        (0..<doc.numberOfPages).flatMap { i in doc.page(at: i + 1).map { read($0, index: i) } ?? [] }
    }

    /// Groups a bar's events into simultaneous columns: close in x, or sharing a stem (chord seconds).
    static func columns(_ m: ReadMeasure, space: CGFloat) -> [[ReadEvent]] {
        var out: [[ReadEvent]] = []
        for e in m.events.sorted(by: { $0.rect.minX < $1.rect.minX }) {
            if let last = out.last, let lead = last.first,
               e.rect.minX - lead.rect.minX < space * 0.9
                || (e.stem != nil && last.contains { $0.stem.map { s in abs(s.midX - e.stem!.midX) < space * 0.3 } ?? false }) {
                out[out.count - 1].append(e)
            } else { out.append([e]) }
        }
        return out
    }

    /// Onset of each column from note values: the next column starts when the earliest sounding event ends.
    static func sweep(_ cols: [[ReadEvent]]) -> (onsets: [Double], total: Double) {
        var onsets: [Double] = [], ends: [Double] = []
        for col in cols {
            let t = onsets.isEmpty ? 0 : (ends.filter { $0 > onsets.last! + 1e-6 }.min() ?? onsets.last!)
            onsets.append(t)
            ends += col.compactMap { $0.duration.map { t + $0 } }
        }
        return (onsets, ends.max() ?? 0)
    }

    /// The most common bar length, i.e. the metre the music is written in.
    static func detectedBeatsPerBar(_ systems: [ReadSystem]) -> Double? {
        let totals = systems.flatMap { s in s.measures.map { sweep(columns($0, space: s.space)).total } }.dropFirst().filter { $0 > 0 }
        let counts = Dictionary(grouping: totals.map { ($0 * 4).rounded() / 4 }, by: { $0 }).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key
    }

    /// One bar's rhythm: columns, their onsets from the bar's start, the bar's length, and whether the
    /// note values added up (exact) or the onsets came from the printed spacing.
    struct BarTiming {
        var cols: [[ReadEvent]], onsets: [Double], length: Double, exact: Bool
        /// How long an event sounds: its value when exact, else until the next event on its staff.
        func duration(_ e: ReadEvent, column k: Int) -> Double {
            if exact, let d = e.duration { return d }
            return (cols.indices.dropFirst(k + 1).first { j in cols[j].contains { $0.staff == e.staff } }.map { onsets[$0] } ?? length) - onsets[k]
        }
    }

    static func timing(_ m: ReadMeasure, space: CGFloat, beatsPerBar: Double, first: Bool) -> BarTiming {
        let cols = columns(m, space: space)
        let (onsets, total) = sweep(cols)
        // A short first bar is a pickup; an empty bar (or whole-bar rest) lasts the full metre.
        let fits = abs(total - beatsPerBar) < 0.01 || (first && total > 0 && total < beatsPerBar)
        let length = fits && total > 0 ? total : beatsPerBar
        if fits || cols.isEmpty || total == 0 { return BarTiming(cols: cols, onsets: onsets, length: length, exact: true) }
        let x0 = cols[0][0].rect.minX, span = max(m.x1 - x0, 1)
        return BarTiming(cols: cols, onsets: cols.map { Double(($0[0].rect.minX - x0) / span) * length }, length: length, exact: false)
    }

    /// Lays the bars end to end: exact rhythms where the note values add up, spacing otherwise.
    static func timeline(_ systems: [ReadSystem], beatsPerBar: Double) -> Timeline {
        var t = Timeline(), beat = 0.0, exact = 0, bars = 0
        var flows: [Flow] = []
        for (si, s) in systems.enumerated() {
            t.systems.append(SystemMark(page: s.page, rect: s.rect))
            for m in s.measures {
                // A multi-bar rest is that many bars sharing one drawn bar.
                let runs = max(1, m.flow.multiRest)
                let bt = timing(m, space: s.space, beatsPerBar: beatsPerBar, first: t.measures.isEmpty)
                let cols = bt.cols
                if bt.exact { exact += runs }
                bars += runs
                let times = bt.onsets.map { beat + $0 }
                var anchors: [(beat: Double, x: CGFloat)] = []
                var inForce: [Int: Int] = [:]   // accidentals earlier in the bar
                for (k, col) in cols.enumerated() {
                    anchors.append((times[k], col.map(\.rect.minX).min()! - s.space * 0.1))
                    for e in col where !e.isRest {
                        let d = diatonic(e, in: s), slot = e.staff * 1000 + d
                        if let a = e.accidental { inForce[slot] = a }
                        t.notes.append(NoteEvent(id: t.notes.count, start: times[k], duration: bt.duration(e, column: k), page: s.page, rect: e.rect, stem: e.stem,
                                                 pitch: ParsedScore.midi(diatonic: d, alter: inForce[slot] ?? ParsedScore.keyAlter(s.key, d.mod(7)))))
                    }
                }
                if runs > 1 {
                    for j in 0..<runs {
                        let x0 = m.x0 + (m.x1 - m.x0) * CGFloat(j) / CGFloat(runs), x1 = m.x0 + (m.x1 - m.x0) * CGFloat(j + 1) / CGFloat(runs)
                        t.measures.append(MeasureMark(start: beat, duration: beatsPerBar, system: si, bar: t.measures.count, x0: x0, x1: x1, anchors: [(beat, x0 + s.space), (beat + beatsPerBar, x1)]))
                        var f = Flow(); if j == 0 { f = m.flow }
                        flows.append(f)
                        beat += beatsPerBar
                    }
                    continue
                }
                if anchors.isEmpty { anchors.append((beat, m.x0 + s.space)) }
                anchors.append((beat + bt.length, m.x1))
                t.measures.append(MeasureMark(start: beat, duration: bt.length, system: si, bar: t.measures.count, x0: m.x0, x1: m.x1, anchors: anchors))
                flows.append(m.flow)
                beat += bt.length
            }
        }
        t.exactBars = (exact, bars)
        return t.unfolded(Flow.playOrder(flows))
    }

    /// Staff position of a head, as diatonic steps (octave × 7 + step), through the clef.
    static func diatonic(_ e: ReadEvent, in s: ReadSystem) -> Int {
        let bottom = s.staffTops[min(e.staff, s.staffTops.count - 1)] + 4 * s.space
        let clef = e.staff < s.clefs.count ? s.clefs[e.staff] : Clef()
        return clef.bottom + Int(((bottom - e.rect.midY) / (s.space / 2)).rounded())
    }

    /// The page as music: pitches from clef, key and accidentals, rhythms from the bar timing, voices
    /// where values at one onset differ, and beams across each beat.
    static func score(_ systems: [ReadSystem], beatsPerBar: Double, title: String) -> ParsedScore {
        var out = ParsedScore()
        out.title = title
        out.staffCount = systems.map(\.staffTops.count).max() ?? 1
        if out.staffCount > 1 { out.braces = [0..<out.staffCount] }   // ponytail: reads every system as one grand staff
        var clefs = [Clef](repeating: Clef(), count: out.staffCount), key: Int?, tick = 0
        let eighths = beatsPerBar != beatsPerBar.rounded()
        let beat = eighths ? 720 : 480   // beams group by the dotted quarter in 6/8, else by the quarter
        for sys in systems {
            for (mi, m) in sys.measures.enumerated() {
                let bt = timing(m, space: sys.space, beatsPerBar: beatsPerBar, first: out.measures.isEmpty)
                var pm = PMeasure(start: tick, length: Int((bt.length * 480).rounded()))
                if out.measures.isEmpty { pm.time = eighths ? (Int(beatsPerBar * 2), 8) : (Int(beatsPerBar), 4) }
                if mi == 0 {
                    if sys.key != key { pm.key = sys.key; key = sys.key }
                    for (st, c) in sys.clefs.enumerated() where st < clefs.count && (out.measures.isEmpty || clefs[st] != c) { pm.clefs[st] = c; clefs[st] = c }
                }
                var inForce: [Int: Int] = [:]   // staff/line → alteration from an accidental earlier in the bar
                var notes: [PNote] = []
                for (k, col) in bt.cols.enumerated() {
                    for e in col.sorted(by: { $0.rect.midY > $1.rect.midY }) {
                        var n = PNote()
                        n.tick = Int((bt.onsets[k] * 480).rounded())
                        n.staff = min(e.staff, out.staffCount - 1)
                        let sounding = bt.duration(e, column: k)
                        n.duration = max(1, Int((sounding * 480).rounded()))
                        (n.type, n.dots) = written(bt.exact ? e.duration ?? sounding : sounding)
                        if e.isRest {
                            n.measureRest = e.duration == nil
                        } else {
                            let bottom = sys.staffTops[e.staff] + 4 * sys.space
                            let d = clefs[n.staff].bottom + Int(((bottom - e.rect.midY) / (sys.space / 2)).rounded())
                            let slot = n.staff * 1000 + d
                            if let a = e.accidental { inForce[slot] = a; n.accidental = ParsedScore.accidentalNames[a + 2] }
                            n.diatonic = d
                            n.alter = inForce[slot] ?? ParsedScore.keyAlter(key ?? 0, d.mod(7))
                            if let st = e.stem { n.stem = st.midY < e.rect.midY ? "up" : "down" }
                        }
                        notes.append(n)
                    }
                }
                pm.notes = voiced(notes, beat: beat)
                pm.flow = m.flow
                out.measures.append(pm)
                tick += pm.length
                // The rest of a multi-bar rest: empty bars the engraver folds into the first.
                for _ in 1..<max(1, m.flow.multiRest) {
                    out.measures.append(PMeasure(start: tick, length: pm.length))
                    tick += pm.length
                }
            }
        }
        if !out.measures.isEmpty { out.measures[out.measures.count - 1].finalBar = true }
        return out
    }

    /// Note value and dots nearest a length in quarters.
    static func written(_ q: Double) -> (String, Int) {
        let table: [(Double, String, Int)] = [(6, "whole", 1), (4, "whole", 0), (3, "half", 1), (2, "half", 0), (1.5, "quarter", 1), (1, "quarter", 0),
                                              (0.75, "eighth", 1), (0.5, "eighth", 0), (0.375, "16th", 1), (0.25, "16th", 0), (0.125, "32nd", 0)]
        let best = table.min { abs(log($0.0 / max(q, 0.01))) < abs(log($1.0 / max(q, 0.01))) }!
        return (best.1, best.2)
    }

    /// Voices per staff: one onset's notes of equal length form a chord; a different length starts another
    /// voice. Then beams over runs of eighths and shorter inside each beat.
    static func voiced(_ notes: [PNote], beat: Int) -> [PNote] {
        var out: [PNote] = []
        for staff in Set(notes.map(\.staff)).sorted() {
            var ends: [Int] = []
            let order = { (g: [PNote]) -> (Int, Int) in (g[0].tick, g[0].diatonic == nil ? 1 : 0) }   // notes before rests
            let byKey: [String: [PNote]] = Dictionary(grouping: notes.filter { $0.staff == staff }) { (n: PNote) in "\(n.tick)|\(n.duration)|\(n.diatonic == nil)" }
            let groups = byKey.values.sorted { order($0) < order($1) }
            var lanes: [[PNote]] = []
            for g in groups {
                let t = g[0].tick
                let v = ends.firstIndex { $0 <= t } ?? { ends.append(0); lanes.append([]); return ends.count - 1 }()
                for (i, var n) in g.enumerated() { n.voice = "\(v + 1)"; n.chord = i > 0; lanes[v].append(n) }
                ends[v] = t + g[0].duration
            }
            for var lane in lanes {
                let heads = lane.indices.filter { !lane[$0].chord }
                var run: [Int] = []
                func close() {
                    if run.count > 1 {
                        for (j, i) in run.enumerated() {
                            let kind = j == 0 ? "begin" : j == run.count - 1 ? "end" : "continue"
                            lane[i].beams[1] = kind
                            // Second beam joins neighbouring sixteenths.
                            let short = { (k: Int) in k >= 0 && k < run.count && lane[run[k]].duration <= 120 }
                            if short(j) { lane[i].beams[2] = short(j - 1) && short(j + 1) ? "continue" : short(j + 1) ? "begin" : short(j - 1) ? "end" : nil }
                        }
                    }
                    run = []
                }
                for i in heads {
                    let n = lane[i]
                    let beamable = n.diatonic != nil && n.duration <= 240 + 120
                        && ["eighth", "16th", "32nd"].contains(n.type)
                    if beamable, let last = run.last, lane[last].tick + lane[last].duration == n.tick, lane[last].tick / beat == n.tick / beat { run.append(i) }
                    else { close(); if beamable { run = [i] } }
                }
                close()
                // Chord notes share their head's beams.
                for i in lane.indices where lane[i].chord { if let h = lane[..<i].lastIndex(where: { !$0.chord }) { lane[i].beams = lane[h].beams } }
                out += lane
            }
        }
        return out.sorted { ($0.tick, $0.staff) < ($1.tick, $1.staff) }
    }

    // MARK: - One page

    struct Bitmap {
        var w: Int, h: Int, px: [Bool]
        /// For each staff-line row, the rows just outside that line (above, below).
        var lineRows: [Int: (above: Int, below: Int)] = [:]
        subscript(x: Int, y: Int) -> Bool { x >= 0 && y >= 0 && x < w && y < h && px[y * w + x] }
        /// Ink with staff lines erased, except where a symbol continues through the line.
        func symbol(_ x: Int, _ y: Int) -> Bool {
            guard let l = lineRows[y] else { return self[x, y] }
            return self[x, y] && self[x, l.above] && self[x, l.below]
        }
        /// Like `symbol`, but keeps slanted strokes that cross a staff line (clefs, sharps).
        func glyph(_ x: Int, _ y: Int) -> Bool {
            guard let l = lineRows[y] else { return self[x, y] }
            return self[x, y] && (x - 1...x + 1).contains { self[$0, l.above] } && (x - 1...x + 1).contains { self[$0, l.below] }
        }
    }

    static func render(_ page: CGPDFPage) -> (Bitmap, CGImage?) {
        let w = Int(page.size.width * scale), h = Int(page.size.height * scale)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        page.draw(in: ctx, size: CGSize(width: w, height: h))
        let buf = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
        return (Bitmap(w: w, h: h, px: (0..<w * h).map { buf[$0] < 150 }), ctx.makeImage())
    }

    static func read(_ page: CGPDFPage, index: Int) -> [ReadSystem] {
        var b = render(page).0
        let (staves, lines) = findStaves(b)
        guard !staves.isEmpty else { return [] }
        for l in lines { for y in l.lowerBound...l.upperBound { b.lineRows[y] = (l.lowerBound - 1, l.upperBound + 1) } }
        let big = ocrImage(page)

        // Join staves that share a left-hand system barline.
        var groups: [[Staff]] = [[staves[0]]]
        for s in staves.dropFirst() {
            let prev = groups[groups.count - 1].last!
            let joined = (prev.x0 - 2...prev.x0 + Int(prev.space)).contains { x in
                let ys = prev.bottom...s.top
                return Double(ys.filter { b[x, $0] }.count) >= Double(ys.count) * 0.92
            }
            if joined { groups[groups.count - 1].append(s) } else { groups.append([s]) }
        }

        return groups.enumerated().map { gi, g in
            let space = g[0].space
            let top = g.first!.top, bottom = g.last!.bottom
            let x0 = g.map(\.x0).min()!, x1 = g.map(\.x1).max()!
            let bars = barlines(b, top: top, bottom: bottom, x0: x0, x1: x1, space: space)
            // Notehead search band: staff ± 3 spaces, never into a neighbouring system.
            let above = gi > 0 ? (groups[gi - 1].last!.bottom + top) / 2 : 0
            let below = gi + 1 < groups.count ? (bottom + groups[gi + 1][0].top) / 2 : b.h - 1
            let bandTop = max(above, top - Int(3 * space)), bandBottom = min(below, bottom + Int(3 * space))
            // Clef, key and time signature: nothing in there is a note or a rest.
            let header = max(x0 + Int(3 * space), g.map { headerEnd(b, staff: $0, from: x0, space: space) }.max() ?? x0)
            let heads = noteheads(b, x0: header, x1: x1, y0: bandTop, y1: bandBottom, space: space)
                .filter { h in !bars.contains { abs(CGFloat($0) - h.rect.midX) < space * 1.6 } } // final/double barlines
                .filter { $0.rect.height - space * 0.5 >= space * 0.75 }                       // grace notes are cue-sized
                .filter { h in onStaffOrLedger(b, head: h.rect, staves: g, space: space) }   // dynamics like p below the staff
            // An up-stem flag reads as a blob up and to the right of its own notehead; chords never stack that way.
            // ponytail: geometric guess; very tight 32nd runs could trip it. Upgrade: trace the stem.
            let notFlags = heads.filter { h in
                !heads.contains { g in
                    let dx = h.rect.minX - g.rect.minX
                    guard dx > space * 0.6, dx < space * 1.25, h.rect.midY < g.rect.minY,
                          let gs = stem(b, x0: Int(g.rect.minX + space * 0.25), x1: Int(g.rect.maxX - space * 0.25), y0: Int(g.rect.minY), y1: Int(g.rect.maxY), space: space)
                    else { return false }
                    // A flag sits on the stem's tip; a real note in a run sits well below its group's beam.
                    return gs.minY >= h.rect.minY - space * 2
                }
            }
            let staffOf: (CGFloat) -> Int = { y in g.indices.min { abs(CGFloat(g[$0].mid) - y) < abs(CGFloat(g[$1].mid) - y) }! }
            // Clef per staff, then the key signature between the clef and the end of the header.
            let clefs = g.map { clef(b, staff: $0, x0: x0, space: space) }
            let key = g.indices.map { keySignature(b, staff: g[$0], from: clefs[$0].end, to: header, space: space) }.first { $0 != 0 } ?? 0
            let headRects = notFlags.map(\.rect)
            let toPoints = CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)

            // Note values.
            var events: [(px: CGRect, e: ReadEvent)] = notFlags.map { h in
                let r = h.rect
                let st = stem(b, x0: Int(r.minX + space * 0.25), x1: Int(r.maxX - space * 0.25), y0: Int(r.minY), y1: Int(r.maxY), space: space)
                var d: Double
                if h.hollow { d = st == nil ? 4 : 2 }
                else { d = 1 / pow(2, Double(st.map { beams(b, stem: $0, headY: r.midY, space: space) } ?? 0)) }
                if dotted(b, head: r, space: space) { d *= 1.5 }
                return (r, ReadEvent(rect: r.applying(toPoints), stem: st?.applying(toPoints), staff: staffOf(r.midY), duration: d, isRest: false,
                                     accidental: accidentalBefore(b, head: r, heads: headRects, space: space)))
            }
            // Rests, per staff, starting after the header.
            for (si, st) in g.enumerated() {
                let taken = events.flatMap { [$0.px.insetBy(dx: -space * 0.2, dy: -space * 0.2)] + ($0.e.stem.map { [$0.applying(CGAffineTransform(scaleX: scale, y: scale))] } ?? []) }
                for r in rests(b, staff: st, x0: header, x1: x1, space: space, avoid: taken) {
                    events.append((r.rect, ReadEvent(rect: r.rect.applying(toPoints), stem: nil, staff: si, duration: r.duration, isRest: true)))
                }
            }

            // The opening time signature reads like rests; nothing before the first note of the piece counts as one.
            if gi == 0, index == 0, let firstNote = events.filter({ !$0.e.isRest }).map(\.px.minX).min() {
                events.removeAll { $0.e.isRest && $0.px.maxX < firstNote }
            }
            var measures: [ReadMeasure] = [], spans: [(Int, Int)] = []
            var edges = [x0] + bars.filter { $0 > x0 + Int(space) }
            if let last = edges.last, last < x1 - Int(2 * space) { edges.append(x1) }
            for (a, c) in zip(edges, edges.dropFirst()) where c - a > Int(2 * space) {
                var inBar = events.filter { $0.px.midX > CGFloat(a) && $0.px.midX < CGFloat(c) }.map(\.e)
                // Clef/key area closed off by a start-repeat barline isn't a bar.
                // So is anything inside the header, like a time signature whose digits line up into a "barline".
                if measures.isEmpty, inBar.isEmpty, CGFloat(c - a) < space * 8 || c <= header + Int(space) { continue }
                var flow = Flow()
                flow.repeatStart = a > x0 && repeatDots(b, edge: a, staff: g[0], left: false)
                flow.repeatEnd = c < x1 - Int(space) && repeatDots(b, edge: c, staff: g[0], left: true) ? 2 : 0
                // A numeral in an otherwise empty bar can be taken for a rest; it's a run of empty bars.
                if inBar.count <= 3, inBar.allSatisfy(\.isRest) {
                    for st in g { if let n = multiRest(b, staff: st, x0: a, x1: c, space: space) { inBar = []; flow.multiRest = n; break } }
                }
                measures.append(ReadMeasure(x0: CGFloat(a) / scale, x1: CGFloat(c) / scale, events: inBar, flow: flow))
                spans.append((a, c))
            }
            // Endings, signs and words belong to the bar under them.
            let barAt = { (x: CGFloat) in spans.firstIndex { CGFloat($0.0) <= x && x < CGFloat($0.1) } ?? (x < CGFloat(spans.first?.0 ?? 0) ? 0 : spans.count - 1) }
            if !spans.isEmpty {
                let bandTop2 = max(above, top - Int(7 * space)), bandBottom2 = min(below, bottom + Int(6 * space))
                let nearby = recognizeText(big, band: CGRect(x: x0, y: bandTop2, width: x1 - x0, height: bandBottom2 - bandTop2))
                for e in endings(b, x0: x0, x1: x1, top: top, space: space) {
                    for i in spans.indices where CGFloat(spans[i].0 + spans[i].1) / 2 > CGFloat(e.x0) && CGFloat(spans[i].0 + spans[i].1) / 2 < CGFloat(e.x1) { measures[i].flow.endings = e.numbers }
                }
                for w in nearby {
                    var f = Flow()
                    apply(words: w.text, to: &f)
                    // Jumps and Fine are right-aligned to their barline; Coda and Segno labels sit at the start.
                    let i = barAt(f.coda || f.segno ? w.rect.minX + space * 0.5 : w.rect.maxX - space * 0.5)
                    if f.daCapo { measures[i].flow.daCapo = true }
                    if f.dalSegno { measures[i].flow.dalSegno = true }
                    if f.toCoda { measures[i].flow.toCoda = true }
                    if f.fine { measures[i].flow.fine = true }
                    if f.coda { measures[i].flow.coda = true }
                    if f.segno { measures[i].flow.segno = true }
                }
                for s in signs(b, x0: header, x1: x1, top: top, space: space, skip: nearby.map(\.rect)) {
                    let i = barAt(CGFloat(s.x) + space)
                    if s.coda { measures[i].flow.coda = true } else { measures[i].flow.segno = true }
                }
            }
            let pad = 3 * space
            let rect = CGRect(x: CGFloat(x0) / scale - 6, y: (CGFloat(top) - pad) / scale, width: CGFloat(x1 - x0) / scale + 12, height: (CGFloat(bottom - top) + 2 * pad) / scale)
            return ReadSystem(page: index, rect: rect, staffTops: g.map { CGFloat($0.top) / scale }, space: space / scale, measures: measures,
                              clefs: clefs.map(\.clef), key: key)
        }
    }

    // MARK: - Clefs, key signatures and accidentals

    /// Ink connected to a seed through `glyph` pixels, inside a box and outside `skip`.
    static func component(_ b: Bitmap, seed: (Int, Int), xs: ClosedRange<Int>, ys: ClosedRange<Int>, skip: [CGRect] = [], seen: inout Set<Int>) -> [(Int, Int)] {
        var stack = [seed], out: [(Int, Int)] = []
        seen.insert(seed.1 * b.w + seed.0)
        while let (px, py) = stack.popLast() {
            out.append((px, py))
            for (qx, qy) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)]
            where xs.contains(qx) && ys.contains(qy) && b.glyph(qx, qy) && !seen.contains(qy * b.w + qx)
                && !skip.contains(where: { $0.contains(CGPoint(x: qx, y: qy)) }) {
                seen.insert(qy * b.w + qx)
                if out.count < 20_000 { stack.append((qx, qy)) }
            }
        }
        return out
    }

    static func bounds(_ px: [(Int, Int)]) -> CGRect {
        let xs = px.map(\.0), ys = px.map(\.1)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()! + 1, height: ys.max()! - ys.min()! + 1)
    }

    /// The clef at the start of a staff, told apart by how far it reaches: a treble clef curls well below
    /// the staff, a bass clef stops short of the bottom line, a C clef spans exactly the staff.
    static func clef(_ b: Bitmap, staff s: Staff, x0: Int, space: CGFloat) -> (clef: Clef, end: Int) {
        let xs = x0...min(b.w - 1, x0 + Int(space * 6)), ys = max(0, s.top - Int(space * 4))...min(b.h - 1, s.bottom + Int(space * 4))
        var seen = Set<Int>()
        for x in xs { for y in s.top...s.bottom where b.glyph(x, y) && !seen.contains(y * b.w + x) {
            let r = bounds(component(b, seed: (x, y), xs: xs, ys: ys, seen: &seen))
            guard r.width >= space * 0.8, r.width <= space * 4, r.height >= space * 2.5, r.height < space * 9 else { continue }
            if r.maxY - CGFloat(s.bottom) > space * 0.7 { return (Clef(sign: "G", line: 2), Int(r.maxX)) }
            // A bass clef stops short of the bottom line; a C clef reaches it.
            if r.maxY - CGFloat(s.bottom) < -space * 0.25 { return (Clef(sign: "F", line: 4), Int(r.maxX)) }
            let line = Int(((CGFloat(s.bottom) - r.midY) / space).rounded()) + 1
            return (Clef(sign: "C", line: max(1, min(5, line))), Int(r.maxX))
        } }
        return (Clef(), x0)
    }

    /// Sharp (1), flat (−1) or natural (0), from the upright strokes: a flat has one, with its bowl low on
    /// the right; a sharp has two of equal reach; a natural's two are offset, left one higher.
    static func accidental(_ px: [(Int, Int)], space: CGFloat) -> Int? {
        let r = bounds(px)
        guard r.height >= space * 1.5, r.height <= space * 3.8, r.width >= space * 0.4, r.width <= space * 1.6 else { return nil }
        let w = Int(r.width), h = Int(r.height), x0 = Int(r.minX), y0 = Int(r.minY)
        var grid = [Bool](repeating: false, count: w * h)
        for (x, y) in px { grid[(y - y0) * w + x - x0] = true }
        var strokes: [(x0: Int, x1: Int, top: Int, bottom: Int)] = []
        for cx in 0..<w {
            var run = 0, best = (len: 0, top: 0, bottom: 0)
            for cy in 0..<h { if grid[cy * w + cx] { run += 1; if run > best.len { best = (run, cy - run + 1, cy) } } else { run = 0 } }
            guard Double(best.len) >= Double(h) * 0.55 else { continue }
            if let l = strokes.last, cx - l.x1 <= 1 { strokes[strokes.count - 1] = (l.x0, cx, min(l.top, best.top), max(l.bottom, best.bottom)) }
            else { strokes.append((cx, cx, best.top, best.bottom)) }
        }
        switch strokes.count {
        case 1:
            let st = strokes[0]
            guard Double(st.x0) < Double(w) * 0.35, st.x1 + 1 < w else { return nil }
            var upper = 0, lower = 0, rows = 0
            for cy in 0..<h {
                let n = (st.x1 + 1..<w).filter { grid[cy * w + $0] }.count
                if cy < h * 45 / 100 { upper += n } else { lower += n }
                if n > 0 { rows += 1 }
            }
            return lower > 0 && upper * 6 < lower && Double(rows) >= Double(h) * 0.25 ? -1 : nil
        case 2:
            let (l, rt) = (strokes[0], strokes[1]), shift = Double(h) * 0.15
            return Double(rt.top - l.top) > shift && Double(rt.bottom - l.bottom) > shift ? 0 : 1
        default: return nil
        }
    }

    /// Sharps or flats between the clef and the time signature: +n sharps, −n flats.
    static func keySignature(_ b: Bitmap, staff s: Staff, from x0: Int, to x1: Int, space: CGFloat) -> Int {
        guard x1 > x0 + 1 else { return 0 }
        let xs = x0 + 1...x1, ys = max(0, s.top - Int(space * 2))...min(b.h - 1, s.bottom + Int(space * 2))
        var seen = Set<Int>(), sharps = 0, flats = 0
        for x in xs { for y in s.top...s.bottom where b.glyph(x, y) && !seen.contains(y * b.w + x) {
            switch accidental(component(b, seed: (x, y), xs: xs, ys: ys, seen: &seen), space: space) {
            case 1: sharps += 1
            case -1: flats += 1
            default: break
            }
        } }
        return sharps >= flats ? sharps : -flats
    }

    /// The accidental printed tight against the left of a notehead, if any.
    static func accidentalBefore(_ b: Bitmap, head r: CGRect, heads: [CGRect], space: CGFloat) -> Int? {
        let left = r.minX + space * 0.25, mid = r.midY
        let xs = max(0, Int(left - space * 2.2))...Int(left + space * 0.2)
        let ys = max(0, Int(mid - space * 3))...min(b.h - 1, Int(mid + space * 2.5))
        let skip = heads.map { $0.insetBy(dx: space * 0.2, dy: space * 0.2) }
        var seen = Set<Int>(), best: (gap: CGFloat, kind: Int)?
        for x in xs { for y in Int(mid - space * 1.2)...Int(mid + space * 1.2) where b.glyph(x, y) && !seen.contains(y * b.w + x)
            && !skip.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) {
            let px = component(b, seed: (x, y), xs: xs, ys: ys, skip: skip, seen: &seen)
            guard let kind = accidental(px, space: space) else { continue }
            let a = bounds(px), gap = left - a.maxX
            guard gap > -space * 0.3, gap < space * 1.0 else { continue }
            // A sharp or natural is centred on its note; a flat's bowl is, so the flat ends just below it.
            let placed = kind == -1 ? (a.maxY - mid > -space * 0.2 && a.maxY - mid < space * 1.0) : abs(a.midY - mid) < space * 0.7
            if placed, best.map({ gap < $0.gap }) ?? true { best = (gap, kind) }
        } }
        return best?.kind
    }

    // MARK: - Staves

    struct Staff { var top: Int, bottom: Int, x0: Int, x1: Int, space: CGFloat; var mid: Int { (top + bottom) / 2 } }

    static func longestRun(_ b: Bitmap, row y: Int) -> (Int, Int) {
        // A photographed line has pin-holes; gaps of a few pixels don't end it.
        var best = (0, -1), start = -1, last = -1
        for x in 0...b.w {
            if x < b.w && b[x, y] { if start < 0 { start = x }; last = x }
            else if start >= 0, x - last > 3 || x == b.w { if last - start > best.1 - best.0 { best = (start, last) }; start = -1 }
        }
        return best
    }

    static func findStaves(_ b: Bitmap) -> ([Staff], [ClosedRange<Int>]) {
        var lines: [(y: Int, x0: Int, x1: Int, rows: ClosedRange<Int>)] = []
        var y = 0
        while y < b.h {
            let run = longestRun(b, row: y)
            if run.1 - run.0 > b.w / 4 {
                var y2 = y
                while y2 + 1 < b.h, case let r = longestRun(b, row: y2 + 1), r.1 - r.0 > b.w / 4 { y2 += 1 }
                // A photographed line is ragged at its edges: take in neighbouring rows that are mostly line too.
                var y1 = y
                let part = (run.1 - run.0) * 3 / 10
                while y1 > 0, case let r = longestRun(b, row: y1 - 1), r.1 - r.0 > part { y1 -= 1 }
                while y2 + 1 < b.h, case let r = longestRun(b, row: y2 + 1), r.1 - r.0 > part { y2 += 1 }
                lines.append(((y + y2) / 2, run.0, run.1, y1...y2))
                y = y2 + 1
            } else { y += 1 }
        }
        var staves: [Staff] = [], rows: [ClosedRange<Int>] = []
        var i = 0
        while i + 4 < lines.count {
            let gaps = (0..<4).map { lines[i + $0 + 1].y - lines[i + $0].y }
            let avg = CGFloat(gaps.reduce(0, +)) / 4
            if avg > 3, gaps.allSatisfy({ abs(CGFloat($0) - avg) <= max(2, avg * 0.25) }) {
                let l = lines[i..<i + 5]
                staves.append(Staff(top: lines[i].y, bottom: lines[i + 4].y, x0: l.map(\.x0).min()!, x1: l.map(\.x1).max()!, space: avg))
                rows += l.map(\.rows)
                i += 5
            } else { i += 1 }
        }
        return (staves, rows)
    }

    // MARK: - Barlines: thin columns dark from the top line to the bottom line and not beyond.

    static func barlines(_ b: Bitmap, top: Int, bottom: Int, x0: Int, x1: Int, space: CGFloat) -> [Int] {
        let reach = Int(space * 0.7)
        var hits: [Int] = []
        for x in x0...min(x1 + 2, b.w - 1) {
            let n = (top...bottom).filter { b[x, $0] }.count
            guard Double(n) >= Double(bottom - top + 1) * 0.95 else { continue }
            let outside = ((top - reach)..<(top - 2)).filter { b[x, $0] }.count + ((bottom + 3)...(bottom + reach)).filter { b[x, $0] }.count
            if outside < reach { hits.append(x) }
        }
        // Cluster columns; double and final barlines collapse into one edge.
        var groups: [(Int, Int)] = []
        for x in hits {
            if let last = groups.last, x - last.1 < Int(space * 1.5) { groups[groups.count - 1].1 = x } else { groups.append((x, x)) }
        }
        // A stem that spans the staff looks the same as a barline from the middle; the difference is that a note's
        // head hangs beside it and a barline has clear air on both sides.
        let rows = top...bottom
        return groups.filter { g in
            // A stem ends at its notehead, so it never runs unbroken top line to bottom line.
            guard (g.0...g.1).contains(where: { x in rows.filter { b[x, $0] }.count >= rows.count - 1 }) else { return false }
            let beside = (-6 ... -3).reduce(0) { a, d in a + rows.filter { b.symbol(g.0 + d, $0) }.count }
                       + (3...6).reduce(0) { a, d in a + rows.filter { b.symbol(g.1 + d, $0) }.count }
            return beside * 100 < 8 * rows.count * 3
        }.map { $0.1 }
    }

    /// A thin vertical run of at least 2.5 spaces touching either side of the blob, in pixels.
    static func stem(_ b: Bitmap, x0: Int, x1: Int, y0: Int, y1: Int, space: CGFloat) -> CGRect? {
        let need = Int(space * 2.5), reach = Int(space * 4)
        let mid = (y0 + y1) / 2
        for x in [x0 - 2, x0 - 1, x0, x0 + 1, x0 + 2, x1 - 2, x1 - 1, x1, x1 + 1, x1 + 2] {
            var run = 0, best = (len: 0, end: 0)
            for y in (mid - reach)...(mid + reach) {
                if b[x, y] { run += 1; if run > best.len { best = (run, y) } } else { run = 0 }
            }
            if best.len >= need {
                // Follow the stem past the search window to its real ends (long stems reach far-off beams).
                var top = best.end - best.len + 1, bottom = best.end
                while top > 0, b[x, top - 1], best.end - top < Int(space * 9) { top -= 1 }
                while b[x, bottom + 1], bottom - top < Int(space * 9) { bottom += 1 }
                return CGRect(x: CGFloat(x) - space * 0.2, y: CGFloat(top), width: space * 0.4, height: CGFloat(bottom - top + 1))
            }
        }
        return nil
    }

    // MARK: - Note values

    /// Heads more than half a space outside the staff need a ledger line between them and the staff.
    static func onStaffOrLedger(_ b: Bitmap, head: CGRect, staves: [Staff], space: CGFloat) -> Bool {
        let y = head.midY
        guard let s = staves.min(by: { abs(CGFloat($0.mid) - y) < abs(CGFloat($1.mid) - y) }) else { return true }
        let gap = y < CGFloat(s.top) ? CGFloat(s.top) - y : y - CGFloat(s.bottom)
        guard gap > space * 0.75 else { return true }
        // Look for a thin line wider than the head, crossing it or just inside it toward the staff.
        // The head proper (rects carry a quarter-space margin); a ledger crosses it and pokes out a little.
        let x0 = Int(head.minX + space * 0.25), x1 = Int(head.maxX - space * 0.25)
        let ys = y < CGFloat(s.top) ? Int(y - space * 0.3)...Int(CGFloat(s.top) - space * 0.5) : Int(CGFloat(s.bottom) + space * 0.5)...Int(y + space * 0.3)
        return ys.contains { yy in (x0 - Int(space * 0.1)...x1 + Int(space * 0.1)).allSatisfy { b[$0, yy] } }
    }

    /// Beams or flags on a stem: separate thick runs crossing a column just beside the stem, near its tip.
    static func beams(_ b: Bitmap, stem: CGRect, headY: CGFloat, space: CGFloat) -> Int {
        let up = headY > stem.midY
        let tip = Int(up ? stem.minY : stem.maxY), dir = up ? 1 : -1
        // Scan from the tip toward the head, stopping short of the head itself (short stems in beamed runs).
        // Three beams fill about two spaces from the tip; looking further only finds neighbouring heads.
        let reach = min(Int(space * 2.1), Int(abs(headY - CGFloat(tip)) - space * 0.75))
        let minRun = Int(space * 0.3)
        var best = 0
        for dx in [-0.5, 0.5] {
            let x = Int(stem.midX + space * dx)
            var count = 0, run = 0
            let sx = Int(stem.midX)
            // A beam or flag is joined to the stem through ink near the tip; text near the tip isn't.
            let attached: (Int, Int) -> Bool = { from, to in
                let xr = min(sx, x) - 1...max(sx, x) + 1, yr = min(tip, to) - 2...max(tip, to) + 2
                var seen = Set<Int>(), stack = [(x, (from + to) / 2)]
                while let (px, py) = stack.popLast() {
                    if abs(px - sx) <= 1 { return true }
                    for (qx, qy) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1), (px - 1, py - 1), (px - 1, py + 1), (px + 1, py - 1), (px + 1, py + 1)]
                    where xr.contains(qx) && yr.contains(qy) && b[qx, qy] && seen.insert(qy * b.w + qx).inserted { stack.append((qx, qy)) }
                }
                return false
            }
            var runStart = 0
            for k in Int(-space * 0.2)...max(Int(-space * 0.2), reach) {
                let y = tip + dir * k
                if b.lineRows[y] != nil && run == 0 { continue }   // a bare staff line isn't a beam
                if b[x, y] { if run == 0 { runStart = y }; run += 1 } else {
                    if run >= minRun, attached(runStart, y - dir) { count += 1 }
                    run = 0
                }
            }
            if run >= minRun, attached(runStart, tip + dir * reach) { count += 1 }
            best = max(best, count)
        }
        return min(best, 3)
    }

    /// An augmentation dot: a small isolated blob just right of the head, on or above its line.
    static func dotted(_ b: Bitmap, head: CGRect, space: CGFloat) -> Bool {
        let wx0 = Int(head.maxX - space * 0.15), wx1 = Int(head.maxX + space * 1.1)
        let wy0 = Int(head.midY - space * 0.95), wy1 = Int(head.midY + space * 0.45)
        var seen = Set<Int>()
        for y in wy0...wy1 { for x in wx0...wx1 where b.symbol(x, y) && !seen.contains(y * b.w + x) {
            var stack = [(x, y)], n = 0, bx = (x, x), by = (y, y), escaped = false
            seen.insert(y * b.w + x)
            while let (px, py) = stack.popLast() {
                n += 1
                bx = (min(bx.0, px), max(bx.1, px)); by = (min(by.0, py), max(by.1, py))
                if px <= wx0 || px >= wx1 || py <= wy0 || py >= wy1 { escaped = true }
                for (qx, qy) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)] where b.symbol(qx, qy) && !seen.contains(qy * b.w + qx) {
                    seen.insert(qy * b.w + qx)
                    if n < 2000 { stack.append((qx, qy)) }
                }
            }
            let w = CGFloat(bx.1 - bx.0 + 1), h = CGFloat(by.1 - by.0 + 1)
            if !escaped, w >= space * 0.25, w <= space * 0.7, h >= space * 0.25, h <= space * 0.7, CGFloat(n) >= w * h * 0.55 { return true }
        } }
        return false
    }

    /// Rests on one staff, classified by shape. Whole rests hang from the second line, half rests sit on the
    /// middle line, quarter and eighth rests are tall strokes centred in the staff. A whole rest alone in a
    /// bar is a whole-bar rest (duration nil).
    static func rests(_ b: Bitmap, staff s: Staff, x0: Int, x1: Int, space: CGFloat, avoid: [CGRect]) -> [(rect: CGRect, duration: Double?)] {
        let y0 = s.top - Int(space * 0.6), y1 = s.bottom + Int(space * 0.6)
        var seen = Set<Int>(), out: [(rect: CGRect, duration: Double?)] = []
        for x in x0...x1 { for y in y0...y1 where b.symbol(x, y) && !seen.contains(y * b.w + x) {
            var stack = [(x, y)], n = 0, bx = (x, x), by = (y, y)
            seen.insert(y * b.w + x)
            while let (px, py) = stack.popLast() {
                n += 1
                bx = (min(bx.0, px), max(bx.1, px)); by = (min(by.0, py), max(by.1, py))
                for (qx, qy) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)]
                where qx >= x0 && qx <= x1 && qy >= y0 && qy <= y1 && b.symbol(qx, qy) && !seen.contains(qy * b.w + qx) {
                    seen.insert(qy * b.w + qx); stack.append((qx, qy))
                }
            }
            let r = CGRect(x: bx.0, y: by.0, width: bx.1 - bx.0 + 1, height: by.1 - by.0 + 1)
            guard by.0 > y0, by.1 < y1 else { continue }                     // runs off the staff: text, dynamics, slurs
            guard !avoid.contains(where: { $0.intersects(r) }) else { continue }
            guard !enclosesHole(b, bx.0...bx.1, by.0...by.1) else { continue }  // accidentals, clefs, digits 0 4 6 8 9
            // Time-signature digits fill the staff from an outer line; rests stop short of both.
            guard abs(r.minY - CGFloat(s.top)) > space * 0.3, abs(r.maxY - CGFloat(s.bottom)) > space * 0.3 else { continue }
            // Accidentals sit just left of a notehead at the same height.
            guard !avoid.contains(where: { $0.minX - r.maxX < space * 1.6 && $0.minX > r.maxX - 1 && $0.minY < r.maxY && $0.maxY > r.minY }) else { continue }
            let ws = r.width / space, hs = r.height / space, fill = CGFloat(n) / (r.width * r.height)
            let midStaff = CGFloat(s.mid)
            if ws >= 0.8, ws <= 1.7, hs >= 0.3, hs <= 0.8, fill >= 0.75 {
                let line2 = CGFloat(s.top) + space, line3 = CGFloat(s.top) + space * 2
                if abs(r.minY - line2) < space * 0.35 { out.append((r, nil)) }            // whole (or whole-bar) rest
                else if abs(r.maxY - line3) < space * 0.35 { out.append((r, 2)) }        // half rest
            } else if ws >= 0.55, ws <= 1.4, fill >= 0.2, fill <= 0.75, abs(r.midY - midStaff) < space * 1.2 {
                if hs >= 2.2, hs <= 3.4 { out.append((r, 1)) }                           // quarter rest
                else if hs >= 1.2, hs < 2.2 { out.append((r, 0.5)) }                     // eighth rest
            }
        } }
        // Time-signature digits: two tall shapes stacked at the same x, one in each half of the staff.
        let digit = { (r: CGRect) in r.height >= space * 1.5 && r.height <= space * 2.5 }
        return out.filter { a in
            !out.contains { b in
                a.rect != b.rect && digit(a.rect) && digit(b.rect) && abs(a.rect.midX - b.rect.midX) < space * 0.6
                    && (a.rect.midY - CGFloat(s.mid)) * (b.rect.midY - CGFloat(s.mid)) < 0
            }
        }
    }

    /// End of the clef + key + time signature cluster: symbols packed together from the left edge of the
    /// staff, until the first clear gap.
    static func headerEnd(_ b: Bitmap, staff s: Staff, from x0: Int, space: CGFloat) -> Int {
        let ys = (s.top - Int(space * 0.5))...(s.bottom + Int(space * 0.5))
        let inked: (Int) -> Bool = { x in ys.contains { b.symbol(x, $0) } }
        var x = x0 + 2
        while x < s.x1, !inked(x) { x += 1 }              // to the clef
        var lastInk = x, gap = Int(space * 1.2)
        while x < s.x1, x - lastInk < gap {
            if inked(x) { lastInk = x }
            x += 1
        }
        return lastInk + 1
    }

    /// True if some white pixel inside the box can't reach the box edge: the shape has a closed loop.
    static func enclosesHole(_ b: Bitmap, _ xs: ClosedRange<Int>, _ ys: ClosedRange<Int>) -> Bool {
        let w = xs.count + 2, h = ys.count + 2           // one-pixel white margin around the box
        var reach = [Bool](repeating: false, count: w * h)
        let white: (Int, Int) -> Bool = { x, y in
            x == 0 || y == 0 || x == w - 1 || y == h - 1 || !b.symbol(xs.lowerBound + x - 1, ys.lowerBound + y - 1)
        }
        var stack = [0]; reach[0] = true
        while let p = stack.popLast() {
            let x = p % w, y = p / w
            for (qx, qy) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where qx >= 0 && qy >= 0 && qx < w && qy < h {
                let q = qy * w + qx
                if !reach[q] && white(qx, qy) { reach[q] = true; stack.append(q) }
            }
        }
        for y in 1..<(h - 1) { for x in 1..<(w - 1) where !reach[y * w + x] && white(x, y) { return true } }
        return false
    }

    // MARK: - Noteheads: fill small enclosed holes (open heads), erode away thin strokes, keep head-sized blobs.

    static func noteheads(_ b: Bitmap, x0: Int, x1: Int, y0: Int, y1: Int, space: CGFloat) -> [(rect: CGRect, hollow: Bool)] {
        let w = x1 - x0 + 1, h = y1 - y0 + 1
        guard w > 0, h > 0 else { return [] }
        var ink = [Bool](repeating: false, count: w * h)
        for y in 0..<h { for x in 0..<w { ink[y * w + x] = b[x0 + x, y0 + y] } }

        let raw = ink

        // 1. Fill small white regions not touching the band edge (the insides of open noteheads).
        var seen = [Bool](repeating: false, count: w * h), hole = seen
        let maxHole = Int(space * space * 0.9)
        for start in 0..<(w * h) where !ink[start] && !seen[start] {
            var stack = [start], region: [Int] = [], edge = false
            seen[start] = true
            while let p = stack.popLast() {
                region.append(p)
                let x = p % w, y = p / w
                if x == 0 || y == 0 || x == w - 1 || y == h - 1 { edge = true }
                for q in [p - 1, p + 1, p - w, p + w] where q >= 0 && q < w * h && !seen[q] && !ink[q] && abs(q % w - x) <= 1 {
                    seen[q] = true; stack.append(q)
                }
            }
            if !edge && region.count <= maxHole { for p in region { ink[p] = true; hole[p] = true } }
        }

        let r = max(1, Int(space * 0.3))
        let need = Int(Double((2 * r + 1) * (2 * r + 1)) * 0.9)
        /// Erode with a box ~0.6 spaces (integral image), then return blob boxes in band pixels.
        func blobs(_ ink: [Bool]) -> [(minX: Int, maxX: Int, minY: Int, maxY: Int)] {
            var sum = [Int](repeating: 0, count: (w + 1) * (h + 1))
            for y in 0..<h { var row = 0; for x in 0..<w { row += ink[y * w + x] ? 1 : 0; sum[(y + 1) * (w + 1) + x + 1] = sum[y * (w + 1) + x + 1] + row } }
            var core = [Bool](repeating: false, count: w * h)
            for y in r..<max(r, h - r) { for x in r..<max(r, w - r) {
                let a = sum[(y - r) * (w + 1) + x - r], bb = sum[(y - r) * (w + 1) + x + r + 1]
                let c = sum[(y + r + 1) * (w + 1) + x - r], d = sum[(y + r + 1) * (w + 1) + x + r + 1]
                core[y * w + x] = d - bb - c + a >= need
            } }
            var out: [(minX: Int, maxX: Int, minY: Int, maxY: Int)] = []
            var seen = [Bool](repeating: false, count: w * h)
            for start in 0..<(w * h) where core[start] && !seen[start] {
                var stack = [start], minX = w, maxX = 0, minY = h, maxY = 0
                seen[start] = true
                while let p = stack.popLast() {
                    let x = p % w, y = p / w
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    for q in [p - 1, p + 1, p - w, p + w] where q >= 0 && q < w * h && !seen[q] && core[q] && abs(q % w - x) <= 1 {
                        seen[q] = true; stack.append(q)
                    }
                }
                out.append((minX, maxX, minY, maxY))
            }
            return out
        }

        // 2. Filled heads come from the ink as printed; open heads only from the hole-filled ink, where
        // filling never gets the chance to glue an accidental onto a filled head.
        let solid = blobs(raw)
        let open = blobs(ink).filter { o in
            !solid.contains { s in s.minX <= o.maxX && o.minX <= s.maxX && s.minY <= o.maxY && o.minY <= s.maxY }
                && (o.minY...o.maxY).contains { y in (o.minX...o.maxX).contains { hole[y * w + $0] } }
        }

        // 3. Blobs → head rectangles (grown back by the erosion radius).
        var out: [(rect: CGRect, hollow: Bool)] = []
        for (blob, hollow) in solid.map({ ($0, false) }) + open.map({ ($0, true) }) {
            var (minX, maxX, minY, maxY) = blob
            // A head fused with the accidental just left of it: keep the head-sized right end.
            if CGFloat(maxX - minX + 1 + 2 * r) > space * 1.7, CGFloat(maxX - minX + 1 + 2 * r) <= space * 2.8 {
                minX = maxX - Int(space * 1.3) + 2 * r
            }
            let rw = CGFloat(maxX - minX + 1 + 2 * r), rh = CGFloat(maxY - minY + 1 + 2 * r)
            // Taller than a stacked chord is a time signature or a barline, not notes.
            guard rw >= space * 0.8, rw <= space * 2.2, rh >= space * 0.6, rh <= space * 3.5 else { continue }
            // Open heads are full-size ovals; slashed grace flags and loops of small symbols are narrower.
            guard !hollow || rw >= space * 1.05 else { continue }
            // Real heads carry a stem at one side, or are whole notes (wide and hollow). Dynamics and text don't.
            let (bl, br, bt, bb) = (x0 + minX - r, x0 + maxX + r, y0 + minY - r, y0 + maxY + r)
            let left = stem(b, x0: bl, x1: bl, y0: bt, y1: bb, space: space), right = stem(b, x0: br, x1: br, y0: bt, y1: bb, space: space)
            // Uprights on both sides spanning the same height: a sharp or natural. (Two voices' stems point
            // opposite ways and don't overlap.)
            if let l = left, let rt = right {
                let overlap = min(l.maxY, rt.maxY) - max(l.minY, rt.minY)
                guard overlap < min(l.height, rt.height) * 0.5 else { continue }
            }
            // An open head never has a long stroke through it; a white pocket under a beam does.
            if hollow {
                let crossedByBeam = (bt...bb).contains { y in
                    var run = 0, best = 0
                    for x in (bl - Int(space))...(br + Int(space)) { if b.symbol(x, y) { run += 1; best = max(best, run) } else { run = 0 } }
                    return CGFloat(best) > CGFloat(br - bl) + space * 1.5
                }
                guard !crossedByBeam else { continue }
            }
            if left == nil && right == nil {
                // A whole note stands clear on both sides; a pocket between a beam and a staff line doesn't.
                let my = (bt + bb) / 2
                guard hollow, rw >= space * 1.4, !b.symbol(bl - Int(space * 0.3), my), !b.symbol(br + Int(space * 0.3), my) else { continue }
            }
            // Split tall blobs (stacked chord heads) into one rect per head.
            let count = max(1, Int((rh / space).rounded()))
            for k in 0..<count {
                let hy = CGFloat(y0 + minY - r) + rh * CGFloat(k) / CGFloat(count)
                out.append((CGRect(x: CGFloat(x0 + minX - r) - space * 0.25, y: hy - space * 0.25, width: rw + space * 0.5, height: rh / CGFloat(count) + space * 0.5), hollow))
            }
        }
        return out
    }
}
