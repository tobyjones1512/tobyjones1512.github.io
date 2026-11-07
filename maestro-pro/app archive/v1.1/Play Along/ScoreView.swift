import MultipeerConnectivity
import SwiftUI
import UniformTypeIdentifiers

struct ScoreScreen: View {
    @Environment(Library.self) private var library
    let item: ScoreItem
    @Binding var columns: NavigationSplitViewVisibility

    @State private var transport = Transport()
    @State private var watcher = CaptureWatcher()
    @State private var annotations = AnnotationStore()
    @Environment(Together.self) private var together
    @State private var showTogether = false
    @State private var score: LoadedScore?
    @State private var pdfSource: LoadedScore?   // the PDF as read, kept while the key or metre changes
    @State private var failure: String?
    @State private var showInspector = false
    @State private var pickingTrack = false
    @State private var pickingExtra = false
    @State private var warnTrack = false
    @State private var pickingMusic = false
    @State private var showWritten = false
    @State private var writer = WrittenReviewModel()
    @State private var fullScreen = false
    @State private var columnsBeforePlay: NavigationSplitViewVisibility?
    @State private var width: CGFloat = 1000
    @Environment(\.closeScore) private var closeScore
    @Environment(\.isStandaloneWindow) private var standalone
    @Environment(\.openWindow) private var openWindow
    @State private var baseTimeline: Timeline?
    @State private var askMetre = false
    @State private var lyricsDoc: LyricsDocument?
    @State private var lyricsInSeconds = false
    @State private var showLyrics = false
    @State private var showChords = false
    @State private var chordModel: ChordChartModel?
    @State private var chordMessage: String?
    @State private var pickingLyrics = false
    @State private var pickingLyricsOnline = false
    @State private var assigningSingers = false
    @State private var onlyPart = 0
    @State private var editingLyrics = false
    @State private var editingTrack = false
    @State private var reloadToken = 0
    @State private var editingScore = false
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    /// The score editor: a window of its own on the Mac, a full-screen page elsewhere (or on a Mac that can't open windows).
    private func openEditor() {
        guard store.allows(.professional) else { return store.present(.professional, "The score editor") }
        Analytics.track("editor_opened")
        #if targetEnvironment(macCatalyst)
        if supportsMultipleWindows { openWindow(id: "score-editor", value: item.id); return }
        #endif
        editingScore = true
    }
    @State private var practice = PracticeSession()
    @State private var recorder = RecordSession()
    @State private var reviewer = ReviewSession()
    @State private var takes: [Take] = []
    @State private var pageIndex = 0
    @AppStorage("pageTurn") private var pageTurn = true
    @AppStorage("showClock") private var showClock = false
    @AppStorage("advancedMode") private var advanced = false
    @AppStorage("follow") private var follow = true
    @AppStorage("playhead") private var showPlayhead = true
    @AppStorage("noteGlow") private var noteGlow = true
    @AppStorage("barWash") private var barWash = true
    private let store = Store.shared
    /// Following the music on the page is Performer's: without it these read off and open the paywall.
    private var glowGate: Binding<Bool> { store.gate(.performer, "Note highlighting", $noteGlow) }
    private var washGate: Binding<Bool> { store.gate(.performer, "Bar highlighting", $barWash) }
    private var lineGate: Binding<Bool> { store.gate(.performer, "The moving line", $showPlayhead) }
    @AppStorage("highlight") private var highlight = "Amber"
    @AppStorage("darkPaper") private var darkPaper = false
    @AppStorage("instrumentKey") private var instrumentKey = InstrumentKey.concert.rawValue
    @AppStorage("zoom") private var zoom = 1.0
    @AppStorage("lyricsAnimate") private var lyricsAnimate = true
    @AppStorage("lyricsProgress") private var lyricsProgress = true
    @AppStorage("lyricsInline") private var lyricsInline = true
    @AppStorage("scoreEditToken") private var scoreEditToken = 0.0

    /// What the page is shown in: the chosen key, plus whatever moves the score from how it was written to the
    /// player's instrument. The backing track is not moved by that: it stays at concert pitch.
    private var sheetShift: Int { (item.transpose ?? 0) + (InstrumentKey(rawValue: instrumentKey) ?? .concert).offset - item.writtenKey.offset }

    var body: some View {
        sheet
        .overlay(alignment: .bottom) {   // floats over the music, which scrolls on beneath it
            if score != nil, !transport.timeline.measures.isEmpty, !fullScreen {
                VStack(spacing: 10) {
                    if practice.active { PracticePanel(session: practice, transport: transport, staves: score?.staves ?? []).transition(.move(edge: .bottom).combined(with: .opacity)) }
                    if recorder.active { RecordPanel(session: recorder, transport: transport).transition(.move(edge: .bottom).combined(with: .opacity)) }
                    if reviewer.active {
                        ReviewPanel(session: reviewer, transport: transport, takes: takes, staves: score?.staves ?? [], open: { openReview($0) }, delete: { deleteTake($0) }, again: { startRecording() }, written: { openWritten() })
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    TransportBar(transport: transport, item: item)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                .animation(.smooth, value: practice.active)
                .animation(.smooth, value: recorder.active)
                .animation(.smooth, value: reviewer.active)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if fullScreen, score != nil, !transport.timeline.measures.isEmpty {
                HStack(spacing: 20) {
                    Button { transport.isPlaying ? transport.pause() : transport.play() } label: {
                        Image(systemName: transport.isPlaying ? "pause.fill" : "play.fill").font(.title2)
                    }
                    Button { transport.tempo = max(30, transport.tempo - 5) } label: { Image(systemName: "minus") }
                    Text("\(Int(transport.tempo)) BPM").monospacedDigit().font(.callout)
                    Button { transport.tempo = min(300, transport.tempo + 5) } label: { Image(systemName: "plus") }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if showClock { ClockBadge().padding(.trailing, fullScreen ? 64 : 0).padding(.top, fullScreen ? 8 : 0) }
        }
        .overlay(alignment: .topTrailing) {
            if fullScreen {
                Button { withAnimation(.smooth) { fullScreen = false } } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.title2).padding(10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .tint(Theme.accent).padding()
                .transition(.opacity)
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .titleHidden()
        .toolbar(fullScreen ? .hidden : .visible, for: .navigationBar)
        .toolbar(id: "score") { toolbar }
        .toolbarRole(.editor)
        .inspector(isPresented: $showInspector) {
            InspectorPanel(item: item, transport: transport, key: score?.key, highlight: $highlight, follow: $follow, showPlayhead: lineGate, noteGlow: glowGate, barWash: washGate, darkPaper: $darkPaper, pickTrack: { pickingTrack = true }, pickExtra: { store.unlock(.performer, "Stacking backing tracks") { pickingExtra = true } }, pickMusic: { store.unlock(.performer, "Apple Music") { pickingMusic = true } }, staves: score?.staves ?? [], editTrack: { store.unlock(.performer, "The track editor") { editingTrack = true } })
                .inspectorColumnWidth(min: 290, ideal: 320, max: 380)
        }
        .sheet(isPresented: $showTogether) { TogetherView(together: together) }
        #if targetEnvironment(macCatalyst)
        // Score editor opens in its own window via openWindow(id: "score-editor"); track editor stays as sheet (needs live transport ref)
        .sheet(isPresented: $editingTrack) { TrackEditorView(item: item, transport: transport) }
        #else
        .fullScreenCover(isPresented: $editingTrack) { TrackEditorView(item: item, transport: transport) }
        .fullScreenCover(isPresented: $editingScore, onDismiss: { reloadToken += 1 }) { ScoreEditorView(item: item) }
        #endif
        .fileImporter(isPresented: $pickingTrack, allowedContentTypes: [.audio]) { result in
            guard let url = try? result.get(), let updated = try? library.importTrack(from: url, for: item) else { return }
            transport.setTrack(library.trackURL(updated))
            Task { await syncTracks() }
            // Hear the track's key and tempo and set the score to match, without being asked.
            let key = score?.key
            if store.allows(.performer) { Task { _ = await TrackMatch.run(item: updated, key: key, library: library, transport: transport) } }
        }
        // Its own host view: two pickers on one view and only one of them opens.
        .background(Color.clear.fileImporter(isPresented: $pickingExtra, allowedContentTypes: [.audio]) { result in
            guard let url = try? result.get() else { return }
            _ = try? library.addExtraTrack(from: url, for: item)
        })
        .task(id: tracksSignature) { await syncTracks() }
        .sheet(isPresented: $pickingMusic) {
            AppleMusicSearchView { ref in
                guard var it = library.items.first(where: { $0.id == item.id }) else { return }
                it.appleMusic = ref
                library.save(it)
                if it.lyrics == nil { Task { if await library.fetchAppleMusicLyrics(for: it) { refreshLyrics() } } }
            }
        }
        .sheet(isPresented: $showWritten, onDismiss: { reviewer.clearFocus() }) {
            WrittenReviewView(model: writer, reviewer: reviewer, title: item.title)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        }
        .alert("Mute the Backing Track?", isPresented: $warnTrack) {
            Button("Mute It and Record") { beginRecording(muteTracks: true) }
            Button("Record Anyway") { beginRecording(muteTracks: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The microphone hears everything the speaker plays, so the backing track would be recorded and judged as if you had played it. Mute it for this recording (it comes back afterwards), or use headphones.")
        }
        .background(Color.clear.fileImporter(isPresented: $pickingLyrics, allowedContentTypes: [.lrc, .plainText, .kar, .midi, .data]) { result in
            guard let url = try? result.get() else { return }
            if let updated = try? library.importLyrics(from: url, for: item) { _ = updated; refreshLyrics(); if item.isLyricsOnly { showLyrics = true } }
        })
        .sheet(isPresented: $pickingLyricsOnline) {
            OnlineLyricsSheet(save: { _ = try library.importLyrics(from: $0, for: item) }) { refreshLyrics(); if item.isLyricsOnly { showLyrics = true } }
        }
        .onChange(of: item.lyrics) { refreshLyrics() }
        .sheet(isPresented: $editingLyrics) { LyricsEditorSheet(item: item) { refreshLyrics() } }
        .sheet(isPresented: $assigningSingers) {
            if let lyricsDoc { SingersSheet(doc: lyricsDoc) { library.setSingers($0, for: item); refreshLyrics() } }
        }
        .task(id: "\(sheetShift) \(item.beatsPerBar) \(zoom) \(reloadToken) \(item.lyrics ?? "") \(item.sheetTitle ?? "") \(lyricsInline) \(scoreEditToken)") { await load() }
        .onChange(of: item.trackSemitones) { _, n in transport.trackSemitones = n }
        .onChange(of: instrumentKey, initial: true) { _, k in transport.soundingShift = (InstrumentKey(rawValue: k) ?? .concert).offset }
        .onChange(of: item.leadIn) { _, n in withAnimation(.smooth) { transport.leadInBars = n ?? 0 } }
        .onChange(of: transport.isPlaying) { _, playing in
            stageMode(playing)
            if playing { practice.stop(); reviewer.close() } else { recorder.finish() }
        }
        .onAppear {
            takes = library.takes(item)
            recorder.onFinish = { take in
                if let take {
                    library.save(take, for: item)
                    takes = library.takes(item)
                    openReview(take)
                }
            }
        }
        .onDisappear { practice.stop(); recorder.stop(); reviewer.close() }
        .sheet(isPresented: $askMetre) {
            MetrePrompt(beats: item.beatsPerBar) { n in
                var updated = item
                updated.beatsPerBar = n; updated.meterDetected = true
                library.save(updated)
                askMetre = false
            }
            .interactiveDismissDisabled()
        }
        .onChange(of: library.editRequest, initial: true) { _, id in
            if id == item.id {
                library.editRequest = nil
                openEditor()
            }
        }
        .onChange(of: transport.hasTrack) { _, has in
            guard let base = baseTimeline else { return }
            transport.timeline = has || item.ignoreTempoMarks == true ? base : base.warped()
            refreshLyrics()
        }
        .task(id: "\(showChords) \(sheetShift) \(reloadToken) \(item.id)") { if showChords { await loadChords() } }
        .onChange(of: item.staffInstruments, initial: true) { _, v in transport.staffInstruments = (v ?? []).map { Instrument(rawValue: $0) } }
        .onChange(of: item.ignoreTempoMarks) { _, ignore in
            guard let base = baseTimeline else { return }
            transport.timeline = transport.hasTrack || ignore == true ? base : base.warped()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: showInspector) { _, open in
            if open { withAnimation(.smooth) { fullScreen = false } }
            // Narrow windows can't fit sidebar, score and inspector; give the score the room.
            if open, width < 900, columns != .detailOnly { withAnimation(.smooth) { columns = .detailOnly } }
        }
        .modifier(ScoreUsage(playing: transport.isPlaying, practice: practice.active, recording: recorder.active, annotating: annotations.active,
                             fullScreen: fullScreen, dark: darkPaper, follow: follow, inspector: showInspector, lyrics: showLyrics,
                             chords: showChords, together: showTogether, connected: together.connected, looping: transport.loop != nil,
                             metronome: transport.metronome, review: showWritten, tempo: Int(transport.tempo)))
        .onAppear {
            together.transport = transport; together.title = item.title; together.lyrics = false
            transport.together = together.connected ? together : nil
            #if DEBUG
            syncTestHooks()
            #endif
        }
        .onChange(of: transport.timeline.measures.count) { _, n in together.bars = n; together.sendHello() }
        .onChange(of: together.connected) { _, on in transport.together = on ? together : nil }
        .onDisappear { transport.pause(); if together.transport === transport { together.transport = nil; transport.together = nil } }
        .focusedSceneValue(\.transport, transport)
        .focusedSceneValue(\.inspector, $showInspector)
        .focusedSceneValue(\.scoreActions, ScoreActions(
            nextPage: { turnPage(1) }, previousPage: { turnPage(-1) },
            editScore: {
                if advanced || item.created == true {
                    stopModes(); transport.pause()
                    openEditor()
                }
            },
            annotate: { store.unlock(.performer, "Annotation") { annotations.active.toggle() } },
            waitForMe: { if canPractice { togglePractice() } },
            record: { if canRecord { recorder.active ? recorder.stop() : startRecording() } },
            chordView: { if advanced { store.unlock(.performer, "Chord View") { withAnimation(.smooth) { showChords.toggle() } } } },
            lyricsView: { if lyricsDoc != nil { withAnimation(.smooth) { showLyrics.toggle() } } }))
        .playbackExtras(transport)
    }

    /// Every control gets its own button on a Mac. On an iPad the bar keeps the few used most (Follow, Zoom, Sound, Edit,
    /// Annotate) and the rest sit in one More menu.
    private var showsAll: Bool {
        #if targetEnvironment(macCatalyst)
        !compact
        #else
        false
        #endif
    }

    /// Below this width the buttons would crowd out the title and the way back to the library, so they fold into one menu.
    private var compact: Bool {
        #if targetEnvironment(macCatalyst)
        false   // Mac toolbar always has room; NavigationSplitView detail column is narrower than 760 with sidebar open
        #else
        width + (showInspector ? 320 : 0) < 760
        #endif
    }

    /// The toolbar can be customised (on iPad and Mac): every control is an item with its own id, so each can be moved,
    /// hidden or put back. On a narrow screen they fold into the one More menu instead.
    @ToolbarContentBuilder private var toolbar: some CustomizableToolbarContent {
        // (The library button is the system's sidebar toggle; a second one of our own showed two.)
        ToolbarItem(id: "more", placement: .topBarTrailing) {
            if compact { compactMenu.tint(BarStyle.tint) }
        }
        Group {        ToolbarItem(id: "follow", placement: .secondaryAction) { if !compact { followButton.tint(BarStyle.tint) } }
        ToolbarItem(id: "dark", placement: .secondaryAction) { if showsAll { darkButton.tint(BarStyle.tint) } }
        ToolbarItem(id: "zoom", placement: .secondaryAction) { if !compact { zoomMenu.tint(BarStyle.tint) } }
        ToolbarItem(id: "show", placement: .secondaryAction) { if showsAll { showMenu.tint(BarStyle.tint) } }
        ToolbarItem(id: "sound", placement: .secondaryAction) { if !compact { soundMenu.tint(BarStyle.tint) } }
        ToolbarItem(id: "together", placement: .secondaryAction) { if showsAll { togetherButton.tint(BarStyle.tint) } }
        ToolbarItem(id: "edit", placement: .secondaryAction) { if !compact { editButton.tint(BarStyle.tint) } }
        ToolbarItem(id: "lyrics", placement: .secondaryAction) { if showsAll { lyricsMenu.tint(BarStyle.tint) } }
        ToolbarItem(id: "annotate", placement: .secondaryAction) { if !compact { annotateButton.tint(BarStyle.tint) } }
        ToolbarItem(id: "chords", placement: .secondaryAction) {
            if showsAll, advanced, !item.isLyricsOnly { ToolbarToggle(title: "Chord View", symbol: "square.grid.2x2", isOn: store.gate(.performer, "Chord View", $showChords)).tint(BarStyle.tint).help("See the piece as a chart of chords") }
        }
        }
        // Always on the bar, never folded into a menu or pushed off by the others: it holds tempo, key and the rest.
        Group {
            ToolbarItem(id: "practice", placement: .secondaryAction) { if showsAll { practiceButton.tint(BarStyle.tint) } }
            ToolbarItem(id: "record", placement: .secondaryAction) { if showsAll || recorder.active { recordMenu.tint(recorder.active ? .red : BarStyle.tint) } }
            ToolbarItem(id: "tuner", placement: .secondaryAction) { if showsAll { tunerButton.tint(BarStyle.tint) } }
            ToolbarItem(id: "tools", placement: .secondaryAction) { if !compact, !showsAll { compactMenu.tint(BarStyle.tint) } }
        }
        ToolbarItem(id: "inspector", placement: .topBarTrailing) {
            ToolbarToggle(title: "Inspector", symbol: "slider.horizontal.3", isOn: $showInspector)
                .tint(BarStyle.tint)
                .help("Show Inspector (⌥⌘I)")
        }
        ToolbarItem(id: "fullscreen", placement: .topBarTrailing) {
            Button { withAnimation(.smooth) { fullScreen = true } } label: {
                Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .tint(BarStyle.tint)
            .help("Show score full screen with auto-scroll")
        }
    }

    /// The music itself.
    @ViewBuilder private var sheet: some View {
        ZStack {
            StageBackground()
            if let score {
                music(score)
                    .transition(.opacity.combined(with: .offset(y: 30)))
                if transport.timeline.measures.isEmpty {
                    Notice(text: String(localized: "No staves were found in this PDF, so it can be read but not followed."))
                }
            } else if let failure {
                ContentUnavailableView("Couldn’t Open Score", systemImage: "exclamationmark.triangle", description: Text(failure))
            } else {
                ReadingView(isPDF: item.isPDF)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            CountInOverlay(transport: transport)
        }
    }

    /// What fills the stage: the chord chart, the words or the pages. Erased to AnyView so the Swift runtime
    /// never has to build the full nested type of every branch (on a device that hung or drew a warning sign).
    private func music(_ score: LoadedScore) -> AnyView {
        if watcher.captured { return AnyView(RecordingNotice()) }
        return AnyView(SecureContent { stage(score) })
    }

    private func stage(_ score: LoadedScore) -> AnyView {
        if showChords && advanced {
            guard let chordModel else {
                return AnyView(ContentUnavailableView("No Chords Yet", systemImage: "square.grid.2x2", description: Text(chordMessage ?? String(localized: "Working out the chords…"))))
            }
            return AnyView(ChordChartView(model: chordModel, transport: transport, zoom: zoom, follow: follow) { bar in
                let i = chordModel.order.firstIndex(of: bar) ?? bar
                transport.seek(to: transport.beat(atBar: Double(i)))
            })
        }
        if showLyrics, let lyricsDoc { return AnyView(LyricsView(doc: lyricsDoc.only(part: onlyPart), transport: transport, seconds: lyricsInSeconds)) }
        return AnyView(pages(score))
    }

    @ViewBuilder private func pages(_ score: LoadedScore) -> some View {
        if pageTurn, !fullScreen, !score.pages.isEmpty {
            PagedScore(score: score, transport: transport, annotations: annotations, follow: follow, page: $pageIndex, guides: Guides(notes: glowGate.wrappedValue, bar: washGate.wrappedValue, line: lineGate.wrappedValue), dark: darkPaper,
                       tint: Theme.highlight(highlight), inkTint: darkPaper ? Theme.highlight(highlight) : Theme.ink(highlight))
        } else {
            ScorePages(score: score, transport: transport, annotations: annotations, follow: follow, zoom: $zoom, guides: Guides(notes: glowGate.wrappedValue, bar: washGate.wrappedValue, line: lineGate.wrappedValue), dark: darkPaper,
                       tint: Theme.highlight(highlight), inkTint: darkPaper ? Theme.highlight(highlight) : Theme.ink(highlight))
        }
    }

    /// Every toolbar action, in one menu, for narrow screens. Each section is erased to AnyView: the full nested
    /// type of the menu was big enough to crash the Swift runtime while building it.
    private var compactMenu: AnyView {
        AnyView(Menu {
            AnyView(compactToolsSection)
            AnyView(compactPageSection)
            AnyView(compactSoundSection)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        })
    }

    @ViewBuilder private var compactToolsSection: some View {
        Section("Tools") {
            Button("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") { withAnimation(.smooth) { fullScreen = true } }
            Toggle("Annotate", systemImage: "pencil.tip.crop.circle", isOn: store.gate(.performer, "Annotation", $annotations.active))
            if advanced || item.created == true {
                Button("Edit Score", systemImage: "music.quarternote.3") {
                    transport.pause()
                    openEditor()
                }
            }
            if advanced { Button("Play Together", systemImage: "person.2.wave.2") { store.unlock(.performer, "Play Together") { showTogether = true } } }
            Button(practice.active ? String(localized: "Stop Wait for Me") : String(localized: "Wait for Me"), systemImage: "ear.and.waveform") { togglePractice() }
                .disabled(!canPractice)
            Button("Tuner", systemImage: "tuningfork") { store.unlock(.performer, "The tuner") { library.showTuner = true } }
            Button(recorder.active ? String(localized: "Stop Recording") : String(localized: "Record Myself"), systemImage: recorder.active ? "stop.circle" : "record.circle") { recorder.active ? recorder.stop() : startRecording() }
                .disabled(!canRecord)
            if !takes.isEmpty {
                Menu("Recordings", systemImage: "waveform") {
                    ForEach(takes) { t in Button(t.date.formatted(date: .abbreviated, time: .shortened)) { openReview(t) } }
                }
            }
        }
        Section("While Playing") {
            Toggle("Highlight Notes", systemImage: "music.note", isOn: glowGate)
            Toggle("Highlight Bar", systemImage: "rectangle.inset.filled", isOn: washGate)
            Toggle("Moving Line", systemImage: "arrow.right.to.line", isOn: lineGate)
        }
    }

    @ViewBuilder private var compactPageSection: some View {
        Section("Page") {
            Toggle("Follow Playback", systemImage: "arrow.down.doc", isOn: $follow)
            Toggle("Dark Sheet Music", systemImage: "moon", isOn: $darkPaper)
            if advanced { Toggle("Chord View", systemImage: "square.grid.2x2", isOn: store.gate(.performer, "Chord View", $showChords).animation(.smooth)) }
            Button("Zoom In", systemImage: "plus.magnifyingglass") { zoom = min(2.5, ((zoom * 1.2) * 20).rounded() / 20) }
            Button("Zoom Out", systemImage: "minus.magnifyingglass") { zoom = max(0.6, ((zoom / 1.2) * 20).rounded() / 20) }
            Button("Fit to Width", systemImage: "arrow.up.left.and.arrow.down.right") { zoom = 1 }
            Toggle("Turn Pages Like a Book", systemImage: "book.pages", isOn: $pageTurn)
        }
        Section("Words") {
            if lyricsDoc != nil { Toggle("Show Lyrics Instead of Music", systemImage: "quote.bubble", isOn: $showLyrics) }
            if !item.isPDF, item.lyrics != nil { Toggle("Words Under the Notes", systemImage: "text.below.photo", isOn: $lyricsInline) }
            Button(item.lyrics == nil ? String(localized: "Add Lyrics File…") : String(localized: "Replace Lyrics File…"), systemImage: "text.badge.plus") { pickingLyrics = true }
            Button("Search for Lyrics Online…", systemImage: "magnifyingglass") { store.unlock(.performer, "Finding lyrics online") { pickingLyricsOnline = true } }
            if item.lyrics != nil { Button("Remove Lyrics File", systemImage: "trash", role: .destructive) { library.removeLyrics(item); showLyrics = false } }
        }
    }

    @ViewBuilder private var compactSoundSection: some View {
        Section("Backing Track & Sound") {
            Button(transport.hasTrack ? String(localized: "Replace Backing Track…") : String(localized: "Add Backing Track…"), systemImage: "waveform.badge.plus") { pickingTrack = true }
            if transport.hasTrack { Button("Add Another Backing Track…", systemImage: "plus") { store.unlock(.performer, "Stacking backing tracks") { pickingExtra = true } } }
            if transport.hasTrack {
                Button("Remove Backing Track", systemImage: "trash", role: .destructive) { library.removeTrack(item); transport.setTrack(nil) }
            }
            Button(transport.hasAnyTrack ? String(localized: "Add a Song From Apple Music…") : String(localized: "Add Backing Track From Apple Music…"), systemImage: "music.note") { store.unlock(.performer, "Apple Music") { pickingMusic = true } }
            Picker("Play Score As", selection: $transport.instrument) {
                ForEach(Instrument.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
        }
    }

    /// Wait for Me needs notes to follow, and no backing track (which would carry on without you).
    private var canPractice: Bool { transport.timeline.notes.contains { $0.pitch != nil } }   // a backing track just stays silent while the score waits

    private func togglePractice() {
        if practice.active { practice.stop() } else { store.unlock(.performer, "Wait for Me") { Task { await practice.begin(transport) } } }
    }

    private var canRecord: Bool { transport.timeline.notes.contains { $0.pitch != nil } }

    /// Moves a page on or back: the book turns to it, or (scrolling) the music jumps to its first bar.
    private func turnPage(_ delta: Int) {
        let t = transport.timeline, pages = score?.pages.count ?? 1
        guard !t.measures.isEmpty else { return }
        let here = transport.beat < 0 ? 0 : (t.measureIndex(at: transport.beat).map { t.systems[t.measures[$0].system].page } ?? 0)
        let target = max(0, min(pages - 1, (pageTurn ? pageIndex : here) + delta))
        if pageTurn { pageIndex = target }
        else if let m = t.measures.first(where: { t.systems[$0.system].page == target }) { transport.seek(to: m.start) }
    }

    private func stopModes() { practice.stop(); recorder.stop(); reviewer.close() }

    #if DEBUG
    /// Test hook: a take of someone playing the first staff, two notes behind in the middle.
    private func makeTestTake() {
        let notes = transport.timeline.notes.filter { $0.pitch != nil && !$0.grace && !$0.isRest && $0.staff == 0 }.sorted { $0.start < $1.start }
        guard notes.count > 12 else { return }
        var take = Take(tempo: transport.tempo, speed: 1, a4: 440)
        let rate = transport.tempo / 60
        for (i, n) in notes.enumerated() {
            let played = (5..<10).contains(i) ? notes[i - 2] : n
            var b = n.start
            while b < n.end - 0.05 { take.frames.append(TakeFrame(t: b / rate, beat: b, midi: Float(played.pitch! - transport.soundingShift))); b += 0.1 }
        }
        take.duration = take.frames.last?.t ?? 0
        reviewer.open(take, audio: nil, transport: transport)
        reviewer.scrub(to: notes[7].start / rate + 0.2)
        if CommandLine.arguments.contains("-writtentest") {
            openWritten()
            Task {
                try? await Task.sleep(for: .seconds(2))
                if let b = writer.facts.worstBars.first ?? writer.facts.behind?.fromBar { reviewer.focus(.bars(b, b), facts: writer.facts) }
            }
        }
    }
    #endif

    /// With a backing track playing, ask first: the microphone would hear it.
    private func startRecording() {
        guard store.allows(.performer) else { return store.present(.performer, "Record Myself") }
        stopModes()
        if transport.hasAnyTrack, !transport.tracksMuted { warnTrack = true } else { beginRecording(muteTracks: false) }
    }

    private func beginRecording(muteTracks: Bool) {
        Task { await recorder.begin(transport, folder: library.takesFolder(item), muteTracks: muteTracks) }
    }

    /// Everything about the backing tracks that should reload or re-level them when it changes.
    private var tracksSignature: String {
        guard let it = library.items.first(where: { $0.id == item.id }) else { return "" }
        let extras = (it.extraTracks ?? []).map { "\($0.id)\($0.file)\($0.enabled)\($0.gainDB)\($0.offset)\($0.reduceVocals)" }.joined(separator: "|")
        let music = it.appleMusic.map { "\($0.id)\($0.enabled)\($0.offset)" } ?? ""
        return "\(it.track ?? "")|\(it.trackEnabled != false)|\(it.reduceVocals == true)|\(it.trackGainDB ?? 0)|\(music)|" + extras
    }

    /// Loads, switches and levels the backing tracks to match the score's settings, making the vocal-reduced copies when asked.
    private func syncTracks() async {
        guard let it = library.items.first(where: { $0.id == item.id }) else { return }
        var url = library.trackURL(it)
        if it.reduceVocals == true, let u = url, let r = await VocalReducer.ensure(u) { url = r }
        if url != transport.trackURL { transport.setTrack(url) }
        transport.trackEnabled = it.trackEnabled != false
        transport.trackGainDB = it.trackGainDB ?? 0
        transport.trackEQ = it.trackEQ
        var specs: [Transport.ExtraSpec] = []
        for t in it.extraTracks ?? [] {
            var u = library.folder(it).appending(path: t.file)
            if t.reduceVocals, let r = await VocalReducer.ensure(u) { u = r }
            specs.append(.init(id: t.id, url: u, offset: t.offset, enabled: t.enabled, gainDB: t.gainDB))
        }
        transport.setExtras(specs)
        await transport.attachAppleMusic(it.appleMusic)
    }

    private func openReview(_ take: Take) {
        guard store.allows(.performer) else { return store.present(.performer, "Reviewing a recording") }
        practice.stop(); recorder.stop()
        reviewer.open(take, audio: library.audioURL(take, for: item), transport: transport)
    }

    private func openWritten() {
        guard let take = reviewer.take, let facts = reviewer.makeFacts() else { return }
        writer.load(take: take, facts: facts, title: item.title, folder: library.takesFolder(item))
        showWritten = true
    }

    private func deleteTake(_ take: Take) {
        library.delete(take, for: item)
        takes = library.takes(item)
        if let next = takes.first { openReview(next) } else { reviewer.close() }
    }

    /// Record yourself, or look at an earlier recording with the notes lit.
    @ViewBuilder private var recordMenu: some View {
        if recorder.active {
            Button { recorder.stop() } label: { Label("Stop Recording", systemImage: "stop.circle.fill").foregroundStyle(.red) }
        } else {
            Menu {
                Button("Record Myself", systemImage: "record.circle") { startRecording() }.disabled(!canRecord)
                if !takes.isEmpty {
                    Section("Recordings") {
                        ForEach(takes) { t in Button(t.date.formatted(date: .abbreviated, time: .shortened), systemImage: "waveform") { openReview(t) } }
                    }
                }
            } label: { Label("Record", systemImage: "record.circle").foregroundStyle(BarStyle.glyph()) }
            .help("Record yourself playing, then see which notes you hit")
        }
    }

    @ViewBuilder private var practiceButton: some View {
        Button { togglePractice() } label: {
            Label("Wait for Me", systemImage: "ear.and.waveform").foregroundStyle(BarStyle.glyph(practice.active)).symbolVariant(practice.active ? .fill : .none)
        }
        .disabled(!canPractice)
        .help(canPractice ? String(localized: "The score waits for you to play each note, in tune") : String(localized: "There are no notes here to follow"))
    }

    @ViewBuilder private var tunerButton: some View {
        Button { store.unlock(.performer, "The tuner") { library.showTuner = true } } label: { Label("Tuner", systemImage: "tuningfork").foregroundStyle(BarStyle.glyph()) }
            .help("Tune up, or practise holding a steady note")
    }

    @ViewBuilder private var followButton: some View {
        ToolbarToggle(title: "Follow Playback", symbol: "arrow.down.doc", isOn: $follow)
            .help("Scroll the page with playback")
    }

    @ViewBuilder private var darkButton: some View {
        ToolbarToggle(title: "Dark Sheet Music", symbol: "moon", isOn: $darkPaper)
            .help("White music on black paper")
    }

    @ViewBuilder private var zoomMenu: some View {
    Menu {
        Button("Zoom In", systemImage: "plus.magnifyingglass") { zoom = min(2.5, ((zoom * 1.2) * 20).rounded() / 20) }
        Button("Zoom Out", systemImage: "minus.magnifyingglass") { zoom = max(0.6, ((zoom / 1.2) * 20).rounded() / 20) }
        Button("Fit to Width", systemImage: "arrow.up.left.and.arrow.down.right") { zoom = 1 }
        Divider()
        Toggle("Turn Pages Like a Book", systemImage: "book.pages", isOn: $pageTurn)
    } label: {
        Label("Zoom", systemImage: "plus.magnifyingglass")
    }
    .help("Make the notation bigger or smaller; the bars reflow into more or fewer to a row. Pinch also works.")
    }

    @ViewBuilder private var showMenu: some View {
    Menu {
        Toggle("Highlight Notes", systemImage: "music.note", isOn: glowGate.animation(.smooth))
        Toggle("Highlight Bar", systemImage: "rectangle.inset.filled", isOn: washGate.animation(.smooth))
        Toggle("Moving Line", systemImage: "arrow.right.to.line", isOn: lineGate.animation(.smooth))
    } label: {
        Label("Show While Playing", systemImage: "eye")
            .symbolVariant(glowGate.wrappedValue || washGate.wrappedValue || lineGate.wrappedValue ? .fill : .none)
    }
    .menuActionDismissBehavior(.disabled)   // flip several in one go
    .help("Choose how playback is shown: notes, bar, line")
    }

    @ViewBuilder private var soundMenu: some View {
    Menu {
        Button(transport.hasTrack ? String(localized: "Replace Backing Track…") : String(localized: "Add Backing Track…"), systemImage: "waveform.badge.plus") { pickingTrack = true }
        if transport.hasTrack { Button("Add Another Backing Track…", systemImage: "plus") { store.unlock(.performer, "Stacking backing tracks") { pickingExtra = true } } }
        Button("Add From Apple Music…", systemImage: "music.note") { store.unlock(.performer, "Apple Music") { pickingMusic = true } }
        if transport.hasTrack {
            Button("Remove Backing Track", systemImage: "trash", role: .destructive) {
                library.removeTrack(item)
                transport.setTrack(nil)
            }
        }
        Divider()
        Picker("Play Score As", selection: $transport.instrument) {
            ForEach(Instrument.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
        }
    } label: {
        Label("Backing Track & Sound", systemImage: transport.hasTrack ? "waveform" : "waveform.badge.plus")
            .contentTransition(.symbolEffect(.replace))
    }
    }

    @ViewBuilder private var togetherButton: some View {
    if advanced {
        Button { store.unlock(.performer, "Play Together") { showTogether = true } } label: {
            Label("Play Together", systemImage: "person.2.wave.2")
                .symbolRenderingMode(.palette)
                .foregroundStyle(BarStyle.glyph(together.connected))
                .symbolVariant(together.connected ? .fill : .none)
        }
        .help("Play in time with another device")
    }
    }

    @ViewBuilder private var editButton: some View {
    if advanced || item.created == true {
        Button {
            transport.pause()
            openEditor()
        } label: {
            Label("Edit Score", systemImage: "music.quarternote.3")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(BarStyle.glyph())
        }
        .foregroundStyle(BarStyle.glyph())
        .help("Change the notes with Apple Pencil")
    }
    }

    @ViewBuilder private var lyricsMenu: some View {
    Menu {
        if lyricsDoc != nil {
            Toggle("Show Lyrics Instead of Music", systemImage: "quote.bubble", isOn: $showLyrics.animation(.smooth))
            Group {   // only lyrics timed word by word can fill and swell
                Toggle("Animate Syllables", systemImage: "textformat.size", isOn: $lyricsAnimate.animation(.smooth))
                Toggle("Show Syllable Progress", systemImage: "text.line.first.and.arrowtriangle.forward", isOn: $lyricsProgress)
            }
            .disabled(lyricsDoc?.wordTimed == false)
            if !item.isPDF, item.lyrics != nil { Toggle("Words Under the Notes", systemImage: "text.below.photo", isOn: $lyricsInline) }
            if library.canEditLyrics(item) { Button("Edit Lyrics…", systemImage: "pencil") { editingLyrics = true } }
            if item.lyrics != nil { Button("Assign Singers…", systemImage: "person.2") { assigningSingers = true } }
            if let lyricsDoc { SingerFilter(doc: lyricsDoc, part: $onlyPart) }
        }
        Button(item.lyrics == nil ? String(localized: "Add Lyrics File…") : String(localized: "Replace Lyrics File…"), systemImage: "text.badge.plus") { pickingLyrics = true }
        Button("Search for Lyrics Online…", systemImage: "magnifyingglass") { store.unlock(.performer, "Finding lyrics online") { pickingLyricsOnline = true } }
        if item.lyrics != nil {
            Button("Remove Lyrics File", systemImage: "trash", role: .destructive) { library.removeLyrics(item); showLyrics = false }
        }
    } label: {
        Label("Lyrics", systemImage: showLyrics ? "quote.bubble.fill" : "quote.bubble")
            .foregroundStyle(BarStyle.glyph(showLyrics))
            .symbolVariant(showLyrics ? .fill : .none)
    }
    .help("Show the words, Apple Music style, or add a lyrics file (.lrc or .txt)")
    }

    @ViewBuilder private var annotateButton: some View {
    ToolbarToggle(title: "Annotate", symbol: "pencil.tip.crop.circle", isOn: store.gate(.performer, "Annotation", $annotations.active))
        .help("Draw on the sheet music with Apple Pencil")
    }

    private func load() async {
        await Transport.activateSession()
        let url = library.scoreURL(item), transpose = sheetShift, zoom = zoom
        let words = lyricsInline ? inlineWords() : []
        let sheetTitle = item.sheetTitle
        do {
            var bpb = item.beatsPerBar
            let loaded: LoadedScore
            if item.isPDF {
                let source: LoadedScore
                if let pdfSource { source = pdfSource } else {
                    source = try await Task.detached(priority: .userInitiated) { try ScoreLoader.load(url, beatsPerBar: 4) }.value
                    pdfSource = source
                }
                // First open of a PDF: take the metre its note values add up to. Later edits in the inspector win.
                if item.meterDetected != true, let m = source.detectedBeatsPerBar {
                    var updated = item
                    updated.beatsPerBar = m
                    updated.meterDetected = true
                    library.save(updated)
                    bpb = m
                } else if item.meterDetected != true {
                    // The page didn't say: every bar needs a length, so ask.
                    askMetre = true
                }
                // The page read as MusicXML, saved with the score. The original key shows the PDF itself;
                // any other key engraves the music read from it.
                let xml = library.convertedURL(item), title = item.title, metre = bpb
                loaded = try await Task.detached(priority: .userInitiated) {
                    try source.musicXML(beatsPerBar: metre, title: title).write(to: xml)
                    return transpose == 0 && zoom == 1 && words.isEmpty ? source : try ScoreLoader.load(xml, beatsPerBar: metre, transpose: transpose, zoom: zoom, lyrics: words)
                }.value
            } else {
                loaded = try await Task.detached(priority: .userInitiated) { try ScoreLoader.load(url, beatsPerBar: 4, transpose: transpose, zoom: zoom, lyrics: words, sheetTitle: sheetTitle) }.value
            }
            let engraved = loaded.timeline(beatsPerBar: bpb)
            baseTimeline = engraved
            // Tempo marks change the pace of the built-in instrument; a recording keeps its own tempo.
            transport.timeline = library.trackURL(item) == nil && item.ignoreTempoMarks != true ? engraved.warped() : engraved
            defer { refreshLyrics() }
            annotations.load(from: library.folder(item).appending(path: "annotations\(transpose)-\(Int(zoom * 100)).plist"))
            if score == nil {   // a re-engrave in a new key keeps playing
                // The score's own tempo, unless you set one of your own.
                let fresh = loaded.tempo.map { library.adoptScoreTempo($0, for: item) } ?? item
                transport.tempo = fresh.tempo
                transport.offset = item.offset
                transport.trackSemitones = item.trackSemitones
                transport.trackGainDB = item.trackGainDB ?? 0
                transport.trackEQ = item.trackEQ
                transport.instrumentGainDB = item.instrumentGainDB ?? 0
                transport.automation = library.trackEdit(item)
                transport.setTrack(library.trackURL(item))
                transport.leadInBars = item.leadIn ?? 0
            }
            withAnimation(.spring(duration: 0.8, bounce: 0.18)) { score = loaded }
            #if DEBUG
            if CommandLine.arguments.contains("-inspector") { showInspector = true }
            if CommandLine.arguments.contains("-chords") { showChords = true }
            if CommandLine.arguments.contains("-looptest") {
                Task {
                    let ms = transport.timeline.measures
                    transport.loop = ms[1].start..<ms[2].end
                    transport.seek(to: ms[1].start); transport.play()
                    var log = "loop \(ms[1].start)..<\(ms[2].end)\n", wraps = 0, last = 0.0, top = 0.0
                    for _ in 0..<200 {
                        try? await Task.sleep(for: .milliseconds(50))
                        if transport.beat < last - 1 { wraps += 1 }
                        last = transport.beat; top = max(top, last)
                    }
                    log += "wraps \(wraps) max beat \(top)\n"
                    try? log.write(toFile: "/tmp/loop-test.txt", atomically: true, encoding: .utf8)
                }
            }
            if CommandLine.arguments.contains("-pageturnplay") { Task { try? await Task.sleep(for: .seconds(4)); if let m = transport.timeline.measures.last(where: { transport.timeline.systems[$0.system].page == 0 }) { transport.countInEnabled = false; transport.seek(to: m.start); transport.play() } } }
            if CommandLine.arguments.contains("-pageturn") { Task { try? await Task.sleep(for: .seconds(4)); if let m = transport.timeline.measures.last(where: { transport.timeline.systems[$0.system].page == 1 })?.start { transport.seek(to: m) } } }
            if CommandLine.arguments.contains("-extratest") {
                Task {
                    if var it = library.items.first(where: { $0.id == item.id }) {
                        if it.track == nil { it = (try? library.importTrack(from: URL(filePath: "/tmp/t1.wav"), for: it)) ?? it }
                        if (it.extraTracks ?? []).isEmpty { _ = try? library.addExtraTrack(from: URL(filePath: "/tmp/t2.wav"), for: it) }
                    }
                    try? await Task.sleep(for: .seconds(2))
                    transport.play()
                    try? await Task.sleep(for: .seconds(3))
                    let s = "playing \(transport.isPlaying) beat \(transport.beat) tracks \(transport.hasAnyTrack)"
                    try? s.write(toFile: "/tmp/extra-test.txt", atomically: true, encoding: .utf8)
                    transport.pause()
                }
            }
            if CommandLine.arguments.contains("-recordtest") { Task { try? await Task.sleep(for: .seconds(1)); startRecording(); try? await Task.sleep(for: .seconds(9)); recorder.stop() } }
            if CommandLine.arguments.contains("-reviewtest") { Task { try? await Task.sleep(for: .seconds(1)); makeTestTake() } }
            if CommandLine.arguments.contains("-practice") { Task { await practice.begin(transport) } }
            if CommandLine.arguments.contains("-editscore") { editingScore = true }
            if CommandLine.arguments.contains("-edittrack") { editingTrack = true }
            if CommandLine.arguments.contains("-annotate") { annotations.active = true }
            if CommandLine.arguments.contains("-autoplay") { Task { try? await Task.sleep(for: .seconds(1)); transport.play() } } // screenshot hook
            #endif
        } catch {
            withAnimation(.smooth) { failure = error.localizedDescription }
        }
    }

    /// The words to show: a lyrics file attached to the score, or the syllables written under its notes.
    /// The chart for the chord view: the score as parsed, moved to the key shown.
    private func loadChords() async {
        let url = item.isPDF ? library.convertedURL(item) : library.scoreURL(item), shift = sheetShift
        guard FileManager.default.fileExists(atPath: url.path) else {
            chordModel = nil; chordMessage = String(localized: "The notes of this PDF have not been read yet. Open the score and let it finish reading.")
            return
        }
        do {
            let parsed = try await Task.detached(priority: .userInitiated) { try MusicXML.parse(MusicXML.data(from: url)).transposed(by: shift) }.value
            chordModel = ChordChartModel(parsed)
        } catch { chordModel = nil; chordMessage = error.localizedDescription }
    }

    /// The words of the lyrics file, one syllable at a time, to print under the notes.
    private func inlineWords() -> [LyricSyllable] {
        guard let url = library.lyricsURL(item), let d = try? Lyrics.document(from: url, duration: nil) else { return [] }
        return d.lines.flatMap(\.syllables)
    }

    private func refreshLyrics() {
        if let url = library.lyricsURL(item), let d = try? Lyrics.document(from: url, duration: transport.trackDuration) {
            lyricsDoc = d.isEmpty ? nil : d.withSingers(library.singers(item))
            lyricsInSeconds = true
        } else {
            let d = Lyrics.fromScore(transport.timeline.notes)
            lyricsDoc = d.isEmpty ? nil : d
            lyricsInSeconds = false
        }
        if lyricsDoc == nil { showLyrics = false }
        #if DEBUG
        if CommandLine.arguments.contains("-showlyrics"), lyricsDoc != nil { showLyrics = true }
        #endif
    }

    #if DEBUG
    /// Two-simulator test: one hosts, one joins, the host plays, and each logs where it is against the shared clock.
    private func syncTestHooks() {
        let args = CommandLine.arguments
        if args.contains("-togetherHost") { together.host() }
        if args.contains("-togetherJoin") { together.browse() }
        guard let i = args.firstIndex(of: "-synclog"), i + 1 < args.count else { return }
        let path = args[i + 1]
        try? "".write(toFile: path, atomically: true, encoding: .utf8)
        Task {
            var n = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                n += 1
                if n % 40 == 0 { try? "mode \(together.mode) connected \(together.connected) nearby \(together.nearby.map(\.displayName)) status \(together.status) acc \(String(describing: together.accuracy)) offset \(together.offset)".write(toFile: path + ".status", atomically: true, encoding: .utf8) }
                guard transport.isPlaying, let h = FileHandle(forWritingAtPath: path) else { continue }
                h.seekToEndOfFile()
                h.write(Data("\(CACurrentMediaTime()) \(transport.beat) \(transport.barPosition(transport.beat)) \(transport.tempo)\n".utf8))
                try? h.close()
            }
        }
        if args.contains("-syncplay") {
            Task {
                while !together.connected { try? await Task.sleep(for: .milliseconds(200)) }
                try? await Task.sleep(for: .seconds(2))
                transport.play()
            }
        }
    }
    #endif

    /// Playing clears the stage: the library slides away and comes back when you stop.
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

// MARK: - Pages

private struct PageLayout {
    static let gap: CGFloat = 32, top: CGFloat = 28, intro: CGFloat = 120
    let width: CGFloat
    let heights: [CGFloat]
    let scales: [CGFloat]

    init(pages: [CGPDFPage], width: CGFloat) {
        self.width = width
        scales = pages.map { width / $0.size.width }
        heights = pages.map { width * $0.size.height / $0.size.width }
    }

    var introHeight: CGFloat = 0
    func top(of page: Int) -> CGFloat { Self.top + introHeight + heights.prefix(page).reduce(0, +) + CGFloat(page) * Self.gap }
}

// MARK: - Turning pages like a book

/// One page at a time, turned with a real page curl when playback (or you) moves to another page.
struct PagedScore: View {
    let score: LoadedScore
    let transport: Transport
    let annotations: AnnotationStore
    let follow: Bool
    @Binding var page: Int
    let guides: Guides
    let dark: Bool
    let tint: Color
    let inkTint: Color
    @AppStorage("reduceMotion") private var reduceMotionSetting = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let timeline = transport.timeline   // read here so a new key or zoom redraws the pages
        let intro = transport.leadInBars > 0
        GeometryReader { geo in
            // The whole page fits: its width, or its height with room for the floating bar and the lead-in strip.
            let aspect = score.pages.first.map { $0.size.width / $0.size.height } ?? 0.77
            let room = geo.size.height - PageLayout.top - 150 - (intro ? PageLayout.intro + 6 : 0)
            let layout = PageLayout(pages: score.pages, width: max(200, min(geo.size.width - 48, 1040, room * aspect)))
            PageCurl(count: score.pages.count, index: $page, swipe: !annotations.active, animated: !(reduceMotionSetting || systemReduceMotion), fast: transport.isPlaying) { i in
                AnyView(
                    VStack(spacing: 6) {
                        if i == 0, intro {
                            IntroStaff(transport: transport, tint: tint, guides: guides, dark: dark)
                                .frame(width: layout.width, height: PageLayout.intro)
                        }
                        PageView(page: score.pages[i], index: i, scale: layout.scales[i], timeline: timeline, transport: transport, annotations: annotations, tint: tint, inkTint: inkTint, guides: guides, dark: dark)
                            .frame(width: layout.width, height: layout.heights[i])
                    }
                    .padding(.top, PageLayout.top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                )
            }
            .background { PageWatcher(transport: transport, enabled: follow) { page = $0 } }
        }
    }
}

/// Tells the book which page the music has reached.
private struct PageWatcher: View {
    let transport: Transport
    let enabled: Bool
    let turn: (Int) -> Void

    var body: some View {
        let t = transport.timeline
        let page: Int? = transport.beat < 0 ? 0 : t.measureIndex(at: max(0, transport.beat)).map { t.systems[t.measures[$0].system].page }
        Color.clear
            .onChange(of: page) { _, new in if enabled, let new { turn(new) } }
            .onChange(of: enabled) { _, on in if on, let page { turn(page) } }
    }
}

private final class PageHost: UIHostingController<AnyView> {
    var number = 0
}

/// A UIPageViewController with the curl transition, showing one page at a time. It turns when `index` changes, and writes
/// the page back to `index` when the reader turns it by dragging.
private struct PageCurl: UIViewControllerRepresentable {
    let count: Int
    @Binding var index: Int
    let swipe: Bool
    let animated: Bool
    /// While the music plays the page turns three times as fast, so it is out of the way by the next bar.
    let fast: Bool
    let content: (Int) -> AnyView

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let c = context.coordinator
        let pvc = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
                                       options: [.spineLocation: NSNumber(value: UIPageViewController.SpineLocation.min.rawValue)])
        pvc.isDoubleSided = false
        pvc.dataSource = c
        pvc.delegate = c
        pvc.view.backgroundColor = .clear
        c.shown = max(0, min(index, count - 1))
        pvc.setViewControllers([c.host(c.shown)], direction: .forward, animated: false)
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        let c = context.coordinator
        c.parent = self
        for (i, h) in c.hosts { h.rootView = content(i) }
        for g in pvc.gestureRecognizers { g.isEnabled = swipe && !(g is UITapGestureRecognizer) }   // taps on the page belong to the music
        c.go(pvc)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurl
        var hosts: [Int: PageHost] = [:]
        var shown = 0
        private var busy = false
        init(_ parent: PageCurl) { self.parent = parent }

        func host(_ i: Int) -> PageHost {
            if let h = hosts[i] { return h }
            let h = PageHost(rootView: parent.content(i))
            h.number = i
            h.view.backgroundColor = .clear
            h.safeAreaRegions = []
            hosts[i] = h
            return h
        }

        /// Turns to the page the app asked for, one turn at a time.
        func go(_ pvc: UIPageViewController) {
            let target = max(0, min(parent.index, parent.count - 1))
            guard target != shown, !busy else { return }
            let forward = target > shown
            shown = target
            busy = true
            pvc.view.layer.speed = parent.fast ? 3 : 1.8   // quick and snappy
            #if DEBUG
            let t0 = CACurrentMediaTime(), wasFast = parent.fast
            #endif
            pvc.setViewControllers([host(target)], direction: forward ? .forward : .reverse, animated: parent.animated) { [weak self, weak pvc] _ in
                pvc?.view.layer.speed = 1
                #if DEBUG
                let l = (try? String(contentsOfFile: "/tmp/turn-time.txt", encoding: .utf8)) ?? ""
                try? (l + "fast=\(wasFast) \(CACurrentMediaTime() - t0)\n").write(toFile: "/tmp/turn-time.txt", atomically: true, encoding: .utf8)
                #endif
                self?.busy = false
                if let pvc { self?.go(pvc) }   // asked for another page meanwhile
            }
        }

        func pageViewController(_ pvc: UIPageViewController, viewControllerBefore vc: UIViewController) -> UIViewController? {
            guard let i = (vc as? PageHost)?.number, i > 0 else { return nil }
            return host(i - 1)
        }
        func pageViewController(_ pvc: UIPageViewController, viewControllerAfter vc: UIViewController) -> UIViewController? {
            guard let i = (vc as? PageHost)?.number, i + 1 < parent.count else { return nil }
            return host(i + 1)
        }
        func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            guard completed, let h = pvc.viewControllers?.first as? PageHost else { return }
            shown = h.number
            parent.index = h.number
        }
    }
}

struct ScorePages: View {
    let score: LoadedScore
    let transport: Transport
    let annotations: AnnotationStore
    let follow: Bool
    @Binding var zoom: Double
    @State private var pinch = 1.0
    let guides: Guides
    let dark: Bool
    let tint: Color
    let inkTint: Color
    @State private var scroller = Scroller()

    var body: some View {
        let timeline = transport.timeline
        GeometryReader { geo in
            var layout = PageLayout(pages: score.pages, width: max(200, min(geo.size.width - 48, 1040)))
            let _ = transport.leadInBars > 0 ? layout.introHeight = PageLayout.intro + PageLayout.gap / 2 : ()
            ScrollView {
                VStack(spacing: PageLayout.gap) {
                    if transport.leadInBars > 0 {
                        IntroStaff(transport: transport, tint: tint, guides: guides, dark: dark)
                            .frame(width: layout.width, height: PageLayout.intro)
                            .padding(.bottom, -PageLayout.gap / 2)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    ForEach(score.pages.indices, id: \.self) { i in
                        PageView(page: score.pages[i], index: i, scale: layout.scales[i], timeline: timeline, transport: transport, annotations: annotations, tint: tint, inkTint: inkTint, guides: guides, dark: dark)
                            .frame(width: layout.width, height: layout.heights[i])
                    }
                }
                .padding(.top, PageLayout.top)
                .padding(.bottom, PageLayout.top + 150)   // room to scroll the last system up clear of the floating bar
                .frame(maxWidth: .infinity)
                .scaleEffect(pinch, anchor: .top)
                .animation(.spring(duration: 0.5, bounce: 0.15), value: transport.leadInBars)
                .background { ScrollFinder(scroller: scroller) }
            }
            .simultaneousGesture(MagnifyGesture()
                .onChanged { pinch = max(0.6 / zoom, min(2.5 / zoom, $0.magnification)) }   // a preview; the bars reflow on release
                .onEnded { _ in
                    zoom = max(0.6, min(2.5, (zoom * pinch * 20).rounded() / 20))
                    pinch = 1
                })
            .background {
                Follower(transport: transport, layout: layout, viewport: geo.size.height, enabled: follow, scroller: scroller)
            }
        }
    }
}

/// Scrolls the score's scroll view to a height. (SwiftUI's own ScrollPosition needs iOS 18, so this reaches the UIScrollView.)
final class Scroller {
    weak var view: UIScrollView?

    func scroll(toY y: CGFloat) {
        guard let v = view else { return }
        let inset = v.adjustedContentInset
        let target = min(max(y - inset.top, -inset.top), max(-inset.top, v.contentSize.height - v.bounds.height + inset.bottom))
        UIView.animate(withDuration: 0.9, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            v.contentOffset = CGPoint(x: v.contentOffset.x, y: target)
        }
    }
}

/// Put inside a ScrollView's content: finds the UIScrollView around it.
struct ScrollFinder: UIViewRepresentable {
    let scroller: Scroller

    final class Finder: UIView {
        var scroller: Scroller?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var v = superview
            while let s = v, !(s is UIScrollView) { v = s.superview }
            scroller?.view = v as? UIScrollView
        }
    }

    func makeUIView(context: Context) -> Finder { let f = Finder(); f.scroller = scroller; f.isUserInteractionEnabled = false; return f }
    func updateUIView(_ f: Finder, context: Context) {}
}

/// Watches the playing system and glides the page so it sits near the top.
private struct Follower: View {
    let transport: Transport
    let layout: PageLayout
    let viewport: CGFloat
    let enabled: Bool
    let scroller: Scroller

    var body: some View {
        let t = transport.timeline
        // The intro sits above page 1: −1 scrolls to the top.
        let system = transport.beat < 0 && transport.leadInBars > 0 ? -1 : t.measureIndex(at: max(0, transport.beat)).map { t.measures[$0].system }
        Color.clear
            .onChange(of: system) { _, s in scroll(to: s) }
            .onChange(of: enabled) { _, on in if on { scroll(to: system) } }
    }

    private func scroll(to s: Int?) {
        guard enabled, let s, s < transport.timeline.systems.count else { return }
        if s < 0 { scroller.scroll(toY: 0); return }
        let sys = transport.timeline.systems[s]
        let y = layout.top(of: sys.page) + sys.rect.minY * layout.scales[sys.page] - viewport * 0.14
        scroller.scroll(toY: max(0, y))
    }
}

private struct PageView: View {
    let page: CGPDFPage
    let index: Int
    let scale: CGFloat
    let timeline: Timeline
    let transport: Transport
    let annotations: AnnotationStore
    let tint: Color
    let inkTint: Color
    let guides: Guides
    let dark: Bool
    @State private var appeared = false
    @State private var ripple: (point: CGPoint, id: Int)?
    @State private var ink: CGImage?
    @AppStorage("reduceMotion") private var reduceMotionSetting = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let notes = timeline.notes.filter { $0.page == index }
        let marks = timeline.measures.filter { timeline.systems[$0.system].page == index }.map { ($0, timeline.systems[$0.system].rect) }
        PageCanvas(page: page, dark: dark)
            .clipShape(RoundedRectangle(cornerRadius: PaperSheet.radius, style: .continuous))
            .background { PaperSheet(dark: dark) }
            .overlay {
                PageOverlay(notes: notes, marks: marks, transport: transport, scale: scale, tint: tint, inkTint: inkTint, guides: guides, dark: dark, ink: ink)
            }
            .overlay { AnnotationLayer(store: annotations, page: index, scale: scale, active: annotations.active) }
            .overlay { if let ripple { Ripple(tint: tint).position(ripple.point).id(ripple.id) } }
            .contentShape(.rect)
            .onTapGesture { p in seek(at: p, notes: notes, marks: marks) }
            .task(id: "\(scale) \(ObjectIdentifier(page).hashValue)") {   // a transpose brings new pages
                let page = page, width = Int(page.size.width * scale * 2)
                ink = await Task.detached(priority: .utility) { inkMask(page, pixelWidth: width) }.value
            }
            .opacity(appeared || index > 0 ? 1 : 0)   // only the opening page rises in; a page being turned to is simply there behind the curl
            .offset(y: appeared || index > 0 || reduceMotionSetting || systemReduceMotion ? 0 : 40)
            .onAppear {
                if reduceMotionSetting || systemReduceMotion { appeared = true; return }
                withAnimation(.spring(duration: 0.9, bounce: 0.2).delay(Double(min(index, 4)) * 0.08)) { appeared = true }
            }
            .accessibilityElement()
            .accessibilityLabel("Page \(index + 1)")
            .accessibilityHint("Tap a note to start from there.")
    }

    private func seek(at p: CGPoint, notes: [NoteEvent], marks: [(MeasureMark, CGRect)]) {
        if annotations.active { return }   // taps belong to the pencil
        let q = CGPoint(x: p.x / scale, y: p.y / scale)
        let nearest = notes.filter { !$0.isRest }.min { hypot($0.rect.midX - q.x, $0.rect.midY - q.y) < hypot($1.rect.midX - q.x, $1.rect.midY - q.y) }
        if let n = nearest, hypot(n.rect.midX - q.x, n.rect.midY - q.y) < 24 {
            transport.seek(to: n.start)
        } else if let m = marks.first(where: { $0.1.contains(q) && q.x >= $0.0.x0 && q.x <= $0.0.x1 }) {
            transport.seek(to: m.0.start)
        } else { return }
        ripple = (p, (ripple?.id ?? 0) + 1)
    }
}

struct PageCanvas: View {
    let page: CGPDFPage
    var dark = false
    var body: some View {
        let canvas = Canvas { ctx, size in ctx.withCGContext { page.draw(in: $0, size: size) } }
        // Light paper multiplies in, so a photographed page's white takes the paper colour instead of covering it.
        if dark { canvas.colorInvert() } else { canvas.blendMode(.multiply) }
    }
}

/// The page's paper, cream or black, lifted off the stage.
struct PaperSheet: View {
    static let radius: CGFloat = 8
    let dark: Bool
    @AppStorage(Surfaces.masterKey) private var master = true
    @AppStorage(Surfaces.shadeKey) private var shadeSetting = 1.0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        // How much the page curves into its binding and how deep its shadows fall.
        let shade = master ? shadeSetting : 0.35
        shape.fill(Theme.paper(dark: dark))
            // Fibre in the paper, and the page curving down into the binding on the left.
            .overlay { Grain(kind: .grain, opacity: dark ? 0.35 : 0.16, role: .paper).clipShape(shape) }
            .overlay { shape.fill(LinearGradient(colors: [.black.opacity((dark ? 0.4 : 0.16) * shade), .clear], startPoint: .leading, endPoint: .init(x: 0.07, y: 0.5))) }
            .overlay { shape.fill(LinearGradient(colors: [.clear, .black.opacity((dark ? 0.2 : 0.06) * shade)], startPoint: .init(x: 0.5, y: 0.9), endPoint: .bottom)) }
            .overlay { shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.12 : 0.8), .black.opacity(dark ? 0.4 : 0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75) }
            .shadow(color: .black.opacity(0.5 * min(1, shade + 0.3)), radius: 2.5, y: 1.5)
            .shadow(color: .black.opacity(0.4 * shade), radius: 9, y: 6)
            .shadow(color: .black.opacity(0.35 * shade), radius: 30, y: 20)
            .animation(.smooth(duration: 0.4), value: dark)
    }
}

private struct Ripple: View {
    let tint: Color
    @State private var go = false
    var body: some View {
        Circle()
            .stroke(tint, lineWidth: 2)
            .frame(width: 60, height: 60)
            .scaleEffect(go ? 1.6 : 0.2)
            .opacity(go ? 0 : 0.9)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeOut(duration: 0.6)) { go = true } }
    }
}

// MARK: - Highlights and playhead

private struct PageOverlay: View {
    let notes: [NoteEvent]
    let marks: [(MeasureMark, CGRect)]
    let transport: Transport
    let scale: CGFloat
    let tint: Color
    let inkTint: Color
    let guides: Guides
    let dark: Bool
    let ink: CGImage?

    var body: some View {
        let beat = transport.beat
        let review = transport.review
        let active = review != nil ? [] : notes.filter { !$0.isRest && beat >= $0.start && beat < $0.end }
        // Reviewing a recording: green for where the score was and what was played right, red for what was played wrong.
        let greens = review.map { r in notes.filter { r.green.contains($0.id) } } ?? []
        let reds = review.map { r in notes.filter { r.red.contains($0.id) } } ?? []
        let focused = transport.focus.isEmpty ? [] : notes.filter { transport.focus.contains($0.id) }
        let current = marks.firstIndex { beat >= $0.0.start && beat < $0.0.end }

        ZStack(alignment: .topLeading) {
            if let current {
                let (m, sys) = marks[current]
                if guides.bar {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity((dark ? 0.16 : 0.13) * (Palette.shared.highContrast ? 2.2 : 1)))
                        .blendMode(dark ? .plusLighter : .multiply)
                        .frame(width: (m.x1 - m.x0) * scale, height: sys.height * scale)
                        .offset(x: m.x0 * scale, y: sys.minY * scale)
                        .id(current)   // snap to the barlines and crossfade; a slide lags behind the bar
                        .transition(.opacity.animation(.easeOut(duration: 0.2)))
                }
                if guides.line {
                    Playhead(tint: tint, height: sys.height * scale)
                        .offset(x: m.x(at: beat) * scale - 6, y: sys.minY * scale)
                        .transition(.opacity)
                }
            }
            // The words under the notes being played, lit while they are sung.
            ForEach(active.filter { $0.lyricRect != nil }) { n in
                let r = n.lyricRect!
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(dark ? 0.5 : 0.55))
                    .blendMode(dark ? .plusLighter : .multiply)
                    .frame(width: r.width * scale, height: r.height * scale)
                    .offset(x: r.minX * scale, y: r.minY * scale)
            }
            if review != nil, let ink {
                lightLayer(greens, color: dark ? Color(red: 0.35, green: 0.95, blue: 0.5) : Color(red: 0.0, green: 0.62, blue: 0.22), ink: ink)
                lightLayer(reds, color: dark ? Color(red: 1.0, green: 0.4, blue: 0.36) : Color(red: 0.88, green: 0.1, blue: 0.1), ink: ink)
            }
            if !focused.isEmpty, let ink {   // the places a written review is pointing at
                lightLayer(focused, color: dark ? Color(red: 0.45, green: 0.7, blue: 1.0) : Color(red: 0.08, green: 0.38, blue: 0.95), ink: ink)
            }
            if guides.notes, let ink, review == nil {
                // The notes themselves change colour: tint, cut to the page's ink, cut to the sounding notes.
                Rectangle()
                    .fill(inkTint)
                    .mask { Image(decorative: ink, scale: 1).resizable().luminanceToAlpha() }
                    .mask {
                        ZStack(alignment: .topLeading) {
                            ForEach(active) { n in
                                let r = n.rect.insetBy(dx: n.rect.width * 0.12, dy: n.rect.height * 0.16)
                                NoteLight()
                                    .frame(width: r.width * scale, height: r.height * scale)
                                    .offset(x: r.minX * scale, y: r.minY * scale)
                                    .transition(.opacity)
                                if let st = n.stem {
                                    NoteLight()
                                        .frame(width: st.width * scale, height: st.height * scale)
                                        .offset(x: st.minX * scale, y: st.minY * scale)
                                        .transition(.opacity)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .animation(.easeOut(duration: 0.1), value: active.map(\.id))   // crisp release, no muddy fade
                    }
                    .shadow(color: tint.opacity(0.7), radius: 4)   // glow hugs the notehead shape
                    .shadow(color: tint.opacity(0.35), radius: 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.smooth(duration: 0.3), value: guides)
        .allowsHitTesting(false)
    }
}

extension PageOverlay {
    /// The given notes in a colour, cut out of the page's ink so the glyphs themselves change colour.
    fileprivate func lightLayer(_ lit: [NoteEvent], color: Color, ink: CGImage) -> some View {
        Rectangle()
            .fill(color)
            .mask { Image(decorative: ink, scale: 1).resizable().luminanceToAlpha() }
            .mask {
                ZStack(alignment: .topLeading) {
                    ForEach(lit) { n in
                        let r = n.rect.insetBy(dx: n.rect.width * 0.12, dy: n.rect.height * 0.16)
                        NoteLight()
                            .frame(width: r.width * scale, height: r.height * scale)
                            .offset(x: r.minX * scale, y: r.minY * scale)
                        if let st = n.stem {
                            NoteLight().frame(width: st.width * scale, height: st.height * scale).offset(x: st.minX * scale, y: st.minY * scale)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .shadow(color: color.opacity(0.7), radius: 4)
            .shadow(color: color.opacity(0.35), radius: 12)
    }
}

/// Mask piece for one sounding note: snaps on with a brief overshoot so the attack reads.
private struct NoteLight: View {
    @State private var lit = false
    var body: some View {
        Rectangle()
            .opacity(lit ? 1 : 0)
            .onAppear { withAnimation(.easeOut(duration: 0.08)) { lit = true } }
    }
}

/// The page's ink as an alpha mask, with thin horizontal rules (staff lines, beams' edges) removed
/// so only notes take the highlight colour.
nonisolated func inkMask(_ page: CGPDFPage, pixelWidth w: Int) -> CGImage? {
    guard w > 0 else { return nil }
    let h = Int(CGFloat(w) * page.size.height / page.size.width)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
    ctx.setFillColor(gray: 1, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    page.draw(in: ctx, size: CGSize(width: w, height: h))
    let gray = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
    var alpha = [UInt8](repeating: 0, count: w * h)
    let gap = max(2, w / 500)   // a staff line is thinner than this
    for y in 0..<h {
        for x in 0..<w {
            let v = 255 - Int(gray[y * w + x])
            guard v > 0 else { continue }
            let above = y >= gap ? gray[(y - gap) * w + x] > 200 : true
            let below = y + gap < h ? gray[(y + gap) * w + x] > 200 : true
            alpha[y * w + x] = above && below ? 0 : UInt8(v)
        }
    }
    return alpha.withUnsafeMutableBytes { buf in
        CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
    }
}

private struct Playhead: View {
    let tint: Color
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 9))
                .foregroundStyle(tint)
            Capsule()
                .fill(tint)
                .frame(width: 2.5, height: max(0, height - 10))
                .shadow(color: tint, radius: 4)
                .shadow(color: tint.opacity(0.5), radius: 14)
        }
        .frame(width: 12)
    }
}

// MARK: - Intro

/// The lead-in bars, engraved as rest bars on a strip of paper above page 1, with the same wash and playhead.
private struct IntroStaff: View {
    let transport: Transport
    let tint: Color
    let guides: Guides
    let dark: Bool

    var body: some View {
        let bars = transport.leadInBars, fg = dark ? Color.white : Color.black, L = transport.leadBar
        let beat = transport.beat, from = transport.start
        let current = beat >= from && beat < 0 ? min(bars - 1, Int((beat - from) / L)) : nil
        GeometryReader { g in
            let sp: CGFloat = 8, top = (g.size.height - 4 * sp) / 2 + 6
            let left: CGFloat = 78, w = (g.size.width - left - 28) / CGFloat(max(bars, 1))
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let ink = GraphicsContext.Shading.color(fg.opacity(0.82))
                    for i in 0..<5 {
                        ctx.fill(Path(CGRect(x: left - 12, y: top + CGFloat(i) * sp, width: size.width - 28 - left + 12, height: 0.9)), with: ink)
                    }
                    for k in 0...bars {
                        ctx.fill(Path(CGRect(x: left + CGFloat(k) * w - (k == bars ? 0.6 : 0), y: top, width: 1.2, height: 4 * sp)), with: ink)
                        guard k < bars else { continue }
                        // Whole rest hanging from the fourth line, and the bar number counting to 1.
                        ctx.fill(Path(CGRect(x: left + (CGFloat(k) + 0.5) * w - 0.7 * sp, y: top + sp, width: 1.4 * sp, height: 0.55 * sp)), with: ink)
                        ctx.draw(Text("−\(bars - k)").font(.system(size: 10, weight: .medium, design: .serif).italic()).foregroundStyle(fg.opacity(0.55)),
                                 at: CGPoint(x: left + CGFloat(k) * w + 4, y: top - 9), anchor: .leading)
                    }
                    ctx.draw(Text("INTRO").font(.system(size: 11, weight: .semibold)).tracking(1.5).foregroundStyle(fg.opacity(0.5)),
                             at: CGPoint(x: 18, y: top + 2 * sp), anchor: .leading)
                }
                if let current {
                    if guides.bar {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(tint.opacity(dark ? 0.16 : 0.13))
                            .blendMode(dark ? .plusLighter : .multiply)
                            .frame(width: w, height: 4 * sp + 28)
                            .offset(x: left + CGFloat(current) * w, y: top - 14)
                            .id(current)
                            .transition(.opacity.animation(.easeOut(duration: 0.2)))
                    }
                    if guides.line {
                        Playhead(tint: tint, height: 4 * sp + 28)
                            .offset(x: left + CGFloat((beat - from) / L) * w - 6, y: top - 14)
                    }
                }
            }
        }
        .background { PaperSheet(dark: dark) }
        .contentShape(.rect)
        .onTapGesture { transport.seek(to: transport.start) }
        .accessibilityElement()
        .accessibilityLabel(bars == 1 ? String(localized: "Intro, 1 bar before bar 1") : String(localized: "Intro, \(bars) bars before bar 1"))
        .accessibilityHint("Tap to start from the intro.")
    }
}

// MARK: - Overlays

struct CountInOverlay: View {
    let transport: Transport

    var body: some View {
        ZStack {
            if let n = transport.countIn {
                Text("\(n)")
                    .font(.system(size: 120, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 210, height: 210)
                    .background(.ultraThinMaterial, in: .circle)
                    .overlay(Circle().strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
                    .shadow(color: Theme.accent.opacity(0.35), radius: 40)
                    .id(n)
                    .transition(.asymmetric(insertion: .scale(scale: 1.35).combined(with: .opacity),
                                            removal: .scale(scale: 0.6).combined(with: .opacity)))
            }
        }
        .animation(.spring(duration: 0.32, bounce: 0.3), value: transport.countIn)
        .allowsHitTesting(false)
        .accessibilityLabel(transport.countIn.map { String(localized: "Count in \($0)") } ?? "")
    }
}

struct ReadingView: View {
    let isPDF: Bool
    @State private var sweep = false

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 9) {
                ForEach(0..<5, id: \.self) { _ in Capsule().fill(.white.opacity(0.18)).frame(height: 1.5) }
            }
            .frame(width: 240)
            .overlay {
                LinearGradient(colors: [.clear, Theme.accent, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 70)
                    .offset(x: sweep ? 140 : -140)
                    .blendMode(.plusLighter)
            }
            .mask { VStack(spacing: 9) { ForEach(0..<5, id: \.self) { _ in Capsule().frame(height: 1.5) } }.frame(width: 240) }
            .overlay {
                VStack(spacing: 9) { ForEach(0..<5, id: \.self) { _ in Capsule().fill(.white.opacity(0.18)).frame(height: 1.5) } }.frame(width: 240)
            }
            Text(isPDF ? String(localized: "Reading staves and notes…") : "Engraving…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { sweep = true } }
    }
}

struct Notice: View {
    let text: String
    var body: some View {
        VStack {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.thinMaterial, in: .capsule)
                .padding(.top, 12)
            Spacer()
        }
    }
}

// MARK: - Inspector

private struct InspectorPanel: View {
    @Environment(Library.self) private var library
    let item: ScoreItem
    let transport: Transport
    let key: (fifths: Int, minor: Bool)?
    @Binding var highlight: String
    @Binding var follow: Bool
    @Binding var showPlayhead: Bool
    @Binding var noteGlow: Bool
    @Binding var barWash: Bool
    @Binding var darkPaper: Bool
    let pickTrack: () -> Void
    let pickExtra: () -> Void
    let pickMusic: () -> Void
    var staves: [String] = []
    @Namespace private var swatch
    @AppStorage("instrumentKey") private var instrumentKey = InstrumentKey.concert.rawValue
    @AppStorage("advancedMode") private var advanced = false
    let editTrack: () -> Void
    @State private var loopFrom = 1
    @State private var gated: (() -> Void)?
    @State private var sharedConverted: SharedFile?
    @State private var openTrack: String?
    @State private var loopTo = 4

    /// Bars are counted as they are played, from 1.
    private func setLoop(_ bars: (Int, Int)?) {
        let ms = transport.timeline.measures
        guard let bars, !ms.isEmpty else { transport.loop = nil; return }
        let a = max(0, min(bars.0, ms.count) - 1), b = max(a, min(bars.1, ms.count) - 1)
        transport.loop = ms[a].start..<ms[b].end
    }

    /// The tempo in the Inspector: setting it makes it your own (the score's tempo can be brought back with the switch under it).
    private var tempoBinding: Binding<Double> {
        Binding { library.items.first { $0.id == item.id }?.tempo ?? item.tempo } set: { t in
            library.setTempo(t, for: item)
            transport.tempo = t
        }
    }

    private var primaryEnabled: Binding<Bool> {
        Binding { library.items.first { $0.id == item.id }?.trackEnabled != false } set: { v in update { $0.trackEnabled = v ? nil : false } }
    }
    private func update(_ change: (inout ScoreItem) -> Void) {
        guard var cur = library.items.first(where: { $0.id == item.id }) else { return }
        change(&cur)
        library.save(cur)
    }
    private func updateExtra(_ id: UUID, _ change: (inout ExtraTrack) -> Void) {
        update { it in if let i = it.extraTracks?.firstIndex(where: { $0.id == id }) { change(&it.extraTracks![i]) } }
    }
    private func extra<V>(_ id: UUID, _ key: WritableKeyPath<ExtraTrack, V>) -> Binding<V> {
        Binding { library.items.first { $0.id == item.id }?.extraTracks?.first { $0.id == id }?[keyPath: key] ?? ExtraTrack(file: "", name: "")[keyPath: key] }
            set: { v in updateExtra(id) { $0[keyPath: key] = v } }
    }

    @State private var showEQ = false

    var body: some View {
        @Bindable var transport = transport
        Form {
            Panel("Tempo") {
                Stepper(value: tempoBinding, in: 20...300) {
                    LabeledContent("BPM") {
                        TempoField(tempo: tempoBinding, showsUnit: false)
                    }
                }
                .animation(.snappy, value: item.tempo)
                if let own = library.items.first(where: { $0.id == item.id })?.scoreTempo {
                    // The score's tempo is the default; your own is optional.
                    Toggle(isOn: Binding { library.items.first { $0.id == item.id }?.customTempo == true } set: { on in
                        if on { tempoBinding.wrappedValue = transport.tempo + (abs(transport.tempo - own) < 0.01 ? 1 : 0) }
                        else if let s = library.useScoreTempo(for: item) { transport.tempo = s }
                    }) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Custom Tempo")
                            Text(library.items.first { $0.id == item.id }?.customTempo == true ? String(localized: "The score says \(Int(own.rounded()))") : String(localized: "Using the score's \(Int(own.rounded()))")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Slider(value: Binding { tempoBinding.wrappedValue.rounded() } set: { v in
                    tempoBinding.wrappedValue = v.rounded()
                }, in: 20...300, step: 1)
                    .tint(Theme.accent)
                LabeledContent("Practice Speed") { PercentField(speed: $transport.speed) }
                Slider(value: $transport.speed, in: 0.5...1.5, step: 0.05) {
                    Text("Practice Speed")
                } minimumValueLabel: { Image(systemName: "tortoise") } maximumValueLabel: { Image(systemName: "hare") }
                .tint(Theme.accent)
                TapTempoButton(current: transport.tempo) { t in tempoBinding.wrappedValue = t }
                Toggle("Metronome", isOn: $transport.metronome)
                Toggle("Count In", isOn: $transport.countInEnabled)
                    .disabled(transport.hasTrack)
                if transport.hasTempoMarks, !transport.hasTrack {
                    Toggle("Ignore the Score’s Tempo Changes", isOn: Binding { bind(\.ignoreTempoMarks, apply: { _ in }).wrappedValue == true } set: { bind(\.ignoreTempoMarks, apply: { _ in }).wrappedValue = $0 ? true : nil })
                }
                if advanced {
                    NumberStepper(title: "Lead-in Bars", value: Binding { Double(bind(\.leadIn, apply: { _ in }).wrappedValue ?? 0) } set: { n in bind(\.leadIn, apply: { _ in }).wrappedValue = n < 1 ? nil : Int(n) }, range: 0...16)
                }
            } footer: {
                if advanced {
                    Text(transport.hasTrack ? String(localized: "Bars Before Bar 1 adds empty bars to the start; the backing track starts with the first of them, from the marker.")
                                            : String(localized: "Bars Before Bar 1 adds empty bars to the start, to count yourself in."))
                }
            }

            Panel("Loop") {
                let bars = transport.timeline.measures.count
                Toggle("Repeat a Section", isOn: Binding { transport.loop != nil } set: { setLoop($0 ? (loopFrom, loopTo) : nil) })
                if transport.loop != nil, bars > 1 {
                    NumberStepper(title: "From Bar", value: Binding { Double(min(loopFrom, bars)) } set: { loopFrom = Int($0); if loopTo < loopFrom { loopTo = loopFrom }; setLoop((loopFrom, loopTo)) }, range: 1...Double(bars))
                    NumberStepper(title: "To Bar", value: Binding { Double(min(loopTo, bars)) } set: { loopTo = Int($0); if loopFrom > loopTo { loopFrom = loopTo }; setLoop((loopFrom, loopTo)) }, range: 1...Double(bars))
                }
            } footer: {
                Text("Plays the chosen bars over and over, to practise a hard passage.")
            }

            if item.isPDF {
                Panel("Metre") {
                    NumberStepper(title: "Crotchet Beats per Bar", value: bind(\.beatsPerBar, apply: { _ in }), range: 1...12, step: 0.5, decimals: 1)
                } footer: {
                    if let q = transport.timeline.exactBars {
                        Text(q.exact == q.of
                             ? String(localized: "Rhythm read from the note values in all \(q.of) bars.")
                             : String(localized: "Rhythm read from the note values in \(q.exact) of \(q.of) bars. The rest (tuplets, unusual engraving) follow the printed spacing."))
                    }
                }
            }

            keySection

            Panel("Backing Tracks & Sound") {
                // One line for each track (its switch, and a button for its own settings), then what to add.
                let it = library.items.first { $0.id == item.id } ?? item
                if transport.hasTrack {
                    TrackLine(title: LocalizedStringKey(it.trackName ?? "Backing Track"), subtitle: nil, enabled: primaryEnabled, id: "first", open: $openTrack) {
                        GainRow(title: "Level", db: bind(\.trackGainDB, apply: { transport.trackGainDB = $0 ?? 0 }))
                        Toggle("Reduce Vocals", isOn: Store.shared.gate(.performer, "Reduce Vocals", Binding { it.reduceVocals == true } set: { v in update { $0.reduceVocals = v ? true : nil } }))
                        Button("Replace…", systemImage: "waveform.badge.plus") { openTrack = nil; pickTrack() }
                        Button("Remove", systemImage: "trash", role: .destructive) { openTrack = nil; library.removeTrack(item); transport.setTrack(nil) }
                    }
                }
                ForEach(it.extraTracks ?? []) { t in
                    TrackLine(title: LocalizedStringKey(t.name), subtitle: nil, enabled: extra(t.id, \.enabled), id: t.id.uuidString, open: $openTrack) {
                        GainRow(title: "Level", db: Binding { t.gainDB == 0 ? nil : t.gainDB } set: { v in updateExtra(t.id) { $0.gainDB = v ?? 0 } })
                        Toggle("Reduce Vocals", isOn: Store.shared.gate(.performer, "Reduce Vocals", extra(t.id, \.reduceVocals)))
                        Button("Remove", systemImage: "trash", role: .destructive) { openTrack = nil; library.removeExtraTrack(t.id, from: item) }
                    }
                }
                if let am = it.appleMusic {
                    TrackLine(title: LocalizedStringKey(am.title), subtitle: "\(am.artist) on Apple Music", enabled: Binding { am.enabled } set: { v in update { $0.appleMusic?.enabled = v } }, id: "music", open: $openTrack) {
                        NumberStepper(title: "Bar 1 Starts At", value: Binding { am.offset } set: { v in update { $0.appleMusic?.offset = v } }, range: 0...600, step: 0.5, decimals: 1, unit: " s")
                        if it.lyrics == nil { Button("Get the Lyrics", systemImage: "quote.bubble") { Task { _ = await library.fetchAppleMusicLyrics(for: item) } } }
                        Button("Remove", systemImage: "trash", role: .destructive) { openTrack = nil; update { $0.appleMusic = nil } }
                        Text("Apple Music plays the song itself, so its key can't change and the singer can't be taken out.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Menu {
                    Button("From a File…", systemImage: "folder", action: transport.hasAnyTrack ? pickExtra : pickTrack)
                    if it.appleMusic == nil { Button("From Apple Music…", systemImage: "music.note", action: pickMusic) }
                } label: { Label(transport.hasAnyTrack ? String(localized: "Add Another Track") : String(localized: "Add a Backing Track"), systemImage: "plus") }
                if transport.hasTrack {
                    Button { Store.shared.unlock(.performer, "The equaliser") { showEQ = true } } label: { Label(it.trackEQ == nil ? "Equaliser…" : String(localized: "Equaliser (On)…"), systemImage: "slider.vertical.3") }
                        .sheet(isPresented: $showEQ) { EQSheet(item: it, transport: transport) }
                    Button { openTrack = openTrack == "sync" ? nil : "sync" } label: { Label("Match and Sync…", systemImage: "wand.and.stars") }
                        .popover(isPresented: Binding { openTrack == "sync" } set: { if !$0 { openTrack = nil } }) {
                            VStack(alignment: .leading, spacing: 12) {
                                TrackMatch(item: item, key: key, transport: transport)
                                if advanced {
                                    TrackSync(url: library.trackURL(item), offset: bind(\.offset, apply: { transport.offset = $0 }),
                                              tempo: tempoBinding, transport: transport)
                                    Button("Edit Backing Track…", systemImage: "waveform.path.ecg") { openTrack = nil; editTrack() }
                                }
                                Text("Drag the marker to where \(transport.leadInBars > 0 ? "the intro" : "bar 1") begins, or delay the track if the score should start first. If the score drifts from the recording, tap Lock Tempo on a downbeat later in the piece.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(16).frame(width: 340).presentationCompactAdaptation(.popover)
                        }
                }
                HStack {
                    Picker("Play Score As", selection: $transport.instrument) {
                        ForEach(Instrument.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    if transport.instrument != .off {
                        Button { openTrack = openTrack == "instrument" ? nil : "instrument" } label: { Image(systemName: "slider.horizontal.3") }
                            .buttonStyle(.borderless)
                            .popover(isPresented: Binding { openTrack == "instrument" } set: { if !$0 { openTrack = nil } }) {
                                GainRow(title: "Instrument Level", db: bind(\.instrumentGainDB, apply: { transport.instrumentGainDB = $0 ?? 0 }))
                                    .padding(16).frame(width: 300).presentationCompactAdaptation(.popover)
                            }
                            .accessibilityLabel("Instrument level")
                    }
                }
            } footer: {
                if transport.instrument != .off { Text("The instrument plays the notes on the page, alongside any backing track.") }
            }

            if staves.count > 1 {
                Panel("Staves") {
                    ForEach(staves.indices, id: \.self) { s in
                        Picker(staves[s], selection: staffVoice(s)) {
                            Text("Same as Above").tag("")
                            ForEach(Instrument.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0.rawValue) }
                        }
                    }
                } footer: {
                    Text("Give each staff its own instrument, for example Bass on the bass-clef staff. Staves left on Same as Above use the instrument chosen above.")
                }
            }

            Panel("Appearance") {
                Toggle("Highlight Notes", isOn: $noteGlow.animation(.smooth))
                Toggle("Highlight Bar", isOn: $barWash.animation(.smooth))
                Toggle("Moving Line", isOn: $showPlayhead.animation(.smooth))
                Picker("Sheet Music", selection: $darkPaper.animation(.smooth)) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(.segmented)
                HStack(spacing: 14) {
                    ForEach(Theme.highlights, id: \.name) { h in
                        Button {
                            withAnimation(.spring(duration: 0.35, bounce: 0.35)) { highlight = h.name }
                        } label: {
                            Circle().fill(h.color)
                                .frame(width: 28, height: 28)
                                .padding(4)
                                .overlay {
                                    if highlight == h.name {
                                        Circle().strokeBorder(.white, lineWidth: 2)
                                            .matchedGeometryEffect(id: "ring", in: swatch)
                                    }
                                }
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(h.name)
                        .accessibilityAddTraits(highlight == h.name ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
                if advanced { ColorSettingsButton() }
            } footer: {
                if !noteGlow && !barWash && !showPlayhead { Text("With everything off, only the bar counter and the page turns follow the music.") }
            }
        }
        .scrollContentBackground(.hidden)
        .tint(Color(red: 1.0, green: 0.76, blue: 0.34))   // the accent on the grey plates: brighter than on the page, so it reads
        .background(StageBackground())
        .copyrightGate($gated)
        .sheet(item: $sharedConverted) { ActivitySheet(url: $0.url).presentationDetents([.medium, .large]) }
    }

    @ViewBuilder private var keySection: some View {
        let semis = Store.shared.gate(.performer, "Changing key", bind(\.transpose, apply: { _ in }))
        Panel("Key") {
            Picker("Your Instrument’s Key", selection: $instrumentKey) {
                ForEach(InstrumentKey.allCases) { Text(LocalizedStringKey($0.label)).tag($0.rawValue) }
            }
            if advanced {
                Picker("Score Is Written For", selection: bind(\.writtenFor, apply: { _ in })) {
                    Text("Concert pitch").tag(String?.none)
                    ForEach(InstrumentKey.allCases.dropFirst()) { Text(LocalizedStringKey($0.rawValue)).tag(String?.some($0.rawValue)) }
                }
            }
            NumberStepper(title: "Transpose", value: Binding { Double(semis.wrappedValue ?? 0) } set: { semis.wrappedValue = $0 == 0 ? nil : Int($0) }, range: -12...12, signed: true)
            if let key {
                let t = item.transpose ?? 0, here = t.mod(12) > 6 ? t.mod(12) - 12 : t.mod(12)
                // Every key, C upwards; choosing one moves the shortest way from where the score is now.
                let options = (-5...6).sorted { a, b in
                    let pc = { (n: Int) in (7 * ParsedScore.transposedKey(key.fifths, by: n) + (key.minor ? 9 : 0)).mod(12) }
                    return pc(a) < pc(b)
                }
                Picker("Key", selection: Binding { here } set: { n in
                    let v = [n - 12, n, n + 12].filter { (-12...12).contains($0) }.min { abs($0 - t) < abs($1 - t) } ?? n
                    withAnimation(.smooth) { semis.wrappedValue = v == 0 ? nil : v }
                }) {
                    ForEach(options, id: \.self) { n in
                        let f = ParsedScore.transposedKey(key.fifths, by: n)
                        Text(ParsedScore.keyName(f, minor: key.minor) + " / " + ParsedScore.keyName(f, minor: !key.minor) + (n == 0 ? " (Original)" : "")).tag(n)
                    }
                }
                .pickerStyle(.menu)
            }
            if transport.hasTrack && advanced {
                Toggle("Shift Backing Track", isOn: Binding { item.shiftTrack != false } set: { v in
                    guard var current = library.items.first(where: { $0.id == item.id }) else { return }
                    current.shiftTrack = v ? nil : false
                    library.save(current)
                })
            }
            if advanced, item.isPDF, FileManager.default.fileExists(atPath: library.convertedURL(item).path) {
                Button("Export as MusicXML", systemImage: "square.and.arrow.up") { Store.shared.unlock(.performer, "Export") { gated = { sharedConverted = SharedFile(url: library.convertedURL(item)) } } }
            }
        } footer: {
            let score = item.isPDF ? String(localized: "In its original key the PDF shows as printed. In any other key, the music read from the page is engraved afresh, so check it against the original.") : String(localized: "The score is re-engraved in the new key.")
            let track = !transport.hasTrack ? "" : item.shiftTrack != false ? String(localized: " The backing track is pitch-shifted to match.") : String(localized: " The backing track stays in its recorded key.")
            let mine = InstrumentKey(rawValue: instrumentKey) ?? .concert, shift = mine.offset - item.writtenKey.offset
            let shown = key.map { ParsedScore.keyName(ParsedScore.transposedKey($0.fifths, by: (item.transpose ?? 0) + shift), minor: $0.minor) }
            let page = shown.map { String(localized: "The page is shown in \($0)\(shift == 0 ? "" : ", moved to suit your instrument; the backing track isn’t"). ") } ?? ""
            Text(page + score + track)
        }
    }

    /// The instrument chosen for one staff ("" = the main one).
    private func staffVoice(_ s: Int) -> Binding<String> {
        Binding {
            let all = library.items.first { $0.id == item.id }?.staffInstruments ?? item.staffInstruments ?? []
            return s < all.count ? all[s] : ""
        } set: { v in
            guard var current = library.items.first(where: { $0.id == item.id }) else { return }
            var all = current.staffInstruments ?? []
            while all.count < staves.count { all.append("") }
            all[s] = v
            current.staffInstruments = all.allSatisfy(\.isEmpty) ? nil : all
            library.save(current)
            transport.staffInstruments = all.map { Instrument(rawValue: $0) }
        }
    }

    private func bind<V>(_ key: WritableKeyPath<ScoreItem, V>, apply: @escaping (V) -> Void) -> Binding<V> {
        Binding {
            library.items.first { $0.id == item.id }?[keyPath: key] ?? item[keyPath: key]
        } set: { v in
            guard var current = library.items.first(where: { $0.id == item.id }) else { return }
            current[keyPath: key] = v
            library.save(current)
            apply(v)
        }
    }
}

/// A row of the inspector: a strip of brushed graphite.
private struct PlateRow: View {
    var body: some View {
        ZStack {
            Rectangle().fill(LinearGradient(colors: [Color(white: 0.36), Color(white: 0.29)], startPoint: .top, endPoint: .bottom))
            Grain(kind: .brushed, opacity: 0.16, role: .metal)
            Rectangle().fill(.white.opacity(0.05)).frame(height: 1).frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// An inspector section whose title folds it away; each remembers whether it was open.
private struct Panel<Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer
    @AppStorage private var collapsed: Bool
    @Environment(\.colorScheme) private var scheme

    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.footer = footer()
        _collapsed = AppStorage(wrappedValue: false, "inspector.collapsed." + title)
    }

    var body: some View {
        Section {
            if !collapsed { content.environment(\.colorScheme, .dark).listRowBackground(PlateRow()) }   // white text on the grey plates, whatever the app's look
        } header: {
            Button { withAnimation(.smooth(duration: 0.3)) { collapsed.toggle() } } label: {
                HStack {
                    // Dark ink on the pale looks, cream on the dark ones.
                    Text(LocalizedStringKey(title)).font(.system(.footnote, weight: .heavy)).textCase(.uppercase).tracking(1.1)
                        .foregroundStyle(scheme == .dark ? Color(red: 0.96, green: 0.92, blue: 0.84) : Color(red: 0.12, green: 0.07, blue: 0.03))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(scheme == .dark ? Color(red: 0.96, green: 0.92, blue: 0.84) : Color(red: 0.12, green: 0.07, blue: 0.03))
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LocalizedStringKey(title))
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            .accessibilityHint("Double-tap to \(collapsed ? "show" : "hide") these settings.")
        } footer: {
            if !collapsed { footer }
        }
    }
}

extension Panel where Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) { self.init(title, content: content, footer: { EmptyView() }) }
}

// MARK: - Matching the score to the track

/// Reads the track's tempo and key and sets the score to them: tempo to the track's beat, and a
/// transposition into the track's key (the track itself stays as recorded).
struct TrackMatch: View {
    @Environment(Library.self) private var library
    let item: ScoreItem
    let key: (fifths: Int, minor: Bool)?
    let transport: Transport
    @State private var working = false
    @State private var result: String?

    var body: some View {
        Button {
            Task { await match() }
        } label: {
            HStack {
                Label("Match Key & Tempo to Track", systemImage: "wand.and.stars")
                Spacer()
                if working { ProgressView().controlSize(.small) }
            }
        }
        .disabled(working)
        .help("Listen to the backing track and set the score’s tempo and key to match it")
        #if DEBUG
        .task { if CommandLine.arguments.contains("-match") { await match() } }   // screenshot hook
        #endif
        if let result {
            Text(result)
                .font(.callout)
                .foregroundStyle(.secondary)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func match() async {
        guard Store.shared.allows(.performer) else { return Store.shared.present(.performer, "Match Key & Tempo") }
        withAnimation(.smooth) { working = true; result = nil }
        let text = await Self.run(item: item, key: key, library: library, transport: transport)
        withAnimation(.smooth) { working = false; result = text }
    }

    /// Listens to the track and moves the score (in concert pitch, whatever instrument it's written for) to its key.
    /// The track stays put; your instrument's transposition is applied on top, to the page only.
    static func run(item: ScoreItem, key: (fifths: Int, minor: Bool)?, library: Library, transport: Transport) async -> String {
        guard let url = library.trackURL(item) else { return "" }
        let found = await Task.detached(priority: .userInitiated) { TrackAnalysis.load(url) }.value
        guard let found, var current = library.items.first(where: { $0.id == item.id }) else { return String(localized: "Couldn’t find a steady beat in this track.") }
        let tempo = found.tempo(near: current.tempo)
        current.tempo = tempo
        current.customTempo = true   // the recording's tempo is a tempo of its own
        var keyNote = ""
        if let key {
            let n = found.transposition(fromFifths: ParsedScore.transposedKey(key.fifths, by: -item.writtenKey.offset))
            current.transpose = n == 0 ? nil : n
            if n != 0 { current.shiftTrack = false }   // the score moves to the track, so the track stays put
            keyNote = n == 0 ? String(localized: ", already the score’s key")
                : n > 0 ? (n == 1 ? String(localized: ", so the score moves up 1 semitone") : String(localized: ", so the score moves up \(n) semitones"))
                : (n == -1 ? String(localized: ", so the score moves down 1 semitone") : String(localized: ", so the score moves down \(-n) semitones"))
        }
        library.save(current)
        transport.tempo = tempo
        return String(localized: "Track: \(TempoField.format(tempo)) BPM in \(found.keyName)\(keyNote).")
    }
}

// MARK: - Backing track sync

/// Waveform with a draggable bar-1 marker, plus delay, skip-silence and tap-to-mark.
private struct TrackSync: View {
    let url: URL?
    @Binding var offset: Double
    @Binding var tempo: Double
    let transport: Transport
    @State private var wave: Waveform?
    @State private var locked = 0
    @State private var dragging = false
    @State private var syncMessage: String?

    private var skip: Double { offset > 0 ? offset : 0 }
    private var delay: Double { offset < 0 ? -offset : 0 }   // never "-0.0"
    /// How long one bar lasts at the current tempo.
    private var barSeconds: Double { max(0.1, transport.leadBar * 60 / max(tempo, 1)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let first = transport.leadInBars > 0 ? "the intro" : "bar 1"
            Text(offset >= 0 ? String(format: "%@ starts %.2f s into the track", first.prefix(1).uppercased() + first.dropFirst(), skip)
                             : String(format: "Track starts %.2f s after %@", delay, first))
                .font(.callout.monospacedDigit())
                .contentTransition(.numericText(value: offset))
                .animation(.snappy, value: offset)
            waveform
        }
        .task(id: url) {
            guard let url else { return }
            let w = await Task.detached(priority: .utility) { Waveform.load(url) }.value
            withAnimation(.smooth(duration: 0.6)) { wave = w }
        }

        NumberStepper(title: "Delay Start", value: Binding { delay } set: { offset = -(($0 * 100).rounded() / 100) }, range: 0...30, step: 0.1, decimals: 1, unit: "s")
        NumberStepper(title: "Delay Start in Bars", value: Binding { delay / barSeconds } set: { offset = -((min($0, 16) * barSeconds * 100).rounded() / 100) }, range: 0...16, step: 0.25, decimals: 2, unit: "bars")
        NumberStepper(title: "Nudge Bar 1", value: Binding { skip } set: { offset = ($0 * 100).rounded() / 100 }, range: 0...600, step: 0.01, decimals: 2, unit: "s")
        // Always available; each says what it did, or what it needs first. Same rows as the buttons around them.
        syncButton("Skip Leading Silence", symbol: "forward.end") {
            guard let wave else { return String(localized: "Still reading the track…") }
            guard wave.firstSound >= 0.01 else { return String(localized: "The track already starts with sound.") }
            withAnimation(.snappy) { offset = (wave.firstSound * 100).rounded() / 100 }
            return String(format: "%@ now starts %.2f s into the track.", transport.leadInBars > 0 ? String(localized: "The intro") : String(localized: "Bar 1"), (wave.firstSound * 100).rounded() / 100)
        }
        syncButton(transport.leadInBars > 0 ? "Mark Intro Start Now" : "Mark Bar 1 Now", symbol: "flag.fill") {
            guard transport.isPlaying else { return String(localized: "Play the track, then tap this on the first beat of \(transport.leadInBars > 0 ? "the intro" : "bar 1").") }
            guard let o = transport.markBarOneHere() else { return String(localized: "The track isn’t sounding yet; wait until it plays, then tap.") }
            withAnimation(.snappy) { offset = (o * 100).rounded() / 100 }
            return String(format: "%@ now starts %.2f s into the track.", transport.leadInBars > 0 ? String(localized: "The intro") : String(localized: "Bar 1"), (o * 100).rounded() / 100)
        }
        syncButton("Lock Tempo Here", symbol: "metronome.fill") {
            guard transport.isPlaying else { return String(localized: "Play past bar 1, then tap this on a later downbeat.") }
            guard let t = transport.tempoLockedHere() else { return String(localized: "Mark bar 1 first, then tap on a downbeat at least a second later.") }
            withAnimation(.snappy) { tempo = t }
            locked += 1
            return String(format: "Tempo set to %.2f BPM to match the recording.", t)
        }
        .sensoryFeedback(.success, trigger: locked)
        if let syncMessage {
            Text(syncMessage).font(.caption).foregroundStyle(.secondary).transition(.opacity)
        }
    }

    private func syncButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> String) -> some View {
        Button(title, systemImage: symbol) {
            let message = action()
            withAnimation(.smooth) { syncMessage = message }
        }
    }

    private var waveform: some View {
        GeometryReader { g in
            let w = g.size.width, dur = max(wave?.duration ?? 1, 0.01)
            let markerX = CGFloat(skip / dur) * w
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.35))
                if let wave {
                    Canvas { ctx, size in
                        let bw = size.width / CGFloat(wave.peaks.count)
                        for (i, p) in wave.peaks.enumerated() {
                            let h = max(1, CGFloat(p) * (size.height - 8))
                            let x = CGFloat(i) * bw
                            let before = x < markerX
                            ctx.fill(Path(roundedRect: CGRect(x: x, y: (size.height - h) / 2, width: max(1, bw - 1), height: h), cornerRadius: 0.5),
                                     with: .color(before ? .white.opacity(0.18) : Theme.accent.opacity(0.85)))
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
                // Bar 1 marker.
                Capsule().fill(.white)
                    .frame(width: dragging ? 3 : 2)
                    .overlay(alignment: .top) {
                        Text("1").font(.caption2.weight(.bold)).foregroundStyle(.black)
                            .frame(width: 16, height: 16).background(.white, in: .circle).offset(y: -6)
                    }
                    .shadow(color: .white.opacity(0.6), radius: dragging ? 6 : 2)
                    .offset(x: markerX - 1)
                    .opacity(offset >= 0 ? 1 : 0.35)
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !dragging { withAnimation(.spring(duration: 0.2)) { dragging = true } }
                    offset = (Double(max(0, min(w, v.location.x)) / w) * dur * 100).rounded() / 100
                }
                .onEnded { _ in withAnimation(.spring(duration: 0.3)) { dragging = false } })
        }
        .frame(height: 64)
        .padding(.top, 8)
        .accessibilityElement()
        .accessibilityLabel("Track start marker")
        .accessibilityValue(String(format: "%.2f seconds", skip))
        .accessibilityAdjustableAction { offset = max(0, skip + ($0 == .increment ? 0.05 : -0.05)) }
    }
}

/// Which playback guides show: the sounding notes, the current bar, the moving line.
struct Guides: Equatable {
    var notes = true, bar = true, line = true
}

/// Tempo you can type into: tap, enter a number, return. Out-of-range values clamp to 20–300.
/// A number with − / + buttons that can also be typed. Out-of-range or unreadable entries are corrected on return.
/// One backing track in the Inspector: its name and switch, and a button that opens its own settings.
private struct TrackLine<Settings: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @Binding var enabled: Bool
    let id: String
    @Binding var open: String?
    @ViewBuilder let settings: Settings

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 0) {
                    Label(title, systemImage: "waveform").lineLimit(1)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).padding(.leading, 28) }
                }
            }
            Button { open = open == id ? nil : id } label: { Image(systemName: "slider.horizontal.3").frame(width: 28, height: 28) }
                .buttonStyle(.borderless)
                .accessibilityLabel("Settings for \(title)")
                .popover(isPresented: Binding { open == id } set: { if !$0 { open = nil } }) {
                    VStack(alignment: .leading, spacing: 12) { settings }
                        .padding(16).frame(width: 300)
                        .presentationCompactAdaptation(.popover)
                }
        }
    }
}

/// A level in decibels for one source, from -24 to +12, with a way back to 0.
private struct GainRow: View {
    let title: LocalizedStringKey
    @Binding var db: Double?

    var body: some View {
        let value = db ?? 0
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value == 0 ? "0 dB" : String(format: "%+.1f dB", value)).monospacedDigit().foregroundStyle(.secondary)
                Button { db = nil } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless).disabled(db == nil).accessibilityLabel("Reset \(title)")
            }
            Slider(value: Binding { value } set: { db = abs($0) < 0.25 ? nil : ($0 * 2).rounded() / 2 }, in: -24...12) {
                Text(title)
            } minimumValueLabel: { Image(systemName: "speaker") } maximumValueLabel: { Image(systemName: "speaker.wave.3") }
            .tint(Theme.accent)
        }
        .accessibilityElement(children: .combine)
    }
}

struct NumberStepper: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step = 1.0
    var decimals = 0
    var unit = ""
    var signed = false
    @State private var text = ""
    @FocusState private var focused: Bool

    private func format(_ v: Double) -> String {
        let s = v.formatted(.number.precision(.fractionLength(decimals)).grouping(.never))
        return signed && v > 0 ? "+" + s : s.replacingOccurrences(of: "-", with: "−")
    }

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack(spacing: 6) {
                Text(title).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                TextField(title, text: $text)
                    .keyboardType(range.lowerBound < 0 ? .numbersAndPunctuation : .decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($focused)
                    .frame(width: 44)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.white.opacity(focused ? 0.12 : 0.06), in: .rect(cornerRadius: 6))
                    .onSubmit(commit)
                    .accessibilityLabel(title)
                if !unit.isEmpty { Text(unit).foregroundStyle(.secondary).lineLimit(1).fixedSize() }
            }
        }
        .onAppear { text = format(value) }
        .onChange(of: value) { _, v in if !focused { text = format(v) } }
        .onChange(of: focused) { _, f in if !f { commit() } }
        // Take a valid number as it is typed, so a button tapped before the field loses focus still sees it.
        .onChange(of: text) { _, _ in if focused, let v = typed, range.contains(v) { value = v } }
    }

    private var typed: Double? {
        Double(text.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "+", with: "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    private func commit() {
        if let v = typed {
            let p = pow(10, Double(decimals))
            value = (max(range.lowerBound, min(range.upperBound, v)) * p).rounded() / p
        }
        text = format(value)
    }
}

/// Practice speed as a percentage that can be typed, so it can go beyond the slider's range (10% to 400%).
struct PercentField: View {
    @Binding var speed: Double
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField("Speed", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focused)
                .frame(width: 56)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.white.opacity(focused ? 0.12 : 0.06), in: .rect(cornerRadius: 6))
                .onSubmit(commit)
                .accessibilityLabel("Practice speed in percent")
            Text("%").foregroundStyle(.secondary)
        }
        .onAppear { text = Self.format(speed) }
        .onChange(of: speed) { _, s in if !focused { text = Self.format(s) } }
        .onChange(of: focused) { _, f in if !f { commit() } }
    }

    private static func format(_ s: Double) -> String { "\(Int((s * 100).rounded()))" }

    private func commit() {
        if let v = Double(text.filter(\.isNumber)) { speed = max(10, min(400, v)) / 100 }
        text = Self.format(speed)
    }
}

struct TempoField: View {
    @Binding var tempo: Double
    @State private var text = ""
    @FocusState private var focused: Bool
    var autofocus = false
    var showsUnit = true

    var body: some View {
        HStack(spacing: 4) {
            TextField("Tempo", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focused)
                .frame(width: 64)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.white.opacity(focused ? 0.12 : 0.06), in: .rect(cornerRadius: 6))
                .onSubmit(commit)
                .accessibilityLabel("Tempo in beats per minute")
            if showsUnit { Text("BPM").foregroundStyle(.secondary) }
        }
        .onAppear { text = Self.format(tempo); if autofocus { focused = true } }
        .onChange(of: tempo) { _, t in text = Self.format(t) }   // also while focused: tapping the tempo in changes it under the cursor
        .onChange(of: focused) { _, f in if !f { commit() } }
    }

    private func commit() {
        if let v = Double(text.replacingOccurrences(of: ",", with: ".")) { tempo = (max(20, min(300, v)) * 100).rounded() / 100 }
        text = Self.format(tempo)
    }

    static func format(_ t: Double) -> String { t.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) }
}

/// Toolbar colours. On the Mac every button has the same grey bezel and a white glyph, and amber means "on":
/// an amber bezel there swallows an amber glyph. iPad keeps its amber glyphs.
enum BarStyle {
    static var tint: Color {
        #if targetEnvironment(macCatalyst)
        Color(white: 0.3)
        #else
        Theme.accent
        #endif
    }

    static func glyph(_ on: Bool = false) -> Color {
        #if targetEnvironment(macCatalyst)
        on ? Theme.accent : .white
        #else
        Theme.accent
        #endif
    }
}

/// Icon-only toolbar toggle: the glyph fills and takes the accent when on, instead of a filled pill.
private struct ToolbarToggle: View {
    let title: LocalizedStringKey
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button { withAnimation(.smooth) { isOn.toggle() } } label: {
            Label {
                Text(title)
            } icon: {
                // Palette + original rendering keeps the amber when the Mac toolbar templates its icons.
                Image(systemName: symbol)
                    .symbolVariant(isOn ? .fill : .none)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(BarStyle.glyph(isOn))   // filled when on
                    .contentTransition(.symbolEffect(.replace))
            }
            .labelStyle(.iconOnly)
        }
        .tint(BarStyle.tint)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Every bar has to last a set number of beats. When the page doesn't make it clear, the player says.
private struct MetrePrompt: View {
    @State var beats: Double
    let done: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How many beats are in each bar?").font(.title2.bold())
            Text("The app couldn't tell from the page. Count the beats in one bar (crotchets): 4 for 4/4, 3 for 3/4, 6 for 6/4. For 6/8 count two dotted-crotchet beats of 3, so enter 3.")
                .foregroundStyle(.secondary)
            NumberStepper(title: "Crotchet beats per bar", value: $beats, range: 1...12, step: 0.5, decimals: 1)
            HStack {
                ForEach([2.0, 3, 4, 5, 6], id: \.self) { n in
                    Button(n.formatted()) { beats = n }.buttonStyle(.bordered).tint(beats == n ? Theme.accent : .gray)
                }
                Spacer()
                Button("Use \(beats.formatted(.number.precision(.fractionLength(0...1)))) Beats") { done(beats) }.buttonStyle(.borderedProminent)
            }
            Text("You can change this later in the inspector.").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: 520)
        .presentationDetents([.medium])
    }
}

/// Usage counts for the score screen's switches. Only what was switched, never which score.
private struct ScoreUsage: ViewModifier {
    let playing: Bool, practice: Bool, recording: Bool, annotating: Bool, fullScreen: Bool, dark: Bool, follow: Bool
    let inspector: Bool, lyrics: Bool, chords: Bool, together: Bool, connected: Bool, looping: Bool, metronome: Bool, review: Bool
    let tempo: Int

    func body(content: Content) -> some View {
        content
            .onChange(of: playing) { _, on in if on { Analytics.track("play", ["tempo": tempo]) } }
            .onChange(of: practice) { _, on in Analytics.track("wait_for_me", ["on": on]) }
            .onChange(of: recording) { _, on in Analytics.track("recording", ["on": on]) }
            .onChange(of: annotating) { _, on in Analytics.track("annotate", ["on": on]) }
            .onChange(of: fullScreen) { _, on in Analytics.track("full_screen", ["on": on]) }
            .onChange(of: dark) { _, on in Analytics.track("dark_sheet_music", ["on": on]) }
            .onChange(of: follow) { _, on in Analytics.track("follow_playback", ["on": on]) }
            .onChange(of: inspector) { _, on in Analytics.track("inspector", ["on": on]) }
            .onChange(of: lyrics) { _, on in Analytics.track("lyrics_panel", ["on": on]) }
            .onChange(of: chords) { _, on in Analytics.track("chord_view", ["on": on]) }
            .onChange(of: together) { _, on in if on { Analytics.track("play_together_opened") } }
            .onChange(of: connected) { _, on in Analytics.track("together_connected", ["on": on]) }
            .onChange(of: looping) { _, on in Analytics.track("loop", ["on": on]) }
            .onChange(of: metronome) { _, on in Analytics.track("metronome", ["on": on]) }
            .onChange(of: review) { _, on in if on { Analytics.track("review_opened") } }
    }
}
