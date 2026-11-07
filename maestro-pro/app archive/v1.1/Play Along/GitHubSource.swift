import Security
import SwiftUI
import UniformTypeIdentifiers

// GitHub repositories as a place to find tracks: the files in each are grouped by name (a score with the recording
// and lyrics file named like it), searched together, and a chosen track is downloaded and imported the same way as
// a folder from Files, so it pairs up and isn't added twice. A token (kept in the Keychain) opens private
// repositories and raises GitHub's limit of 60 requests an hour.

nonisolated struct GitHubRepo: Codable, Hashable, Identifiable {
    var owner: String
    var name: String
    var branch: String?
    /// Only look inside this folder.
    var folder: String?
    var id: String { [owner, name, branch ?? "", folder ?? ""].joined(separator: "/") }
    var title: String { "\(owner)/\(name)" + (folder.map { "/\($0)" } ?? "") }

    /// "owner/repo", or a github.com link to the repository, a branch or a folder in it.
    init?(_ text: String) {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "www.", "github.com/"] where s.lowercased().hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if s.hasSuffix(".git") { s.removeLast(4) }
        let parts = s.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        owner = parts[0]
        name = parts[1]
        if parts.count >= 4, parts[2] == "tree" {
            branch = parts[3]
            folder = parts.count > 4 ? parts[4...].joined(separator: "/") : nil
        }
    }
}

nonisolated struct GitHubTrack: Identifiable, Hashable {
    let repo: GitHubRepo
    let branch: String
    let name: String
    let files: [String]   // paths in the repository
    var id: String { repo.id + "|" + (files.first ?? name) }
    var hasScore: Bool { files.contains { GitHub.scoreExtensions.contains(GitHub.ext($0)) } }
    var hasLyrics: Bool { files.contains { UTType.lyricExtensions.contains(GitHub.ext($0)) } }
    var hasAudio: Bool { files.contains { GitHub.audioExtensions.contains(GitHub.ext($0)) } }
    /// The file name tidied for display: "hello_world" becomes "Hello World".
    var title: String { GitHub.tidy(name) }
}

nonisolated enum GitHub {
    static let scoreExtensions: Set<String> = ["pdf", "musicxml", "mxl", "xml", "maestropro", "playalong"]
    static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aif", "aiff", "caf", "aac", "flac"]
    static func ext(_ path: String) -> String { (path as NSString).pathExtension.lowercased() }

    /// Separators become spaces, camelCase is split, and all-lowercase words are capitalised.
    static func tidy(_ name: String) -> String {
        let spaced = name.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[_\\-.]+", with: " ", options: .regularExpression)
        let words = spaced.split(separator: " ").map { $0 == $0.lowercased() ? $0.capitalized : String($0) }
        return words.isEmpty ? name : words.joined(separator: " ")
    }

    /// Every word of the search appears somewhere in the text, ignoring case, accents, and punctuation.
    static func matches(_ text: String, _ search: String) -> Bool {
        func words(_ s: String) -> [String] {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }
        let hay = words(text)
        let joined = hay.joined(separator: " ")
        return words(search).allSatisfy { q in
            if joined.contains(q) { return true }
            let allowed = q.count <= 3 ? 0 : q.count <= 6 ? 1 : 2   // typos allowed grow with the word's length
            // Compared with whole words, and with the start of longer ones so a half-typed word still matches.
            return allowed > 0 && hay.contains { edits(q, $0) <= allowed || edits(q, String($0.prefix(q.count))) <= allowed }
        }
    }

    /// Levenshtein distance.
    private static func edits(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var prev = row[0]
            row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let cur = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = cur
            }
        }
        return a.isEmpty ? b.count : row[b.count]
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        let status: Int
        init(_ message: String, status: Int = 0) { errorDescription = message; self.status = status }
    }

    static func request(_ path: String, token: String?, raw: Bool = false, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: "https://api.github.com" + path) else { throw Failure(String(localized: "That isn't a GitHub address.")) }
        var req = URLRequest(url: url)
        req.setValue(raw ? "application/vnd.github.raw" : "application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpMethod = method
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body); req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: req)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200..<300: return data
        case 401: throw Failure("GitHub didn't accept the token. Check it, or remove it for public repositories.", status: 401)
        case 403, 429: throw Failure(method == "GET" ? String(localized: "GitHub's limit for requests without a token has been reached. Add a token, or try again in an hour.")
                                     : String(localized: "GitHub wouldn't let the token change this repository. It needs read and write access to the repository's contents."), status: 403)
        case 404: throw Failure("Couldn't find that on GitHub. If the repository is private, add a token that can read it.", status: 404)
        case let code: throw Failure("GitHub answered with an error (\(code)).", status: code)
        }
    }

    /// Every track in a repository (or its folder), named after its files.
    static func tracks(in repo: GitHubRepo, token: String?) async throws -> [GitHubTrack] {
        struct Info: Decodable { let default_branch: String }
        struct Tree: Decodable { struct Entry: Decodable { let path: String; let type: String }; let tree: [Entry] }
        let base = "/repos/\(repo.owner)/\(repo.name)"
        var branch = repo.branch ?? ""
        if branch.isEmpty { branch = try JSONDecoder().decode(Info.self, from: await request(base, token: token)).default_branch }
        let tree = try await JSONDecoder().decode(Tree.self, from: request("\(base)/git/trees/\(branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch)?recursive=1", token: token))
        let prefix = repo.folder.map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        var groups: [String: [String]] = [:]
        for entry in tree.tree where entry.type == "blob" {
            if let prefix, !entry.path.hasPrefix(prefix) { continue }
            let e = ext(entry.path), stem = ((entry.path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
            guard scoreExtensions.contains(e) || audioExtensions.contains(e) || UTType.lyricExtensions.contains(e),
                  !["readme", "license", "licence", "notes", "changelog"].contains(stem) else { continue }
            groups[(entry.path as NSString).deletingPathExtension.lowercased(), default: []].append(entry.path)
        }
        return groups.values.compactMap { files in
            let track = GitHubTrack(repo: repo, branch: branch, name: ((files[0] as NSString).lastPathComponent as NSString).deletingPathExtension, files: files.sorted())
            return track.hasScore || track.hasLyrics ? track : nil   // a recording alone has nothing to show
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Downloads a track's files into a folder named after the repository, keeping their paths, so importing that
    /// folder recognises them next time.
    static func download(_ track: GitHubTrack, token: String?) async throws -> URL {
        let root = URL.temporaryDirectory.appending(path: "GitHub", directoryHint: .isDirectory)
            .appending(path: "github-\(track.repo.owner)-\(track.repo.name)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: root)
        for path in track.files {
            let encoded = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
            let data = try await request("/repos/\(track.repo.owner)/\(track.repo.name)/contents/\(encoded)?ref=\(track.branch)", token: token, raw: true)
            let dest = root.appending(path: path)
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: dest)
        }
        return root
    }

    /// The first repository added in Tracks from GitHub, offered when a score is first connected.
    static var savedRepoName: String {
        let repos = (try? JSONDecoder().decode([GitHubRepo].self, from: Data((UserDefaults.standard.string(forKey: "githubRepos") ?? "[]").utf8))) ?? []
        return repos.first.map { "\($0.owner)/\($0.name)" } ?? ""
    }

    // MARK: Token, in the Keychain

    private static let account = "github-token"
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.tobyjones.PlayAlong", kSecAttrAccount as String: account] }

    static var token: String? {
        var q = query
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setToken(_ token: String?) {
        SecItemDelete(query as CFDictionary)
        guard let token, !token.isEmpty else { return }
        var q = query
        q[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}

/// Repositories you've added, their tracks searched together, and a button to add one to the library.
struct GitHubBrowser: View {
    let onOpen: (ScoreItem) -> Void
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("githubRepos") private var saved = "[]"
    @State private var newRepo = ""
    @State private var tracks: [GitHubTrack] = []
    @State private var loading = false
    @State private var adding: String?
    @State private var failure: String?
    @State private var term = ""
    @State private var token = GitHub.token ?? ""
    @State private var showToken = false

    private var repos: [GitHubRepo] { (try? JSONDecoder().decode([GitHubRepo].self, from: Data(saved.utf8))) ?? [] }
    private func store(_ list: [GitHubRepo]) { saved = (try? String(data: JSONEncoder().encode(list), encoding: .utf8)) ?? "[]" }

    private var shown: [GitHubTrack] {
        let q = term.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? tracks : tracks.filter { GitHub.matches($0.title + " " + $0.repo.title, q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(repos) { repo in
                        Label(repo.title + (repo.branch.map { " (\($0))" } ?? ""), systemImage: "shippingbox")
                    }
                    .onDelete { offsets in
                        var list = repos
                        list.remove(atOffsets: offsets)
                        store(list)
                        Task { await load() }
                    }
                    HStack {
                        TextField("owner/repository or a GitHub link", text: $newRepo)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit(addRepo)
                        Button("Add", action: addRepo).disabled(GitHubRepo(newRepo) == nil)
                    }
                } header: { Text("Repositories") } footer: {
                    Text("Scores, lyrics and recordings with the same name are added together. Swipe to remove a repository.")
                }

                Section {
                    if loading { HStack { ProgressView(); Text("Looking through the repositories…").foregroundStyle(.secondary) } }
                    else if repos.isEmpty { Text("Add a repository above to see its tracks.").foregroundStyle(.secondary) }
                    else if shown.isEmpty { Text(term.isEmpty ? String(localized: "No scores or lyrics found.") : String(localized: "Nothing matches “\(term)”.")).foregroundStyle(.secondary) }
                    ForEach(shown) { track in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(track.title).fontWeight(.medium)
                                HStack(spacing: 6) {
                                    if track.hasScore { Image(systemName: "music.note").accessibilityLabel("Score") }
                                    if track.hasLyrics { Image(systemName: "quote.bubble").accessibilityLabel("Lyrics") }
                                    if track.hasAudio { Image(systemName: "waveform").accessibilityLabel("Recording") }
                                    Text(track.repo.title)
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if adding == track.id { ProgressView() } else {
                                Button("Add") { Task { await add(track) } }.buttonStyle(.bordered).disabled(adding != nil)
                            }
                        }
                    }
                } header: { Text("Tracks") }

                Section {
                    DisclosureGroup("Access Token", isExpanded: $showToken) {
                        SecureField(String(localized: "Personal access token"), text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save Token") { GitHub.setToken(token.trimmingCharacters(in: .whitespaces)); Task { await load() } }
                    }
                } footer: {
                    Text("Needed for private repositories, for adding a lot of tracks, and for pushing a score's history to GitHub (then with read and write access to the repository's contents). It's kept in your Keychain.")
                }
            }
            .searchable(text: $term, prompt: String(localized: "Search tracks"))
            .navigationTitle("Tracks from GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .refreshable { await load() }
            .task { await load() }
            .alert("GitHub", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
                Button("OK") {}
            } message: { Text(failure ?? "") }
        }
        .pageSheet()
    }

    private func addRepo() {
        guard let repo = GitHubRepo(newRepo) else { return }
        var list = repos
        if !list.contains(repo) { list.append(repo) }
        store(list)
        newRepo = ""
        Task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        var all: [GitHubTrack] = []
        for repo in repos {
            do { all += try await GitHub.tracks(in: repo, token: GitHub.token) }
            catch { failure = "\(repo.title): \(error.localizedDescription)" }
        }
        tracks = all
    }

    private func add(_ track: GitHubTrack) async {
        adding = track.id
        defer { adding = nil }
        do {
            let folder = try await GitHub.download(track, token: GitHub.token)
            let result = await library.importFolder(folder, link: false)
            // The item made from this track, found by where it came from.
            let prefix = folder.lastPathComponent + "/" + (track.files.first { GitHub.scoreExtensions.contains(GitHub.ext($0)) } ?? track.files.first { UTType.lyricExtensions.contains(GitHub.ext($0)) } ?? "")
            if let item = library.items.first(where: { $0.source == prefix }) ?? (result.added > 0 ? library.items.max { $0.added < $1.added } : nil) {
                onOpen(item)
                dismiss()
            } else if !result.failed.isEmpty {
                failure = String(localized: "Couldn't read \(result.failed.joined(separator: ", ")).")
            } else {
                failure = result.summary
            }
        } catch {
            failure = error.localizedDescription
        }
    }
}
