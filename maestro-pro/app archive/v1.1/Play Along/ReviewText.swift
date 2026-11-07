import Foundation

// What a take comes to, in words: the facts worked out from a recording, a written review made from them (by Apple
// Intelligence when it is there, by plain rules when it is not), and the places in it that can be tapped.

/// A place in the music a review can point at.
nonisolated enum ReviewRef: Hashable {
    case bar(Int)
    case bars(Int, Int)
    case note(Int)      // a note's id in the timeline

    var url: URL {
        switch self {
        case .bar(let n): URL(string: "playalong-review://bar/\(n)")!
        case .bars(let a, let b): URL(string: "playalong-review://bars/\(a)-\(b)")!
        case .note(let id): URL(string: "playalong-review://note/\(id)")!
        }
    }

    init?(url: URL) {
        guard url.scheme == "playalong-review", let host = url.host else { return nil }
        let rest = url.lastPathComponent
        switch host {
        case "bar": guard let n = Int(rest) else { return nil }; self = .bar(n)
        case "note": guard let n = Int(rest) else { return nil }; self = .note(n)
        case "bars":
            let p = rest.split(separator: "-").compactMap { Int($0) }
            guard p.count == 2 else { return nil }
            self = .bars(p[0], p[1])
        default: return nil
        }
    }
}

nonisolated struct BarSpan: Equatable {
    var number: Int
    var start: Double
    var end: Double
}

nonisolated struct ReviewFacts {
    struct NoteInfo { var name: String; var bar: Int; var start: Double; var hit: Bool }
    struct Run { var fromBar: Int; var toBar: Int; var notes: Int }

    var hit = 0, total = 0
    /// Notes the recording never got to (it stopped first), and the bar it stopped in.
    var unreached = 0
    var stoppedAtBar: Int?
    var worstBars: [Int] = []
    var bestBars: (from: Int, to: Int)?
    var behind: Run?, ahead: Run?
    /// Average pitch error when the right note was played, in cents (+ sharp).
    var cents: Double?
    var stray: [(name: String, count: Int)] = []
    /// The notes that were missed and the ones the review can refer to.
    var missed: [Int] = []
    var notes: [Int: NoteInfo] = [:]
    var bars: [BarSpan] = []
    /// How much of each bar was played right (0...1), for bars with notes in them.
    var barAccuracy: [Int: Double] = [:]

    var accuracy: Double { total > 0 ? Double(hit) / Double(total) : 0 }

    func isValid(_ ref: ReviewRef) -> Bool {
        let numbers = Set(bars.map(\.number))
        switch ref {
        case .bar(let n): return numbers.contains(n)
        case .bars(let a, let b): return numbers.contains(a) && numbers.contains(b) && a <= b
        case .note(let id): return notes[id] != nil
        }
    }

    /// What a reference reads as in the review.
    func label(_ ref: ReviewRef) -> String {
        switch ref {
        case .bar(let n): "bar \(n)"
        case .bars(let a, let b): a == b ? "bar \(a)" : "bars \(a) to \(b)"
        case .note(let id): notes[id].map { "\($0.name), bar \($0.bar)" } ?? "a note"
        }
    }
}

nonisolated extension TakeJudge {
    /// Works out how the take went: where it was good, where it fell behind or rushed, and which notes gave trouble.
    func facts(_ take: Take, bars: [BarSpan]) -> ReviewFacts {
        var f = ReviewFacts(bars: bars)
        func bar(at beat: Double) -> Int? { bars.last { $0.start <= beat + 0.0001 }?.number }
        var index: [Int: Int] = [:]
        for (i, n) in notes.enumerated() { index[n.id] = i }
        var seen: [Int: Int] = [:], good: [Int: Int] = [:]
        var centsSum = 0.0, centsN = 0
        var stray: [Int: Int] = [:]
        var frameOffsets: [(bar: Int?, d: Int)] = []   // how many notes ahead (+) or behind (-) the player was, when out of time
        var reachedBeat = -Double.infinity
        for fr in take.frames {
            let m = moment(fr)
            reachedBeat = max(reachedBeat, fr.beat)
            for id in m.expected {
                seen[id, default: 0] += 1
                if m.correct, let p = m.played, notes[index[p]!].pitch == notes[index[id]!].pitch { good[id, default: 0] += 1 }
            }
            if let midi = fr.midi.map(Double.init) {
                if m.played == nil { stray[Int(midi.rounded()), default: 0] += 1 }
                else if m.correct { centsSum += (midi - midi.rounded()) * 100; centsN += 1 }
            }
            if let p = m.played, !m.correct, let e = m.expected.compactMap({ index[$0] }).min(), let pi = index[p] {
                frameOffsets.append((bar(at: fr.beat), pi - e))
            }
        }
        // Per bar: notes due and notes hit.
        var due: [Int: Int] = [:], hits: [Int: Int] = [:]
        for n in notes {
            let b = bar(at: n.start) ?? 0
            due[b, default: 0] += 1
            let s = seen[n.id] ?? 0, g = good[n.id] ?? 0
            let hit = s > 0 && Double(g) / Double(s) >= 0.34
            if hit { hits[b, default: 0] += 1; f.hit += 1 }
            else if s == 0 { f.unreached += 1 }
            f.notes[n.id] = ReviewFacts.NoteInfo(name: Pitch.name(n.pitch!), bar: b, start: n.start, hit: hit)
        }
        f.total = notes.count
        if f.unreached > 0 { f.stoppedAtBar = bar(at: reachedBeat) }
        for (b, d) in due { f.barAccuracy[b] = Double(hits[b] ?? 0) / Double(d) }
        let missedBars = due.keys.sorted().map { ($0, due[$0]! - (hits[$0] ?? 0)) }
        // Bars with the most missed notes (not counting bars the recording never reached).
        let reachedLimit = f.stoppedAtBar ?? Int.max
        f.worstBars = missedBars.filter { $0.1 > 0 && $0.0 <= reachedLimit }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.prefix(3).map(\.0).sorted()
        // The longest run of bars with every note hit.
        var best: (from: Int, to: Int)?, runStart: Int?, prev: Int?
        for b in due.keys.sorted() {
            let clean = (hits[b] ?? 0) == due[b]!
            if clean { if runStart == nil || (prev != nil && b != prev! + 1) { runStart = b }; if let s = runStart, best == nil || b - s > best!.to - best!.from { best = (s, b) } }
            else { runStart = nil }
            prev = b
        }
        if let b = best, b.to > b.from { f.bestBars = b }
        f.cents = centsN >= 5 ? centsSum / Double(centsN) : nil
        f.stray = stray.sorted { $0.value > $1.value }.prefix(2).map { (Pitch.name($0.key), $0.value) }
        // The most missed notes, the longest first (they are the ones that show most on the page).
        let missed = notes.filter { f.notes[$0.id]?.hit == false && (seen[$0.id] ?? 0) > 0 }.sorted { $0.duration != $1.duration ? $0.duration > $1.duration : $0.start < $1.start }
        f.missed = missed.prefix(3).map(\.id)
        // Runs of falling behind or rushing: three or more frames in a row on the wrong side.
        func longestRun(_ sign: Int) -> ReviewFacts.Run? {
            var best: (score: Int, run: ReviewFacts.Run)?, cur: [(bar: Int?, d: Int)] = []
            func close() {
                if cur.count >= 3, let a = cur.first?.bar, let b = cur.last?.bar {
                    let by = cur.map { abs($0.d) }.max() ?? 0
                    let s = by * cur.count
                    if best == nil || s > best!.score { best = (s, .init(fromBar: a, toBar: b, notes: by)) }
                }
                cur = []
            }
            for o in frameOffsets { if (o.d < 0 ? -1 : 1) == sign { cur.append(o) } else { close() } }
            close()
            return best?.run
        }
        f.behind = longestRun(-1)
        f.ahead = longestRun(1)
        return f
    }
}

/// The review as shown: a headline and short paragraphs, each about one thing.
nonisolated struct WrittenReview: Codable, Equatable {
    enum Kind: String, Codable { case strength, timing, pitch, trouble, tip }
    struct Para: Codable, Equatable { var kind: Kind; var text: String }
    var headline: String
    var paragraphs: [Para]
    /// Written by Apple Intelligence rather than by the app's own rules.
    var byAI = false
}

/// The review text split into plain words and tappable places. Anything in braces that doesn't point at something real is dropped.
nonisolated enum ReviewText {
    enum Segment: Equatable { case text(String), ref(ReviewRef) }

    static func parse(_ s: String, facts: ReviewFacts) -> [Segment] {
        guard let re = try? NSRegularExpression(pattern: "\\{\\s*(bar|bars|note)\\s*:\\s*([0-9]+(?:\\s*-\\s*[0-9]+)?)\\s*\\}") else { return [.text(s)] }
        var out: [Segment] = [], last = s.startIndex
        let ns = s as NSString
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            let r = Range(m.range, in: s)!
            if r.lowerBound > last { out.append(.text(String(s[last..<r.lowerBound]))) }
            last = r.upperBound
            let kind = ns.substring(with: m.range(at: 1)), arg = ns.substring(with: m.range(at: 2)).replacingOccurrences(of: " ", with: "")
            let nums = arg.split(separator: "-").compactMap { Int($0) }
            let ref: ReviewRef? = switch kind {
            case "bar": nums.first.map { .bar($0) }
            case "note": nums.first.map { .note($0) }
            default: nums.count == 2 ? .bars(nums[0], nums[1]) : nums.first.map { .bar($0) }
            }
            if let ref, facts.isValid(ref) { out.append(.ref(ref)) }
        }
        if last < s.endIndex { out.append(.text(String(s[last...]))) }
        // Braces left over (a made-up place) are removed.
        return out.map { if case .text(let t) = $0 { .text(t.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")) } else { $0 } }
    }
}

extension ReviewText {
    /// Whether a reworded paragraph still says the same thing: the same places, the same numbers, nothing made up.
    static func accepts(original: String, rewrite: String) -> Bool {
        func tokens(_ s: String) -> [String] {
            guard let re = try? NSRegularExpression(pattern: "\\{[^}]*\\}") else { return [] }
            return re.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length)).map { (s as NSString).substring(with: $0.range).replacingOccurrences(of: " ", with: "") }.sorted()
        }
        func numbers(_ s: String) -> Set<String> {
            let plain = s.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            return Set(plain.split { !$0.isNumber }.map(String.init))
        }
        let t = tokens(rewrite)
        // No longer than the plain sentence (a chatty rewrite is thrown away).
        guard !rewrite.isEmpty, rewrite.count <= max(60, Int(Double(original.count) * 1.2)), !rewrite.contains("!"), t == tokens(original) else { return false }
        guard numbers(original).isSubset(of: numbers(rewrite)), numbers(rewrite).isSubset(of: numbers(original)) else { return false }
        return !rewrite.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression).contains("{")
    }
}

/// The review written by rules, used when Apple Intelligence isn't available (and as the facts the AI works from).
nonisolated enum ReviewComposer {
    static func template(_ f: ReviewFacts) -> WrittenReview {
        let pct = Int((f.accuracy * 100).rounded())
        let headline = "\(f.hit) of \(f.total) notes"
        var p: [WrittenReview.Para] = []
        if let b = f.bestBars {
            p.append(.init(kind: .strength, text: "Clean: {bars:\(b.from)-\(b.to)}, every note right and in time."))
        } else if f.hit > 0 {
            p.append(.init(kind: .strength, text: "\(f.hit) of \(f.total) notes right (\(pct)%)."))
        }
        if let r = f.behind {
            p.append(.init(kind: .timing, text: "Behind by up to \(r.notes) note\(r.notes == 1 ? "" : "s") around {bars:\(r.fromBar)-\(r.toBar)}. Practise it slower."))
        } else if let r = f.ahead {
            p.append(.init(kind: .timing, text: "Ahead by up to \(r.notes) note\(r.notes == 1 ? "" : "s") around {bars:\(r.fromBar)-\(r.toBar)}. Use the metronome."))
        } else if f.hit > 0 {
            p.append(.init(kind: .timing, text: "Timing: steady."))
        }
        if let c = f.cents, abs(c) >= 8 {
            p.append(.init(kind: .pitch, text: "Tuning: about \(Int(abs(c).rounded())) cents \(c > 0 ? "sharp" : "flat")."))
        } else if f.cents != nil {
            p.append(.init(kind: .pitch, text: "Tuning: steady."))
        }
        var trouble: [String] = []
        if !f.missed.isEmpty { trouble.append("Missed: " + f.missed.map { "{note:\($0)}" }.joined(separator: ", ") + ".") }
        if !f.worstBars.isEmpty { trouble.append("Work on " + f.worstBars.map { "{bar:\($0)}" }.joined(separator: ", ") + ".") }
        if let s = f.stray.first { trouble.append("Stray \(s.name), not in the music.") }
        if !trouble.isEmpty { p.append(.init(kind: .trouble, text: trouble.joined(separator: " "))) }
        if f.unreached > 0, let b = f.stoppedAtBar { p.append(.init(kind: .trouble, text: "Stopped at {bar:\(b)}; \(f.unreached) note\(f.unreached == 1 ? "" : "s") not played.")) }
        p.append(.init(kind: .tip, text: f.accuracy >= 0.9 ? "Next: a little faster, or from memory." : "Next: loop the weak bars slowly, then play it through."))
        return WrittenReview(headline: headline, paragraphs: p)
    }
}
