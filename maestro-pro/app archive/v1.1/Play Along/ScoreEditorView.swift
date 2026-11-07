import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Edit a score's notes on the page. Select a note and drag it up or down to change its pitch; Draw puts a note on a
/// rest; Erase turns notes into rests. With Apple Pencil, double-tap the pencil to switch to the eraser and back.
struct ScoreEditorView: View {
    let item: ScoreItem
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    #if targetEnvironment(macCatalyst)
    @AppStorage("pencilOnlyEditing") private var pencilOnly = false   // a Mac has no Apple Pencil; the mouse edits by default
    #else
    @AppStorage("pencilOnlyEditing") private var pencilOnly = true
    #endif

    enum Tool: String, CaseIterable, Identifiable {
        case pencil = "Notes", rest = "Rests", marks = "Marks", dynamics = "Dynamics", bar = "Bars", form = "Form", medley = "Medley", erase = "Erase", draw = "Draw"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .pencil: "pencil.tip"; case .rest: "pause"; case .marks: "textformat.abc"; case .dynamics: "speaker.wave.2"
            case .bar: "repeat"; case .form: "arrow.uturn.right"; case .medley: "doc.on.doc"; case .erase: "eraser"; case .draw: "scribble.variable"
            }
        }
        /// What the mode is for, in a few words.
        var purpose: String {
            switch self {
            case .pencil: String(localized: "Put in and move notes, and set how long they last")
            case .rest: String(localized: "Add, change and remove rests")
            case .marks: String(localized: "Accidentals, ties and articulations")
            case .dynamics: String(localized: "Loud and soft, crescendo and diminuendo")
            case .bar: String(localized: "Repeat signs and adding or removing bars")
            case .form: String(localized: "First and second time bars, jumps and tempo")
            case .medley: String(localized: "Copy, cut, paste and insert bars, even from other scores")
            case .erase: String(localized: "Rub out notes and rests")
            case .draw: String(localized: "Draw on the page in any colour")
            }
        }
        /// Modes that choose a whole bar.
        var choosesBar: Bool { self == .bar || self == .form }
    }

    private struct Moving {
        var event: NoteEvent
        var startY: CGFloat
        var diatonic: Int          // where it is now (a note's own pitch, or the pitch under the pencil for a rest)
        var original: Int
        var place: Bool            // a rest being turned into a note
        var restTool = false       // the Rests tool: touching it selects a rest, or turns a note into one
        var append = false         // free editing: a note added after the bar's last one, where no rest is
    }

    @State private var score: ParsedScore?
    @State private var document: CGPDFDocument?
    @State private var pages: [CGPDFPage] = []
    @State private var timeline = Timeline()
    @State private var tool = Tool.pencil
    @State private var previous = Tool.pencil
    @State private var selectedBar: Int?
    @State private var stroke: [CGPoint] = []
    @State private var strokePage = 0
    @State private var scribbling = false
    @State private var selected: EditInfo?
    @State private var base = 480
    @State private var dotted = false
    @State private var triplet = false
    @AppStorage("editFree") private var free = false
    @State private var undo: [ParsedScore] = []
    @State private var redo: [ParsedScore] = []
    @State private var moving: Moving?
    @State private var movingPage = 0
    @State private var failure: String?
    @State private var dirty = false
    @State private var confirmDiscard = false
    @State private var engraving: Task<Void, Never>?
    @State private var erasing = false
    @State private var saved: String?
    @State private var stale = false     // an edit is being re-engraved: the page on screen is a moment behind the score
    @State private var showHelp = false
    @State private var showHistory = false
    @State private var ink = AnnotationStore()
    @State private var showTempo = false
    @Environment(\.undoManager) private var undoManager
    @State private var bridge = UndoBridge()
    @State private var tempoDraft = 100.0
    @State private var tieMessage: String?
    @State private var medleyAnchor: Int?
    @State private var medleyRange: ClosedRange<Int>?
    @State private var showInsert = false
    /// Plays the notes as they are written, on the instrument chosen in Settings (the piano if none is).
    @State private var player = Transport()
    @AppStorage("editorHear") private var hear = true
    @AppStorage("medleyMatchKey") private var matchKey = true

    private var ticks: Int { triplet ? base * 2 / 3 : dotted ? base * 3 / 2 : base }
    private var tuplet: Int { triplet ? 3 : 0 }
    private let width: CGFloat = 612

    var body: some View {
        NavigationStack {
            ZStack {
                StageBackground()
                if let failure {
                    ContentUnavailableView("Can’t Edit This Score", systemImage: "exclamationmark.triangle", description: Text(failure))
                } else if pages.isEmpty {
                    ProgressView("Preparing the score…")
                } else {
                    GeometryReader { geo in
                        let w = max(300, min(geo.size.width - 40, 900)), scale = w / width
                        ScrollView {
                            VStack(spacing: 18) {
                                ForEach(pages.indices, id: \.self) { i in page(i, w: w, scale: scale) }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 16)
                            .padding(.bottom, 190)
                        }
                        .scrollDisabled(!pencilOnly)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { if score != nil, failure == nil { palette } }
            .navigationTitle(item.isPDF ? String(localized: "Edit a Copy of \(item.title)") : String(localized: "Edit \(item.title)"))
            .navigationBarTitleDisplayMode(.inline)
            .titleHidden()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dirty ? (confirmDiscard = true) : dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { listen() } label: { Label(player.isPlaying ? "Stop" : "Listen", systemImage: player.isPlaying ? "stop.fill" : "play.fill") }
                        .help("Hear the music from the chosen note or bar")
                    Menu {
                        Picker("Instrument", selection: $player.instrument) {
                            ForEach(Instrument.allCases) { Text($0 == .off ? String(localized: "Piano (default)") : $0.rawValue).tag($0) }
                        }
                        Toggle("Hear Notes as I Edit", systemImage: "speaker.wave.2", isOn: $hear)
                        Divider()
                        Toggle("Edit with Apple Pencil Only", systemImage: "applepencil", isOn: $pencilOnly)
                        Toggle("Free Editing (No Auto-Corrections)", systemImage: "hand.raised", isOn: $free)
                        if !item.isPDF, library.hasOriginal(item) {
                            Button("Restore the Original Score", systemImage: "arrow.uturn.backward.circle", role: .destructive) {
                                library.restoreOriginal(item)
                                Task { await load() }
                                dirty = false
                            }
                        }
                    } label: { Label("Options", systemImage: "ellipsis.circle") }
                    if !item.isPDF, let score {
                        Button { showHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }
                            .help("Saved versions, branches and merges")
                            .sheet(isPresented: $showHistory) { HistorySheet(item: item, score: score, apply: applyVersion, persist: persistVersion).environment(library) }
                    }
                    Button("Save") { save() }.fontWeight(.semibold).disabled(!dirty)
                }
            }
            .alert("Can’t Tie", isPresented: Binding { tieMessage != nil } set: { if !$0 { tieMessage = nil } }) { Button("OK") {} } message: { Text(tieMessage ?? "") }
            .sheet(isPresented: $showInsert) { InsertBarsSheet(current: item) { clip, match in tool = .medley; pasteBars(clip, matchKey: match) } }
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { dismiss() }
            }
        }
        .task { await load() }
        .onChange(of: tool) { _, t in Analytics.track("editor_tool", ["tool": t.rawValue]) }
        .onChange(of: selected) { _, s in
            // A note chosen or just written sounds, so a wrong note is heard at once.
            guard hear, let s, let n = score?.measures[s.measure].notes[s.index], let d = n.diatonic else { return }
            player.preview(ParsedScore.midi(diatonic: d, alter: n.alter), seconds: 0.6)
        }
        .onDisappear { player.pause() }
    }

    /// Plays from the chosen note or bar (or the start), with the notes lit as they sound.
    private func listen() {
        if player.isPlaying { player.pause(); return }
        player.countInEnabled = false
        player.metronome = false
        let from = selected.flatMap { s in timeline.notes.first { $0.edit?.measure == s.measure && $0.edit?.index == s.index }?.start }
            ?? selectedBar.flatMap { b in timeline.measures.first { $0.bar == b }?.start } ?? 0
        player.seek(to: from)
        player.play()
    }

    // MARK: Pages

    private func page(_ i: Int, w: CGFloat, scale: CGFloat) -> some View {
        let h = w * Engraver.pageSize.height / Engraver.pageSize.width
        return ZStack {
            PaperSheet(dark: false)
            PageCanvas(page: pages[i]).clipShape(RoundedRectangle(cornerRadius: PaperSheet.radius, style: .continuous))
            Canvas { ctx, _ in drawOverlay(&ctx, page: i, scale: scale) }
                .allowsHitTesting(false)
            AnnotationLayer(store: ink, page: i, scale: scale, active: tool == .draw)
            StylusSurface(allowFingers: !pencilOnly,
                          began: { began($0.applying(.init(scaleX: 1 / scale, y: 1 / scale)), page: i) },
                          moved: { moved($0.applying(.init(scaleX: 1 / scale, y: 1 / scale)), page: i) },
                          ended: { ended($0.applying(.init(scaleX: 1 / scale, y: 1 / scale)), page: i) },
                          pencilTap: { tool = tool == .erase ? previous : { previous = tool; return .erase }() })
                .allowsHitTesting(tool != .draw)
        }
        .overlay(alignment: .topLeading) { quickMenu(page: i, width: w, scale: scale) }
        .frame(width: w, height: h)
        .accessibilityElement()
        .accessibilityLabel("Page \(i + 1) of the score")
        .accessibilityHint("Edit the notes with Apple Pencil.")
    }

    // MARK: Quick menu

    private enum QuickKind { case note, rest, bar, range }

    /// Where the quick menu hangs: above the chosen note or rest, or the chosen bar.
    private func quickAnchor(page i: Int, scale: CGFloat) -> (point: CGPoint, kind: QuickKind)? {
        if let s = selected, let e = timeline.notes.first(where: { $0.page == i && $0.edit?.measure == s.measure && $0.edit?.index == s.index }) {
            return (CGPoint(x: e.rect.midX * scale, y: e.rect.minY * scale), e.isRest ? .rest : .note)
        }
        if tool == .medley, let r = medleyRange, let m = timeline.measures.first(where: { $0.bar == r.lowerBound && timeline.systems[$0.system].page == i }) {
            let last = timeline.measures.last(where: { $0.bar == r.upperBound && timeline.systems[$0.system].page == i && $0.system == m.system })
            return (CGPoint(x: ((m.x0 + (last?.x1 ?? m.x1)) / 2) * scale, y: timeline.systems[m.system].rect.minY * scale), .range)
        }
        if selected == nil, let b = selectedBar, let m = timeline.measures.first(where: { $0.bar == b && timeline.systems[$0.system].page == i }) {
            return (CGPoint(x: (m.x0 + m.x1) / 2 * scale, y: timeline.systems[m.system].rect.minY * scale), .bar)
        }
        return nil
    }

    /// A small bar of the things most wanted for what was just tapped, hanging over it like the system edit menu.
    @ViewBuilder private func quickMenu(page i: Int, width w: CGFloat, scale: CGFloat) -> some View {
        if tool != .draw, tool != .erase, !stale, moving == nil, let anchor = quickAnchor(page: i, scale: scale) {
            let count: CGFloat = anchor.kind == .note ? 7 : anchor.kind == .rest ? 3 : 4
            let width = count * 40 + 16
            quickContent(anchor.kind)
                .padding(4)
                .metalPlate(radius: 10)
                .environment(\.colorScheme, .dark)
                .fixedSize()
                .offset(x: max(6, min(w - width - 6, anchor.point.x - width / 2)), y: max(4, anchor.point.y - 52))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    private func quickButton(_ label: String, glyph: Bool = false, active: Bool = false, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if label.hasPrefix("sf:") { Image(systemName: String(label.dropFirst(3))) }
                else { Text(label).font(glyph ? .custom("Bravura", size: 24) : .system(size: 16, weight: .semibold)) }
            }
            .frame(width: 38, height: 34)
            .foregroundStyle(active ? Theme.accent : Color.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(help)
    }

    @ViewBuilder private func quickContent(_ kind: QuickKind) -> some View {
        HStack(spacing: 2) {
            switch kind {
            case .note:
                quickButton("\u{E262}", glyph: true, help: "Sharp") { accidental(.sharp) }
                quickButton("\u{E260}", glyph: true, help: "Flat") { accidental(.flat) }
                quickButton("\u{E261}", glyph: true, help: "Natural") { accidental(.natural) }
                quickButton("Tie", active: selectedTied, help: String(localized: "Tie to the next note")) { tieSelected() }
                quickButton("•", active: selectedDotted, help: "Dotted") { toggleDot() }
                Menu {
                    ForEach(ScoreEdit.dynamicNames, id: \.self) { d in Button(d) { setDynamic(d) } }
                    Divider()
                    Button("No Dynamic") { setDynamic(nil) }
                } label: {
                    Text("mf").font(.custom("Baskerville-BoldItalic", size: 18)).frame(width: 38, height: 34).foregroundStyle(.white)
                }
                .accessibilityLabel("Dynamic")
                quickButton("sf:trash", help: String(localized: "Turn into a rest")) { deleteSelected() }
            case .rest:
                quickButton("½", help: "Shorter") { changeLength(by: 0.5) }
                quickButton("×2", help: "Longer") { changeLength(by: 2) }
                quickButton("sf:trash", help: String(localized: "Remove the rest")) { deleteSelected() }
            case .range:
                quickButton("sf:doc.on.doc", help: String(localized: "Copy the bars")) { copyBars() }
                quickButton("sf:scissors", help: String(localized: "Cut the bars")) { cutBars() }
                quickButton("sf:doc.on.clipboard", help: String(localized: "Paste after these bars")) { pasteBars() }
                quickButton("sf:trash", help: String(localized: "Delete the bars")) { deleteRange() }
            case .bar:
                quickButton("‖:", help: String(localized: "Repeat start")) { barEdit { ScoreEdit.toggleRepeatStart(&$0, measure: $1) } }
                quickButton(":‖", help: String(localized: "Repeat end")) { barEdit { ScoreEdit.cycleRepeatEnd(&$0, measure: $1) } }
                quickButton("+", help: String(localized: "Add a bar after")) { barEdit { ScoreEdit.insertBar(&$0, after: $1) } }
                quickButton("sf:trash", help: barsChosen > 1 ? String(localized: "Delete the bars") : String(localized: "Delete the bar")) { deleteBar() }
            }
        }
    }

    private var selectedDotted: Bool {
        guard let s = selected, let n = score?.measures[s.measure].notes[s.index] else { return false }
        return n.dots > 0
    }

    /// A dot on or off the selected note.
    private func toggleDot() {
        guard let s = selected, let n = score?.measures[s.measure].notes[s.index], n.tuplet == 0 else { return }
        resizeSelected(n.dots > 0 ? n.duration * 2 / 3 : n.duration * 3 / 2, tuplet: 0)
    }

    /// The selected note or rest twice as long, or half as long.
    private func changeLength(by factor: Double) {
        guard let s = selected, let n = score?.measures[s.measure].notes[s.index] else { return }
        resizeSelected(Int((Double(n.duration) * factor).rounded()), tuplet: n.tuplet)
    }

    private func drawOverlay(_ ctx: inout GraphicsContext, page i: Int, scale: CGFloat) {
        if player.isPlaying {   // the notes sounding now
            let beat = player.beat
            for n in timeline.notes where n.page == i && !n.isRest && beat >= n.start && beat < n.end {
                ctx.fill(Path(roundedRect: n.rect.insetBy(dx: -2, dy: -2).applying(.init(scaleX: scale, y: scale)), cornerRadius: 4), with: .color(Theme.accent.opacity(0.5)))
            }
        }
        if let s = selected, let e = timeline.notes.first(where: { $0.page == i && $0.edit?.measure == s.measure && $0.edit?.index == s.index }) {
            let r = e.rect.insetBy(dx: -3, dy: -3).applying(.init(scaleX: scale, y: scale))
            ctx.stroke(Path(roundedRect: r, cornerRadius: 4), with: .color(Theme.accent), lineWidth: 2)
            ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(Theme.accent.opacity(0.18)))
        }
        let highlighted: [Int] = tool == .medley || tool == .bar ? (medleyRange.map { Array($0) } ?? []) : (selectedBar.map { [$0] } ?? [])
        for b in highlighted {
            for mark in timeline.measures where mark.bar == b && timeline.systems[mark.system].page == i {
                let sys = timeline.systems[mark.system].rect
                let r = CGRect(x: mark.x0, y: sys.minY, width: mark.x1 - mark.x0, height: sys.height).applying(.init(scaleX: scale, y: scale))
                ctx.fill(Path(roundedRect: r, cornerRadius: 6), with: .color(Theme.accent.opacity(0.14)))
                ctx.stroke(Path(roundedRect: r, cornerRadius: 6), with: .color(Theme.accent), lineWidth: 2)
            }
        }
        if strokePage == i, stroke.count > 1 {
            var path = Path()
            path.addLines(stroke.map { CGPoint(x: $0.x * scale, y: $0.y * scale) })
            ctx.stroke(path, with: .color(scribbling ? .red.opacity(0.8) : Theme.accent.opacity(0.5)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        if let m = moving, movingPage == i, !m.restTool, let info = m.event.edit {
            let y = info.top + CGFloat(8 - (m.diatonic - info.clefBottom)) * info.space / 2
            let c = CGPoint(x: m.event.rect.midX * scale, y: y * scale)
            let rw = info.space * 1.3 * scale, rh = info.space * scale
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - rw / 2, y: c.y - rh / 2, width: rw, height: rh)), with: .color(Theme.accent.opacity(0.85)))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rw / 2, y: c.y - rh / 2, width: rw, height: rh)), with: .color(.white), lineWidth: 1.5)
            ctx.draw(Text(Self.name(m.diatonic)).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent), at: CGPoint(x: c.x + rw, y: c.y - rh))
        }
    }

    static func name(_ diatonic: Int) -> String { "\(Array("CDEFGAB")[diatonic.mod(7)])\(diatonic.floorDiv(7))" }

    // MARK: Touches (in page points)

    private func note(at q: CGPoint, page: Int) -> NoteEvent? {
        timeline.notes.filter { $0.page == page && !$0.isRest && $0.edit != nil && $0.rect.insetBy(dx: -5, dy: -5).contains(q) }
            .min { hypot($0.rect.midX - q.x, $0.rect.midY - q.y) < hypot($1.rect.midX - q.x, $1.rect.midY - q.y) }
    }

    private func rest(at q: CGPoint, page: Int) -> NoteEvent? {
        timeline.notes.filter { $0.page == page && $0.isRest && $0.edit != nil && $0.rect.insetBy(dx: -4, dy: -4).contains(q) }
            .min { hypot($0.rect.midX - q.x, $0.rect.midY - q.y) < hypot($1.rect.midX - q.x, $1.rect.midY - q.y) }
    }

    private func diatonic(under q: CGPoint, _ info: EditInfo) -> Int {
        let pos = 8 - Double((q.y - info.top) * 2 / info.space)
        return max(0, info.clefBottom + Int(pos.rounded()))
    }

    /// A rest the pencil is over, in its staff and bar, even if the touch is some way from the glyph.
    private func restSlot(at q: CGPoint, page: Int) -> NoteEvent? {
        timeline.notes.filter { e in
            guard e.page == page, e.isRest, let info = e.edit else { return false }
            return q.y >= info.top - 3 * info.space && q.y <= info.top + 7 * info.space && abs(e.rect.midX - q.x) < max(e.rect.width / 2 + 2 * info.space, 3 * info.space)
        }.min { abs($0.rect.midX - q.x) < abs($1.rect.midX - q.x) }
    }

    /// Any note or rest of the staff and bar under the touch, even where there is nothing to touch (free editing adds a note there).
    private func staffSlot(at q: CGPoint, page: Int) -> NoteEvent? {
        guard let b = bar(at: q, page: page) else { return nil }
        return timeline.notes.first { e in
            guard e.page == page, let info = e.edit, info.measure == b else { return false }
            return q.y >= info.top - 3 * info.space && q.y <= info.top + 7 * info.space
        }
    }

    private func bar(at q: CGPoint, page: Int) -> Int? {
        timeline.measures.first { m in
            let sys = timeline.systems[m.system]
            return sys.page == page && q.x >= m.x0 && q.x <= m.x1 && q.y >= sys.rect.minY && q.y <= sys.rect.maxY
        }?.bar
    }

    private var staffSpace: CGFloat { timeline.notes.first { $0.edit != nil }?.edit?.space ?? 7 }

    private func began(_ q: CGPoint, page: Int) {
        // Touches use positions from the page as drawn; until it catches up with the last edit they'd hit the wrong note.
        guard !stale else { moving = nil; stroke = []; return }
        movingPage = page
        stroke = [q]; strokePage = page; scribbling = false
        switch tool {
        case .draw:
            break
        case .erase:
            eraseHit(q, page: page)
        case .bar, .form:
            selectedBar = bar(at: q, page: page)
            selected = nil
            if tool == .bar { medleyAnchor = selectedBar; medleyRange = selectedBar.map { $0...$0 } }   // drag on to choose several
        case .medley:
            moving = nil; selected = nil; selectedBar = nil
            if let b = bar(at: q, page: page) { medleyAnchor = b; medleyRange = b...b } else { medleyAnchor = nil; medleyRange = nil }
        case .marks, .dynamics:
            // Touching only chooses: a note to mark, or (on empty staff) the bar.
            moving = nil
            if let n = note(at: q, page: page), let info = n.edit { selected = info; selectedBar = info.measure }
            else if let r = rest(at: q, page: page), let info = r.edit, tool == .dynamics { selected = nil; selectedBar = info.measure }
            else { selected = nil; selectedBar = bar(at: q, page: page) }
        case .rest:
            if let n = note(at: q, page: page) ?? restSlot(at: q, page: page) {
                selectedBar = nil
                moving = Moving(event: n, startY: q.y, diatonic: 0, original: 0, place: false, restTool: true)
            } else { moving = nil; selected = nil; selectedBar = bar(at: q, page: page) }
        case .pencil:
            if let n = note(at: q, page: page), let info = n.edit, let d = score?.measures[info.measure].notes[info.index].diatonic {
                selected = info; selectedBar = nil
                moving = Moving(event: n, startY: q.y, diatonic: d, original: d, place: false)
            } else if let r = restSlot(at: q, page: page), let info = r.edit {
                moving = Moving(event: r, startY: q.y, diatonic: diatonic(under: q, info), original: -1, place: true)
            } else if free, let e = staffSlot(at: q, page: page), let info = e.edit {
                selected = nil
                moving = Moving(event: e, startY: q.y, diatonic: diatonic(under: q, info), original: -1, place: true, append: true)
            } else {
                selected = nil
                moving = nil
                selectedBar = bar(at: q, page: page)   // a bar with nothing to touch: its quick menu
            }
        }
    }

    private func moved(_ q: CGPoint, page: Int) {
        guard !stale else { return }
        stroke.append(q)
        if tool == .erase { eraseHit(q, page: page); return }
        if tool == .medley || tool == .bar {   // drag across bars to choose several
            if let a = medleyAnchor, let b = bar(at: q, page: page) { medleyRange = min(a, b)...max(a, b) }
            return
        }
        if tool == .pencil || tool == .rest {
            // A scribble cancels what the stroke was doing; it will erase when the pencil lifts.
            if !scribbling, ScoreEdit.isScribble(stroke, space: staffSpace) { scribbling = true; moving = nil }
            if scribbling { return }
        }
        guard tool == .pencil, var m = moving, let info = m.event.edit else { return }
        let before = m.diatonic
        m.diatonic = m.place ? diatonic(under: q, info) : max(0, m.original + Int(((m.startY - q.y) / (info.space / 2)).rounded()))
        moving = m
        if hear, m.diatonic != before, let s = score {   // each step of a drag is heard
            player.preview(ParsedScore.midi(diatonic: m.diatonic, alter: ParsedScore.keyAlter(ScoreEdit.key(at: info.measure, in: s), m.diatonic.mod(7))), seconds: 0.35)
        }
    }

    private func ended(_ q: CGPoint, page: Int) {
        defer { moving = nil; stroke = []; scribbling = false }
        guard !stale else { return }
        if tool == .pencil || tool == .rest, scribbling || ScoreEdit.isScribble(stroke, space: staffSpace) { scribbleErase(page: page); return }
        guard let m = moving, let info = m.event.edit else { return }
        if m.restTool {
            if m.event.isRest { selected = info }
            else {
                var newIndex: Int?
                let free = self.free
                commit { s in newIndex = free ? ScoreEdit.setRestFree(&s, measure: info.measure, index: info.index, ticks: ticks, tuplet: tuplet) : ScoreEdit.setRest(&s, measure: info.measure, index: info.index, ticks: ticks, tuplet: tuplet) }
                selected = newIndex.map { EditInfo(measure: info.measure, index: $0, staff: info.staff, top: info.top, space: info.space, clefBottom: info.clefBottom) }
            }
        } else if m.place {
            var newIndex: Int?
            let free = self.free
            if m.append { commit { s in newIndex = ScoreEdit.append(&s, measure: info.measure, staff: info.staff, diatonic: m.diatonic, ticks: ticks, tuplet: tuplet) } }
            else if free { commit { s in newIndex = ScoreEdit.placeFree(&s, measure: info.measure, rest: info.index, diatonic: m.diatonic, ticks: ticks, tuplet: tuplet) } }
            else { commit { s in newIndex = ScoreEdit.place(&s, measure: info.measure, rest: info.index, diatonic: m.diatonic, ticks: ticks, tuplet: tuplet) } }
            if let i = newIndex { selected = EditInfo(measure: info.measure, index: i, staff: info.staff, top: info.top, space: info.space, clefBottom: info.clefBottom) }
        } else if tool == .pencil, m.diatonic != m.original {
            commit { ScoreEdit.setPitch(&$0, measure: info.measure, index: info.index, diatonic: m.diatonic) }
        }
    }

    /// Everything the scribble crossed: notes go (to rests); if it only crossed rests, they are taken out.
    private func scribbleErase(page: Int) {
        guard stroke.count > 1 else { return }
        let pad = staffSpace * 0.3
        let hit = timeline.notes.filter { $0.page == page && $0.edit != nil && ScoreEdit.stroke(stroke, crosses: $0.rect.insetBy(dx: -pad, dy: -pad)) }
        let notes = hit.filter { !$0.isRest }.compactMap(\.edit), rests = hit.filter(\.isRest).compactMap(\.edit)
        guard !notes.isEmpty || !rests.isEmpty else { return }
        selected = nil
        // Highest index first, so removing a chord's note doesn't move the ones still to do.
        func order(_ infos: [EditInfo]) -> [(measure: Int, index: Int)] {
            var seen = Set<String>(), out: [(measure: Int, index: Int)] = []
            for e in infos where seen.insert("\(e.measure)|\(e.index)").inserted { out.append((e.measure, e.index)) }
            return out.sorted { $0.measure != $1.measure ? $0.measure > $1.measure : $0.index > $1.index }
        }
        commit { s in
            if !notes.isEmpty { for e in order(notes) { ScoreEdit.erase(&s, measure: e.measure, index: e.index) } }
            else { for e in order(rests) { ScoreEdit.deleteRest(&s, measure: e.measure, index: e.index) } }
        }
    }

    /// Anything the eraser touches goes, with nothing to select first: a note becomes a rest, a rest comes off the page.
    private func eraseHit(_ q: CGPoint, page: Int) {
        guard !erasing, !stale else { return }
        if let n = note(at: q, page: page), let info = n.edit {
            erasing = true   // one at a time: the page is redrawn before the next, so indices stay right
            commit { ScoreEdit.erase(&$0, measure: info.measure, index: info.index) }
            if selected?.measure == info.measure && selected?.index == info.index { selected = nil }
        } else if let r = rest(at: q, page: page), let info = r.edit {
            erasing = true
            commit { _ = ScoreEdit.deleteRest(&$0, measure: info.measure, index: info.index) }
            selected = nil
        }
    }

    // MARK: Editing

    /// Hooks the edit history into the system's undo, so the three-finger swipe, shake and Command-Z reach it too.
    private func connectUndo() {
        bridge.undo = {
            step(undo: true)
            undoManager?.registerUndo(withTarget: bridge) { $0.redo() }
        }
        bridge.redo = {
            step(undo: false)
            undoManager?.registerUndo(withTarget: bridge) { $0.undo() }
        }
    }

    private func commit(_ f: (inout ParsedScore) -> Void) {
        guard var s = score else { return }
        connectUndo()
        undoManager?.registerUndo(withTarget: bridge) { $0.undo() }
        undo.append(s); redo = []
        f(&s)
        score = s
        dirty = true
        stale = true
        engrave()
    }

    private func step(undo isUndo: Bool) {
        guard var s = score, let other = isUndo ? undo.popLast() : redo.popLast() else { return }
        if isUndo { redo.append(s) } else { undo.append(s) }
        s = other
        score = s
        selected = nil
        dirty = true
        stale = true
        engrave()
    }

    private var selectedIsRest: Bool {
        guard let s = selected, let n = score?.measures[s.measure].notes[s.index] else { return false }
        return n.diatonic == nil
    }

    /// The selected note or rest takes the chosen length.
    private func resizeSelected(_ ticks: Int, tuplet: Int? = nil) {
        guard let s = selected else { return }
        let tuplet = tuplet ?? self.tuplet, free = self.free
        if selectedIsRest { commit { _ = free ? ScoreEdit.setRestFree(&$0, measure: s.measure, index: s.index, ticks: ticks, tuplet: tuplet) : ScoreEdit.setRest(&$0, measure: s.measure, index: s.index, ticks: ticks, tuplet: tuplet) } }
        else { commit { _ = free ? ScoreEdit.resizeFree(&$0, measure: s.measure, index: s.index, ticks: ticks, tuplet: tuplet) : ScoreEdit.resize(&$0, measure: s.measure, index: s.index, ticks: ticks, tuplet: tuplet) } }
    }

    private var selectedTied: Bool {
        guard let s = selected, let n = score?.measures[s.measure].notes[s.index] else { return false }
        return n.tieStart
    }

    private func tieSelected() {
        guard let s = selected else { return }
        let free = self.free
        guard var probe = score, ScoreEdit.toggleTie(&probe, measure: s.measure, index: s.index, free: free) else {
            tieMessage = String(localized: "There is no note after this one to tie to. Add one first, or turn on Free Editing in Options.")
            return
        }
        commit { _ = ScoreEdit.toggleTie(&$0, measure: s.measure, index: s.index, free: free) }
    }

    private func accidental(_ a: ScoreEdit.Accidental) {
        guard let s = selected else { return }
        commit { ScoreEdit.setAccidental(&$0, measure: s.measure, index: s.index, a) }
    }

    /// A note becomes a rest; a rest is taken out, its time going to the note before it.
    private func deleteSelected() {
        guard let s = selected else { return }
        if selectedIsRest { commit { _ = ScoreEdit.deleteRest(&$0, measure: s.measure, index: s.index) } }
        else { commit { _ = ScoreEdit.erase(&$0, measure: s.measure, index: s.index) } }
        selected = nil
    }

    // MARK: Bars

    private var barFlow: Flow? { selectedBar.flatMap { score?.measures.indices.contains($0) == true ? score?.measures[$0].flow : nil } }

    private func barEdit(_ f: @escaping (inout ParsedScore, Int) -> Void) {
        guard let b = selectedBar else { return }
        commit { f(&$0, b) }
    }

    private var canExpand: Bool { score.map { $0.playOrder != Array($0.measures.indices) } ?? false }

    private var barControls: some View {
        let flow = barFlow
        return HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { barEdit { ScoreEdit.toggleRepeatStart(&$0, measure: $1) } } label: { Label("‖: Start", systemImage: "arrowtriangle.right.fill").labelStyle(.titleOnly) }
                        .lit(flow?.repeatStart == true)
                    Button { barEdit { ScoreEdit.cycleRepeatEnd(&$0, measure: $1) } } label: {
                        Text(flow.map { $0.repeatEnd > 0 ? ":‖ ×\($0.repeatEnd)" : ":‖ End" } ?? ":‖ End")
                    }
                    .lit((flow?.repeatEnd ?? 0) > 0)
                    Button("Add Bar After", systemImage: "plus.rectangle") { barEdit { ScoreEdit.insertBar(&$0, after: $1) } }
                    Button(barsChosen > 1 ? "Delete \(barsChosen) Bars" : "Delete Bar", systemImage: "trash") { deleteBar() }.keyTint(.red)
                }
            }
            .disabled(selectedBar == nil)
            Divider().frame(height: 28)
            Button("Expand Repeats", systemImage: "rectangle.expand.vertical") { commit { _ = ScoreEdit.expandRepeats(&$0) }; selectedBar = nil }
                .disabled(!canExpand)
                .help("Write every repeat, ending and jump out as its own bars")
        }
    }

    private var formControls: some View {
        let flow = barFlow
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("1st Time Bar") { barEdit { ScoreEdit.toggleEnding(&$0, measure: $1, number: 1) } }.lit(flow?.endings == [1])
                Button("2nd Time Bar") { barEdit { ScoreEdit.toggleEnding(&$0, measure: $1, number: 2) } }.lit(flow?.endings == [2])
                Button("No Time Bar", systemImage: "xmark.circle") { barEdit { ScoreEdit.clearEnding(&$0, measure: $1, whole: true) } }
                    .disabled(flow?.endings.isEmpty != false)
                    .help("Remove the 1st or 2nd time bar from this bar and the bars joined to it")
                Button("Bracket Longer", systemImage: "arrow.right.to.line") { barEdit { _ = ScoreEdit.extendEnding(&$0, measure: $1) } }
                    .disabled(flow?.endings.isEmpty != false)
                Button("Bracket Shorter", systemImage: "arrow.left.to.line") { barEdit { _ = ScoreEdit.shortenEnding(&$0, measure: $1) } }
                    .disabled(flow?.endings.isEmpty != false)
                Divider().frame(height: 28)
                Menu {
                    ForEach(ScoreEdit.Sign.allCases, id: \.self) { sign in
                        Button { barEdit { ScoreEdit.toggle(sign, &$0, measure: $1) } } label: {
                            if let score, let selectedBar, ScoreEdit.has(sign, in: score, measure: selectedBar) { Label(sign.rawValue, systemImage: "checkmark") } else { Text(sign.rawValue) }
                        }
                    }
                } label: { Label("Jumps", systemImage: "arrow.uturn.right") }
                Button("Tempo", systemImage: "metronome") {
                    guard let b = selectedBar, let s = score else { return }
                    tempoDraft = ScoreEdit.tempo(at: b, in: s, fallback: item.tempo)
                    showTempo = true
                }
                .popover(isPresented: $showTempo) { tempoPopover }
            }
        }
        .disabled(selectedBar == nil)
    }

    private var markControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([(ScoreEdit.Accidental.sharp, "\u{E262}", "Sharp"), (.flat, "\u{E260}", "Flat"), (.natural, "\u{E261}", "Natural")], id: \.2) { a in
                    Button { accidental(a.0) } label: { Text(a.1).font(.custom("Bravura", size: 28)).frame(width: 30, height: 40) }
                        .disabled(selected == nil || selectedIsRest)
                        .accessibilityLabel(a.2)
                }
                Button("Key", systemImage: "arrow.counterclockwise") { accidental(.key) }.disabled(selected == nil || selectedIsRest).labelStyle(.titleOnly)
                    .accessibilityLabel("Follow the key signature")
                Divider().frame(height: 28)
                Button { tieSelected() } label: { Text("Tie").frame(height: 40) }
                    .lit(selectedTied)
                    .disabled(selected == nil || selectedIsRest)
                    .accessibilityLabel("Tie to the next note")
                    .help("Tie this note to the next one, so they sound as one long note")
                Divider().frame(height: 28)
                ForEach(ScoreEdit.articulations, id: \.name) { a in
                    Button(a.label) { articulate(a.name) }
                        .lit(selectedHas(a.name))
                        .disabled(selected == nil || selectedIsRest)
                }
            }
        }
    }

    private var dynamicControls: some View {
        let hp = barHairpin
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ScoreEdit.dynamicNames, id: \.self) { d in
                    Button { setDynamic(d) } label: { Text(d).font(.custom("Baskerville-BoldItalic", size: 20)).frame(minWidth: 30, minHeight: 40) }
                        .lit(currentDynamic == d)
                        .accessibilityLabel(d)
                }
                Button("None") { setDynamic(nil) }.disabled(currentDynamic == nil)
                Divider().frame(height: 28)
                Button("Crescendo") { barEdit { ScoreEdit.toggleHairpin(&$0, measure: $1, crescendo: true) } }
                    .lit(hp?.crescendo == true)
                Button("Diminuendo") { barEdit { ScoreEdit.toggleHairpin(&$0, measure: $1, crescendo: false) } }
                    .lit(hp?.crescendo == false)
                Button("Longer", systemImage: "arrow.right.to.line") { barEdit { _ = ScoreEdit.resizeHairpin(&$0, measure: $1, by: 1) } }.disabled(hp == nil)
                Button("Shorter", systemImage: "arrow.left.to.line") { barEdit { _ = ScoreEdit.resizeHairpin(&$0, measure: $1, by: -1) } }.disabled(hp == nil || hp?.span == 0)
            }
        }
        .disabled(selectedBar == nil)
    }

    /// Where a dynamic goes: at the chosen note, else the start of the chosen bar.
    private var dynamicTick: Int { selected.flatMap { s in score?.measures[s.measure].notes[s.index].tick } ?? 0 }
    private var currentDynamic: String? {
        guard let b = selectedBar, let s = score else { return nil }
        return ScoreEdit.dynamic(in: s, measure: b, tick: dynamicTick)
    }
    private var barHairpin: Hairpin? {
        guard let b = selectedBar, let s = score else { return nil }
        return ScoreEdit.hairpin(in: s, measure: b)
    }
    private func setDynamic(_ text: String?) {
        guard let m = selected?.measure ?? selectedBar else { return }
        let tick = dynamicTick
        commit { ScoreEdit.setDynamic(&$0, measure: m, tick: tick, text: text) }
    }
    private func selectedHas(_ articulation: String) -> Bool {
        guard let s = selected, let n = score?.measures[s.measure].notes[s.index] else { return false }
        return n.articulations.contains(articulation)
    }
    private func articulate(_ name: String) {
        guard let s = selected else { return }
        commit { ScoreEdit.toggleArticulation(&$0, measure: s.measure, index: s.index, name) }
    }

    // MARK: Medley

    private var medleyControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button("Copy", systemImage: "doc.on.doc") { copyBars() }.disabled(medleyRange == nil)
                Button("Cut", systemImage: "scissors") { cutBars() }.disabled(medleyRange == nil)
                Button("Paste", systemImage: "doc.on.clipboard") { pasteBars() }.disabled(library.barClip == nil)
                Button { matchKey.toggle() } label: { Label("Match Key", systemImage: matchKey ? "checkmark.circle.fill" : "circle") }
                    .lit(matchKey)
                    .help("Move pasted bars into the key of the music they go after")
                Divider().frame(height: 28)
                Button("Insert from Score…", systemImage: "square.and.arrow.down.on.square") { showInsert = true }
                Button("Duplicate", systemImage: "plus.square.on.square") { duplicateBars() }.disabled(medleyRange == nil)
                Button("Delete", systemImage: "trash") { deleteRange() }.keyTint(.red).disabled(medleyRange == nil)
            }
        }
    }

    private func copyBars() {
        guard let r = medleyRange, let s = score, let clip = ScoreEdit.clip(from: s, bars: r, title: item.title) else { return }
        library.barClip = clip
    }

    private func cutBars() { copyBars(); deleteRange() }

    private func deleteRange() {
        guard let r = medleyRange else { return }
        commit { _ = ScoreEdit.deleteBars(&$0, r) }
        medleyRange = nil; medleyAnchor = nil
    }

    /// Bars from the clipboard (or another score) go in after the chosen bars, or at the end of the piece.
    private func pasteBars(_ clip: BarClip? = nil, matchKey override: Bool? = nil) {
        guard let clip = clip ?? library.barClip, let s = score else { return }
        let position = medleyRange?.upperBound ?? (s.measures.count - 1), opening = item.tempo, match = override ?? matchKey
        var went: ClosedRange<Int>?
        commit { went = ScoreEdit.paste(&$0, clip: clip, after: position, matchKey: match, openingTempo: opening) }
        medleyRange = went; medleyAnchor = went?.lowerBound
    }

    private func duplicateBars() {
        guard let r = medleyRange, let s = score, let clip = ScoreEdit.clip(from: s, bars: r, title: item.title) else { return }
        pasteBars(clip, matchKey: false)
    }

    private var tempoPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tempo at Bar \((selectedBar ?? 0) + 1)").font(.headline)
            NumberStepper(title: "♩ =", value: $tempoDraft, range: 20...300, unit: "BPM")
            Text("Playback speeds up or slows down from this bar on, relative to the opening tempo, until the next mark. A recording has its own tempo, so marks only change the built-in instrument.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Remove Mark", role: .destructive) {
                    barEdit { s, b in ScoreEdit.setTempo(&s, measure: b, bpm: nil, opening: item.tempo) }
                    showTempo = false
                }
                .disabled(selectedBar.map { score?.measures[$0].tempo == nil } ?? true)
                Spacer()
                Button("Set Mark") {
                    let bpm = tempoDraft
                    barEdit { s, b in ScoreEdit.setTempo(&s, measure: b, bpm: bpm, opening: item.tempo) }
                    showTempo = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 340)
        .presentationCompactAdaptation(.popover)
    }

    /// The bar chosen in the Bars tool, or every bar dragged across.
    private func deleteBar() {
        if tool == .bar, let r = medleyRange, r.count > 1 { commit { _ = ScoreEdit.deleteBars(&$0, r) }; medleyRange = nil; medleyAnchor = nil; selectedBar = nil; return }
        guard let b = selectedBar else { return }
        commit { _ = ScoreEdit.deleteBar(&$0, measure: b) }
        selectedBar = nil
        medleyRange = nil; medleyAnchor = nil
    }

    private var barsChosen: Int { tool == .bar ? medleyRange?.count ?? 0 : 0 }

    // MARK: Palette

    private var palette: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Tool.allCases) { t in
                            Button { withAnimation(.snappy(duration: 0.2)) { tool = t } } label: {
                                Label(t.rawValue, systemImage: t.symbol).font(.callout.weight(.medium)).padding(.horizontal, 4)
                            }
                            .buttonStyle(KeyStyle())
                            .lit(tool == t)
                            .accessibilityAddTraits(tool == t ? .isSelected : [])
                        }
                    }
                }
                Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }.accessibilityLabel("What do the modes do?")
                if tool != .draw {
                    Button { if let m = undoManager, m.canUndo { m.undo() } else { connectUndo(); bridge.undo() } } label: { Image(systemName: "arrow.uturn.backward") }.disabled(undo.isEmpty).accessibilityLabel("Undo")
                        .keyboardShortcut("z", modifiers: .command)
                    Button { if let m = undoManager, m.canRedo { m.redo() } else { connectUndo(); bridge.redo() } } label: { Image(systemName: "arrow.uturn.forward") }.disabled(redo.isEmpty).accessibilityLabel("Redo")
                        .keyboardShortcut("z", modifiers: [.command, .shift])
                } else {
                    Button { ink.undo() } label: { Image(systemName: "arrow.uturn.backward") }.accessibilityLabel("Undo drawing")
                    Button { ink.redo() } label: { Image(systemName: "arrow.uturn.forward") }.accessibilityLabel("Redo drawing")
                }
            }
            switch tool {
            case .bar: barControls
            case .form: formControls
            case .medley: medleyControls
            case .marks: markControls
            case .dynamics: dynamicControls
            case .draw: EmptyView()
            default: noteControls
            }
            (Text("\(tool.rawValue): \(tool.purpose). ").bold().foregroundStyle(Theme.accent) + Text(hint).foregroundStyle(.secondary))
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(KeyStyle())
        .padding(.horizontal, 18).padding(.vertical, 14)
        .metalPlate(radius: 14, screws: true)
        .padding(.horizontal, 16).padding(.bottom, 8)
        .environment(\.colorScheme, .dark)
        .onChange(of: tool) { _, t in
            if t.choosesBar { selected = nil } else if t != .dynamics, t != .marks { selectedBar = nil }
            if t == .erase || t == .draw { selected = nil; selectedBar = nil }
            if t != .medley { medleyRange = nil; medleyAnchor = nil }
        }
        .sheet(isPresented: $showHelp) { helpSheet }
    }

    private var helpSheet: some View {
        NavigationStack {
            List {
                ForEach(Tool.allCases) { t in
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t.rawValue).font(.headline)
                            Text(help(for: t)).font(.callout).foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: t.symbol).foregroundStyle(Theme.accent).frame(width: 28) }
                    .padding(.vertical, 4)
                }
                Section("Anywhere") {
                    Text("Select a note, then tap a length (semibreve, minim, crotchet…) to change how long it lasts. The dot makes it longer by half; the 3 makes triplets, three notes in the time of two. A note takes over whatever follows it in the bar; a shorter one leaves rests behind.")
                    Text("Options (top right) has Free Editing. With it on, the editor stops helping: notes are never clipped to the bar, never overwrite their neighbours and leave no rests behind, so a bar can hold too many or too few beats. Touch empty space in a bar to add a note after the last one.")
                    Text("Double-tap Apple Pencil to switch to the eraser and back. Undo and Redo are at the top right of this panel.")
                }
            }
            .navigationTitle("Editing Modes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showHelp = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func help(for t: Tool) -> String {
        switch t {
        case .pencil: String(localized: "Touch a rest and slide up or down to choose the pitch; lift to put a note there, as long as the length chosen below. Drag a note up or down to move it. Scribble back and forth over notes to rub them out. Tapping a note or an empty bar brings up a small menu of the things you are most likely to want.")
        case .marks: String(localized: "Tap a note, then add a sharp, flat or natural, tie it to the next note, or give it staccato, accent, tenuto, marcato or a fermata. Tap one again to take it off.")
        case .dynamics: String(localized: "Tap a note (the dynamic goes at that note) or a bar (it goes at the start), then choose ppp to fff. Crescendo and Diminuendo put a hairpin over the bar; Longer and Shorter stretch it across more bars. The built-in instrument plays louder and softer to match.")
        case .rest: String(localized: "Tap a note to turn it into a rest of the chosen length. Tap a rest to select it, then choose another length to change it, or the bin to take it off the page (the bar keeps its length).")
        case .erase: String(localized: "Touch or drag over notes and rests. A note becomes a rest; a rest comes off the page. Nothing needs selecting first.")
        case .draw: String(localized: "Draw over the music with Apple Pencil and the pen, marker, pencil and colour tools. Your drawing stays on the sheet music, and shows when you play it. White works too. Use the eraser in the tool palette to rub it out.")
        case .bar: String(localized: "Tap a bar, then add or remove repeat signs, or insert or delete the bar. Expand Repeats writes the piece out as it is played.")
        case .medley: String(localized: "Drag across bars to choose them, then Copy, Cut or Duplicate. Paste puts the copied bars in after the chosen bars (or at the end), in this score or any other you open next, so you can build a medley. Insert from Score takes bars from another score in your library. Match Key moves them into the key they follow; each piece keeps its own metre and tempo.")
        case .form: String(localized: "Tap a bar, then put a first or second time bar over it (Bracket Longer stretches it over more bars), add Segno, Coda, To Coda, D.C., D.S. or Fine, or set a tempo mark.")
        }
    }

    private var noteControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([(1920, "\u{E1D2}", "Semibreve"), (960, "\u{E1D3}", "Minim"), (480, "\u{E1D5}", "Crotchet"), (240, "\u{E1D7}", "Quaver"), (120, "\u{E1D9}", "Semiquaver")], id: \.0) { d in
                    Button {
                        base = d.0
                        if tool != .erase { resizeSelected(ticks) }
                    } label: {
                        Text(tool == .rest ? Self.restGlyph(d.0) : d.1).font(.custom("Bravura", size: 30)).frame(width: 34, height: 40)
                    }
                    .lit(base == d.0)
                    .accessibilityLabel(d.2 + (tool == .rest ? " rest" : " note"))
                }
                Button { dotted.toggle(); if dotted { triplet = false }; if tool != .erase { resizeSelected(ticks) } } label: {
                    Text("•").font(.system(size: 24, weight: .bold)).frame(width: 30, height: 40)
                }
                .lit(dotted)
                .accessibilityLabel("Dotted")
                Button { triplet.toggle(); if triplet { dotted = false }; if tool != .erase { resizeSelected(ticks) } } label: {
                    Text("3").font(.custom("Baskerville-BoldItalic", size: 22)).frame(width: 30, height: 40)
                }
                .lit(triplet)
                .accessibilityLabel("Triplet")
                .help("Triplet: three notes in the time of two")
                Divider().frame(height: 28)
                Button { deleteSelected() } label: { Image(systemName: "trash").frame(width: 30, height: 40) }
                    .disabled(selected == nil).keyTint(.red)
                    .accessibilityLabel(selectedIsRest ? String(localized: "Remove rest") : String(localized: "Turn note into a rest"))
            }
        }
    }

    static func restGlyph(_ ticks: Int) -> String {
        switch ticks { case 1920: "\u{E4E3}"; case 960: "\u{E4E4}"; case 480: "\u{E4E5}"; case 240: "\u{E4E6}"; default: "\u{E4E7}" }
    }

    /// What is selected, so it's clear what the length buttons will change.
    private var selection: String? {
        guard let s = selected, let n = score?.measures[s.measure].notes[s.index] else { return nil }
        let names = ["whole": "semibreve", "half": "minim", "quarter": "crotchet", "eighth": "quaver", "16th": "semiquaver", "32nd": "demisemiquaver"]
        let length = (n.dots > 0 ? "dotted " : n.tuplet == 3 ? "triplet " : "") + (names[n.type] ?? n.type)
        return n.diatonic == nil ? "\(length) rest" : "\(length) \(Self.name(n.diatonic!))"
    }

    private var hint: String {
        if tool == .pencil || tool == .rest, let selection { return String(localized: "Selected: \(selection). Tap a length to change it, or the bin to remove it.") }
        if tool == .marks, let selection { return String(localized: "Selected: \(selection).") }
        return switch tool {
        case .pencil: String(localized: "Touch a rest and slide up or down to pick a pitch; drag a note to move it; scribble over a note to rub it out. Tap a note, then a length, to change its duration. The 3 makes triplets; Tie joins a note to the next one.")
        + (free ? String(localized: " Free Editing is on: nothing is corrected, and touching empty space in a bar adds a note after the last one.") : "")
        case .rest: String(localized: "Tap a note to turn it into a rest of the chosen length, or tap a rest to select it and change its length.")
        case .erase: String(localized: "Touch or drag over what you want gone: notes become rests, rests come off the page. Double-tap Apple Pencil to switch to the eraser and back.")
        case .draw: String(localized: "Draw with Apple Pencil using the tool palette; the ink stays on the page.")
        case .marks: String(localized: "Tap a note to mark it.")
        case .dynamics: selectedBar == nil ? "Tap a note or a bar to choose where the dynamic goes." : String(localized: "Bar \(selectedBar! + 1)\(selected == nil ? "" : ", at the chosen note"): choose a dynamic, or a crescendo or diminuendo over the bar.")
        case .medley: medleyRange.map { String(localized: "Bars \($0.lowerBound + 1) to \($0.upperBound + 1) chosen. Copy, Cut, Duplicate or Delete them, or Paste after them.") } ?? String(localized: "Touch a bar and drag across more to choose them. With none chosen, Paste goes at the end.")
        case .bar: selectedBar == nil ? "Tap a bar to choose it, or drag across several to delete them together." : barsChosen > 1 ? String(localized: "Bars \(medleyRange!.lowerBound + 1) to \(medleyRange!.upperBound + 1) chosen. Delete them, or tap one bar for repeat signs.") : String(localized: "Bar \(selectedBar! + 1): add repeat signs, or insert or delete the bar. Drag across more bars to choose several.")
        case .form: selectedBar == nil ? "Tap a bar to choose it, then add endings, jumps or a tempo mark." : String(localized: "Bar \(selectedBar! + 1): 1st/2nd time bars (Bracket Longer stretches one over the next bar), jumps, or a tempo mark.")
        }
    }

    // MARK: Load, engrave, save

    private func load() async {
        failure = nil
        let url = item.isPDF ? library.convertedURL(item) : library.scoreURL(item)
        do {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ScoreError.unsupported(String(localized: "Open this PDF once first, so the app can read its notes, then come back to edit a copy."))
            }
            let s = try await Task.detached { try MusicXML.parse(MusicXML.data(from: url)) }.value
            ink.load(from: library.folder(item).appending(path: "annotations0-100.plist"))
            score = s
            if !item.isPDF, library.history(item) == nil { library.recordVersion(s, "Starting point", for: item) }
            undo = []; redo = []; selected = nil
            undoManager?.removeAllActions(withTarget: bridge)
            stale = true
            engrave()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func engrave() {
        guard let s = score else { return }
        engraving?.cancel()
        engraving = Task {
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            let (data, t) = await Task.detached(priority: .userInitiated) { Engraver.engrave(s, musicFont: ScoreLoader.musicFont) }.value
            guard !Task.isCancelled, let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider) else { return }
            document = doc
            pages = (0..<doc.numberOfPages).compactMap { doc.page(at: $0 + 1) }
            timeline = t
            player.timeline = t
            player.tempo = s.tempo ?? s.measures.compactMap(\.tempo).first ?? 100
            erasing = false
            stale = false
            #if DEBUG
            if let i = CommandLine.arguments.firstIndex(of: "-edittool"), i + 1 < CommandLine.arguments.count, let t = Tool(rawValue: CommandLine.arguments[i + 1]), tool != t { tool = t }
            if CommandLine.arguments.contains("-medleytest"), !testRan, let before = score?.measures.count {
                testRan = true
                tool = .medley; medleyRange = 0...1; copyBars()
                medleyRange = 14...14; pasteBars()
                try? "bars \(before) -> \(score?.measures.count ?? 0); range \(String(describing: medleyRange)); clip \(library.barClip?.count ?? 0)".write(toFile: "/tmp/medley-test.txt", atomically: true, encoding: .utf8)
            }
            if CommandLine.arguments.contains("-quickmenu"), selected == nil, let n = timeline.notes.first(where: { !$0.isRest && $0.edit != nil }) { selected = n.edit }
            if CommandLine.arguments.contains("-editortest"), !testRan { testRan = true; Task { await runTest() } }
            #endif
        }
    }

    #if DEBUG
    @State private var testRan = false
    /// Drives the same entry points the touch layer does, to check hit-testing and editing end to end.
    private func runTest() async {
        func settle() async {
            try? await Task.sleep(for: .milliseconds(100))
            for _ in 0..<100 where stale { try? await Task.sleep(for: .milliseconds(50)) }
        }
        var log: [String] = []
        let before = score!
        // Drag the first note two steps up.
        if let n = timeline.notes.first(where: { !$0.isRest && $0.edit != nil }), let e = n.edit {
            let q = CGPoint(x: n.rect.midX, y: n.rect.midY)
            tool = .pencil
            began(q, page: n.page); moved(CGPoint(x: q.x, y: q.y - e.space), page: n.page); ended(CGPoint(x: q.x, y: q.y - e.space), page: n.page)
            log.append("moved \(Self.name(before.measures[e.measure].notes[e.index].diatonic!)) → \(Self.name(score!.measures[e.measure].notes[e.index].diatonic!))")
            await settle()
        }
        // Erase the second note on the page.
        if let n = timeline.notes.filter({ !$0.isRest && $0.edit != nil }).dropFirst().first, let e = n.edit {
            tool = .erase
            began(CGPoint(x: n.rect.midX, y: n.rect.midY), page: n.page); ended(CGPoint(x: n.rect.midX, y: n.rect.midY), page: n.page)
            log.append("erased → rest: \(score!.measures[e.measure].notes[e.index].diatonic == nil)")
            await settle()
        }
        // Draw a note on that rest.
        if let r = timeline.notes.first(where: { $0.isRest && $0.edit != nil }), let e = r.edit {
            tool = .pencil
            let y = e.top + e.space * 2
            began(CGPoint(x: r.rect.midX, y: y), page: r.page); ended(CGPoint(x: r.rect.midX, y: y), page: r.page)
            log.append("drew a note: \(score!.measures.flatMap(\.notes).count) notes+rests vs \(before.measures.flatMap(\.notes).count)")
            await settle()
        }
        // Scribble over the third note on the page.
        if let n = timeline.notes.filter({ !$0.isRest && $0.edit != nil }).dropFirst(2).first, let e = n.edit {
            tool = .pencil
            let c = CGPoint(x: n.rect.midX, y: n.rect.midY)
            began(c, page: n.page)
            for i in 0..<24 { moved(CGPoint(x: c.x + (i % 4 < 2 ? -e.space : e.space) * 0.8, y: c.y + CGFloat(i) * 0.2), page: n.page) }
            ended(c, page: n.page)
            log.append("scribble erased: \(score!.measures[e.measure].notes[e.index].diatonic == nil)")
            await settle()
        }
        // The Rests tool turns the next note into an eighth rest.
        if let n = timeline.notes.filter({ !$0.isRest && $0.edit != nil }).dropFirst(3).first, let e = n.edit {
            tool = .rest; base = 240
            began(CGPoint(x: n.rect.midX, y: n.rect.midY), page: n.page); ended(CGPoint(x: n.rect.midX, y: n.rect.midY), page: n.page)
            let r = score!.measures[e.measure].notes[e.index]
            log.append("rest tool: \(r.diatonic == nil) \(r.duration)")
            await settle()
        }
        // Bars: repeat marks and an ending on bar 3.
        if let m = timeline.measures.first(where: { $0.bar == 2 }) {
            tool = .bar
            let sys = timeline.systems[m.system]
            began(CGPoint(x: (m.x0 + m.x1) / 2, y: sys.rect.midY), page: sys.page); ended(CGPoint(x: (m.x0 + m.x1) / 2, y: sys.rect.midY), page: sys.page)
            barEdit { ScoreEdit.toggleRepeatStart(&$0, measure: $1) }
            barEdit { ScoreEdit.cycleRepeatEnd(&$0, measure: $1) }
            barEdit { ScoreEdit.toggleEnding(&$0, measure: $1, number: 1) }
            log.append("bar \(selectedBar.map { $0 + 1 } ?? -1): start \(score!.measures[2].flow.repeatStart) end \(score!.measures[2].flow.repeatEnd) ending \(score!.measures[2].flow.endings)")
            await settle()
        }
        try? log.joined(separator: "\n").write(toFile: "/tmp/editor-test.txt", atomically: true, encoding: .utf8)
    }
    #endif

    /// A version from the history becomes the score in the editor (and can be undone like any edit).
    private func applyVersion(_ s: ParsedScore) { commit { $0 = s } }

    /// Writes what the editor has to the score's file, as the history has already recorded it.
    private func persistVersion() {
        guard let s = score, (try? library.saveEdited(s, for: item)) != nil else { return }
        dirty = false
    }

    private func save() {
        guard var s = score else { return }
        if !free { ScoreEdit.fillShortBars(&s) }
        do {
            let result = try library.saveEdited(s, for: item)
            dirty = false
            if !item.isPDF { library.recordVersion(s, "Saved changes", for: item) }
            if item.isPDF {
                // A copy of a PDF keeps the drawing that was on it.
                let old = library.folder(item).appending(path: "annotations0-100.plist")
                try? FileManager.default.copyItem(at: old, to: library.folder(result).appending(path: "annotations0-100.plist"))
                library.openRequest = result.id
            }
            dismiss()
        } catch {
            failure = error.localizedDescription
        }
    }
}

// MARK: - Touch input

/// Reports touches on the page straight away, from Apple Pencil (and a mouse); fingers too when asked, and the
/// pencil's double-tap. With fingers off, the page scrolls under them as usual.
struct StylusSurface: UIViewRepresentable {
    var allowFingers: Bool
    var began: (CGPoint) -> Void
    var moved: (CGPoint) -> Void
    var ended: (CGPoint) -> Void
    var pencilTap: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Keeps the Pencil from also scrolling the page it is drawing on: only fingers scroll.
    final class Surface: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var up = superview
            while let s = up, !(s is UIScrollView) { up = s.superview }
            (up as? UIScrollView)?.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue), NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        }
    }

    func makeUIView(context: Context) -> UIView {
        let v = Surface()
        v.backgroundColor = .clear
        let r = TouchRecognizer()
        r.cancelsTouchesInView = false
        v.addGestureRecognizer(r)
        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        v.addInteraction(pencil)
        context.coordinator.recognizer = r
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {
        let c = context.coordinator
        c.pencilTap = pencilTap
        guard let r = c.recognizer else { return }
        r.onBegan = began; r.onMoved = moved; r.onEnded = ended
        var types = [UITouch.TouchType.pencil, .indirectPointer]
        if allowFingers { types.append(.direct) }
        r.allowedTouchTypes = types.map { NSNumber(value: $0.rawValue) }
    }

    final class Coordinator: NSObject, UIPencilInteractionDelegate {
        var recognizer: TouchRecognizer?
        var pencilTap: () -> Void = {}
        @available(iOS 17.5, *)
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) { pencilTap() }
        func pencilInteractionDidTap(_ interaction: UIPencilInteraction) { pencilTap() }
    }
}

final class TouchRecognizer: UIGestureRecognizer {
    var onBegan: ((CGPoint) -> Void)?, onMoved: ((CGPoint) -> Void)?, onEnded: ((CGPoint) -> Void)?
    private var tracked: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard tracked == nil, let t = touches.first else { return }
        tracked = t
        state = .began
        onBegan?(t.location(in: view))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tracked, touches.contains(t) else { return }
        state = .changed
        onMoved?(t.location(in: view))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tracked, touches.contains(t) else { return }
        state = .ended
        onEnded?(t.location(in: view))
        tracked = nil
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = tracked, touches.contains(t) else { return }
        state = .cancelled
        onEnded?(t.location(in: view))
        tracked = nil
    }
    override func reset() { tracked = nil }
}

/// Carries the editor's undo and redo to the system UndoManager (which needs an object to hold them).
final class UndoBridge: NSObject {
    var undo: () -> Void = {}
    var redo: () -> Void = {}
}
