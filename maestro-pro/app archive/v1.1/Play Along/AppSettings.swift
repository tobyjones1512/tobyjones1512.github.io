import SafariServices
import SwiftUI

/// Reads a stored preference without needing a view.
enum Pref {
    static func bool(_ key: String, _ fallback: Bool) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? fallback }
    static func double(_ key: String, _ fallback: Double) -> Double { UserDefaults.standard.object(forKey: key) as? Double ?? fallback }
    static func string(_ key: String, _ fallback: String) -> String { UserDefaults.standard.string(forKey: key) ?? fallback }
}

import UIKit

// MARK: - Looks

/// The app's surroundings: light or dark, the stage behind the music, the accent.
struct StylePreset: Identifiable {
    let name: String
    let light: Bool
    let top: Color, bottom: Color
    let accent: Color
    var id: String { name }

    static let all: [StylePreset] = [
        .init(name: "Leather", light: false, top: Color(red: 0.17, green: 0.12, blue: 0.09), bottom: Color(red: 0.08, green: 0.055, blue: 0.042), accent: Color(red: 1.0, green: 0.71, blue: 0.27)),
        .init(name: "Charcoal", light: false, top: Color(red: 0.075, green: 0.078, blue: 0.09), bottom: Color(red: 0.035, green: 0.036, blue: 0.042), accent: Color(red: 1.0, green: 0.71, blue: 0.27)),
        .init(name: "Black", light: false, top: .black, bottom: .black, accent: Color(red: 1.0, green: 0.71, blue: 0.27)),
        .init(name: "Midnight", light: false, top: Color(red: 0.05, green: 0.07, blue: 0.15), bottom: Color(red: 0.02, green: 0.03, blue: 0.08), accent: Color(red: 0.45, green: 0.72, blue: 1.0)),
        .init(name: "Forest", light: false, top: Color(red: 0.05, green: 0.11, blue: 0.09), bottom: Color(red: 0.02, green: 0.05, blue: 0.04), accent: Color(red: 0.42, green: 0.88, blue: 0.62)),
        .init(name: "Beige", light: true, top: Color(red: 0.93, green: 0.89, blue: 0.80), bottom: Color(red: 0.87, green: 0.82, blue: 0.72), accent: Color(red: 0.74, green: 0.36, blue: 0.0)),
        .init(name: "Cream", light: true, top: Color(red: 0.98, green: 0.96, blue: 0.90), bottom: Color(red: 0.93, green: 0.90, blue: 0.82), accent: Color(red: 0.74, green: 0.36, blue: 0.0)),
        .init(name: "Sepia", light: true, top: Color(red: 0.89, green: 0.82, blue: 0.69), bottom: Color(red: 0.80, green: 0.72, blue: 0.58), accent: Color(red: 0.55, green: 0.24, blue: 0.0)),
        .init(name: "Yellow", light: true, top: Color(red: 0.99, green: 0.96, blue: 0.78), bottom: Color(red: 0.95, green: 0.90, blue: 0.64), accent: Color(red: 0.62, green: 0.30, blue: 0.0)),
        .init(name: "Sky", light: true, top: Color(red: 0.88, green: 0.93, blue: 0.98), bottom: Color(red: 0.79, green: 0.87, blue: 0.96), accent: Color(red: 0.0, green: 0.36, blue: 0.85)),
        .init(name: "Grey", light: true, top: Color(red: 0.92, green: 0.92, blue: 0.93), bottom: Color(red: 0.84, green: 0.84, blue: 0.86), accent: Color(red: 0.0, green: 0.36, blue: 0.85)),
        .init(name: "White", light: true, top: .white, bottom: Color(red: 0.94, green: 0.94, blue: 0.95), accent: Color(red: 0.0, green: 0.36, blue: 0.85)),
    ]

    func apply() {
        Palette.shared.set("stageTop", top)
        Palette.shared.set("stageBottom", bottom)
        Palette.shared.set("accent", accent)
        UserDefaults.standard.set(light ? "light" : "dark", forKey: "appearance")
        UserDefaults.standard.set(name, forKey: "stylePreset")
    }
}

/// The colour of the page the music is printed on. Kind to the eyes, or to dyslexia, or to a bright room.
struct PaperPreset: Identifiable {
    let name: String
    let color: Color
    var id: String { name }

    static let all: [PaperPreset] = [
        .init(name: "White", color: .white),
        .init(name: "Cream", color: Color(red: 0.985, green: 0.972, blue: 0.94)),
        .init(name: "Beige", color: Color(red: 0.96, green: 0.92, blue: 0.84)),
        .init(name: "Sepia", color: Color(red: 0.92, green: 0.85, blue: 0.72)),
        .init(name: "Yellow", color: Color(red: 1.0, green: 0.98, blue: 0.78)),
        .init(name: "Peach", color: Color(red: 0.99, green: 0.91, blue: 0.85)),
        .init(name: "Green", color: Color(red: 0.88, green: 0.95, blue: 0.88)),
        .init(name: "Blue", color: Color(red: 0.87, green: 0.92, blue: 0.99)),
        .init(name: "Grey", color: Color(red: 0.88, green: 0.88, blue: 0.89)),
    ]
}

extension Palette {
    /// Highlight colours that stay distinct for the common kinds of colour blindness (Okabe–Ito).
    func useColourBlindSafeHighlights() {
        set("Amber", Color(red: 0.90, green: 0.62, blue: 0.0))
        set("Mint", Color(red: 0.0, green: 0.62, blue: 0.45))
        set("Sky", Color(red: 0.34, green: 0.71, blue: 0.91))
        set("Rose", Color(red: 0.84, green: 0.37, blue: 0.0))
        set("Violet", Color(red: 0.80, green: 0.47, blue: 0.65))
        set("ink.Amber", Color(red: 0.70, green: 0.40, blue: 0.0))
        set("ink.Mint", Color(red: 0.0, green: 0.45, blue: 0.33))
        set("ink.Sky", Color(red: 0.0, green: 0.45, blue: 0.75))
        set("ink.Rose", Color(red: 0.70, green: 0.25, blue: 0.0))
        set("ink.Violet", Color(red: 0.65, green: 0.25, blue: 0.50))
    }
}

// MARK: - The settings page

struct AppSettingsView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    @AppStorage("advancedMode") private var advanced = false
    @State private var showHelp = false
    @State private var showFeedback = false
    @State private var showDiversity = false
    @State private var showFormats = false
    @State private var showShortcuts = false
    // General
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("stylePreset") private var stylePreset = "Charcoal"
    @AppStorage("keepAwake") private var keepAwake = true
    @AppStorage("showClock") private var showClock = false
    @AppStorage("hideSidebarOnPlay") private var hideSidebar = true
    @AppStorage("sortBy") private var sortBy = "added"
    @AppStorage("checkFolders") private var checkFolders = true
    // Playback
    @AppStorage("defaultMetronome") private var defaultMetronome = false
    @AppStorage("defaultCountIn") private var defaultCountIn = true
    @AppStorage("defaultSpeed") private var defaultSpeed = 1.0
    @AppStorage("defaultVolume") private var defaultVolume = 0.8
    @AppStorage("instrument") private var instrument = Instrument.off.rawValue
    @AppStorage("autoPlay") private var autoPlay = false
    // Sheet music
    @AppStorage("darkPaper") private var darkPaper = false
    @AppStorage("zoom") private var zoom = 1.0
    @AppStorage("follow") private var follow = true
    @AppStorage("noteGlow") private var noteGlow = true
    @Environment(\.openURL) private var openURL
    @AppStorage("barWash") private var barWash = true
    @AppStorage("playhead") private var showPlayhead = true
    @AppStorage("highlight") private var highlight = "Amber"
    @AppStorage("paperName") private var paperName = "Cream"
    // Lyrics
    @AppStorage("lyricsSize") private var lyricsSize = 1.0
    @AppStorage("lyricsAnimate") private var lyricsAnimate = true
    @AppStorage("lyricsStrength") private var lyricsStrength = "gentle"
    @AppStorage("lyricsProgress") private var lyricsProgress = true
    @AppStorage("lyricsBlur") private var lyricsBlur = true
    @AppStorage("lyricsBreakBar") private var lyricsBreakBar = false
    @AppStorage("lyricsBold") private var lyricsBold = true
    @AppStorage("lyricsFont") private var lyricsFont = "rounded"
    @AppStorage("lyricsAlign") private var lyricsAlign = "leading"
    @AppStorage("lyricsPartForceLeft") private var lyricsPartForceLeft = false
    @AppStorage("lyricsPartColor1") private var lyricsPartColor1 = ""
    @AppStorage("lyricsPartColor2") private var lyricsPartColor2 = ""
    @AppStorage("lyricsPartColor3") private var lyricsPartColor3 = ""
    // Accessibility
    @AppStorage("uiTextSize") private var uiTextSize = "default"
    @AppStorage("boldUI") private var boldUI = false
    @AppStorage("highContrast") private var highContrast = false
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("largeControls") private var largeControls = false
    @AppStorage("visualBeat") private var visualBeat = false
    @AppStorage("hapticBeat") private var hapticBeat = false
    @AppStorage("announceBars") private var announceBars = false
    @State private var showColours = false
    @State private var confirmReset = false
    @State private var rescanning = false
    @State private var rescanned: String?
    @State private var tidied: String?
    @AppStorage("autoTidyTitles") private var autoTidy = true

    var body: some View {
        NavigationStack {
            Form {
                #if DEBUG
                Section { NavigationLink { DebugSettings() } label: { Label("Debug", systemImage: "ladybug") } }
                #endif
                Section {
                    let store = Store.shared
                    LabeledContent("Your Plan", value: store.tier.name)
                    if store.tier < .professional {
                        Button(store.tier == .free ? String(localized: "Choose a Plan") : String(localized: "Upgrade to Professional"), systemImage: "sparkles") {
                            store.present(store.tier == .free ? .performer : .professional, store.tier == .free ? "Everything" : String(localized: "The score editor"))
                        }
                    }
                    if store.tier > .free {
                        Button("Manage Subscription", systemImage: "creditcard") { openURL(URL(string: "https://apps.apple.com/account/subscriptions")!) }
                    }
                    Button("Restore Purchases", systemImage: "arrow.clockwise") { Task { await store.restore() } }
                }
                Section {
                    Button("Provide Feedback", systemImage: "bubble.left.and.text.bubble.right") { showFeedback = true }
                    Button(DiversitySurvey.name, systemImage: "person.3") { showDiversity = true }
                }
                Section {
                    Button("Help and Guide", systemImage: "questionmark.circle") { showHelp = true }
                    Button("Supported File Formats", systemImage: "doc.on.doc") { showFormats = true }
                    Button("Keyboard Shortcuts", systemImage: "keyboard") { showShortcuts = true }
                }
                modeSection
                playbackSection
                sheetSection
                listeningSection
                lyricsSection
                if advanced { librarySection }
                accessibilitySection
                // How the app looks comes last: it is set once, and the rest is used every time.
                appearanceSection
                if AppIconPicker.available { AppIconPicker() }
                surfacesSection
                Section {
                    if advanced { Button("Customise Every Colour…") { showColours = true } }
                    Button("Reset All Settings", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Your library and annotations are never touched by a reset.")
                }
                Section {
                    CreditBanner()
                        .listRowInsets(EdgeInsets(top: 28, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }
            .formStyle(.grouped)
            .defaultScrollAnchor(CommandLine.arguments.contains("-settingsbottom") ? .bottom : nil)   // test hook
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showColours) {
                NavigationStack {
                    ColorSettings()
                        .navigationTitle("Colours")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showColours = false } } }
                }
            }
            .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive, action: resetAll)
            }
        }
        .sheet(isPresented: $showFeedback) { FeedbackView() }
        .sheet(isPresented: $showDiversity) { SafariView(url: DiversitySurvey.url).ignoresSafeArea() }
        .sheet(isPresented: $showHelp) { HelpView() }
        .sheet(isPresented: $showFormats) { FormatsView() }
        .sheet(isPresented: $showShortcuts) { ShortcutsView() }
        #if DEBUG
        .onAppear { if CommandLine.arguments.contains("-shortcuts") { showShortcuts = true } }
        #endif
        .frame(minWidth: 380, minHeight: 520)
    }

    // MARK: Sections

    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $advanced.animation(.smooth)) {
                Text("Simple").tag(false)
                Text("Advanced").tag(true)
            }
            .pickerStyle(.segmented)
        } header: { Text("Mode") } footer: {
            Text(advanced
                 ? String(localized: "Everything is available: the backing track editor, the score editor, sync tools, key and metre overrides, Play Together, sharing and exporting, colours and linked folders.")
                 : String(localized: "Just the essentials: open a score, rehearse it, set tempo and key. Switch to Advanced for the editors, sync tools, sharing and the rest."))
        }
    }

    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                Text("Dark").tag("dark")
                Text("Light").tag("light")
                Text("Match System").tag("system")
            }
            .pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(StylePreset.all) { p in
                        Button { withAnimation(.smooth) { p.apply(); stylePreset = p.name; appearance = p.light ? "light" : "dark" } } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(LinearGradient(colors: [p.top, p.bottom], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 64, height: 44)
                                    .overlay(Circle().fill(p.accent).frame(width: 14, height: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(stylePreset == p.name ? Color.accentColor : .gray.opacity(0.4), lineWidth: stylePreset == p.name ? 3 : 1))
                                Text(LocalizedStringKey(p.name)).font(.caption).foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(p.name) background")
                        .accessibilityAddTraits(stylePreset == p.name ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            Picker("Sort Library By", selection: $sortBy) {
                Text("Date Added").tag("added")
                Text("Title").tag("title")
            }
            Toggle("Keep the Screen On While Playing", isOn: $keepAwake)
            Toggle("Hide the Library While Playing", isOn: $hideSidebar)
            Toggle("Show the Time Above Music and Lyrics", isOn: $showClock)
        } header: { Text("Appearance") } footer: {
            Text("A backdrop sets the background, whether the app is light or dark, and the accent colour together.")
        }
    }

    private var playbackSection: some View {
        Section {
            Toggle("Metronome On by Default", isOn: $defaultMetronome)
            Toggle("Count In by Default", isOn: $defaultCountIn)
            Toggle("Start Playing When a Score Opens", isOn: $autoPlay)
            LabeledContent("Practice Speed") {
                Picker("Practice Speed", selection: $defaultSpeed) {
                    ForEach([0.5, 0.6, 0.7, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25], id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
                }
                .labelsHidden()
            }
            Picker("Play Scores As", selection: $instrument) {
                ForEach(Instrument.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0.rawValue) }
            }
            Slider(value: $defaultVolume, in: 0.1...1) { Text("Instrument Volume") } minimumValueLabel: { Image(systemName: "speaker") } maximumValueLabel: { Image(systemName: "speaker.wave.3") }
        } header: { Text("Playback") } footer: {
            Text("These apply to each score you open. Change one for a single score from its own controls.")
        }
    }

    @AppStorage("pageTurn") private var pageTurn = true

    private var sheetSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PaperPreset.all) { p in
                        Button { withAnimation(.smooth) { Palette.shared.set("paper", p.color); paperName = p.name; darkPaper = false } } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(p.color)
                                    .frame(width: 46, height: 58)
                                    .overlay(VStack(spacing: 5) { ForEach(0..<4, id: \.self) { _ in Rectangle().fill(.black.opacity(0.55)).frame(height: 0.8) } }.padding(.horizontal, 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(paperName == p.name && !darkPaper ? Color.accentColor : .gray.opacity(0.4), lineWidth: paperName == p.name && !darkPaper ? 3 : 1))
                                Text(LocalizedStringKey(p.name)).font(.caption).foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(p.name) paper")
                        .accessibilityAddTraits(paperName == p.name && !darkPaper ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            Toggle("White Music on Black Paper", isOn: $darkPaper.animation(.smooth))
            Toggle("Follow Playback", isOn: $follow)
            Toggle("Turn Pages Like a Book", isOn: $pageTurn)
            Toggle("Highlight Notes", isOn: Store.shared.gate(.performer, "Note highlighting", $noteGlow))
            Toggle("Highlight Bar", isOn: Store.shared.gate(.performer, "Bar highlighting", $barWash))
            Toggle("Moving Line", isOn: Store.shared.gate(.performer, "The moving line", $showPlayhead))
            Picker("Highlight Colour", selection: $highlight) {
                ForEach(Palette.highlightNames, id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
            }
            LabeledContent("Zoom") {
                Picker("Zoom", selection: $zoom) {
                    ForEach([0.8, 1.0, 1.2, 1.4, 1.6, 2.0, 2.5], id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
                }
                .labelsHidden()
            }
        } header: { Text("Sheet Music") } footer: {
            Text("Paper colour tints the page behind the notes, and scanned pages take it too.")
        }
    }

    private var lyricsSection: some View {
        Section {
            Picker("Typeface", selection: $lyricsFont) {
                Text("Rounded").tag("rounded")
                Text("Standard").tag("default")
                Text("Serif").tag("serif")
                Text("Monospaced").tag("mono")
            }
            Slider(value: $lyricsSize, in: 0.6...1.8, step: 0.1) { Text("Text Size") } minimumValueLabel: { Text("A").font(.caption) } maximumValueLabel: { Text("A").font(.title3) }
            Toggle("Bold Text", isOn: $lyricsBold)
            Picker("Alignment", selection: $lyricsAlign) {
                Text("Left").tag("leading")
                Text("Centred").tag("center")
            }
            .pickerStyle(.segmented)
            Toggle("Animate Syllables", isOn: $lyricsAnimate.animation(.smooth))
            if lyricsAnimate {
                Picker("Animation", selection: $lyricsStrength) {
                    Text("Gentle").tag("gentle")
                    Text("Full").tag("full")
                }
                .pickerStyle(.segmented)
            }
            Toggle("Show Syllable Progress", isOn: $lyricsProgress)
            Toggle("Blur Lines Not Being Sung", isOn: $lyricsBlur)
            Toggle("Progress Bar in Breaks", isOn: $lyricsBreakBar)
            Toggle("All Singers on the Left", isOn: $lyricsPartForceLeft)
            ColorPicker("Singer 1 Colour", selection: colorBinding(for: $lyricsPartColor1), supportsOpacity: false)
            ColorPicker("Singer 2 Colour", selection: colorBinding(for: $lyricsPartColor2), supportsOpacity: false)
            ColorPicker("Singer 3 Colour", selection: colorBinding(for: $lyricsPartColor3), supportsOpacity: false)
        } header: { Text("Lyrics") } footer: {
            Text("Stressed syllables swell softly as they’re sung. Turn animation off for still lines, and syllable progress off to light each line all at once.")
        }
    }

    private var librarySection: some View {
        Section {
            if library.linkedFolders.isEmpty {
                Text("No folders linked.").foregroundStyle(.secondary)
            }
            ForEach(library.linkedFolders, id: \.self) { url in
                HStack {
                    Label(url.lastPathComponent, systemImage: "folder")
                    Spacer()
                    Button("Remove", role: .destructive) { library.unlink(url) }.buttonStyle(.borderless)
                }
            }
            Button { library.showFolderPicker = true; dismiss() } label: { Label("Link a Folder from Files…", systemImage: "folder.badge.plus") }
            Button {
                rescanning = true
                Task { let r = await library.rescanLinked(); rescanned = r.summary; rescanning = false }
            } label: {
                HStack { Label("Check Linked Folders Now", systemImage: "arrow.triangle.2.circlepath"); if rescanning { Spacer(); ProgressView() } }
            }
            .disabled(library.linkedFolders.isEmpty || rescanning)
            if let rescanned { Text(rescanned).font(.caption).foregroundStyle(.secondary) }
            Toggle("Check Linked Folders When the App Opens", isOn: $checkFolders)
            Toggle("Tidy Titles on Import", isOn: $autoTidy)
            Button {
                let n = library.tidyTitles()
                tidied = n == 0 ? String(localized: "All titles are already tidy.") : (n == 1 ? String(localized: "1 title tidied.") : String(localized: "\(n) titles tidied."))
            } label: { Label("Tidy Up Titles", systemImage: "textformat") }
            if let tidied { Text(tidied).font(.caption).foregroundStyle(.secondary) }
            LabeledContent("iCloud Sync", value: library.isCloud ? "On" : "Off")
        } header: { Text("Library") } footer: {
            Text("Everything in a linked folder is added to your library, and new files are picked up on the next check. A recording or lyrics file with the same name as a score goes with it.")
        }
    }

    @AppStorage("micSensitivity") private var micSensitivity = 0.6
    @AppStorage("tunerA4") private var tunerA4 = 440.0
    @AppStorage("tunerTolerance") private var tunerTolerance = 10.0
    @AppStorage("tunerGoal") private var tunerGoal = 10.0
    @AppStorage("practiceTolerance") private var practiceTolerance = 30.0
    @AppStorage("practiceHold") private var practiceHold = 0.8
    @AppStorage("practiceAnyOctave") private var practiceAnyOctave = false

    /// How the app listens to you: for the tuner and for Wait for Me.
    private var listeningSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                HStack { Text("Microphone Sensitivity"); Spacer(); Text("\(Int((micSensitivity * 100).rounded()))%").foregroundStyle(.secondary).monospacedDigit() }
                Slider(value: $micSensitivity, in: 0.1...1) { Text("Microphone Sensitivity") }.tint(Theme.accent)
            }
            Stepper(value: $tunerA4, in: 415...466, step: 1) { LabeledContent("Tuning: A =", value: "\(Int(tunerA4)) Hz") }
            Picker("Wait for Me: In Tune Within", selection: $practiceTolerance) {
                Text("±15¢ (strict)").tag(15.0); Text("±30¢").tag(30.0); Text("±50¢ (relaxed)").tag(50.0)
            }
            Picker("Wait for Me: Hold for", selection: $practiceHold) {
                Text("Half the length").tag(0.5); Text("Most of it").tag(0.8); Text("All of it").tag(1.0)
            }
            Toggle("Wait for Me: Accept Any Octave", isOn: $practiceAnyOctave)
            Picker("Tuner: In Tune Within", selection: $tunerTolerance) {
                Text("±5¢ (strict)").tag(5.0); Text("±10¢").tag(10.0); Text("±20¢ (relaxed)").tag(20.0)
            }
            Picker("Tuner: Steady Note Goal", selection: $tunerGoal) {
                ForEach([5.0, 10, 20, 30], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
            }
            Button { Store.shared.unlock(.performer, "The tuner") { library.showTuner = true; dismiss() } } label: { Label("Open the Tuner", systemImage: "tuningfork") }
        } header: { Text("Listening") } footer: {
            Text("Used by the tuner and by Wait for Me, which listen through the microphone. Turn sensitivity up in a quiet room or for a soft instrument, and down if it hears noise. A cent (¢) is a hundredth of a semitone.")
        }
    }

    private var accessibilitySection: some View {
        Section {
            Picker("App Text Size", selection: $uiTextSize) {
                Text("Default").tag("default")
                Text("Large").tag("large")
                Text("Larger").tag("larger")
                Text("Largest").tag("largest")
            }
            Toggle("Bold Text", isOn: $boldUI)
            Toggle("High Contrast", isOn: $highContrast.animation(.smooth))
                .onChange(of: highContrast) { _, on in Palette.shared.highContrast = on }
            Toggle("Larger Playback Controls", isOn: $largeControls)
            Toggle("Reduce Motion", isOn: $reduceMotion)
            Toggle("Flash on the Beat", isOn: $visualBeat)
            Toggle("Tap on the Beat (Haptics)", isOn: $hapticBeat)
            Toggle("Announce Bars with VoiceOver", isOn: $announceBars)
            Button("Colour-Blind-Friendly Highlights") { Palette.shared.useColourBlindSafeHighlights() }
        } header: { Text("Accessibility") } footer: {
            Text("The app also follows your device’s Larger Text, Bold Text, Increase Contrast and Reduce Motion settings. Page colours are under Sheet Music, and backdrops under Appearance.")
        }
    }

    @AppStorage(Surfaces.masterKey) private var surfaceMaster = true
    @AppStorage(Surfaces.shadeKey) private var surfaceShade = 1.0
    @AppStorage("surface.paper") private var surfacePaper = 1.0
    @AppStorage("surface.desk") private var surfaceDesk = 1.0
    @AppStorage("surface.leather") private var surfaceLeather = 1.0
    @AppStorage("surface.metal") private var surfaceMetal = 1.0

    /// How real the materials look: paper fibre, leather, brushed metal, and the shadow under the page.
    private var surfacesSection: some View {
        Section {
            Toggle("Realistic Surfaces", isOn: $surfaceMaster.animation(.smooth))
            if surfaceMaster {
                strengthRow("Paper Grain", $surfacePaper)
                strengthRow("Page Shadow and Curl", $surfaceShade)
                strengthRow("Desk Leather", $surfaceDesk)
                strengthRow("Leather Buttons", $surfaceLeather)
                strengthRow("Brushed Metal", $surfaceMetal)
                Button("Reset Surfaces") { withAnimation(.smooth) { surfacePaper = 1; surfaceShade = 1; surfaceDesk = 1; surfaceLeather = 1; surfaceMetal = 1 } }
                    .disabled([surfacePaper, surfaceShade, surfaceDesk, surfaceLeather, surfaceMetal].allSatisfy { $0 == 1 })
            }
        } header: { Text("Surfaces") } footer: {
            Text("The paper, desk, buttons and control panels are drawn as real materials. Turn each one down for a flatter look, or switch them all off. High Contrast turns them off too.")
        }
    }

    private func strengthRow(_ title: LocalizedStringKey, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title); Spacer(); Text(value.wrappedValue == 0 ? "Off" : "\(Int((value.wrappedValue * 100).rounded()))%").foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: 0...2) { Text(title) }.tint(Theme.accent)
        }
        .accessibilityElement(children: .combine)
    }

    private func colorBinding(for hex: Binding<String>) -> Binding<Color> {
        Binding(
            get: {
                guard hex.wrappedValue.count == 6, let v = UInt32(hex.wrappedValue, radix: 16) else { return .primary }
                return Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
            },
            set: { color in
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                UIColor(color).getRed(&r, green: &g, blue: &b, alpha: nil)
                hex.wrappedValue = String(format: "%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
            }
        )
    }

    private func resetAll() {
        let keys = ["appearance", "stylePreset", "keepAwake", "showClock", "hideSidebarOnPlay", "sortBy", "checkFolders", "defaultMetronome", "defaultCountIn", "defaultSpeed",
                    "defaultVolume", "instrument", "autoPlay", "darkPaper", "zoom", "follow", "noteGlow", "barWash", "playhead", "highlight", "paperName",
                    "lyricsSize", "lyricsAnimate", "lyricsStrength", "lyricsProgress", "lyricsBlur", "lyricsBreakBar", "lyricsBold", "lyricsFont", "lyricsAlign", "lyricsPartForceLeft", "lyricsPartColor1", "lyricsPartColor2", "lyricsPartColor3", "uiTextSize", "boldUI", "highContrast", "reduceMotion",
                    "largeControls", "visualBeat", "hapticBeat", "announceBars", "pageTurn", "reviewSlack", Shortcuts.key, "micSensitivity", "tunerA4", "tunerTolerance", "tunerGoal",
                    "practiceTolerance", "practiceHold", "practiceAnyOctave"] + Surfaces.all
        for k in keys { UserDefaults.standard.removeObject(forKey: k) }
        Palette.shared.reset()
        Palette.shared.highContrast = false
        appearance = "dark"; stylePreset = "Charcoal"
    }
}

// MARK: - What playback does besides the music

/// Keeps the screen awake, taps or flashes the beat, and speaks the bar number, as the settings ask.
struct PlaybackExtras: ViewModifier {
    let transport: Transport
    @AppStorage("keepAwake") private var keepAwake = true
    @AppStorage("showClock") private var showClock = false
    @AppStorage("visualBeat") private var visualBeat = false
    @AppStorage("hapticBeat") private var hapticBeat = false
    @AppStorage("announceBars") private var announceBars = false

    func body(content: Content) -> some View {
        content
            .overlay { if visualBeat { BeatFlash(transport: transport).allowsHitTesting(false) } }
            .background { if hapticBeat || announceBars { BeatTicker(transport: transport, haptic: hapticBeat, announce: announceBars) } }
            .onChange(of: transport.isPlaying, initial: true) { _, playing in UIApplication.shared.isIdleTimerDisabled = playing && keepAwake }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

extension View {
    func playbackExtras(_ transport: Transport) -> some View { modifier(PlaybackExtras(transport: transport)) }
}

/// The beat number, whole, and whether it opens a bar.
private func beatInfo(_ transport: Transport) -> (beat: Int, downbeat: Bool, bar: Int?)? {
    guard transport.isPlaying else { return nil }
    let b = transport.beat
    let whole = Int(b.rounded(.down))
    let measures = transport.timeline.measures
    guard let i = transport.timeline.measureIndex(at: b), i < measures.count else { return (whole, false, nil) }
    let m = measures[i]
    return (whole, b >= m.start && b - m.start < 1, (m.bar) + 1)
}

private struct BeatTicker: View {
    let transport: Transport
    let haptic: Bool
    let announce: Bool

    var body: some View {
        let info = beatInfo(transport)
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: info?.beat) { _, new in
                guard let info, new != nil else { return }
                if haptic { UIImpactFeedbackGenerator(style: info.downbeat ? .heavy : .light).impactOccurred() }
                if announce, info.downbeat, UIAccessibility.isVoiceOverRunning, let bar = info.bar {
                    UIAccessibility.post(notification: .announcement, argument: String(localized: "Bar \(bar)"))
                }
            }
    }
}

/// A pulse around the edge of the screen on each beat, stronger on the first of a bar.
private struct BeatFlash: View {
    let transport: Transport
    @State private var pulse = 0.0

    var body: some View {
        let info = beatInfo(transport)
        RoundedRectangle(cornerRadius: 0)
            .strokeBorder(Theme.accent, lineWidth: 14)
            .opacity(pulse)
            .ignoresSafeArea()
            .onChange(of: info?.beat) { _, new in
                guard let info, new != nil else { return }
                pulse = info.downbeat ? 0.9 : 0.45
                withAnimation(.easeOut(duration: 0.28)) { pulse = 0 }
            }
    }
}

/// The Userbase Diversity Questionnaire, offered in Settings and at the end of onboarding.
enum DiversitySurvey {
    static let url = URL(string: "https://app.jackpoll.org/s/x0R2lkqRkD")!
    /// "Poll" is the word used in the US; "Questionnaire" everywhere else.
    static var name: String { Locale.current.region == .unitedStates ? "Userbase Diversity Poll" : "Userbase Diversity Questionnaire" }
}

/// A web page shown inside the app, with Safari's own controls.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
