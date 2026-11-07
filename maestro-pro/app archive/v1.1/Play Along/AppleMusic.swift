import os
import SwiftUI
#if canImport(MusicKit)
import MusicKit
#endif

// Apple Music: choose a song to play along with, and fetch its lyrics. The song is streamed by Apple Music (it needs a
// subscription), so the app starts, stops and keeps it in time but can't change it: no key change, and the singer can't be
// taken out (Apple Music does not give apps the audio, only the playing of it).

/// One song found by a search.
struct SongHit: Identifiable, Hashable {
    var id: String          // the Apple Music catalogue ID
    var title: String
    var artist: String
    var artwork: URL?
    var duration: Double?
}

enum AppleMusicCatalog {
    /// Searches the whole of Apple Music through Apple's public catalogue search (no developer token or sign-in needed).
    static func search(_ term: String) async throws -> [SongHit] {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        let country = Locale.current.region?.identifier ?? "US"
        c.queryItems = [.init(name: "term", value: term), .init(name: "media", value: "music"), .init(name: "entity", value: "song"),
                        .init(name: "limit", value: "30"), .init(name: "country", value: country)]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        struct Reply: Decodable { struct Hit: Decodable { var trackId: Int?; var trackName: String?; var artistName: String?; var artworkUrl100: String?; var trackTimeMillis: Double? }; var results: [Hit] }
        return try JSONDecoder().decode(Reply.self, from: data).results.compactMap { h in
            guard let id = h.trackId, let t = h.trackName else { return nil }
            return SongHit(id: String(id), title: t, artist: h.artistName ?? "", artwork: h.artworkUrl100.flatMap(URL.init), duration: h.trackTimeMillis.map { $0 / 1000 })
        }
    }

    /// Songs in the person's own library that match (needs only the Apple Music permission).
    static func library(_ term: String) async -> [SongHit] {
        #if canImport(MusicKit)
        guard MusicAuthorization.currentStatus == .authorized,
              let r = try? await MusicLibrarySearchRequest(term: term, types: [Song.self]).response() else { return [] }
        return r.songs.prefix(25).compactMap { song in
            // A library song plays through its catalogue ID, when it has one.
            guard let data = try? JSONEncoder().encode(song.playParameters),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = (json["catalogId"] as? String) ?? (json["catalogID"] as? String) else { return nil }
            return SongHit(id: id, title: song.title, artist: song.artistName, artwork: song.artwork?.url(width: 100, height: 100), duration: song.duration)
        }
        #else
        return []
        #endif
    }
}

#if canImport(MediaPlayer)
import MediaPlayer
import AVFoundation

/// Plays an Apple Music song through the system's app music player. The transport starts it, stops it and moves it back into
/// time if it drifts. Needs an Apple Music subscription.
@MainActor final class AppleMusicTrack: ExternalTrack {
    let id: String
    let duration: Double
    private let player = MPMusicPlayerController.applicationMusicPlayer
    private var queued = false
    private var starting = false

    init(id: String, duration: Double) { self.id = id; self.duration = duration }

    var isPlaying: Bool { player.playbackState == .playing }
    var currentTime: Double { player.currentPlaybackTime }
    var rate: Float = 1 { didSet { player.currentPlaybackRate = rate } }
    var enabled = true { didSet { if !enabled { pause() } } }

    static func authorize() async -> Bool {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: return true
        case .notDetermined: return await withCheckedContinuation { c in MPMediaLibrary.requestAuthorization { c.resume(returning: $0 == .authorized) } }
        default: return false
        }
    }

    func play(from seconds: Double) {
        guard enabled, !starting else { return }
        starting = true
        Task {
            defer { starting = false }
            if !queued {
                // Set up the audio session once when the track is first queued; resetting it on every play
                // interrupts playback and causes the stop/restart glitch.
                await Task.detached(priority: .userInitiated) {
                    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                    try? AVAudioSession.sharedInstance().setActive(true)
                }.value
                player.setQueue(with: [id])
                queued = true
                // prepareToPlay callback may never fire if the player hangs; race it against a 3-second timeout
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    let lock = OSAllocatedUnfairLock(initialState: false)
                    let go = { lock.withLock { done in if !done { done = true; c.resume() } } }
                    player.prepareToPlay { _ in go() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { go() }
                }
            }
            player.currentPlaybackTime = max(0, seconds)
            player.currentPlaybackRate = rate
            player.play()
        }
    }

    func pause() { player.pause() }
}
#endif

#if canImport(MusicKit)
extension AppleMusicTrack {
    /// The song's lyrics as LRC lines, when Apple Music offers them for it (this needs Apple's developer token, which MusicKit supplies).
    static func lyrics(for id: String) async -> String? {
        do {
            let storefront = try await MusicDataRequest.currentCountryCode
            guard let url = URL(string: "https://api.music.apple.com/v1/catalog/\(storefront)/songs/\(id)/lyrics") else { return nil }
            let data = try await MusicDataRequest(urlRequest: URLRequest(url: url)).response().data
            struct Reply: Decodable { struct Item: Decodable { struct Attributes: Decodable { var ttml: String? }; var attributes: Attributes }; var data: [Item] }
            guard let ttml = try JSONDecoder().decode(Reply.self, from: data).data.first?.attributes.ttml else { return nil }
            return TTML.toLRC(ttml)
        } catch { return nil }
    }
}
#endif

extension Transport {
    /// Makes the transport play along with the Apple Music song a score has chosen (or none).
    func attachAppleMusic(_ ref: AppleMusicRef?) async {
        #if canImport(MediaPlayer)
        guard let ref else { setExternal(nil, id: nil, offset: 0); return }
        if externalID == ref.id, external != nil {
            setExternalOffset(ref.offset)
            setExternalEnabled(ref.enabled)
            return
        }
        guard await AppleMusicTrack.authorize() else { return }
        setExternal(AppleMusicTrack(id: ref.id, duration: ref.duration ?? 240), id: ref.id, offset: ref.offset)
        setExternalEnabled(ref.enabled)
        #endif
    }
}

/// Search the whole of Apple Music (and your own library) for a song. It searches as you type and says plainly when something is wrong.
struct AppleMusicSearchView: View {
    var dismissOnPick = true
    let onPick: (AppleMusicRef) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var busy = false
    @State private var notice: String?
    @State private var detail: String?
    @State private var denied = false
    @State private var catalog: [SongHit] = []
    @State private var library: [SongHit] = []

    var body: some View {
        NavigationStack {
            List {
                if let notice {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(notice, systemImage: "info.circle").foregroundStyle(.primary)
                        if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                        if denied { Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } } }
                    }
                }
                if !catalog.isEmpty { Section("Apple Music") { ForEach(catalog) { row($0) } } }
                if !library.isEmpty { Section("In Your Library") { ForEach(library) { row($0) } } }
                if term.isEmpty, notice == nil {
                    Text("Type the name of a song or an artist.").foregroundStyle(.secondary)
                }
            }
            .overlay { if busy { ProgressView() } }
            .searchable(text: $term, placement: .navigationBarDrawer(displayMode: .always), prompt: String(localized: "Songs on Apple Music"))
            .task(id: term) { await search() }
            .task { await check() }
            #if DEBUG
            .onAppear { if let i = CommandLine.arguments.firstIndex(of: "-musicterm"), i + 1 < CommandLine.arguments.count { term = CommandLine.arguments[i + 1] } }
            #endif
            .navigationTitle("Apple Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func row(_ song: SongHit) -> some View {
        Button {
            onPick(AppleMusicRef(id: song.id, title: song.title, artist: song.artist, duration: song.duration))
            if dismissOnPick { dismiss() }
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: song.artwork) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(song.artist).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if let d = song.duration { Text(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)).font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
            }
        }
        .buttonStyle(.plain)
    }

    /// Asks for what playing a song needs (the Apple Music permission) and says if a subscription is missing.
    private func check() async {
        #if canImport(MediaPlayer)
        guard await AppleMusicTrack.authorize() else {
            denied = true
            notice = String(localized: "Maestro Pro isn’t allowed to use Apple Music.")
            detail = String(localized: "Allow it in the Settings app under Maestro Pro (on a Mac, System Settings, Privacy and Security, Media and Apple Music).")
            return
        }
        #endif
        #if canImport(MusicKit)
        _ = await MusicAuthorization.request()
        if let sub = try? await MusicSubscription.current, !sub.canPlayCatalogContent { notice = String(localized: "Playing songs needs an Apple Music subscription."); detail = String(localized: "You can still search.") }
        #endif
    }

    private func search() async {
        let q = term.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { catalog = []; library = []; return }
        try? await Task.sleep(for: .milliseconds(400))   // wait for the typing to pause
        guard !Task.isCancelled else { return }
        busy = true
        defer { busy = false }
        do {
            let found = try await AppleMusicCatalog.search(q)
            guard !Task.isCancelled else { return }
            catalog = found
            if notice == "Apple Music couldn’t be searched." { notice = nil; detail = nil }
        } catch {
            guard !Task.isCancelled else { return }
            catalog = []
            notice = String(localized: "Apple Music couldn’t be searched.")
            detail = String(localized: "Check the connection and try again. (\(error.localizedDescription))")
        }
        let mine = await AppleMusicCatalog.library(q)
        guard !Task.isCancelled else { return }
        let have = Set(catalog.map(\.id))
        library = mine.filter { !have.contains($0.id) }
        if catalog.isEmpty, library.isEmpty, notice == nil { notice = String(localized: "No songs found.") }
        else if notice == "No songs found." { notice = nil }
    }
}

extension Library {
    /// Fetches the lyrics of a score's Apple Music song and keeps them with the score. False when Apple Music has none.
    func fetchAppleMusicLyrics(for item: ScoreItem) async -> Bool {
        #if canImport(MusicKit)
        guard let ref = items.first(where: { $0.id == item.id })?.appleMusic ?? item.appleMusic, let lrc = await AppleMusicTrack.lyrics(for: ref.id) else { return false }
        guard var it = items.first(where: { $0.id == item.id }) else { return false }
        if let old = it.lyrics { try? FileManager.default.removeItem(at: folder(it).appending(path: old)) }
        it.lyrics = "lyrics.lrc"
        do { try lrc.write(to: folder(it).appending(path: "lyrics.lrc"), atomically: true, encoding: .utf8) } catch { return false }
        save(it)
        return true
        #else
        return false
        #endif
    }

    /// A new lyrics screen for an Apple Music song: its words, in time, with the song playing along. Nil when Apple Music has no lyrics for it.
    func newAppleMusicItem(_ ref: AppleMusicRef) async -> ScoreItem? {
        #if canImport(MusicKit)
        guard let lrc = await AppleMusicTrack.lyrics(for: ref.id) else { return nil }
        let name = ref.title.replacingOccurrences(of: "/", with: "-")
        let tmp = FileManager.default.temporaryDirectory.appending(path: "\(name).lrc")
        guard (try? lrc.write(to: tmp, atomically: true, encoding: .utf8)) != nil, var item = try? importScore(from: tmp) else { return nil }
        try? FileManager.default.removeItem(at: tmp)
        item.title = ref.title
        item.appleMusic = ref
        save(item)
        return item
        #else
        return nil
        #endif
    }
}

// MARK: - Online lyrics search (lrclib.net)

struct LrcHit: Identifiable, Decodable {
    let id: Int
    let trackName: String
    let artistName: String
    let duration: Double?
    let syncedLyrics: String?
    let plainLyrics: String?

    /// Timed word by word (`<01:23.45>` before each word), so the words fill and swell as they're sung.
    var wordTimed: Bool { syncedLyrics?.range(of: #"<\d+:\d+(?:[.:]\d+)?>"#, options: .regularExpression) != nil }
}

enum LrcLibSearch {
    static func find(_ query: String) async -> [LrcHit] {
        var c = URLComponents(string: "https://lrclib.net/api/search")!
        c.queryItems = [.init(name: "q", value: query)]
        guard let url = c.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let hits = try? JSONDecoder().decode([LrcHit].self, from: data) else { return [] }
        return hits.filter { $0.syncedLyrics != nil }
    }
}

struct OnlineLyricsSheet: View {
    var initialTerm = ""
    /// Keeps the chosen lyrics, handed over as an .lrc file.
    let save: (URL) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var results: [LrcHit] = []
    @State private var busy = false
    @State private var showLyricsify = false
    @State private var failure: String?
    let onAdd: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if !results.isEmpty {
                    ForEach(results) { hit in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(hit.trackName).font(.body.weight(.semibold))
                                    if hit.wordTimed {
                                        Image(systemName: "star.fill").font(.caption).foregroundStyle(Theme.accent)
                                            .accessibilityLabel("Timed word by word")
                                            .help("Timed word by word")
                                    }
                                }
                                Text(hit.artistName).font(.callout).foregroundStyle(.secondary)
                                if let d = hit.duration {
                                    Text(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Add") { addHit(hit) }.buttonStyle(.bordered)
                        }
                    }
                    if results.contains(where: \.wordTimed) {
                        Label("Timed word by word: the words fill as they're sung.", systemImage: "star.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else if !term.isEmpty, !busy {
                    Text("No synced lyrics found. Try the song title and artist name.").foregroundStyle(.secondary)
                } else if term.isEmpty {
                    Text("Type the song title or artist to find synced lyrics.").foregroundStyle(.secondary)
                }
            }
            .overlay { if busy { ProgressView() } }
            .searchable(text: $term, prompt: String(localized: "Song title or artist"))
            .task(id: term) { await search() }
            .onAppear { if term.isEmpty { term = initialTerm } }
            .navigationTitle("Find Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Lyricsify…", systemImage: "safari") { showLyricsify = true }
                        .help("Find Enhanced lyrics (timed word by word) on lyricsify.com")
                }
            }
            .sheet(isPresented: $showLyricsify) {
                LyricsifyBrowser(term: term) { lrc in showLyricsify = false; add(lrc) }
            }
            .alert("Couldn't Add Lyrics", isPresented: .constant(failure != nil), presenting: failure) { _ in
                Button("OK") { failure = nil }
            } message: { Text($0) }
        }
    }

    private func search() async {
        let q = term.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        busy = true; defer { busy = false }
        results = await LrcLibSearch.find(q)
    }

    private func addHit(_ hit: LrcHit) {
        guard let lrc = hit.syncedLyrics else { failure = String(localized: "No synced lyrics available."); return }
        add(lrc.contains("[ar:") ? lrc : "[ar:\(hit.artistName)]\n[ti:\(hit.trackName)]\n" + lrc)   // so the singers can be looked up
    }

    private func add(_ lrc: String) {
        let tmp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".lrc")
        do {
            try lrc.write(to: tmp, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tmp) }
            try save(tmp)
            onAdd()
            dismiss()
        } catch { failure = error.localizedDescription }
    }
}

/// Choose a song and open its lyrics as a new item, with the song playing along.
struct AppleMusicLyricsSheet: View {
    @Environment(Library.self) private var library
    @State private var failed = false

    var body: some View {
        AppleMusicSearchView(dismissOnPick: false) { ref in
            Task {
                if let item = await library.newAppleMusicItem(ref) { library.showAppleMusic = false; library.openRequest = item.id } else { failed = true }
            }
        }
        .alert("No Lyrics", isPresented: $failed) { Button("OK") {} } message: { Text("Apple Music has no lyrics for that song, or it didn’t let the app read them.") }
    }
}
