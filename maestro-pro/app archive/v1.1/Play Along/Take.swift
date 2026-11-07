import Foundation

// A recording of someone playing a score, and the judging of it: for any moment of the recording, which note should be
// sounding (green) and which note the player actually hit (green when right, red when wrong or out of time).

/// One analysed stretch of the recording: when it was (seconds into the audio), where the score was then (beats), and the pitch heard.
nonisolated struct TakeFrame: Codable, Equatable {
    var t: Double
    var beat: Double
    var midi: Float?
}

nonisolated struct Take: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var duration = 0.0
    var tempo = 100.0, speed = 1.0
    var a4 = 440.0
    /// The file name of the sound, beside the take's data (nil: none was kept).
    var audio: String?
    var frames: [TakeFrame] = []

    /// Where the score was `t` seconds into the recording.
    func beat(at t: Double) -> Double {
        guard let first = frames.first, let last = frames.last else { return t * tempo * speed / 60 }
        let rate = tempo * speed / 60
        if t <= first.t { return first.beat - (first.t - t) * rate }
        if t >= last.t { return last.beat + (t - last.t) * rate }
        var lo = 0, hi = frames.count - 1
        while hi - lo > 1 { let m = (lo + hi) / 2; if frames[m].t <= t { lo = m } else { hi = m } }
        let a = frames[lo], b = frames[hi]
        return b.t > a.t ? a.beat + (b.beat - a.beat) * (t - a.t) / (b.t - a.t) : a.beat
    }

    /// The time in the recording at which the score was at `beat` (the other way round from `beat(at:)`).
    func time(atBeat beat: Double) -> Double {
        guard let first = frames.first, let last = frames.last else { return beat * 60 / (tempo * speed) }
        let rate = tempo * speed / 60
        if beat <= first.beat { return first.t - (first.beat - beat) / rate }
        if beat >= last.beat { return last.t + (beat - last.beat) / rate }
        var lo = 0, hi = frames.count - 1
        while hi - lo > 1 { let m = (lo + hi) / 2; if frames[m].beat <= beat { lo = m } else { hi = m } }
        let a = frames[lo], b = frames[hi]
        return b.beat > a.beat ? a.t + (b.t - a.t) * (beat - a.beat) / (b.beat - a.beat) : a.t
    }

    /// The analysed stretch that was current at `t`, if sound was being analysed then.
    func frame(at t: Double) -> TakeFrame? {
        guard !frames.isEmpty else { return nil }
        var lo = 0, hi = frames.count
        while lo < hi { let m = (lo + hi) / 2; if frames[m].t <= t { lo = m + 1 } else { hi = m } }
        guard lo > 0, t - frames[lo - 1].t < 0.15 else { return nil }
        return frames[lo - 1]
    }
}

/// What the notes should look like at a moment of a review.
nonisolated struct ReviewLit: Equatable {
    var green: Set<Int> = []
    var red: Set<Int> = []
    /// A pitch that is not in the score near here (MIDI), when the player hit one.
    var stray: Double?
    var beat = 0.0
}

nonisolated struct TakeJudge {
    /// How near a semitone the pitch has to be for it to count as that note.
    var tolerance = 0.3
    /// How many beats early or late still counts as in time.
    var slack = 0.3
    /// How far from a note (beats) the player can be and still be said to have played that note: no limit, so however far
    /// behind or ahead they are, the note they hit is found (the nearest one in the score with that pitch).
    var reach = Double.infinity
    var anyOctave = false

    let notes: [NoteEvent]
    private let byKey: [Int: [Int]]       // pitch (or pitch class) → indices into `notes`, by start
    private let longest: Double

    struct Moment: Equatable {
        var expected: [Int] = []          // note ids that should be sounding
        var played: Int?                  // the note id the player hit, when the pitch is in the score near here
        var correct = false
        var heard: Double?
    }

    /// `events`: the score's notes; only pitched, non-grace ones in `staff` (nil: all) are judged.
    init(events: [NoteEvent], staff: Int?, anyOctave: Bool = false, slack: Double = 0.3, tolerance: Double = 0.3) {
        self.anyOctave = anyOctave; self.slack = slack; self.tolerance = tolerance
        notes = events.filter { $0.pitch != nil && !$0.grace && !$0.isRest && (staff == nil || $0.staff == staff) }.sorted { $0.start < $1.start }
        var d: [Int: [Int]] = [:]
        for (i, n) in notes.enumerated() { d[anyOctave ? n.pitch!.mod(12) : n.pitch!, default: []].append(i) }
        byKey = d
        longest = notes.map(\.duration).max() ?? 0
    }

    var count: Int { notes.count }

    func expected(at beat: Double) -> [Int] {
        var lo = 0, hi = notes.count
        while lo < hi { let m = (lo + hi) / 2; if notes[m].start <= beat + 0.0001 { lo = m + 1 } else { hi = m } }
        var out: [Int] = []
        var i = lo - 1
        while i >= 0, notes[i].start > beat - longest - 0.001 {
            if notes[i].end > beat + 0.0001 { out.append(notes[i].id) }
            i -= 1
        }
        return out
    }

    private func gap(_ n: NoteEvent, _ beat: Double) -> Double { beat < n.start ? n.start - beat : beat > n.end ? beat - n.end : 0 }

    func moment(_ f: TakeFrame) -> Moment {
        var m = Moment(expected: expected(at: f.beat))
        guard let midi = f.midi.map(Double.init) else { return m }
        m.heard = midi
        let rounded = Int(midi.rounded())
        guard abs(midi - Double(rounded)) <= tolerance,
              let candidates = byKey[anyOctave ? rounded.mod(12) : rounded] else { return m }
        let best = candidates.map { notes[$0] }.min { gap($0, f.beat) < gap($1, f.beat) }
        guard let best, gap(best, f.beat) <= reach else { return m }
        m.played = best.id
        m.correct = gap(best, f.beat) <= slack
        return m
    }

    /// What to light at `t` seconds into the take.
    func lit(_ take: Take, at t: Double) -> ReviewLit {
        let beat = take.beat(at: t)
        var out = ReviewLit(green: Set(expected(at: beat)), beat: beat)
        guard let f = take.frame(at: t), f.midi != nil else { return out }
        let m = moment(f)
        if let p = m.played { if m.correct { out.green.insert(p) } else { out.red.insert(p) } }
        else { out.stray = m.heard }
        return out
    }

    /// How many notes were played right (the right pitch, in time, for at least part of the note) out of all that were due.
    func summary(_ take: Take) -> (hit: Int, total: Int) {
        var seen: [Int: Int] = [:], good: [Int: Int] = [:]
        let pitch = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.pitch!) })
        for f in take.frames {
            let m = moment(f)
            for id in m.expected {
                seen[id, default: 0] += 1
                if m.correct, let p = m.played, anyOctave ? pitch[p]!.mod(12) == pitch[id]!.mod(12) : pitch[p] == pitch[id] { good[id, default: 0] += 1 }
            }
        }
        // A note counts as played when it was right for at least a third of the time it was due, or in a frame at all when it is short.
        let hit = notes.filter { n in
            guard let s = seen[n.id], let g = good[n.id] else { return false }
            return Double(g) / Double(s) >= 0.34
        }.count
        return (hit, notes.count)
    }
}
