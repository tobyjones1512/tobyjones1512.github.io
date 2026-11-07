import Foundation

/// Apple Music gives lyrics as TTML (timed text). This turns it into the LRC lines the app already shows and follows.
nonisolated enum TTML {
    /// "[mm:ss.xx]words" for each timed line, or nil when the text holds no timed lines.
    static func toLRC(_ ttml: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"<p\b([^>]*)>(.*?)</p>"#, options: [.dotMatchesLineSeparators]),
              let begin = try? NSRegularExpression(pattern: #"begin="([^"]+)""#) else { return nil }
        let ns = ttml as NSString
        var lines: [String] = []
        for m in re.matches(in: ttml, range: NSRange(location: 0, length: ns.length)) {
            let attrs = ns.substring(with: m.range(at: 1)), inner = ns.substring(with: m.range(at: 2))
            let a = attrs as NSString
            guard let b = begin.firstMatch(in: attrs, range: NSRange(location: 0, length: a.length)),
                  let t = seconds(a.substring(with: b.range(at: 1))) else { continue }
            // Words in spans stay spaced as they were written; tags go, entities become characters.
            var text = inner.replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            for (e, c) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'")] { text = text.replacingOccurrences(of: e, with: c) }
            text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !text.isEmpty else { continue }
            let cs = Int((t * 100).rounded())
            lines.append(String(format: "[%02d:%02d.%02d]", cs / 6000, cs / 100 % 60, cs % 100) + text)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// "1:02.345", "00:01:02.345" or "62.345s" as seconds.
    static func seconds(_ s: String) -> Double? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("s") { t.removeLast(); return Double(t) }
        let parts = t.split(separator: ":").map(String.init)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total = 0.0
        for p in parts { guard let v = Double(p) else { return nil }; total = total * 60 + v }
        return total
    }
}
