import SwiftUI

/// Every kind of file the app opens or makes.
struct FormatsView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Format: Identifiable {
        let name: String, ext: String, note: String
        var id: String { name + ext }
    }

    private static let sections: [(title: String, footer: String, formats: [Format])] = [
        (String(localized: "Sheet music"), String(localized: "Import with Import Score, by dragging a file onto the window, or from the share sheet of another app."), [
            Format(name: "PDF", ext: ".pdf", note: String(localized: "Printed or scanned music. The notes are read from the page so it can be followed and played.")),
            Format(name: "MusicXML", ext: ".musicxml  .xml", note: String(localized: "Exact timing; can be edited, transposed, played and exported.")),
            Format(name: String(localized: "Compressed MusicXML"), ext: ".mxl", note: String(localized: "The zipped form most notation apps save.")),
            Format(name: String(localized: "Maestro Pro score"), ext: ".maestropro", note: String(localized: "A score with its backing track, from another Maestro Pro user.")),
        ]),
        (String(localized: "Lyrics and karaoke"), String(localized: "Lyrics can go with a score or stand alone; a karaoke file plays as its own item."), [
            Format(name: String(localized: "Timed lyrics"), ext: ".lrc", note: String(localized: "Lines (and words) with times.")),
            Format(name: String(localized: "Plain lyrics"), ext: ".txt", note: String(localized: "Words only; spread across the recording.")),
            Format(name: String(localized: "Karaoke MIDI"), ext: ".kar  .mid  .midi", note: String(localized: "Words and music in one file. A plain MIDI file counts when it carries words.")),
            Format(name: "CD+Graphics", ext: ".cdg", note: String(localized: "The picture track of a karaoke disc, shown as it was made.")),
        ]),
        (String(localized: "Backing tracks"), String(localized: "Any audio the device can play can be added to a score or to lyrics."), [
            Format(name: "Audio", ext: ".mp3  .m4a  .aac  .wav  .aiff  .caf  .flac", note: String(localized: "Plays in time with the score; can be pitch-shifted and have its volume, tempo and pitch edited.")),
        ]),
        (String(localized: "Whole folders"), String(localized: "Import Folder reads every supported file in a folder, pairing scores with a recording and lyrics of the same name."), [
            Format(name: "Folder", ext: "", note: String(localized: "Link one in Settings to keep it in step with the library.")),
        ]),
        (String(localized: "Recognised, not readable"), String(localized: "These are named so you get a clear explanation instead of a failure."), [
            Format(name: "Band-in-a-Box", ext: ".sgu  .sg0  .mgu  .mg0  .sgc  .sgd  .sgb  .sge", note: String(localized: "A closed format. In Band-in-a-Box, save as MusicXML for the notation and as audio for the backing, then import those.")),
        ]),
        (String(localized: "What the app makes"), String(localized: "From the Share menu of a score in the library."), [
            Format(name: "MusicXML", ext: ".musicxml", note: String(localized: "Opens in MuseScore, Finale, Sibelius, Dorico and most other notation apps.")),
            Format(name: "PDF", ext: ".pdf", note: String(localized: "The typeset page, or the original for a PDF score.")),
            Format(name: "Print", ext: "", note: String(localized: "Through the system print dialog.")),
            Format(name: "Video", ext: ".mp4", note: String(localized: "The music following along, with the sound.")),
            Format(name: String(localized: "Maestro Pro score"), ext: ".maestropro", note: String(localized: "The score and its backing track, to share with another player.")),
        ]),
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(Self.sections, id: \.title) { section in
                    Section {
                        ForEach(section.formats) { f in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(f.name).font(.headline)
                                    Spacer()
                                    if !f.ext.isEmpty { Text(f.ext).font(.system(.footnote, design: .monospaced)).foregroundStyle(.secondary) }
                                }
                                Text(f.note).font(.callout).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                            .accessibilityElement(children: .combine)
                        }
                    } header: { Text(section.title) } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.footer)
                            if section.title == "Lyrics and karaoke" {
                                Text("Looking for lyrics? Lyricsify has timed .lrc files for many songs. Maestro Pro is not affiliated with Lyricsify and does not supply or endorse its content.")
                                Link("Visit lyricsify.com", destination: URL(string: "https://www.lyricsify.com")!)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Supported Files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
