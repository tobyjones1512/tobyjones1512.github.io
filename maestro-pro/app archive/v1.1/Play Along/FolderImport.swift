import SwiftUI
import UniformTypeIdentifiers

/// Importing a whole folder from Files, and keeping folders linked so new music in them is picked up.
extension Library {
    struct FolderResult {
        var added = 0, skipped = 0
        var failed: [String] = []
        var summary: String {
            var parts: [String] = []
            if added > 0 { parts.append((added == 1 ? String(localized: "Added 1 piece.") : String(localized: "Added \(added) pieces."))) }
            else { parts.append(String(localized: "Nothing new to add.")) }
            if skipped > 0 { parts.append("\(skipped) already in your library.") }
            if !failed.isEmpty { parts.append(String(localized: "Couldn’t read \(failed.count): \(failed.prefix(3).joined(separator: ", "))\(failed.count > 3 ? "…" : "").")) }
            return parts.joined(separator: " ")
        }
    }

    /// Every file under a folder (a plain loop the enumerator can't be used across an await in).
    private static func files(in folder: URL, keys: [URLResourceKey]) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        for case let url as URL in walker { out.append(url) }
        return out
    }

    private static let bookmarksKey = "linkedFolders"
    private static let scoreExtensions: Set<String> = ["pdf", "musicxml", "mxl", "xml", "maestropro", "playalong"]
    private static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aif", "aiff", "caf", "aac", "flac"]

    // MARK: Linked folders

    var linkedFolders: [URL] {
        (UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? []).compactMap { data in
            var stale = false
            #if targetEnvironment(macCatalyst)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
            #else
            let options: URL.BookmarkResolutionOptions = []
            #endif
            return try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
        }
    }

    private func remember(_ url: URL) {
        #if targetEnvironment(macCatalyst)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        guard let data = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        var all = UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? []
        if !linkedFolders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) { all.append(data) }
        UserDefaults.standard.set(all, forKey: Self.bookmarksKey)
    }

    func unlink(_ url: URL) {
        let keep = (UserDefaults.standard.array(forKey: Self.bookmarksKey) as? [Data] ?? []).filter { data in
            var stale = false
            #if targetEnvironment(macCatalyst)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
            #else
            let options: URL.BookmarkResolutionOptions = []
            #endif
            return (try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale))?.standardizedFileURL != url.standardizedFileURL
        }
        UserDefaults.standard.set(keep, forKey: Self.bookmarksKey)
    }

    func rescanLinked() async -> FolderResult {
        var total = FolderResult()
        for url in linkedFolders {
            let r = await importFolder(url, link: false)
            total.added += r.added; total.skipped += r.skipped; total.failed += r.failed
        }
        return total
    }

    // MARK: Importing

    /// Everything musical in the folder and its subfolders. A recording or lyrics file named like a score goes
    /// with that score; a lyrics file on its own becomes a lyrics item, with a same-named recording as its audio.
    func importFolder(_ folder: URL, link: Bool = true) async -> FolderResult {
        Analytics.track("folder_imported")
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        if link { remember(folder) }

        // Group by directory and base name.
        struct Group { var scores: [URL] = [], audio: URL?, lyrics: URL? }
        var groups: [String: Group] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey]
        for url in Self.files(in: folder, keys: keys) {
            guard (try? url.resourceValues(forKeys: Set(keys)))?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased(), base = url.deletingLastPathComponent().path + "/" + url.deletingPathExtension().lastPathComponent.lowercased()
            if Self.scoreExtensions.contains(ext) { groups[base, default: Group()].scores.append(url) }
            else if Self.audioExtensions.contains(ext) { groups[base, default: Group()].audio = url }
            else if UTType.lyricExtensions.contains(ext), !["readme", "license", "licence", "notes", "changelog"].contains(url.deletingPathExtension().lastPathComponent.lowercased()) {
                // A plain MIDI file is only music; it counts when it carries karaoke words.
                if ext == "mid" || ext == "midi", !((try? Data(contentsOf: url)).map(Karaoke.hasLyrics) ?? false) { continue }
                groups[base, default: Group()].lyrics = url
            }
        }

        var result = FolderResult()
        let work = groups.values.flatMap { g -> [(url: URL, group: Group)] in
            g.scores.isEmpty ? (g.lyrics.map { [($0, g)] } ?? []) : g.scores.map { ($0, g) }
        }.sorted { $0.url.path < $1.url.path }
        importing = (0, work.count)
        defer { importing = nil }
        let rootPath = folder.standardizedFileURL.path

        for (n, entry) in work.enumerated() {
            importing = (n, work.count)
            await Task.yield()
            let key = folder.lastPathComponent + String(entry.url.standardizedFileURL.path.dropFirst(rootPath.count))
            if items.contains(where: { $0.source == key }) { result.skipped += 1; continue }
            do {
                var item = ["maestropro", "playalong"].contains(entry.url.pathExtension.lowercased()) ? try importShared(from: entry.url) : try importScore(from: entry.url)
                item.source = key
                if item.isLyricsOnly {
                    if let audio = entry.group.audio { item = try importTrack(from: audio, for: item) }
                } else {
                    if let audio = entry.group.audio { item = try importTrack(from: audio, for: item) }
                    if let lyrics = entry.group.lyrics, let withLyrics = try? importLyrics(from: lyrics, for: item) { item = withLyrics }
                }
                save(item)
                result.added += 1
            } catch {
                result.failed.append(entry.url.lastPathComponent)
            }
        }
        return result
    }
}
