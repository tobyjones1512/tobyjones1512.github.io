import SwiftUI
import UIKit
import PencilKit

/// Getting a score out of the app: as MusicXML, as a PDF, or to a printer.
extension Library {
    private func exportFolder() throws -> URL {
        let dir = URL.temporaryDirectory.appending(path: "export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func safeName(_ item: ScoreItem) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let name = item.title.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Score" : name
    }

    /// The score as plain MusicXML (a PDF's is the music read from it).
    func exportMusicXML(_ item: ScoreItem) throws -> URL {
        Analytics.track("export_musicxml")
        let source = item.isPDF ? convertedURL(item) : scoreURL(item)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw ScoreError.unsupported(String(localized: "Open this PDF once first, so the app can read its notes, then export them."))
        }
        let out = try exportFolder().appending(path: safeName(item) + ".musicxml")
        try MusicXML.data(from: source).write(to: out)
        return out
    }

    /// The page as a PDF: a PDF score as it came, anything else engraved in the key now shown, with the pencil
    /// annotations drawn for that key and zoom.
    func exportPDF(_ item: ScoreItem, transpose: Int) throws -> URL {
        Analytics.track("export_pdf")
        let out = try exportFolder().appending(path: safeName(item) + ".pdf")
        if item.isPDF {
            try FileManager.default.copyItem(at: scoreURL(item), to: out)
        } else {
            var parsed = try MusicXML.parse(MusicXML.data(from: scoreURL(item))).transposed(by: transpose)
            parsed.title = item.sheetTitle ?? TitleClean.clean(parsed.title)
            try Engraver.engrave(parsed, musicFont: ScoreLoader.musicFont).0.write(to: out)
        }
        let zoom = UserDefaults.standard.object(forKey: "zoom") as? Double ?? 1
        addInk(folder(item).appending(path: "annotations\(transpose)-\(Int(zoom * 100)).plist"), to: out)
        return out
    }

    /// Draws saved pencil strokes (kept in page points, as AnnotationStore does) onto the pages of a PDF.
    private func addInk(_ plist: URL, to pdf: URL) {
        guard let saved = try? PropertyListDecoder().decode([Int: Data].self, from: Data(contentsOf: plist)),
              let doc = CGPDFDocument(pdf as CFURL), doc.numberOfPages > 0 else { return }
        let ink = saved.compactMapValues { try? PKDrawing(data: $0) }.filter { !$0.value.strokes.isEmpty }
        guard !ink.isEmpty else { return }
        let data = UIGraphicsPDFRenderer(bounds: .zero).pdfData { ctx in
            for n in 1...doc.numberOfPages {
                guard let page = doc.page(at: n) else { continue }
                let box = page.getBoxRect(.mediaBox)
                ctx.beginPage(withBounds: box, pageInfo: [:])
                let c = ctx.cgContext
                c.saveGState()
                c.translateBy(x: 0, y: box.height); c.scaleBy(x: 1, y: -1)
                c.translateBy(x: -box.minX, y: -box.minY)
                c.drawPDFPage(page)
                c.restoreGState()
                guard let d = ink[n - 1] else { continue }
                let area = CGRect(origin: .zero, size: box.size)
                UITraitCollection(userInterfaceStyle: .light).performAsCurrent { d.image(from: area, scale: 2).draw(in: area) }
            }
        }
        try? data.write(to: pdf)
    }
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// The system share sheet (it has Print, Save to Files, AirDrop, Mail and the rest).
struct ActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

enum Printer {
    /// Opens the print dialog for a PDF.
    @MainActor static func print(_ pdf: URL, name: String) {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = name
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = pdf
        controller.present(animated: true)
    }
}
