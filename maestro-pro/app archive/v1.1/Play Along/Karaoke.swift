import Foundation

// Karaoke files: a standard MIDI file (.kar, or .mid) whose text events carry the words, each one time-stamped.
// Read for the words and for the music, which plays through the app's own instruments.

nonisolated struct KaraokeNote {
    var start: Double, duration: Double   // seconds
    var pitch: Int
    /// The vocal melody (a guide for the singer), as opposed to the accompaniment.
    var melody: Bool
}

nonisolated struct KaraokeFile {
    var title: String?
    var lyrics = LyricsDocument()
    var notes: [KaraokeNote] = []
    var length: Double { max(lyrics.end, notes.map { $0.start + $0.duration }.max() ?? 0) }
}

nonisolated enum Karaoke {
    static let extensions: Set<String> = ["kar", "mid", "midi"]

    static func hasLyrics(_ data: Data) -> Bool { (try? parse(data))?.lyrics.isEmpty == false }

    private struct Reader {
        let data: Data
        var at = 0
        mutating func byte() throws -> Int {
            guard at < data.count else { throw ScoreError.unsupported(String(localized: "This karaoke file is damaged.")) }
            defer { at += 1 }
            return Int(data[data.startIndex + at])
        }
        mutating func int(_ n: Int) throws -> Int { var v = 0; for _ in 0..<n { v = v << 8 | (try byte()) }; return v }
        mutating func varlen() throws -> Int {
            var v = 0
            for _ in 0..<4 { let b = try byte(); v = v << 7 | (b & 0x7F); if b & 0x80 == 0 { break } }
            return v
        }
        mutating func bytes(_ n: Int) throws -> Data {
            guard n >= 0, at + n <= data.count else { throw ScoreError.unsupported(String(localized: "This karaoke file is damaged.")) }
            defer { at += n }
            return data.subdata(in: (data.startIndex + at)..<(data.startIndex + at + n))
        }
    }

    private struct TextEvent { var tick: Int, text: String, isLyric: Bool, track: Int }

    static func parse(_ data: Data) throws -> KaraokeFile {
        var r = Reader(data: data)
        guard try r.bytes(4) == Data("MThd".utf8) else { throw ScoreError.unsupported(String(localized: "This isn’t a karaoke (MIDI) file.")) }
        _ = try r.int(4)
        _ = try r.int(2)
        let trackCount = try r.int(2)
        let division = try r.int(2)
        guard division & 0x8000 == 0, division > 0 else { throw ScoreError.unsupported(String(localized: "This karaoke file uses a time format the app can’t read.")) }

        var tempos: [(tick: Int, micros: Int)] = [(0, 500_000)]
        var texts: [TextEvent] = []
        var names: [Int: String] = [:]
        var notes: [(start: Int, end: Int, pitch: Int, track: Int)] = []

        for track in 0..<trackCount {
            guard (try? r.bytes(4)) == Data("MTrk".utf8), let length = try? r.int(4) else { break }
            let end = r.at + length
            var tick = 0, status = 0
            var active: [Int: Int] = [:]   // channel*128+pitch → start tick
            while r.at < end {
                tick += try r.varlen()
                var first = try r.byte()
                if first & 0x80 != 0 { status = first; first = -1 }
                if status == 0xFF {
                    let type = try r.byte(), len = try r.varlen()
                    let body = try r.bytes(len)
                    switch type {
                    case 0x51 where len == 3: tempos.append((tick, Int(body[body.startIndex]) << 16 | Int(body[body.startIndex + 1]) << 8 | Int(body[body.startIndex + 2])))
                    case 0x01, 0x05:
                        let text = String(data: body, encoding: .utf8) ?? String(data: body, encoding: .isoLatin1) ?? ""
                        texts.append(TextEvent(tick: tick, text: text, isLyric: type == 0x05, track: track))
                    case 0x03: names[track] = String(data: body, encoding: .utf8) ?? String(data: body, encoding: .isoLatin1) ?? ""
                    case 0x2F: r.at = end
                    default: break
                    }
                } else if status == 0xF0 || status == 0xF7 {
                    _ = try r.bytes(try r.varlen())
                } else {
                    let kind = status & 0xF0, channel = status & 0x0F
                    let d1 = first >= 0 ? first : try r.byte()
                    let d2 = (kind == 0xC0 || kind == 0xD0) ? 0 : try r.byte()
                    guard channel != 9 else { continue }   // drums
                    let key = channel * 128 + d1
                    if kind == 0x90 && d2 > 0 { active[key] = tick }
                    else if kind == 0x80 || (kind == 0x90 && d2 == 0), let s = active.removeValue(forKey: key) {
                        notes.append((s, tick, d1, track))
                    }
                }
            }
            r.at = end
        }

        tempos.sort { $0.tick < $1.tick }
        func seconds(_ tick: Int) -> Double {
            var t = 0.0, lastTick = 0, micros = 500_000
            for tempo in tempos {
                if tempo.tick > tick { break }
                t += Double(tempo.tick - lastTick) * Double(micros) / 1e6 / Double(division)
                lastTick = tempo.tick; micros = tempo.micros
            }
            return t + Double(tick - lastTick) * Double(micros) / 1e6 / Double(division)
        }

        var file = KaraokeFile()
        file.lyrics = lyrics(texts, names: names, seconds: seconds, title: &file.title)
        file.lyrics.title = file.title
        let melodyTracks = Set(names.filter { $0.value.range(of: #"melod|vocal|lead|voice|vox|sing"#, options: [.regularExpression, .caseInsensitive]) != nil }.keys)
        file.notes = notes.map { KaraokeNote(start: seconds($0.start), duration: max(0.05, seconds($0.end) - seconds($0.start)), pitch: $0.pitch, melody: melodyTracks.contains($0.track)) }
            .sorted { $0.start < $1.start }
        return file
    }

    // MARK: - The words

    private static func lyrics(_ all: [TextEvent], names: [Int: String], seconds: (Int) -> Double, title: inout String?) -> LyricsDocument {
        // Header lines ("@T" title, "@L" language) aren't sung.
        let headers = all.filter { $0.text.hasPrefix("@") }
        title = headers.first { $0.text.hasPrefix("@T") }.map { String($0.text.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        let body = all.filter { !$0.text.hasPrefix("@") }
        // The track the words are in: Lyric events if there are any, otherwise the text track called Words (or with the most text).
        let byTrack = Dictionary(grouping: body, by: \.track)
        let lyricTracks = byTrack.filter { $0.value.contains { $0.isLyric } }
        let chosen: [TextEvent]
        if let t = lyricTracks.max(by: { $0.value.count < $1.value.count }) { chosen = t.value.filter(\.isLyric) }
        else if let t = byTrack.first(where: { (names[$0.key] ?? "").range(of: #"word|lyric|karaoke|text"#, options: [.regularExpression, .caseInsensitive]) != nil && $0.value.count > 4 }) { chosen = t.value }
        else if let t = byTrack.max(by: { $0.value.count < $1.value.count }), t.value.count > 4 { chosen = t.value }
        else { return LyricsDocument() }

        struct Raw { var text: String; var time: Double; var breakBefore: Bool; var paragraph: Bool }
        var raws: [Raw] = []
        var markers = false
        for e in chosen.sorted(by: { $0.tick < $1.tick }) {
            var text = e.text
            var newLine = false, paragraph = false
            if text.hasPrefix("/") { newLine = true; text.removeFirst(); markers = true }
            else if text.hasPrefix("\\") { newLine = true; paragraph = true; text.removeFirst(); markers = true }
            if text.contains("\n") || text.contains("\r") {
                newLine = true; markers = true
                text = text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            }
            if text.trimmingCharacters(in: .whitespaces).isEmpty && !newLine { continue }
            raws.append(Raw(text: text, time: seconds(e.tick), breakBefore: newLine, paragraph: paragraph))
        }
        guard !raws.isEmpty else { return LyricsDocument() }

        // Split into lines at the markers (or, with none, at long gaps and after a good number of words).
        var lines: [[Raw]] = [[]]
        var paragraphs: [Bool] = [false]
        var words = 0
        for (i, raw) in raws.enumerated() {
            let gap = i > 0 ? raw.time - raws[i - 1].time : 0
            let split = markers ? raw.breakBefore : (gap > 2.0 || (words >= 9 && (raws[i - 1].text.hasSuffix(" ") || raw.text.hasPrefix(" "))))
            if split, !lines[lines.count - 1].isEmpty { lines.append([]); paragraphs.append(raw.paragraph); words = 0 }
            else if split { paragraphs[paragraphs.count - 1] = raw.paragraph }
            lines[lines.count - 1].append(raw)
            if raw.text.hasSuffix(" ") || raw.text.hasPrefix(" ") { words += 1 }
        }

        var doc = LyricsDocument()
        doc.timed = true
        for (li, line) in lines.enumerated() where !line.isEmpty {
            let nextStart = lines[(li + 1)...].first { !$0.isEmpty }?.first?.time
            // Syllables end where the next begins; the last ends when the next line starts, or shortly after.
            var syllables: [LyricSyllable] = []
            var wordStart = 0
            for (i, raw) in line.enumerated() {
                let shown = raw.text.trimmingCharacters(in: .whitespaces)
                if shown.isEmpty { continue }
                let nextRaw = i + 1 < line.count ? line[i + 1] : nil
                let wordEnd = raw.text.hasSuffix(" ") || (nextRaw?.text.hasPrefix(" ") ?? true)
                let end = nextRaw?.time ?? min(nextStart.map { $0 - 0.03 } ?? raw.time + 1.5, raw.time + 2.0)
                syllables.append(LyricSyllable(text: shown, start: raw.time, end: max(end, raw.time + 0.1), stressed: false, wordEnd: wordEnd))
                if wordEnd {
                    let word = syllables[wordStart...]
                    let st = Lyrics.stress(word.map(\.text), word: word.map(\.text).joined())
                    for (k, idx) in (wordStart..<syllables.count).enumerated() { syllables[idx].stressed = st[k] || syllables[idx].end - syllables[idx].start >= 1.5 }
                    wordStart = syllables.count
                }
            }
            if wordStart < syllables.count { syllables[syllables.count - 1].wordEnd = true }
            if !syllables.isEmpty { doc.lines.append(LyricLine(syllables: syllables, breakBefore: !doc.lines.isEmpty && paragraphs[li])) }
        }
        return doc
    }
}

extension Lyrics {
    /// The words of a file on disk: karaoke (MIDI) or lyrics text.
    static func document(from url: URL, duration: Double?) throws -> LyricsDocument {
        if Karaoke.extensions.contains(url.pathExtension.lowercased()) { return try Karaoke.parse(Data(contentsOf: url)).lyrics }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .isoLatin1) else {
            throw ScoreError.unsupported(String(localized: "This lyrics file couldn’t be read as text."))
        }
        return parse(text, duration: duration)
    }
}
