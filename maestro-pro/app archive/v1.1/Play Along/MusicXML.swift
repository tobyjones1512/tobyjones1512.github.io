import Foundation

// MusicXML (partwise) → a flat, engraving-ready model. Ticks are 480 per quarter note.

nonisolated let ticksPerQuarter = 480

nonisolated struct Clef: Equatable {
    var sign = "G", line = 2
    /// Diatonic number (octave * 7 + step) of the bottom staff line.
    var bottom: Int {
        switch sign {
        case "F": return 24 - 2 * (line - 1)
        case "C": return 28 - 2 * (line - 1)
        default: return 32 - 2 * (line - 1)
        }
    }
}

nonisolated struct PNote {
    var tick = 0, duration = 0, staff = 0
    var voice = "1"
    var diatonic: Int?            // nil = rest
    var alter = 0
    var accidental: String?
    var type = "quarter"
    var dots = 0
    var chord = false, measureRest = false, tieStart = false, hidden = false
    /// Notes in the group this note is a part of when it is a tuplet (3 for a triplet), else 0.
    var tuplet = 0
    var stem: String?
    var beams: [Int: String] = [:]
    /// staccato, accent, tenuto, strong-accent, fermata, breath-mark, caesura, trill-mark, mordent, inverted-mordent, turn,
    /// arpeggiate, and "finger:N" for a fingering.
    var articulations: [String] = []
    var slurStart = false, slurStop = false
    var lyric: String?
    var lyricText: String?, syllabic: String?   // the bare syllable and begin/middle/end/single
}

nonisolated struct PMeasure {
    var start = 0, length = 0
    var notes: [PNote] = []
    var time: (beats: Int, type: Int)?
    var key: Int?
    var clefs: [Int: Clef] = [:]
    var finalBar = false
    var flow = Flow()
    /// Tempo from this bar on, in quarter-note beats a minute; `tempoShown` when it is printed (♩ = 96) rather than only played.
    var tempo: Double?
    var tempoShown = false
    /// Dynamics ("mf") and text directions ("dolce") at a tick on a staff.
    var marks: [(tick: Int, staff: Int, text: String, dynamic: Bool)] = []
    /// Crescendo and diminuendo hairpins that start in this bar.
    var hairpins: [Hairpin] = []
    /// Chord symbols the file carries (`<harmony>`), at ticks of the bar.
    var chords: [ChordMark] = []
    /// Small ornamental notes that sound just before the note at their tick (they take no time in the bar).
    var graces: [Grace] = []
    /// Octave-shift lines (8va) and pedal marks that start in this bar.
    var spans: [Span] = []
}

nonisolated struct Grace: Equatable {
    var tick = 0, staff = 0, diatonic = 0, alter = 0
    var slash = true
}

/// A line that runs from a tick of the bar it starts in to a tick of a later (or the same) bar: "8va", "8vb", "15ma", "15mb" or "pedal".
nonisolated struct Span: Equatable {
    var kind: String
    var staff = 0
    var startTick = 0
    var span = 0
    var endTick = 0
}

/// A crescendo or diminuendo: from a tick of the bar it starts in to a tick of a later (or the same) bar.
nonisolated struct Hairpin: Equatable {
    var crescendo: Bool
    var staff = 0
    var startTick = 0
    /// Bars after the one it starts in where it ends (0 = in the same bar), and the tick there.
    var span = 0
    var endTick = 0
}

/// How a bar sits in the form of the piece: repeats, endings, signs and jumps.
nonisolated struct Flow: Equatable {
    var repeatStart = false
    var repeatEnd = 0          // total times the section plays, when this bar closes a repeat
    var endings: [Int] = []    // volta numbers this bar belongs to
    var multiRest = 0          // this bar starts a run of that many empty bars
    var segno = false, coda = false          // destinations
    var toCoda = false, fine = false         // act only after a D.C./D.S.
    var daCapo = false, dalSegno = false     // jump, once, at the end of this bar

    /// Bars in the order they're played. After a D.C./D.S. repeats are not taken and the last ending is played;
    /// the piece then stops at Fine, or leaps from "To Coda" to the coda.
    static func playOrder(_ f: [Flow]) -> [Int] {
        var order: [Int] = [], i = 0, section = 0, pass = 1, jumped = false
        let segno = f.firstIndex { $0.segno }, coda = f.lastIndex { $0.coda && !$0.toCoda }
        let lastEnding = f.flatMap(\.endings).max() ?? 1
        while i < f.count, order.count < 100_000 {
            let m = f[i], p = jumped ? lastEnding : pass
            if !m.endings.isEmpty, !m.endings.contains(p) { i += 1; continue }
            if m.repeatStart, !jumped { section = i }
            order.append(i)
            if jumped, m.fine { break }
            if jumped, m.toCoda, let c = coda, c > i { i = c; continue }
            if !jumped, m.repeatEnd > 0 {
                if pass < m.repeatEnd { pass += 1; i = section; continue }
                pass = 1; section = i + 1
            }
            if !jumped {
                if m.daCapo { jumped = true; i = 0; continue }
                if m.dalSegno, let s = segno { jumped = true; i = s; continue }
            }
            i += 1
        }
        return order
    }
}

/// How loud the printed dynamics make each note: a factor on the instrument's normal level (mf = 1).
/// ponytail: one loudness curve for the whole score (dynamics from every staff are merged), and a sforzando is just a loud
/// level, not an accent. Upgrade: a curve per staff, and a short attack boost for sf/sfz.
nonisolated enum Dynamics {
    static let normal = 0.72
    static let levels: [String: Double] = ["ppp": 0.25, "pp": 0.35, "p": 0.45, "mp": 0.6, "mf": 0.72, "f": 0.86, "ff": 0.98, "fff": 1.05,
                                           "sf": 0.95, "sfz": 0.95, "fz": 0.95, "rf": 0.9, "rfz": 0.9, "fp": 0.86, "sfp": 0.9]

    /// The loudness factor at an absolute tick of the score. A dynamic holds until the next; a hairpin ramps from the
    /// level where it starts to the next dynamic after it (or a step up or down when none follows).
    static func factor(for score: ParsedScore) -> (Int) -> Double {
        var changes: [(at: Int, level: Double)] = []
        var ramps: [(from: Int, to: Int, up: Bool)] = []
        for (i, m) in score.measures.enumerated() {
            for mark in m.marks where mark.dynamic { if let l = levels[mark.text] { changes.append((m.start + mark.tick, l)) } }
            for h in m.hairpins {
                let last = min(i + h.span, score.measures.count - 1)
                ramps.append((m.start + h.startTick, last == i + h.span ? score.measures[last].start + h.endTick : score.measures[last].start + score.measures[last].length, h.crescendo))
            }
        }
        changes.sort { $0.at < $1.at }
        func level(_ t: Int) -> Double { changes.last { $0.at <= t }?.level ?? normal }
        return { t in
            var l = level(t)
            if let r = ramps.first(where: { t >= $0.from && t < $0.to && $0.to > $0.from }) {
                let start = level(r.from)
                let target = changes.first { $0.at > r.from && $0.at <= r.to + 60 }?.level ?? min(1.05, max(0.2, start + (r.up ? 0.22 : -0.22)))
                l = start + (target - start) * Double(t - r.from) / Double(r.to - r.from)
            }
            return min(1.45, max(0.2, l / normal))
        }
    }
}

nonisolated extension ParsedScore {
    /// What a group of `actual` notes stands in for: 3 in the time of 2, 5 in the time of 4, 7 in the time of 4.
    static func normalNotes(_ actual: Int) -> Int { var n = 1; while n * 2 < actual { n *= 2 }; return n }
    /// MIDI note number for a diatonic position (octave × 7 + step) and alteration.
    static func midi(diatonic d: Int, alter: Int) -> Int { 12 * (d.floorDiv(7) + 1) + [0, 2, 4, 5, 7, 9, 11][d.mod(7)] + alter }
    var playOrder: [Int] { Flow.playOrder(measures.map(\.flow)) }
}

nonisolated struct ParsedScore {
    var title = "", composer = ""
    var staffCount = 0
    /// What each staff is called (a part's name in the file), for choosing its instrument.
    var staffNames: [String] = []
    var braces: [Range<Int>] = []   // staff ranges that belong to one multi-staff part
    var measures: [PMeasure] = []
    var tempo: Double?
    var minor = false

    /// The opening key, e.g. "A major".
    var keyName: String { Self.keyName(measures.first?.key ?? 0, minor: minor) }

    static func keyName(_ fifths: Int, minor: Bool) -> String {
        let f = max(-7, min(7, fifths)) + 7
        let names = minor ? ["A♭", "E♭", "B♭", "F", "C", "G", "D", "A", "E", "B", "F♯", "C♯", "G♯", "D♯", "A♯"]
                          : ["C♭", "G♭", "D♭", "A♭", "E♭", "B♭", "F", "C", "G", "D", "A", "E", "B", "F♯", "C♯"]
        return names[f] + (minor ? " minor" : " major")
    }

    /// The alteration a key signature gives a letter (0 = C … 6 = B).
    static func keyAlter(_ fifths: Int, _ step: Int) -> Int {
        let sharpOrder = [3, 0, 4, 1, 5, 2, 6]   // F C G D A E B
        return fifths > 0 ? (sharpOrder.prefix(fifths).contains(step) ? 1 : 0) : (sharpOrder.reversed().prefix(-fifths).contains(step) ? -1 : 0)
    }

    static let accidentalNames = ["flat-flat", "flat", "natural", "sharp", "double-sharp"]

    /// The key `semitones` away, spelled with the fewest accidentals (F♯ over G♭).
    static func transposedKey(_ fifths: Int, by semitones: Int) -> Int {
        let f = (fifths + 7 * semitones).mod(12)
        return f > 6 ? f - 12 : f
    }

    /// Every pitch moved by `semitones`, spelled in the new key, with accidentals redone bar by bar.
    func transposed(by semitones: Int) -> ParsedScore {
        guard semitones != 0 else { return self }
        let natural = [0, 2, 4, 5, 7, 9, 11]
        func pitch(_ d: Int) -> Int { d.floorDiv(7) * 12 + natural[d.mod(7)] }
        let keyAlter = Self.keyAlter
        var out = self, key = 0
        var tied: [Int: Int] = [:]   // staff/line → alteration of a note tied into the next bar
        for i in out.measures.indices {
            if let k = out.measures[i].key { key = k }
            let nk = Self.transposedKey(key, by: semitones)
            if out.measures[i].key != nil || i == 0 { out.measures[i].key = nk }
            // Letters move with the tonic (each fifth is four letters); the octave follows the semitones.
            let d = (4 * (nk - key)).mod(7), aim = Double(semitones) * 7 / 12
            let shift = [d - 7, d, d + 7].min { abs(Double($0) - aim) < abs(Double($1) - aim) }!
            var inForce: [Int: Int] = [:]   // staff/line → alteration already shown in this bar
            var carry: [Int: Int] = [:]
            for j in out.measures[i].notes.indices.sorted(by: { out.measures[i].notes[$0].tick < out.measures[i].notes[$1].tick }) {
                var n = out.measures[i].notes[j]
                guard let d0 = n.diatonic else { continue }
                let target = pitch(d0) + n.alter + semitones
                var dn = d0 + shift
                if target - pitch(dn) > 2 { dn += 1 } else if target - pitch(dn) < -2 { dn -= 1 }
                let alter = target - pitch(dn), slot = n.staff * 1000 + dn
                if n.tieStart { carry[slot] = alter }
                // The end of a tie from the last bar takes no accidental, and doesn't set one for the rest of this bar.
                if n.tick == 0, tied[slot] == alter { n.accidental = nil; tied[slot] = nil }
                else {
                    n.accidental = alter == (inForce[slot] ?? keyAlter(nk, dn.mod(7))) ? nil : Self.accidentalNames[max(-2, min(2, alter)) + 2]
                    inForce[slot] = alter
                }
                n.diatonic = dn; n.alter = alter
                out.measures[i].notes[j] = n
            }
            tied = carry
            for g in out.measures[i].graces.indices {
                var gr = out.measures[i].graces[g]
                let target = pitch(gr.diatonic) + gr.alter + semitones
                var dn = gr.diatonic + shift
                if target - pitch(dn) > 2 { dn += 1 } else if target - pitch(dn) < -2 { dn -= 1 }
                gr.diatonic = dn; gr.alter = target - pitch(dn)
                out.measures[i].graces[g] = gr
            }
            out.measures[i].chords = out.measures[i].chords.map { ChordMark(tick: $0.tick, chord: $0.chord?.transposed(by: semitones)) }
        }
        return out
    }
}

nonisolated extension Int {
    func mod(_ m: Int) -> Int { (self % m + m) % m }
    func floorDiv(_ m: Int) -> Int { (self - mod(m)) / m }
}

nonisolated enum MusicXML {
    static func parse(_ data: Data) throws -> ParsedScore {
        let root = try XNode.parse(data)
        guard root.name == "score-partwise" else { throw ScoreError.unsupported("Only partwise MusicXML is supported.") }
        var score = ParsedScore()
        score.title = root["work"]?["work-title"]?.text ?? root["movement-title"]?.text ?? ""
        score.composer = root["identification"]?.all("creator").first { $0.attrs["type"] == "composer" }?.text ?? ""

        var partNames: [String: String] = [:]
        for sp in root["part-list"]?.all("score-part") ?? [] { if let id = sp.attrs["id"], let n = sp["part-name"]?.text, !n.isEmpty { partNames[id] = n } }
        var openWedges: [String: (bar: Int, tick: Int, crescendo: Bool, staff: Int)] = [:]
        var openSpans: [String: (bar: Int, tick: Int, kind: String, staff: Int)] = [:]
        for part in root.all("part") {
            let base = score.staffCount
            var staves = 1, divisions = 1
            var ending: [Int] = []
            for (i, m) in part.all("measure").enumerated() {
                if score.measures.count <= i { score.measures.append(PMeasure()) }
                var cursor = 0, maxCursor = 0, lastStart = 0, endingStops = false, codaSymbol = false
                // A metronome mark printed in this bar is what the page says; a separate "sound" tempo does not override it.
                let marked = m.children.filter { $0.name == "direction" }.flatMap { $0.all("direction-type") }.compactMap(Self.metronomeBPM).first
                for el in m.children {
                    switch el.name {
                    case "attributes":
                        if let d = el["divisions"]?.int { divisions = max(d, 1) }
                        if let s = el["staves"]?.int { staves = s }
                        if let f = el["key"]?["fifths"]?.int {
                            score.measures[i].key = f
                            if i == 0, base == 0 { score.minor = el["key"]?["mode"]?.text == "minor" }
                        }
                        if let r = el["measure-style"]?["multiple-rest"]?.int { score.measures[i].flow.multiRest = r }
                        if let t = el["time"], let b = t["beats"]?.int, let bt = t["beat-type"]?.int { score.measures[i].time = (b, bt) }
                        for c in el.all("clef") {
                            let n = Int(c.attrs["number"] ?? "1") ?? 1
                            score.measures[i].clefs[base + n - 1] = Clef(sign: c["sign"]?.text ?? "G", line: c["line"]?.int ?? (c["sign"]?.text == "F" ? 4 : 2))
                        }
                    case "harmony":
                        if let step = el["root"]?["root-step"]?.text, let at = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11][step] {
                            let alter = Int(el["root"]?["root-alter"]?.text ?? "") ?? Int(Double(el["root"]?["root-alter"]?.text ?? "") ?? 0)
                            var chord = Chord(root: (at + alter).mod(12), kind: Chord.kind(fromXML: el["kind"]?.text ?? ""), bass: nil)
                            if let bs = el["bass"]?["bass-step"]?.text, let b = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11][bs] {
                                chord.bass = (b + (Int(el["bass"]?["bass-alter"]?.text ?? "") ?? 0)).mod(12)
                            }
                            score.measures[i].chords.append(ChordMark(tick: cursor + ticks(el["offset"]?.int, divisions), chord: chord))
                        }
                    case "backup": cursor -= ticks(el["duration"]?.int, divisions)
                    case "forward": cursor += ticks(el["duration"]?.int, divisions)
                    case "note":
                        if el["cue"] != nil { continue }
                        if let g = el["grace"] {
                            if let p = el["pitch"], el["chord"] == nil {
                                let step = "CDEFGAB".firstIndex(of: Character(p["step"]?.text ?? "C")).map { "CDEFGAB".distance(from: "CDEFGAB".startIndex, to: $0) } ?? 0
                                score.measures[i].graces.append(Grace(tick: cursor, staff: base + (el["staff"]?.int ?? 1) - 1, diatonic: (p["octave"]?.int ?? 4) * 7 + step,
                                                                      alter: Int(Double(p["alter"]?.text ?? "0") ?? 0), slash: g.attrs["slash"] != "no"))
                            }
                            continue
                        }
                        var n = PNote()
                        n.duration = ticks(el["duration"]?.int, divisions)
                        n.chord = el["chord"] != nil
                        n.tick = n.chord ? lastStart : cursor
                        if !n.chord { lastStart = cursor; cursor += n.duration }
                        n.staff = base + (el["staff"]?.int ?? 1) - 1
                        n.voice = el["voice"]?.text ?? "1"
                        if let p = el["pitch"] {
                            let step = "CDEFGAB".firstIndex(of: Character(p["step"]?.text ?? "C")).map { "CDEFGAB".distance(from: "CDEFGAB".startIndex, to: $0) } ?? 0
                            n.diatonic = (p["octave"]?.int ?? 4) * 7 + step
                            n.alter = Int(Double(p["alter"]?.text ?? "0") ?? 0)
                        }
                        n.measureRest = el["rest"]?.attrs["measure"] == "yes"
                        n.hidden = el.attrs["print-object"] == "no"
                        n.type = el["type"]?.text ?? (n.measureRest ? "whole" : typeFor(n.duration))
                        n.dots = el.all("dot").count
                        n.accidental = el["accidental"]?.text
                        if let a = el["time-modification"]?["actual-notes"]?.int, a > 1, a != (el["time-modification"]?["normal-notes"]?.int ?? 0) { n.tuplet = a }
                        n.stem = el["stem"]?.text
                        n.tieStart = el.all("tie").contains { $0.attrs["type"] == "start" } || el.all("notations").contains { $0.all("tied").contains { $0.attrs["type"] == "start" } }
                        for b in el.all("beam") { n.beams[Int(b.attrs["number"] ?? "1") ?? 1] = b.text }
                        for nt in el.all("notations") {
                            n.articulations += nt.all("articulations").flatMap { $0.children.map(\.name) } + nt.all("fermata").map { _ in "fermata" }
                            n.articulations += nt.all("ornaments").flatMap { $0.children.map(\.name) }.filter { Self.ornaments.contains($0) }
                            n.articulations += nt.all("technical").flatMap { $0.all("fingering") }.map { "finger:" + $0.text.trimmingCharacters(in: .whitespaces) }
                            if !nt.all("arpeggiate").isEmpty { n.articulations.append("arpeggiate") }
                            for sl in nt.all("slur") {
                                if sl.attrs["type"] == "start" { n.slurStart = true } else if sl.attrs["type"] == "stop" { n.slurStop = true }
                            }
                        }
                        if let l = el["lyric"], let t = l["text"]?.text {
                            let syl = l["syllabic"]?.text
                            n.lyric = t + (syl == "begin" || syl == "middle" ? " -" : "")
                            n.lyricText = t; n.syllabic = syl
                        }
                        score.measures[i].notes.append(n)
                    case "barline":
                        if let r = el["repeat"] {
                            if r.attrs["direction"] == "forward" { score.measures[i].flow.repeatStart = true }
                            else { score.measures[i].flow.repeatEnd = max(Int(r.attrs["times"] ?? "") ?? 2, 2) }
                        } else if el["bar-style"]?.text == "light-heavy" { score.measures[i].finalBar = true }
                        if let e = el["ending"] {
                            if e.attrs["type"] == "start" { ending = (e.attrs["number"] ?? "1").split { $0 == "," || $0 == " " }.compactMap { Int($0) } }
                            else { endingStops = true }
                        }
                    case "direction", "sound":
                        if el.name == "direction" {
                            let staff = base + (el["staff"]?.int ?? 1) - 1
                            let at = cursor + ticks(el["offset"]?.int, divisions)
                            for dt in el.all("direction-type") {
                                if let w = dt["wedge"] {
                                    let key = "\(base)|\(staff)|\(w.attrs["number"] ?? "1")"
                                    switch w.attrs["type"] {
                                    case "crescendo", "diminuendo": openWedges[key] = (i, at, w.attrs["type"] == "crescendo", staff)
                                    case "stop":
                                        if let o = openWedges.removeValue(forKey: key), o.bar <= i {
                                            score.measures[o.bar].hairpins.append(Hairpin(crescendo: o.crescendo, staff: o.staff, startTick: o.tick, span: i - o.bar, endTick: at))
                                        }
                                    default: break
                                    }
                                }
                                // Octave shifts (8va is "down": the notes are written an octave lower than they sound) and the pedal.
                                for (name, node) in [("octave", dt["octave-shift"]), ("pedal", dt["pedal"])] {
                                    guard let node, let type = node.attrs["type"] else { continue }
                                    let key = "\(base)|\(staff)|\(name)"
                                    if type == "stop" || type == "change" {
                                        if let o = openSpans.removeValue(forKey: key), o.bar <= i {
                                            score.measures[o.bar].spans.append(Span(kind: o.kind, staff: o.staff, startTick: o.tick, span: i - o.bar, endTick: at))
                                        }
                                    }
                                    if type == "start" || type == "change" || type == "up" || type == "down" {
                                        let big = node.attrs["size"] == "15"
                                        let kind = name == "pedal" ? "pedal" : type == "down" ? (big ? "15ma" : "8va") : (big ? "15mb" : "8vb")
                                        openSpans[key] = (i, at, kind, staff)
                                    }
                                }
                                if let d = dt["dynamics"]?.children.first {
                                    let text = d.name == "other-dynamics" ? d.text : d.name
                                    score.measures[i].marks.append((at, staff, text, true))
                                }
                                for w in dt.all("words") where !w.text.isEmpty {
                                    score.measures[i].marks.append((at, staff, w.text, false))
                                    let t = w.text.lowercased().trimmingCharacters(in: .whitespaces)
                                    if t.contains("d.c.") || t.contains("da capo") { score.measures[i].flow.daCapo = true }
                                    else if t.contains("d.s.") || t.contains("dal segno") { score.measures[i].flow.dalSegno = true }
                                    else if t.hasPrefix("to coda") { score.measures[i].flow.toCoda = true }
                                    else if t == "fine" { score.measures[i].flow.fine = true }
                                }
                                if let pm = dt["metronome"]?["per-minute"]?.text, let bpm = Double(pm.trimmingCharacters(in: .whitespaces)), let m = dt["metronome"] {
                                    let units: [String: Double] = ["whole": 4, "half": 2, "quarter": 1, "eighth": 0.5, "16th": 0.25]
                                    let unit = units[m["beat-unit"]?.text ?? "quarter"] ?? 1
                                    score.measures[i].tempo = bpm * unit * (m["beat-unit-dot"] != nil ? 1.5 : 1)
                                    score.measures[i].tempoShown = true
                                }
                                if dt["segno"] != nil { score.measures[i].flow.segno = true }
                                if dt["coda"] != nil { codaSymbol = true }
                            }
                        }
                        let s = el.name == "sound" ? el : el["sound"]
                        if let s {
                            if s.attrs["segno"] != nil { score.measures[i].flow.segno = true }
                            if s.attrs["coda"] != nil { score.measures[i].flow.coda = true }
                            if s.attrs["tocoda"] != nil { score.measures[i].flow.toCoda = true }
                            if s.attrs["fine"] != nil { score.measures[i].flow.fine = true }
                            if s.attrs["dacapo"] == "yes" { score.measures[i].flow.daCapo = true }
                            if s.attrs["dalsegno"] != nil { score.measures[i].flow.dalSegno = true }
                        }
                        let sound = s?.attrs["tempo"].flatMap(Double.init)
                        if let t = sound, marked == nil { score.measures[i].tempo = t }
                        if score.tempo == nil, let t = marked ?? sound { score.tempo = t }
                    default: break
                    }
                    maxCursor = max(maxCursor, cursor)
                }
                score.measures[i].length = max(score.measures[i].length, maxCursor)
                if !ending.isEmpty { score.measures[i].flow.endings = ending }
                if endingStops { ending = [] }
                if codaSymbol, !score.measures[i].flow.toCoda { score.measures[i].flow.coda = true }
            }
            if staves > 1 { score.braces.append(base..<base + staves) }
            let name = partNames[part.attrs["id"] ?? ""] ?? ""
            for k in 0..<staves { score.staffNames.append(staves > 1 && !name.isEmpty ? "\(name) (\(staves == 2 ? (k == 0 ? "upper" : "lower") : "\(k + 1)"))" : name) }
            score.staffCount += staves
        }
        guard !score.measures.isEmpty, score.staffCount > 0 else { throw ScoreError.unsupported("The file contains no measures.") }
        var t = 0
        for i in score.measures.indices {
            score.measures[i].start = t
            if score.measures[i].length == 0 { score.measures[i].length = ticksPerQuarter * 4 }
            t += score.measures[i].length
        }
        return score
    }

    /// Writes a score as partwise MusicXML: one part, its staves, voices joined with backup/forward.
    static func write(_ s: ParsedScore) -> Data {
        func esc(_ t: String) -> String { t.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        var x = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<score-partwise version=\"4.0\">\n"
        if !s.title.isEmpty { x += "<work><work-title>\(esc(s.title))</work-title></work>\n" }
        if !s.composer.isEmpty { x += "<identification><creator type=\"composer\">\(esc(s.composer))</creator></identification>\n" }
        x += "<part-list><score-part id=\"P1\"><part-name>Music</part-name></score-part></part-list>\n<part id=\"P1\">\n"
        for (i, m) in s.measures.enumerated() {
            x += "<measure number=\"\(i + 1)\">"
            if i == 0 || m.key != nil || m.time != nil || !m.clefs.isEmpty || m.flow.multiRest > 1 {
                x += "<attributes>"
                if i == 0 { x += "<divisions>\(ticksPerQuarter)</divisions>" }
                if let k = m.key { x += "<key><fifths>\(k)</fifths>\(i == 0 && s.minor ? "<mode>minor</mode>" : "")</key>" }
                if let t = m.time { x += "<time><beats>\(t.beats)</beats><beat-type>\(t.type)</beat-type></time>" }
                if i == 0, s.staffCount > 1 { x += "<staves>\(s.staffCount)</staves>" }
                for (st, c) in m.clefs.sorted(by: { $0.key < $1.key }) { x += "<clef number=\"\(st + 1)\"><sign>\(c.sign)</sign><line>\(c.line)</line></clef>" }
                if m.flow.multiRest > 1 { x += "<measure-style><multiple-rest>\(m.flow.multiRest)</multiple-rest></measure-style>" }
                x += "</attributes>"
            }
            if let t = m.tempo ?? (i == 0 ? s.tempo : nil) {
                let shown = m.tempoShown && m.tempo != nil
                x += "<direction placement=\"above\"><direction-type>" + (shown ? "<metronome><beat-unit>quarter</beat-unit><per-minute>\(Int(t.rounded()))</per-minute></metronome>" : "<words></words>") + "</direction-type><sound tempo=\"\(t)\"/></direction>"
            }
            let f = m.flow
            if f.repeatStart { x += "<barline location=\"left\"><repeat direction=\"forward\"/></barline>" }
            if !f.endings.isEmpty, i == 0 || s.measures[i - 1].flow.endings != f.endings {
                x += "<barline location=\"left\"><ending number=\"\(f.endings.map(String.init).joined(separator: ","))\" type=\"start\"/></barline>"
            }
            for (on, tag) in [(f.segno, "segno=\"s\""), (f.coda, "coda=\"c\""), (f.toCoda, "tocoda=\"c\""), (f.fine, "fine=\"yes\""), (f.daCapo, "dacapo=\"yes\""), (f.dalSegno, "dalsegno=\"s\"")] where on {
                // The segno and coda are written as the signs themselves, so other notation apps draw them.
                let sign = tag.hasPrefix("segno") ? "<segno/>" : tag.hasPrefix("coda") ? "<coda/>" : "<words></words>"
                x += "<direction><direction-type>\(sign)</direction-type><sound \(tag)/></direction>"
            }
            for mark in m.chords {
                guard let c = mark.chord else { continue }
                let step = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"][c.root], sharp = [1, 3, 6, 8, 10].contains(c.root)
                x += "<harmony><root><root-step>\(step)</root-step>" + (sharp ? "<root-alter>1</root-alter>" : "") + "</root><kind>\(c.xmlKind)</kind>"
                if let b = c.bass {
                    x += "<bass><bass-step>\(["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"][b.mod(12)])</bass-step>" + ([1, 3, 6, 8, 10].contains(b.mod(12)) ? "<bass-alter>1</bass-alter>" : "") + "</bass>"
                }
                x += "<offset>\(mark.tick)</offset></harmony>"
            }
            // Hairpins: the start where it begins and a stop where it ends, each at its own offset in the bar.
            func wedge(_ type: String, _ number: Int, tick: Int, staff: Int) {
                x += "<direction placement=\"below\"><direction-type><wedge type=\"\(type)\" number=\"\(number)\"/></direction-type><offset>\(tick)</offset>" + (s.staffCount > 1 ? "<staff>\(staff + 1)</staff>" : "") + "</direction>"
            }
            // Octave shifts and the pedal: the start where it begins and a stop where it ends.
            func span(_ sp: Span, stop: Bool, tick: Int) {
                let size = sp.kind.hasPrefix("15") ? "15" : "8", down = sp.kind.hasSuffix("a") || sp.kind == "8va"
                let tag = sp.kind == "pedal" ? "<pedal type=\"\(stop ? "stop" : "start")\" line=\"yes\"/>"
                                             : "<octave-shift type=\"\(stop ? "stop" : (down ? "down" : "up"))\" size=\"\(size)\"/>"
                x += "<direction placement=\"\(sp.kind == "pedal" ? "below" : "above")\"><direction-type>\(tag)</direction-type><offset>\(tick)</offset>" + (s.staffCount > 1 ? "<staff>\(sp.staff + 1)</staff>" : "") + "</direction>"
            }
            for sp in m.spans { span(sp, stop: false, tick: sp.startTick) }
            for j in s.measures.indices where j <= i {
                for sp in s.measures[j].spans where j + sp.span == i { span(sp, stop: true, tick: sp.endTick) }
            }
            for (k, h) in m.hairpins.enumerated() { wedge(h.crescendo ? "crescendo" : "diminuendo", (i + k) % 6 + 1, tick: h.startTick, staff: h.staff) }
            for j in s.measures.indices where j <= i {
                for (k, h) in s.measures[j].hairpins.enumerated() where j + h.span == i { wedge("stop", (j + k) % 6 + 1, tick: h.endTick, staff: h.staff) }
            }
            // Dynamics and words, placed by an offset from the start of the bar.
            for mark in m.marks {
                x += "<direction placement=\"\(mark.dynamic ? "below" : "above")\"><direction-type>"
                if mark.dynamic {
                    let known = ["p", "pp", "ppp", "mp", "mf", "f", "ff", "fff", "fp", "sf", "sfz", "rf", "rfz", "fz"]
                    x += "<dynamics>" + (known.contains(mark.text) ? "<\(mark.text)/>" : "<other-dynamics>\(esc(mark.text))</other-dynamics>") + "</dynamics>"
                } else { x += "<words>\(esc(mark.text))</words>" }
                x += "</direction-type><offset>\(mark.tick)</offset>" + (s.staffCount > 1 ? "<staff>\(mark.staff + 1)</staff>" : "") + "</direction>"
            }
            var cursor = 0, reach = 0, first = true
            let lanes = Dictionary(grouping: m.notes) { "\($0.staff)|\($0.voice)" }.sorted { a, b in
                let (p, q) = (a.value[0], b.value[0]); return p.staff != q.staff ? p.staff < q.staff : p.voice < q.voice
            }
            for (_, lane) in lanes {
                if !first, cursor > 0 { x += "<backup><duration>\(cursor)</duration></backup>"; cursor = 0 }
                first = false
                let ordered = lane.sorted(by: { $0.tick < $1.tick })
                for (k, n) in ordered.enumerated() {
                    if !n.chord, n.tick > cursor { x += "<forward><duration>\(n.tick - cursor)</duration></forward>"; cursor = n.tick }
                    else if !n.chord, n.tick < cursor { x += "<backup><duration>\(cursor - n.tick)</duration></backup>"; cursor = n.tick }   // an overfull bar overlaps
                    if !n.chord {
                        for g in m.graces where g.tick == n.tick && g.staff == n.staff && n.voice == "1" && k == ordered.firstIndex(where: { $0.tick == n.tick && !$0.chord })! {
                            x += "<note><grace\(g.slash ? " slash=\"yes\"" : "")/><pitch><step>\(Array("CDEFGAB")[g.diatonic.mod(7)])</step>\(g.alter != 0 ? "<alter>\(g.alter)</alter>" : "")<octave>\(g.diatonic.floorDiv(7))</octave></pitch><voice>\(esc(n.voice))</voice><type>eighth</type>" + (s.staffCount > 1 ? "<staff>\(g.staff + 1)</staff>" : "") + "</note>"
                        }
                    }
                    // A tie stops on the same pitch that follows its start.
                    let stops = n.diatonic != nil && ordered[..<k].contains { $0.tieStart && $0.diatonic == n.diatonic && $0.tick + $0.duration == n.tick }
                    x += (n.hidden ? "<note print-object=\"no\">" : "<note>") + (n.chord ? "<chord/>" : "")
                    if let d = n.diatonic {
                        x += "<pitch><step>\(Array("CDEFGAB")[d.mod(7)])</step>\(n.alter != 0 ? "<alter>\(n.alter)</alter>" : "")<octave>\(d.floorDiv(7))</octave></pitch>"
                    } else { x += n.measureRest ? "<rest measure=\"yes\"/>" : "<rest/>" }
                    x += "<duration>\(n.duration)</duration>" + (stops ? "<tie type=\"stop\"/>" : "") + (n.tieStart ? "<tie type=\"start\"/>" : "") + "<voice>\(esc(n.voice))</voice>"
                    if !n.measureRest { x += "<type>\(n.type)</type>" + String(repeating: "<dot/>", count: n.dots) }
                    if let a = n.accidental { x += "<accidental>\(a)</accidental>" }
                    if n.tuplet > 1 { x += "<time-modification><actual-notes>\(n.tuplet)</actual-notes><normal-notes>\(ParsedScore.normalNotes(n.tuplet))</normal-notes></time-modification>" }
                    if let st = n.stem { x += "<stem>\(st)</stem>" }
                    if s.staffCount > 1 { x += "<staff>\(n.staff + 1)</staff>" }
                    for (level, kind) in n.beams.sorted(by: { $0.key < $1.key }) { x += "<beam number=\"\(level)\">\(kind)</beam>" }
                    let orn = n.articulations.filter(Self.ornaments.contains), fingers = n.articulations.filter { $0.hasPrefix("finger:") }
                    let marks = n.articulations.filter { $0 != "fermata" && $0 != "arpeggiate" && !Self.ornaments.contains($0) && !$0.hasPrefix("finger:") }
                    let fermata = n.articulations.contains("fermata"), arp = n.articulations.contains("arpeggiate")
                    if !marks.isEmpty || !orn.isEmpty || !fingers.isEmpty || fermata || arp || n.tieStart || stops || n.slurStart || n.slurStop {
                        x += "<notations>" + (stops ? "<tied type=\"stop\"/>" : "") + (n.tieStart ? "<tied type=\"start\"/>" : "")
                            + (n.slurStop ? "<slur type=\"stop\" number=\"1\"/>" : "") + (n.slurStart ? "<slur type=\"start\" number=\"1\"/>" : "")
                            + (orn.isEmpty ? "" : "<ornaments>" + orn.map { "<\($0)/>" }.joined() + "</ornaments>")
                            + (fingers.isEmpty ? "" : "<technical>" + fingers.map { "<fingering>\(esc(String($0.dropFirst(7))))</fingering>" }.joined() + "</technical>")
                            + (marks.isEmpty ? "" : "<articulations>" + marks.map { "<\($0)/>" }.joined() + "</articulations>") + (fermata ? "<fermata/>" : "") + (arp ? "<arpeggiate/>" : "") + "</notations>"
                    }
                    if let text = n.lyricText {
                        x += "<lyric number=\"1\">" + (n.syllabic.map { "<syllabic>\($0)</syllabic>" } ?? "") + "<text>\(esc(text))</text></lyric>"
                    }
                    x += "</note>"
                    if !n.chord { cursor += n.duration; reach = max(reach, cursor) }
                }
            }
            // Keep the bar its full length even where no voice fills it.
            if reach < m.length { x += "<forward><duration>\(m.length - cursor)</duration></forward>" }
            if f.repeatEnd > 0 || (!f.endings.isEmpty && (i + 1 == s.measures.count || s.measures[i + 1].flow.endings != f.endings)) {
                x += "<barline location=\"right\">" + (f.endings.isEmpty ? "" : "<ending number=\"\(f.endings.map(String.init).joined(separator: ","))\" type=\"stop\"/>")
                    + (f.repeatEnd > 0 ? "<repeat direction=\"backward\" times=\"\(f.repeatEnd)\"/>" : "") + "</barline>"
            } else if m.finalBar { x += "<barline location=\"right\"><bar-style>light-heavy</bar-style></barline>" }
            x += "</measure>\n"
        }
        return Data((x + "</part>\n</score-partwise>\n").utf8)
    }

    /// Quarter notes a minute from a printed metronome mark (the beat unit and any dot taken into account).
    static func metronomeBPM(_ dt: XNode) -> Double? {
        guard let m = dt["metronome"], let pm = m["per-minute"]?.text, let bpm = Double(pm.trimmingCharacters(in: .whitespaces)) else { return nil }
        let units: [String: Double] = ["whole": 4, "half": 2, "quarter": 1, "eighth": 0.5, "16th": 0.25]
        return bpm * (units[m["beat-unit"]?.text ?? "quarter"] ?? 1) * (m["beat-unit-dot"] != nil ? 1.5 : 1)
    }

    static let ornaments: Set<String> = ["trill-mark", "mordent", "inverted-mordent", "turn", "inverted-turn", "delayed-turn", "shake"]

    private static func ticks(_ d: Int?, _ divisions: Int) -> Int { (d ?? 0) * ticksPerQuarter / divisions }

    private static func typeFor(_ ticks: Int) -> String {
        switch ticks {
        case 1920...: "whole"
        case 960...: "half"
        case 480...: "quarter"
        case 240...: "eighth"
        default: "16th"
        }
    }

    /// Accepts plain MusicXML or compressed .mxl.
    static func data(from url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        guard data.starts(with: [0x50, 0x4B, 0x03, 0x04]) else { return data }
        let files = try Zip.entries(data)
        guard let xml = files.first(where: { !$0.key.hasPrefix("META-INF") && ($0.key.hasSuffix(".xml") || $0.key.hasSuffix(".musicxml")) })?.value
        else { throw ScoreError.unsupported("The .mxl archive has no score inside.") }
        return xml
    }
}

nonisolated enum ScoreError: LocalizedError {
    case unsupported(String)
    var errorDescription: String? { if case .unsupported(let s) = self { s } else { nil } }
}

// MARK: - Minimal XML tree

nonisolated final class XNode: NSObject, XMLParserDelegate {
    let name: String
    var attrs: [String: String]
    var children: [XNode] = []
    private var buffer = ""
    var text: String { buffer.trimmingCharacters(in: .whitespacesAndNewlines) }
    var int: Int? { Int(text) }

    init(_ name: String, _ attrs: [String: String] = [:]) { self.name = name; self.attrs = attrs }

    subscript(_ child: String) -> XNode? { children.first { $0.name == child } }
    func all(_ child: String) -> [XNode] { children.filter { $0.name == child } }

    private var stack: [XNode] = []

    static func parse(_ data: Data) throws -> XNode {
        let doc = XNode("#doc")
        doc.stack = [doc]
        let parser = XMLParser(data: data)
        parser.delegate = doc
        guard parser.parse(), let root = doc.children.first else {
            throw ScoreError.unsupported("This doesn’t look like a valid MusicXML file.")
        }
        return root
    }

    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let n = XNode(e, attributes)
        stack.last?.children.append(n)
        stack.append(n)
    }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) { stack.removeLast() }
    func parser(_ p: XMLParser, foundCharacters s: String) { stack.last?.buffer += s }
}

// MARK: - Minimal zip reader (stored + deflate), enough for .mxl

nonisolated enum Zip {
    static func entries(_ d: Data) throws -> [String: Data] {
        let b = [UInt8](d)
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard let eocd = stride(from: b.count - 22, through: max(0, b.count - 65_557), by: -1).first(where: { u32($0) == 0x06054b50 })
        else { throw ScoreError.unsupported("Damaged .mxl archive.") }
        var out: [String: Data] = [:]
        var p = u32(eocd + 16)
        for _ in 0..<u16(eocd + 10) {
            guard p + 46 <= b.count, u32(p) == 0x02014b50 else { break }
            let method = u16(p + 10), size = u32(p + 20), nameLen = u16(p + 28)
            let extra = u16(p + 30), comment = u16(p + 32), local = u32(p + 42)
            let name = String(decoding: b[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            let raw = d.subdata(in: start..<(start + size))
            if method == 0 { out[name] = raw }
            else if method == 8 { out[name] = try (raw as NSData).decompressed(using: .zlib) as Data }
            p += 46 + nameLen + extra + comment
        }
        return out
    }
}
