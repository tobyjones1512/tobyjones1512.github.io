import CoreText
import SwiftUI

@main struct MyApp: App {
    @State private var library = Library()
    @State private var together = Together()
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("uiTextSize") private var uiTextSize = "default"
    @AppStorage("boldUI") private var boldUI = false
    @AppStorage("highContrast") private var highContrast = false
    @AppStorage("scoreEditToken") private var scoreEditToken = 0.0

    init() {
        Analytics.start()
        _ = Store.shared   // starts listening for purchases and renewals
        if let url = Bundle.main.url(forResource: "Bravura", withExtension: "otf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        #if targetEnvironment(macCatalyst)
        if UserDefaults.standard.object(forKey: "advancedMode") == nil {
            UserDefaults.standard.set(true, forKey: "advancedMode")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
            .modifier(OnboardingGate())
            #if DEBUG
            .modifier(ForcedLandscape())   // screenshot hook: the simulator can't be rotated headlessly
            #endif
            .environment(library)
            .environment(together)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "system" ? nil : .dark)
            .dynamicTypeSize(uiTextSize == "large" ? .xLarge : uiTextSize == "larger" ? .xxxLarge : uiTextSize == "largest" ? .accessibility2 : .large)
            .environment(\.legibilityWeight, boldUI ? .bold : nil)
            .tint(Theme.accent)
        }
        .commands { AppCommands(library: library) }
        WindowGroup(id: "score", for: UUID.self) { $id in
            if let id, let item = library.items.first(where: { $0.id == id }) {
                NavigationStack {
                    Group {
                        if item.isLyricsOnly {
                            LyricsScreen(item: item, columns: .constant(.detailOnly))
                        } else {
                            ScoreScreen(item: item, columns: .constant(.detailOnly))
                        }
                    }
                    .toolbarColorScheme(appearance == "light" ? .light : appearance == "system" ? nil : .dark, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .id(item.id)
                }
                .environment(library)
                .environment(together)
                .environment(\.isStandaloneWindow, true)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "system" ? nil : .dark)
                .dynamicTypeSize(uiTextSize == "large" ? .xLarge : uiTextSize == "larger" ? .xxxLarge : uiTextSize == "largest" ? .accessibility2 : .large)
                .environment(\.legibilityWeight, boldUI ? .bold : nil)
                .tint(Theme.accent)
            }
        }
        WindowGroup(id: "score-editor", for: UUID.self) { $id in
            if let id, let item = library.items.first(where: { $0.id == id }) {
                ScoreEditorView(item: item)
                    .environment(library)
                    .preferredColorScheme(appearance == "light" ? .light : appearance == "system" ? nil : .dark)
                    .tint(Theme.accent)
                    .onDisappear { scoreEditToken = Date().timeIntervalSince1970 }
            }
        }
        #if os(macOS)
        Settings { AppSettingsView().environment(library).frame(width: 480, height: 640) }
        #endif
    }
}

/// Every customisable colour, persisted as RGBA in UserDefaults. Views read it through `Theme`, so changes show live.
@Observable final class Palette {
    static let shared = Palette()
    static let highlightNames = ["Amber", "Mint", "Sky", "Rose", "Violet"]
    static let defaults: [String: Color] = [
        "accent": Color(red: 1.0, green: 0.71, blue: 0.27),
        "stageTop": Color(red: 0.17, green: 0.12, blue: 0.09),       // dark leather, lit from above
        "stageBottom": Color(red: 0.08, green: 0.055, blue: 0.042),
        "paper": Color(red: 0.985, green: 0.972, blue: 0.94),
        "darkPaper": Color(white: 0.035),
        "Amber": Color(red: 1.0, green: 0.71, blue: 0.27),
        "Mint": Color(red: 0.32, green: 0.88, blue: 0.70),
        "Sky": Color(red: 0.36, green: 0.66, blue: 1.0),
        "Rose": Color(red: 1.0, green: 0.42, blue: 0.56),
        "Violet": Color(red: 0.69, green: 0.52, blue: 1.0),
        // Deeper versions of the highlights for recoloured ink on light paper, where the bright tints lose legibility.
        "ink.Amber": Color(red: 0.86, green: 0.42, blue: 0.0),
        "ink.Mint": Color(red: 0.0, green: 0.55, blue: 0.40),
        "ink.Sky": Color(red: 0.0, green: 0.40, blue: 0.92),
        "ink.Rose": Color(red: 0.86, green: 0.07, blue: 0.33),
        "ink.Violet": Color(red: 0.45, green: 0.20, blue: 0.92),
    ]
    private static let key = "palette"

    private var custom: [String: [Double]]
    /// Pure black on white, brighter highlights (Settings ▸ Accessibility).
    var highContrast = UserDefaults.standard.bool(forKey: "highContrast")

    init() { custom = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: [Double]] ?? [:] }

    func color(_ name: String) -> Color {
        if let c = custom[name], c.count == 4 { return Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: c[3]) }
        return Self.defaults[name] ?? .gray
    }

    func set(_ name: String, _ color: Color) {
        let r = color.resolve(in: EnvironmentValues())
        custom[name] = [Double(r.red), Double(r.green), Double(r.blue), Double(r.opacity)]
        UserDefaults.standard.set(custom, forKey: Self.key)
    }

    func reset() { custom = [:]; UserDefaults.standard.removeObject(forKey: Self.key) }
    var isCustom: Bool { !custom.isEmpty }
}

enum Theme {
    private static func c(_ n: String) -> Color { Palette.shared.color(n) }
    static var accent: Color { c("accent") }
    static var stageTop: Color { c("stageTop") }
    static var stageBottom: Color { c("stageBottom") }
    static var paper: Color { Palette.shared.highContrast ? .white : c("paper") }
    /// Dark sheet music: near-black paper, the printed ink inverted to white.
    static var darkPaper: Color { Palette.shared.highContrast ? .black : c("darkPaper") }
    static func paper(dark: Bool) -> Color { dark ? darkPaper : paper }

    static var highlights: [(name: String, color: Color)] { Palette.highlightNames.map { ($0, c($0)) } }
    static func highlight(_ name: String) -> Color { Palette.highlightNames.contains(name) ? c(name) : accent }
    static func ink(_ name: String) -> Color { c(Palette.highlightNames.contains(name) ? "ink." + name : "ink.Amber") }

    static var stage: LinearGradient {
        if Palette.shared.highContrast {
            let c: Color = UserDefaults.standard.string(forKey: "appearance") == "light" ? .white : .black
            return LinearGradient(colors: [c, c], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [stageTop, stageBottom], startPoint: .top, endPoint: .bottom)
    }
}

/// Colour pickers for everything in `Palette`.
struct ColorSettings: View {
    private let palette = Palette.shared

    private func row(_ title: String, _ key: String) -> some View {
        ColorPicker(title, selection: Binding { palette.color(key) } set: { palette.set(key, $0) })
    }

    var body: some View {
        Form {
            Section("Interface") {
                row("Accent", "accent")
                row("Background Top", "stageTop")
                row("Background Bottom", "stageBottom")
            }
            Section("Sheet Music") {
                row("Light Paper", "paper")
                row("Dark Paper", "darkPaper")
            }
            Section("Highlights") {
                ForEach(Palette.highlightNames, id: \.self) { n in
                    row(n, n)
                    row("\(n) on Light Paper", "ink." + n)
                }
            }
            Button("Reset to Defaults", role: .destructive) { palette.reset() }
                .disabled(!palette.isCustom)
        }
        .formStyle(.grouped)
    }
}

extension FocusedValues {
    @Entry var transport: Transport?
    @Entry var inspector: Binding<Bool>?
    @Entry var scoreActions: ScoreActions?
}

struct AppCommands: Commands {
    let library: Library
    @FocusedValue(\.transport) private var transport
    @FocusedValue(\.inspector) private var inspector
    @FocusedValue(\.scoreActions) private var actions
    @AppStorage(Shortcuts.key) private var keys = ""
    @AppStorage("follow") private var follow = true
    @AppStorage("darkPaper") private var darkPaper = false
    @AppStorage("pageTurn") private var pageTurn = true
    @AppStorage("noteGlow") private var noteGlow = true
    @AppStorage("barWash") private var barWash = true
    @AppStorage("playhead") private var showPlayhead = true
    @AppStorage("zoom") private var zoom = 1.0

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { library.showSettings = true }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .help) {
            Button("Maestro Pro Help") { library.showHelp = true }
                .keyboardShortcut("?")
        }
        CommandGroup(replacing: .newItem) {
            Button("New Blank Score…") { Store.shared.unlock(.professional, "Writing a new score") { library.showBlank = true } }
            Button("Import Score…") { library.showImporter = true }
                .keyboardShortcut("o")
        }
        CommandMenu("Playback") {
            Group {
                Button(transport?.isPlaying == true ? "Pause" : "Play") { transport?.toggle() }
                    .shortcut(.playPause, keys)
                Button("Go to Beginning") { transport?.seek(to: transport?.start ?? 0) }
                    .shortcut(.toStart, keys)
                Divider()
                Button("Previous Bar") { transport?.skipBar(-1) }
                    .shortcut(.previousBar, keys)
                Button("Next Bar") { transport?.skipBar(1) }
                    .shortcut(.nextBar, keys)
                Button("Previous Page") { actions?.previousPage() }
                    .shortcut(.previousPage, keys)
                    .disabled(actions == nil)
                Button("Next Page") { actions?.nextPage() }
                    .shortcut(.nextPage, keys)
                    .disabled(actions == nil)
                Divider()
                Button("Slower") { if let t = transport { t.speed = max(0.5, ((t.speed - 0.05) * 20).rounded() / 20) } }
                    .shortcut(.slower, keys)
                Button("Faster") { if let t = transport { t.speed = min(1.5, ((t.speed + 0.05) * 20).rounded() / 20) } }
                    .shortcut(.faster, keys)
                Divider()
                Button(transport?.metronome == true ? "Turn Metronome Off" : "Turn Metronome On") { transport?.metronome.toggle() }
                    .shortcut(.metronome, keys)
                Button(transport?.countInEnabled == true ? "Turn Count In Off" : "Turn Count In On") { transport?.countInEnabled.toggle() }
                    .shortcut(.countIn, keys)
            }
            .disabled(transport == nil || library.typing)
        }
        CommandMenu("Score") {
            Group {
                Button("Edit Score") { actions?.editScore() }.shortcut(.editScore, keys)
                Button("Annotate") { actions?.annotate() }.shortcut(.annotate, keys)
                Divider()
                Button("Wait for Me") { actions?.waitForMe() }.shortcut(.waitForMe, keys)
                Button("Record Myself") { actions?.record() }.shortcut(.record, keys)
            }
            .disabled(actions == nil || library.typing)
            Button("Tuner") { Store.shared.unlock(.performer, "The tuner") { library.showTuner = true } }.shortcut(.tuner, keys).disabled(library.typing)
        }
        CommandGroup(after: .sidebar) {
            Group {
                Button("Zoom In") { zoom = min(2.5, ((zoom * 1.2) * 20).rounded() / 20) }.shortcut(.zoomIn, keys)
                Button("Zoom Out") { zoom = max(0.6, ((zoom / 1.2) * 20).rounded() / 20) }.shortcut(.zoomOut, keys)
                Button("Fit to Width") { zoom = 1 }.shortcut(.fitWidth, keys)
                Divider()
                Toggle("Follow Playback", isOn: $follow).shortcut(.follow, keys)
                Toggle("Dark Sheet Music", isOn: $darkPaper).shortcut(.darkSheet, keys)
                Toggle("Turn Pages Like a Book", isOn: $pageTurn).shortcut(.pageTurn, keys)
                Toggle("Highlight Notes", isOn: Store.shared.gate(.performer, "Note highlighting", $noteGlow)).shortcut(.highlightNotes, keys)
                Toggle("Highlight Bar", isOn: Store.shared.gate(.performer, "Bar highlighting", $barWash)).shortcut(.highlightBar, keys)
                Toggle("Moving Line", isOn: Store.shared.gate(.performer, "The moving line", $showPlayhead)).shortcut(.movingLine, keys)
                Divider()
                Button("Chord View") { actions?.chordView() }.shortcut(.chordView, keys).disabled(actions == nil)
                Button("Lyrics Instead of Music") { actions?.lyricsView() }.shortcut(.lyricsView, keys).disabled(actions == nil)
            }
            .disabled(library.typing)
            Button(inspector?.wrappedValue == true ? "Hide Inspector" : "Show Inspector") { inspector?.wrappedValue.toggle() }
                .shortcut(.inspector, keys)
                .disabled(inspector == nil || library.typing)
        }
    }
}

struct ColorSettingsButton: View {
    @State private var show = false
    var body: some View {
        Button("Customise Colours…") { show = true }
            .sheet(isPresented: $show) {
                VStack(spacing: 0) {
                    ColorSettings()
                    Button("Done") { show = false }.keyboardShortcut(.defaultAction).padding()
                }
                .frame(minWidth: 360, minHeight: 480)
            }
    }
}

#if DEBUG
/// With `-landscape`, lays the app out sideways so a portrait simulator screenshot rotated 90° clockwise is a landscape one.
private struct ForcedLandscape: ViewModifier {
    func body(content: Content) -> some View {
        if CommandLine.arguments.contains("-landscape") {
            GeometryReader { g in
                content.frame(width: g.size.height, height: CommandLine.arguments.contains("-mac") ? 860 : g.size.width)
                    .rotationEffect(.degrees(-90))
                    .frame(width: g.size.width, height: g.size.height)
            }.ignoresSafeArea()
        } else { content }
    }
}
#endif
