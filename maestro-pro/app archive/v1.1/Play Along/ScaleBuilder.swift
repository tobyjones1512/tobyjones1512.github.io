import Foundation

// Scales, arpeggios, pentatonics and blues scales in every key, engraved on demand as ordinary scores,
// so they play, transpose, loop with a backing track and play through the instruments like any other music.
// ponytail: one octave up and back from the root in octave 4, quarter notes in 4/4; no fingerings, no
// two-octave versions. The key's transpose control moves them up or down.

nonisolated struct ScaleKind: Identifiable, Hashable {
    enum Group: String, CaseIterable { case scales = "Scales", pentatonic = "Pentatonic & Blues", arpeggios = "Arpeggios" }

    let name: String
    let group: Group
    /// Takes its key signature from the minor key on the same root (else the major key).
    let minorKey: Bool
    /// Ascending notes as (letter steps above the root letter, semitones above the root), root first.
    let up: [(Int, Int)]
    /// Descending form, if it differs from the ascending one (melodic minor).
    var down: [(Int, Int)]?
    var id: String { name }

    static func == (a: ScaleKind, b: ScaleKind) -> Bool { a.name == b.name }
    func hash(into h: inout Hasher) { h.combine(name) }

    static let all: [ScaleKind] = [
        .init(name: "Major Scale", group: .scales, minorKey: false, up: [(0, 0), (1, 2), (2, 4), (3, 5), (4, 7), (5, 9), (6, 11)]),
        .init(name: "Natural Minor Scale", group: .scales, minorKey: true, up: [(0, 0), (1, 2), (2, 3), (3, 5), (4, 7), (5, 8), (6, 10)]),
        .init(name: "Harmonic Minor Scale", group: .scales, minorKey: true, up: [(0, 0), (1, 2), (2, 3), (3, 5), (4, 7), (5, 8), (6, 11)]),
        .init(name: "Melodic Minor Scale", group: .scales, minorKey: true, up: [(0, 0), (1, 2), (2, 3), (3, 5), (4, 7), (5, 9), (6, 11)],
              down: [(0, 0), (1, 2), (2, 3), (3, 5), (4, 7), (5, 8), (6, 10)]),
        .init(name: "Major Pentatonic", group: .pentatonic, minorKey: false, up: [(0, 0), (1, 2), (2, 4), (4, 7), (5, 9)]),
        .init(name: "Minor Pentatonic", group: .pentatonic, minorKey: true, up: [(0, 0), (2, 3), (3, 5), (4, 7), (6, 10)]),
        .init(name: "Blues Scale", group: .pentatonic, minorKey: true, up: [(0, 0), (2, 3), (3, 5), (4, 6), (4, 7), (6, 10)]),
        .init(name: "Major Blues Scale", group: .pentatonic, minorKey: false, up: [(0, 0), (1, 2), (2, 3), (2, 4), (4, 7), (5, 9)]),
        .init(name: "Major Arpeggio", group: .arpeggios, minorKey: false, up: [(0, 0), (2, 4), (4, 7)]),
        .init(name: "Minor Arpeggio", group: .arpeggios, minorKey: true, up: [(0, 0), (2, 3), (4, 7)]),
        .init(name: "Dominant 7th Arpeggio", group: .arpeggios, minorKey: false, up: [(0, 0), (2, 4), (4, 7), (6, 10)]),
        .init(name: "Major 7th Arpeggio", group: .arpeggios, minorKey: false, up: [(0, 0), (2, 4), (4, 7), (6, 11)]),
        .init(name: "Minor 7th Arpeggio", group: .arpeggios, minorKey: true, up: [(0, 0), (2, 3), (4, 7), (6, 10)]),
        .init(name: "Diminished Arpeggio", group: .arpeggios, minorKey: true, up: [(0, 0), (2, 3), (4, 6)]),
        .init(name: "Diminished 7th Arpeggio", group: .arpeggios, minorKey: true, up: [(0, 0), (2, 3), (4, 6), (6, 9)]),
    ]
}

/// The twelve keys, spelled with the fewest accidentals: root letter, its alteration and the key signature.
nonisolated struct ScaleKey: Identifiable, Hashable {
    let letter: Int, alter: Int, fifths: Int
    var id: String { "\(letter)\(alter)\(fifths)" }
    var name: String { String("CDEFGAB"[("CDEFGAB".index("CDEFGAB".startIndex, offsetBy: letter))]) + (alter > 0 ? "♯" : alter < 0 ? "♭" : "") }
    var signature: String { fifths == 0 ? "no ♯ or ♭" : "\(abs(fifths))\(fifths > 0 ? "♯" : "♭")" }

    static let major = [(0, 0, 0), (1, -1, -5), (1, 0, 2), (2, -1, -3), (2, 0, 4), (3, 0, -1), (3, 1, 6), (4, 0, 1), (5, -1, -4), (5, 0, 3), (6, -1, -2), (6, 0, 5)].map(ScaleKey.init)
    static let minor = [(0, 0, -3), (0, 1, 4), (1, 0, -1), (2, -1, -6), (2, 0, 1), (3, 0, -4), (3, 1, 3), (4, 0, -2), (4, 1, 5), (5, 0, 0), (6, -1, -5), (6, 0, 2)].map(ScaleKey.init)

    init(_ l: Int, _ a: Int, _ f: Int) { letter = l; alter = a; fifths = f }
}

nonisolated enum ScaleBuilder {
    private static let natural = [0, 2, 4, 5, 7, 9, 11]

    static func score(_ kind: ScaleKind, in key: ScaleKey) -> ParsedScore {
        // Pitches: letters count up from the root's letter; the alteration is whatever reaches the wanted semitone.
        let octave = 4, rootSemis = octave * 12 + natural[key.letter] + key.alter
        func pitch(_ step: Int, _ semis: Int) -> (d: Int, alter: Int) {
            let d = octave * 7 + key.letter + step
            return (d, rootSemis + semis - (d.floorDiv(7) * 12 + natural[d.mod(7)]))
        }
        let down = kind.down ?? kind.up
        // The blue note is a flattened fifth; where that would need a double flat, write it as a raised fourth.
        let spell = { (n: (Int, Int)) -> (d: Int, alter: Int) in
            let p = pitch(n.0, n.1)
            return n == (4, 6) && p.alter < -1 ? pitch(3, 6) : p
        }
        let line = kind.up.map(spell) + [pitch(7, 12)] + down.reversed().map(spell)

        var s = ParsedScore()
        s.title = "\(key.name) \(kind.name)"
        s.staffCount = 1
        s.minor = kind.minorKey
        s.tempo = 96
        // Quarter notes; the last one fills its bar.
        let beats = (0..<line.count).map { $0 == line.count - 1 ? 4 - ((line.count - 1) % 4) : 1 }
        var inForce: [Int: Int] = [:]
        var tick = 0, bar = PMeasure(start: 0, length: 4 * ticksPerQuarter), used = 0
        bar.key = key.fifths; bar.time = (4, 4); bar.clefs[0] = Clef()
        for (p, n) in zip(line, beats) {
            var note = PNote()
            note.tick = used * ticksPerQuarter
            note.duration = n * ticksPerQuarter
            note.staff = 0; note.voice = "1"
            note.diatonic = p.d; note.alter = p.alter
            (note.type, note.dots) = [1: ("quarter", 0), 2: ("half", 0), 3: ("half", 1), 4: ("whole", 0)][n]!
            // An accidental wherever the note differs from what the key and the bar so far say.
            if p.alter != (inForce[p.d] ?? ParsedScore.keyAlter(key.fifths, p.d.mod(7))) { note.accidental = ParsedScore.accidentalNames[max(-2, min(2, p.alter)) + 2] }
            inForce[p.d] = p.alter
            bar.notes.append(note)
            used += n
            if used == 4 { s.measures.append(bar); tick += bar.length; bar = PMeasure(start: tick, length: 4 * ticksPerQuarter); used = 0; inForce = [:] }
        }
        if used > 0 { s.measures.append(bar) }
        s.measures[s.measures.count - 1].finalBar = true
        return s
    }
}
