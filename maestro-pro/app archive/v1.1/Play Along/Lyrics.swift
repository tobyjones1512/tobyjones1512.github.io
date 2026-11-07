import Foundation

// Lyrics, with or without sheet music. Time is in the unit of whatever clock drives them: seconds for a lyrics
// file (the transport runs at 60 BPM, so a beat is a second) and beats for a score's own lyrics.

nonisolated struct LyricSyllable {
    var text: String
    var start: Double, end: Double
    var stressed: Bool
    /// Whether a space follows (the end of a word) rather than the next syllable continuing it.
    var wordEnd: Bool
    var staff: Int = 0
}

nonisolated struct LyricLine {
    var syllables: [LyricSyllable]
    /// A blank line came before this one (a new verse or chorus).
    var breakBefore = false
    /// Which voice in a multi-part song (0 = no part info, 1 = part 1, 2 = part 2, …)
    var part: Int = 0
    /// When another singer's lines began, if this line follows ones taken out (see `only(part:)`): the break starts there.
    var restFrom: Double?
    var start: Double { syllables.first?.start ?? 0 }
    var end: Double { syllables.last?.end ?? 0 }
    var text: String { syllables.reduce("") { $0 + $1.text + ($1.wordEnd ? " " : "") }.trimmingCharacters(in: .whitespaces) }
}

nonisolated struct LyricsDocument {
    var title: String?
    var artist: String?
    var lines: [LyricLine] = []
    /// Whether the file said when each line is sung; without that the lines are spread over the track.
    var timed = false
    /// Whether each word has its own time (karaoke files, a score's notes, `<01:23.45>` tags in an LRC file).
    /// Without it the syllables are only spaced out evenly, so filling and swelling them would be guesswork.
    var wordTimed = true
    var isEmpty: Bool { lines.isEmpty }
    var end: Double { lines.last?.end ?? 0 }
    /// Number of distinct named parts (0 or 1 = single-voice, 2+ = multi-part)
    var partCount: Int { Set(lines.map(\.part).filter { $0 > 0 && $0 != LyricLine.everyone }).count }

    /// Who sings each line of `new`, carried over from the same lyrics before an edit (with their singers in place):
    /// the old line at the same time, else one with the same words, else the one in the same place when no lines
    /// were added or taken away.
    func singers(after old: LyricsDocument) -> [Int: Int] {
        var used = Set<Int>(), out: [Int: Int] = [:]
        for (j, line) in lines.enumerated() {
            let match = old.lines.indices.first { !used.contains($0) && old.timed && timed && abs(old.lines[$0].start - line.start) < 0.01 }
                ?? old.lines.indices.first { !used.contains($0) && old.lines[$0].text == line.text }
                ?? (old.lines.count == lines.count && !used.contains(j) ? j : nil)
            guard let i = match else { continue }
            used.insert(i)
            if old.lines[i].part != 0 { out[j] = old.lines[i].part }
        }
        return out
    }

    /// Only the lines one singer sings (theirs, everyone's and any not given to anyone); 0 keeps them all. A line
    /// that follows lines taken out starts a new block, so their turns stay apart.
    func only(part: Int) -> LyricsDocument {
        guard part > 0 else { return self }
        var doc = self, skipped: Double?
        doc.lines = []
        for var line in lines {
            guard line.part == part || line.part == 0 || line.part == LyricLine.everyone else { skipped = skipped ?? line.start; continue }
            if let skipped { line.restFrom = skipped; if !doc.lines.isEmpty { line.breakBefore = true } }
            skipped = nil
            doc.lines.append(line)
        }
        return doc
    }

    /// The same lyrics with the singers chosen in Assign Singers (line index -> part) in place of the file's own.
    func withSingers(_ singers: [Int: Int]) -> LyricsDocument {
        var doc = self
        for (i, part) in singers where doc.lines.indices.contains(i) { doc.lines[i].part = part }
        return doc
    }
}

extension LyricLine {
    /// A line everyone sings together: centred, in the ordinary colour.
    static let everyone = 9

    /// Words in round brackets are backing vocals, drawn small above the line. Returns the line without them, and
    /// them on their own (brackets taken off), keeping each syllable's timing.
    nonisolated var splitBacking: (main: LyricLine, backing: LyricLine?) {
        guard syllables.contains(where: { $0.text.contains("(") }) else { return (self, nil) }
        var main = self, backing = self
        main.syllables = []; backing.syllables = []
        var inside = false
        for s in syllables {
            var piece = ""
            func flush(wordEnd: Bool) {
                let text = piece.trimmingCharacters(in: .whitespaces)
                piece = ""
                guard !text.isEmpty else { return }
                var copy = s
                copy.text = text
                copy.wordEnd = wordEnd
                if inside { backing.syllables.append(copy) } else { main.syllables.append(copy) }
            }
            for ch in s.text {
                if ch == "(" { flush(wordEnd: true); inside = true }
                else if ch == ")" { flush(wordEnd: true); inside = false }
                else { piece.append(ch) }
            }
            flush(wordEnd: s.wordEnd)
        }
        return (main, backing.syllables.isEmpty ? nil : backing)
    }
}

nonisolated enum Lyrics {
    // MARK: - Reading files

    /// An LRC file (`[01:23.45] words`, optionally with `<01:23.45>` before each word), or plain text.
    /// Plain text gets times spread across `duration` (or at a singing pace when there's no track).
    static func parse(_ text: String, duration: Double?) -> LyricsDocument {
        var doc = LyricsDocument()
        var entries: [(time: Double?, words: [(time: Double?, text: String)], breakBefore: Bool, part: Int)] = []
        var offset = 0.0
        var pendingBreak = false
        var currentPart = 0
        let tag = try! NSRegularExpression(pattern: #"^\[(\d+):(\d+(?:[.:]\d+)?)\]"#)
        let meta = try! NSRegularExpression(pattern: #"^\[([A-Za-z]+):(.*)\]\s*$"#)
        let inline = try! NSRegularExpression(pattern: #"<(\d+):(\d+(?:[.:]\d+)?)>"#)
        let partTag = try! NSRegularExpression(pattern: #"\[P:?(\d)\]"#, options: .caseInsensitive)

        func seconds(_ m: String, _ s: String) -> Double? {
            guard let mm = Double(m), let ss = Double(s.replacingOccurrences(of: ":", with: ".")) else { return nil }
            return mm * 60 + ss
        }

        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            let whole = NSRange(line.startIndex..., in: line)
            if let m = meta.firstMatch(in: line, range: whole), tag.firstMatch(in: line, range: whole) == nil {
                let key = String(line[Range(m.range(at: 1), in: line)!]).lowercased(), value = String(line[Range(m.range(at: 2), in: line)!]).trimmingCharacters(in: .whitespaces)
                switch key {
                case "ti": doc.title = value
                case "ar": doc.artist = value
                case "offset": offset = (Double(value) ?? 0) / 1000
                case "p": currentPart = Int(value) ?? currentPart
                default: break
                }
                continue
            }
            // Strip leading [P:N] part tag (inline alongside time tags).
            if let m = partTag.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let r = Range(m.range(at: 1), in: line), let n = Int(String(line[r])) {
                currentPart = n
                line = (line as NSString).replacingCharacters(in: m.range, with: "").trimmingCharacters(in: .whitespaces)
            }
            // Leading time tags (a line can be sung more than once).
            var times: [Double] = []
            var rest = line
            while let m = tag.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
                  let a = Range(m.range(at: 1), in: rest), let b = Range(m.range(at: 2), in: rest), let t = seconds(String(rest[a]), String(rest[b])) {
                times.append(t)
                rest = String(rest[Range(m.range, in: rest)!.upperBound...])
            }
            rest = rest.trimmingCharacters(in: .whitespaces)
            if rest.isEmpty && times.isEmpty {
                pendingBreak = !entries.isEmpty
                continue
            }
            // Word times inside the line.
            var words: [(time: Double?, text: String)] = []
            let nsRest = rest as NSString
            var cursor = 0
            var wordTime: Double?
            for m in inline.matches(in: rest, range: NSRange(location: 0, length: nsRest.length)) {
                let chunk = nsRest.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                if !chunk.trimmingCharacters(in: .whitespaces).isEmpty { words.append((wordTime, chunk)) }
                wordTime = seconds(nsRest.substring(with: m.range(at: 1)), nsRest.substring(with: m.range(at: 2)))
                cursor = m.range.location + m.range.length
            }
            let tail = nsRest.substring(from: cursor)
            if !tail.trimmingCharacters(in: .whitespaces).isEmpty || words.isEmpty { words.append((wordTime, tail)) }
            if rest.isEmpty { continue }
            if times.isEmpty { entries.append((nil, words, pendingBreak, currentPart)); pendingBreak = false }
            else { for t in times { entries.append((t + offset, words, pendingBreak, currentPart)); pendingBreak = false } }
        }
        guard !entries.isEmpty else { return doc }

        doc.timed = entries.contains { $0.time != nil }
        doc.wordTimed = entries.contains { $0.words.contains { $0.time != nil } }
        if doc.timed {
            entries.sort { ($0.time ?? 0) < ($1.time ?? 0) }
        } else {
            // Spread across the track by how much there is to sing; without one, about 3 syllables a second.
            let counts = entries.map { max(1, $0.words.reduce(0) { $0 + wordSyllables($1.text).count }) }
            let pace = 0.38   // seconds per syllable, plus a breath between lines
            let natural = counts.reduce(0.0) { $0 + Double($1) * pace + 0.6 } + entries.reduce(0.0) { $0 + ($1.breakBefore ? 1.2 : 0) }
            let k = duration.map { max(0.3, min(3, ($0 - 2) / natural)) } ?? 1
            var t = duration == nil ? 0.5 : 1.0
            for i in entries.indices {
                if entries[i].breakBefore { t += 1.2 * k }
                entries[i].time = t
                t += (Double(counts[i]) * pace + 0.6) * k
            }
        }

        for (i, e) in entries.enumerated() {
            let start = e.time ?? 0
            let nextStart = i + 1 < entries.count ? entries[i + 1].time ?? start + 4 : (duration ?? start + 6)
            var line = makeLine(words: e.words, start: start, nextStart: nextStart, breakBefore: e.breakBefore)
            line.part = e.part
            if !line.syllables.isEmpty { doc.lines.append(line) }
        }
        return doc
    }

    /// Syllables of a line's words, spread across the time the line is sung.
    private static func makeLine(words: [(time: Double?, text: String)], start: Double, nextStart: Double, breakBefore: Bool) -> LyricLine {
        struct Piece { var text: String; var stressed: Bool; var wordEnd: Bool; var weight: Double; var time: Double? }
        var pieces: [Piece] = []
        for w in words {
            let pieceTexts = w.text.split(whereSeparator: \.isWhitespace).map(String.init)
            for (wi, word) in pieceTexts.enumerated() {
                let sy = wordSyllables(word), st = stress(sy, word: word)
                for (i, s) in sy.enumerated() {
                    let last = i == sy.count - 1
                    pieces.append(Piece(text: s, stressed: st[i], wordEnd: last, weight: (st[i] ? 1.35 : 1) + (last && wi == pieceTexts.count - 1 ? 0.35 : 0), time: i == 0 && wi == 0 ? w.time : nil))
                }
            }
        }
        guard !pieces.isEmpty else { return LyricLine(syllables: [], breakBefore: breakBefore) }
        // The line lasts until the next begins, but a long gap is silence, not a long note.
        let natural = Double(pieces.count) * 0.55 + 0.4
        let end = max(start + 0.5, min(nextStart - 0.05, start + max(natural, 1.5) * 1.6))
        var syllables: [LyricSyllable] = []
        // Explicit word times anchor the syllables after them; the rest share what's left in proportion.
        var i = 0
        var cursor = start
        while i < pieces.count {
            var j = i + 1
            while j < pieces.count, pieces[j].time == nil { j += 1 }
            let segStart = pieces[i].time ?? cursor
            let segEnd = j < pieces.count ? pieces[j].time! : end
            let total = pieces[i..<j].reduce(0.0) { $0 + $1.weight }
            var t = segStart
            for p in pieces[i..<j] {
                let d = max(0.05, (segEnd - segStart) * p.weight / total)
                syllables.append(LyricSyllable(text: p.text, start: t, end: t + d, stressed: p.stressed, wordEnd: p.wordEnd))
                t += d
            }
            cursor = segEnd
            i = j
        }
        return LyricLine(syllables: syllables, breakBefore: breakBefore)
    }

    // MARK: - A score's own lyrics

    /// Lines from the sung syllables of a timeline, broken where there's a rest of a beat and a half or more,
    /// or after a long phrase.
    static func fromScore(_ notes: [NoteEvent]) -> LyricsDocument {
        let sung = notes.filter { $0.lyric != nil }.sorted { $0.start < $1.start }
        var doc = LyricsDocument()
        doc.timed = true
        guard !sung.isEmpty else { return doc }
        var current: [LyricSyllable] = []
        var wordCount = 0
        func flush() {
            if !current.isEmpty { doc.lines.append(LyricLine(syllables: current)); current = [] }
            wordCount = 0
        }
        // A word's syllables arrive one note at a time; its stress comes from the whole word.
        var word: [NoteEvent] = []
        func finishWord() {
            guard !word.isEmpty else { return }
            let text = word.map { $0.lyric ?? "" }
            let st = stress(text, word: text.joined())
            let wordStaff = word[0].staff
            for (i, n) in word.enumerated() {
                // Stressed by the word's own stress, or by sitting on a long note.
                current.append(LyricSyllable(text: text[i], start: n.start, end: n.end, stressed: st[i] || n.duration >= 2, wordEnd: i == word.count - 1, staff: wordStaff))
            }
            word = []
            wordCount += 1
        }
        for (i, n) in sung.enumerated() {
            word.append(n)
            let ends = n.syllabic == "end" || n.syllabic == "single" || n.syllabic == nil
            if ends {
                finishWord()
                let gap = i + 1 < sung.count ? sung[i + 1].start - n.end : 4
                if gap >= 1.5 || wordCount >= 9 { flush() }
            }
        }
        finishWord()
        flush()
        // If multiple staves have lyrics, assign parts by staff.
        if Set(sung.map(\.staff)).count > 1 {
            for i in doc.lines.indices {
                let staves = Set(doc.lines[i].syllables.map(\.staff))
                if staves.count == 1 { doc.lines[i].part = staves.first! + 1 }
            }
        }
        return doc
    }

    // MARK: - Syllables

    private static let digraphs = ["th", "sh", "ch", "ph", "wh", "ck", "ng", "gh", "qu"]

    /// Splits a word into syllables without losing a character (punctuation stays with its neighbours).
    static func wordSyllables(_ word: String) -> [String] {
        let chars = Array(word)
        let lower = chars.map { Character($0.lowercased()) }
        func isVowel(_ i: Int) -> Bool {
            let c = lower[i]
            if "aeiou".contains(c) { return true }
            return c == "y" && i > 0 && !"aeiou".contains(lower[i - 1]) && i != 0
        }
        // Vowel groups, then drop a silent final e.
        var groups: [Range<Int>] = []
        var i = 0
        while i < chars.count {
            if isVowel(i) {
                var j = i + 1
                while j < chars.count, isVowel(j) { j += 1 }
                groups.append(i..<j); i = j
            } else { i += 1 }
        }
        let letters = lower.indices.filter { lower[$0].isLetter }
        if groups.count > 1, let last = groups.last, let lastLetter = letters.last, last == lastLetter..<lastLetter + 1, lower[lastLetter] == "e" {
            let before = lastLetter > 0 ? lower[lastLetter - 1] : " "
            // "table", "little" keep their final syllable; "make", "love" don't.
            if !(before == "l" && lastLetter >= 2 && !"aeiou".contains(lower[lastLetter - 2])) { groups.removeLast() }
        }
        if groups.count <= 1 { return [word] }
        // Cut between groups: one consonant goes with the following vowel, more are shared (digraphs stay whole).
        var cuts: [Int] = []
        for g in 1..<groups.count {
            let a = groups[g - 1].upperBound, b = groups[g].lowerBound
            let between = b - a
            if between <= 1 { cuts.append(a) }
            else {
                let pair = String(lower[(b - 2)..<b])
                cuts.append(digraphs.contains(pair) && between == 2 ? a : (between >= 3 && digraphs.contains(pair) ? b - 2 : a + 1))
            }
        }
        var result: [String] = []
        var from = 0
        for c in cuts { result.append(String(chars[from..<c])); from = c }
        result.append(String(chars[from...]))
        return result.filter { !$0.isEmpty }
    }

    private static let unstressed: Set<String> = [
        "a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "at", "for", "by", "as", "is", "are", "was", "were", "be", "am",
        "it", "its", "i", "you", "he", "she", "we", "they", "me", "him", "her", "us", "them", "my", "your", "his", "our", "their",
        "that", "this", "with", "from", "so", "if", "than", "then", "do", "does", "did", "has", "have", "had", "will", "would", "can", "could",
        "'cause", "cause", "'til", "til", "oh", "ooh", "ah", "uh", "la", "na", "da", "doo",
        "i'm", "i've", "i'll", "i'd", "you're", "you've", "you'll", "you'd", "he's", "she's", "it's", "we're", "we've", "we'll", "we'd",
        "they're", "they've", "they'll", "that's", "there's", "what's", "let's", "who's",
    ]
    private static let weakPrefixes = ["to", "for", "be", "de", "re", "a", "en", "ex", "con", "com", "pre", "pro", "per", "dis", "mis", "sur", "ap", "ob", "sub", "trans", "ac", "ad", "al", "ar", "as", "at"]

    /// Which syllables of a word carry the beat. Rules of thumb for English, not a dictionary: small words
    /// don't, one-syllable words do, longer words stress the first syllable unless it's a weak prefix.
    static func stress(_ syllables: [String], word: String) -> [Bool] {
        let n = syllables.count
        let bare = word.lowercased().replacingOccurrences(of: "’", with: "'").filter { $0.isLetter || $0 == "'" }
        if n == 0 { return [] }
        if unstressed.contains(bare) { return [Bool](repeating: false, count: n) }
        var result = [Bool](repeating: false, count: n)
        if n == 1 { result[0] = true; return result }
        var at = 0
        let first = syllables[0].lowercased().filter(\.isLetter)
        if weakPrefixes.contains(first) { at = 1 }
        for (suffix, back) in [("tion", 2), ("sion", 2), ("tions", 2), ("ic", 2), ("ical", 3), ("ity", 2), ("ify", 3), ("ian", 2), ("ious", 2), ("ial", 2), ("ee", 1), ("eer", 1), ("ese", 1)] where bare.hasSuffix(suffix) && n >= back {
            at = max(0, n - back); break
        }
        result[at] = true
        return result
    }

    static func split(_ text: String) -> [String] { text.split(whereSeparator: \.isWhitespace).map(String.init) }
}
