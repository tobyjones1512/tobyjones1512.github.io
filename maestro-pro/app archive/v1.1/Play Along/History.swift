import Foundation
import SwiftUI

// Version history for a score, in the manner of Git: each saved version is a commit (a full MusicXML snapshot), a branch
// is a name for the newest commit of one line of edits, and a merge is a commit with two parents. Everything lives in the
// score's own folder: history.json plus history/<commit>.musicxml.

nonisolated struct Commit: Codable, Identifiable, Hashable {
    var id: String            // also the snapshot's file name
    var parents: [String]
    var message: String
    var date: Date
    var branch: String        // the branch it was made on
}

nonisolated struct History: Codable {
    var commits: [Commit] = []
    var branches: [String: String] = [:]   // name -> newest commit
    var head = "main"

    var tip: String? { branches[head] }
    func commit(_ id: String?) -> Commit? { commits.first { $0.id == id } }

    /// Every commit reachable from `id`, itself included.
    func ancestors(of id: String) -> Set<String> {
        var seen = Set<String>(), stack = [id]
        while let c = stack.popLast() { if seen.insert(c).inserted { stack += commit(c)?.parents ?? [] } }
        return seen
    }

    /// The nearest commit two lines of edits share, where they parted.
    func mergeBase(_ a: String, _ b: String) -> String? {
        let mine = ancestors(of: a)
        var queue = [b], seen = Set<String>()
        while !queue.isEmpty {
            let c = queue.removeFirst()
            if mine.contains(c) { return c }
            if seen.insert(c).inserted { queue += commit(c)?.parents ?? [] }
        }
        return nil
    }
}

/// Three-way merge, bar by bar. A bar changed on only one side takes that change; a bar changed differently on both is a
/// conflict, settled by `preferTheirs`. ponytail: bars are matched by number, so a bar inserted or deleted early on one
/// side shifts the rest and shows as conflicts; upgrade to a bar-aligning diff if that bites.
nonisolated enum ScoreMerge {
    private static func signature(_ m: PMeasure?) -> String? {
        guard var m else { return nil }
        m.start = 0   // where a bar starts follows from the bars before it
        return "\(m)"
    }

    static func merge(base: ParsedScore, ours: ParsedScore, theirs: ParsedScore, preferTheirs: Bool) -> (score: ParsedScore, conflicts: [Int]) {
        func bar(_ s: ParsedScore, _ i: Int) -> PMeasure? { s.measures.indices.contains(i) ? s.measures[i] : nil }
        var out = ours, conflicts: [Int] = []
        out.measures = []
        for i in 0..<max(base.measures.count, ours.measures.count, theirs.measures.count) {
            let b = bar(base, i), o = bar(ours, i), t = bar(theirs, i)
            let sb = signature(b), so = signature(o), st = signature(t)
            let pick: PMeasure?
            if so == st || st == sb { pick = o }
            else if so == sb { pick = t }
            else { conflicts.append(i + 1); pick = preferTheirs ? (t ?? o) : (o ?? t) }
            if let pick { out.measures.append(pick) }
        }
        if ours.title == base.title { out.title = theirs.title }
        if ours.composer == base.composer { out.composer = theirs.composer }
        if ours.tempo == base.tempo { out.tempo = theirs.tempo }
        ScoreEdit.renumber(&out)
        return (out, conflicts)
    }
}

extension Library {
    private func historyFile(_ item: ScoreItem) -> URL { folder(item).appending(path: "history.json") }
    func snapshotFolder(_ item: ScoreItem) -> URL { folder(item).appending(path: "history", directoryHint: .isDirectory) }
    func snapshotFile(_ item: ScoreItem, _ id: String) -> URL { snapshotFolder(item).appending(path: id + ".musicxml") }

    func history(_ item: ScoreItem) -> History? {
        try? JSONDecoder().decode(History.self, from: Data(contentsOf: historyFile(item)))
    }

    func saveHistory(_ h: History, for item: ScoreItem) {
        try? JSONEncoder().encode(h).write(to: historyFile(item), options: .atomic)
    }

    func snapshot(_ id: String, for item: ScoreItem) -> ParsedScore? {
        try? MusicXML.parse(Data(contentsOf: snapshotFile(item, id)))
    }

    /// Saves `score` as a new version on the current branch (with `merging` as a second parent for a merge). Does nothing,
    /// and returns the history as it was, when the score is the same as the branch's newest version.
    @discardableResult
    func recordVersion(_ score: ParsedScore, _ message: String, for item: ScoreItem, merging: [String] = []) -> History {
        var h = history(item) ?? History()
        let data = MusicXML.write(score)
        if merging.isEmpty, let tip = h.tip, (try? Data(contentsOf: snapshotFile(item, tip))) == data { return h }
        try? FileManager.default.createDirectory(at: snapshotFolder(item), withIntermediateDirectories: true)
        let id = UUID().uuidString
        guard (try? data.write(to: snapshotFile(item, id))) != nil else { return h }
        h.commits.append(Commit(id: id, parents: (h.tip.map { [$0] } ?? []) + merging, message: message, date: .now, branch: h.head))
        h.branches[h.head] = id
        saveHistory(h, for: item)
        return h
    }

    /// A version of the score as a new score of its own, with its own (empty) history.
    func spinOff(_ item: ScoreItem, score: ParsedScore, title: String) throws -> ScoreItem {
        var copy = try duplicate(item)
        try? FileManager.default.removeItem(at: historyFile(copy))
        try? FileManager.default.removeItem(at: snapshotFolder(copy))
        copy.title = title
        return try saveEdited(score, for: copy)
    }
}

// MARK: - History viewer

struct HistorySheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let item: ScoreItem
    /// The score as it is in the editor now.
    let score: ParsedScore
    /// Puts a version into the editor, and `persist` writes what the editor has to the score's file.
    let apply: (ParsedScore) -> Void
    let persist: () -> Void

    private struct Prompt: Identifiable {
        enum Kind { case version, branch, spinOff, repo }
        let kind: Kind
        var commit: String?
        var id: String { "\(kind)" }
        var title: String { switch kind { case .version: "Save Version"; case .branch: "New Branch"; case .spinOff: "Spin Off as New Score"; case .repo: "GitHub Repository" } }
        var field: String { switch kind { case .version: String(localized: "What changed"); case .branch: String(localized: "Branch name"); case .spinOff: String(localized: "Score name"); case .repo: "owner/repository" } }
    }

    @State private var h = History()
    @State private var prompt: Prompt?
    @State private var text = ""
    @State private var mergeSource: String?
    @State private var message: String?
    @State private var link: GitLink?
    @State private var syncing = false

    private var branchNames: [String] { h.branches.keys.sorted { $0 == "main" ? true : $1 == "main" ? false : $0 < $1 } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Branch", value: h.head)
                    Button("Save Version…", systemImage: "checkmark.circle") { ask(.version) }
                    Button("New Branch…", systemImage: "arrow.triangle.branch") { ask(.branch, commit: h.tip) }
                } footer: { Text("A version is a snapshot you can go back to. A branch is a separate line of edits, to try something without touching the main score.") }

                Section {
                    if let link {
                        LabeledContent("Repository", value: link.repo)
                        Button("Push to GitHub", systemImage: "arrow.up.circle") { sync(push: true) }.disabled(syncing)
                        Button("Pull from GitHub", systemImage: "arrow.down.circle") { sync(push: false) }.disabled(syncing)
                        Button("Change Repository…", systemImage: "shippingbox") { ask(.repo, suggest: link.repo) }
                    } else {
                        Button("Connect to a GitHub Repository…", systemImage: "shippingbox") { ask(.repo, suggest: GitHub.savedRepoName) }
                    }
                    if syncing { HStack { ProgressView(); Text("Talking to GitHub…").foregroundStyle(.secondary) } }
                } header: { Text("GitHub") } footer: {
                    Text("Every version and branch goes to the repository as a real Git commit and branch, as one MusicXML file. It needs a token with write access, added in Tracks from GitHub under Access Token.")
                }

                Section("Branches") {
                    ForEach(branchNames, id: \.self) { name in
                        let tip = h.commit(h.branches[name])
                        Menu {
                            if name != h.head {
                                Button("Switch to This Branch", systemImage: "arrow.right.circle") { switchTo(name) }
                                Button("Merge into \(h.head)…", systemImage: "arrow.triangle.merge") { mergeSource = name }
                            }
                            Button("Spin Off as New Score…", systemImage: "square.and.arrow.up.on.square") { ask(.spinOff, commit: h.branches[name], suggest: "\(item.title) (\(name))") }
                            if name != h.head {
                                Button("Delete Branch", systemImage: "trash", role: .destructive) { deleteBranch(name) }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(name).foregroundStyle(.primary).fontWeight(name == h.head ? .semibold : .regular)
                                    if let tip { Text(tip.message).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if name == h.head { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                    }
                }

                Section("History") {
                    ForEach(h.commits.reversed()) { c in
                        HStack(alignment: .top) {
                            Image(systemName: c.parents.count > 1 ? "arrow.triangle.merge" : "circle.fill")
                                .font(c.parents.count > 1 ? .body : .system(size: 8)).foregroundStyle(.secondary).frame(width: 20).padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.message)
                                HStack(spacing: 6) {
                                    Text(c.date.formatted(date: .abbreviated, time: .shortened))
                                    Text(c.branch).padding(.horizontal, 6).background(.quaternary, in: Capsule())
                                    ForEach(branchNames.filter { h.branches[$0] == c.id }, id: \.self) { Text($0 == h.head ? "\($0) (current)" : $0).foregroundStyle(Theme.accent) }
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button("Roll Back to This Version", systemImage: "arrow.uturn.backward") { rollBack(to: c) }.disabled(c.id == h.tip)
                                Button("Branch from Here…", systemImage: "arrow.triangle.branch") { ask(.branch, commit: c.id) }
                                Button("Spin Off as New Score…", systemImage: "square.and.arrow.up.on.square") { ask(.spinOff, commit: c.id, suggest: "\(item.title) (\(c.message))") }
                            } label: { Image(systemName: "ellipsis.circle").padding(8) }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { h = library.history(item) ?? library.recordVersion(score, "Starting point", for: item); link = library.gitLink(item) }
            .alert(prompt?.title ?? "", isPresented: Binding { prompt != nil } set: { if !$0 { prompt = nil } }) {
                TextField(prompt?.field ?? "", text: $text)
                Button("OK") { if let p = prompt { finish(p) } }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Merge “\(mergeSource ?? "")” into “\(h.head)”", isPresented: Binding { mergeSource != nil } set: { if !$0 { mergeSource = nil } }, titleVisibility: .visible) {
                Button("Merge, Keep Mine Where They Clash") { if let s = mergeSource { merge(s, preferTheirs: false) } }
                Button("Merge, Take Theirs Where They Clash") { if let s = mergeSource { merge(s, preferTheirs: true) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Bars changed on only one branch are brought together. Bars changed on both clash. You can roll the merge back from the history.") }
            .alert("History", isPresented: Binding { message != nil } set: { if !$0 { message = nil } }) { Button("OK") {} } message: { Text(message ?? "") }
        }
    }

    private func ask(_ kind: Prompt.Kind, commit: String? = nil, suggest: String = "") {
        text = suggest
        prompt = Prompt(kind: kind, commit: commit)
    }

    private func refresh() { h = library.history(item) ?? h }

    /// What is in the editor goes onto the current branch first, so moving anywhere never loses it.
    private func checkpoint() { h = library.recordVersion(score, "Work in progress", for: item) }

    private func show(_ s: ParsedScore) { apply(s); persist() }

    private func finish(_ p: Prompt) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch p.kind {
        case .version:
            h = library.recordVersion(score, name.isEmpty ? "Saved version" : name, for: item)
            persist()
        case .branch:
            guard !name.isEmpty, h.branches[name] == nil, let at = p.commit else { message = name.isEmpty ? String(localized: "Give the branch a name.") : String(localized: "There is already a branch called “\(name)”."); return }
            checkpoint()
            var next = h
            next.branches[name] = at
            next.head = name
            library.saveHistory(next, for: item)
            h = next
            if let s = library.snapshot(at, for: item) { show(s) }
        case .repo:
            guard let repo = GitHubRepo(name) else { message = String(localized: "That isn't a GitHub repository. Use owner/repository."); return }
            var next = library.gitLink(item) ?? GitLink(repo: "", path: library.gitPath(item))
            if next.repo != repo.title { next.shas = [:] }   // a different repository has none of these commits
            next.repo = repo.title
            library.saveGitLink(next, for: item)
            link = next
            sync(push: true)
        case .spinOff:
            guard !name.isEmpty, let at = p.commit, let s = library.snapshot(at, for: item) else { return }
            do { _ = try library.spinOff(item, score: s, title: name); message = "“\(name)” is now a score of its own in your library." }
            catch { message = error.localizedDescription }
        }
    }

    private func sync(push: Bool) {
        guard var l = link else { return }
        guard let token = GitHub.token, !token.isEmpty else { message = String(localized: "Add a GitHub token with write access first: Tracks from GitHub, then Access Token."); return }
        checkpoint()
        var next = h
        let library = library, item = item
        syncing = true
        Task {
            defer { syncing = false }
            do {
                let n: Int
                if push {
                    n = try await GitSync.push(next, link: &l, token: token) { library.snapshotData($0, for: item) }
                } else {
                    n = try await GitSync.pull(&next, link: &l, token: token) { library.storeSnapshot($1, id: $0, for: item) }
                }
                library.saveGitLink(l, for: item)
                link = l
                if !push {
                    let moved = next.tip != h.tip
                    library.saveHistory(next, for: item)
                    h = next
                    if moved, let tip = next.tip, let s = library.snapshot(tip, for: item) { show(s) }
                }
                message = push ? (n == 0 ? String(localized: "GitHub already has everything.") : (n == 1 ? String(localized: "Sent 1 version to \(l.repo).") : String(localized: "Sent \(n) versions to \(l.repo).")))
                               : (n == 0 ? String(localized: "Nothing new on GitHub.") : (n == 1 ? String(localized: "Brought in 1 version. Branches that went separate ways are named …-github, to merge.") : String(localized: "Brought in \(n) versions. Branches that went separate ways are named …-github, to merge.")))
            } catch { message = error.localizedDescription }
        }
    }

    private func switchTo(_ name: String) {
        checkpoint()
        var next = h
        next.head = name
        library.saveHistory(next, for: item)
        h = next
        if let tip = h.tip, let s = library.snapshot(tip, for: item) { show(s) }
    }

    private func rollBack(to c: Commit) {
        checkpoint()
        guard let s = library.snapshot(c.id, for: item) else { return }
        h = library.recordVersion(s, String(localized: "Rolled back to “\(c.message)”"), for: item)
        show(s)
    }

    private func deleteBranch(_ name: String) {
        var next = h
        next.branches[name] = nil
        library.saveHistory(next, for: item)
        h = next
    }

    private func merge(_ source: String, preferTheirs: Bool) {
        checkpoint()
        guard let ours = h.tip, let theirs = h.branches[source] else { return }
        guard let base = h.mergeBase(ours, theirs) else { message = String(localized: "These branches share no history, so they can’t be merged."); return }
        if base == theirs { message = "“\(h.head)” already has everything in “\(source)”."; return }
        guard let theirScore = library.snapshot(theirs, for: item) else { return }
        if base == ours {   // nothing new here: the branch just moves forward
            var next = h
            next.branches[h.head] = theirs
            library.saveHistory(next, for: item)
            h = next
            show(theirScore)
            message = "“\(h.head)” moved forward to “\(source)”."
            return
        }
        guard let baseScore = library.snapshot(base, for: item), let ourScore = library.snapshot(ours, for: item) else { return }
        let (merged, conflicts) = ScoreMerge.merge(base: baseScore, ours: ourScore, theirs: theirScore, preferTheirs: preferTheirs)
        h = library.recordVersion(merged, String(localized: "Merged “\(source)” into “\(h.head)”"), for: item, merging: [theirs])
        show(merged)
        message = conflicts.isEmpty ? String(localized: "Merged with no clashes.")
            : String(localized: "Merged. Bars changed on both branches: \(conflicts.map(String.init).joined(separator: ", ")). The \(preferTheirs ? "other" : "current") branch’s version of those was kept.")
    }
}
