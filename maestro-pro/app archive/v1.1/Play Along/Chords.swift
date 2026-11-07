import Foundation

// Chords: names for the harmony of a score, either the chord symbols the file carries or ones worked out from the notes,
// for the chord view (a bar-by-bar chart).
// ponytail: chords are guessed per half bar (per bar in 3/4, 2/4, 6/8) from the notes sounding then, with the lowest note
// as the bass; no key-aware reharmonisation, no sus, sixth or extended chords, and a bare melody gets a plausible triad.
// Upgrade: weigh by beat strength and the key, and look ahead for passing notes.

nonisolated struct Chord: Equatable {
    var root: Int            // pitch class, 0 = C
    var kind: String         // the symbol's ending: "", "m", "7", "maj7", "m7♭5"…
    var bass: Int?           // the bass note when it is not the root (a slash chord)

    static let sharps = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    static let flats = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    /// The symbol as printed on a chart, spelled with flats or sharps.
    func name(flats useFlats: Bool) -> String {
        let names = useFlats ? Self.flats : Self.sharps
        return names[root.mod(12)] + kind + (bass.map { "/" + names[$0.mod(12)] } ?? "")
    }

    func transposed(by semitones: Int) -> Chord { Chord(root: (root + semitones).mod(12), kind: kind, bass: bass.map { ($0 + semitones).mod(12) }) }

    /// The ending MusicXML's `<kind>` stands for.
    static func kind(fromXML kind: String) -> String {
        switch kind {
        case "major", "": ""
        case "minor": "m"
        case "dominant", "dominant-seventh": "7"
        case "major-seventh": "maj7"
        case "minor-seventh": "m7"
        case "diminished": "dim"
        case "augmented": "aug"
        case "half-diminished": "m7♭5"
        case "diminished-seventh": "dim7"
        case "suspended-fourth": "sus4"
        case "suspended-second": "sus2"
        case "major-sixth": "6"
        case "minor-sixth": "m6"
        case "dominant-ninth": "9"
        case "major-ninth": "maj9"
        case "minor-ninth": "m9"
        case "power": "5"
        default: ""
        }
    }

    /// The other way, for writing a file.
    var xmlKind: String {
        switch kind {
        case "m": "minor"
        case "7": "dominant"
        case "maj7": "major-seventh"
        case "m7": "minor-seventh"
        case "dim": "diminished"
        case "aug": "augmented"
        case "m7♭5": "half-diminished"
        case "dim7": "diminished-seventh"
        case "sus4": "suspended-fourth"
        case "sus2": "suspended-second"
        case "6": "major-sixth"
        case "m6": "minor-sixth"
        case "9": "dominant-ninth"
        case "maj9": "major-ninth"
        case "m9": "minor-ninth"
        case "5": "power"
        default: "major"
        }
    }
}

/// A chord at a tick of a bar; nil means no chord is sounding (N.C.).
nonisolated struct ChordMark: Equatable {
    var tick: Int
    var chord: Chord?
}

nonisolated enum Chords {
    // Suspended and sixth chords are not guessed (a passing note over a G triad would read as Gsus4); the file's own symbols can be any kind.
    private static let shapes: [(kind: String, tones: [Int], cost: Double)] = [
        ("", [0, 4, 7], 0), ("m", [0, 3, 7], 0), ("dim", [0, 3, 6], 0.12), ("aug", [0, 4, 8], 0.2),
        ("7", [0, 4, 7, 10], 0.35), ("maj7", [0, 4, 7, 11], 0.38), ("m7", [0, 3, 7, 10], 0.35), ("m7♭5", [0, 3, 6, 10], 0.4),
        ("dim7", [0, 3, 6, 9], 0.4),
    ]

    /// The chord that best fits these notes, as (MIDI pitch, how long it sounds in the stretch); nil when nothing sounds.
    static func detect(_ notes: [(pitch: Int, weight: Double)]) -> Chord? {
        guard !notes.isEmpty else { return nil }
        var w = [Double](repeating: 0, count: 12)
        for n in notes { w[n.pitch.mod(12)] += n.weight }
        let total = w.reduce(0, +)
        guard total > 0 else { return nil }
        let lowest = notes.min { $0.pitch < $1.pitch }!.pitch.mod(12)
        var best: (chord: Chord, score: Double)?
        for root in 0..<12 {
            for shape in shapes {
                let tones = Set(shape.tones.map { ($0 + root) % 12 })
                let inside = tones.reduce(0.0) { $0 + w[$1] }, outside = total - inside
                let missing = tones.filter { w[$0] == 0 }.count
                // Notes in the chord count for it, notes outside count against it, and a chord with notes missing loses a little.
                var score = inside - 1.4 * outside - 0.22 * total * Double(missing) / Double(tones.count) - shape.cost * total
                // A seventh chord needs its seventh to be a real part of the sound, not a passing note.
                if tones.count == 4, w[(root + shape.tones[3]) % 12] < 0.14 * total { score -= 0.6 * total }
                if lowest == root { score += 0.25 * total }
                else if tones.contains(lowest) { score += 0.05 * total }
                if w[root] > 0 { score += 0.15 * total }
                if best == nil || score > best!.score + 1e-9 { best = (Chord(root: root, kind: shape.kind, bass: nil), score) }
            }
        }
        guard var chord = best?.chord else { return nil }
        let tones = Set(shapes.first { $0.kind == chord.kind }!.tones.map { ($0 + chord.root) % 12 })
        if lowest != chord.root, tones.contains(lowest) { chord.bass = lowest }
        return chord
    }

    /// The chords of every bar: those written in the file when it has any, else worked out from the notes.
    static func chart(for score: ParsedScore) -> (bars: [[ChordMark]], fromFile: Bool) {
        let fromFile = score.measures.contains { !$0.chords.isEmpty }
        if fromFile { return (score.measures.map(\.chords), true) }
        var out: [[ChordMark]] = []
        for (m, bar) in score.measures.enumerated() {
            let beat = ScoreEdit.beat(at: m, in: score), perBar = max(1, bar.length / max(beat, 1))
            let cuts = perBar >= 4 ? [0, (perBar + 1) / 2 * beat, bar.length] : [0, bar.length]
            var marks: [ChordMark] = []
            for k in 0..<(cuts.count - 1) {
                let a = cuts[k], b = cuts[k + 1]
                let sounding = bar.notes.compactMap { n -> (pitch: Int, weight: Double)? in
                    guard let d = n.diatonic, !n.hidden else { return nil }
                    let overlap = min(n.tick + n.duration, b) - max(n.tick, a)
                    return overlap > 0 ? (ParsedScore.midi(diatonic: d, alter: n.alter), Double(overlap)) : nil
                }
                let chord = detect(sounding)
                if let last = marks.last, last.chord == chord { continue }
                marks.append(ChordMark(tick: a, chord: chord))
            }
            out.append(marks)
        }
        return (out, false)
    }
}
