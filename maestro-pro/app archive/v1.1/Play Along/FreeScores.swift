import SwiftUI

/// Public-domain scores bundled with the app (the MuseTrainer library), added to the library on request.
struct FreeScore: Identifiable {
    let file: String, title: String
    var id: String { file }

    static let all: [FreeScore] = {
        guard let url = Bundle.main.url(forResource: "free-scores", withExtension: "json", subdirectory: "Free Scores") ?? Bundle.main.url(forResource: "free-scores", withExtension: "json"),
              let names = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))) else { return [] }
        return names.map { FreeScore(file: $0.key, title: $0.value) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }()

    var url: URL? {
        let name = (file as NSString).deletingPathExtension
        return Bundle.main.url(forResource: name, withExtension: "mxl", subdirectory: "Free Scores") ?? Bundle.main.url(forResource: name, withExtension: "mxl")
    }
}

extension Library {
    func has(_ score: FreeScore) -> Bool { items.contains { $0.title == score.title } }

    @discardableResult func add(_ score: FreeScore) throws -> ScoreItem {
        Analytics.track("catalogue_score_added")
        if let existing = items.first(where: { $0.title == score.title }) { return existing }
        guard let url = score.url else { throw ScoreError.unsupported("“\(score.title)” is missing from the app.") }
        var item = try importScore(from: url)
        item.title = score.title
        save(item)
        return item
    }
}

/// The jazz collection: only its list is in the app; each tune is downloaded when it is asked for.
struct JazzScore: Identifiable {
    let dir: String, file: String
    var id: String { dir + "/" + file }
    var key: String { "jazz/" + id }
    /// The tune's name alone: no extension, camelCase split, trailing key, part, instrument or version tags dropped.
    var title: String {
        var t = (file as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
        if let r = t.range(of: " - ") { t = String(t[..<r.lowerBound]) }
        for (pattern, with) in [("(?<=[a-z])(?=[A-Z])", " "), ("(?<=[a-z])(?=[A-G][#b]?$)", " "), ("(?<=[A-Za-z])\\d+$", "")] {
            t = t.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
        }
        var words = t.split(separator: " ").map(String.init)
        let tag = try! NSRegularExpression(pattern: "^(transcription|lead|bass|with|score|full|sax|asax|alto|tenor|piano|melody|part|chords|final|\\d+|i{1,3}|iv|v|[a-g][#b]?m?)$", options: .caseInsensitive)
        while words.count > 1, let w = words.last, tag.firstMatch(in: w, range: NSRange(w.startIndex..., in: w)) != nil { words.removeLast() }
        return words.joined(separator: " ")
    }
    /// Same tune under another file name, for hiding duplicates.
    var sameTuneKey: String { title.lowercased().filter { $0.isLetter || $0.isNumber } }
    var volume: String {
        switch dir {
        case "IV_Part-1": "Volume IV (Part 1)"
        case "IV_Part-2": "Volume IV (Part 2)"
        default: "Volume \(dir)"
        }
    }
    var url: URL? {
        var c = URLComponents(string: "https://effendi.me/jazz/repo/")
        c?.path += "\(dir)/\(file)"
        return c?.url
    }

    static let volumes: [(dir: String, scores: [JazzScore])] = {
        guard let url = Bundle.main.url(forResource: "jazz-fake-book", withExtension: "json", subdirectory: "Free Scores") ?? Bundle.main.url(forResource: "jazz-fake-book", withExtension: "json"),
              let list = try? JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: url)) else { return [] }
        var seen = Set<String>()
        return ["I", "II", "III", "IV_Part-1", "IV_Part-2", "V"].compactMap { d in
            list[d].map { (d, $0.map { JazzScore(dir: d, file: $0) }.filter { seen.insert($0.sameTuneKey).inserted }) }
        }
    }()
}

extension Library {
    func has(_ score: JazzScore) -> Bool { items.contains { $0.source == score.key } }

    /// Downloads one tune and adds it to the library.
    @discardableResult func add(_ score: JazzScore) async throws -> ScoreItem {
        Analytics.track("jazz_score_added")
        if let existing = items.first(where: { $0.source == score.key }) { return existing }
        guard let remote = score.url else { throw ScoreError.unsupported("“\(score.title)” has no address.") }
        let (data, response) = try await URLSession.shared.data(from: remote)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ScoreError.unsupported("“\(score.title)” couldn’t be downloaded. Check your connection and try again.") }
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: score.file)
        try data.write(to: file)
        var item = try importScore(from: file)
        item.title = score.title
        item.source = score.key
        save(item)
        return item
    }
}

struct FreeScoreBrowser: View {
    let open: (ScoreItem) -> Void
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var failure: String?
    @State private var source = Source.classical
    @State private var downloading: Set<String> = []
    @State private var bulk: (done: Int, of: Int)?
    @State private var confirmAll = false
    @State private var onlineResults: [OnlineScore] = []
    @State private var onlineSearching = false
    @State private var instrument = "All"

    enum Source: String, CaseIterable, Identifiable {
        case classical = "Classical", jazz = "Jazz", internet = "Internet"
        var id: String { rawValue }
    }

    private var shown: [FreeScore] {
        query.isEmpty ? FreeScore.all : FreeScore.all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var jazz: [(dir: String, scores: [JazzScore])] {
        JazzScore.volumes.map { v in (v.dir, query.isEmpty ? v.scores : v.scores.filter { $0.title.localizedCaseInsensitiveContains(query) }) }.filter { !$0.scores.isEmpty }
    }
    private var jazzToAdd: [JazzScore] { jazz.flatMap(\.scores).filter { !library.has($0) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Collection", selection: $source) { ForEach(Source.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) } }
                        .pickerStyle(.segmented)
                }
                if source == .classical {
                    ForEach(shown) { score in
                        HStack {
                            Text(score.title)
                            Spacer()
                            if library.has(score) {
                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                            } else {
                                Button("Add") { add(score) }.buttonStyle(.bordered)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if let item = try? library.add(score) { open(item); dismiss() } }
                    }
                } else if source == .jazz {
                    Section { Text("Jazz tunes are downloaded when you add them, so you need to be online.").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(jazz, id: \.dir) { volume in
                        Section(volume.scores[0].volume) {
                            ForEach(volume.scores) { score in
                                HStack {
                                    Text(score.title)
                                    Spacer()
                                    if library.has(score) {
                                        Image(systemName: "checkmark").foregroundStyle(.secondary)
                                    } else if downloading.contains(score.id) {
                                        ProgressView()
                                    } else {
                                        Button("Add") { Task { await add(score) } }.buttonStyle(.bordered)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { if let item = await add(score) { open(item); dismiss() } }
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        Picker("Instrument", selection: $instrument) {
                            ForEach(["All", "Piano", "Violin", "Guitar", "Cello", "Flute", "Trumpet", "Saxophone", "Choir"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                        }
                        Text("Searches the web, and GitHub, for MusicXML scores. Type a composer or piece name above. Check that a score is free to use before you add it.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if onlineSearching {
                        Section { HStack { Spacer(); ProgressView(); Spacer() } }
                    } else if onlineResults.isEmpty, !query.isEmpty {
                        Section { Text("No results. Try a different search or instrument.").foregroundStyle(.secondary) }
                    }
                    ForEach(onlineResults) { score in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(score.title)
                                Text(score.repoName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if library.has(score) {
                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                            } else if downloading.contains(score.key) {
                                ProgressView()
                            } else {
                                Button("Add") { Task { await addOnline(score) } }.buttonStyle(.bordered)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { Task { if let item = await addOnline(score) { open(item); dismiss() } } }
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle("Search Scores")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: "\(source.rawValue) \(query) \(instrument)") {
                guard source == .internet else { return }
                let q = query.trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else { onlineResults = []; return }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                onlineSearching = true
                defer { onlineSearching = false }
                onlineResults = await OnlineScoreSearch.find(q, instrument: instrument == "All" ? "" : instrument)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if let bulk {
                        Text("\(bulk.done) of \(bulk.of)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    } else if source == .classical {
                        Button("Add All") { shown.forEach(add) }.disabled(shown.allSatisfy(library.has))
                    } else if source == .jazz {
                        Button("Add All") { confirmAll = true }.disabled(jazzToAdd.isEmpty)
                    }
                }
            }
            .confirmationDialog("Download \(jazzToAdd.count) tunes?", isPresented: $confirmAll, titleVisibility: .visible) {
                Button("Download \(jazzToAdd.count)") { addAllJazz() }
            } message: { Text("Each is a small file, fetched from effendi.me.") }
            .alert("Couldn’t Add Score", isPresented: .constant(failure != nil), presenting: failure) { _ in
                Button("OK") { failure = nil }
            } message: { Text($0) }
        }
    }

    private func add(_ score: FreeScore) {
        do { try withAnimation(.smooth) { _ = try library.add(score) } } catch { failure = error.localizedDescription }
    }

    @discardableResult private func add(_ score: JazzScore) async -> ScoreItem? {
        downloading.insert(score.id)
        defer { downloading.remove(score.id) }
        do { return try await library.add(score) } catch { failure = error.localizedDescription; return nil }
    }

    private func addAllJazz() {
        let list = jazzToAdd
        bulk = (0, list.count)
        Task {
            var failed = 0
            for (n, s) in list.enumerated() {
                do { _ = try await library.add(s) } catch { failed += 1 }
                bulk = (n + 1, list.count)
            }
            bulk = nil
            if failed > 0 { failure = "\(failed) of \(list.count) tunes couldn’t be downloaded. Check your connection and try again." }
        }
    }

    @discardableResult private func addOnline(_ score: OnlineScore) async -> ScoreItem? {
        downloading.insert(score.key)
        defer { downloading.remove(score.key) }
        do { return try await library.add(score) } catch { failure = error.localizedDescription; return nil }
    }
}

// MARK: - Public domain internet search

struct OnlineScore: Identifiable {
    let id: String   // "owner/repo/path"
    let title: String
    let repoName: String
    let rawURL: URL
    var key: String { "github/\(id)" }
}

extension Library {
    func has(_ score: OnlineScore) -> Bool { items.contains { $0.source == score.key } }

    @discardableResult func add(_ score: OnlineScore) async throws -> ScoreItem {
        Analytics.track("internet_score_added")
        if let existing = items.first(where: { $0.source == score.key }) { return existing }
        let (data, response) = try await URLSession.shared.data(from: score.rawURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ScoreError.unsupported(String(localized: "Couldn’t download \(score.title). Check your connection and try again."))
        }
        let ext = score.rawURL.pathExtension.isEmpty ? "musicxml" : score.rawURL.pathExtension
        let tmp = FileManager.default.temporaryDirectory.appending(path: "\(score.title).\(ext)")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        var item = try importScore(from: tmp)
        item.title = score.title
        item.source = score.key
        save(item)
        return item
    }
}

enum OnlineScoreSearch {
    /// Searches GitHub and the web concurrently, merging and deduplicating results.
    static func find(_ query: String, instrument: String) async -> [OnlineScore] {
        let q = instrument.isEmpty ? query : "\(query) \(instrument)"
        async let github = githubSearch(q)
        async let web = webSearch(q)
        let (g, w) = await (github, web)
        var seen = Set<String>()
        return (g + w).filter { seen.insert($0.id).inserted }
    }

    // MARK: GitHub repo search

    private static func githubSearch(_ query: String) async -> [OnlineScore] {
        var c = URLComponents(string: "https://api.github.com/search/repositories")!
        c.queryItems = [.init(name: "q", value: "\(query) musicxml in:name,description,topics"), .init(name: "sort", value: "stars"), .init(name: "per_page", value: "6")]
        var req = URLRequest(url: c.url!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        struct Repo: Decodable { var full_name: String; var name: String; var default_branch: String }
        struct Reply: Decodable { var items: [Repo] }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let repos = try? JSONDecoder().decode(Reply.self, from: data).items else { return [] }
        var results: [OnlineScore] = []
        for repo in repos {
            let files = await listMusicXML(repo: repo.full_name, branch: repo.default_branch)
            for f in files {
                results.append(OnlineScore(id: "\(repo.full_name)/\(f.path)", title: (f.name as NSString).deletingPathExtension, repoName: repo.name, rawURL: f.rawURL))
            }
        }
        return results
    }

    private struct RawFile { var name: String; var path: String; var rawURL: URL }

    private static func listMusicXML(repo: String, branch: String) async -> [RawFile] {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/git/trees/\(branch)?recursive=1") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        struct Tree: Decodable { var tree: [Node] }
        struct Node: Decodable { var path: String; var type: String }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let nodes = try? JSONDecoder().decode(Tree.self, from: data).tree else { return [] }
        return nodes
            .filter { $0.type == "blob" && ($0.path.hasSuffix(".musicxml") || $0.path.hasSuffix(".mxl")) }
            .prefix(4)
            .compactMap { node in
                let name = (node.path as NSString).lastPathComponent
                let encoded = node.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? node.path
                return URL(string: "https://raw.githubusercontent.com/\(repo)/\(branch)/\(encoded)")
                    .map { RawFile(name: name, path: node.path, rawURL: $0) }
            }
    }

    // MARK: Web search

    /// Asks a web search engine for pages about the piece, then reads each page for links to MusicXML files. There is no
    /// key-free search service meant for this, so it reads the engine's ordinary results page; if that changes, only this
    /// function needs to.
    private static func webSearch(_ query: String) async -> [OnlineScore] {
        var c = URLComponents(string: "https://search.brave.com/search")!
        c.queryItems = [.init(name: "q", value: "\(query) musicxml mxl download")]
        guard let url = c.url, let page = await fetch(url) else { return [] }
        let pages = links(in: page, base: url, pattern: ##"href=\"(https?://[^\"#]+)\""##)
            .filter { u in !["brave.com", "brave.software", "youtube.com", "facebook.com"].contains { u.host?.hasSuffix($0) == true } }
        var seenHosts = Set<String>(), chosen: [URL] = []
        for u in pages where seenHosts.insert(u.host ?? "").inserted { chosen.append(u) }
        return await withTaskGroup(of: [OnlineScore].self) { group in
            for u in chosen.prefix(10) {
                group.addTask {
                    // A result can be the file itself, or a page that links to it.
                    if isScore(u) { return [score(u)] }
                    guard let html = await fetch(u) else { return [] }
                    return links(in: html, base: u, pattern: ##"href=[\"']([^\"'#>\s]+\.(?:mxl|musicxml)(?:\?[^\"'>\s]*)?)[\"']"##).filter(isScore).prefix(5).map(score)
                }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }
    }

    private static func fetch(_ url: URL) async -> String? {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req), (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return String(decoding: data.prefix(1_500_000), as: UTF8.self)
    }

    private static func links(in html: String, base: URL, pattern: String) -> [URL] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        var seen = Set<URL>()
        return re.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { m in
            Range(m.range(at: 1), in: html).flatMap { URL(string: String(html[$0]).replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL }
        }.filter { seen.insert($0).inserted }
    }

    private static func isScore(_ u: URL) -> Bool { ["mxl", "musicxml"].contains(u.pathExtension.lowercased()) }

    private static func score(_ u: URL) -> OnlineScore {
        let title = (u.lastPathComponent.removingPercentEncoding ?? u.lastPathComponent as String) as NSString
        return OnlineScore(id: "web/\(u.absoluteString)", title: TitleClean.tidy(title.deletingPathExtension), repoName: u.host ?? "Web", rawURL: u)
    }
}
