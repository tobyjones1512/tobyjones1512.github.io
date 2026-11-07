import Foundation

/// A piece's name without the key it happens to be written in ("Nocturne in E♭ Major" → "Nocturne"), since the
/// app transposes and the key belongs to the player, not the title.
nonisolated enum TitleClean {
    // A note name with an optional accidental, then (optionally) major/minor.
    private static let note = #"[A-G](?:\s?(?:[#♯♭]|sharp|flat|b(?![a-z])))?"#
    private static let mode = #"(?:\s?(?:major|minor|maj|min))"#
    // "in A Minor", "in C", "(in E flat)", "- A Minor", or a bare "Bb" / "F# minor" at the end.
    private static let patterns: [String] = [
        #"[\s,\-–\#u{2014}:(\[]*\bin\s+"# + note + mode + #"?\s*[)\]]?\s*$"#,
        #"[\s,\-–\#u{2014}:(\[]+"# + note + mode + #"\s*[)\]]?\s*$"#,
        #"[\s,\-–\#u{2014}:(\[]+[A-G](?:[#♯♭]|b(?![a-z]))"# + mode + #"?\s*[)\]]?\s*$"#,
    ]
    // "in A Minor" in the middle ("Nocturne in C Minor, Op. 9" or "Concerto in D Major for Violin").
    private static let middle = #"\s+in\s+"# + note + mode + #"(?=[\s,]|$)"#

    static func clean(_ title: String) -> String {
        var t = title
        for _ in 0..<3 { let next = once(t); if next == t { break }; t = next }
        return t.isEmpty ? title : t
    }

    private static func once(_ title: String) -> String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for p in patterns {
            let r = try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
            // Only the note letter itself is case-insensitive in spirit: require a capital for a bare key.
            if let m = r.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), let range = Range(m.range, in: t) {
                let hit = String(t[range])
                let hasIn = hit.range(of: #"\bin\b"#, options: [.regularExpression, .caseInsensitive]) != nil
                let letter = hit.first { "ABCDEFGabcdefg".contains($0) && !(hasIn && false) }
                let capital = hit.contains { "ABCDEFG".contains($0) }
                if hasIn || capital, letter != nil, t.distance(from: t.startIndex, to: range.lowerBound) > 0 { t.removeSubrange(range) }
            }
        }
        if let r = try? NSRegularExpression(pattern: middle), let m = r.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), let range = Range(m.range, in: t) {
            // Case-sensitive on the note: "in a" is the word, "in A" the key.
            let hit = String(t[range])
            if hit.contains(where: { "ABCDEFG".contains($0) }) { t.removeSubrange(range) }
        }
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,-–\u{2014}:;([") .union(.whitespacesAndNewlines))
        return t
    }

    private static let noise = #"[\(\[][^\)\]]*\b(?:official|lyrics?|video|audio|karaoke|hd|hq|4k|remaster(?:ed)?|backing track|kbps|explicit|visuali[sz]er)\b[^\)\]]*[\)\]]"#

    /// A file name made fit to read: "01_test-name-one (Official Video)" → "Test Name One". Separators become spaces,
    /// track numbers and bracketed clutter go, and a name that is all one case gets capitals.
    static func tidy(_ name: String) -> String {
        var t = name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: #"(?<=\S)-(?=\S)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: noise, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\d{1,3}\s*[.)\-]?\s+(?=\S)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–")))
        if t == t.lowercased() || t == t.uppercased() { t = t.capitalized }
        return t.isEmpty ? name : t
    }
}
