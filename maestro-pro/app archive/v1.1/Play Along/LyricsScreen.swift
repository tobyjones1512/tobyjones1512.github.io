import SwiftUI
import UniformTypeIdentifiers

/// A lyrics file on its own, optionally with a recording to sing along to.
struct LyricsScreen: View {
    @Environment(Library.self) private var library
    let item: ScoreItem
    @Binding var columns: NavigationSplitViewVisibility

    @State private var transport = Transport()
    @State private var watcher = CaptureWatcher()
    @Environment(Together.self) private var together
    @State private var showTogether = false
    @State private var onlyPart = 0
    @State private var geniusResult: String?
    @State private var askingArtist = false
    @State private var suggestions: [LrcHit] = []
    @State private var suggesting = false
    @State private var artistName = ""
    @AppStorage("advancedMode") private var advanced = false
    @Environment(\.closeScore) private var closeScore
    @State private var width: CGFloat = 1000
    @State private var doc: LyricsDocument?
    @State private var cdg: CDGPlayer?
    @State private var failure: String?
    @State private var pickingTrack = false
    @State private var karaoke: KaraokeFile?
    @State private var assigningSingers = false
    @State private var editingLyrics = false
    @State private var showEQ = false
    @AppStorage("karaokeMelody") private var melodyGuide = true
    @AppStorage("lyricsAnimate") private var lyricsAnimate = true
    @AppStorage("lyricsProgress") private var lyricsProgress = true
    @AppStorage("lyricsBlur") private var lyricsBlur = true
    @State private var columnsBeforePlay: NavigationSplitViewVisibility?
    @AppStorage("lyricsSize") private var size = 1.0
    @AppStorage("showClock") private var showClock = false
    @Environment(\.verticalSizeClass) private var vSize
    /// An iPhone on its side has no height to spare: the bar folds into a button until it's wanted.
    @State private var barOpen = false
    private var foldBar: Bool { vSize == .compact && UIDevice.current.userInterfaceIdiom == .phone }

    /// The words themselves.
    private var words: some View {
        ZStack {
            StageBackground()
            if watcher.captured, cdg != nil || doc != nil {
                RecordingNotice()
            } else if let cdg {
                SecureContent { CDGView(player: cdg, transport: transport, bottom: foldBar && !barOpen ? 16 : 140) }.transition(.opacity)
            } else if let doc {
                SecureContent { LyricsView(doc: doc.only(part: onlyPart), transport: transport, seconds: true) }
                    .transition(.opacity)
            } else if let failure {
                ContentUnavailableView("Couldn’t Open Lyrics", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                }
            }
        }
    }

    var body: some View {
        words
        .overlay(alignment: .topTrailing) { if showClock { ClockBadge() } }
        .overlay(alignment: .bottom) {
            if doc != nil || cdg != nil {
                if foldBar && !barOpen {
                    HStack {
                        Button { withAnimation(.smooth) { barOpen = true } } label: {
                            Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill").font(.title3.weight(.semibold)).frame(width: 48, height: 48)
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.accent)
                        .metalPlate(radius: 24, screws: false)
                        .environment(\.colorScheme, .dark)
                        .accessibilityLabel("Show Playback Controls")
                        Spacer()
                    }
                    .padding(.leading, 20).padding(.bottom, 14)
                } else {
                    TransportBar(transport: transport, item: item, lyricsOnly: true)
                        .overlay(alignment: .topTrailing) {
                            if foldBar {
                                Button { withAnimation(.smooth) { barOpen = false } } label: { Image(systemName: "chevron.down.circle.fill").font(.title3).padding(8) }
                                    .foregroundStyle(.secondary).accessibilityLabel("Hide Playback Controls")
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                }
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .titleHidden()
        .toolbarRole(.editor)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .toolbar(id: "lyrics") {
            ToolbarItem(id: "recording", placement: .secondaryAction) {
                Menu {
                    Button(transport.hasTrack ? String(localized: "Replace Recording…") : String(localized: "Add Recording…"), systemImage: "waveform.badge.plus") { pickingTrack = true }
                    if transport.hasTrack {
                        Button("Equaliser…", systemImage: "slider.vertical.3") { Store.shared.unlock(.performer, "The equaliser") { showEQ = true } }
                        Button("Remove Recording", systemImage: "trash", role: .destructive) {
                            library.removeTrack(item)
                            transport.setTrack(nil)
                            Task { await load() }
                        }
                    }
                } label: {
                    Label("Recording", systemImage: transport.hasTrack ? "waveform" : "waveform.badge.plus")
                }
                .help("Sing along to a recording; untimed lyrics are spread across it")
            }
            ToolbarItem(id: "together", placement: .secondaryAction) {
                if advanced {
                    Button { Store.shared.unlock(.performer, "Play Together") { showTogether = true } } label: {
                        Label("Play Together", systemImage: "person.2.wave.2").symbolVariant(together.connected ? .fill : .none)
                    }
                    .help("Start the words in time with sheet music or lyrics on another device")
                }
            }
            ToolbarItem(id: "karaoke", placement: .secondaryAction) {
                if karaoke?.notes.isEmpty == false, !transport.hasTrack {
                    Menu {
                        Picker("Play Music As", selection: $transport.instrument) {
                            ForEach(Instrument.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                        }
                        Toggle("Play the Melody Guide", isOn: $melodyGuide)
                    } label: {
                        Label("Karaoke Music", systemImage: "pianokeys")
                    }
                    .menuActionDismissBehavior(.disabled)
                    .help("The karaoke file's own music, played on a built-in instrument")
                }
            }
            ToolbarItem(id: "text", placement: .secondaryAction) {
                if !item.isCDG { Menu {
                    Button("Bigger Text", systemImage: "textformat.size.larger") { size = min(1.8, size + 0.1) }
                    Button("Smaller Text", systemImage: "textformat.size.smaller") { size = max(0.6, size - 0.1) }
                    Divider()
                    Group {   // only lyrics timed word by word can fill and swell
                        Toggle("Animate Syllables", systemImage: "wand.and.stars", isOn: $lyricsAnimate.animation(.smooth))
                        Toggle("Show Syllable Progress", systemImage: "text.line.first.and.arrowtriangle.forward", isOn: $lyricsProgress)
                    }
                    .disabled(doc?.wordTimed == false)
                    Toggle("Blur Other Lines", systemImage: "circle.lefthalf.filled", isOn: $lyricsBlur.animation(.smooth))
                    Divider()
                    Button("Edit Lyrics…", systemImage: "pencil") { editingLyrics = true }.disabled(!library.canEditLyrics(item))
                    Button("Assign Singers…", systemImage: "person.2") { assigningSingers = true }.disabled(doc == nil)
                    Button("Match Singers", systemImage: "person.2.badge.gearshape") { matchSingers() }
                    .disabled(doc == nil || item.isCDG)
                    if let doc { SingerFilter(doc: doc, part: $onlyPart) }
                    Button("Lyrics Appearance…", systemImage: "gearshape") { library.showSettings = true }
                } label: {
                    Label("Text", systemImage: "textformat.size")
                } }
            }
        }
        .fileImporter(isPresented: $pickingTrack, allowedContentTypes: [.audio]) { result in
            guard let url = try? result.get(), let updated = try? library.importTrack(from: url, for: item) else { return }
            transport.setTrack(library.trackURL(updated))
            Task { await load() }
        }
        .task { await load() }
        .sheet(isPresented: $showEQ) { EQSheet(item: library.items.first { $0.id == item.id } ?? item, transport: transport) }
        .sheet(isPresented: $editingLyrics) { LyricsEditorSheet(item: item) { Task { await load() } } }
        .sheet(isPresented: $assigningSingers) {
            if let doc { SingersSheet(doc: doc) { library.setSingers($0, for: item); self.doc = doc.withSingers($0) } }
        }
        .onChange(of: transport.isPlaying) { _, playing in stageMode(playing) }
        .onChange(of: watcher.captured) { _, on in if on { transport.pause() } }
        .sheet(isPresented: $showTogether) { TogetherView(together: together) }
        .onAppear {
            transport.lyricsClock = true
            together.transport = transport; together.title = item.title; together.lyrics = true; together.bars = 0
            transport.together = together.connected ? together : nil
            together.sendHello()
        }
        .onChange(of: together.connected) { _, on in transport.together = on ? together : nil }
        .onChange(of: library.singersVersion) { _, _ in if let doc { self.doc = doc.withSingers(library.singers(item)) } }
        .sheet(isPresented: $suggesting) {
            NavigationStack {
                List {
                    Section { ForEach(suggestions) { hit in
                        Button { suggesting = false; matchSingers(artist: hit.artistName, title: hit.trackName) } label: {
                            VStack(alignment: .leading) {
                                Text(hit.trackName).foregroundStyle(.primary)
                                Text(hit.artistName).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    } } footer: { Text("The song couldn’t be matched. Pick the closest one.") }
                    Button("None of These: Enter the Artist…") { suggesting = false; askingArtist = true }
                }
                .navigationTitle("Did You Mean?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { suggesting = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Who Sings This?", isPresented: $askingArtist) {
            TextField("Artist", text: $artistName)
            Button("Match") { matchSingers(artist: artistName) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The artist couldn’t be worked out from the track. Enter it to match the singers.") }
        .alert("Singers", isPresented: Binding { geniusResult != nil } set: { if !$0 { geniusResult = nil } }) { Button("OK") {} } message: { Text(geniusResult ?? "") }
        .onChange(of: item.trackSemitones) { _, n in applyKey(n) }
        .onChange(of: melodyGuide) { _, _ in if doc != nil { setNotes() } }
        .onDisappear { transport.pause(); if together.transport === transport { together.transport = nil; transport.together = nil } }
        .focusedSceneValue(\.transport, transport)
        .playbackExtras(transport)
    }

    private func matchSingers(artist: String? = nil, title: String? = nil) {
        Task {
            guard let n = await library.matchSingers(item, replace: true, artist: artist, title: title) else {
                if artist != nil { geniusResult = String(localized: "That song couldn’t be found on Genius, so its singers couldn’t be matched."); return }   // asked once already
                var seen = Set<String>()
                suggestions = Array(await LrcLibSearch.find(item.title).filter { seen.insert(($0.artistName + $0.trackName).lowercased()).inserted }.prefix(8))
                if suggestions.isEmpty { askingArtist = true } else { suggesting = true }
                return
            }
            geniusResult = n > 0 ? String(localized: "\(n) lines were given a singer. Check them in Assign Singers.") : String(localized: "Only one singer was found for this song.")
        }
    }

    private func load() async {
        await Transport.activateSession()
        let track = library.trackURL(item)
        if item.isCDG { await loadCDG(track: track); return }
        let url = library.lyricsURL(item)!
        do {
            if track != nil, !transport.hasTrack { transport.setTrack(track) }
            transport.trackEQ = item.trackEQ
            await transport.attachAppleMusic(item.appleMusic)
            let parsed: LyricsDocument
            if Karaoke.extensions.contains(url.pathExtension.lowercased()) {
                let file = try await Task.detached { try Karaoke.parse(Data(contentsOf: url)) }.value
                karaoke = file
                parsed = file.lyrics
            } else {
                karaoke = nil
                parsed = try Lyrics.document(from: url, duration: transport.trackDuration)
            }
            guard !parsed.isEmpty else { throw ScoreError.unsupported(String(localized: "There are no lyrics in this file.")) }
            // Each line is a "bar" of a 60 BPM clock, so a beat is a second and the skip buttons step line by line.
            transport.tempo = 60
            transport.countInEnabled = false
            transport.offset = item.offset
            var t = Timeline()
            let end = max(parsed.end + 2, transport.trackDuration ?? 0, transport.externalDuration ?? 0, karaoke?.length ?? 0)
            for (i, line) in parsed.lines.enumerated() {
                let next = i + 1 < parsed.lines.count ? parsed.lines[i + 1].start : end
                t.measures.append(MeasureMark(start: line.start, duration: max(0.1, next - line.start), system: 0, bar: i, x0: 0, x1: 0, anchors: []))
            }
            transport.timeline = t
            setNotes()
            applyKey(item.trackSemitones)
            withAnimation(.smooth) { doc = parsed.withSingers(library.singers(item)) }
            #if DEBUG
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "-lyricsseek"), i + 1 < args.count, let t = Double(args[i + 1]) { transport.seek(to: t) }
            if args.contains("-autoplay") { Task { try? await Task.sleep(for: .seconds(1)); transport.play() } }
            #endif
        } catch {
            failure = error.localizedDescription
        }
    }

    /// A CD+Graphics karaoke file: its own pictures, in time with the recording.
    private func loadCDG(track: URL?) async {
        let source = library.scoreURL(item)
        do {
            if track != nil, !transport.hasTrack { transport.setTrack(track) }
            let player = try await Task.detached { try CDGPlayer(data: Data(contentsOf: source)) }.value
            // Each ten seconds is a "bar" of a 60 BPM clock, so a beat is a second and the skip buttons step through it.
            transport.tempo = 60
            transport.countInEnabled = false
            transport.offset = item.offset
            var t = Timeline()
            let end = max(player.duration, transport.trackDuration ?? 0)
            var start = 0.0
            while start < end {
                t.measures.append(MeasureMark(start: start, duration: min(10, end - start), system: 0, bar: t.measures.count, x0: 0, x1: 0, anchors: []))
                start += 10
            }
            transport.timeline = t
            applyKey(item.trackSemitones)
            withAnimation(.smooth) { cdg = player }
            #if DEBUG
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "-lyricsseek"), i + 1 < args.count, let s = Double(args[i + 1]) { transport.seek(to: s) }
            if args.contains("-autoplay") { Task { try? await Task.sleep(for: .seconds(1)); transport.play() } }
            #endif
        } catch {
            failure = error.localizedDescription
        }
    }

    /// A karaoke file's own music plays through the built-in instruments, unless a recording is the backing.
    private func setNotes() {
        var t = transport.timeline
        guard let karaoke, !transport.hasTrack else { t.notes = []; transport.timeline = t; return }
        t.notes = karaoke.notes.filter { melodyGuide || !$0.melody }.enumerated().map { i, n in
            NoteEvent(id: i, start: n.start, duration: n.duration, page: 0, rect: .zero, pitch: n.pitch)
        }
        transport.timeline = t
        if transport.instrument == .off { transport.instrument = .piano }
    }

    /// The backing moves by semitones: a recording is pitch-shifted, the karaoke music is played that much higher or lower.
    private func applyKey(_ n: Int) {
        transport.trackSemitones = n
        transport.soundingShift = -n
    }

    private func stageMode(_ playing: Bool) {
        withAnimation(.smooth(duration: 0.5)) {
            if playing, columns != .detailOnly, Pref.bool("hideSidebarOnPlay", true) {
                columnsBeforePlay = columns
                columns = .detailOnly
            } else if !playing, let previous = columnsBeforePlay {
                columns = previous
                columnsBeforePlay = nil
            }
        }
    }
}

/// The lyrics file as text, timings and all, to correct the words.
struct LyricsEditorSheet: View {
    let item: ScoreItem
    let onSave: () -> Void
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.body.monospaced())
                .autocorrectionDisabled()
                .padding(.horizontal)
                .safeAreaInset(edge: .top) {
                    Text("Each line starts with the time it is sung, like [01:23.45]. Change the words after it; keep the time as it is.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Edit Lyrics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do { try library.saveLyricsText(text, for: item); onSave(); dismiss() }
                            catch { failure = error.localizedDescription }
                        }
                    }
                }
                .alert("Couldn’t Save Lyrics", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
                    Button("OK") {}
                } message: { Text(failure ?? "") }
                .task { text = library.lyricsURL(item).flatMap { try? Library.readText($0) } ?? "" }
        }
    }
}

/// Choose lines and say who sings them, for duets and trios: singer 1 on the left, singer 2 on the right,
/// singer 3 and everyone together in the middle. Saved with the song.
/// Shows one singer's lines only (with everyone's), for a song with more than one singer.
struct SingerFilter: View {
    let doc: LyricsDocument
    @Binding var part: Int

    var body: some View {
        if doc.partCount >= 2 {
            Picker("Show Lines For", systemImage: "person.crop.circle", selection: $part) {
                Text("All Singers").tag(0)
                ForEach(Set(doc.lines.map(\.part)).filter { $0 > 0 && $0 != LyricLine.everyone }.sorted(), id: \.self) { Text("Singer \($0)").tag($0) }
            }
            .pickerStyle(.menu)
        }
    }
}

struct SingersSheet: View {
    let doc: LyricsDocument
    let onSave: ([Int: Int]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var parts: [Int]
    @State private var selection = Set<Int>()

    init(doc: LyricsDocument, onSave: @escaping ([Int: Int]) -> Void) {
        self.doc = doc
        self.onSave = onSave
        _parts = State(initialValue: doc.lines.map(\.part))
    }

    static func name(_ part: Int) -> String {
        switch part {
        case 1, 2, 3: String(localized: "Singer \(part)")
        case LyricLine.everyone: "Everyone"
        default: ""
        }
    }

    var body: some View {
        NavigationStack {
            // Each tap ticks or unticks a line, so several can be chosen on iPad and Mac alike.
            List(doc.lines.indices, id: \.self) { i in
                Button {
                    if selection.contains(i) { selection.remove(i) } else { selection.insert(i) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selection.contains(i) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection.contains(i) ? Theme.accent : .secondary)
                            .font(.title3)
                        Text(doc.lines[i].text).foregroundStyle(.primary)
                        Spacer()
                        Text(Self.name(parts[i])).font(.callout).foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.contains(i) ? .isSelected : [])
            }
            .navigationTitle("Assign Singers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button(selection.count == doc.lines.count ? String(localized: "Select None") : String(localized: "Select All")) {
                        selection = selection.count == doc.lines.count ? [] : Set(doc.lines.indices)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(Dictionary(uniqueKeysWithValues: parts.enumerated().map { ($0.offset, $0.element) }))
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    ForEach([1, 2, 3, LyricLine.everyone], id: \.self) { part in
                        Button(Self.name(part)) { assign(part) }
                    }
                    Button("Clear", role: .destructive) { assign(0) }
                }
            }
            .safeAreaInset(edge: .top) {
                Text(selection.isEmpty ? String(localized: "Tap the lines one person sings, then choose who sings them below.") : (selection.count == 1 ? String(localized: "1 line selected") : String(localized: "\(selection.count) lines selected")))
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(.bar)
            }
        }
    }

    private func assign(_ part: Int) {
        for i in selection { parts[i] = part }
        selection = []
    }
}

/// The karaoke picture, as large as the screen allows, following the playback clock.
struct CDGView: View {
    let player: CDGPlayer
    let transport: Transport
    /// Room left under the picture for the floating bar; a folded bar needs almost none.
    var bottom: CGFloat = 140

    var body: some View {
        let t = transport.seconds   // reading the clock redraws this as playback moves
        Group {
            if let image = player.image(at: max(0, t)) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(CGFloat(CDGPlayer.width) / CGFloat(CDGPlayer.height), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Karaoke picture")
    }
}
