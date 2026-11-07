import SwiftUI

/// Choose bars from another score in the library to put into the one being edited: the way to build a medley.
struct InsertBarsSheet: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    let current: ScoreItem
    let insert: (BarClip, Bool) -> Void

    @State private var picked: ScoreItem?
    @State private var source: ParsedScore?
    @State private var from = 1.0
    @State private var to = 1.0
    @State private var matchKey = true
    @State private var failure: String?
    @State private var loading = false

    /// Scores with notes to take (not lyrics files or karaoke pictures).
    private var choices: [ScoreItem] { library.items.filter { !$0.isLyricsOnly && !$0.isCDG } }

    var body: some View {
        NavigationStack {
            List {
                Section("Take bars from") {
                    ForEach(choices) { item in
                        Button { pick(item) } label: {
                            HStack {
                                Text(item.title).foregroundStyle(.primary)
                                if item.id == current.id { Text("(this score)").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                if loading && picked?.id == item.id { ProgressView() }
                                else if picked?.id == item.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            }
                        }
                    }
                }
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
                if let source {
                    Section {
                        NumberStepper(title: "From Bar", value: $from, range: 1...Double(source.measures.count))
                        NumberStepper(title: "To Bar", value: $to, range: from...Double(source.measures.count))
                        Toggle("Match My Key", isOn: $matchKey)
                    } header: { Text("Bars") } footer: {
                        Text("\(Int(to - from) + 1) of the \(source.measures.count) bars of “\(picked?.title ?? "")” go in after the bar you have chosen, or at the end if none is chosen. They keep their own metre and tempo, and your music takes its own back after them.")
                    }
                }
            }
            .navigationTitle("Insert Bars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") {
                        if let source, let clip = ScoreEdit.clip(from: source, bars: (Int(from) - 1)...(Int(to) - 1), title: picked?.title ?? "") {
                            insert(clip, matchKey)
                            dismiss()
                        }
                    }
                    .disabled(source == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func pick(_ item: ScoreItem) {
        picked = item; source = nil; failure = nil; loading = true
        let url = item.isPDF ? library.convertedURL(item) : library.scoreURL(item)
        Task {
            do {
                guard FileManager.default.fileExists(atPath: url.path) else { throw ScoreError.unsupported(String(localized: "Open this PDF once first, so the app can read its notes, then come back.")) }
                let parsed = try await Task.detached { try MusicXML.parse(MusicXML.data(from: url)) }.value
                guard picked?.id == item.id else { return }
                source = parsed; from = 1; to = Double(parsed.measures.count)
            } catch { failure = error.localizedDescription }
            loading = false
        }
    }
}
