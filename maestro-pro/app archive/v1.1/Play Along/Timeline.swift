import CoreGraphics

// Everything the player needs, in page points (top-left origin). Time is in quarter-note beats.

nonisolated struct NoteEvent: Identifiable {
    var id: Int
    var start: Double
    var duration: Double
    var page: Int
    var rect: CGRect
    /// Stem (and flag) area, recoloured with the head when the note sounds.
    var stem: CGRect?
    /// MIDI note number, when the score says what pitch it is.
    var pitch: Int?
    /// The sung syllable on this note and whether it begins, continues, ends or is a whole word (MusicXML).
    var lyric: String?
    /// Where the syllable is printed under the note, to light it while it is sung.
    var lyricRect: CGRect?
    var syllabic: String?
    /// Rests are drawn with a rect (so the editor can find them) but never light up or sound.
    var isRest = false
    /// A small ornamental note: it sounds, but the player never has to play it.
    var grace = false
    /// Beats a grace note sounds before `start` (the note it decorates).
    var lead = 0.0
    var sounds: Double { start - lead }
    /// Where the note came from in the score, for editing (engraved scores only).
    var edit: EditInfo?
    /// The staff it is on (for its own instrument), and how loud the printed dynamics make it (1 = normal).
    var staff = 0
    var velocity = 1.0
    var end: Double { start + duration }
}

/// What the score editor needs to turn a tap on the page back into a change to the score.
nonisolated struct EditInfo: Equatable {
    var measure: Int, index: Int, staff: Int
    /// Page y of the staff's top line, the staff space, and the diatonic number of its bottom line.
    var top: CGFloat, space: CGFloat, clefBottom: Int
}

nonisolated struct MeasureMark {
    var start: Double
    var duration: Double
    var system: Int
    /// Index of the engraved bar (bars repeat in the timeline, so this isn't the position in it).
    var bar = 0
    var x0: CGFloat, x1: CGFloat
    /// (beat, x) points the playhead passes through: note onsets, then the closing barline.
    var anchors: [(beat: Double, x: CGFloat)]
    var end: Double { start + duration }

    func x(at beat: Double) -> CGFloat {
        var prev = (beat: start, x: anchors.first?.x ?? x0)
        for a in anchors {
            if beat < a.beat {
                let t = (beat - prev.beat) / max(a.beat - prev.beat, 0.0001)
                return prev.x + (a.x - prev.x) * CGFloat(max(0, min(1, t)))
            }
            prev = a
        }
        return x1
    }
}

nonisolated struct SystemMark {
    var page: Int
    var rect: CGRect
}

nonisolated struct Timeline {
    var notes: [NoteEvent] = []
    var measures: [MeasureMark] = []
    var systems: [SystemMark] = []
    /// PDFs only: how many bars had note values that added up (exact rhythm) out of all bars.
    var exactBars: (exact: Int, of: Int)?
    var length: Double { measures.last?.end ?? 0 }
    /// For each bar as played, how much longer than written it lasts (2 = half speed) because of tempo marks.
    /// `warped()` applies them; a recording that has its own tempo is better left alone.
    var stretch: [Double] = []
    /// True once `warped()` has applied the tempo marks, so the bars last as long as their marks say.
    var warpedApplied = false

    /// The timeline as played: `order` lists engraved bars, repeats included; each visit gets its own time slot.
    func unfolded(_ order: [Int], tempoRatios: [Double?] = []) -> Timeline {
        var t = self
        t.measures = []; t.notes = []; t.stretch = []
        var at = 0.0, ratio = 1.0
        for i in order {
            if i == 0 { ratio = 1 }   // back to the start: back to the opening tempo
            if i < tempoRatios.count, let r = tempoRatios[i] { ratio = r }
            t.stretch.append(ratio)
            var m = measures[i]
            let shift = at - m.start
            for n in notes where n.start >= m.start - 0.001 && n.start < m.end - 0.001 {
                var n = n; n.id = t.notes.count; n.start += shift
                t.notes.append(n)
            }
            m.start += shift
            m.anchors = m.anchors.map { ($0.beat + shift, $0.x) }
            t.measures.append(m)
            at = m.end
        }
        return t
    }

    /// The timeline with each bar lasting as long as its tempo mark says (the same positions on the page).
    func warped() -> Timeline {
        guard stretch.count == measures.count, stretch.contains(where: { abs($0 - 1) > 0.001 }) else { return self }
        var t = self
        t.measures = []; t.notes = []; t.warpedApplied = true
        var at = 0.0
        for (k, m) in measures.enumerated() {
            let f = stretch[k]
            var w = m
            for n in notes where n.start >= m.start - 0.001 && n.start < m.end - 0.001 {
                var n = n; n.id = t.notes.count
                n.start = at + (n.start - m.start) * f; n.duration *= f; n.lead *= f
                t.notes.append(n)
            }
            w.start = at; w.duration = m.duration * f
            w.anchors = m.anchors.map { (at + ($0.beat - m.start) * f, $0.x) }
            t.measures.append(w)
            at = w.end
        }
        return t
    }

    func measureIndex(at beat: Double) -> Int? {
        guard !measures.isEmpty else { return nil }
        var lo = 0, hi = measures.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if measures[mid].start <= beat { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}

// MARK: - PDF page drawing shared by the viewer, thumbnails and the reader

nonisolated extension CGPDFPage {
    var size: CGSize {
        let b = getBoxRect(.cropBox)
        return rotationAngle % 180 == 0 ? b.size : CGSize(width: b.height, height: b.width)
    }

    /// Draws into a top-left-origin context, filling `size`.
    func draw(in ctx: CGContext, size target: CGSize) {
        let box = getBoxRect(.cropBox)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: target.height)
        ctx.scaleBy(x: target.width / size.width, y: -target.height / size.height)
        // Undo page rotation so the page renders upright.
        switch (rotationAngle % 360 + 360) % 360 {
        case 90: ctx.translateBy(x: 0, y: box.width); ctx.rotate(by: -.pi / 2)
        case 180: ctx.translateBy(x: box.width, y: box.height); ctx.rotate(by: .pi)
        case 270: ctx.translateBy(x: box.height, y: 0); ctx.rotate(by: .pi / 2)
        default: break
        }
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(self)
        ctx.restoreGState()
    }
}
