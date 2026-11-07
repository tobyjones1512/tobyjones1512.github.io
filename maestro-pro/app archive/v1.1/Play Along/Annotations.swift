import SwiftUI
import PencilKit

/// Pencil drawings on the pages of one score, kept in page points so they follow zoom. Saved per key,
/// because a transposed score is engraved afresh and the notes move.
@Observable final class AnnotationStore {
    var drawings: [Int: PKDrawing] = [:]
    var active = false
    /// The canvas most recently drawn on, so Undo and Redo buttons can reach its history.
    @ObservationIgnored weak var lastCanvas: PKCanvasView?
    func undo() { lastCanvas?.undoManager?.undo() }
    func redo() { lastCanvas?.undoManager?.redo() }
    @ObservationIgnored private var url: URL?

    func load(from url: URL) {
        self.url = url
        let saved = (try? PropertyListDecoder().decode([Int: Data].self, from: Data(contentsOf: url))) ?? [:]
        drawings = saved.compactMapValues { try? PKDrawing(data: $0) }
    }

    func set(_ drawing: PKDrawing, page: Int) {
        drawings[page] = drawing
        guard let url else { return }
        try? PropertyListEncoder().encode(drawings.mapValues { $0.dataRepresentation() }).write(to: url, options: .atomic)
    }

    var isEmpty: Bool { drawings.values.allSatisfy { $0.strokes.isEmpty } }
}

/// The ink everything starts in: a clear blue, fixed so the dark interface doesn't turn it white.
let defaultInk = PKInkingTool(.pen, color: UIColor(red: 0.1, green: 0.42, blue: 1, alpha: 1), width: 4)

/// A canvas that takes the tool picker once it's on screen and asked to draw.
final class InkView: PKCanvasView {
    static let picker: PKToolPicker = {
        let p = PKToolPicker()
        if #available(iOS 18, macCatalyst 18, *) {
            p.selectedToolItem = PKToolPickerInkingItem(type: .pen, color: UIColor(red: 0.1, green: 0.42, blue: 1, alpha: 1), width: 4)
        } else {
            p.selectedTool = defaultInk
        }
        // Swatches in the colours they show: the picker follows the app's dark look by default, which hands the
        // canvas (drawn in the light style) the opposite of what was picked, so white came out black.
        p.colorUserInterfaceStyle = .light
        return p
    }()

    var wantsInk = false { didSet { refresh() } }
    override func didMoveToWindow() { super.didMoveToWindow(); refresh() }

    private func refresh() {
        guard window != nil else { return }
        if wantsInk {
            Self.picker.addObserver(self)
            Self.picker.setVisible(true, forFirstResponder: self)
            becomeFirstResponder()
        } else if isFirstResponder {
            Self.picker.setVisible(false, forFirstResponder: self)
            resignFirstResponder()
        }
    }
}

/// A transparent canvas over one page. Pencil draws; a finger still scrolls and taps through.
struct AnnotationLayer: UIViewRepresentable {
    let store: AnnotationStore
    let page: Int
    let scale: CGFloat
    let active: Bool

    func makeCoordinator() -> Coordinator { Coordinator(store: store, page: page) }

    func makeUIView(context: Context) -> InkView {
        let v = InkView()
        v.backgroundColor = .clear
        v.isOpaque = false
        v.isScrollEnabled = false
        v.overrideUserInterfaceStyle = .light   // draw in the colours chosen, not their dark-mode versions
        v.tool = defaultInk
        #if targetEnvironment(macCatalyst)
        v.drawingPolicy = .anyInput
        #else
        v.drawingPolicy = .pencilOnly
        #endif
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ v: InkView, context: Context) {
        let c = context.coordinator
        // Only a real change of zoom reloads the drawing, since that clears what Undo can go back to.
        if abs(c.scale - scale) > 0.002 || !c.loaded {
            c.scale = scale
            c.loaded = true
            c.applying = true
            v.drawing = (store.drawings[page] ?? PKDrawing()).transformed(using: CGAffineTransform(scaleX: scale, y: scale))
            c.applying = false
        }
        v.isUserInteractionEnabled = active
        v.wantsInk = active
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let store: AnnotationStore, page: Int
        var scale: CGFloat = 0, loaded = false, applying = false
        init(store: AnnotationStore, page: Int) { self.store = store; self.page = page }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !applying, scale > 0 else { return }
            store.lastCanvas = canvasView
            store.set(canvasView.drawing.transformed(using: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)), page: page)
        }
    }
}
