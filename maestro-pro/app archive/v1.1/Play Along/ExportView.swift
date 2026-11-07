import SwiftUI
import UIKit

/// Makes a video of a library score the way it looks in the player (key, highlights, drawings, instrument,
/// backing track), then offers the file.
struct ExportView: View {
    let item: ScoreItem
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("darkPaper") private var darkPaper = false
    @AppStorage("noteGlow") private var noteGlow = true
    @AppStorage("barWash") private var barWash = true
    @AppStorage("playhead") private var showPlayhead = true
    @AppStorage("highlight") private var highlight = "Amber"
    @AppStorage("instrumentKey") private var instrumentKey = InstrumentKey.concert.rawValue
    @AppStorage("zoom") private var zoom = 1.0
    @State private var stage = String(localized: "Reading the score…")
    @State private var progress = 0.0
    @State private var result: URL?
    @State private var failure: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "film").font(.system(size: 44)).foregroundStyle(Theme.accent)
            Text("Export Video").font(.title2.bold())
            Text(item.title).foregroundStyle(.secondary)
            if let result {
                Text("Your video is ready.").foregroundStyle(.secondary)
                ShareLink(item: result) { Label("Save or Share Video", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderedProminent)
            } else if let failure {
                Text(failure).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                Text("A landscape video of the music with your highlights, drawings and sound, as the player shows it. Keep the app open while it’s made.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                ProgressView(value: progress).tint(Theme.accent)
                Text(stage).font(.footnote).foregroundStyle(.secondary)
            }
            Button(result == nil ? "Cancel" : "Done") { task?.cancel(); dismiss() }
        }
        .padding(30)
        .frame(minWidth: 340, minHeight: 320)
        .task { start() }
        .interactiveDismissDisabled(result == nil && failure == nil)
        #if DEBUG
        .onChange(of: result) { _, url in   // test hook: leave the file where a script can find it
            if CommandLine.arguments.contains("-export"), let url { try? FileManager.default.removeItem(atPath: "/tmp/play-along-export.mp4"); try? FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: "/tmp/play-along-export.mp4")) }
        }
        .onChange(of: failure) { _, f in if CommandLine.arguments.contains("-export"), let f { try? f.write(toFile: "/tmp/play-along-export.txt", atomically: true, encoding: .utf8) } }
        #endif
    }

    private func start() {
        guard task == nil else { return }
        let item = item, key = InstrumentKey(rawValue: instrumentKey) ?? .concert, zoom = zoom, isPDF = item.isPDF
        let shift = (item.transpose ?? 0) + key.offset - item.writtenKey.offset
        let url = library.scoreURL(item), converted = library.convertedURL(item), track = library.trackURL(item)
        let drawingsURL = library.folder(item).appending(path: "annotations\(shift)-\(Int(zoom * 100)).plist")
        let ui: (Color) -> CGColor = { UIColor($0).cgColor }
        let look = (dark: darkPaper, notes: noteGlow, bar: barWash, line: showPlayhead, tint: ui(Theme.highlight(highlight)), ink: ui(Theme.ink(highlight)), paper: ui(Theme.paper), stage: ui(Theme.stageBottom))
        let instrument = Instrument(rawValue: UserDefaults.standard.string(forKey: "instrument") ?? "") ?? .off
        let staffVoices = (item.staffInstruments ?? []).map { Instrument(rawValue: $0) }
        task = Task {
            do {
                let (pages, timeline, start) = try await Task.detached(priority: .userInitiated) { () throws -> ([CGPDFPage], Timeline, Double) in
                    var metre = item.beatsPerBar
                    let loaded: LoadedScore
                    if isPDF {
                        let source = try ScoreLoader.load(url, beatsPerBar: 4)
                        if item.meterDetected != true, let m = source.detectedBeatsPerBar { metre = m }
                        if shift == 0 && zoom == 1 { loaded = source } else {
                            try source.musicXML(beatsPerBar: metre, title: item.title).write(to: converted)
                            loaded = try ScoreLoader.load(converted, beatsPerBar: metre, transpose: shift, zoom: zoom)
                        }
                    } else {
                        loaded = try ScoreLoader.load(url, beatsPerBar: 4, transpose: shift, zoom: zoom, sheetTitle: item.sheetTitle)
                    }
                    var timeline = loaded.timeline(beatsPerBar: metre)
                    if track == nil, item.ignoreTempoMarks != true { timeline = timeline.warped() }   // the score's tempo changes
                    let bar = timeline.measures.count > 1 ? timeline.measures[1].duration : timeline.measures.first?.duration ?? 4
                    return (loaded.pages, timeline, -Double(item.leadIn ?? 0) * bar)
                }.value
                let drawings = AnnotationStore()
                drawings.load(from: drawingsURL)
                let options = VideoOptions(
                    title: item.title, dark: look.dark, notes: look.notes, bar: look.bar, line: look.line,
                    tint: look.tint, ink: look.ink, paper: look.paper, stage: look.stage,
                    tempo: item.tempo, track: track, trackOffset: item.offset, trackSemitones: item.trackSemitones,
                    instrument: instrument, staffInstruments: staffVoices, soundingShift: key.offset, volume: 0.8, drawings: drawings.drawings)
                await MainActor.run { stage = String(localized: "Making the video…") }
                let out = try await Task.detached(priority: .userInitiated) {
                    try await VideoExport.export(pages: pages, timeline: timeline, start: start, options: options) { p in Task { @MainActor in progress = p } }
                }.value
                await MainActor.run { withAnimation { result = out } }
            } catch is CancellationError {
            } catch {
                await MainActor.run { failure = error.localizedDescription }
            }
        }
    }
}
