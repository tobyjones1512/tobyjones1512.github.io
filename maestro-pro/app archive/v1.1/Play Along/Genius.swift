import Foundation

// Who sings which line, from the song's page on genius.com. Genius marks duets in its section headers
// ("[Chorus: Elton John & Kiki Dee, <i>Elton John</i>, <b>Kiki Dee</b>]": plain text both, italics one, bold the
// other) and then sets each line in that singer's style. Those lines are matched to the lyrics you have, and
// each matched line is given Singer 1, 2 or 3 (in the order they first sing) or Everyone.
// The page is found from its address (genius.com/Artist-title-lyrics); Genius's search and API are not used
// (its robots.txt keeps them off-limits). ponytail: names are split on ",", "&", "and", "with", so a band
// called "Earth, Wind & Fire" counts as three people; Assign Singers puts it right.

nonisolated enum Genius {
    /// Text in one style: 0 plain, 1 italic, 2 bold, 3 both.
    struct Run: Equatable { var text: String; var style: Int }

    /// The address Genius gives a song: "Elton John & Kiki Dee", "Don't Go Breaking My Heart" ->
    /// genius.com/Elton-john-and-kiki-dee-dont-go-breaking-my-heart-lyrics.
    static func pageURL(artist: String, title: String) -> URL? {
        let words = "\(artist) \(title)".replacingOccurrences(of: "&", with: " and ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "[’'\u{2018}.]", with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !words.isEmpty, !artist.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let slug = words.joined(separator: "-")
        return URL(string: "https://genius.com/" + slug.prefix(1).uppercased() + slug.dropFirst() + "-lyrics")
    }

    /// The page, or nil when there isn't one at that address.
    static func page(_ url: URL) async -> String? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Reading the page

    /// The lyrics on the page, line by line, each a list of styled runs. Headers like "[Verse 1: …]" are lines too.
    static func lines(html: String) -> [[Run]] {
        var out: [[Run]] = [[]]
        var depth = 0, containerDepth: Int?, skipDepth: Int?
        var italic = 0, bold = 0
        let s = html[...]
        var i = s.startIndex
        func add(_ text: String) {
            guard containerDepth != nil, skipDepth == nil, !text.isEmpty else { return }
            let style = (italic > 0 ? 1 : 0) + (bold > 0 ? 2 : 0)
            if let last = out[out.count - 1].last, last.style == style { out[out.count - 1][out[out.count - 1].count - 1].text += text }
            else { out[out.count - 1].append(Run(text: text, style: style)) }
        }
        while i < s.endIndex {
            guard let lt = s[i...].firstIndex(of: "<") else { add(decode(String(s[i...]))); break }
            add(decode(String(s[i..<lt])))
            guard let gt = s[lt...].firstIndex(of: ">") else { break }
            let tag = s[s.index(after: lt)..<gt]
            i = s.index(after: gt)
            let closing = tag.hasPrefix("/")
            let name = tag.drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }.lowercased()
            let selfClosing = tag.hasSuffix("/") || ["br", "img", "input", "meta", "link", "hr"].contains(name)
            if name == "br" { if containerDepth != nil, skipDepth == nil { out.append([]) }; continue }
            if name == "script" || name == "style", !closing {   // skip their contents whole
                if let end = s[i...].range(of: "</\(name)", options: .caseInsensitive) { i = end.upperBound }
                continue
            }
            if name == "i" || name == "em" { italic += closing ? -1 : 1; italic = max(0, italic); continue }
            if name == "b" || name == "strong" { bold += closing ? -1 : 1; bold = max(0, bold); continue }
            guard name == "div" || name == "span" || name == "a" || name == "p" || name == "h2" || name == "button" || name == "svg" else { continue }
            if selfClosing { continue }
            if closing {
                if skipDepth == depth { skipDepth = nil }
                if containerDepth == depth { containerDepth = nil; out.append([]) }
                depth -= 1
            } else {
                depth += 1
                if containerDepth == nil, tag.contains("data-lyrics-container=\"true\"") { containerDepth = depth; italic = 0; bold = 0 }
                else if containerDepth != nil, skipDepth == nil, tag.contains("data-exclude-from-selection=\"true\"") { skipDepth = depth }
            }
        }
        return out.map { line in line.map { Run(text: $0.text, style: $0.style) } }
            .filter { !$0.map(\.text).joined().trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        for (k, v) in ["&amp;": "&", "&#x27;": "'", "&#39;": "'", "&quot;": "\"", "&lt;": "<", "&gt;": ">", "&nbsp;": " "] { out = out.replacingOccurrences(of: k, with: v) }
        return out
    }

    /// Each sung line's text and who sings it (names; empty when the page doesn't say).
    static func sung(html: String) -> [(text: String, singers: [String])] {
        var styleNames: [Int: [String]] = [:]
        var out: [(String, [String])] = []
        for line in lines(html: html) {
            let text = line.map(\.text).joined().trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("["), text.hasSuffix("]") {
                styleNames = header(line)
                continue
            }
            // The style most of the line is in decides; a style the header didn't name falls back to plain.
            var weight: [Int: Int] = [:]
            for r in line { weight[r.style, default: 0] += r.text.trimmingCharacters(in: .whitespaces).count }
            let style = weight.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? 0
            out.append((text, styleNames[style] ?? styleNames[0] ?? []))
        }
        return out
    }

    /// "[Chorus: A & B, <i>A</i>, <b>B</b>]" -> plain: [A, B], italic: [A], bold: [B].
    static func header(_ line: [Run]) -> [Int: [String]] {
        var runs = line
        guard let colon = runs.firstIndex(where: { $0.text.contains(":") }) else { return [:] }
        runs[colon].text = String(runs[colon].text.split(separator: ":", maxSplits: 1).dropFirst().first ?? "")
        runs = Array(runs[colon...])
        if !runs.isEmpty { runs[runs.count - 1].text = runs[runs.count - 1].text.replacingOccurrences(of: "]", with: "") }
        var names: [Int: [String]] = [:]
        for r in runs {
            let found = r.text.components(separatedBy: CharacterSet(charactersIn: ",&"))
                .flatMap { $0.components(separatedBy: " and ") }.flatMap { $0.components(separatedBy: " with ") }
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            names[r.style, default: []] += found
        }
        return names
    }

    // MARK: Matching to your lyrics

    /// Line index in `doc` -> singer (1, 2, 3 or `LyricLine.everyone`). Empty when the page has fewer than two singers.
    static func singers(for doc: LyricsDocument, html: String) -> [Int: Int] {
        let theirs = sung(html: html)
        // Singers numbered in the order they first sing alone.
        var order: [String] = []
        for s in theirs where s.singers.count == 1 && !order.contains(s.singers[0]) { order.append(s.singers[0]) }
        let everyone = Set(theirs.flatMap(\.singers))
        guard everyone.count >= 2 else { return [:] }
        func part(_ names: [String]) -> Int? {
            if names.count == 1 { return order.firstIndex(of: names[0]).flatMap { $0 < 3 ? $0 + 1 : nil } }
            return names.count > 1 ? LyricLine.everyone : nil
        }
        let theirWords = theirs.map { words($0.text) }
        var out: [Int: Int] = [:], cursor = 0
        for (i, line) in doc.lines.enumerated() {
            let mine = words(line.text)
            guard !mine.isEmpty else { continue }
            // The best line a little way ahead, else (a repeated chorus Genius only printed once) anywhere.
            let ahead = cursor..<min(theirs.count, cursor + 8)
            var best = ahead.map { ($0, similarity(mine, theirWords[$0])) }.max { $0.1 < $1.1 }
            if (best?.1 ?? 0) < 0.5 {
                best = theirs.indices.map { ($0, similarity(mine, theirWords[$0])) }.max { $0.1 < $1.1 }
                if (best?.1 ?? 0) < 0.75 { continue }
            } else { cursor = best!.0 + 1 }
            if let j = best?.0, let p = part(theirs[j].singers) { out[i] = p }
        }
        return out
    }

    static func words(_ s: String) -> [String] {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "[’'\u{2018}]", with: "", options: .regularExpression)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// How many words two lines share, out of the longer one.
    static func similarity(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var pool = b, shared = 0
        for w in a { if let k = pool.firstIndex(of: w) { pool.remove(at: k); shared += 1 } }
        return Double(shared) / Double(max(a.count, b.count))
    }
}
