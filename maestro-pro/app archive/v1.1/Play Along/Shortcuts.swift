import SwiftUI

// Keyboard shortcuts for the Mac (and an iPad with a keyboard): every one can be changed in Settings.

/// A key with its modifiers. The key is a name for the special keys ("space", "left", "pageDown"…) or the character itself.
struct KeyChord: Codable, Equatable, Hashable {
    var key: String
    var command = false, option = false, shift = false, control = false

    static let special: [String: KeyEquivalent] = [
        "space": .space, "return": .return, "left": .leftArrow, "right": .rightArrow, "up": .upArrow, "down": .downArrow,
        "pageUp": .pageUp, "pageDown": .pageDown, "home": .home, "end": .end, "tab": .tab, "escape": .escape, "delete": .delete,
    ]
    static let names: [String: String] = [
        "space": "Space", "return": "↩", "left": "←", "right": "→", "up": "↑", "down": "↓", "pageUp": "Page Up", "pageDown": "Page Down",
        "home": "Home", "end": "End", "tab": "⇥", "escape": "⎋", "delete": "⌫",
    ]

    var keyEquivalent: KeyEquivalent { Self.special[key] ?? KeyEquivalent(key.first ?? " ") }
    var modifiers: EventModifiers {
        var m: EventModifiers = []
        if command { m.insert(.command) }
        if option { m.insert(.option) }
        if shift { m.insert(.shift) }
        if control { m.insert(.control) }
        return m
    }
    var isNone: Bool { key.isEmpty }
    /// As on a Mac menu: ⌃⌥⇧⌘ then the key.
    var label: String {
        guard !isNone else { return "None" }
        return (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + (Self.names[key] ?? key.uppercased())
    }
    static let none = KeyChord(key: "")
    static func plain(_ k: String) -> KeyChord { KeyChord(key: k) }
    static func cmd(_ k: String, option: Bool = false, shift: Bool = false) -> KeyChord { KeyChord(key: k, command: true, option: option, shift: shift) }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case playPause, toStart, previousBar, nextBar, previousPage, nextPage, slower, faster, metronome, countIn
    case zoomIn, zoomOut, fitWidth, follow, darkSheet, pageTurn, highlightNotes, highlightBar, movingLine, inspector, chordView, lyricsView
    case editScore, annotate, waitForMe, record, tuner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playPause: "Play or Pause"
        case .toStart: "Go to Beginning"
        case .previousBar: "Previous Bar"
        case .nextBar: "Next Bar"
        case .previousPage: "Previous Page"
        case .nextPage: "Next Page"
        case .slower: "Slower"
        case .faster: "Faster"
        case .metronome: "Metronome"
        case .countIn: "Count In"
        case .zoomIn: "Zoom In"
        case .zoomOut: "Zoom Out"
        case .fitWidth: "Fit to Width"
        case .follow: "Follow Playback"
        case .darkSheet: "Dark Sheet Music"
        case .pageTurn: "Turn Pages Like a Book"
        case .highlightNotes: "Highlight Notes"
        case .highlightBar: "Highlight Bar"
        case .movingLine: "Moving Line"
        case .inspector: "Inspector"
        case .chordView: "Chord View"
        case .lyricsView: "Lyrics Instead of Music"
        case .editScore: "Edit Score"
        case .annotate: "Annotate"
        case .waitForMe: "Wait for Me"
        case .record: "Record Myself"
        case .tuner: "Tuner"
        }
    }

    var group: String {
        switch self {
        case .playPause, .toStart, .previousBar, .nextBar, .previousPage, .nextPage, .slower, .faster, .metronome, .countIn: "Playback"
        case .zoomIn, .zoomOut, .fitWidth, .follow, .darkSheet, .pageTurn, .highlightNotes, .highlightBar, .movingLine, .inspector, .chordView, .lyricsView: "View"
        default: "Tools"
        }
    }

    var defaultChord: KeyChord {
        switch self {
        case .playPause: .plain("space")
        case .toStart: .plain("return")
        case .previousBar: .plain("left")
        case .nextBar: .plain("right")
        case .previousPage: .plain("pageUp")
        case .nextPage: .plain("pageDown")
        case .slower: .plain("[")
        case .faster: .plain("]")
        case .metronome: .plain("k")
        case .countIn: KeyChord(key: "k", shift: true)
        case .zoomIn: .cmd("=")
        case .zoomOut: .cmd("-")
        case .fitWidth: .cmd("0")
        case .follow: .cmd("f", option: true)
        case .darkSheet: .cmd("d", option: true)
        case .pageTurn: .cmd("p", option: true)
        case .highlightNotes: .cmd("1", option: true)
        case .highlightBar: .cmd("2", option: true)
        case .movingLine: .cmd("3", option: true)
        case .inspector: .cmd("i", option: true)
        case .chordView: .cmd("c", shift: true)
        case .lyricsView: .cmd("l", shift: true)
        case .editScore: .cmd("e")
        case .annotate: .cmd("a", shift: true)
        case .waitForMe: .cmd("w", option: true)
        case .record: .cmd("r")
        case .tuner: .cmd("t")
        }
    }
}

/// The shortcuts as chosen: only the differences from the defaults are stored (an empty key means "none").
enum Shortcuts {
    static let key = "shortcuts"

    static func overrides(_ blob: String) -> [String: KeyChord] {
        (try? JSONDecoder().decode([String: KeyChord].self, from: Data(blob.utf8))) ?? [:]
    }

    static func chord(_ a: ShortcutAction, _ blob: String) -> KeyChord {
        overrides(blob)[a.rawValue] ?? a.defaultChord
    }

    static func encode(_ o: [String: KeyChord]) -> String {
        guard !o.isEmpty, let d = try? JSONEncoder().encode(o) else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    /// Gives `chord` to `action`; whichever action had it loses it. Returns the title of that action, if any.
    static func assign(_ chord: KeyChord, to action: ShortcutAction, in blob: String) -> (blob: String, displaced: String?) {
        var o = overrides(blob)
        var displaced: String?
        if !chord.isNone {
            for other in ShortcutAction.allCases where other != action && self.chord(other, blob) == chord {
                o[other.rawValue] = KeyChord.none
                displaced = other.title
            }
        }
        o[action.rawValue] = chord == action.defaultChord ? nil : chord
        return (encode(o), displaced)
    }

    static func reset(_ action: ShortcutAction, in blob: String) -> String {
        var o = overrides(blob)
        o[action.rawValue] = nil
        // The default may be taken by another action's own choice: then it stays without.
        let c = action.defaultChord
        if ShortcutAction.allCases.contains(where: { $0 != action && chord($0, encode(o)) == c }) { o[action.rawValue] = KeyChord.none }
        return encode(o)
    }
}

extension View {
    /// Gives a menu item the chosen shortcut (or none).
    func shortcut(_ action: ShortcutAction, _ blob: String) -> some View {
        modifier(ShortcutModifier(chord: Shortcuts.chord(action, blob)))
    }
}

private struct ShortcutModifier: ViewModifier {
    let chord: KeyChord
    func body(content: Content) -> some View {
        if chord.isNone { content } else { content.keyboardShortcut(chord.keyEquivalent, modifiers: chord.modifiers) }
    }
}

/// What the score on screen can do from the menu bar.
struct ScoreActions {
    var nextPage: () -> Void = {}
    var previousPage: () -> Void = {}
    var editScore: () -> Void = {}
    var annotate: () -> Void = {}
    var waitForMe: () -> Void = {}
    var record: () -> Void = {}
    var chordView: () -> Void = {}
    var lyricsView: () -> Void = {}
}
