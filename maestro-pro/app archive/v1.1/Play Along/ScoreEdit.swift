import CoreGraphics
import Foundation

// Changes to a ParsedScore that the score editor makes: move a note's pitch, turn a note into a rest, put a note on a
// rest, change a note's length, set accidentals. Each keeps the bars the right length and the beams in order.

nonisolated enum ScoreEdit {
    /// Note lengths the editor writes, longest first: ticks, MusicXML type, dots.
    static let ladder: [(ticks: Int, type: String, dots: Int)] = [
        (1920, "whole", 0), (1440, "half", 1), (960, "half", 0), (720, "quarter", 1), (480, "quarter", 0),
        (360, "eighth", 1), (240, "eighth", 0), (180, "16th", 1), (120, "16th", 0), (90, "32nd", 1), (60, "32nd", 0),
    ]

    /// Lengths a tuplet of `actual` notes can take (a triplet eighth is 160 ticks): the plain lengths scaled to fit.
    static func tupletLadder(_ actual: Int) -> [(ticks: Int, type: String, dots: Int)] {
        let normal = ParsedScore.normalNotes(actual)
        return [(1920, "whole"), (960, "half"), (480, "quarter"), (240, "eighth"), (120, "16th"), (60, "32nd")]
            .map { ($0.0 * normal / actual, $0.1, 0) }
    }

    static func step(atMost ticks: Int, tuplet: Int) -> (ticks: Int, type: String, dots: Int)? {
        tuplet > 1 ? tupletLadder(tuplet).first { $0.ticks <= ticks } : step(atMost: ticks)
    }

    /// Rests that add up to `ticks` in tuplet lengths, longest first.
    static func fill(_ ticks: Int, tuplet: Int) -> [(ticks: Int, type: String, dots: Int)] {
        guard tuplet > 1 else { return fill(ticks) }
        var left = ticks, out: [(ticks: Int, type: String, dots: Int)] = []
        while let s = step(atMost: left, tuplet: tuplet) { out.append(s); left -= s.ticks }
        return out
    }

    /// The ladder step at or below `ticks`.
    static func step(atMost ticks: Int) -> (ticks: Int, type: String, dots: Int)? { ladder.first { $0.ticks <= ticks } }

    /// Lengths that add up to `ticks`, longest first, as far as the ladder can express (anything under a 32nd is dropped).
    static func fill(_ ticks: Int) -> [(ticks: Int, type: String, dots: Int)] {
        var left = ticks, out: [(ticks: Int, type: String, dots: Int)] = []
        while let s = step(atMost: left) { out.append(s); left -= s.ticks }
        return out
    }

    /// Ticks in a beat of the bar: a quarter for 2/4, 3/4, 4/4; an eighth for x/8 and shorter, or a dotted quarter in 6/8, 9/8, 12/8.
    static func beat(at measure: Int, in score: ParsedScore) -> Int {
        var time = (beats: 4, type: 4)
        for i in 0...min(max(measure, 0), max(score.measures.count - 1, 0)) where i < score.measures.count { if let t = score.measures[i].time { time = t } }
        if time.type >= 8, time.beats % 3 == 0, time.beats >= 6 { return 1920 / time.type * 3 }
        return 1920 / max(1, time.type)
    }

    /// Rests that add up to `ticks` starting `at` a tick of the bar, the way a copyist writes them: each starts on its own
    /// length's grid and none straddles a beat it does not begin (a half rest begins on beat 1 or 3, not 2).
    static func fill(_ ticks: Int, at start: Int, beat: Int) -> [(ticks: Int, type: String, dots: Int)] {
        var t = start, left = ticks, out: [(ticks: Int, type: String, dots: Int)] = []
        let compound = beat % 720 == 0
        func fits(_ s: (ticks: Int, type: String, dots: Int)) -> Bool {
            guard s.ticks <= left else { return false }
            if s.dots > 0 { guard compound, t % beat == 0, s.ticks % beat == 0 else { return false } }
            else if t % s.ticks != 0 { return false }
            if t % beat != 0 { return t + s.ticks <= (t / beat + 1) * beat }
            return s.ticks <= beat || s.ticks % beat == 0
        }
        while left > 0 {
            guard let s = ladder.first(where: fits) ?? step(atMost: left) else { break }
            out.append(s); t += s.ticks; left -= s.ticks
        }
        return out
    }

    /// Rests for `ticks` of a bar from `start`: in the given tuplet's lengths if it is one, else plain lengths on the beat; when
    /// plain ones cannot make it exactly (the gap a triplet left), triplet lengths.
    static func restPieces(_ ticks: Int, at start: Int, beat: Int, tuplet: Int) -> [(ticks: Int, type: String, dots: Int, tuplet: Int)] {
        guard ticks > 0 else { return [] }
        func tagged(_ p: [(ticks: Int, type: String, dots: Int)], _ t: Int) -> [(ticks: Int, type: String, dots: Int, tuplet: Int)] { p.map { ($0.ticks, $0.type, $0.dots, t) } }
        if tuplet > 1 { return tagged(fill(ticks, tuplet: tuplet), tuplet) }
        let plain = fill(ticks, at: start, beat: beat)
        if plain.reduce(0, { $0 + $1.ticks }) == ticks { return tagged(plain, 0) }
        let trip = fill(ticks, tuplet: 3)
        return trip.reduce(0, { $0 + $1.ticks }) == ticks ? tagged(trip, 3) : tagged(plain, 0)
    }

    static func key(at measure: Int, in score: ParsedScore) -> Int {
        var key = 0
        for i in 0...min(measure, score.measures.count - 1) { if let k = score.measures[i].key { key = k } }
        return key
    }

    private static func sameLane(_ a: PNote, _ b: PNote) -> Bool { a.staff == b.staff && a.voice == b.voice }

    // MARK: Pitch

    /// Moves a note to another line or space; it takes the key's accidental unless it already had its own.
    static func setPitch(_ score: inout ParsedScore, measure m: Int, index i: Int, diatonic: Int) {
        guard score.measures.indices.contains(m), score.measures[m].notes.indices.contains(i), score.measures[m].notes[i].diatonic != nil else { return }
        let fifths = key(at: m, in: score)
        var n = score.measures[m].notes[i]
        n.diatonic = max(0, diatonic)
        n.alter = ParsedScore.keyAlter(fifths, n.diatonic!.mod(7))
        n.accidental = nil
        n.tieStart = false
        score.measures[m].notes[i] = n
    }

    enum Accidental { case sharp, flat, natural, key }

    static func setAccidental(_ score: inout ParsedScore, measure m: Int, index i: Int, _ a: Accidental) {
        guard score.measures.indices.contains(m), score.measures[m].notes.indices.contains(i), let d = score.measures[m].notes[i].diatonic else { return }
        let inKey = ParsedScore.keyAlter(key(at: m, in: score), d.mod(7))
        switch a {
        case .sharp: score.measures[m].notes[i].alter = 1; score.measures[m].notes[i].accidental = "sharp"
        case .flat: score.measures[m].notes[i].alter = -1; score.measures[m].notes[i].accidental = "flat"
        case .natural: score.measures[m].notes[i].alter = 0; score.measures[m].notes[i].accidental = "natural"
        case .key: score.measures[m].notes[i].alter = inKey; score.measures[m].notes[i].accidental = nil
        }
    }

    // MARK: Erase

    /// A note becomes a rest of the same length (the bar keeps its length); one note of a chord just goes.
    @discardableResult
    static func erase(_ score: inout ParsedScore, measure m: Int, index i: Int) -> Bool {
        guard score.measures.indices.contains(m), score.measures[m].notes.indices.contains(i), score.measures[m].notes[i].diatonic != nil else { return false }
        let n = score.measures[m].notes[i]
        let members = score.measures[m].notes.indices.filter { sameLane(score.measures[m].notes[$0], n) && score.measures[m].notes[$0].tick == n.tick }
        // Ties into this note lead nowhere now.
        for j in score.measures[m].notes.indices where score.measures[m].notes[j].tieStart && score.measures[m].notes[j].diatonic == n.diatonic && sameLane(score.measures[m].notes[j], n) {
            score.measures[m].notes[j].tieStart = false
        }
        if members.count > 1 {
            score.measures[m].notes.remove(at: i)
            // The first of a chord carries its place in the bar; if it went, the next takes over.
            if !n.chord, let next = score.measures[m].notes.indices.first(where: { sameLane(score.measures[m].notes[$0], n) && score.measures[m].notes[$0].tick == n.tick && score.measures[m].notes[$0].chord }) {
                score.measures[m].notes[next].chord = false
            }
        } else {
            var r = n
            r.diatonic = nil; r.alter = 0; r.accidental = nil; r.tieStart = false
            r.articulations = []; r.lyric = nil; r.lyricText = nil; r.syllabic = nil; r.beams = [:]; r.stem = nil; r.chord = false
            score.measures[m].notes[i] = r
        }
        beam(&score, measure: m)
        return true
    }

    // MARK: Place and resize

    private static func blank(like n: PNote, tick: Int, _ step: (ticks: Int, type: String, dots: Int), tuplet: Int = 0) -> PNote {
        var r = n
        r.tick = tick; r.duration = step.ticks; r.type = step.type; r.dots = step.dots; r.tuplet = tuplet
        r.measureRest = false; r.hidden = false; r.chord = false
        r.diatonic = nil; r.alter = 0; r.accidental = nil; r.tieStart = false
        r.articulations = []; r.lyric = nil; r.lyricText = nil; r.syllabic = nil; r.beams = [:]; r.stem = nil
        return r
    }

    /// After `members` (a note, its chord, or a rest) was set to end at `newEnd`: whatever else in its lane now starts
    /// inside it is overwritten, and any time left over after it (it got shorter, or overwrote part of a longer note)
    /// is filled with rests. The bar stays the right length.
    private static func settle(_ score: inout ParsedScore, measure m: Int, members: Set<Int>, start: Int, oldEnd: Int, newEnd: Int, oldTuplet: Int = 0) {
        guard let lead = members.min() else { return }
        let lane = score.measures[m].notes[lead]
        var cover = oldEnd, coverTuplet = oldTuplet
        var out: [PNote] = []
        for (k, n) in score.measures[m].notes.enumerated() {
            if members.contains(k) { out.append(n); continue }
            if sameLane(n, lane), n.tick >= start, n.tick < newEnd {
                if !n.chord, n.tick + n.duration > cover { cover = n.tick + n.duration; coverTuplet = n.tuplet }
                continue
            }
            out.append(n)
        }
        // Time left over is rested in the same kind of length as whatever it was taken from.
        let tuplet = lane.tuplet > 1 ? lane.tuplet : coverTuplet
        var tick = newEnd
        for piece in restPieces(max(0, cover - newEnd), at: newEnd, beat: beat(at: m, in: score), tuplet: tuplet) {
            out.append(blank(like: lane, tick: tick, (piece.ticks, piece.type, piece.dots), tuplet: piece.tuplet)); tick += piece.ticks
        }
        score.measures[m].notes = out
    }

    /// Whether a voice of a bar runs from its start to its end with no gap and no overlap.
    private static func laneComplete(_ s: ParsedScore, _ m: Int, staff: Int, voice: String) -> Bool {
        var at = 0
        for n in s.measures[m].notes.filter({ $0.staff == staff && $0.voice == voice && !$0.chord }).sorted(by: { $0.tick < $1.tick }) {
            if n.tick != at { return false }
            at = n.tick + n.duration
        }
        return at == s.measures[m].length
    }

    /// Runs an edit with the length asked for; if that leaves a gap no rest can fill (a plain note cut across a triplet, say),
    /// the next shorter length is tried, and so on, so a bar that was complete stays complete.
    private static func fitted<T>(_ score: inout ParsedScore, measure m: Int, index i: Int, ticks wanted: Int, tuplet: Int, _ apply: (inout ParsedScore, Int, Int) -> T?) -> T? {
        guard score.measures.indices.contains(m), score.measures[m].notes.indices.contains(i) else { return nil }
        let lane = score.measures[m].notes[i], was = laneComplete(score, m, staff: lane.staff, voice: lane.voice)
        var attempt = wanted, kind = tuplet
        var first: (score: ParsedScore, result: T)?
        while true {
            var trial = score
            if let result = apply(&trial, attempt, kind) {
                if first == nil { first = (trial, result) }
                if !was || laneComplete(trial, m, staff: lane.staff, voice: lane.voice) { score = trial; return result }
            }
            if let cur = step(atMost: attempt, tuplet: kind), let shorter = step(atMost: cur.ticks - 1, tuplet: kind) { attempt = shorter.ticks; continue }
            // Nothing shorter fits: the element's own length always does.
            if attempt != lane.duration || kind != lane.tuplet {
                attempt = lane.duration; kind = lane.tuplet
                var trial = score
                if let result = apply(&trial, attempt, kind), laneComplete(trial, m, staff: lane.staff, voice: lane.voice) { score = trial; return result }
            }
            // Nothing keeps a complete bar complete: leave it as it was.
            if !was, let f = first { score = f.score; return f.result }
            return nil
        }
    }

    /// Puts a note on a rest. A longer note than the rest takes over what follows it in the bar (up to the barline);
    /// a shorter one leaves rests. Returns the index of the new note.
    @discardableResult
    static func place(_ score: inout ParsedScore, measure m: Int, rest i: Int, diatonic: Int, ticks wanted: Int, tuplet: Int = 0) -> Int? {
        fitted(&score, measure: m, index: i, ticks: wanted, tuplet: tuplet) { placeOnce(&$0, measure: m, rest: i, diatonic: diatonic, ticks: $1, tuplet: $2) }
    }

    private static func placeOnce(_ score: inout ParsedScore, measure m: Int, rest i: Int, diatonic: Int, ticks wanted: Int, tuplet: Int) -> Int? {
        guard score.measures.indices.contains(m), score.measures[m].notes.indices.contains(i), score.measures[m].notes[i].diatonic == nil else { return nil }
        var r = score.measures[m].notes[i]
        let length = score.measures[m].length
        if r.measureRest { r.measureRest = false; r.duration = length; r.tick = 0; r.type = "whole"; r.dots = 0 }   // a bar's rest is the whole bar
        guard let step = step(atMost: min(wanted, length - r.tick), tuplet: tuplet) else { return nil }
        let oldEnd = r.tick + r.duration, oldTuplet = r.tuplet
        var note = r
        note.tuplet = tuplet
        note.diatonic = max(0, diatonic); note.alter = ParsedScore.keyAlter(key(at: m, in: score), note.diatonic!.mod(7)); note.accidental = nil
        note.duration = step.ticks; note.type = step.type; note.dots = step.dots
        note.hidden = false; note.beams = [:]; note.tieStart = false
        score.measures[m].notes[i] = note
        settle(&score, measure: m, members: [i], start: note.tick, oldEnd: oldEnd, newEnd: note.tick + step.ticks, oldTuplet: oldTuplet)
        beam(&score, measure: m)
        return score.measures[m].notes.firstIndex { $0.tick == note.tick && sameLane($0, note) && $0.diatonic == note.diatonic && !$0.chord }
    }

    /// Changes how long a note lasts. Shorter leaves rests; longer takes over what follows it in the bar.
    @discardableResult
    static func resize(_ score: inout ParsedScore, measure m: Int, index i: Int, ticks wanted: Int, tuplet: Int = 0) -> Bool {
        fitted(&score, measure: m, index: i, ticks: wanted, tuplet: tuplet) { resizeOnce(&$0, measure: m, index: i, ticks: $1, tuplet: $2) ? true : nil } ?? false
    }

    private static func resizeOnce(_ score: inout ParsedScore, measure m: Int, index i: Int, ticks wanted: Int, tuplet: Int) -> Bool {
        guard score.measures.indices.contains(m), score.measures[m].notes.indices.contains(i), score.measures[m].notes[i].diatonic != nil else { return false }
        let n = score.measures[m].notes[i]
        guard let step = step(atMost: min(wanted, score.measures[m].length - n.tick), tuplet: tuplet), step.ticks != n.duration || tuplet != n.tuplet else { return false }
        let members = Set(score.measures[m].notes.indices.filter { sameLane(score.measures[m].notes[$0], n) && score.measures[m].notes[$0].tick == n.tick })
        for k in members {
            score.measures[m].notes[k].duration = step.ticks
            score.measures[m].notes[k].type = step.type
            score.measures[m].notes[k].dots = step.dots
            score.measures[m].notes[k].tuplet = tuplet
            score.measures[m].notes[k].beams = [:]
        }
        settle(&score, measure: m, members: members, start: n.tick, oldEnd: n.tick + n.duration, newEnd: n.tick + step.ticks, oldTuplet: n.tuplet)
        beam(&score, measure: m)
        return true
    }

    // ponytail: triplets are the only tuplets the editor can write (the file reader keeps any it finds); a bar is edited in
    // its first voice per staff. Upgrade: a tuplet ladder per ratio, and voice choice.
    // MARK: Free editing (no help)

    /// With the editor's help off, a change does exactly what was asked and nothing else: no clamping to the bar, nothing
    /// overwritten, no rests added. A bar can end up too long or too short.
    static func exactLength(_ wanted: Int, tuplet: Int) -> (ticks: Int, type: String, dots: Int)? { step(atMost: wanted, tuplet: tuplet) }

    @discardableResult
    static func placeFree(_ score: inout ParsedScore, measure m: Int, rest i: Int, diatonic: Int, ticks wanted: Int, tuplet: Int = 0) -> Int? {
        guard score.measures.indices.contains(m), score.measures[m].notes.indices.contains(i), score.measures[m].notes[i].diatonic == nil, let step = exactLength(wanted, tuplet: tuplet) else { return nil }
        var n = score.measures[m].notes[i]
        if n.measureRest { n.measureRest = false; n.tick = 0 }
        n.tuplet = tuplet
        n.diatonic = max(0, diatonic); n.alter = ParsedScore.keyAlter(key(at: m, in: score), n.diatonic!.mod(7)); n.accidental = nil
        n.duration = step.ticks; n.type = step.type; n.dots = step.dots; n.hidden = false; n.beams = [:]; n.tieStart = false
        score.measures[m].notes[i] = n
        beam(&score, measure: m)
        return i
    }

    /// A new note after everything in the staff's bar, even when the bar is already full.
    @discardableResult
    static func append(_ score: inout ParsedScore, measure m: Int, staff: Int, diatonic: Int, ticks wanted: Int, tuplet: Int = 0) -> Int? {
        guard score.measures.indices.contains(m), let step = exactLength(wanted, tuplet: tuplet) else { return nil }
        let lane = score.measures[m].notes.filter { $0.staff == staff && $0.voice == (score.measures[m].notes.first { $0.staff == staff }?.voice ?? "1") && !$0.chord }
        var n = lane.first ?? PNote()
        n = blank(like: n, tick: lane.map { $0.tick + $0.duration }.max() ?? 0, step, tuplet: tuplet)
        n.staff = staff; n.hidden = false
        n.diatonic = max(0, diatonic); n.alter = ParsedScore.keyAlter(key(at: m, in: score), n.diatonic!.mod(7))
        score.measures[m].notes.append(n)
        beam(&score, measure: m)
        return score.measures[m].notes.count - 1
    }

    @discardableResult
    static func resizeFree(_ score: inout ParsedScore, measure m: Int, index i: Int, ticks wanted: Int, tuplet: Int = 0) -> Bool {
        guard score.measures.indices.contains(m), score.measures[m].notes.indices.contains(i), let step = exactLength(wanted, tuplet: tuplet) else { return false }
        let n = score.measures[m].notes[i]
        guard step.ticks != n.duration || tuplet != n.tuplet else { return false }
        for k in score.measures[m].notes.indices where sameLane(score.measures[m].notes[k], n) && score.measures[m].notes[k].tick == n.tick {
            score.measures[m].notes[k].duration = step.ticks; score.measures[m].notes[k].type = step.type
            score.measures[m].notes[k].dots = step.dots; score.measures[m].notes[k].tuplet = tuplet
            score.measures[m].notes[k].measureRest = false; score.measures[m].notes[k].beams = [:]
        }
        beam(&score, measure: m)
        return true
    }

    @discardableResult
    static func setRestFree(_ score: inout ParsedScore, measure m: Int, index i: Int, ticks wanted: Int, tuplet: Int = 0) -> Int? {
        guard score.measures.indices.contains(m), score.measures[m].notes.indices.contains(i), let step = exactLength(wanted, tuplet: tuplet) else { return nil }
        let n = score.measures[m].notes[i]
        if n.diatonic == nil { return resizeFree(&score, measure: m, index: i, ticks: wanted, tuplet: tuplet) ? i : nil }
        var rest = blank(like: n, tick: n.tick, step, tuplet: tuplet)
        rest.measureRest = false
        score.measures[m].notes[i] = rest
        // The rest of a chord goes with it.
        score.measures[m].notes.removeAll { sameLane($0, n) && $0.tick == n.tick && $0.diatonic != nil }
        beam(&score, measure: m)
        return score.measures[m].notes.firstIndex { $0.tick == n.tick && sameLane($0, n) && $0.diatonic == nil }
    }

    // MARK: Lyrics

    /// ponytail: syllables go to the top staff's notes in order, ignoring any timing in the file and melisma (one note, one
    /// syllable). Upgrade: place words by the file's times, with a hold marker for a syllable that spans notes.
    /// Puts a lyrics file's words under the notes of the top staff, one syllable a note, in order. A score that already has
    /// words of its own is left alone. A tied note carries one syllable, on its first head. Returns how many notes got one.
    @discardableResult
    static func addLyrics(_ score: inout ParsedScore, syllables: [(text: String, wordEnd: Bool)]) -> Int {
        guard !syllables.isEmpty, !score.measures.contains(where: { $0.notes.contains { $0.lyricText != nil } }) else { return 0 }
        var next = 0, wordStart = true, given = 0
        var tiedInto: Set<String> = []   // staff|pitch|tick where a tie arrives
        for m in score.measures.indices {
            var heads = score.measures[m].notes.indices.filter { score.measures[m].notes[$0].staff == 0 && score.measures[m].notes[$0].diatonic != nil && !score.measures[m].notes[$0].chord }
            heads.sort { score.measures[m].notes[$0].tick < score.measures[m].notes[$1].tick }
            var carried: Set<String> = []
            for i in heads {
                let n = score.measures[m].notes[i]
                let key = "\(n.diatonic!)|\(n.tick)"
                let arrives = tiedInto.contains(key)
                if n.tieStart { carried.insert("\(n.diatonic!)|\(n.tick + n.duration)") }
                if arrives || next >= syllables.count { continue }
                let syl = syllables[next]; next += 1
                let end = syl.wordEnd
                score.measures[m].notes[i].lyricText = syl.text
                score.measures[m].notes[i].syllabic = wordStart ? (end ? "single" : "begin") : (end ? "end" : "middle")
                score.measures[m].notes[i].lyric = syl.text + (end ? "" : " -")
                wordStart = end
                given += 1
            }
            // A tie into the next bar arrives at its first tick (tick 0 there).
            tiedInto = Set(carried.filter { $0.hasSuffix("|\(score.measures[m].length)") }.map { String($0.split(separator: "|")[0]) + "|0" })
        }
        return given
    }

    // MARK: Ties

    /// Ties a note to the next note of its voice, or takes the tie off. With help, the next note must be a note, and takes
    /// the same pitch; without, the tie is simply drawn.
    @discardableResult
    static func toggleTie(_ score: inout ParsedScore, measure m: Int, index i: Int, free: Bool) -> Bool {
        guard score.measures.indices.contains(m), score.measures[m].notes.indices.contains(i), let d = score.measures[m].notes[i].diatonic else { return false }
        if score.measures[m].notes[i].tieStart { score.measures[m].notes[i].tieStart = false; return true }
        let n = score.measures[m].notes[i]
        if !free {
            // The next element of the voice: in this bar, or the first of the next bar.
            let end = n.tick + n.duration
            var next: (bar: Int, index: Int)?
            let here = score.measures[m].notes.indices.filter { sameLane(score.measures[m].notes[$0], n) && !score.measures[m].notes[$0].chord && score.measures[m].notes[$0].tick >= end }
                .min { score.measures[m].notes[$0].tick < score.measures[m].notes[$1].tick }
            if let h = here { next = (m, h) }
            else if m + 1 < score.measures.count,
                    let h = score.measures[m + 1].notes.indices.filter({ sameLane(score.measures[m + 1].notes[$0], n) && !score.measures[m + 1].notes[$0].chord })
                        .min(by: { score.measures[m + 1].notes[$0].tick < score.measures[m + 1].notes[$1].tick }) { next = (m + 1, h) }
            guard let (bar, h) = next, score.measures[bar].notes[h].diatonic != nil else { return false }
            score.measures[bar].notes[h].diatonic = d
            score.measures[bar].notes[h].alter = n.alter
            score.measures[bar].notes[h].accidental = nil
        }
        score.measures[m].notes[i].tieStart = true
        return true
    }

    // MARK: Beams

    /// Beams eighths and shorter within each beat, per staff and voice; everything else stands alone with a flag.
    static func beam(_ score: inout ParsedScore, measure m: Int) {
        guard score.measures.indices.contains(m) else { return }
        for k in score.measures[m].notes.indices { score.measures[m].notes[k].beams = [:] }
        let lanes = Dictionary(grouping: score.measures[m].notes.indices, by: { "\(score.measures[m].notes[$0].staff)|\(score.measures[m].notes[$0].voice)" })
        for (_, idx) in lanes {
            // One entry per chord (its first note), in time order.
            let heads = idx.filter { !score.measures[m].notes[$0].chord }.sorted { score.measures[m].notes[$0].tick < score.measures[m].notes[$1].tick }
            var group: [Int] = []
            func flush() {
                defer { group = [] }
                guard group.count > 1 else { return }
                for (n, h) in group.enumerated() {
                    let kind = n == 0 ? "begin" : n == group.count - 1 ? "end" : "continue"
                    apply(h, level: 1, kind)
                }
                // Second beam across runs of sixteenths.
                var run: [Int] = []
                func closeRun() {
                    defer { run = [] }
                    guard run.count > 1 else { return }
                    for (n, h) in run.enumerated() { apply(h, level: 2, n == 0 ? "begin" : n == run.count - 1 ? "end" : "continue") }
                }
                for h in group { if score.measures[m].notes[h].duration <= 120 { run.append(h) } else { closeRun() } }
                closeRun()
            }
            func apply(_ h: Int, level: Int, _ kind: String) {
                let tick = score.measures[m].notes[h].tick
                for k in idx where score.measures[m].notes[k].tick == tick { score.measures[m].notes[k].beams[level] = kind }
            }
            for h in heads {
                let n = score.measures[m].notes[h]
                let beamable = n.diatonic != nil && !n.hidden && n.duration <= 240 && n.duration > 0
                if beamable, let last = group.last {
                    let prev = score.measures[m].notes[last]
                    if prev.tick + prev.duration == n.tick && prev.tick / 480 == n.tick / 480 { group.append(h) } else { flush(); group = [h] }
                } else if beamable { group = [h] } else { flush() }
            }
            flush()
        }
    }

    // MARK: Rests

    /// Makes the element at `i` a rest of `ticks` (a rest changes length; a note becomes a rest). A longer rest takes over
    /// what follows it in the bar; a shorter one leaves rests. Returns the index of the new rest.
    @discardableResult
    static func setRest(_ score: inout ParsedScore, measure m: Int, index i: Int, ticks wanted: Int, tuplet: Int = 0) -> Int? {
        fitted(&score, measure: m, index: i, ticks: wanted, tuplet: tuplet) { setRestOnce(&$0, measure: m, index: i, ticks: $1, tuplet: $2) }
    }

    private static func setRestOnce(_ score: inout ParsedScore, measure m: Int, index i: Int, ticks wanted: Int, tuplet: Int) -> Int? {
        guard score.measures.indices.contains(m), score.measures[m].notes.indices.contains(i) else { return nil }
        var base = score.measures[m].notes[i]
        if base.measureRest { base.measureRest = false; base.tick = 0; base.duration = score.measures[m].length }
        guard let first = step(atMost: min(wanted, score.measures[m].length - base.tick), tuplet: tuplet) else { return nil }
        let oldTuplet = base.tuplet
        let members = score.measures[m].notes.indices.filter { sameLane(score.measures[m].notes[$0], base) && score.measures[m].notes[$0].tick == base.tick }
        let anchor = members.min() ?? i
        let oldEnd = base.tick + base.duration
        // Ties into a note that is going lead nowhere.
        if base.diatonic != nil {
            for j in score.measures[m].notes.indices where score.measures[m].notes[j].tieStart && score.measures[m].notes[j].diatonic == base.diatonic && sameLane(score.measures[m].notes[j], base) { score.measures[m].notes[j].tieStart = false }
        }
        score.measures[m].notes[anchor] = blank(like: base, tick: base.tick, first, tuplet: tuplet)
        // The rest of a chord goes; the anchor (the lowest index) keeps its place.
        let gone = Set(members).subtracting([anchor])
        score.measures[m].notes = score.measures[m].notes.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
        settle(&score, measure: m, members: [anchor], start: base.tick, oldEnd: oldEnd, newEnd: base.tick + first.ticks, oldTuplet: oldTuplet)
        beam(&score, measure: m)
        return score.measures[m].notes.firstIndex { $0.tick == base.tick && sameLane($0, base) && $0.diatonic == nil }
    }

    /// Takes a rest off the page: it stays in the bar as an invisible rest, so every bar keeps its length.
    @discardableResult
    static func deleteRest(_ score: inout ParsedScore, measure m: Int, index i: Int) -> Bool {
        guard score.measures.indices.contains(m), score.measures[m].notes.indices.contains(i), score.measures[m].notes[i].diatonic == nil else { return false }
        if score.measures[m].notes[i].measureRest {
            // A bar's rest: make it an explicit whole-bar rest, then hide it.
            score.measures[m].notes[i].measureRest = false
            score.measures[m].notes[i].duration = score.measures[m].length
            score.measures[m].notes[i].tick = 0
        }
        score.measures[m].notes[i].hidden = true
        return true
    }

    /// Every bar must last its full length in every part: a short bar is filled out with rests. Returns how many bars needed it.
    @discardableResult
    static func fillShortBars(_ score: inout ParsedScore) -> Int {
        var fixed = 0
        for m in score.measures.indices {
            let length = score.measures[m].length
            let lanes = Dictionary(grouping: score.measures[m].notes.filter { !$0.chord }, by: { "\($0.staff)|\($0.voice)" })
            var added = false
            for (_, items) in lanes {
                let end = items.map { $0.tick + $0.duration }.max() ?? 0
                guard end < length, let template = items.first else { continue }
                var tick = end
                for piece in restPieces(length - end, at: end, beat: beat(at: m, in: score), tuplet: 0) {
                    var r = blank(like: template, tick: tick, (piece.ticks, piece.type, piece.dots), tuplet: piece.tuplet); r.hidden = true
                    score.measures[m].notes.append(r); tick += piece.ticks
                }
                added = true
            }
            if added { fixed += 1; beam(&score, measure: m) }
        }
        return fixed
    }

    // MARK: Bars and repeats

    /// Start ticks follow from the bar lengths.
    static func renumber(_ score: inout ParsedScore) {
        var t = 0
        for i in score.measures.indices { score.measures[i].start = t; t += score.measures[i].length }
    }

    static func toggleRepeatStart(_ score: inout ParsedScore, measure m: Int) {
        guard score.measures.indices.contains(m) else { return }
        score.measures[m].flow.repeatStart.toggle()
    }

    /// Off, then repeat twice, three times, four times.
    static func cycleRepeatEnd(_ score: inout ParsedScore, measure m: Int) {
        guard score.measures.indices.contains(m) else { return }
        let n = score.measures[m].flow.repeatEnd
        score.measures[m].flow.repeatEnd = n == 0 ? 2 : n >= 4 ? 0 : n + 1
    }

    /// Marks the bar as a first, second (…) time bar, or clears it. A first-time bar closes with the repeat sign.
    static func toggleEnding(_ score: inout ParsedScore, measure m: Int, number: Int) {
        guard score.measures.indices.contains(m) else { return }
        let on = score.measures[m].flow.endings != [number]
        score.measures[m].flow.endings = on ? [number] : []
        if on, number == 1, score.measures[m].flow.repeatEnd == 0, m + 1 >= score.measures.count || score.measures[m + 1].flow.endings != [1] {
            score.measures[m].flow.repeatEnd = 2
        }
    }

    /// Takes the time bar off the bar, and with `whole`, off every bar of its bracket. A repeat sign it was carrying stays
    /// on the last bar that had the bracket.
    static func clearEnding(_ score: inout ParsedScore, measure m: Int, whole: Bool = false) {
        guard score.measures.indices.contains(m), !score.measures[m].flow.endings.isEmpty else { return }
        let ending = score.measures[m].flow.endings
        var lo = m, hi = m
        if whole {
            while lo > 0, score.measures[lo - 1].flow.endings == ending { lo -= 1 }
            while hi + 1 < score.measures.count, score.measures[hi + 1].flow.endings == ending { hi += 1 }
        }
        for i in lo...hi { score.measures[i].flow.endings = [] }
    }

    /// Stretches the bar's bracket over the bar after it (a first or second time that lasts several bars).
    @discardableResult
    static func extendEnding(_ score: inout ParsedScore, measure m: Int) -> Bool {
        guard score.measures.indices.contains(m + 1), !score.measures[m].flow.endings.isEmpty else { return false }
        let ending = score.measures[m].flow.endings
        // The repeat sign belongs on the bracket's last bar.
        if score.measures[m].flow.repeatEnd > 0 && ending == [1] {
            score.measures[m + 1].flow.repeatEnd = score.measures[m].flow.repeatEnd
            score.measures[m].flow.repeatEnd = 0
        }
        score.measures[m + 1].flow.endings = ending
        return true
    }

    /// Takes the bar off the end of its bracket (the bracket must have more than one bar).
    @discardableResult
    static func shortenEnding(_ score: inout ParsedScore, measure m: Int) -> Bool {
        guard score.measures.indices.contains(m), m > 0, !score.measures[m].flow.endings.isEmpty, score.measures[m - 1].flow.endings == score.measures[m].flow.endings else { return false }
        if score.measures[m].flow.repeatEnd > 0 && score.measures[m].flow.endings == [1] {
            score.measures[m - 1].flow.repeatEnd = score.measures[m].flow.repeatEnd
            score.measures[m].flow.repeatEnd = 0
        }
        score.measures[m].flow.endings = []
        return true
    }

    enum Sign: String, CaseIterable {
        case segno = "Segno", coda = "Coda", toCoda = "To Coda"
        case daCapo = "D.C.", dcAlCoda = "D.C. al Coda", dcAlFine = "D.C. al Fine"
        case dalSegno = "D.S.", dsAlCoda = "D.S. al Coda", dsAlFine = "D.S. al Fine", fine = "Fine"

        /// The jump or stop it makes in the bar's flow.
        fileprivate var key: WritableKeyPath<Flow, Bool> {
            switch self {
            case .segno: \.segno
            case .coda: \.coda
            case .toCoda: \.toCoda
            case .daCapo, .dcAlCoda, .dcAlFine: \.daCapo
            case .dalSegno, .dsAlCoda, .dsAlFine: \.dalSegno
            case .fine: \.fine
            }
        }
        /// The words printed above the bar (the segno and coda are drawn as signs).
        var words: String? { self == .segno || self == .coda ? nil : rawValue }
        /// Wordings that share one flag (a bar has one D.C. at a time).
        fileprivate var family: [Sign] { [.daCapo, .dcAlCoda, .dcAlFine].contains(self) ? [.daCapo, .dcAlCoda, .dcAlFine] : [.dalSegno, .dsAlCoda, .dsAlFine].contains(self) ? [.dalSegno, .dsAlCoda, .dsAlFine] : [self] }
    }

    static func has(_ sign: Sign, _ f: Flow) -> Bool { f[keyPath: sign.key] }

    /// Whether the bar carries this very sign or wording.
    static func has(_ sign: Sign, in score: ParsedScore, measure m: Int) -> Bool {
        guard score.measures.indices.contains(m), has(sign, score.measures[m].flow) else { return false }
        guard let w = sign.words else { return true }
        return score.measures[m].marks.contains { !$0.dynamic && $0.text == w }
    }

    /// Jumps and Fine also get their words above the bar, so they show on the page. A bar can have one wording of each jump.
    static func toggle(_ sign: Sign, _ score: inout ParsedScore, measure m: Int) {
        guard score.measures.indices.contains(m) else { return }
        let on = !has(sign, in: score, measure: m)
        score.measures[m].flow[keyPath: sign.key] = on
        let family = Set(sign.family.compactMap(\.words))
        score.measures[m].marks.removeAll { !$0.dynamic && family.contains($0.text) }
        if on, let w = sign.words { score.measures[m].marks.append((tick: 0, staff: 0, text: w, dynamic: false)) }
    }

    // MARK: Tempo marks

    /// The tempo in force at a bar (the last mark at or before it), in quarter-note beats a minute.
    static func tempo(at m: Int, in score: ParsedScore, fallback: Double) -> Double {
        var t = score.tempo ?? fallback
        for i in 0...min(max(m, 0), max(score.measures.count - 1, 0)) where i < score.measures.count { if let x = score.measures[i].tempo { t = x } }
        return t
    }

    /// Puts a printed tempo mark (♩ = 96) on a bar, or takes the bar's mark off (`bpm` nil). The first mark in a piece with
    /// no tempo of its own makes the current playing tempo the opening one, so later marks are relative to it.
    static func setTempo(_ score: inout ParsedScore, measure m: Int, bpm: Double?, opening: Double) {
        guard score.measures.indices.contains(m) else { return }
        if score.tempo == nil { score.tempo = m == 0 ? bpm ?? opening : opening }
        score.measures[m].tempo = bpm.map { max(20, min(300, $0)) }
        score.measures[m].tempoShown = bpm != nil
    }

    // MARK: Expand repeats

    /// Writes the piece out as it is played: every repeat, ending, and D.C./D.S. jump becomes its own bars, and the
    /// signs that asked for them go. Returns false when there is nothing to expand.
    @discardableResult
    static func expandRepeats(_ score: inout ParsedScore) -> Bool {
        let order = score.playOrder
        guard order != Array(score.measures.indices), !order.isEmpty else { return false }
        // What is in force at each original bar, so a copy only restates a key, metre or clef that changed.
        var keys: [Int] = [], times: [(beats: Int, type: Int)] = [], clefs: [[Int: Clef]] = []
        var key = 0, time = (beats: 4, type: 4), clef: [Int: Clef] = [:]
        for m in score.measures {
            if let k = m.key { key = k }
            if let t = m.time { time = t }
            for (s, c) in m.clefs { clef[s] = c }
            keys.append(key); times.append(time); clefs.append(clef)
        }
        let jumpWords = ["d.c.", "d.s.", "da capo", "dal segno", "fine", "to coda"]
        var out: [PMeasure] = []
        var shownKey = 0, shownTime = (beats: 4, type: 4), shownClefs: [Int: Clef] = [:]
        for (n, i) in order.enumerated() {
            var m = score.measures[i]
            m.flow = Flow(multiRest: m.flow.multiRest)
            m.finalBar = false
            m.marks.removeAll { mark in !mark.dynamic && jumpWords.contains { mark.text.lowercased().contains($0) } }
            m.key = n == 0 || keys[i] != shownKey ? keys[i] : nil
            m.time = n == 0 || times[i] != shownTime ? times[i] : nil
            m.clefs = clefs[i].filter { shownClefs[$0.key] != $0.value }
            if n == 0 { m.key = score.measures[0].key; m.time = score.measures[0].time; m.clefs = score.measures[0].clefs }
            shownKey = keys[i]; shownTime = times[i]; shownClefs = clefs[i]
            // Back at the start of the piece, the opening tempo comes back with it.
            if i == 0, n > 0, m.tempo == nil { m.tempo = score.tempo }
            out.append(m)
        }
        out[out.count - 1].finalBar = true
        score.measures = out
        renumber(&score)
        return true
    }

    /// An empty bar after bar `m`, the same length, resting in every staff.
    static func insertBar(_ score: inout ParsedScore, after m: Int) {
        guard score.measures.indices.contains(m) else { return }
        var bar = PMeasure()
        bar.length = score.measures[m].length
        for s in 0..<max(1, score.staffCount) {
            var rest = PNote()
            rest.tick = 0; rest.duration = bar.length; rest.staff = s; rest.type = "whole"; rest.measureRest = true; rest.diatonic = nil
            bar.notes.append(rest)
        }
        // Adding after the last bar: the closing barline moves to the new bar.
        if m == score.measures.count - 1, score.measures[m].finalBar { score.measures[m].finalBar = false; bar.finalBar = true }
        // A hairpin that runs across the gap gets longer.
        for j in 0...m { for k in score.measures[j].hairpins.indices where j + score.measures[j].hairpins[k].span > m { score.measures[j].hairpins[k].span += 1 } }
        score.measures.insert(bar, at: m + 1)
        renumber(&score)
    }

    /// Removes a bar (never the last one); a key, metre or clef change on it moves to the next bar.
    @discardableResult
    static func deleteBar(_ score: inout ParsedScore, measure m: Int) -> Bool {
        guard score.measures.count > 1, score.measures.indices.contains(m) else { return false }
        let gone = score.measures[m]
        // Hairpins that ran through or into the bar end a bar sooner.
        for j in 0..<m {
            for k in score.measures[j].hairpins.indices.reversed() where j + score.measures[j].hairpins[k].span >= m {
                score.measures[j].hairpins[k].span -= 1
                score.measures[j].hairpins[k].endTick = min(score.measures[j].hairpins[k].endTick, score.measures[min(m, score.measures.count - 1)].length)
            }
        }
        score.measures.remove(at: m)
        if gone.finalBar, m > 0 { score.measures[m - 1].finalBar = true }
        if m < score.measures.count {
            if score.measures[m].key == nil { score.measures[m].key = gone.key }
            if score.measures[m].time == nil { score.measures[m].time = gone.time }
            for (s, c) in gone.clefs where score.measures[m].clefs[s] == nil { score.measures[m].clefs[s] = c }
            if gone.flow.repeatStart { score.measures[m].flow.repeatStart = true }
        }
        renumber(&score)
        return true
    }

    // MARK: Articulations

    static let articulations: [(name: String, label: String)] = [("staccato", "Staccato"), ("accent", "Accent"), ("tenuto", "Tenuto"), ("strong-accent", "Marcato"), ("fermata", "Fermata")]

    /// Adds an articulation to a note, or takes it off if it has it.
    static func toggleArticulation(_ score: inout ParsedScore, measure m: Int, index i: Int, _ name: String) {
        guard score.measures.indices.contains(m), score.measures[m].notes.indices.contains(i), score.measures[m].notes[i].diatonic != nil else { return }
        if let at = score.measures[m].notes[i].articulations.firstIndex(of: name) { score.measures[m].notes[i].articulations.remove(at: at) }
        else { score.measures[m].notes[i].articulations.append(name) }
    }

    // MARK: Dynamics

    static let dynamicNames = ["ppp", "pp", "p", "mp", "mf", "f", "ff", "fff"]

    /// Puts a dynamic (p, mf, ff…) at a tick of the bar in place of any that is there, or takes it off (`text` nil).
    static func setDynamic(_ score: inout ParsedScore, measure m: Int, tick: Int, text: String?) {
        guard score.measures.indices.contains(m) else { return }
        score.measures[m].marks.removeAll { $0.dynamic && $0.tick == tick && $0.staff == 0 }
        if let text { score.measures[m].marks.append((tick: tick, staff: 0, text: text, dynamic: true)) }
    }

    static func dynamic(in score: ParsedScore, measure m: Int, tick: Int) -> String? {
        guard score.measures.indices.contains(m) else { return nil }
        return score.measures[m].marks.first { $0.dynamic && $0.tick == tick && $0.staff == 0 }?.text
    }

    /// A crescendo (or diminuendo) over the whole bar; the same again takes it off.
    static func toggleHairpin(_ score: inout ParsedScore, measure m: Int, crescendo: Bool) {
        guard score.measures.indices.contains(m) else { return }
        let had = score.measures[m].hairpins.contains { $0.crescendo == crescendo && $0.startTick == 0 }
        score.measures[m].hairpins.removeAll { $0.staff == 0 && $0.startTick == 0 }
        if !had { score.measures[m].hairpins.append(Hairpin(crescendo: crescendo, staff: 0, startTick: 0, span: 0, endTick: score.measures[m].length)) }
    }

    static func hairpin(in score: ParsedScore, measure m: Int) -> Hairpin? {
        score.measures.indices.contains(m) ? score.measures[m].hairpins.first { $0.staff == 0 && $0.startTick == 0 } : nil
    }

    /// Stretches the bar's hairpin over the bar after it, or pulls it back a bar.
    @discardableResult
    static func resizeHairpin(_ score: inout ParsedScore, measure m: Int, by bars: Int) -> Bool {
        guard score.measures.indices.contains(m), let k = score.measures[m].hairpins.firstIndex(where: { $0.staff == 0 && $0.startTick == 0 }) else { return false }
        let span = score.measures[m].hairpins[k].span + bars
        guard span >= 0, m + span < score.measures.count else { return false }
        score.measures[m].hairpins[k].span = span
        score.measures[m].hairpins[k].endTick = score.measures[m + span].length
        return true
    }

    // MARK: Pencil strokes

    /// A back-and-forth scribble in any direction: the pencil doubles back sharply several times in a small area,
    /// and the path is long for the room it covers. A straight drag or a slow arc is not one.
    static func isScribble(_ points: [CGPoint], space: CGFloat) -> Bool {
        guard points.count >= 6 else { return false }
        // Thin the path so sensor jitter and very dense samples don't count as turns.
        var path = [points[0]]
        for p in points.dropFirst() where hypot(p.x - path.last!.x, p.y - path.last!.y) >= space * 0.35 { path.append(p) }
        guard path.count >= 5 else { return false }
        let xs = path.map(\.x), ys = path.map(\.y)
        let w = xs.max()! - xs.min()!, h = ys.max()! - ys.min()!
        var length: CGFloat = 0
        for (a, b) in zip(path, path.dropFirst()) { length += hypot(b.x - a.x, b.y - a.y) }
        // Sharp turns: the direction changes by well over a right angle.
        var turns = 0
        var i = 0
        while i + 2 < path.count {
            let a = CGPoint(x: path[i + 1].x - path[i].x, y: path[i + 1].y - path[i].y)
            let b = CGPoint(x: path[i + 2].x - path[i + 1].x, y: path[i + 2].y - path[i + 1].y)
            let cos = (a.x * b.x + a.y * b.y) / max(hypot(a.x, a.y) * hypot(b.x, b.y), 0.0001)
            if cos < -0.2 { turns += 1; i += 2 } else { i += 1 }
        }
        let size = max(w, h, space)
        return turns >= 3 && length > 2.5 * size && w < space * 24 && h < space * 18
    }

    /// True if the stroke passes over the rectangle (checked along each segment, not just at its sample points).
    static func stroke(_ points: [CGPoint], crosses rect: CGRect) -> Bool {
        for (a, b) in zip(points, points.dropFirst()) {
            let steps = max(1, Int(hypot(b.x - a.x, b.y - a.y) / 2))
            for s in 0...steps {
                let f = CGFloat(s) / CGFloat(steps)
                if rect.contains(CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)) { return true }
            }
        }
        return points.count == 1 && rect.contains(points[0])
    }
}

// MARK: - Medleys: copy, cut, paste and insert bars

/// Bars taken from a score, with the key, metre, clefs and tempo they were in, so they can go into another piece.
nonisolated struct BarClip {
    var measures: [PMeasure]
    var staffCount: Int
    var key: Int
    var time: (beats: Int, type: Int)
    var clefs: [Int: Clef]
    var tempo: Double?
    var title: String
    var count: Int { measures.count }
}

nonisolated extension ScoreEdit {
    /// The key, metre and clefs in force at the end of bar `m` (nothing yet before the first bar, `m` = -1).
    static func context(at m: Int, in score: ParsedScore) -> (key: Int, time: (beats: Int, type: Int), clefs: [Int: Clef]) {
        var key = 0, time = (beats: 4, type: 4), clefs: [Int: Clef] = [:]
        if m >= 0, !score.measures.isEmpty {
            for i in 0...min(m, score.measures.count - 1) {
                if let k = score.measures[i].key { key = k }
                if let t = score.measures[i].time { time = t }
                for (s, c) in score.measures[i].clefs { clefs[s] = c }
            }
        }
        return (key, time, clefs)
    }

    /// The tempo marked at or before a bar, if the score has one anywhere before it.
    static func markedTempo(at m: Int, in score: ParsedScore) -> Double? {
        var t = score.tempo
        if m >= 0, !score.measures.isEmpty { for i in 0...min(m, score.measures.count - 1) { if let x = score.measures[i].tempo { t = x } } }
        return t
    }

    /// Semitones to move music from one key signature (in fifths) to another, the shortest way.
    static func shift(fromFifths a: Int, toFifths b: Int) -> Int {
        let d = (7 * b - 7 * a).mod(12)
        return d > 6 ? d - 12 : d
    }

    /// Copies bars out of a score.
    static func clip(from score: ParsedScore, bars: ClosedRange<Int>, title: String = "") -> BarClip? {
        guard bars.lowerBound >= 0, bars.upperBound < score.measures.count else { return nil }
        let start = context(at: bars.lowerBound, in: score)
        var measures = Array(score.measures[bars])
        for i in measures.indices {
            measures[i].finalBar = false
            // A hairpin that would run out of the copied bars stops at the last of them; a tie out of the last bar goes nowhere.
            for k in measures[i].hairpins.indices where i + measures[i].hairpins[k].span >= measures.count {
                measures[i].hairpins[k].span = measures.count - 1 - i
                measures[i].hairpins[k].endTick = measures[measures.count - 1].length
            }
        }
        for k in measures[measures.count - 1].notes.indices where measures[measures.count - 1].notes[k].tieStart { measures[measures.count - 1].notes[k].tieStart = false }
        return BarClip(measures: measures, staffCount: score.staffCount, key: start.key, time: start.time, clefs: start.clefs, tempo: markedTempo(at: bars.lowerBound, in: score), title: title)
    }

    /// Puts copied bars into a score after bar `m` (-1 = at the start). The new bars carry their own key, metre and clefs,
    /// and the music after them gets its own back; with `matchKey` the bars are moved into the key in force. Staves the piece
    /// has and the clip lacks rest; staves the clip has and the piece lacks are left out. Returns where the bars went.
    @discardableResult
    static func paste(_ score: inout ParsedScore, clip: BarClip, after m: Int, matchKey: Bool, openingTempo: Double) -> ClosedRange<Int>? {
        guard !clip.measures.isEmpty, m >= -1, m < score.measures.count, score.staffCount > 0 else { return nil }
        let before = context(at: m, in: score)
        let beforeTempo = markedTempo(at: m, in: score) ?? openingTempo
        var bars = clip.measures, key = clip.key
        if matchKey, m >= 0 {
            let moved = shift(fromFifths: clip.key, toFifths: before.key)
            if moved != 0 {
                var temp = ParsedScore(); temp.staffCount = clip.staffCount; temp.measures = bars; temp.measures[0].key = clip.key
                temp = temp.transposed(by: moved)
                bars = temp.measures; key = temp.measures[0].key ?? key
            }
        }
        let n = score.staffCount
        for i in bars.indices {
            bars[i].notes = bars[i].notes.filter { $0.staff < n }
            for s in 0..<n where !bars[i].notes.contains(where: { $0.staff == s }) {
                var r = PNote(); r.staff = s; r.duration = bars[i].length; r.type = "whole"; r.measureRest = true
                bars[i].notes.append(r)
            }
            bars[i].clefs = bars[i].clefs.filter { $0.key < n }
            bars[i].marks = bars[i].marks.filter { $0.staff < n }
            bars[i].hairpins = bars[i].hairpins.filter { $0.staff < n }
            bars[i].finalBar = false
        }
        var clefs = clip.clefs.filter { $0.key < n }
        for s in 0..<n where clefs[s] == nil { clefs[s] = before.clefs[s] ?? Clef() }
        bars[0].key = key; bars[0].time = clip.time; bars[0].clefs = clefs
        if let t = clip.tempo, abs(t - beforeTempo) > 0.5 {
            if score.tempo == nil { score.tempo = openingTempo }
            bars[0].tempo = t; bars[0].tempoShown = true
        }
        let at = m + 1, last = at + bars.count - 1
        // A hairpin running across the gap gets longer by the bars put into it.
        for j in 0..<at { for k in score.measures[j].hairpins.indices where j + score.measures[j].hairpins[k].span >= at { score.measures[j].hairpins[k].span += bars.count } }
        if at > 0, at == score.measures.count, score.measures[at - 1].finalBar { score.measures[at - 1].finalBar = false; bars[bars.count - 1].finalBar = true }
        score.measures.insert(contentsOf: bars, at: at)
        // Where the pasted music ends, the old music's own key, metre, clefs and tempo come back.
        if last + 1 < score.measures.count, m >= 0 {
            let now = context(at: last, in: score)
            var f = score.measures[last + 1]
            if f.key == nil, now.key != before.key { f.key = before.key }
            if f.time == nil, now.time != before.time { f.time = before.time }
            for (s, c) in before.clefs where s < n && f.clefs[s] == nil && now.clefs[s] != c { f.clefs[s] = c }
            if f.tempo == nil, let now = markedTempo(at: last, in: score), abs(now - beforeTempo) > 0.5 { f.tempo = beforeTempo; f.tempoShown = true }
            score.measures[last + 1] = f
        }
        renumber(&score)
        return at...last
    }

    /// Takes a run of bars out (never all of them).
    @discardableResult
    static func deleteBars(_ score: inout ParsedScore, _ bars: ClosedRange<Int>) -> Int {
        var removed = 0
        for b in bars.reversed() where deleteBar(&score, measure: b) { removed += 1 }
        return removed
    }
}
