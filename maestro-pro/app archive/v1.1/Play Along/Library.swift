import AVFoundation
import CoreText
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library item (persisted as info.json next to the imported files)

nonisolated struct ScoreItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var file: String
    var track: String?
    var tempo: Double = 100
    var scoreTempo: Double?         // the tempo the score itself gives (its printed mark); `tempo` follows it unless the person set their own
    var customTempo: Bool?          // true: `tempo` is the person's own, not the score's
    var offset: Double = 0          // seconds into the backing track where bar 1 begins
    var beatsPerBar: Double = 4     // PDFs only; MusicXML carries its own metre
    var meterDetected: Bool?        // PDFs: set once the metre has been read from the page
    var transpose: Int?             // semitones; nil = as written
    /// The title printed on the sheet, when it isn't the one in the file. The library name (`title`) is separate.
    var sheetTitle: String?
    var shiftTrack: Bool?           // MusicXML: whether the backing track follows the transposition (default yes)
    var leadIn: Int?                // empty bars before bar 1, for an intro
    var generated: Bool?            // a scale or arpeggio made by the app: kept out of the main list
    var writtenFor: String?         // InstrumentKey the score is written for; nil = concert pitch
    var lyrics: String?             // lyrics file saved beside the score (.lrc or .txt)
    var source: String?             // where it came from in a linked folder, so a rescan doesn't add it twice
    var created: Bool?              // a blank score made in the app
    var ignoreTempoMarks: Bool?     // play at one tempo, whatever tempo changes the score prints
    var staffInstruments: [String]? // an instrument for each staff ("" = the main one)
    var lengthBeats: Double?        // quarter notes in the score as played (repeats included); -1 when it can't be worked out
    var trackSeconds: Double?       // length of the backing track; -1 when it can't be read
    var trackGainDB: Double?        // level of the backing track, in decibels (nil = 0)
    var trackEQ: TrackEQ?           // equaliser for the backing tracks (nil = straight through)
    var trackEnabled: Bool?         // nil or true: the backing track is heard
    var trackName: String?          // what the backing track is called in the list (the file's name)
    var appleMusic: AppleMusicRef?  // a song from Apple Music that plays along (and its lyrics, once fetched)
    var reduceVocals: Bool?         // the backing track plays with the singer cut down
    var extraTracks: [ExtraTrack]?  // more recordings that play along with the first, each of which can be switched off
    var instrumentGainDB: Double?   // level of the built-in instrument on top of the default volume, in decibels
    var added = Date()

    var isPDF: Bool { file.lowercased().hasSuffix(".pdf") }
    /// Words only: a lyrics file with no sheet music.
    var isLyricsOnly: Bool { UTType.lyricExtensions.contains((file as NSString).pathExtension.lowercased()) }
    var isCDG: Bool { file.lowercased().hasSuffix(".cdg") }
    var kindLabel: String { isCDG ? "Karaoke" : isLyricsOnly ? "Lyrics" : isPDF ? "PDF" : "MusicXML" }
    var trackSemitones: Int { shiftTrack != false ? transpose ?? 0 : 0 }
    var writtenKey: InstrumentKey { InstrumentKey(rawValue: writtenFor ?? "") ?? .concert }
}

/// A song chosen from Apple Music.
nonisolated struct AppleMusicRef: Codable, Hashable {
    var id: String
    var title: String
    var artist: String
    /// Seconds into the song where bar 1 begins.
    var offset = 0.0
    var enabled = true
    var duration: Double?
}

/// A second (third…) backing track for a score: it plays together with the others, and can be switched off by itself.
nonisolated struct ExtraTrack: Codable, Identifiable, Hashable {
    var id = UUID()
    var file: String
    var name: String
    var enabled = true
    var gainDB = 0.0
    /// Seconds into this recording where bar 1 begins (like the first track's).
    var offset = 0.0
    var reduceVocals = false
}

nonisolated struct Playlist: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var scores: [UUID] = []
}

extension UTType {
    static let musicXML = UTType(filenameExtension: "musicxml") ?? .xml
    static let mxl = UTType(filenameExtension: "mxl") ?? .data
    static let lyricExtensions = ["lrc", "txt", "kar", "mid", "midi", "cdg"]
    static let kar = UTType(filenameExtension: "kar") ?? .midi
    static let cdg = UTType(filenameExtension: "cdg") ?? .data
    /// .lrc has no system type, so the picker knows it only as the file's own dynamic type: match that exactly.
    static let lrc = UTType(filenameExtension: "lrc") ?? .plainText
    /// Band-in-a-Box songs: recognised so the picker offers them, then explained (the format is closed).
    static let bandInABox: [UTType] = ["sgu", "sg0", "mgu", "mg0", "sgc", "sgd", "sgb", "sge"].map { UTType(filenameExtension: $0) ?? .data }
    static let scoreTypes: [UTType] = [.pdf, musicXML, mxl, .xml, .playAlongScore, lrc, .plainText, kar, .midi, cdg] + bandInABox
}

@Observable final class Library {
    private(set) var items: [ScoreItem] = []
    private(set) var playlists: [Playlist] = []
    var showImporter = false { didSet { if showImporter { Analytics.track("import_picker_opened") } } }
    /// Bars copied in the score editor, ready to paste into any score (a medley).
    var barClip: BarClip?
    var showHelp = false { didSet { if showHelp { Analytics.track("help_opened") } } }
    var showScanner = false { didSet { if showScanner { Analytics.track("scanner_opened") } } }
    var showScales = false { didSet { if showScales { Analytics.track("scales_opened") } } }
    var showFreeScores = false { didSet { if showFreeScores { Analytics.track("search_scores_opened") } } }
    var showBlank = false { didSet { if showBlank { Analytics.track("new_score_opened") } } }
    /// Set to open the score editor on a score as soon as it appears.
    var editRequest: UUID?
    var showSettings = false { didSet { if showSettings { Analytics.track("settings_opened") } } }
    var showAppleMusic = false { didSet { if showAppleMusic { Analytics.track("apple_music_opened") } } }
    var showTuner = false { didSet { if showTuner { Analytics.track("tuner_opened") } } }
    /// True while something on screen wants the keyboard for itself (the tap tempo key), so the Playback shortcuts stand down.
    var typing = false
    var showFolderPicker = false
    var showLyricsPicker = false
    var showGitHub = false
    /// Goes up whenever singers are saved, so an open lyrics screen shows them.
    private(set) var singersVersion = 0
    /// A score to open next (set when an edit makes a new one).
    var openRequest: UUID?
    /// Progress of a folder import, while one is running.
    var importing: (done: Int, total: Int)?
    private(set) var root: URL
    private(set) var isCloud = false
    @ObservationIgnored private var query: NSMetadataQuery?
    private var playlistsURL: URL { root.deletingLastPathComponent().appending(path: "Playlists.json") }
    private static let local = URL.applicationSupportDirectory.appending(path: "Library", directoryHint: .isDirectory)

    init() {
        root = Self.local
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        reload()
    }

    /// Rescans the library folder (after a sync brings in changes).
    func reload() { apply(Self.load(root)) }

    /// The same, reading the files off the main thread: in iCloud a file that hasn't downloaded yet blocks the read.
    func reloadInBackground() async {
        let root = root
        apply(await Task.detached { Self.load(root) }.value)
    }

    nonisolated private static func load(_ root: URL) -> (items: [ScoreItem], playlists: [Playlist]) {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let items = dirs.compactMap { try? JSONDecoder().decode(ScoreItem.self, from: Data(contentsOf: $0.appending(path: "info.json"))) }
            .sorted { $0.added > $1.added }
        let playlists = (try? JSONDecoder().decode([Playlist].self, from: Data(contentsOf: root.deletingLastPathComponent().appending(path: "Playlists.json")))) ?? []
        return (items, playlists)
    }

    private func apply(_ loaded: (items: [ScoreItem], playlists: [Playlist])) {
        items = loaded.items
        playlists = loaded.playlists
        if isCloud { requestDownloads() }
        // Titles already in the library lose their keys once; later renames are left alone.
        if !UserDefaults.standard.bool(forKey: "titlesCleaned") {
            UserDefaults.standard.set(true, forKey: "titlesCleaned")
            for item in items where TitleClean.clean(item.title) != item.title { var c = item; c.title = TitleClean.clean(item.title); save(c) }
        }
    }

    /// A file's name as its title; tidied unless the user turned "Tidy Titles on Import" off.
    static func importTitle(_ name: String) -> String {
        let clean = TitleClean.clean(name)
        return UserDefaults.standard.object(forKey: "autoTidyTitles") as? Bool ?? true ? TitleClean.tidy(clean) : clean
    }

    /// Runs every title in the library through the import tidy-up. Returns how many changed.
    func tidyTitles() -> Int {
        var n = 0
        for item in items {
            let t = TitleClean.tidy(TitleClean.clean(item.title))
            if t != item.title { var c = item; c.title = t; save(c); n += 1 }
        }
        return n
    }

    /// Moves the library into the iCloud Drive container, so it syncs across the user's devices. Does nothing
    /// when iCloud isn't available (signed out, or the app isn't set up for it); the library stays on this device.
    func enableCloud() async {
        guard !isCloud else { return }
        let container = await Task.detached { FileManager.default.url(forUbiquityContainerIdentifier: nil) }.value
        guard let container else { return }
        let fm = FileManager.default, cloud = container.appending(path: "Documents/Library", directoryHint: .isDirectory)
        try? fm.createDirectory(at: cloud, withIntermediateDirectories: true)
        // Bring what's already on this device along, without overwriting anything another device synced.
        await Task.detached {
            for dir in (try? fm.contentsOfDirectory(at: Self.local, includingPropertiesForKeys: nil)) ?? [] {
                let dest = cloud.appending(path: dir.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) { try? fm.copyItem(at: dir, to: dest) }
            }
            let cloudPlaylists = cloud.deletingLastPathComponent().appending(path: "Playlists.json")
            if !fm.fileExists(atPath: cloudPlaylists.path) { try? fm.copyItem(at: Self.local.deletingLastPathComponent().appending(path: "Playlists.json"), to: cloudPlaylists) }
        }.value
        root = cloud
        isCloud = true
        await reloadInBackground()
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(value: true)
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            NotificationCenter.default.addObserver(forName: name, object: q, queue: .main) { [weak self] _ in Task { await self?.reloadInBackground() } }
        }
        q.start()
        query = q
    }

    /// Files another device added show up as ".name.icloud" placeholders until they're fetched.
    private func requestDownloads() {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in files where url.pathExtension == "icloud" && url.lastPathComponent.hasPrefix(".") {
            let real = url.deletingLastPathComponent().appending(path: String(url.lastPathComponent.dropFirst().dropLast(7)))
            try? FileManager.default.startDownloadingUbiquitousItem(at: real)
        }
    }

    func folder(_ item: ScoreItem) -> URL { root.appending(path: item.id.uuidString, directoryHint: .isDirectory) }
    func scoreURL(_ item: ScoreItem) -> URL { folder(item).appending(path: item.file) }
    /// PDFs: the page read as MusicXML, rewritten each time the score opens.
    func convertedURL(_ item: ScoreItem) -> URL { folder(item).appending(path: "converted.musicxml") }
    func trackURL(_ item: ScoreItem) -> URL? { item.track.map { folder(item).appending(path: $0) } }
    /// The lyrics for an item: its own file when it is only words, otherwise the file attached to the score.
    func lyricsURL(_ item: ScoreItem) -> URL? { item.isLyricsOnly ? scoreURL(item) : item.lyrics.map { folder(item).appending(path: $0) } }

    /// Who sings each line (line index -> part), as chosen in Assign Singers.
    private func singersURL(_ item: ScoreItem) -> URL { folder(item).appending(path: "singers.json") }
    func singers(_ item: ScoreItem) -> [Int: Int] { (try? JSONDecoder().decode([Int: Int].self, from: Data(contentsOf: singersURL(item)))) ?? [:] }
    func setSingers(_ singers: [Int: Int], for item: ScoreItem) {
        try? JSONEncoder().encode(singers).write(to: singersURL(item), options: .atomic)
        singersVersion += 1
    }

    /// Matches the song to its page on genius.com and, when more than one person sings it, gives each line its singer.
    /// The artist and title come from the lyrics file's tags, the audio track's tags, or a name like "Artist - Song",
    /// else from `artist` (asked of the user). Lyrics that already have singers are left alone unless `replace`.
    /// Returns how many lines were given a singer (0: no page found, or only one singer), or nil when the song
    /// couldn't be matched.
    @discardableResult
    func matchSingers(_ item: ScoreItem, replace: Bool = false, artist given: String? = nil, title givenTitle: String? = nil) async -> Int? {
        Analytics.track("singers_matched")
        guard let url = lyricsURL(item), let doc = try? Lyrics.document(from: url, duration: nil),
              replace || (singers(item).isEmpty && doc.partCount < 2) else { return 0 }
        var tries: [(String, String)] = []
        if let given, !given.isEmpty { tries.append((given, givenTitle ?? doc.title ?? item.title)) }
        if let artist = doc.artist { tries.append((artist, doc.title ?? item.title)) }
        if let track = trackURL(item) {
            let md = (try? await AVURLAsset(url: track).load(.commonMetadata)) ?? []
            func tag(_ id: AVMetadataIdentifier) async -> String? {
                guard let m = AVMetadataItem.metadataItems(from: md, filteredByIdentifier: id).first else { return nil }
                return try? await m.load(.stringValue)
            }
            if let artist = await tag(.commonIdentifierArtist), let title = await tag(.commonIdentifierTitle) { tries.append((artist, title)) }
        }
        let halves = item.title.components(separatedBy: " - ")
        if halves.count == 2 { tries += [(halves[0], halves[1]), (halves[1], halves[0])] }
        if tries.isEmpty { return nil }
        for (artist, title) in tries {
            guard let page = Genius.pageURL(artist: artist, title: title), let html = await Genius.page(page) else { continue }
            let found = Genius.singers(for: doc, html: html)
            if !found.isEmpty { setSingers(found, for: item) }
            return found.count
        }
        return nil   // nothing matched: the caller can offer suggestions
    }

    /// Lyrics files that are plain text, and so can be edited in the app.
    func canEditLyrics(_ item: ScoreItem) -> Bool { lyricsURL(item).map { ["lrc", "txt"].contains($0.pathExtension.lowercased()) } ?? false }

    /// Saves edited lyrics text, keeping each line's singer where the line can still be found.
    func saveLyricsText(_ text: String, for item: ScoreItem) throws {
        Analytics.track("lyrics_text_saved")
        guard let url = lyricsURL(item) else { return }
        let before = (try? Lyrics.document(from: url, duration: nil))?.withSingers(singers(item))
        let after = Lyrics.parse(text, duration: nil)
        guard !after.isEmpty else { throw ScoreError.unsupported(String(localized: "There are no lyrics left. Type at least one line.")) }
        try text.write(to: url, atomically: true, encoding: .utf8)
        if let before { setSingers(after.singers(after: before), for: item) }
    }

    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? String(data: data, encoding: .isoLatin1) else {
            throw ScoreError.unsupported(String(localized: "This lyrics file couldn’t be read as text."))
        }
        return text
    }

    func importLyrics(from url: URL, for item: ScoreItem) throws -> ScoreItem {
        Analytics.track("lyrics_added", ["kind": url.pathExtension.lowercased()])
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var item = item
        if let old = item.lyrics { try? FileManager.default.removeItem(at: folder(item).appending(path: old)) }
        try? FileManager.default.removeItem(at: singersURL(item))   // the lines are new
        item.lyrics = "lyrics." + url.pathExtension.lowercased()
        try copyIn(url, to: folder(item).appending(path: item.lyrics!))
        guard let doc = try? Lyrics.document(from: folder(item).appending(path: item.lyrics!), duration: nil), !doc.isEmpty else {
            try? FileManager.default.removeItem(at: folder(item).appending(path: item.lyrics!))
            throw ScoreError.unsupported(String(localized: "There are no lyrics in that file."))
        }
        save(item)
        return item
    }

    /// A lyrics file and the recording to sing it to, chosen together, become one lyrics item with its backing.
    @discardableResult
    func importLyricsWithBacking(_ urls: [URL]) throws -> ScoreItem {
        Analytics.track("lyrics_with_backing_added")
        let audioTypes: Set<String> = ["mp3", "m4a", "wav", "aif", "aiff", "caf", "aac", "flac"]
        guard let lyrics = urls.first(where: { UTType.lyricExtensions.contains($0.pathExtension.lowercased()) }) else {
            throw ScoreError.unsupported("Choose a lyrics or karaoke file (.lrc, .txt, .kar or .cdg) along with its recording.")
        }
        var item = try importScore(from: lyrics)
        if let audio = urls.first(where: { audioTypes.contains($0.pathExtension.lowercased()) }) {
            item = try importTrack(from: audio, for: item)
        }
        return item
    }

    /// Lyrics found online and the recording they go with become one lyrics item, named after the recording.
    @discardableResult
    func importLyrics(_ lrc: URL, backing: URL, title: String) throws -> ScoreItem {
        let named = URL.temporaryDirectory.appending(path: title.replacingOccurrences(of: "/", with: "-") + ".lrc")
        try? FileManager.default.removeItem(at: named)
        try FileManager.default.copyItem(at: lrc, to: named)
        defer { try? FileManager.default.removeItem(at: named) }
        return try importTrack(from: backing, for: importScore(from: named))
    }

    // MARK: Edited scores

    private func originalURL(_ item: ScoreItem) -> URL? {
        (try? FileManager.default.contentsOfDirectory(at: folder(item), includingPropertiesForKeys: nil))?.first { $0.lastPathComponent.hasPrefix("original.") }
    }
    func hasOriginal(_ item: ScoreItem) -> Bool { originalURL(item) != nil }

    /// Writes an edited score. A MusicXML score is changed in place (its first version is kept, to go back to);
    /// a PDF's notes are saved as a new MusicXML score beside it.
    func saveEdited(_ score: ParsedScore, for item: ScoreItem) throws -> ScoreItem {
        Analytics.track("score_edited_saved")
        let data = MusicXML.write(score)
        let fm = FileManager.default
        if item.isPDF {
            var copy = ScoreItem(title: item.title + " (Edited)", file: "score.musicxml")
            copy.tempo = item.tempo; copy.beatsPerBar = item.beatsPerBar; copy.writtenFor = item.writtenFor; copy.offset = item.offset
            try fm.createDirectory(at: folder(copy), withIntermediateDirectories: true)
            try data.write(to: scoreURL(copy))
            if let t = trackURL(item), let name = item.track {
                try? fm.copyItem(at: t, to: folder(copy).appending(path: name))
                copy.track = name
            }
            save(copy)
            return copy
        }
        let ext = (item.file as NSString).pathExtension
        let backup = folder(item).appending(path: "original." + ext)
        if originalURL(item) == nil { try? fm.copyItem(at: scoreURL(item), to: backup) }
        var updated = item
        if ext.lowercased() != "musicxml" { try? fm.removeItem(at: scoreURL(item)); updated.file = "score.musicxml" }
        try data.write(to: folder(item).appending(path: updated.file))
        save(updated)
        return updated
    }

    func restoreOriginal(_ item: ScoreItem) {
        Analytics.track("score_original_restored")
        guard let original = originalURL(item) else { return }
        var restored = item
        let ext = original.pathExtension
        try? FileManager.default.removeItem(at: scoreURL(item))
        restored.file = "score." + ext
        try? FileManager.default.copyItem(at: original, to: folder(item).appending(path: restored.file))
        save(restored)
    }

    func removeLyrics(_ item: ScoreItem) {
        var item = item
        if let old = item.lyrics { try? FileManager.default.removeItem(at: folder(item).appending(path: old)) }
        try? FileManager.default.removeItem(at: singersURL(item))
        item.lyrics = nil
        save(item)
    }

    /// Free keeps three scores (scales and arpeggios made by the app don't count); a paid plan keeps any number.
    static let freeLimit = 3
    func requireRoom() throws {
        guard !Store.shared.allows(.performer), items.filter({ $0.generated != true }).count >= Self.freeLimit else { return }
        throw ScoreError.unsupported(String(localized: "Free keeps up to \(Self.freeLimit) scores. Delete one, or choose a plan in Settings to keep as many as you like."))
    }

    @discardableResult
    func importScore(from url: URL) throws -> ScoreItem {
        try requireRoom()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        Analytics.track("score_imported", ["kind": ext])
        if ext.range(of: #"^(sg|mg)[a-z0-9]$"#, options: .regularExpression) != nil {
            throw ScoreError.unsupported(String(localized: "Band-in-a-Box songs are saved in a closed format that only Band-in-a-Box can read. In Band-in-a-Box choose File ▸ Save As ▸ MusicXML (for the notation) and Audio (for the backing track), then import those."))
        }
        var item = ScoreItem(title: Self.importTitle(url.deletingPathExtension().lastPathComponent), file: "score." + url.pathExtension.lowercased())
        try FileManager.default.createDirectory(at: folder(item), withIntermediateDirectories: true)
        try copyIn(url, to: scoreURL(item))
        if item.isCDG {
            do { _ = try CDGPlayer(data: Data(contentsOf: scoreURL(item))) } catch {
                try? FileManager.default.removeItem(at: folder(item))
                throw error
            }
            save(item)
            return item
        }
        if item.isLyricsOnly {
            do {
                let doc = try Lyrics.document(from: scoreURL(item), duration: nil)
                guard !doc.isEmpty else { throw ScoreError.unsupported(String(localized: "There are no lyrics in that file.")) }
                if let t = doc.title, !t.isEmpty { item.title = t }
            } catch {
                try? FileManager.default.removeItem(at: folder(item))
                throw error
            }
            save(item)
            return item
        }
        // Validate up front so a bad file never lands in the library.
        do {
            let loaded = try ScoreLoader.load(scoreURL(item), beatsPerBar: 4, analyse: false)
            if !loaded.title.isEmpty { item.title = TitleClean.clean(loaded.title) }
            if let t = loaded.tempo { item.tempo = t }
        } catch {
            try? FileManager.default.removeItem(at: folder(item))
            throw error
        }
        save(item)
        return item
    }

    func importTrack(from url: URL, for item: ScoreItem) throws -> ScoreItem {
        Analytics.track("backing_track_added", ["kind": url.pathExtension.lowercased()])
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var item = item
        if let old = trackURL(item) { try? FileManager.default.removeItem(at: old) }
        item.track = "track." + url.pathExtension.lowercased()
        try copyIn(url, to: folder(item).appending(path: item.track!))
        save(item)
        return item
    }

    /// Copies an imported file into the library, so the original can be moved or deleted. Coordinated
    /// reading downloads files that are only in iCloud before the copy.
    private func copyIn(_ url: URL, to dest: URL) throws {
        var coordination: NSError?, failure: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordination) { src in
            do { try FileManager.default.copyItem(at: src, to: dest) } catch { failure = error }
        }
        if let e = coordination ?? failure { throw e }
    }

    /// Recordings of the player, with their analysis, kept in the score's own folder.
    func takesFolder(_ item: ScoreItem) -> URL { folder(item).appending(path: "takes", directoryHint: .isDirectory) }
    func takes(_ item: ScoreItem) -> [Take] {
        let files = (try? FileManager.default.contentsOfDirectory(at: takesFolder(item), includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap { try? JSONDecoder().decode(Take.self, from: Data(contentsOf: $0)) }.sorted { $0.date > $1.date }
    }
    func save(_ take: Take, for item: ScoreItem) {
        try? FileManager.default.createDirectory(at: takesFolder(item), withIntermediateDirectories: true)
        try? JSONEncoder().encode(take).write(to: takesFolder(item).appending(path: "\(take.id.uuidString).json"))
    }
    func delete(_ take: Take, for item: ScoreItem) {
        let dir = takesFolder(item)
        try? FileManager.default.removeItem(at: dir.appending(path: "\(take.id.uuidString).json"))
        if let a = take.audio { try? FileManager.default.removeItem(at: dir.appending(path: a)) }
    }
    func audioURL(_ take: Take, for item: ScoreItem) -> URL? { take.audio.map { takesFolder(item).appending(path: $0) } }

    func trackEditURL(_ item: ScoreItem) -> URL { folder(item).appending(path: "trackedit.json") }
    func trackEdit(_ item: ScoreItem) -> TrackEdit { (try? JSONDecoder().decode(TrackEdit.self, from: Data(contentsOf: trackEditURL(item)))) ?? TrackEdit() }
    func saveTrackEdit(_ edit: TrackEdit, for item: ScoreItem) {
        if edit.isEmpty { try? FileManager.default.removeItem(at: trackEditURL(item)) }
        else { try? JSONEncoder().encode(edit).write(to: trackEditURL(item)) }
    }

    /// Adds another backing track that plays with the others.
    func addExtraTrack(from url: URL, for item: ScoreItem) throws -> ScoreItem {
        Analytics.track("extra_track_added")
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var item = items.first { $0.id == item.id } ?? item
        let id = UUID()
        let file = "track-\(id.uuidString.prefix(8))." + url.pathExtension.lowercased()
        try copyIn(url, to: folder(item).appending(path: file))
        item.extraTracks = (item.extraTracks ?? []) + [ExtraTrack(id: id, file: file, name: url.deletingPathExtension().lastPathComponent)]
        save(item)
        return item
    }

    func removeExtraTrack(_ id: UUID, from item: ScoreItem) {
        var item = items.first { $0.id == item.id } ?? item
        if let t = item.extraTracks?.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: folder(item).appending(path: t.file))
            try? FileManager.default.removeItem(at: folder(item).appending(path: VocalReducer.derivedName(t.file)))
        }
        item.extraTracks?.removeAll { $0.id == id }
        if item.extraTracks?.isEmpty == true { item.extraTracks = nil }
        save(item)
    }

    func removeTrack(_ item: ScoreItem) {
        Analytics.track("backing_track_removed")
        var item = items.first { $0.id == item.id } ?? item
        try? FileManager.default.removeItem(at: trackEditURL(item))
        if let old = trackURL(item) { try? FileManager.default.removeItem(at: old) }
        if let t = item.track { try? FileManager.default.removeItem(at: folder(item).appending(path: VocalReducer.derivedName(t))) }
        item.track = nil
        item.offset = 0
        item.trackName = nil; item.trackEnabled = nil; item.reduceVocals = nil
        save(item)
    }

    func save(_ item: ScoreItem) {
        try? JSONEncoder().encode(item).write(to: folder(item).appending(path: "info.json"))
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.insert(item, at: 0) }
    }

    /// A copy of a score with everything that goes with it: its backing track, lyrics, drawings, settings and the original it
    /// was edited from. It is a normal item of its own, called "… copy" (then "… copy 2" and so on).
    @discardableResult
    func duplicate(_ item: ScoreItem) throws -> ScoreItem {
        try requireRoom()
        Analytics.track("score_duplicated")
        var copy = item
        copy.id = UUID(); copy.added = Date(); copy.source = nil; copy.generated = nil
        var title = item.title + " copy", n = 2
        while items.contains(where: { $0.title == title }) { title = item.title + " copy \(n)"; n += 1 }
        copy.title = title
        try FileManager.default.copyItem(at: folder(item), to: folder(copy))
        save(copy)
        return copy
    }

    func delete(_ item: ScoreItem) {
        Analytics.track("score_deleted")
        try? FileManager.default.removeItem(at: folder(item))
        items.removeAll { $0.id == item.id }
        for i in playlists.indices { playlists[i].scores.removeAll { $0 == item.id } }
        savePlaylists()
    }

    // MARK: Tempo

    /// The tempo the score gives. The item plays at it unless the person has set a tempo of their own.
    @discardableResult func adoptScoreTempo(_ t: Double, for item: ScoreItem) -> ScoreItem {
        guard var it = items.first(where: { $0.id == item.id }) else { return item }
        if it.scoreTempo != t || (it.customTempo != true && abs(it.tempo - t) > 0.01) {
            it.scoreTempo = t
            if it.customTempo != true { it.tempo = t }
            save(it)
        }
        return it
    }

    /// The person's own tempo (typed, tapped, or matched to a recording). Setting it back to the score's own clears the override.
    func setTempo(_ t: Double, for item: ScoreItem) {
        guard var it = items.first(where: { $0.id == item.id }) else { return }
        it.tempo = t
        it.customTempo = it.scoreTempo.map { abs($0 - t) > 0.01 } ?? true ? true : nil
        save(it)
    }

    /// Back to the score's own tempo (and which tempo that is, if it has one).
    @discardableResult func useScoreTempo(for item: ScoreItem) -> Double? {
        guard var it = items.first(where: { $0.id == item.id }), let s = it.scoreTempo else { return nil }
        it.customTempo = nil
        it.tempo = s
        save(it)
        return s
    }

    // MARK: Set-lists

    /// Seconds a score takes: its backing track if it has one, otherwise its notes at its tempo. Nil when neither is known.
    func estimatedSeconds(_ item: ScoreItem) -> Double? {
        if let s = item.trackSeconds, s > 0 { return s }
        if let b = item.lengthBeats, b > 0, item.tempo > 0 { return b * 60 / item.tempo }
        return nil
    }

    /// "4 scores · about 14 min", with a note when some scores have no known length.
    func summary(of list: Playlist) -> String {
        let members = scores(in: list)
        guard !members.isEmpty else { return String(localized: "Empty") }
        var seconds = 0.0, unknown = 0
        for m in members { if let s = estimatedSeconds(m) { seconds += s } else { unknown += 1 } }
        let count = members.count == 1 ? String(localized: "1 score") : String(localized: "\(members.count) scores")
        guard seconds > 0 else { return count }
        return count + String(localized: " · about ") + Self.approximately(seconds) + (unknown > 0 ? String(localized: " + \(unknown) not timed") : "")
    }

    static func approximately(_ seconds: Double) -> String {
        if seconds < 90 { return String(localized: "\(Int(seconds.rounded())) sec") }
        let minutes = Int((seconds / 60).rounded())
        return minutes < 60 ? String(localized: "\(minutes) min") : String(localized: "\(minutes / 60) h \(minutes % 60) min")
    }

    /// Works out the length of each score that doesn't have one yet (once, in the background), for the set-list totals.
    func fillLengths() async {
        let todo = items.filter { ($0.lengthBeats == nil && !$0.isPDF && !$0.isLyricsOnly) || ($0.track != nil && $0.trackSeconds == nil) }
        for it in todo {
            let score = scoreURL(it), track = trackURL(it), wantBeats = it.lengthBeats == nil && !it.isPDF && !it.isLyricsOnly
            let m = await Task.detached(priority: .utility) { Self.measure(score: wantBeats ? score : nil, track: it.trackSeconds == nil ? track : nil) }.value
            guard var u = items.first(where: { $0.id == it.id }) else { continue }
            if wantBeats { u.lengthBeats = m.beats ?? -1 }
            if it.trackSeconds == nil, track != nil { u.trackSeconds = m.seconds ?? -1 }
            save(u)
        }
    }

    private nonisolated static func measure(score: URL?, track: URL?) -> (beats: Double?, seconds: Double?) {
        var beats: Double?, seconds: Double?
        if let score, ["musicxml", "xml", "mxl"].contains(score.pathExtension.lowercased()),
           let parsed = try? MusicXML.parse(MusicXML.data(from: score)) {
            beats = Double(parsed.playOrder.reduce(0) { $0 + parsed.measures[$1].length }) / Double(ticksPerQuarter)
        }
        if let track, let f = try? AVAudioFile(forReading: track), f.processingFormat.sampleRate > 0 { seconds = Double(f.length) / f.processingFormat.sampleRate }
        return (beats, seconds)
    }

    // MARK: Playlists

    func scores(in playlist: Playlist) -> [ScoreItem] {
        playlist.scores.compactMap { id in items.first { $0.id == id } }
    }

    @discardableResult
    func newPlaylist(_ name: String, adding item: ScoreItem? = nil) -> Playlist {
        Analytics.track("playlist_created")
        let p = Playlist(name: name, scores: item.map { [$0.id] } ?? [])
        playlists.append(p)
        savePlaylists()
        return p
    }

    func rename(_ playlist: Playlist, to name: String) { edit(playlist) { $0.name = name } }
    func add(_ item: ScoreItem, to playlist: Playlist) { edit(playlist) { if !$0.scores.contains(item.id) { $0.scores.append(item.id) } } }
    func remove(_ item: ScoreItem, from playlist: Playlist) { edit(playlist) { $0.scores.removeAll { $0 == item.id } } }
    func move(in playlist: Playlist, from: IndexSet, to: Int) { edit(playlist) { $0.scores.move(fromOffsets: from, toOffset: to) } }

    func delete(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        savePlaylists()
    }

    private func edit(_ playlist: Playlist, _ change: (inout Playlist) -> Void) {
        guard let i = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        change(&playlists[i])
        savePlaylists()
    }

    private func savePlaylists() { try? JSONEncoder().encode(playlists).write(to: playlistsURL) }

    func importSample() throws -> ScoreItem {
        return try importScore(from: Bundle.main.url(forResource: "Ode to Joy", withExtension: "musicxml")!)
    }
}

// MARK: - Loading a score file into pages + timeline

nonisolated final class LoadedScore: @unchecked Sendable {
    let document: CGPDFDocument
    let pages: [CGPDFPage]
    let title: String
    let tempo: Double?
    let isPDF: Bool
    /// One label per staff of an engraved score ("Staff 1: Treble clef"), for choosing an instrument for each.
    var staves: [String] = []
    /// The key as written, before any transposition.
    var key: (fifths: Int, minor: Bool)?
    private let read: [ReadSystem]
    private let engraved: Timeline

    init(document: CGPDFDocument, title: String, tempo: Double?, read: [ReadSystem], engraved: Timeline, isPDF: Bool) {
        self.document = document
        self.pages = (0..<document.numberOfPages).compactMap { document.page(at: $0 + 1) }
        self.title = title; self.tempo = tempo; self.read = read; self.engraved = engraved; self.isPDF = isPDF
    }

    /// PDFs: the metre the note values add up to, read from the page.
    var detectedBeatsPerBar: Double? { isPDF ? SheetReader.detectedBeatsPerBar(read) : nil }

    /// PDFs: the music read from the page, as MusicXML.
    func musicXML(beatsPerBar: Double, title: String) -> Data {
        MusicXML.write(SheetReader.score(read, beatsPerBar: beatsPerBar, title: title))
    }

    func timeline(beatsPerBar: Double) -> Timeline {
        isPDF ? SheetReader.timeline(read, beatsPerBar: beatsPerBar) : engraved
    }
}

nonisolated enum ScoreLoader {
    static let musicFont: CTFont = {
        let url = Bundle.main.url(forResource: "Bravura", withExtension: "otf")!
        let desc = (CTFontManagerCreateFontDescriptorsFromData(try! Data(contentsOf: url) as CFData) as! [CTFontDescriptor])[0]
        return CTFontCreateWithFontDescriptor(desc, 28, nil)
    }()

    static func load(_ url: URL, beatsPerBar: Double, analyse: Bool = true, transpose: Int = 0, zoom: Double = 1, lyrics: [LyricSyllable] = [], sheetTitle: String? = nil) throws -> LoadedScore {
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = CGPDFDocument(url as CFURL), doc.numberOfPages > 0 else {
                throw ScoreError.unsupported(String(localized: "This PDF couldn’t be opened. It may be damaged or password-protected."))
            }
            let read = analyse ? SheetReader.read(doc) : []
            let loaded = LoadedScore(document: doc, title: "", tempo: nil, read: read, engraved: Timeline(), isPDF: true)
            if let first = read.first { loaded.key = (first.key, false) }   // ponytail: mode isn't read, so minor keys show as their relative major
            return loaded
        }
        let original = try MusicXML.parse(MusicXML.data(from: url))
        var parsed = original.transposed(by: transpose)
        parsed.title = sheetTitle ?? TitleClean.clean(parsed.title)   // the title printed on the page never names the key
        ScoreEdit.addLyrics(&parsed, syllables: lyrics.map { ($0.text, $0.wordEnd) })   // words from a lyrics file go under the notes
        let (pdf, timeline) = Engraver.engrave(parsed, musicFont: musicFont, scale: CGFloat(zoom))
        let doc = CGPDFDocument(CGDataProvider(data: pdf as CFData)!)!
        let loaded = LoadedScore(document: doc, title: parsed.title, tempo: parsed.tempo, read: [], engraved: timeline, isPDF: false)
        loaded.key = (original.measures.first?.key ?? 0, original.minor)
        loaded.staves = (0..<parsed.staffCount).map { s in
            let clef = parsed.measures.lazy.compactMap { $0.clefs[s] }.first
            let name = s < parsed.staffNames.count ? parsed.staffNames[s] : ""
            return String(localized: "Staff \(s + 1): ") + (name.isEmpty ? (clef?.sign == "F" ? String(localized: "Bass clef") : clef?.sign == "C" ? String(localized: "C clef") : String(localized: "Treble clef")) : name)
        }
        return loaded
    }
}
