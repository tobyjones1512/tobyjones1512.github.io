import SwiftUI
import UIKit

#if !targetEnvironment(macCatalyst)
import VisionKit

/// The system document camera: photograph one or more pages of printed music, with edge detection and
/// perspective correction. The pages come back as images.
struct DocumentScanner: UIViewControllerRepresentable {
    let finished: ([UIImage]) -> Void
    let cancelled: () -> Void

    static var isSupported: Bool { false }   // scanning is switched off for now; restore to VNDocumentCameraViewController.isSupported

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            parent.finished((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }
        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { parent.cancelled() }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) { parent.cancelled() }
    }
}
#else
enum DocumentScanner { static var isSupported: Bool { false } }
#endif

nonisolated enum ScanPDF {
    /// The photographed pages as one cleaned-up PDF (lighting flattened, straightened, staves at the reader's size).
    static func make(from images: [UIImage], named fallback: String) throws -> URL {
        // Bake in the camera's orientation so the pixels are the right way up.
        let cgs = images.compactMap { img -> CGImage? in
            guard img.imageOrientation != .up else { return img.cgImage }
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: img.size, format: format).image { _ in img.draw(at: .zero) }.cgImage
        }
        guard !cgs.isEmpty else { throw ScoreError.unsupported("No pages were scanned.") }
        // The score takes the title printed on the first page; without one, the dated name it was given.
        var name = ScanCleanup.title(cgs[0]).map(TitleClean.clean) ?? fallback
        name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        if name.isEmpty { name = fallback }
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let file = url.appending(path: name + ".pdf")
        guard ScanCleanup.writePDF(cgs, to: file) else { throw ScoreError.unsupported("The scan couldn’t be saved.") }
        return file
    }
}
