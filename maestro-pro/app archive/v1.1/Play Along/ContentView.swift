import SwiftUI
import UniformTypeIdentifiers

private struct CloseScoreKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
private struct StandaloneWindowKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Leaves the open score and shows the library again (for narrow screens, where the sidebar is out of the way).
    var closeScore: () -> Void {
        get { self[CloseScoreKey.self] }
        set { self[CloseScoreKey.self] = newValue }
    }
    /// True when the score is displayed in its own standalone window with no sidebar.
    var isStandaloneWindow: Bool {
        get { self[StandaloneWindowKey.self] }
        set { self[StandaloneWindowKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(Library.self) private var library
    @State private var selection: Pick?
    @State private var columns = NavigationSplitViewVisibility.all
    @State private var error: String?
    @State private var backingForLyrics: URL?   // a recording waiting for its words to be found online
    @State private var dropTargeted = false
    @State private var scanning = false
    @AppStorage("appearance") private var appearance = "dark"
    @State private var folderResult: Library.FolderResult?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var duoCompact = false   // the opened Duo is narrow enough for the compact layout

    var body: some View {
        // Chosen by the room there is, not the device, so folding the Duo open swaps layouts and keeps `selection`.
        GeometryReader { geo in
            Group {
            if PhoneViewer.forceFull { full.environment(\.horizontalSizeClass, duoCompact ? .compact : sizeClass) }
            else if PhoneViewer.isFrontScreen(geo.size) { OpenPrompt() }
            else if PhoneViewer.applies(to: geo.size) { PhoneViewer(selection: $selection) }
            // The opened Duo is phone-idiom but wide enough for the whole app; the existing compact layout keeps it from being squeezed.
            else { full.environment(\.horizontalSizeClass, duoCompact ? .compact : sizeClass) }
            }
            .onChange(of: geo.size.width, initial: true) { _, w in duoCompact = PhoneViewer.isDuo && w < PhoneViewer.compactBelow && geo.size.height >= w }   // on its side the opened Duo gets the library beside the home screen
        }

        .task { await library.enableCloud() }
        #if DEBUG
        .task { await shotSeed() }   // screenshots: `-seed` fills the library, `-open <words>` opens a score, `-paywall` and `-tuner` also work in the phone layouts
        #endif
        .task { await library.fillLengths() }
        .task { if Pref.bool("checkFolders", true), !library.linkedFolders.isEmpty { _ = await library.rescanLinked() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await library.reloadInBackground() } } }
    }

    #if DEBUG
    private func shotSeed() async {
        let args = CommandLine.arguments
        try? await Task.sleep(for: .seconds(1.5))
        if args.contains("-seed") {
            Store.shared.debugTier = .professional
            for n in ["Chopin_-_Nocturne_Op_9_No_2_E_Flat_Major", "Clair_de_Lune__Debussy", "Fur_Elise", "Canon_in_D", "Sonate_No._14_Moonlight_1st_Movement", "Bach_Toccata_and_Fugue_in_D_Minor_Piano_solo", "Waltz_in_A_MinorChopin", "Swan_Lake"] {
                if let u = Bundle.main.url(forResource: n, withExtension: "mxl") { _ = try? library.importScore(from: u) }
            }
        }
        if let i = args.firstIndex(of: "-open"), i + 1 < args.count, let it = library.items.first(where: { $0.title.localizedCaseInsensitiveContains(args[i + 1]) }) { selection = Pick(score: it.id) }
        if PhoneViewer.applies(to: UIScreen.main.bounds.size) || PhoneViewer.isFrontScreen(UIScreen.main.bounds.size) {
            if args.contains("-paywall") { Store.shared.present(args.contains("-pro") ? .professional : .performer, args.contains("-pro") ? "The score editor" : "The tuner") }
            if args.contains("-tuner") { library.showTuner = true }
        }
    }
    #endif

    @ViewBuilder private var full: some View {
        @Bindable var library = library
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
                // The system toggle hops between columns and vanishes when the sidebar overlays; ours below stays put.
                .toolbar(removing: .sidebarToggle)
        } detail: {
          Group {
            if let item = library.items.first(where: { $0.id == selection?.score }) {
                Group {
                    if item.isLyricsOnly { LyricsScreen(item: item, columns: $columns) } else { ScoreScreen(item: item, columns: $columns) }
                }
                    // Pinned, so the bar's icons don't flip between light and dark as pale music scrolls under them.
                    .toolbarColorScheme(appearance == "light" ? .light : appearance == "system" ? nil : .dark, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .id(item.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                Welcome(hasScores: library.items.contains { $0.generated != true }, openSample: openSample)
                    .transition(.opacity)
                    .toolbar {
                        if columns == .detailOnly {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { library.showSettings = true } label: { Label("Settings", systemImage: "gearshape").foregroundStyle(Theme.accent) }.tint(Theme.accent)
                            }
                        }
                    }
            }
          }
          .toolbar {
              // On a narrow screen the split view is a stack and its back button is the way to the library.
              if sizeClass != .compact, !duoCompact {
                  ToolbarItem(placement: .topBarLeading) {
                      Button { withAnimation(.smooth) { columns = columns == .detailOnly ? .all : .detailOnly } } label: {
                          Label(columns == .detailOnly ? "Show Library" : "Hide Library", systemImage: "sidebar.leading")
                      }
                      .tint(BarStyle.tint)
                      .keyboardShortcut("s", modifiers: [.command, .control])
                      .help(columns == .detailOnly ? "Show Library (⌃⌘S)" : "Hide Library (⌃⌘S)")
                  }
              }
          }
        }
        .animation(.smooth(duration: 0.45), value: selection?.score)
        .environment(\.closeScore, { withAnimation(.smooth) { selection = nil; columns = .all } })
        #if targetEnvironment(macCatalyst)
        .onAppear {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.sizeRestrictions?.minimumSize = CGSize(width: 960, height: 700)
            }
        }
        #endif
        #if DEBUG
        .onAppear { // screenshot hooks
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "-open"), i + 1 < args.count { selection = library.items.first { $0.title == args[i + 1] }.map { Pick(score: $0.id) } }
            else if args.contains("-demo") { openSample() }
            if args.contains("-scaletest"), let item = try? library.scale(ScaleKind.all[6], in: ScaleKey.minor[3]) { selection = Pick(score: item.id) }   // E♭ blues
            if args.contains("-freescores") { library.showFreeScores = true }
            if let i = args.firstIndex(of: "-edit"), i + 1 < args.count, let item = library.items.first(where: { $0.title == args[i + 1] }) { selection = Pick(score: item.id); library.editRequest = item.id }
            if args.contains("-newblank"), let item = try? library.createBlank(title: "Blank Test", beats: 3, beatType: 4, fifths: 1, bars: 8, staves: .piano, tempo: 90) { selection = Pick(score: item.id); library.editRequest = item.id }
            if args.contains("-newblanksheet") { library.showBlank = true }
            if args.contains("-settings") { library.showSettings = true }
            if args.contains("-tuner") { library.showTuner = true; if args.contains("-tunerclose") { Task { try? await Task.sleep(for: .seconds(12)); library.showTuner = false } } }
            if args.contains("-applemusic") { library.showAppleMusic = true }
            if args.contains("-paywall") { Store.shared.present(args.contains("-pro") ? .professional : .performer, args.contains("-pro") ? "The score editor" : "The tuner") }
            if let i = args.firstIndex(of: "-attachtrack"), i + 2 < args.count, let it = library.items.first(where: { $0.title == args[i + 2] }) { _ = try? library.importTrack(from: URL(fileURLWithPath: args[i + 1]), for: it) }
            if args.contains("-playlisttest"), library.playlists.isEmpty { library.newPlaylist("Practice", adding: library.items.first) }
            if let i = args.firstIndex(of: "-lyricsbacking"), i + 2 < args.count {
                let r = Result { try library.importLyricsWithBacking([URL(fileURLWithPath: args[i + 1]), URL(fileURLWithPath: args[i + 2])]) }
                try? "\((try? r.get())?.track ?? "no track") \((try? r.get())?.title ?? "failed")".write(toFile: "/tmp/lyricsbacking.txt", atomically: true, encoding: .utf8)
            }
            if let i = args.firstIndex(of: "-preset"), i + 1 < args.count, let p = StylePreset.all.first(where: { $0.name == args[i + 1] }) { p.apply() }
            if let i = args.firstIndex(of: "-importfolder"), i + 1 < args.count {
                Task { let r = await library.importFolder(URL(fileURLWithPath: args[i + 1])); try? r.summary.write(toFile: "/tmp/folder-result.txt", atomically: true, encoding: .utf8) }
            }
            if let i = args.firstIndex(of: "-lyricsfile"), i + 1 < args.count, let item = try? library.importScore(from: URL(fileURLWithPath: args[i + 1])) { selection = Pick(score: item.id) }
            if args.contains("-importer") { library.showImporter = true }
            if args.contains("-duplicatetest"), let first = library.items.first(where: { $0.track != nil }) ?? library.items.first, let copy = try? library.duplicate(first) {
                let files = (try? FileManager.default.contentsOfDirectory(atPath: library.folder(copy).path).sorted()) ?? []
                try? "\(first.title) -> \(copy.title); files \(files); items \(library.items.count)".write(toFile: "/tmp/duplicate-test.txt", atomically: true, encoding: .utf8)
            }
            if args.contains("-help") { library.showHelp = true }
            if args.contains("-loopbacktest") { Task { await loopbackTest() } }
            if args.contains("-sharetest"), let item = library.items.first ?? (try? library.importSample()) {   // round-trip a share file
                let file = try? library.makeShareFile(item)
                if let file { try? FileManager.default.removeItem(atPath: "/tmp/test.playalong"); try? FileManager.default.copyItem(at: file, to: URL(fileURLWithPath: "/tmp/test.playalong")) }
                let r = Result { try library.importShared(from: file!) }
                try? "\(r)".write(toFile: "/tmp/play-along-share.txt", atomically: true, encoding: .utf8)
            }
        }
        #endif
        #if !targetEnvironment(macCatalyst)
        .fullScreenCover(isPresented: $library.showScanner) {
            ZStack {
                DocumentScanner(finished: { images in
                    // Tidying the photos takes a few seconds: keep a progress screen up over the camera until it's done.
                    scanning = true
                    let name = "Scanned Music \(Date.now.formatted(date: .abbreviated, time: .shortened))".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
                    Task {
                        let made = await Task.detached(priority: .userInitiated) { Result { try ScanPDF.make(from: images, named: name) } }.value
                        switch made {
                        case .success(let url): importScore(url)
                        case .failure(let e): self.error = e.localizedDescription
                        }
                        library.showScanner = false
                        scanning = false
                    }
                }, cancelled: { library.showScanner = false })
                if scanning {
                    ZStack {
                        Theme.stage
                        VStack(spacing: 16) {
                            ProgressView().controlSize(.large)
                            Text("Reading your scan…").font(.headline)
                            Text("Straightening the page and getting the notes ready.").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(.smooth, value: scanning)
            .ignoresSafeArea()
        }
        #endif
        .sheet(isPresented: $library.showHelp) { HelpView().environment(library) }
        .sheet(isPresented: $library.showScales) {
            ScaleBrowser { item in withAnimation(.smooth) { selection = Pick(score: item.id) } }.environment(library)
        }
        .background(Color.clear.fileImporter(isPresented: $library.showImporter, allowedContentTypes: UTType.scoreTypes + [.data], allowsMultipleSelection: true) { result in
            for url in (try? result.get()) ?? [] { importScore(url) }
        })
        .background(Color.clear.fileImporter(isPresented: $library.showLyricsPicker, allowedContentTypes: [.lrc, .plainText, .kar, .midi, .cdg, .audio, .data], allowsMultipleSelection: true) { result in
            do {
                let urls = try result.get()
                if urls.contains(where: { UTType.lyricExtensions.contains($0.pathExtension.lowercased()) }) {
                    let item = try library.importLyricsWithBacking(urls)
                    withAnimation(.smooth) { selection = Pick(score: item.id) }
                    Task { await library.matchSingers(item) }
                } else if let audio = urls.first {
                    // Just the recording: keep a copy (the picker's access ends here), then find its words online.
                    let scoped = audio.startAccessingSecurityScopedResource()
                    defer { if scoped { audio.stopAccessingSecurityScopedResource() } }
                    let copy = URL.temporaryDirectory.appending(path: audio.lastPathComponent)
                    try? FileManager.default.removeItem(at: copy)
                    try FileManager.default.copyItem(at: audio, to: copy)
                    backingForLyrics = copy
                }
            } catch { self.error = error.localizedDescription }
        })
        .sheet(isPresented: Binding { backingForLyrics != nil } set: { if !$0 { backingForLyrics = nil } }) {
            if let backing = backingForLyrics {
                let title = backing.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
                OnlineLyricsSheet(initialTerm: title, save: { lrc in
                    let item = try library.importLyrics(lrc, backing: backing, title: title)
                    withAnimation(.smooth) { selection = Pick(score: item.id) }
                    Task { await library.matchSingers(item) }
                }) {}
                .environment(library)
            }
        }
        .background(Color.clear.fileImporter(isPresented: $library.showFolderPicker, allowedContentTypes: [.folder]) { result in
            guard let url = try? result.get() else { return }
            Task { folderResult = await library.importFolder(url) }
        })
        .alert("Folder Imported", isPresented: Binding { folderResult != nil } set: { if !$0 { folderResult = nil } }, presenting: folderResult) { _ in
            Button("OK") {}
        } message: { Text($0.summary) }
        .overlay(alignment: .bottom) {
            if let progress = library.importing {
                HStack(spacing: 10) {
                    ProgressView(value: Double(progress.done), total: Double(max(1, progress.total)))
                        .frame(width: 140)
                    Text("Importing \(progress.done + 1) of \(progress.total)…").font(.callout).monospacedDigit()
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.regularMaterial, in: .capsule)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: library.importing?.done)
        .sheet(isPresented: $library.showSettings) { AppSettingsView().pageSheet().environment(library) }
        .sheet(isPresented: $library.showTuner) { TunerView().pageSheet().environment(library) }
        .sheet(isPresented: $library.showAppleMusic) { AppleMusicLyricsSheet().environment(library) }
        .sheet(isPresented: $library.showBlank) {
            NewScoreSheet { item in
                // Straight into the editor, where the notes get written.
                selection = Pick(score: item.id)
                library.editRequest = item.id
            }
            .environment(library)
        }
        .sheet(isPresented: $library.showGitHub) {
            GitHubBrowser { item in withAnimation(.smooth) { selection = Pick(score: item.id) } }.environment(library)
        }
        .sheet(isPresented: $library.showFreeScores) {
            FreeScoreBrowser { item in withAnimation(.smooth) { selection = Pick(score: item.id) } }.environment(library)
        }
        .onChange(of: library.openRequest) { _, id in
            if let id { selection = Pick(score: id); library.openRequest = nil }
        }
        .onOpenURL { url in
            #if DEBUG
            try? "opened \(url)".write(toFile: "/tmp/openurl.txt", atomically: true, encoding: .utf8)
            #endif
            importScore(url)
        }
        .onDrop(of: UTType.scoreTypes, isTargeted: $dropTargeted, perform: drop)
        .overlay { if dropTargeted { DropHalo().transition(.opacity) } }
        .animation(.easeOut(duration: 0.2), value: dropTargeted)
        .alert("Couldn’t Import Score", isPresented: .constant(error != nil), presenting: error) { _ in
            Button("OK") { error = nil }
        } message: { Text($0) }
    }

    #if DEBUG
    /// Two transports linked in one process, each with its own sheet music (one a tone higher), tempo and
    /// start; the first plays and both should stay on the same bar.
    private func loopbackTest() async {
        guard let item = library.items.first ?? (try? library.importSample()) else { return }
        let url = library.scoreURL(item)
        func make(transpose: Int, tempo: Double) async -> (Transport, Together) {
            let t = Transport(), g = Together()
            let loaded = try? ScoreLoader.load(url, beatsPerBar: 4, transpose: transpose)
            t.timeline = loaded!.timeline(beatsPerBar: 4)
            t.tempo = tempo
            t.countInEnabled = false
            g.transport = t; t.together = g
            return (t, g)
        }
        let (ta, ga) = await make(transpose: 0, tempo: 120), (tb, gb) = await make(transpose: 2, tempo: 80)
        ga.loopback = gb; gb.loopback = ga
        ga.markConnectedForTest(); gb.markConnectedForTest()
        ta.seek(to: 10)   // while stopped: both should move to bar 3.5
        try? await Task.sleep(for: .milliseconds(100))
        var report = "after seek: A bar \(ta.barPosition(ta.beat)) B bar \(tb.barPosition(tb.beat))\n"
        ta.play()
        var worst = 0.0, samples = 0
        for _ in 0..<160 {
            try? await Task.sleep(for: .milliseconds(50))
            guard ta.isPlaying, tb.isPlaying else { continue }
            let d = abs(ta.barPosition(ta.beat) - tb.barPosition(tb.beat)) * 4 * 60 / ta.tempo   // seconds
            if CACurrentMediaTime() > 0 { worst = max(worst, d); samples += 1 }
        }
        report += "playing: tempo A \(ta.tempo) B \(tb.tempo), \(samples) samples, worst gap \(Int(worst * 1000)) ms\n"
        tb.pause()   // B pauses: A should stop too
        try? await Task.sleep(for: .milliseconds(200))
        report += "after B pause: A playing \(ta.isPlaying) bar \(ta.barPosition(ta.beat)); B bar \(tb.barPosition(tb.beat))\n"
        try? report.write(toFile: "/tmp/play-along-loopback.txt", atomically: true, encoding: .utf8)
    }
    #endif

    private func importScore(_ url: URL) {
        do {
            // A file from another Maestro Pro user holds the score and its track; anything else is a score file.
            let item = ["maestropro", "playalong"].contains(url.pathExtension.lowercased()) ? try library.importShared(from: url) : try library.importScore(from: url)
            withAnimation(.smooth) { selection = Pick(score: item.id) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openSample() {
        if let existing = library.items.first(where: { $0.title == "Ode to Joy" }) { selection = Pick(score: existing.id); return }
        if let item = try? library.importSample() { withAnimation(.smooth) { selection = Pick(score: item.id) } }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        for p in providers {
            guard let type = UTType.scoreTypes.first(where: { p.hasItemConformingToTypeIdentifier($0.identifier) }) else { continue }
            _ = p.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                guard let url else { return }
                // The provided file disappears when this handler returns; keep a copy for the main actor.
                let copy = URL.temporaryDirectory.appending(path: UUID().uuidString + "-" + url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: copy)
                Task { @MainActor in importScore(copy); try? FileManager.default.removeItem(at: copy) }
            }
        }
        return true
    }
}

// MARK: - Sidebar

/// A sidebar row: the same score can sit in the library and in several playlists.
struct Pick: Hashable {
    var score: UUID
    var playlist: UUID?
}

private enum PlaylistPrompt: Identifiable {
    case create(adding: ScoreItem?)
    case rename(Playlist)
    var id: String { if case .rename(let p) = self { p.id.uuidString } else { "new" } }
}

private struct Sidebar: View {
    @Environment(Library.self) private var library
    @Binding var selection: Pick?
    @State private var query = ""
    @State private var prompt: PlaylistPrompt?
    @State private var sharing: ScoreItem?
    @State private var exporting: ScoreItem?
    @State private var sharedFile: SharedFile?
    @State private var gated: (() -> Void)?   // waiting on the copyright warning
    @State private var shareError: String?
    @AppStorage("instrumentKey") private var instrumentKey = InstrumentKey.concert.rawValue
    @State private var renaming: ScoreItem?
    @State private var deleting: Playlist?
    @State private var name = ""
    @State private var sheetTitling: ScoreItem?
    @State private var expanded: Set<UUID> = []
    @State private var scoresExpanded = true
    @AppStorage("sortBy") private var sortBy = "added"
    @AppStorage("advancedMode") private var advanced = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private func matches(_ item: ScoreItem) -> Bool {
        !searching || GitHub.matches(item.title, query)
    }

    var body: some View {
        let scores = library.items.filter { $0.generated != true }.filter(matches)
            .sorted { sortBy == "title" ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.added > $1.added }
        List(selection: $selection) {
            Section("Scores", isExpanded: searching ? .constant(true) : $scoresExpanded) {
                ForEach(scores) { item in
                    ScoreRow(item: item)
                        .tag(Pick(score: item.id))
                        .contextMenu { menu(for: item, in: nil) }
                }
                .onDelete { $0.map { scores[$0] }.forEach(delete) }
            }
            ForEach(library.playlists) { list in
                let members = library.scores(in: list).filter(matches)
                if !searching || !members.isEmpty {
                    Section(isExpanded: searching ? .constant(true) : expansion(list)) {
                        ForEach(members) { item in
                            ScoreRow(item: item)
                                .tag(Pick(score: item.id, playlist: list.id))
                                .contextMenu { menu(for: item, in: list) }
                        }
                        .onDelete { $0.map { members[$0] }.forEach { item in withAnimation(.smooth) { library.remove(item, from: list) } } }
                        .onMove(perform: searching ? nil : { library.move(in: list, from: $0, to: $1) })
                        if members.isEmpty {
                            Text("Add scores with Add to Set-List in a score’s menu.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .selectionDisabled()
                        }
                    } header: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Label(list.name, systemImage: "music.note.list")
                                Text(library.summary(of: list)).font(.caption2).foregroundStyle(.secondary).padding(.leading, 28)
                            }
                            Spacer()
                            Menu {
                                Button("Rename…", systemImage: "pencil") { name = list.name; prompt = .rename(list) }
                                Button("Delete Set-List…", systemImage: "trash", role: .destructive) { deleting = list }
                            } label: {
                                Image(systemName: "ellipsis.circle").imageScale(.medium).frame(width: 32, height: 32).contentShape(.rect)
                            }
                            .accessibilityLabel("Set-List options for \(list.name)")
                        }
                        .contextMenu {
                            Button("Rename…", systemImage: "pencil") { name = list.name; prompt = .rename(list) }
                            Button("Delete Set-List…", systemImage: "trash", role: .destructive) { deleting = list }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(StageBackground())
        .tint(Color(white: 0.32))   // neutral selection keeps white text legible; amber stays for primary actions
        .animation(.smooth, value: library.items)
        .animation(.smooth, value: library.playlists)
        .animation(.smooth, value: query)
        .searchable(text: $query, placement: .sidebar, prompt: String(localized: "Search Scores"))
        .sheet(item: $sharing) { ShareScoreView(item: $0) }
        .sheet(item: $exporting) { ExportView(item: $0) }
        .sheet(item: $sharedFile) { ActivitySheet(url: $0.url).presentationDetents([.medium, .large]) }
        .copyrightGate($gated)
        .alert("Couldn’t Finish", isPresented: Binding { shareError != nil } set: { if !$0 { shareError = nil } }) { Button("OK") {} } message: { Text(shareError ?? "") }
        #if DEBUG
        .onAppear { if CommandLine.arguments.contains("-export") { exporting = library.items.first } }   // test hook
        #endif
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                #if !targetEnvironment(macCatalyst)
                Button { library.showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                    .keyboardShortcut(",", modifiers: .command)
                    .help("Settings (⌘,)")
                #endif
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Add Music") {
                        Button("Import Score…", systemImage: "square.and.arrow.down") { library.showImporter = true }
                        Button("New Blank Score…", systemImage: "doc.badge.plus") { Store.shared.unlock(.professional, "Writing a new score") { library.showBlank = true } }
                        Button("Import Folder from Files…", systemImage: "folder.badge.plus") { library.showFolderPicker = true }
                        Button("Search Scores…", systemImage: "magnifyingglass") { Store.shared.unlock(.performer, "Search Scores") { library.showFreeScores = true } }
                        Button("Tracks from GitHub…", systemImage: "shippingbox") { library.showGitHub = true }
                        Button("Scales & Arpeggios…", systemImage: "pianokeys") { library.showScales = true }
                        if DocumentScanner.isSupported {
                            Button("Scan Sheet Music…", systemImage: "camera.viewfinder") { library.showScanner = true }
                        }
                    }
                    Section("Lyrics") {
                        Button("Lyrics with Backing…", systemImage: "quote.bubble") { Store.shared.unlock(.performer, "Finding lyrics online") { library.showLyricsPicker = true } }
                        Button("Lyrics from Apple Music…", systemImage: "music.note") { Store.shared.unlock(.performer, "Apple Music") { library.showAppleMusic = true } }
                    }
                    Section {
                        Button("New Set-List…", systemImage: "music.note.list") { name = ""; prompt = .create(adding: nil) }
                        Button("Tuner…", systemImage: "tuningfork") { Store.shared.unlock(.performer, "The tuner") { library.showTuner = true } }
                        Button("Help", systemImage: "questionmark.circle") { library.showHelp = true }
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                #if targetEnvironment(macCatalyst)
                .tint(Color(white: 0.3))   // neutral like the sidebar button; amber means "on" or "play"
                #else
                .tint(Theme.accent)
                #endif
            }
        }
        .overlay {
            if library.items.isEmpty {
                Text("Imported scores appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if searching, scores.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: Binding { deleting != nil } set: { if !$0 { deleting = nil } }, titleVisibility: .visible, presenting: deleting) { list in
            Button("Delete Set-List", role: .destructive) {
                if selection?.playlist == list.id { selection?.playlist = nil }
                withAnimation(.smooth) { library.delete(list) }
            }
        } message: { _ in Text("The scores in it stay in your library.") }
        .alert("Rename Score", isPresented: Binding { renaming != nil } set: { if !$0 { renaming = nil } }, presenting: renaming) { item in
            TextField("Title", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { var renamed = item; renamed.title = title; library.save(renamed) }
            }
        }
        .alert("Title on the Sheet", isPresented: Binding { sheetTitling != nil } set: { if !$0 { sheetTitling = nil } }, presenting: sheetTitling) { item in
            TextField("Title", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Use Library Name") { var c = item; c.sheetTitle = nil; library.save(c) }
            Button("Save") { var c = item; c.sheetTitle = name.trimmingCharacters(in: .whitespacesAndNewlines); if c.sheetTitle?.isEmpty == true { c.sheetTitle = nil }; library.save(c) }
        } message: { _ in Text("This is the heading printed on the music. The name in your library stays as it is.") }
        .alert(prompt.map { if case .rename = $0 { String(localized: "Rename Set-List") } else { String(localized: "New Set-List") } } ?? "",
               isPresented: Binding { prompt != nil } set: { if !$0 { prompt = nil } }, presenting: prompt) { p in
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button(p.id == "new" ? "Create" : "Rename") { commit(p) }
        }
    }

    private func expansion(_ list: Playlist) -> Binding<Bool> {
        Binding { !expanded.contains(list.id) } set: { open in   // stored as collapsed, so new playlists start open
            if open { expanded.remove(list.id) } else { expanded.insert(list.id) }
        }
    }

    /// How far the page is moved from the written key, as the score screen shows it.
    private func shift(_ item: ScoreItem) -> Int { (item.transpose ?? 0) + (InstrumentKey(rawValue: instrumentKey) ?? .concert).offset - item.writtenKey.offset }

    private func share(_ item: ScoreItem, print: Bool = false, _ make: () throws -> URL) {
        do {
            let url = try make()
            if print { Printer.print(url, name: item.title) } else { sharedFile = SharedFile(url: url) }
        } catch { shareError = error.localizedDescription }
    }

    @ViewBuilder private func menu(for item: ScoreItem, in list: Playlist?) -> some View {
        if supportsMultipleWindows {
            Button("Open in New Window", systemImage: "macwindow.badge.plus") { openWindow(id: "score", value: item.id) }
            Divider()
        }
        Button("Rename…", systemImage: "pencil") { name = item.title; renaming = item }
        if !item.isPDF, !item.isLyricsOnly { Button("Edit Title on Sheet…", systemImage: "textformat") { name = item.sheetTitle ?? TitleClean.clean(item.title); sheetTitling = item } }
        Menu("Add to Set-List", systemImage: "music.note.list") {
            ForEach(library.playlists) { p in
                Button(p.name) { withAnimation(.smooth) { library.add(item, to: p) } }
                    .disabled(p.scores.contains(item.id))
            }
            if !library.playlists.isEmpty { Divider() }
            Button("New Set-List…", systemImage: "plus") { name = ""; prompt = .create(adding: item) }
        }
        if let list {
            Button("Remove from “\(list.name)”", systemImage: "minus.circle") { withAnimation(.smooth) { library.remove(item, from: list) } }
        }
        Menu("Share", systemImage: "square.and.arrow.up") {
            if !item.isLyricsOnly {
                Button("Export as MusicXML…", systemImage: "doc.text") { Store.shared.unlock(.performer, "Export") { gated = { share(item) { try library.exportMusicXML(item) } } } }
                Button("Export as PDF…", systemImage: "doc.richtext") { Store.shared.unlock(.performer, "Export") { gated = { share(item) { try library.exportPDF(item, transpose: shift(item)) } } } }
                Button("Print…", systemImage: "printer") { Store.shared.unlock(.performer, "Printing") { gated = { share(item, print: true) { try library.exportPDF(item, transpose: shift(item)) } } } }
            }
            if advanced {
                if !item.isLyricsOnly { Divider() }
                Button("Share with Another Player…", systemImage: "person.2.wave.2") { Store.shared.unlock(.performer, "Sharing with another player") { gated = { sharing = item } } }
                Button("Export Video…", systemImage: "film") { Store.shared.unlock(.performer, "Video export") { gated = { exporting = item } } }
            }
        }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            do { try library.duplicate(item) } catch { shareError = error.localizedDescription }
        }
        Divider()
        Button("Delete from Library", systemImage: "trash", role: .destructive) { delete(item) }
    }

    private func commit(_ p: PlaylistPrompt) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let title = trimmed.isEmpty ? "Untitled Set-List" : trimmed
        withAnimation(.smooth) {
            switch p {
            case .create(let item): library.newPlaylist(title, adding: item)
            case .rename(let list): library.rename(list, to: title)
            }
        }
    }

    private func delete(_ item: ScoreItem) {
        if selection?.score == item.id { selection = nil }
        withAnimation(.smooth) { library.delete(item) }
    }
}

private struct ScoreRow: View {
    @Environment(Library.self) private var library
    let item: ScoreItem

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if item.isLyricsOnly {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3).fill(Theme.accent.opacity(0.18))
                        Image(systemName: "quote.bubble.fill").foregroundStyle(Theme.accent)
                    }
                    .accessibilityHidden(true)
                } else {
                    Thumbnail(url: library.scoreURL(item), transpose: item.isPDF ? 0 : item.transpose ?? 0)
                }
            }
            .frame(width: 40, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(item.kindLabel)
                    if item.track != nil {
                        Image(systemName: "waveform")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Has backing track")
                    }
                    Text("♩ \(Int(item.tempo))")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// First page of a score in miniature.
struct Thumbnail: View {
    let url: URL
    var transpose = 0
    @AppStorage("darkPaper") private var dark = false
    @State private var page: CGPDFPage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(Theme.paper(dark: dark))
            if let page {
                PageCanvas(page: page, dark: dark)
                    .transition(.opacity)
            }
        }
        .clipShape(.rect(cornerRadius: 3))
        .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
        .task(id: "\(url) \(transpose)") {
            let loaded = await Task.detached { try? ScoreLoader.load(url, beatsPerBar: 4, analyse: false, transpose: transpose) }.value
            withAnimation(.easeOut(duration: 0.3)) { page = loaded?.pages.first }
        }
    }
}

// MARK: - Welcome

/// A home-screen button: a pad of stitched leather with the icon pressed into it. The main action is a brass plate.
private struct HomeTile: View {
    let title: LocalizedStringKey
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 26, weight: .regular)).frame(height: 30)
                Text(title).font(.system(.callout, design: .default, weight: .bold)).multilineTextAlignment(.center).lineLimit(2).frame(maxWidth: 118)   // narrow enough that a long name goes on two lines
            }
            .frame(width: 156, height: 100)
            .foregroundStyle(prominent ? Color(red: 0.12, green: 0.07, blue: 0.02) : Color(red: 0.97, green: 0.93, blue: 0.84))
            .shadow(color: prominent ? .white.opacity(0.4) : .black.opacity(0.7), radius: 0, y: prominent ? 0.8 : -0.8)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(TileStyle(prominent: prominent))
        .accessibilityLabel(title)
    }
}

private struct TileStyle: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        Group {
            if prominent { configuration.label.modifier(BrassPlate(radius: 12, pressed: pressed)) }
            else { configuration.label.modifier(LeatherPad(radius: 12, pressed: pressed)) }
        }
        .offset(y: pressed ? 1.5 : 0)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

private struct Welcome: View {
    @Environment(Library.self) private var library
    let hasScores: Bool
    let openSample: () -> Void
    @State private var appeared = false
    @Environment(\.colorScheme) private var scheme
    /// Lettering on the desk: ivory on dark leather, dark brown on a light desk.
    private var lettering: Color { scheme == .dark ? Color(red: 0.93, green: 0.88, blue: 0.78) : Color(red: 0.24, green: 0.16, blue: 0.09) }

    var body: some View {
        ZStack {
            StageBackground()
            VStack(spacing: 28) {
                ClefMark(appeared: appeared)
                VStack(spacing: 10) {
                    Text("Maestro Pro")
                        .font(.custom("Baskerville-SemiBold", size: 46))
                        .foregroundStyle(lettering)
                        .engraved(scheme == .dark ? 1 : 0.35)
                    Text(hasScores ? String(localized: "Open a score from your library, or bring in a new one.")
                                   : String(localized: "Read, rehearse, perform and write.\nSheet music timed to the note."))
                        .font(.custom("Baskerville-Italic", size: 20))
                        .foregroundStyle(lettering.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
                if PhoneViewer.isDuo {
                    // The Duo keeps it to the two things its screen is for.
                    HStack(spacing: 14) {
                        HomeTile(title: "Import Score", symbol: "square.and.arrow.down", prominent: true) { library.showImporter = true }
                        HomeTile(title: "Tuner", symbol: "tuningfork") { Store.shared.unlock(.performer, "The tuner") { library.showTuner = true } }
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                } else {
                WrapLayout(spacing: 14, lineSpacing: 14) {
                    HomeTile(title: "Import Score", symbol: "square.and.arrow.down", prominent: true) { library.showImporter = true }
                    HomeTile(title: "New Blank Score", symbol: "doc.badge.plus") { Store.shared.unlock(.professional, "Writing a new score") { library.showBlank = true } }
                    HomeTile(title: "Import Folder", symbol: "folder.badge.plus") { library.showFolderPicker = true }
                    if DocumentScanner.isSupported {
                        HomeTile(title: "Scan Music", symbol: "camera.viewfinder") { library.showScanner = true }
                    }
                    HomeTile(title: "Lyrics with Backing", symbol: "quote.bubble") { Store.shared.unlock(.performer, "Finding lyrics online") { library.showLyricsPicker = true } }
                    HomeTile(title: "Search Scores", symbol: "magnifyingglass") { Store.shared.unlock(.performer, "Search Scores") { library.showFreeScores = true } }
                    HomeTile(title: "Scales & Arpeggios", symbol: "pianokeys") { library.showScales = true }
                    HomeTile(title: "Tuner", symbol: "tuningfork") { Store.shared.unlock(.performer, "The tuner") { library.showTuner = true } }
                    HomeTile(title: "Open Sample", symbol: "music.note", action: openSample)
                }
                .frame(maxWidth: 700)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                }
                #if DEBUG
                if CommandLine.arguments.contains("-creditbanner") { CreditBanner().frame(maxWidth: 520) }
                #endif
                Text("Drop files anywhere in the window.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .opacity(appeared ? 1 : 0)
            }
            .padding(32)
        }
        .onAppear { withAnimation(.spring(duration: 1.1, bounce: 0.25).delay(0.1)) { appeared = true } }
    }
}

/// A treble clef and four notes inlaid in brass on the leather, the staff drawn in with them.
private struct ClefMark: View {
    let appeared: Bool
    private let brass = Color(red: 0.88, green: 0.7, blue: 0.38)

    var body: some View {
        ZStack {
            VStack(spacing: 11) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(brass.opacity(0.85))
                        .frame(height: 1.6)
                        .shadow(color: .black.opacity(0.7), radius: 0, y: 1)
                        .scaleEffect(x: appeared ? 1 : 0, anchor: .leading)
                        .animation(.easeOut(duration: 0.9).delay(Double(i) * 0.07), value: appeared)
                }
            }
            .frame(width: 220)
            Text("\u{E050}")
                .font(.custom("Bravura", size: 50))
                .foregroundStyle(brass)
                .shadow(color: .white.opacity(0.3), radius: 0, y: -0.8)
                .shadow(color: .black.opacity(0.75), radius: 1, y: 1.6)
                .offset(x: -70, y: 9)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.8).delay(0.45), value: appeared)
            HStack(spacing: 26) {
                ForEach(0..<4, id: \.self) { i in
                    Text("\u{E1D5}")
                        .font(.custom("Bravura", size: 50))
                        .foregroundStyle(brass)
                        .shadow(color: .white.opacity(0.3), radius: 0, y: -0.8)
                        .shadow(color: .black.opacity(0.75), radius: 1, y: 1.6)
                        .offset(y: [8, -3, -14, 2][i])
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(0.7 + Double(i) * 0.09), value: appeared)
                }
            }
            .offset(x: 30, y: 9)
        }
        .frame(height: 120)
        .accessibilityHidden(true)
    }
}

private struct DropHalo: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 22)
            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
            .background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 22))
            .padding(10)
            .overlay {
                Label("Drop to Import", systemImage: "square.and.arrow.down")
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .foregroundStyle(Color(red: 0.93, green: 0.88, blue: 0.78))
                    .modifier(LeatherPad(radius: 12))
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}

