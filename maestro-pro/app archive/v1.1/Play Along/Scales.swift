import SwiftUI

extension Library {
    /// The score for a scale, made the first time it's asked for and kept (hidden from the main list).
    func scale(_ kind: ScaleKind, in key: ScaleKey) throws -> ScoreItem {
        Analytics.track("scale_made", ["kind": kind.name])
        let score = ScaleBuilder.score(kind, in: key)
        if let existing = items.first(where: { $0.generated == true && $0.title == score.title }) { return existing }
        var item = ScoreItem(title: score.title, file: "score.musicxml")
        item.generated = true
        item.tempo = 96
        try FileManager.default.createDirectory(at: folder(item), withIntermediateDirectories: true)
        try MusicXML.write(score).write(to: scoreURL(item))
        save(item)
        return item
    }
}

/// Every key for each kind of scale, arpeggio, pentatonic and blues scale.
struct ScaleBrowser: View {
    let open: (ScoreItem) -> Void
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage("scaleKind") private var kindName = "Major Scale"
    @State private var failure: String?

    private var kind: ScaleKind { ScaleKind.all.first { $0.name == kindName } ?? ScaleKind.all[0] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(ScaleKind.Group.allCases, id: \.self) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LocalizedStringKey(group.rawValue)).font(.headline).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(ScaleKind.all.filter { $0.group == group }) { k in
                                        Button(k.name) { withAnimation(.smooth) { kindName = k.name } }
                                            .buttonStyle(.bordered)
                                            .tint(k == kind ? Theme.accent : .gray)
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Text(LocalizedStringKey(kind.name)).font(.title3.bold())
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                        ForEach(kind.minorKey ? ScaleKey.minor : ScaleKey.major) { key in
                            Button {
                                do { open(try library.scale(kind, in: key)); dismiss() } catch { failure = error.localizedDescription }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(key.name).font(.title2.bold())
                                    Text(key.signature).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 64)
                            }
                            .buttonStyle(.bordered)
                            .tint(.primary)
                        }
                    }
                    if let failure { Text(failure).foregroundStyle(.red) }
                }
                .padding(20)
            }
            .navigationTitle("Scales & Arpeggios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 420, minHeight: 560)
    }
}
