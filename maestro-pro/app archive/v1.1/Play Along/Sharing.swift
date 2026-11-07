import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let playAlongScore = UTType(exportedAs: "com.tobyjones.PlayAlong.score", conformingTo: .data)
}

// Sending a score to another Maestro Pro user: one .maestropro file holding the sheet music, the backing
// track and the settings. Layout: "PLAYALONG1", a 4-byte header length, the JSON header (the item and the
// names and sizes of its files), then the files back to back.

extension Library {
    private static let magic = Data("PLAYALONG1".utf8)

    private struct Header: Codable {
        var item: ScoreItem
        var files: [File]
        struct File: Codable { var name: String; var size: Int }
    }

    /// Packs a score and its backing track into one file in the temporary folder.
    func makeShareFile(_ item: ScoreItem) throws -> URL {
        Analytics.track("score_shared")
        var item = item
        item.transpose = nil; item.shiftTrack = nil   // the recipient chooses their own key
        item.generated = nil                          // a shared scale or arpeggio shows in their main list
        let edits = FileManager.default.fileExists(atPath: trackEditURL(item).path) ? ["trackedit.json"] : []
        let names = [item.file] + (item.track.map { [$0] } ?? []) + (item.extraTracks ?? []).map(\.file) + (item.lyrics.map { [$0] } ?? []) + edits
        var body = Data(), files: [Header.File] = []
        for name in names {
            let data = try Data(contentsOf: folder(item).appending(path: name))
            files.append(.init(name: name, size: data.count))
            body.append(data)
        }
        let header = try JSONEncoder().encode(Header(item: item, files: files))
        var out = Self.magic
        withUnsafeBytes(of: UInt32(header.count).littleEndian) { out.append(contentsOf: $0) }
        out.append(header)
        out.append(body)
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: item.title.replacingOccurrences(of: "/", with: "-") + ".maestropro")
        try out.write(to: url)
        return url
    }

    /// Adds a received .maestropro (or older .playalong) file to the library as a new score.
    @discardableResult
    func importShared(from url: URL) throws -> ScoreItem {
        try requireRoom()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let bad = ScoreError.unsupported(String(localized: "This isn’t a Maestro Pro score, or it’s damaged."))
        guard data.starts(with: Self.magic), data.count > Self.magic.count + 4 else { throw bad }
        let hl = Self.magic.count
        let length = Int(data[hl..<hl + 4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
        guard hl + 4 + length <= data.count, let header = try? JSONDecoder().decode(Header.self, from: data[(hl + 4)..<(hl + 4 + length)]) else { throw bad }
        var item = header.item
        // Only the files the item names, as plain file names.
        let allowed = Set([item.file, "trackedit.json"] + (item.track.map { [$0] } ?? []) + (item.extraTracks ?? []).map(\.file) + (item.lyrics.map { [$0] } ?? []))
        guard header.files.allSatisfy({ allowed.contains($0.name) && !$0.name.contains("/") && $0.size >= 0 }) else { throw bad }
        item.id = UUID()
        item.added = Date()
        try FileManager.default.createDirectory(at: folder(item), withIntermediateDirectories: true)
        do {
            var at = hl + 4 + length
            for f in header.files {
                guard at + f.size <= data.count else { throw bad }
                try data[at..<at + f.size].write(to: folder(item).appending(path: f.name))
                at += f.size
            }
            if item.isCDG {
                _ = try CDGPlayer(data: Data(contentsOf: scoreURL(item)))
            } else if item.isLyricsOnly {
                guard !(try Lyrics.document(from: scoreURL(item), duration: nil)).isEmpty else { throw bad }
            } else {
                _ = try ScoreLoader.load(scoreURL(item), beatsPerBar: 4, analyse: false)
            }
        } catch {
            try? FileManager.default.removeItem(at: folder(item))
            throw error
        }
        save(item)
        return item
    }
}

/// Asks first, then packs the score for sharing.
struct ShareScoreView: View {
    let item: ScoreItem
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.2.wave.2").font(.system(size: 44)).foregroundStyle(Theme.accent)
            Text("Share with Another Player").font(.title2.bold())
            Label {
                Text("Sheet music and recordings are usually protected by copyright. Only share music you wrote, own the rights to, or have permission to pass on. Sharing copyrighted material without permission may be illegal, and you are responsible for what you send.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            .font(.callout)
            if let file {
                Text("The file holds the sheet music\(item.track != nil ? " and the backing track" : ""). The other person opens it in Maestro Pro.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                ShareLink(item: file) { Label("Share…", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderedProminent)
            } else if let failure {
                Text(failure).foregroundStyle(.secondary)
            } else {
                Button("I Have Permission to Share This") {
                    do { file = try library.makeShareFile(item) } catch { failure = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent)
            }
            Button(file == nil ? "Cancel" : "Done") { dismiss() }
        }
        .padding(30)
        .frame(minWidth: 340, minHeight: 320)
    }
}

// MARK: - Copyright warning

extension View {
    /// Before anything leaves the app (sharing, exporting, printing), a few pages on copyright and piracy that
    /// have to be read through and agreed to. Set `pending` to the action to run once they have been.
    func copyrightGate(_ pending: Binding<(() -> Void)?>) -> some View {
        modifier(CopyrightGate(pending: pending))
    }
}

private struct CopyrightGate: ViewModifier {
    @Binding var pending: (() -> Void)?
    @State private var showing: (() -> Void)?
    @State private var agreed: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onChange(of: pending != nil) { _, on in if on { showing = pending; pending = nil } }
            .sheet(isPresented: Binding { showing != nil } set: { if !$0 { showing = nil } }, onDismiss: {
                // Run it once the warning has gone, so a share sheet it opens has the screen to itself.
                agreed?(); agreed = nil
            }) {
                CopyrightWarning { agreed = showing; showing = nil }
            }
    }
}

struct CopyrightWarning: View {
    let onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var confirmed = false

    private let pages: [(symbol: String, title: String, text: String)] = [
        ("music.note.list", String(localized: "Music Belongs to Someone"),
         String(localized: "Sheet music, recordings, backing tracks and lyrics are almost always protected by copyright. The composer, lyricist, arranger, performer or publisher owns them, even when they are easy to find online.")),
        ("exclamationmark.shield", String(localized: "Piracy Is Against the Law"),
         String(localized: "Copying or sharing protected music without permission is piracy. Copyright law protects it in almost every country, and the rules and penalties depend on where you live. Infringement can lead to claims for damages and, in serious cases, fines or prison.")),
        ("checkmark.seal", String(localized: "What You Can Usually Share"),
         String(localized: "Music you wrote or recorded yourself, music in the public domain, and music whose licence allows sharing (such as some Creative Commons works). Anything else needs the permission of whoever owns it. Buying a copy for yourself does not give you the right to pass it on.")),
        ("person.badge.shield.checkmark", String(localized: "It’s Your Responsibility"),
         String(localized: "Maestro Pro can’t tell who owns what you share. By carrying on, you confirm that you have the right to share or export this music, and that you, not the app, are responsible for what you do with it.")),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in
                        VStack(spacing: 18) {
                            Image(systemName: pages[i].symbol).font(.system(size: 56)).foregroundStyle(Theme.accent)
                            Text(pages[i].title).font(.title2.bold()).multilineTextAlignment(.center)
                            Text(pages[i].text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            if i == pages.count - 1 {
                                Toggle("I own this music or have permission to share it", isOn: $confirmed)
                                    .padding(.top, 8)
                            }
                        }
                        .padding(32)
                        .frame(maxWidth: 520)
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                Button {
                    if page < pages.count - 1 { withAnimation { page += 1 } } else { onAgree() }
                } label: {
                    Text(page < pages.count - 1 ? "Next" : String(localized: "Agree and Continue")).frame(maxWidth: 320)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(page == pages.count - 1 && !confirmed)
                .padding(.bottom, 28)
            }
            .navigationTitle("Before You Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .tint(Theme.accent)
        .interactiveDismissDisabled()
        .frame(minWidth: 420, minHeight: 520)
    }
}
