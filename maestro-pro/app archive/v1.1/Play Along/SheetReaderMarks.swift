import CoreGraphics
import CoreText
import Foundation
import Vision

// What the page says about the form of the piece: repeat barlines, first/second endings, multi-bar rests,
// segno and coda signs, and the words D.C., D.S., To Coda and Fine.
// Words and rest numerals are read with Vision; signs and repeat dots by shape.
// ponytail: shape tests are tuned to common engraving sizes; an unusual segno or coda is missed (the words
// still work), and the numeral of a multi-bar rest needs Vision to read it, else the bar stays one bar.

nonisolated extension Int { var cg: CGFloat { CGFloat(self) } }

nonisolated extension SheetReader {
    struct TextItem { var text: String; var rect: CGRect }   // page pixels

    /// `factor` converts the image's pixels to the bitmap's (the page is drawn larger for reading small text).
    static func recognizeText(_ image: CGImage, factor: CGFloat = 1) -> [TextItem] {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        guard (try? VNImageRequestHandler(cgImage: image).perform([req])) != nil else { return [] }
        let w = CGFloat(image.width) * factor, h = CGFloat(image.height) * factor
        return (req.results ?? []).compactMap { o in
            guard let c = o.topCandidates(1).first else { return nil }
            let r = o.boundingBox
            return TextItem(text: c.string, rect: CGRect(x: r.minX * w, y: (1 - r.maxY) * h, width: r.width * w, height: r.height * h))
        }
    }

    /// The page drawn at 4× for reading words: Vision misses small italic words like "Fine" at 2×.
    static func ocrImage(_ page: CGPDFPage) -> CGImage? {
        let k: CGFloat = 4, w = Int(page.size.width * k), h = Int(page.size.height * k)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        page.draw(in: ctx, size: CGSize(width: w, height: h))
        return ctx.makeImage()
    }

    /// Words in a band of the page (bitmap pixels). Vision finds more in a strip than in a whole page.
    static func recognizeText(_ big: CGImage?, band: CGRect) -> [TextItem] {
        let f = CGFloat(4) / scale
        guard let big, let crop = big.cropping(to: CGRect(x: band.minX * f, y: band.minY * f, width: band.width * f, height: band.height * f)) else { return [] }
        return recognizeText(crop, factor: 1 / f).map { TextItem(text: $0.text, rect: $0.rect.offsetBy(dx: band.minX, dy: band.minY)) }
    }

    // MARK: Digits

    /// Where the music font lives, if not in the app bundle.
    nonisolated(unsafe) static var musicFontURL: URL?

    private static let gridW = 12, gridH = 16

    /// Digit shapes from a few system fonts, each stretched to the same box and sampled on a coarse grid.
    private static let digitTemplates: [(digit: Int, grid: [Bool])] = {
        var out: [(Int, [Bool])] = []
        var fonts = ["Baskerville-Bold", "Times-Bold", "Helvetica-Bold", "Georgia-Bold", "Didot-Bold", "Times-Roman"].map { (CTFontCreateWithName($0 as CFString, 100, nil), 0x30) }
        // The music font's own numerals (SMuFL time signature digits) look like most engraved ones.
        if let url = musicFontURL ?? Bundle.main.url(forResource: "Bravura", withExtension: "otf"), let data = try? Data(contentsOf: url),
           let p = CGDataProvider(data: data as CFData), let f = CGFont(p) { fonts.append((CTFontCreateWithGraphicsFont(f, 100, nil, nil), 0xE080)) }
        for (font, base) in fonts {
            for d in 0...9 {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(UnicodeScalar(base + d)!), attributes: [.init(kCTFontAttributeName as String): font]))
                let bb = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                let w = gridW * 10, h = gridH * 10
                guard bb.width > 0, bb.height > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { continue }
                ctx.setFillColor(gray: 1, alpha: 1)
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.setFillColor(gray: 0, alpha: 1)
                ctx.scaleBy(x: CGFloat(w) / bb.width, y: CGFloat(h) / bb.height)
                ctx.translateBy(x: -bb.minX, y: -bb.minY)
                ctx.textPosition = .zero
                CTLineDraw(line, ctx)
                let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h)
                out.append((d, (0..<gridW * gridH).map { i in
                    var ink = 0
                    for y in 0..<10 { for x in 0..<10 where px[((i / gridW) * 10 + y) * w + (i % gridW) * 10 + x] < 128 { ink += 1 } }
                    return ink > 40
                }))
            }
        }
        return out
    }()

    /// Which digit the ink in a box is, by best match to the templates (nil if nothing is close).
    static func digit(_ b: Bitmap, _ r: CGRect) -> Int? {
        let grid = (0..<gridW * gridH).map { i -> Bool in
            let x0 = Int(r.minX + r.width * CGFloat(i % gridW) / CGFloat(gridW)), x1 = max(x0 + 1, Int(r.minX + r.width * CGFloat(i % gridW + 1) / CGFloat(gridW)))
            let y0 = Int(r.minY + r.height * CGFloat(i / gridW) / CGFloat(gridH)), y1 = max(y0 + 1, Int(r.minY + r.height * CGFloat(i / gridW + 1) / CGFloat(gridH)))
            var ink = 0, all = 0
            for y in y0..<y1 { for x in x0..<x1 { all += 1; if b.symbol(x, y) { ink += 1 } } }
            return ink * 10 > all * 4
        }
        var score = [Double](repeating: 0, count: 10)
        for t in digitTemplates { score[t.digit] = max(score[t.digit], Double(zip(t.grid, grid).filter { $0 == $1 }.count) / Double(gridW * gridH)) }
        let order = score.indices.sorted { score[$0] > score[$1] }
        return score[order[0]] >= 0.7 && score[order[0]] - score[order[1]] >= 0.02 ? order[0] : nil
    }

    /// Two dots in the middle spaces, just before (`left`) or after a barline.
    static func repeatDots(_ b: Bitmap, edge: Int, staff s: Staff, left: Bool) -> Bool {
        let sp = s.space, ys = [s.top + Int(sp * 1.5), s.top + Int(sp * 2.5)], clear = Int(sp * 0.32)
        let lo = left ? edge - Int(sp * 2.4) : edge + Int(sp * 0.3), hi = left ? edge - Int(sp * 1.0) : edge + Int(sp * 1.3)
        guard lo < hi else { return false }
        return (lo...hi).contains { x in
            ys.allSatisfy { y in
                guard b[x, y], !b[x, y - clear], !b[x, y + clear] else { return false }
                var a = x, c = x
                while b[a - 1, y], x - a < 20 { a -= 1 }
                while b[c + 1, y], c - x < 20 { c += 1 }
                return CGFloat(c - a + 1) <= sp * 0.8
            }
        }
    }

    /// The bar count of a multi-bar rest in a bar: a number, alone, written above the staff over a thick
    /// bar on the middle line, or by itself in the staff.
    static func multiRest(_ b: Bitmap, staff s: Staff, x0: Int, x1: Int, space sp: CGFloat) -> Int? {
        let x0 = x0 + Int(sp * 0.6), x1 = x1 - Int(sp * 0.6), off = max(2, Int(sp * 0.2))
        guard x1 - x0 > Int(sp * 3) else { return nil }
        var thick = false, run = 0
        for x in x0...x1 {
            if b[x, s.mid - off] && b[x, s.mid + off] { run += 1; if CGFloat(run) >= sp * 2.5 { thick = true; break } } else { run = 0 }
        }
        // Numerals: ink shapes about as tall as a digit, with staff lines erased.
        let ys = (s.top - Int(sp * 3.5))...(s.bottom), skipRows: ClosedRange<Int>? = thick ? (s.mid - Int(sp * 0.8))...(s.mid + Int(sp * 0.8)) : nil
        var seen = Set<Int>(), digits: [CGRect] = []
        for x in x0...x1 { for y in ys where b.symbol(x, y) && !seen.contains(y * b.w + x) {
            var stack = [(x, y)], pts: [(Int, Int)] = []
            seen.insert(y * b.w + x)
            while let (px, py) = stack.popLast() {
                pts.append((px, py))
                for (qx, qy) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)]
                where qx >= x0 && qx <= x1 && ys.contains(qy) && b.symbol(qx, qy) && !seen.contains(qy * b.w + qx) {
                    seen.insert(qy * b.w + qx)
                    if pts.count + stack.count < 6000 { stack.append((qx, qy)) }
                }
            }
            let r = bounds(pts)
            if skipRows?.contains(Int(r.midY)) == true && r.width > sp * 1.5 { continue }   // the bar and its end serifs
            if r.height >= sp * 0.9, r.height <= sp * 3.4, r.width >= sp * 0.3, r.width <= sp * 2.2, r.height >= r.width * 0.8 { digits.append(r) }
        } }
        // One group of digits side by side; two stacked groups are a time signature.
        let sorted = digits.sorted { $0.minX < $1.minX }
        guard var group = sorted.first else { return nil }
        for d in sorted.dropFirst() {
            guard d.minX - group.maxX < sp * 0.9, abs(d.midY - group.midY) < sp * 0.8 else { return nil }
            group = group.union(d)
        }
        guard sorted.count <= 3 else { return nil }
        let above = group.maxY < CGFloat(s.top) + sp * 0.5
        guard thick ? above : group.height >= sp * 1.4 && group.midY > CGFloat(s.top) && group.midY < CGFloat(s.bottom) else { return nil }
        var n = 0
        for d in sorted { guard let v = digit(b, d) else { return nil }; n = n * 10 + v }
        return (2...999).contains(n) ? n : nil
    }

    /// Ending brackets above the staff: a thin line with a tick down at its left end and the ending's
    /// numbers under it. Returns pixel spans with their ending numbers.
    static func endings(_ b: Bitmap, x0: Int, x1: Int, top: Int, space sp: CGFloat) -> [(x0: Int, x1: Int, numbers: [Int])] {
        var out: [(x0: Int, x1: Int, numbers: [Int])] = []
        for y in (top - Int(sp * 7))...(top - Int(sp * 1)) {
            var x = x0
            while x < x1 {
                guard b[x, y] else { x += 1; continue }
                var e = x
                while b[e + 1, y] || b[e + 2, y] { e += 1 }
                defer { x = e + 1 }
                guard CGFloat(e - x) >= sp * 3, !out.contains(where: { abs($0.x0 - x) < 5 }) else { continue }
                let mid = (x + e) / 2
                guard !b[mid, y - 3], !b[mid, y + 3],   // a thin line, not a beam
                      (x - 1...x + 2).contains(where: { b[$0, y + Int(sp * 1.0)] }) else { continue }
                // Numbers: runs of inked columns under the line, right of the tick (small text breaks into
                // pieces, so columns rather than connected shapes).
                var digits: [CGRect] = []
                let ys = (y + Int(sp * 0.25))...(y + Int(sp * 1.9)), xs = (x + 3)...min(e, x + Int(sp * 5))
                var runStart: Int?, gap = 0
                for px in xs.lowerBound...(xs.upperBound + 3) {
                    if px <= xs.upperBound, ys.contains(where: { b[px, $0] }) { if runStart == nil { runStart = px }; gap = 0 }
                    else if let s0 = runStart {
                        gap += 1
                        if gap > 2 {
                            let cols = s0...(px - gap), inked = ys.filter { y0 in cols.contains { b[$0, y0] } }
                            if let lo = inked.first, let hi = inked.last, CGFloat(hi - lo + 1) >= sp * 0.55 {
                                digits.append(CGRect(x: s0, y: lo, width: cols.count, height: hi - lo + 1))
                            }
                            runStart = nil
                        }
                    }
                }
                // A serifed 1 reads as 7, and no piece has seven endings.
                let numbers = digits.sorted { $0.minX < $1.minX }.compactMap { digit(b, $0) }.map { $0 == 7 ? 1 : $0 }
                if !numbers.isEmpty, numbers.count == digits.count { out.append((x, e, numbers)) }
            }
        }
        return out.sorted { $0.x0 < $1.x0 }
    }

    /// Segno and coda signs above the staff, found by shape.
    static func signs(_ b: Bitmap, x0: Int, x1: Int, top: Int, space sp: CGFloat, skip: [CGRect]) -> [(x: Int, coda: Bool)] {
        let ys = (top - Int(sp * 6))...(top - Int(sp * 0.4))
        var seen = Set<Int>(), out: [(Int, Bool)] = []
        let blocked = { (x: Int, y: Int) in skip.contains { $0.insetBy(dx: -4, dy: -4).contains(CGPoint(x: x, y: y)) } }
        for x in x0...x1 { for y in ys where b[x, y] && !seen.contains(y * b.w + x) && !blocked(x, y) {
            var stack = [(x, y)], pts: [(Int, Int)] = []
            seen.insert(y * b.w + x)
            while let (px, py) = stack.popLast() {
                pts.append((px, py))
                for (qx, qy) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)]
                where qx >= x0 && qx <= x1 && ys.contains(qy) && b[qx, qy] && !seen.contains(qy * b.w + qx) {
                    seen.insert(qy * b.w + qx)
                    if pts.count + stack.count < 4000 { stack.append((qx, qy)) }
                }
            }
            let r = bounds(pts), fill = CGFloat(pts.count) / (r.width * r.height), ratio = r.height / r.width
            guard r.width >= sp * 1.3, r.width <= sp * 4.6, r.height >= sp * 2, r.height <= sp * 4.6 else { continue }
            // A note beside an "=" is a tempo mark (♩ = 96), not a sign: the sign stands alone.
            let yTop = Int(r.maxY - sp * 1.6), yBottom = Int(r.maxY)
            let beside = ((Int(r.maxX) + Int(sp * 0.3))...(Int(r.maxX) + Int(sp * 1.8))).contains { cx in cx < b.w && (yTop...yBottom).contains { cy in cy < b.h && b[cx, cy] } }
            if beside { continue }
            if ratio >= 0.8, ratio <= 1.25, fill >= 0.2, fill <= 0.55, enclosesHole(b, Int(r.minX)...Int(r.maxX), Int(r.minY)...Int(r.maxY)) { out.append((Int(r.minX), true)) }
            else if ratio >= 1.2, ratio <= 2.4, fill >= 0.15, fill <= 0.5 { out.append((Int(r.minX), false)) }
        } }
        return out
    }

    /// Marks a bar from words: D.C., D.S., To Coda, Fine, Coda, Segno.
    static func apply(words text: String, to flow: inout Flow) {
        let n = text.lowercased().filter { !$0.isWhitespace }
        if n.hasPrefix("d.c") || n.contains("dacapo") { flow.daCapo = true }
        else if n.hasPrefix("d.s") || n.contains("dalsegno") { flow.dalSegno = true }
        else if n.hasPrefix("tocoda") { flow.toCoda = true }
        else if n == "fine" || n == "fine." { flow.fine = true }
        else if n == "coda" { flow.coda = true }
        else if n == "segno" { flow.segno = true }
    }
}
