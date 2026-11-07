import SwiftUI

// MARK: - Choosing them

struct ShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Library.self) private var library
    @AppStorage(Shortcuts.key) private var blob = ""
    @State private var capturing: ShortcutAction?
    @State private var message: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(["Playback", "View", "Tools"], id: \.self) { group in
                    Section(group) {
                        ForEach(ShortcutAction.allCases.filter { $0.group == group }) { a in row(a) }
                    }
                }
                Section {
                    if let message { Label(message, systemImage: "info.circle").font(.callout) }
                    Button("Reset All to Defaults", role: .destructive) { blob = ""; message = nil }.disabled(blob.isEmpty)
                } footer: {
                    Text("Choose a shortcut, then press the keys you want. Delete takes the shortcut away and Escape cancels. A shortcut that is already in use moves to the action you choose it for. Shortcuts show in the Mac menu bar, and on an iPad by holding the Command key.")
                }
            }
            .background {   // catches the keys while a shortcut is being chosen
                Color.clear.focusable().focused($focused).onKeyPress(phases: .down) { press in capture(press) }
            }
            .navigationTitle("Keyboard Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onChange(of: capturing) { _, c in library.typing = c != nil; focused = c != nil }
        .onDisappear { library.typing = false }
    }

    private func row(_ a: ShortcutAction) -> some View {
        let chord = Shortcuts.chord(a, blob), custom = chord != a.defaultChord
        return HStack {
            Text(a.title)
            Spacer()
            Button { message = nil; capturing = capturing == a ? nil : a } label: {
                Text(capturing == a ? String(localized: "Press keys…") : chord.label)
                    .font(.system(.callout, design: .monospaced, weight: .semibold))
                    .frame(minWidth: 84)
                    .foregroundStyle(capturing == a ? Color.white : chord.isNone ? Color.secondary : Theme.accent)
            }
            .buttonStyle(.bordered)
            .tint(capturing == a ? Theme.accent : nil)
            Button { blob = Shortcuts.reset(a, in: blob) } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.borderless).disabled(!custom).accessibilityLabel("Reset \(a.title)")
        }
        .accessibilityElement(children: .combine)
    }

    private func capture(_ press: KeyPress) -> KeyPress.Result {
        guard let a = capturing else { return .ignored }
        if press.key == .escape { capturing = nil; return .handled }
        if press.key == .delete, press.modifiers.isEmpty {
            blob = Shortcuts.assign(.none, to: a, in: blob).blob
            capturing = nil
            return .handled
        }
        let name = KeyChord.special.first { $0.value == press.key }?.key
        let char = press.key.character
        guard name != nil || (!char.isWhitespace && !char.isNewline && char.unicodeScalars.allSatisfy { $0.value > 31 }) else { return .handled }
        var c = KeyChord(key: name ?? String(char).lowercased(), command: press.modifiers.contains(.command), option: press.modifiers.contains(.option),
                         shift: press.modifiers.contains(.shift), control: press.modifiers.contains(.control))
        if name == nil, !c.command, !c.option, !c.control, c.shift { c.shift = true }   // a shifted letter is kept as Shift + letter
        let result = Shortcuts.assign(c, to: a, in: blob)
        blob = result.blob
        message = result.displaced.map { "\(c.label) now belongs to \(a.title). \($0) has no shortcut." }
        capturing = nil
        return .handled
    }
}
