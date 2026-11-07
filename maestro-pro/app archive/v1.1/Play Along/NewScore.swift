import SwiftUI

extension Library {
    enum Staves: String, CaseIterable, Identifiable {
        case treble = "Treble", bass = "Bass", piano = "Piano (two staves)"
        var id: String { rawValue }
    }

    /// An empty score: every bar resting, ready to be written in the score editor.
    @discardableResult
    func createBlank(title: String, beats: Int, beatType: Int, fifths: Int, bars: Int, staves: Staves, tempo: Double) throws -> ScoreItem {
        Analytics.track("blank_score_created")
        var score = ParsedScore()
        score.title = title
        score.tempo = tempo
        score.staffCount = staves == .piano ? 2 : 1
        if staves == .piano { score.braces = [0..<2] }
        let length = beats * ticksPerQuarter * 4 / beatType
        for i in 0..<max(1, bars) {
            var m = PMeasure()
            m.start = i * length; m.length = length
            if i == 0 {
                m.key = fifths; m.time = (beats, beatType)
                m.clefs[0] = staves == .bass ? Clef(sign: "F", line: 4) : Clef()
                if staves == .piano { m.clefs[1] = Clef(sign: "F", line: 4) }
            }
            for s in 0..<score.staffCount {
                var rest = PNote()
                rest.staff = s; rest.tick = 0; rest.duration = length; rest.type = "whole"; rest.measureRest = true
                m.notes.append(rest)
            }
            m.finalBar = i == max(1, bars) - 1
            score.measures.append(m)
        }
        var item = ScoreItem(title: title.isEmpty ? "Untitled" : title, file: "score.musicxml")
        item.tempo = tempo
        item.created = true
        let fm = FileManager.default
        try fm.createDirectory(at: folder(item), withIntermediateDirectories: true)
        try MusicXML.write(score).write(to: scoreURL(item))
        save(item)
        return item
    }
}

/// The questions that set up a blank score: name, metre, key, staves, length and tempo.
struct NewScoreSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let created: (ScoreItem) -> Void

    @State private var title = ""
    @State private var beats = 4.0
    @State private var beatType = 4
    @State private var fifths = 0
    @State private var staves = Library.Staves.treble
    @State private var bars = 16.0
    @State private var tempo = 100.0
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Untitled", text: $title)
                }
                Section {
                    NumberStepper(title: "Beats in each bar", value: $beats, range: 1...16)
                    Picker("Beat is a", selection: $beatType) {
                        Text("Minim").tag(2); Text("Crotchet").tag(4); Text("Quaver").tag(8)
                    }
                } header: { Text("Time Signature") } footer: { Text("\(Int(beats))/\(beatType). Every bar will last exactly this long.") }
                Section("Music") {
                    Picker("Key", selection: $fifths) {
                        ForEach(-7...7, id: \.self) { Text(ParsedScore.keyName($0, minor: false)).tag($0) }
                    }
                    Picker("Staves", selection: $staves) {
                        ForEach(Library.Staves.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    NumberStepper(title: "Bars", value: $bars, range: 1...200)
                    NumberStepper(title: "Tempo", value: $tempo, range: 20...300, unit: "BPM")
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .navigationTitle("New Blank Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        do {
                            let item = try library.createBlank(title: title.trimmingCharacters(in: .whitespaces), beats: Int(beats), beatType: beatType, fifths: fifths, bars: Int(bars), staves: staves, tempo: tempo)
                            dismiss()
                            created(item)
                        } catch { failure = error.localizedDescription }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }
}
