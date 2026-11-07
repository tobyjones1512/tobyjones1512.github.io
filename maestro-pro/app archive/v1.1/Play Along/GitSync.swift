import Foundation

// A score's history kept in a GitHub repository: every version is a real Git commit (a merge keeps both parents) and every
// branch a real branch, written through GitHub's web API, since there is no git program on an iPad. The score is one
// MusicXML file in the repository. Push sends what GitHub doesn't have; Pull brings in what the history doesn't.
// ponytail: commit times are the time of the push, and only plain .musicxml files are read back. Branch names with spaces
// become dashes on GitHub.

nonisolated struct GitLink: Codable {
    var repo: String                  // "owner/name"
    var path: String                  // the score's file in the repository
    var shas: [String: String] = [:]  // version id -> Git commit
}

nonisolated enum GitSync {
    private static func object(_ path: String, _ token: String, _ method: String = "GET", _ body: [String: Any]? = nil) async throws -> [String: Any] {
        (try JSONSerialization.jsonObject(with: await GitHub.request(path, token: token, method: method, body: body)) as? [String: Any]) ?? [:]
    }

    private static func heads(_ repo: String, _ token: String) async throws -> [String: String] {
        do {
            let list = try JSONSerialization.jsonObject(with: await GitHub.request("/repos/\(repo)/git/matching-refs/heads/", token: token)) as? [[String: Any]] ?? []
            return Dictionary(list.compactMap { r in
                guard let ref = r["ref"] as? String, let sha = (r["object"] as? [String: Any])?["sha"] as? String else { return nil }
                return (String(ref.dropFirst("refs/heads/".count)), sha)
            }, uniquingKeysWith: { a, _ in a })
        } catch let e as GitHub.Failure where e.status == 409 { return [:] }
    }

    private static func ref(_ name: String) -> String { name.replacingOccurrences(of: " ", with: "-") }

    /// Sends every version GitHub lacks, then moves each branch there. Returns how many versions went.
    static func push(_ h: History, link: inout GitLink, token: String, snapshot: (String) -> Data?) async throws -> Int {
        Analytics.track("github_push")
        let base = "/repos/\(link.repo)"
        let main = try await object(base, token)["default_branch"] as? String ?? "main"
        var remote = try await heads(link.repo, token)
        if remote.isEmpty {   // an empty repository takes no commits until it holds a file
            _ = try await GitHub.request("\(base)/contents/README.md", token: token, method: "PUT",
                                         body: ["message": "Initial commit", "content": Data("Scores kept with Maestro Pro.\n".utf8).base64EncodedString()])
            remote = try await heads(link.repo, token)
        }
        var sent = 0
        for c in h.commits where link.shas[c.id] == nil {
            guard let data = snapshot(c.id) else { continue }
            let blob = try await object("\(base)/git/blobs", token, "POST", ["content": data.base64EncodedString(), "encoding": "base64"])
            // The first version attaches to the repository's main branch, so earlier files there are kept.
            let parents = c.parents.isEmpty ? [remote[main]].compactMap { $0 } : c.parents.compactMap { link.shas[$0] }
            var tree: [String: Any] = ["tree": [["path": link.path, "mode": "100644", "type": "blob", "sha": blob["sha"] as Any]]]
            if let p = parents.first, let t = (try await object("\(base)/git/commits/\(p)", token)["tree"] as? [String: Any])?["sha"] { tree["base_tree"] = t }
            let treeSha = try await object("\(base)/git/trees", token, "POST", tree)["sha"] as Any
            let made = try await object("\(base)/git/commits", token, "POST", ["message": c.message, "tree": treeSha, "parents": parents])
            link.shas[c.id] = made["sha"] as? String
            sent += 1
        }
        for (name, id) in h.branches.sorted(by: { $0.key < $1.key }) {
            guard let sha = link.shas[id], remote[ref(name)] != sha else { continue }
            do {
                if remote[ref(name)] != nil { _ = try await object("\(base)/git/refs/heads/\(ref(name))", token, "PATCH", ["sha": sha, "force": false]) }
                else { _ = try await object("\(base)/git/refs", token, "POST", ["ref": "refs/heads/\(ref(name))", "sha": sha]) }
            } catch let e as GitHub.Failure where e.status == 422 {
                throw GitHub.Failure("“\(name)” on GitHub has versions this history doesn't. Pull first, merge, then push again.")
            }
        }
        return sent
    }

    /// Brings in versions made elsewhere (another device, or in the GitHub page itself). A branch that has moved on is moved
    /// forward here; one that has gone separate ways arrives as “name-github” to merge. Returns how many versions came.
    static func pull(_ h: inout History, link: inout GitLink, token: String, store: (String, Data) -> Void) async throws -> Int {
        Analytics.track("github_pull")
        let base = "/repos/\(link.repo)"
        let remote = try await heads(link.repo, token)
        var known = Dictionary(link.shas.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
        func parents(_ c: [String: Any]) -> [String] { (c["parents"] as? [[String: Any]] ?? []).compactMap { $0["sha"] as? String } }

        var pending: [(sha: String, commit: [String: Any])] = [], seen = Set<String>(), stack = Array(remote.values)
        while let sha = stack.popLast(), seen.count < 300 {
            guard known[sha] == nil, seen.insert(sha).inserted else { continue }
            let c = try await object("\(base)/git/commits/\(sha)", token)
            pending.append((sha, c))
            stack += parents(c)
        }
        var brought = 0
        while let i = pending.firstIndex(where: { p in parents(p.commit).allSatisfy { known[$0] != nil || !seen.contains($0) } }) {
            let (sha, c) = pending.remove(at: i)
            let ids = parents(c).compactMap { known[$0] }
            let treeSha = (c["tree"] as? [String: Any])?["sha"] as? String ?? ""
            let entries = try await object("\(base)/git/trees/\(treeSha)?recursive=1", token)["tree"] as? [[String: Any]] ?? []
            let file = entries.first { $0["path"] as? String == link.path } ?? entries.first { ($0["path"] as? String)?.hasSuffix(".musicxml") == true }
            guard let blob = file?["sha"] as? String else { known[sha] = ids.first; continue }   // a commit that doesn't touch the score
            let text = try await object("\(base)/git/blobs/\(blob)", token)["content"] as? String ?? ""
            guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { continue }
            let id = UUID().uuidString
            store(id, data)
            let when = ((c["author"] as? [String: Any])?["date"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? .now
            h.commits.append(Commit(id: id, parents: ids, message: (c["message"] as? String ?? "From GitHub").components(separatedBy: "\n")[0], date: when, branch: "GitHub"))
            link.shas[id] = sha
            known[sha] = id
            brought += 1
        }
        for (name, sha) in remote {
            guard let id = known[sha] else { continue }
            let local = name
            if let mine = h.branches[local] {
                if mine == id || h.ancestors(of: mine).contains(id) { continue }          // up to date, or ahead
                if h.ancestors(of: id).contains(mine) { h.branches[local] = id }           // GitHub is ahead: move forward
                else { h.branches[local + "-github"] = id }                                // parted ways: merge it
            } else { h.branches[local] = id }
        }
        return brought
    }
}

extension Library {
    private func gitFile(_ item: ScoreItem) -> URL { folder(item).appending(path: "github.json") }

    func gitLink(_ item: ScoreItem) -> GitLink? { try? JSONDecoder().decode(GitLink.self, from: Data(contentsOf: gitFile(item))) }
    func saveGitLink(_ link: GitLink, for item: ScoreItem) { try? JSONEncoder().encode(link).write(to: gitFile(item), options: .atomic) }

    func snapshotData(_ id: String, for item: ScoreItem) -> Data? { try? Data(contentsOf: snapshotFile(item, id)) }
    func storeSnapshot(_ data: Data, id: String, for item: ScoreItem) {
        try? FileManager.default.createDirectory(at: snapshotFolder(item), withIntermediateDirectories: true)
        try? data.write(to: snapshotFile(item, id))
    }

    /// The name of the score's file in a repository.
    func gitPath(_ item: ScoreItem) -> String {
        let name = item.title.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|")).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? "Score" : name) + ".musicxml"
    }
}
