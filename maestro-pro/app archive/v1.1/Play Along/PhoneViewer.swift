import SwiftUI
import Combine

/// What the app is on a phone's screen (an iPhone, or the Duo's outer display): the library, and each score as a page to read.
/// Playing, editing and everything else wait for a screen big enough, such as the Duo opened out or an iPad.
struct PhoneViewer: View {
    /// A window whose shorter side is under this many points is a phone-sized screen. The Duo's inner display is wider.
    static let narrow: CGFloat = 600
    /// Below this width the opened Duo uses the app's compact layout (one column) instead of a squeezed sidebar and page.
    static let compactBelow: CGFloat = 900
    /// iPhone Duo hardware. ponytail: model list is the only way to tell the Duo's front screen from an iPhone; add new identifiers here.
    static let isDuo: Bool = {
        var u = utsname(); uname(&u)
        let machine = withUnsafeBytes(of: &u.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return ["iPhone19,4"].contains(ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine)
    }()
    /// Debug: `-forcefull` shows the whole app on a phone-sized screen, to check the compact layout.
    static var forceFull: Bool {
        #if DEBUG
        CommandLine.arguments.contains("-forcefull")
        #else
        false
        #endif
    }
    static func isPhoneSized(_ size: CGSize) -> Bool {
        UIDevice.current.userInterfaceIdiom == .phone && min(size.width, size.height) < narrow
    }
    /// An ordinary iPhone: just the sheet music.
    static func applies(to size: CGSize) -> Bool { isPhoneSized(size) && !isDuo }
    /// The Duo's front screen.
    static func isFrontScreen(_ size: CGSize) -> Bool { isPhoneSized(size) && isDuo }

    @Environment(Library.self) private var library
    /// Shared with the full layout, so opening the Duo keeps the score you were reading.
    @Binding var selection: Pick?

    private var scores: [ScoreItem] { library.items.filter { $0.generated != true } }

    var body: some View {
        @Bindable var library = library
        return NavigationStack {
            Group {
                if scores.isEmpty {
                    ContentUnavailableView("No Scores Yet", systemImage: "music.note.list", description: Text("Add scores on your iPad or Mac and they appear here."))
                } else {
                    List(scores) { item in
                        Button { selection = Pick(score: item.id) } label: {
                            VStack(alignment: .leading) {
                                Text(item.title)
                                if item.isLyricsOnly || item.isCDG { Text(item.kindLabel).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Scores")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Tuner", systemImage: "tuningfork") { Store.shared.unlock(.performer, "The tuner") { library.showTuner = true } }
                }
            }
            .sheet(isPresented: $library.showTuner) { TunerView().environment(library) }
            .navigationDestination(item: $selection) { pick in
                if let item = library.items.first(where: { $0.id == pick.score }) {
                    if item.isLyricsOnly || item.isCDG { LyricsScreen(item: item, columns: .constant(.automatic)) } else { SheetOnly(item: item) }
                }
            }
        }
    }
}

/// The pages of one score, fitted to the width, and nothing else.
private struct SheetOnly: View {
    let item: ScoreItem
    @Environment(Library.self) private var library
    @AppStorage("darkPaper") private var darkPaper = false
    @State private var score: LoadedScore?
    @State private var failed = false
    @State private var scrolling = false
    @State private var bpm = 100.0
    @State private var beats = 0.0       // the piece's length, from its timeline
    @State private var askBPM = false
    @State private var scroller = Scroller()
    private let tick = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.stage).ignoresSafeArea()
            if let score {
                GeometryReader { geo in
                    let width = geo.size.width - 24
                    ScrollView {
                        VStack(spacing: 20) {
                            ForEach(score.pages.indices, id: \.self) { i in
                                let page = score.pages[i]
                                PageCanvas(page: page, dark: darkPaper)
                                    .clipShape(RoundedRectangle(cornerRadius: PaperSheet.radius, style: .continuous))
                                    .background { PaperSheet(dark: darkPaper) }
                                    .frame(width: width, height: width * page.size.height / page.size.width)
                                    .accessibilityLabel("Page \(i + 1)")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background { ScrollFinder(scroller: scroller) }
                    }
                }
            } else if failed {
                ContentUnavailableView("Couldn’t Open Score", systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if score != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Tempo", systemImage: "metronome") { askBPM = true }
                        .popover(isPresented: $askBPM) {
                            VStack(spacing: 10) {
                                Text("Tempo").font(.headline)
                                HStack {
                                    TextField("BPM", value: $bpm, format: .number.precision(.fractionLength(0)))
                                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 70)
                                        .textFieldStyle(.roundedBorder)
                                    Text("BPM").foregroundStyle(.secondary)
                                }
                                Text("Each stave scrolls past in the time it takes to play at this tempo.")
                                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                            .padding().frame(width: 260).presentationCompactAdaptation(.popover)
                        }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(scrolling ? String(localized: "Stop Scrolling") : "Autoscroll", systemImage: scrolling ? "pause.fill" : "play.fill") { scrolling.toggle() }
                }
            }
        }
        .onReceive(tick) { _ in
            guard scrolling, let v = scroller.view else { return }
            if v.isTracking || v.isDragging || v.isDecelerating { return }   // the reader's finger wins
            let end = v.contentSize.height - v.bounds.height + v.adjustedContentInset.bottom
            if v.contentOffset.y >= end - 0.5 { scrolling = false; return }
            // The whole piece takes beats * 60 / bpm seconds, so each stave gets its own length in time. ponytail: assumes even stave heights.
            let pace = beats > 0 ? v.contentSize.height * min(max(bpm, 20), 300) / (beats * 60) : 40
            v.contentOffset.y = min(end, v.contentOffset.y + pace / 60)
        }
        .onDisappear { scrolling = false }
        .task {
            let url = library.scoreURL(item)
            let loaded = await Task.detached(priority: .userInitiated) { try? ScoreLoader.load(url, beatsPerBar: 4, analyse: true) }.value
            score = loaded
            if let loaded { beats = loaded.timeline(beatsPerBar: item.beatsPerBar).length; if let t = loaded.tempo { bpm = t } }
            failed = loaded == nil
        }
    }
}

/// The Duo's front screen: the app lives on the inner display.
struct OpenPrompt: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Theme.stage).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "book.pages").font(.system(size: 56)).foregroundStyle(Theme.accent)
                Text("Open Your iPhone").font(.title2.weight(.semibold))
                Text("Maestro Pro is made for the big screen. Unfold your iPhone Duo to carry on.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(32)
        }
    }
}
