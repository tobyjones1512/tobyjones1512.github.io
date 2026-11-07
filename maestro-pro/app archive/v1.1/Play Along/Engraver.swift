import CoreGraphics
import CoreText
import Foundation

// Lays out a ParsedScore into PDF pages with Bravura (SMuFL) and records where every note landed.
// ponytail: ties, slurs, lyrics, dynamics, hairpins, ornaments and octave lines are drawn but without collision avoidance (a long lyric or
// a hairpin can run into its neighbour); no cross-system hairpin shaping beyond clipping at the system edge; seconds are not
// pulled apart. Upgrade: measure text and nudge.
// or multi-voice rests. Add when real-world files need them.

nonisolated enum Engraver {
    static let baseSpace: CGFloat = 7                 // staff space at normal size, points
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 54

    /// `scale` is the zoom: the notation grows or shrinks and the bars reflow, so a larger scale means fewer
    /// bars to a row and more rows.
    static func engrave(_ score: ParsedScore, musicFont: CTFont, scale: CGFloat = 1) -> (Data, Timeline) {
        let sp = baseSpace * scale
        var e = Run(score: score, font: CTFontCreateCopyWithAttributes(musicFont, 4 * sp, nil, nil), sp: sp)
        return e.render()
    }

    private struct ChordGeo {
        var x: CGFloat, w: CGFloat, hi: CGFloat, lo: CGFloat   // hi = smallest y (highest note)
        var mid: CGFloat
        var up: Bool
        var beams: [Int: String]
        var events: Range<Int>
        var sp: CGFloat
        var stemX: CGFloat { up ? x + w - 0.06 * sp : x + 0.06 * sp }
    }

    private struct Run {
        let score: ParsedScore
        let font: CTFont
        var ctx: CGContext!
        var timeline = Timeline()
        let data = NSMutableData()
        var page = -1
        var carried: [(key: String, up: Bool)] = []   // ties running into the next system
        var headEvents: [String: Int] = [:]           // staff|pitch|tick → its event, to join ties for playback
        var tieLinks: [(from: Int, to: String)] = []
        /// The slur open on each staff: where it began (y nil = it came in from the system before).
        var slurs: [Int: (x: CGFloat, y: CGFloat?, above: Bool)] = [:]

        let sp: CGFloat
        let hasLyrics: Bool
        init(score: ParsedScore, font: CTFont, sp: CGFloat) {
            self.score = score; self.font = font; self.sp = sp
            hasLyrics = score.measures.contains { $0.notes.contains { $0.lyric != nil } }
        }

        // MARK: Glyphs

        func glyph(_ cp: UInt16) -> CGGlyph {
            var c = cp, g: CGGlyph = 0
            CTFontGetGlyphsForCharacters(font, &c, &g, 1)
            return g
        }
        func width(_ cp: UInt16) -> CGFloat {
            var g = glyph(cp)
            return CGFloat(CTFontGetAdvancesForGlyphs(font, .horizontal, &g, nil, 1))
        }
        func draw(_ cp: UInt16, _ x: CGFloat, _ y: CGFloat, scaleY: CGFloat = 1, size: CGFloat = 1) {
            var g = glyph(cp), p = CGPoint.zero
            ctx.saveGState()
            ctx.translateBy(x: x, y: y)
            ctx.scaleBy(x: size, y: -scaleY * size)
            ctx.textMatrix = .identity
            CTFontDrawGlyphs(font, &g, &p, 1, ctx)
            ctx.restoreGState()
        }
        func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ t: CGFloat) {
            ctx.setLineWidth(t)
            ctx.strokeLineSegments(between: [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y1)])
        }
        @discardableResult func text(_ s: String, _ font: CTFont, x: CGFloat, y: CGFloat, align: CGFloat = 0) -> CGFloat {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.init(kCTFontAttributeName as String): font, .init(kCTForegroundColorFromContextAttributeName as String): true]))
            let w = CTLineGetTypographicBounds(line, nil, nil, nil)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = CGPoint(x: x - CGFloat(w) * align, y: y)
            CTLineDraw(line, ctx)
            return CGFloat(w)
        }

        // MARK: Layout

        struct MLayout {
            var index: Int
            var count = 1                      // bars folded into one multi-bar rest
            var width: CGFloat = 0
            var prefix: CGFloat = 0
            var onsets: [Int: CGFloat] = [:]   // relative tick → x offset in measure
            var key = 0, time = (4, 4)
            var clefs: [Clef] = []
            var showKey = false, showTime = false
        }

        /// How wide a syllable is as printed.
        func lyricWidth(_ s: String) -> CGFloat {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.init(kCTFontAttributeName as String): CTFontCreateWithName("Baskerville" as CFString, 10.5, nil)]))
            return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }

        func layoutMeasures() -> [MLayout] {
            var clefs = Array(repeating: Clef(), count: score.staffCount)
            var key = 0, time = (4, 4)
            var out: [MLayout] = [], i = 0
            while i < score.measures.count {
                let m = score.measures[i]
                var L = MLayout(index: i)
                for (s, c) in m.clefs where s < clefs.count { clefs[s] = c }
                if let k = m.key, k != key || i == 0 { key = k; L.showKey = i > 0 }
                if let t = m.time, t != time || i == 0 { time = (t.beats, t.type); L.showTime = true }
                L.key = key; L.time = time; L.clefs = clefs
                if L.showKey { L.prefix += keyWidth(key) + sp }
                if m.flow.repeatStart { L.prefix += 1.8 * sp }
                if L.showTime && i > 0 { L.prefix += 2.6 * sp }
                // A run of empty bars with no key/time/clef change inside it is drawn as one bar with a number.
                let n = m.flow.multiRest
                if n > 1, i + n <= score.measures.count, m.notes.allSatisfy({ $0.diatonic == nil }),
                   score.measures[i + 1..<i + n].allSatisfy({ $0.key == nil && $0.time == nil && $0.clefs.isEmpty && $0.notes.allSatisfy { $0.diatonic == nil } }) {
                    L.count = n
                    L.onsets[0] = L.prefix + 1.2 * sp
                    L.width = L.prefix + 6 * sp
                    out.append(L); i += n; continue
                }
                let ticks = Set(m.notes.filter { !$0.hidden || $0.diatonic == nil }.map(\.tick) + [0]).sorted()
                var x = L.prefix + 1.2 * sp
                // The words under the notes need room too: neighbouring syllables must not run into each other.
                let words = ticks.map { t -> CGFloat in m.notes.first { $0.tick == t && $0.diatonic != nil && $0.lyric != nil }?.lyric.map(lyricWidth) ?? 0 }
                for (k, t) in ticks.enumerated() {
                    let gap = Double((k + 1 < ticks.count ? ticks[k + 1] : m.length) - t)
                    if m.notes.contains(where: { $0.tick == t && $0.accidental != nil }) { x += 1.2 * sp }
                    L.onsets[t] = x
                    var advance = sp * (1.4 + 1.6 * CGFloat(max(gap, 60) / 480).squareRoot())
                    if k + 1 < ticks.count, words[k] > 0 || words[k + 1] > 0 { advance = max(advance, (words[k] + words[k + 1]) / 2 + 0.9 * sp) }
                    x += advance
                }
                L.width = x + 0.4 * sp
                out.append(L); i += 1
            }
            return out.map { L in
                var L = L
                if score.measures[L.index + L.count - 1].flow.repeatEnd > 0 { L.width += 1.2 * sp }
                return L
            }
        }

        func headerWidth(_ m: MLayout, first: Bool) -> CGFloat {
            keyX + keyWidth(m.key) + (m.showTime || first ? 3.2 * sp : 0) + sp
        }

        /// Room under each staff for the words, when the music has any.
        var lyricRoom: CGFloat { hasLyrics ? 3.8 * sp : 0 }
        var staffGap: CGFloat { 9 * sp + lyricRoom }
        var systemHeight: CGFloat { CGFloat(score.staffCount) * 4 * sp + CGFloat(score.staffCount - 1) * staffGap }

        mutating func render() -> (Data, Timeline) {
            var box = CGRect(origin: .zero, size: pageSize)
            ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
            let measures = layoutMeasures()
            let avail = pageSize.width - 2 * margin

            // Greedy line breaking.
            var systems: [[MLayout]] = [], current: [MLayout] = []
            for m in measures {
                var head = headerWidth(current.first ?? m, first: systems.isEmpty)
                if current.isEmpty { head = headerWidth(m, first: systems.isEmpty) }
                let used = head + current.reduce(0) { $0 + $1.width } + m.width
                if !current.isEmpty && used > avail { systems.append(current); current = [] }
                current.append(m)
            }
            if !current.isEmpty { systems.append(current) }

            var y = pageSize.height // forces a new page
            for (si, sys) in systems.enumerated() {
                if y + systemHeight + 2 * sp > pageSize.height - margin {
                    newPage()
                    y = margin + 2 * sp
                    if page == 0 { y += titleBlock() }
                }
                let head = headerWidth(sys[0], first: si == 0)
                let natural = sys.reduce(0) { $0 + $1.width }
                var stretch = (avail - head) / natural
                if si == systems.count - 1 && stretch > 1.5 { stretch = 1 }
                drawSystem(sys, index: si, top: y, header: head, stretch: stretch, first: si == 0)
                y += systemHeight + 10 * sp + lyricRoom
            }
            ctx.endPDFPage()
            ctx.closePDF()
            // Tempo changes slow or quicken the bars from the mark on, relative to the opening tempo.
            let base = score.tempo ?? score.measures.compactMap(\.tempo).first
            let ratios = score.measures.map { m in base.flatMap { b in m.tempo.map { b / max($0, 1) } } }
            // How loud each note is, from the dynamics and hairpins.
            let factor = Dynamics.factor(for: score)
            for i in timeline.notes.indices where timeline.notes[i].pitch != nil { timeline.notes[i].velocity = factor(Int((timeline.notes[i].start * 480).rounded())) }
            // A tied note sounds once, for the length of the whole chain; the later heads stay on the page but stay quiet.
            var root: [Int: Int] = [:]
            for link in tieLinks.sorted(by: { timeline.notes[$0.from].start < timeline.notes[$1.from].start }) {
                guard let tail = headEvents[link.to], tail != link.from else { continue }
                let head = root[link.from] ?? link.from
                timeline.notes[head].duration += timeline.notes[tail].duration
                timeline.notes[tail].pitch = nil
                root[tail] = head
            }
            return (data as Data, timeline.unfolded(score.playOrder, tempoRatios: ratios))
        }

        mutating func newPage() {
            if page >= 0 { ctx.endPDFPage() }
            ctx.beginPDFPage(nil)
            ctx.translateBy(x: 0, y: pageSize.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.setFillColor(gray: 0.08, alpha: 1)
            ctx.setStrokeColor(gray: 0.08, alpha: 1)
            ctx.setLineCap(.butt)
            page += 1
        }

        func titleBlock() -> CGFloat {
            let title = CTFontCreateWithName("Baskerville-SemiBold" as CFString, 24, nil)
            let small = CTFontCreateWithName("Baskerville-Italic" as CFString, 11, nil)
            text(score.title.isEmpty ? "Untitled" : score.title, title, x: pageSize.width / 2, y: margin + 6, align: 0.5)
            if !score.composer.isEmpty { text(score.composer, small, x: pageSize.width - margin, y: margin + 30, align: 1) }
            return 44
        }

        func staffTop(_ top: CGFloat, _ s: Int) -> CGFloat { top + CGFloat(s) * (4 * sp + staffGap) }
        func yFor(pos: Int, staffTop: CGFloat) -> CGFloat { staffTop + CGFloat(8 - pos) * sp / 2 }

        // MARK: System

        /// Repeat barline at a bar's left (`forward`) or right edge: thick and thin line, two dots.
        func drawRepeat(_ x: CGFloat, forward: Bool, top: CGFloat) {
            let d: CGFloat = forward ? 1 : -1
            for s in 0..<score.staffCount {
                let t = staffTop(top, s)
                line(x + d * 0.25 * sp, t, x + d * 0.25 * sp, t + 4 * sp, 0.5 * sp)
                line(x + d * 1.0 * sp, t, x + d * 1.0 * sp, t + 4 * sp, 0.16 * sp)
                for y in [1.5, 2.5] { ctx.fillEllipse(in: CGRect(x: x + d * 1.75 * sp - 0.2 * sp, y: t + y * sp - 0.2 * sp, width: 0.4 * sp, height: 0.4 * sp)) }
            }
            let t = staffTop(top, 0), b = staffTop(top, score.staffCount - 1) + 4 * sp
            if score.staffCount > 1 { line(x + d * 0.25 * sp, t, x + d * 0.25 * sp, b, 0.5 * sp) }
        }

        mutating func drawSystem(_ sys: [MLayout], index si: Int, top: CGFloat, header: CGFloat, stretch: CGFloat, first: Bool) {
            let n = score.staffCount
            let left = margin, bottom = staffTop(top, n - 1) + 4 * sp
            var right = left + header
            for m in sys { right += m.width * stretch }

            // Staves, system bracket, braces.
            for s in 0..<n {
                let t = staffTop(top, s)
                for l in 0..<5 { line(left, t + CGFloat(l) * sp, right, t + CGFloat(l) * sp, 0.13 * sp) }
            }
            if n > 1 { line(left, top, left, bottom, 0.16 * sp) }
            for r in score.braces {
                let t = staffTop(top, r.lowerBound), b = staffTop(top, r.upperBound - 1) + 4 * sp
                draw(0xE000, left - 0.4 * sp - width(0xE000) * (b - t) / (4 * sp), b, scaleY: (b - t) / (4 * sp))
            }
            timeline.systems.append(SystemMark(page: page, rect: CGRect(x: left - 6, y: top - 3.5 * sp, width: right - left + 12, height: bottom - top + 7 * sp)))
            if sys[0].index > 0 {
                text("\(sys[0].index + 1)", CTFontCreateWithName("Baskerville-Italic" as CFString, 9, nil), x: left, y: top - 1.6 * sp)
            }

            // Header: clef, key, time.
            let m0 = sys[0]
            for s in 0..<n {
                let t = staffTop(top, s), c = m0.clefs[s]
                let cp: UInt16 = c.sign == "F" ? 0xE062 : c.sign == "C" ? 0xE05C : 0xE050
                draw(cp, left + 0.8 * sp, yFor(pos: 2 * (c.line - 1), staffTop: t))
                drawKey(m0.key, clef: c, x: left + keyX, staffTop: t)
                if m0.showTime || first { drawTime(m0.time, x: left + keyX + keyWidth(m0.key) + (m0.key != 0 ? 0.4 * sp : 0), staffTop: t) }
            }

            var pending: [(key: String, x: CGFloat, y: CGFloat, up: Bool)] = [] // ties never cross systems
            var heads: [String: (x: CGFloat, y: CGFloat)] = [:]
            var x = left + header
            for (k, L) in sys.enumerated() {
                let m = score.measures[L.index]
                let w = L.width * stretch
                // Mid-system key/time changes.
                for s in 0..<n {
                    let t = staffTop(top, s)
                    if L.showKey && k > 0 { drawKey(L.key, clef: L.clefs[s], x: x + 0.5 * sp, staffTop: t) }
                    if L.showTime && k > 0 { drawTime(L.time, x: x + 0.5 * sp + (L.showKey ? keyWidth(L.key) + sp : 0), staffTop: t) }
                }
                let ox: (Int) -> CGFloat = { x + L.prefix + ((L.onsets[$0] ?? 0) - L.prefix) * stretch }
                if L.count > 1 {
                    // Bar count, centred in the staff like a time signature.
                    let digits = Array(String(L.count).utf8).map { UInt16(0xE080 + Int($0) - 48) }
                    let tw = digits.reduce(0) { $0 + width($1) }
                    for s in 0..<n {
                        var dx = x + L.prefix + (w - L.prefix - tw) / 2
                        for d in digits { draw(d, dx, yFor(pos: 4, staffTop: staffTop(top, s))); dx += width(d) }
                    }
                } else {
                    pending += drawNotes(m, L, top: top, ox: ox, measureX: x, measureW: w, heads: &heads)
                }
                for mark in m.marks where mark.staff < n {
                    let tick = L.onsets.keys.filter { $0 <= mark.tick }.max() ?? 0
                    let st = staffTop(top, mark.staff)
                    if mark.dynamic {
                        var dx = ox(tick) - 0.3 * sp
                        for ch in mark.text {
                            guard let i = "pmfrszn".firstIndex(of: ch) else { continue }
                            let cp = UInt16(0xE520 + "pmfrszn".distance(from: "pmfrszn".startIndex, to: i))
                            draw(cp, dx, st + 7.4 * sp)   // clear of stems hanging below the staff
                            dx += width(cp)
                        }
                    } else {
                        text(mark.text, CTFontCreateWithName("Baskerville-Italic" as CFString, 10.5, nil), x: ox(tick), y: st - 2.2 * sp)
                    }
                }

                // Crescendo and diminuendo hairpins that pass through this bar.
                for (j, h) in score.measures.enumerated().flatMap({ j, m in m.hairpins.map { (j, $0) } }) where j <= L.index && L.index <= j + h.span && h.staff < n {
                    let first = score.measures[j], last = score.measures[min(j + h.span, score.measures.count - 1)]
                    let from = first.start + h.startTick, to = max(from + 1, last.start + h.endTick)
                    func xAt(_ tick: Int) -> CGFloat { ox(L.onsets.keys.filter { $0 <= tick }.max() ?? 0) }
                    let x0 = j == L.index ? xAt(h.startTick) : x + L.prefix + 0.2 * sp
                    let x1 = L.index == j + h.span && h.endTick < m.length ? xAt(h.endTick) : x + w - 0.3 * sp
                    guard x1 > x0 + 0.5 * sp else { continue }
                    let f0 = Double(max(0, m.start + (j == L.index ? h.startTick : 0) - from)) / Double(to - from)
                    let f1 = Double(min(to, m.start + (L.index == j + h.span ? h.endTick : m.length)) - from) / Double(to - from)
                    let yc = staffTop(top, h.staff) + 7.0 * sp, open = 0.8 * sp
                    func spread(_ f: Double) -> CGFloat { open * CGFloat(h.crescendo ? f : 1 - f) }
                    line(x0, yc - spread(f0), x1, yc - spread(f1), 0.1 * sp)
                    line(x0, yc + spread(f0), x1, yc + spread(f1), 0.1 * sp)
                }

                // Octave-shift lines (8va) and the pedal.
                for (j, sp0) in score.measures.enumerated().flatMap({ j, m in m.spans.map { (j, $0) } }) where j <= L.index && L.index <= j + sp0.span && sp0.staff < n {
                    func xAt(_ tick: Int) -> CGFloat { ox(L.onsets.keys.filter { $0 <= tick }.max() ?? 0) }
                    let st = staffTop(top, sp0.staff), begins = j == L.index, ends = L.index == j + sp0.span
                    if sp0.kind == "pedal" {
                        if begins { draw(0xE650, xAt(sp0.startTick), st + 8.6 * sp) }
                        if ends { draw(0xE655, ends && sp0.endTick < m.length ? xAt(sp0.endTick) : x + w - 1.2 * sp, st + 8.6 * sp) }
                        continue
                    }
                    let below = sp0.kind.hasSuffix("b"), yl = below ? st + 6.3 * sp : st - 2.9 * sp
                    let x0 = begins ? xAt(sp0.startTick) : x + L.prefix + 0.2 * sp
                    let x1 = ends && sp0.endTick < m.length ? xAt(sp0.endTick) : x + w - 0.3 * sp
                    let label = sp0.kind == "pedal" ? "" : sp0.kind
                    if begins || k == 0 { text(label, CTFontCreateWithName("Baskerville-Italic" as CFString, 10.5, nil), x: x0, y: yl + 0.4 * sp) }
                    let lx = (begins || k == 0) ? x0 + CGFloat(label.count) * 0.95 * sp + 0.3 * sp : x0
                    guard x1 > lx else { continue }
                    ctx.saveGState()
                    ctx.setLineDash(phase: 0, lengths: [0.9 * sp, 0.6 * sp])
                    line(lx, yl, x1, yl, 0.09 * sp)
                    ctx.restoreGState()
                    if ends { line(x1, yl, x1, yl + (below ? -0.9 : 0.9) * sp, 0.09 * sp) }
                }

                // Barline.
                let bx = x + w
                let last = score.measures[L.index + L.count - 1]
                if m.flow.repeatStart { drawRepeat(x, forward: true, top: top) }
                if last.flow.repeatEnd > 0 {
                    drawRepeat(bx, forward: false, top: top)
                } else if last.finalBar || L.index + L.count == score.measures.count {
                    line(bx - 1.0 * sp, top, bx - 1.0 * sp, bottom, 0.16 * sp)
                    line(bx - 0.25 * sp, top, bx - 0.25 * sp, bottom, 0.5 * sp)
                } else {
                    line(bx, top, bx, bottom, 0.16 * sp)
                }

                // A printed tempo (♩ = 96).
                if m.tempoShown, let bpm = m.tempo {
                    let tx = x + L.prefix + 0.4 * sp, ty = top - 4.6 * sp
                    draw(0xE1D5, tx, ty)
                    text("= \(Int(bpm.rounded()))", CTFontCreateWithName("Baskerville-Bold" as CFString, 10.5, nil), x: tx + width(0xE1D5) + 0.3 * sp, y: ty)
                }

                // Segno and coda signs.
                if m.flow.segno { draw(0xE047, x + L.prefix + 0.4 * sp, top - 3.0 * sp) }
                if m.flow.coda { draw(0xE048, x + L.prefix + 0.4 * sp, top - 3.0 * sp) }
                if m.flow.toCoda { draw(0xE048, bx - width(0xE048) - 0.5 * sp, top - 4.4 * sp) }   // "To ⊕" at the bar's end

                // First/second ending bracket.
                if !m.flow.endings.isEmpty {
                    let y = top - 5.2 * sp, fresh = L.index == 0 || score.measures[L.index - 1].flow.endings != m.flow.endings
                    line(x + (fresh ? 0.3 * sp : 0), y, bx, y, 0.1 * sp)
                    if fresh {
                        line(x + 0.3 * sp, y, x + 0.3 * sp, y + 1.5 * sp, 0.1 * sp)
                        text(m.flow.endings.map(String.init).joined(separator: ",") + ".", CTFontCreateWithName("Baskerville" as CFString, 9, nil), x: x + 0.7 * sp, y: y + 1.3 * sp)
                    }
                }

                // Timing marks (a multi-bar rest still gets one per bar).
                for j in 0..<L.count {
                    let mj = score.measures[L.index + j]
                    let start = Double(mj.start) / 480, dur = Double(mj.length) / 480
                    let x0 = x + w * CGFloat(j) / CGFloat(L.count), x1 = x + w * CGFloat(j + 1) / CGFloat(L.count)
                    var anchors = L.count > 1 ? [(beat: start, x: x0 + 0.5 * sp)] : L.onsets.keys.sorted().map { (beat: start + Double($0) / 480, x: ox($0) - 0.4 * sp) }
                    if anchors.first?.beat ?? 1 > start { anchors.insert((start, x0 + 0.5 * sp), at: 0) }
                    anchors.append((start + dur, x1))
                    timeline.measures.append(MeasureMark(start: start, duration: dur, system: timeline.systems.count - 1, bar: L.index + j, x0: x0, x1: x1, anchors: anchors))
                }
                x = bx
            }

            // A slur still open at the end of the row runs off the edge and picks up again on the next.
            for (s, o) in slurs where s < n {
                let y = o.y ?? staffTop(top, s) + (o.above ? -0.5 : 4.5) * sp
                drawSlur(from: o.x, y, to: right, y, above: o.above)
                slurs[s] = (left + header, nil, o.above)
            }

            // Ties: finish those carried in, draw within the system, and half-ties off the end.
            for c in carried { if let end = heads[c.key] { drawTie(from: left + header - 1.4 * sp, to: end.x, y: end.y, above: !c.up) } }
            carried = []
            for t in pending {
                if let end = heads[t.key] {
                    drawTie(from: t.x, to: end.x, y: t.y, above: !t.up)
                } else {
                    drawTie(from: t.x, to: right + 0.6 * sp, y: t.y, above: !t.up)
                    carried.append((t.key, t.up))
                }
            }
        }

        /// Key signatures sit clear of the clef, with a little air between accidentals.
        var keyX: CGFloat { 4.0 * sp }
        var keyStep: CGFloat { 1.15 * sp }
        func keyWidth(_ fifths: Int) -> CGFloat { CGFloat(abs(fifths)) * keyStep }

        func drawKey(_ fifths: Int, clef: Clef, x: CGFloat, staffTop: CGFloat) {
            guard fifths != 0 else { return }
            var shift = ((30 - clef.bottom) % 7 + 7) % 7
            if shift > 3 { shift -= 7 }
            let sharps = [8, 5, 9, 6, 3, 7, 4], flats = [4, 7, 3, 6, 2, 5, 1]
            for i in 0..<min(abs(fifths), 7) {
                let pos = (fifths > 0 ? sharps : flats)[i] + shift
                draw(fifths > 0 ? 0xE262 : 0xE260, x + CGFloat(i) * keyStep, yFor(pos: pos, staffTop: staffTop))
            }
        }

        func drawTime(_ t: (Int, Int), x: CGFloat, staffTop: CGFloat) {
            for (v, pos) in [(t.0, 6), (t.1, 2)] {
                let digits = String(v).compactMap { $0.wholeNumberValue }
                let w = digits.reduce(0) { $0 + width(UInt16(0xE080 + $1)) }
                var dx = x + (2 * sp - w) / 2
                for d in digits { draw(UInt16(0xE080 + d), dx, yFor(pos: pos, staffTop: staffTop)); dx += width(UInt16(0xE080 + d)) }
            }
        }

        /// A slur: a thin crescent between two note heads, bowing away from the stems.
        func drawSlur(from x0: CGFloat, _ y0: CGFloat, to x1: CGFloat, _ y1: CGFloat, above: Bool) {
            guard x1 > x0 + 0.5 * sp else { return }
            let d: CGFloat = above ? -1 : 1
            let h = min(3 * sp, 0.9 * sp + (x1 - x0) * 0.07), mx = (x0 + x1) / 2, my = (y0 + y1) / 2
            ctx.move(to: CGPoint(x: x0, y: y0))
            ctx.addQuadCurve(to: CGPoint(x: x1, y: y1), control: CGPoint(x: mx, y: my + d * 2 * h))
            ctx.addQuadCurve(to: CGPoint(x: x0, y: y0), control: CGPoint(x: mx, y: my + d * (2 * h - 0.6 * sp)))
            ctx.fillPath()
        }

        func drawTie(from x0: CGFloat, to x1: CGFloat, y: CGFloat, above: Bool) {
            let d: CGFloat = above ? -1 : 1
            let a = CGPoint(x: x0, y: y + d * 0.6 * sp), b = CGPoint(x: x1, y: y + d * 0.6 * sp)
            let mx = (x0 + x1) / 2, h = min(1.6 * sp, 0.6 * sp + (x1 - x0) * 0.06)
            ctx.move(to: a)
            ctx.addQuadCurve(to: b, control: CGPoint(x: mx, y: a.y + d * h))
            ctx.addQuadCurve(to: a, control: CGPoint(x: mx, y: a.y + d * (h - 0.35 * sp)))
            ctx.fillPath()
        }

        // MARK: Notes

        mutating func drawNotes(_ m: PMeasure, _ L: MLayout, top: CGFloat, ox: (Int) -> CGFloat, measureX: CGFloat, measureW: CGFloat, heads: inout [String: (x: CGFloat, y: CGFloat)]) -> [(key: String, x: CGFloat, y: CGFloat, up: Bool)] {
            var ties: [(key: String, x: CGFloat, y: CGFloat, up: Bool)] = []
            // Group into chords keeping document order.
            var order: [String] = [], chords: [String: [Int]] = [:]
            for (i, note) in m.notes.enumerated() {
                let key = "\(note.staff)|\(note.voice)|\(note.tick)"
                if chords[key] == nil { order.append(key) }
                chords[key, default: []].append(i)
            }
            var beamGroups: [String: [ChordGeo]] = [:]
            // Where each tuplet note or rest sits, to bracket the groups afterwards.
            var tupletMarks: [(lane: String, tick: Int, actual: Int, x0: CGFloat, x1: CGFloat, y: CGFloat, st: CGFloat)] = []

            // Grace notes: small slashed notes just before their main note; they sound a hair early and take no time.
            for g in m.graces where g.staff < score.staffCount {
                let st = staffTop(top, g.staff), clef = L.clefs[min(g.staff, L.clefs.count - 1)]
                let siblings = m.graces.filter { $0.tick == g.tick && $0.staff == g.staff }
                let nth = siblings.firstIndex(of: g) ?? 0, behind = CGFloat(siblings.count - nth)
                let main = L.onsets.keys.filter { $0 <= g.tick }.max() ?? 0
                let small: CGFloat = 0.65, hw = width(0xE0A4) * small
                let hasAcc = g.alter != ParsedScore.keyAlter(L.key, g.diatonic.mod(7))
                let gx = ox(main) - behind * (1.7 * sp) - (hasAcc ? 0.5 * sp : 0)
                let pos = g.diatonic - clef.bottom, y = yFor(pos: pos, staffTop: st)
                if hasAcc {
                    let cp: UInt16 = g.alter > 0 ? 0xE262 : g.alter < 0 ? 0xE260 : 0xE261
                    draw(cp, gx - width(cp) * small - 0.15 * sp, y, size: small)
                }
                for p in (pos < -1 ? Array(stride(from: -2, through: pos, by: -2)) : []) + (pos > 9 ? Array(stride(from: 10, through: pos, by: 2)) : []) {
                    let ly = yFor(pos: p, staffTop: st); line(gx - 0.3 * sp, ly, gx + hw + 0.3 * sp, ly, 0.14 * sp)
                }
                draw(0xE0A4, gx, y, size: small)
                let sx = gx + hw - 0.04 * sp, tip = y - 2.6 * sp
                line(sx, y - 0.1 * sp, sx, tip, 0.1 * sp)
                draw(0xE240, sx - 0.04 * sp, tip, size: small)
                if g.slash { line(sx - 0.7 * sp, tip + 1.0 * sp, sx + 0.9 * sp, tip + 0.1 * sp, 0.09 * sp) }
                var e = NoteEvent(id: timeline.notes.count, start: Double(m.start + g.tick) / 480, duration: 0.1, page: page,
                                  rect: CGRect(x: gx - 0.2 * sp, y: y - 0.6 * sp, width: hw + 0.4 * sp, height: 1.2 * sp), pitch: ParsedScore.midi(diatonic: g.diatonic, alter: g.alter))
                e.staff = g.staff; e.grace = true; e.lead = 0.1 * Double(behind)
                timeline.notes.append(e)
            }

            for key in order {
                let indices = chords[key]!
                let notes = indices.map { m.notes[$0] }
                let first = notes[0], s = first.staff
                let st = staffTop(top, s), clef = L.clefs[min(s, L.clefs.count - 1)]
                let mid = yFor(pos: 4, staffTop: st)
                var x = ox(first.tick)

                // Rests.
                if first.diatonic == nil {
                    if first.hidden { continue }
                    if first.tuplet > 1 { tupletMarks.append(("\(s)|\(first.voice)", first.tick, first.tuplet, x, x + 1.4 * sp, st + 1.2 * sp, st)) }
                    let restInfo = EditInfo(measure: L.index, index: indices[0], staff: s, top: st, space: sp, clefBottom: clef.bottom)
                    func restEvent(_ r: CGRect) {
                        var e = NoteEvent(id: timeline.notes.count, start: Double(m.start + first.tick) / 480, duration: Double(first.duration) / 480, page: page, rect: r, pitch: nil)
                        e.isRest = true; e.edit = restInfo
                        timeline.notes.append(e)
                    }
                    if first.measureRest || first.duration >= m.length && first.type == "whole" {
                        let w = width(0xE4E3)
                        draw(0xE4E3, measureX + (measureW - w) / 2, yFor(pos: 6, staffTop: st))
                        restEvent(CGRect(x: measureX + measureW / 2 - 1.5 * sp, y: st + 0.5 * sp, width: 3 * sp, height: 3 * sp))
                        continue
                    }
                    let cp: UInt16 = switch first.type {
                    case "whole": 0xE4E3
                    case "half": 0xE4E4
                    case "eighth": 0xE4E6
                    case "16th": 0xE4E7
                    case "32nd": 0xE4E8
                    default: 0xE4E5
                    }
                    draw(cp, x, yFor(pos: first.type == "whole" ? 6 : 4, staffTop: st))
                    drawDots(first.dots, x: x + width(cp), pos: 5, staffTop: st)
                    restEvent(CGRect(x: x - 0.4 * sp, y: st + 0.4 * sp, width: width(cp) + 0.8 * sp, height: 3.2 * sp))
                    continue
                }

                let pitched = notes.filter { $0.diatonic != nil && !$0.hidden }
                let pitchedIndices = indices.filter { m.notes[$0].diatonic != nil && !m.notes[$0].hidden }
                guard !pitched.isEmpty else { continue }
                let headCP: UInt16 = first.type == "whole" || first.type == "breve" ? 0xE0A2 : first.type == "half" ? 0xE0A3 : 0xE0A4
                let w = width(headCP)
                let positions = pitched.map { $0.diatonic! - clef.bottom }
                let (minP, maxP) = (positions.min()!, positions.max()!)
                let up: Bool = first.stem.map { $0 == "up" } ?? ((minP + maxP) < 8)
                if headCP == 0xE0A2 { x -= 0.25 * sp }

                // Accidentals, staggered left in a crowded chord.
                var accRow = 0
                for (note, pos) in zip(pitched, positions).sorted(by: { $0.1 > $1.1 }) {
                    guard let acc = note.accidental else { continue }
                    let cp: UInt16 = switch acc {
                    case "sharp": 0xE262
                    case "flat": 0xE260
                    case "natural": 0xE261
                    case "double-sharp": 0xE263
                    case "flat-flat": 0xE264
                    default: 0
                    }
                    guard cp != 0 else { continue }
                    let aw = width(cp)
                    draw(cp, x - aw - 0.3 * sp - CGFloat(accRow % 2) * (aw + 0.2 * sp), yFor(pos: pos, staffTop: st))
                    accRow += 1
                }

                // Ledger lines.
                let lw = w + 0.8 * sp
                if minP < -1 { for p in stride(from: -2, through: minP, by: -2) { let y = yFor(pos: p, staffTop: st); line(x - 0.4 * sp, y, x - 0.4 * sp + lw, y, 0.16 * sp) } }
                if maxP > 9 { for p in stride(from: 10, through: maxP, by: 2) { let y = yFor(pos: p, staffTop: st); line(x - 0.4 * sp, y, x - 0.4 * sp + lw, y, 0.16 * sp) } }

                // Heads, dots, events.
                let firstEvent = timeline.notes.count
                for (k, (note, pos)) in zip(pitched, positions).enumerated() {
                    let y = yFor(pos: pos, staffTop: st)
                    draw(headCP, x, y)
                    drawDots(note.dots, x: x + w, pos: pos, staffTop: st)
                    let abs = m.start + note.tick
                    timeline.notes.append(NoteEvent(id: timeline.notes.count, start: Double(abs) / 480, duration: Double(note.duration) / 480, page: page,
                                                    rect: CGRect(x: x - 0.35 * sp, y: y - 0.85 * sp, width: w + 0.7 * sp, height: 1.7 * sp),
                                                    pitch: ParsedScore.midi(diatonic: note.diatonic!, alter: note.alter)))
                    timeline.notes[timeline.notes.count - 1].staff = s
                    timeline.notes[timeline.notes.count - 1].edit = EditInfo(measure: L.index, index: pitchedIndices[k], staff: s, top: st, space: sp, clefBottom: clef.bottom)
                    let tieKey = "\(s)|\(note.diatonic!)|\(abs + note.duration)"
                    heads["\(s)|\(note.diatonic!)|\(abs)"] = (x - 0.15 * sp, y)
                    headEvents["\(s)|\(note.diatonic!)|\(abs)"] = timeline.notes.count - 1
                    if note.tieStart { ties.append((tieKey, x + w + 0.15 * sp, y, up)); tieLinks.append((timeline.notes.count - 1, tieKey)) }
                }
                if let n = pitched.first(where: { $0.lyricText != nil }) { timeline.notes[firstEvent].lyric = n.lyricText; timeline.notes[firstEvent].syllabic = n.syllabic }

                let hi = yFor(pos: maxP, staffTop: st), lo = yFor(pos: minP, staffTop: st)
                let cx = x + w / 2
                if first.tuplet > 1 { tupletMarks.append(("\(s)|\(first.voice)", first.tick, first.tuplet, x, x + w, up ? hi - 3.5 * sp : hi, st)) }
                // Slurs: one per staff; it opens at a note that starts it and closes at the note that stops it.
                let slurAbove = !up
                if pitched.contains(where: \.slurStop), let o = slurs.removeValue(forKey: s) {
                    let ey = o.above ? hi - 0.8 * sp : lo + 0.8 * sp
                    drawSlur(from: o.x, o.y ?? ey, to: cx, ey, above: o.above)
                }
                if pitched.contains(where: \.slurStart) { slurs[s] = (cx, slurAbove ? hi - 0.8 * sp : lo + 0.8 * sp, slurAbove) }

                if pitched.contains(where: { $0.articulations.contains("arpeggiate") }) {
                    let ax = x - (accRow > 0 ? 2.6 : 1.3) * sp
                    var yy = lo + 0.4 * sp
                    while yy > hi - 0.5 * sp { draw(0xE63C, ax, yy); yy -= 1.0 * sp }
                }
                var stackAbove = hi - 0.9 * sp, stackBelow = lo + 0.9 * sp
                var topRow = min(st - 1.2 * sp, hi - 2 * sp)
                let small = CTFontCreateWithName("Baskerville-Italic" as CFString, 8.5, nil)
                for a in Set(pitched.flatMap(\.articulations)).sorted() {
                    if a == "fermata" {
                        draw(0xE4C0, cx - width(0xE4C0) / 2, topRow)
                        topRow -= 1.6 * sp
                        continue
                    }
                    let ornament: [String: UInt16] = ["trill-mark": 0xE566, "turn": 0xE567, "inverted-turn": 0xE568, "delayed-turn": 0xE567,
                                                      "mordent": 0xE56D, "inverted-mordent": 0xE56C, "shake": 0xE566]
                    if let cp = ornament[a] {
                        draw(cp, cx - width(cp) / 2, topRow)
                        topRow -= 1.3 * sp
                        continue
                    }
                    if a == "breath-mark" { draw(0xE4CE, x + w + 0.9 * sp, yFor(pos: 9, staffTop: st) + 0.2 * sp); continue }
                    if a == "caesura" { draw(0xE4D1, x + w + 0.7 * sp, yFor(pos: 6, staffTop: st)); continue }
                    if a.hasPrefix("finger:") {
                        if up { text(String(a.dropFirst(7)), small, x: cx, y: stackBelow + 0.9 * sp, align: 0.5); stackBelow += 1.1 * sp }
                        else { text(String(a.dropFirst(7)), small, x: cx, y: stackAbove - 0.2 * sp, align: 0.5); stackAbove -= 1.1 * sp }
                        continue
                    }
                    let pair: [String: (UInt16, UInt16)] = ["staccato": (0xE4A2, 0xE4A3), "accent": (0xE4A0, 0xE4A1), "tenuto": (0xE4A4, 0xE4A5),
                                                            "strong-accent": (0xE4AC, 0xE4AD), "staccatissimo": (0xE4A6, 0xE4A7)]
                    guard let cp = pair[a] else { continue }
                    if up {   // marks go on the notehead side, away from the stem
                        draw(cp.1, cx - width(cp.1) / 2, stackBelow); stackBelow += 0.9 * sp
                    } else {
                        draw(cp.0, cx - width(cp.0) / 2, stackAbove); stackAbove -= 0.9 * sp
                    }
                }
                if let lyric = pitched.first(where: { $0.lyric != nil })?.lyric {
                    // Under the dynamics and the pedal, in a row of its own (the rows of staves are spaced out to make room).
                    // In the middle of the gap below this staff (between it and the next staff or system), not up against either.
                    let gapBelow = s == score.staffCount - 1 ? 10 * sp + lyricRoom : staffGap
                    let ly = st + 4 * sp + gapBelow / 2 + 0.4 * sp
                    let w = text(lyric, CTFontCreateWithName("Baskerville" as CFString, 10.5, nil), x: cx, y: ly, align: 0.5)
                    timeline.notes[firstEvent].lyricRect = CGRect(x: cx - w / 2 - 2.5, y: ly - 9.5, width: w + 5, height: 13)
                }

                guard headCP != 0xE0A2 else { continue }
                let geo = ChordGeo(x: x, w: w, hi: hi, lo: lo, mid: mid, up: up, beams: first.beams, events: firstEvent..<timeline.notes.count, sp: sp)
                let groupKey = "\(s)|\(first.voice)"
                if let b = first.beams[1] {
                    beamGroups[groupKey, default: []].append(geo)
                    if b == "end" { drawBeamGroup(beamGroups.removeValue(forKey: groupKey)!) }
                    continue
                }
                // Plain stem + flag.
                let tip = up ? min(hi - 3.5 * sp, mid) : max(lo + 3.5 * sp, mid)
                line(geo.stemX, up ? lo - 0.17 * sp : hi + 0.17 * sp, geo.stemX, tip, 0.12 * sp)
                let flags = ["eighth": 0, "16th": 1, "32nd": 2][first.type]
                if let f = flags { draw(UInt16(0xE240 + f * 2 + (up ? 0 : 1)), geo.stemX - 0.06 * sp, tip) }
                setStem(geo.events, x: geo.stemX, from: up ? lo : hi, to: tip, flag: flags != nil)
            }
            for (_, g) in beamGroups where !g.isEmpty { drawBeamGroup(g) } // unterminated groups
            drawTuplets(tupletMarks)
            return ties
        }

        /// A bracket and number over each run of tuplet notes (a 3 over three triplet notes).
        func drawTuplets(_ marks: [(lane: String, tick: Int, actual: Int, x0: CGFloat, x1: CGFloat, y: CGFloat, st: CGFloat)]) {
            for (_, lane) in Dictionary(grouping: marks, by: \.lane) {
                let sorted = lane.sorted { $0.tick < $1.tick }
                var i = 0
                while i < sorted.count {
                    var group = [sorted[i]]
                    var j = i
                    while group.count < sorted[i].actual, j + 1 < sorted.count, sorted[j + 1].actual == sorted[i].actual { j += 1; group.append(sorted[j]) }
                    i = j + 1
                    guard group.count > 1 else { continue }
                    let x0 = group.map(\.x0).min()! - 0.2 * sp, x1 = group.map(\.x1).max()! + 0.2 * sp
                    let y = min(group.map(\.y).min()! - 1.0 * sp, group[0].st - 1.4 * sp)
                    let mid = (x0 + x1) / 2, gap = 0.9 * sp, t = 0.1 * sp
                    line(x0, y, mid - gap, y, t); line(mid + gap, y, x1, y, t)
                    line(x0, y, x0, y + 0.8 * sp, t); line(x1, y, x1, y + 0.8 * sp, t)
                    text("\(group[0].actual)", CTFontCreateWithName("Baskerville-BoldItalic" as CFString, 10, nil), x: mid, y: y + 0.35 * sp, align: 0.5)
                }
            }
        }

        mutating func setStem(_ events: Range<Int>, x: CGFloat, from y0: CGFloat, to y1: CGFloat, flag: Bool) {
            let r = CGRect(x: x - 0.25 * sp, y: min(y0, y1), width: (flag ? 1.6 : 0.5) * sp, height: abs(y1 - y0))
            for i in events { timeline.notes[i].stem = r }
        }

        func drawDots(_ n: Int, x: CGFloat, pos: Int, staffTop: CGFloat) {
            let p = pos % 2 == 0 ? pos + 1 : pos
            for i in 0..<n { draw(0xE1E7, x + 0.35 * sp + CGFloat(i) * 0.6 * sp, yFor(pos: p, staffTop: staffTop)) }
        }

        mutating func drawBeamGroup(_ raw: [ChordGeo]) {
            guard raw.count > 1 else {
                if let c = raw.first {
                    let tip = c.up ? c.hi - 3.5 * sp : c.lo + 3.5 * sp
                    line(c.stemX, c.up ? c.lo : c.hi, c.stemX, tip, 0.12 * sp)
                    setStem(c.events, x: c.stemX, from: c.up ? c.lo : c.hi, to: tip, flag: false)
                }
                return
            }
            let avg = raw.reduce(0) { $0 + ($1.hi + $1.lo) / 2 - $1.mid } / CGFloat(raw.count)
            let up = avg > 0
            let g = raw.map { var c = $0; c.up = up; return c }
            let tips = g.map { up ? $0.hi - 3.5 * sp : $0.lo + 3.5 * sp }
            let (a, b) = (g.first!, g.last!)
            let slope = max(-0.12, min(0.12, (tips.last! - tips.first!) / max(b.stemX - a.stemX, 1)))
            var y0 = tips.first!
            let lineAt: (CGFloat, CGFloat) -> CGFloat = { y0, x in y0 + slope * (x - a.stemX) }
            for (c, t) in zip(g, tips) {
                let d = lineAt(y0, c.stemX) - t
                if up && d > 0 { y0 -= d }
                if !up && d < 0 { y0 -= d }
            }
            for c in g {
                line(c.stemX, up ? c.lo - 0.17 * sp : c.hi + 0.17 * sp, c.stemX, lineAt(y0, c.stemX), 0.12 * sp)
                // Stop short of the beam: it belongs to the whole group, not this note.
                setStem(c.events, x: c.stemX, from: up ? c.lo : c.hi, to: lineAt(y0, c.stemX) + (up ? 0.6 : -0.6) * sp, flag: false)
            }
            let thick = 0.5 * sp, dir: CGFloat = up ? 1 : -1
            func beam(_ x0: CGFloat, _ x1: CGFloat, level: Int) {
                let off = CGFloat(level - 1) * 0.75 * sp * dir
                let ya = lineAt(y0, x0) + off, yb = lineAt(y0, x1) + off
                ctx.move(to: CGPoint(x: x0, y: ya)); ctx.addLine(to: CGPoint(x: x1, y: yb))
                ctx.addLine(to: CGPoint(x: x1, y: yb + thick * dir)); ctx.addLine(to: CGPoint(x: x0, y: ya + thick * dir))
                ctx.fillPath()
            }
            let half = 0.06 * sp
            beam(a.stemX - half, b.stemX + half, level: 1)
            for level in 2...3 {
                for (i, c) in g.enumerated() {
                    switch c.beams[level] {
                    case "begin", "continue":
                        if i + 1 < g.count, ["continue", "end"].contains(g[i + 1].beams[level]) { beam(c.stemX - half, g[i + 1].stemX + half, level: level) }
                    case "forward hook": beam(c.stemX, c.stemX + 1.1 * sp, level: level)
                    case "backward hook": beam(c.stemX - 1.1 * sp, c.stemX, level: level)
                    default: break
                    }
                }
            }
        }
    }
}
