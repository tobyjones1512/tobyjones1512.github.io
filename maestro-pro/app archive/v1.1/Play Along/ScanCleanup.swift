import CoreGraphics
import Vision
import Foundation

/// Turns a photographed page into the clean, straight, black-on-white page the reader expects:
/// uneven lighting and shadows are flattened, a slight tilt is corrected, and the page is sized so the
/// staves come out at the engraver's size whatever the camera distance.
nonisolated enum ScanCleanup {
    static let targetSpace: CGFloat = 7   // staff space in PDF points, same as Engraver.baseSpace

    struct Gray { var w: Int, h: Int, px: [UInt8] }

    static func gray(_ image: CGImage, maxSide: Int) -> Gray {
        let k = min(1, CGFloat(maxSide) / CGFloat(max(image.width, image.height)))
        let w = max(1, Int(CGFloat(image.width) * k)), h = max(1, Int(CGFloat(image.height) * k))
        var px = [UInt8](repeating: 255, count: w * h)
        px.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return Gray(w: w, h: h, px: px)
    }

    /// Ink where a pixel is clearly darker than the paper around it (local mean over a wide window).
    static func binarize(_ g: Gray) -> [Bool] {
        let w = g.w, h = g.h
        var sum = [Int](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h {
            var row = 0
            for x in 0..<w { row += Int(g.px[y * w + x]); sum[(y + 1) * (w + 1) + x + 1] = sum[y * (w + 1) + x + 1] + row }
        }
        let r = max(8, w / 30)
        var ink = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            let y0 = max(0, y - r), y1 = min(h, y + r + 1)
            for x in 0..<w {
                let x0 = max(0, x - r), x1 = min(w, x + r + 1)
                let area = (x1 - x0) * (y1 - y0)
                let total = sum[y1 * (w + 1) + x1] - sum[y0 * (w + 1) + x1] - sum[y1 * (w + 1) + x0] + sum[y0 * (w + 1) + x0]
                // Ink is much darker than the neighbourhood; the floor keeps blank shadow from turning into ink.
                ink[y * w + x] = Int(g.px[y * w + x]) * area * 100 < total * 78 && g.px[y * w + x] < 200
            }
        }
        return ink
    }

    /// The tilt (degrees, counter-clockwise positive) at which the ink falls into the sharpest rows: staff lines.
    static func tilt(_ ink: [Bool], w: Int, h: Int) -> Double {
        let step = max(1, w / 700)
        var pts: [(Double, Double)] = []
        for y in stride(from: 0, to: h, by: step) { for x in stride(from: 0, to: w, by: step) where ink[y * w + x] { pts.append((Double(x), Double(y))) } }
        guard pts.count > 200 else { return 0 }
        func score(_ deg: Double) -> Double {
            let s = sin(deg * .pi / 180), c = cos(deg * .pi / 180)
            var bins = [Double](repeating: 0, count: (h + 2 * w) / step + 4)
            let off = Double(w) / Double(step) + 2
            for (x, y) in pts { bins[Int((y * c + x * s) / Double(step) + off)] += 1 }
            return bins.reduce(0) { $0 + $1 * $1 }
        }
        var best = 0.0, bestScore = -1.0
        for d in stride(from: -10.0, through: 10.0, by: 0.5) { let v = score(d); if v > bestScore { best = d; bestScore = v } }
        for d in stride(from: best - 0.5, through: best + 0.5, by: 0.1) { let v = score(d); if v > bestScore { best = d; bestScore = v } }
        return best
    }

    /// Staff-line spacing in pixels, from how the rows of ink repeat.
    static func staffSpace(_ ink: [Bool], w: Int, h: Int) -> CGFloat? {
        var rows = [Double](repeating: 0, count: h)
        for y in 0..<h { var n = 0; for x in 0..<w where ink[y * w + x] { n += 1 }; rows[y] = Double(n) }
        let mean = rows.reduce(0, +) / Double(h)
        let d = rows.map { $0 - mean }
        let maxLag = min(h / 4, max(12, w / 8))
        guard maxLag > 4 else { return nil }
        let ac = (0...maxLag).map { lag in (0..<h - lag).reduce(0.0) { $0 + d[$1] * d[$1 + lag] } }
        // The first strong peak after the line's own width is the line-to-line spacing.
        guard let top = ac.dropFirst(3).max(), top > 0 else { return nil }
        for lag in 4..<maxLag where ac[lag] > ac[lag - 1] && ac[lag] >= ac[lag + 1] && ac[lag] > top * 0.6 { return CGFloat(lag) }
        return nil
    }

    static func image(_ px: [UInt8], w: Int, h: Int) -> CGImage? {
        var px = px
        return px.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }
    }

    static func rotate(_ src: CGImage, degrees: Double) -> CGImage? {
        let w = src.width, h = src.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(w) / 2, y: CGFloat(h) / 2)
        ctx.rotate(by: CGFloat(-degrees * .pi / 180))
        ctx.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: - Orientation

    static func rotated(_ g: Gray, _ turns: Int) -> Gray {   // clockwise quarter turns
        let t = ((turns % 4) + 4) % 4
        if t == 0 { return g }
        let nw = t == 2 ? g.w : g.h, nh = t == 2 ? g.h : g.w
        var out = [UInt8](repeating: 255, count: nw * nh)
        for y in 0..<g.h { for x in 0..<g.w {
            let (nx, ny) = t == 1 ? (g.h - 1 - y, x) : t == 2 ? (g.w - 1 - x, g.h - 1 - y) : (y, g.w - 1 - x)
            out[ny * nw + nx] = g.px[y * g.w + x]
        } }
        return Gray(w: nw, h: nh, px: out)
    }

    static func rowCounts(_ ink: [Bool], w: Int, h: Int) -> [Int] { (0..<h).map { y in (0..<w).reduce(0) { $0 + (ink[y * w + $1] ? 1 : 0) } } }

    /// How much upright text Vision finds: the right way up reads a title and bar numbers, upside down it reads little.
    static func textScore(_ g: Gray) -> Double {
        guard let img = image(g.px, w: g.w, h: g.h) else { return 0 }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .fast
        req.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: img).perform([req])
        return (req.results ?? []).reduce(0) { sum, o in
            guard let c = o.topCandidates(1).first, c.confidence > 0.5 else { return sum }
            return sum + Double(c.string.filter(\.isLetter).count) * Double(c.confidence)
        }
    }

    /// Turns the page so staves run left to right and the page is the right way up, however the camera was held.
    static func upright(_ g: Gray) -> Gray {
        let ink = binarize(g)
        let rows = rowCounts(ink, w: g.w, h: g.h).reduce(0) { $0 + $1 * $1 }
        var cols = 0
        for x in 0..<g.w { var n = 0; for y in 0..<g.h where ink[y * g.w + x] { n += 1 }; cols += n * n }
        // Staves run along rows or along columns; text then says which way up.
        let pair = cols > rows ? [1, 3] : [0, 2]
        let a = rotated(g, pair[0]), b = rotated(g, pair[1])
        return textScore(b) > textScore(a) ? b : a
    }

    /// The title printed on the page: the largest line of text that has real words in it.
    static func title(_ image: CGImage) -> String? {
        let g = upright(gray(image, maxSide: 2600))
        guard let img = Self.image(g.px, w: g.w, h: g.h) else { return nil }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: img).perform([req])
        let best = (req.results ?? []).compactMap { o -> (String, CGFloat)? in
            guard let c = o.topCandidates(1).first, c.confidence > 0.5, c.string.filter(\.isLetter).count >= 3,
                  o.boundingBox.midY > 0.55, (0.2...0.8).contains(o.boundingBox.midX), o.boundingBox.width > o.boundingBox.height * 3 else { return nil }   // upper middle of the page (Vision's y runs upward), not a binder label
            return (c.string.trimmingCharacters(in: .whitespacesAndNewlines), o.boundingBox.height)
        }.max { $0.1 < $1.1 }
        return best?.0
    }

    // MARK: - Page curl

    /// Pages photographed in a binder curl: a staff that should be straight bends. Slide the columns of each
    /// system up or down until its lines agree with the middle of the page.
    static func flatten(_ g: Gray) -> Gray {
        let w = g.w, h = g.h, ink = binarize(g)
        let strips = 64, sw = w / strips
        guard sw >= 8 else { return g }
        // Systems: bands of rows that carry ink across the page, split at the blank gaps between them.
        // Rows that carry a long run of ink are staff lines; the title, numbers and stray marks don't make a system.
        let live: [Bool] = (0..<h).map { y in
            var best = 0, start = -1, last = -1
            for x in 0...w {
                if x < w && ink[y * w + x] { if start < 0 { start = x }; last = x }
                else if start >= 0, x - last > 3 || x == w { best = max(best, last - start); start = -1 }
            }
            return best > w / 6
        }
        var bands: [ClosedRange<Int>] = []
        var y = 0
        while y < h {
            guard live[y] else { y += 1; continue }
            var y1 = y, gap = 0, i = y
            while i < h, gap < h / 40 { if live[i] { y1 = i; gap = 0 } else { gap += 1 }; i += 1 }
            if y1 - y > h / 60 { bands.append(max(0, y - h / 80)...min(h - 1, y1 + h / 80)) }
            y = y1 + 1
        }
        guard !bands.isEmpty else { return g }
        let reach = h / 50
        var dy = [[Int]](repeating: [Int](repeating: 0, count: strips), count: bands.count)
        for (bi, band) in bands.enumerated() {
            let lo = max(0, band.lowerBound - reach), hi = min(h - 1, band.upperBound + reach)
            let prof: [[Double]] = (0..<strips).map { s in
                (lo...hi).map { y in Double((s * sw..<(s + 1) * sw).reduce(0) { $0 + (ink[y * w + $1] ? 1 : 0) }) }
            }
            func best(_ a: [Double], _ b: [Double]) -> Int {   // shift d so that a[y + d] ≈ b[y]
                var bestD = 0, bestV = -1.0
                for d in -14...14 {
                    var v = 0.0
                    for y in 0..<a.count where y + d >= 0 && y + d < a.count { v += a[y + d] * b[y] }
                    if v > bestV { bestV = v; bestD = d }
                }
                return bestD
            }
            let mid = strips / 2
            for s in stride(from: mid + 1, to: strips, by: 1) { dy[bi][s] = dy[bi][s - 1] + best(prof[s], prof[s - 1]) }
            for s in stride(from: mid - 1, through: 0, by: -1) { dy[bi][s] = dy[bi][s + 1] + best(prof[s], prof[s + 1]) }
            // Chaining neighbours lets rounding errors pile up across the page; line each strip up with the
            // average of all of them instead.
            for _ in 0..<2 {
                var ref = [Double](repeating: 0, count: hi - lo + 1)
                for s in 0..<strips { for y in ref.indices where y + dy[bi][s] >= 0 && y + dy[bi][s] < ref.count { ref[y] += prof[s][y + dy[bi][s]] } }
                for s in 0..<strips {
                    var bestD = dy[bi][s], bestV = -1.0
                    for d in dy[bi][s] - 3...dy[bi][s] + 3 {
                        var v = 0.0
                        for y in 0..<ref.count where y + d >= 0 && y + d < ref.count { v += prof[s][y + d] * ref[y] }
                        if v > bestV { bestV = v; bestD = d }
                    }
                    dy[bi][s] = bestD
                }
            }
        }
        var out = [UInt8](repeating: 255, count: w * h)
        for y in 0..<h {
            let bi = bands.indices.min { distance(y, bands[$0]) < distance(y, bands[$1]) }!
            for x in 0..<w {
                let f = (Double(x) / Double(sw)) - 0.5
                let s0 = max(0, min(strips - 1, Int(f.rounded(.down)))), s1 = min(strips - 1, s0 + 1)
                let t = max(0, min(1, f - Double(s0)))
                let d = Int((Double(dy[bi][s0]) * (1 - t) + Double(dy[bi][s1]) * t).rounded())
                let sy = y + d
                if sy >= 0 && sy < h { out[y * w + x] = g.px[sy * w + x] }
            }
        }
        return Gray(w: w, h: h, px: out)
    }

    static func distance(_ y: Int, _ r: ClosedRange<Int>) -> Int { r.contains(y) ? 0 : min(abs(y - r.lowerBound), abs(y - r.upperBound)) }

    /// Everything outside the sheet of paper (carpet, desk, the binder's edge) turned white. Paper is where the
    /// typical (median) pixel of a small block is bright, which holds even under dense music and a shadow.
    static func whiteOutsidePage(_ g: Gray) -> Gray {
        let w = g.w, h = g.h
        let b = max(4, w / 220)
        let bw = w / b, bh = h / b
        guard bw > 8, bh > 8 else { return g }
        var med = [Int](repeating: 0, count: bw * bh)
        var block = [UInt8](repeating: 0, count: b * b)
        for by in 0..<bh { for bx in 0..<bw {
            var n = 0
            for y in by * b..<by * b + b { for x in bx * b..<bx * b + b { block[n] = g.px[y * w + x]; n += 1 } }
            block.sort()
            med[by * bw + bx] = Int(block[block.count / 2])
        } }
        let sorted = med.sorted()
        let paper = sorted[sorted.count * 9 / 10]
        let bright = med.map { $0 * 100 > paper * 55 }
        // The page is the biggest connected patch of bright blocks; each row and column keeps what lies between
        // that patch's first and last block, so dense music (dark blocks) inside it isn't cut out.
        var label = [Int](repeating: -1, count: bw * bh)
        var best: [Int] = []
        var queue: [Int] = []
        for start in 0..<bw * bh where bright[start] && label[start] < 0 {
            var members: [Int] = []
            queue = [start]; label[start] = start
            var head = 0
            while head < queue.count {
                let i = queue[head]; head += 1; members.append(i)
                let x = i % bw, y = i / bw
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < bw && ny < bh {
                    let j = ny * bw + nx
                    if bright[j], label[j] < 0 { label[j] = start; queue.append(j) }
                }
            }
            if members.count > best.count { best = members }
        }
        guard !best.isEmpty else { return g }
        var rowRange = [(Int, Int)](repeating: (Int.max, -1), count: bh), colRange = [(Int, Int)](repeating: (Int.max, -1), count: bw)
        for i in best {
            let x = i % bw, y = i / bw
            rowRange[y] = (min(rowRange[y].0, x), max(rowRange[y].1, x))
            colRange[x] = (min(colRange[x].0, y), max(colRange[x].1, y))
        }
        var out = g
        for y in 0..<h {
            let by = min(bh - 1, y / b)
            for x in 0..<w {
                let bx = min(bw - 1, x / b)
                let r = rowRange[by], c = colRange[bx]
                if !(bx > r.0 && bx < r.1 && by > c.0 && by < c.1) { out.px[y * w + x] = 255 }
            }
        }
        return out
    }

    /// The part of a photo that is the page: from the title above the first staff to below the last, and the width
    /// the staves cover. Carpet, binder and desk around it are cut away.
    static func pageRegion(_ ink: [Bool], w: Int, h: Int, space: CGFloat) -> CGRect? {
        // Rows holding a long unbroken line; a staff line is thin, a blob of carpet is thick.
        var runs: [(first: Int, last: Int)?] = []
        for y in 0..<h {
            var best = 0, start = -1, last = -1, first = 0, lastEnd = 0
            for x in 0...w {
                if x < w && ink[y * w + x] { if start < 0 { start = x }; last = x }
                else if start >= 0, x - last > 3 || x == w {
                    if last - start > best { best = last - start; first = start; lastEnd = last }
                    start = -1
                }
            }
            runs.append(best > w / 4 ? (first, lastEnd) : nil)
        }
        // Thin lines, then five in a row spaced like a staff.
        var lines: [(y: Int, first: Int, last: Int)] = []
        var y = 0
        while y < h {
            guard runs[y] != nil else { y += 1; continue }
            var y2 = y
            while y2 + 1 < h, runs[y2 + 1] != nil { y2 += 1 }
            if CGFloat(y2 - y + 1) <= max(6, space * 0.6) {
                let r = (y...y2).compactMap { runs[$0] }
                lines.append(((y + y2) / 2, r.map(\.first).min()!, r.map(\.last).max()!))
            }
            y = y2 + 1
        }
        var top = h, bottom = -1, x0 = w, x1 = 0
        var i = 0
        while i + 4 < lines.count {
            let gaps = (0..<4).map { CGFloat(lines[i + $0 + 1].y - lines[i + $0].y) }
            if gaps.allSatisfy({ abs($0 - space) <= space * 0.3 }) {
                for l in lines[i..<i + 5] { top = min(top, l.y); bottom = max(bottom, l.y); x0 = min(x0, l.first); x1 = max(x1, l.last) }
                i += 5
            } else { i += 1 }
        }
        // A staff the spacing test missed still belongs to the page if it follows on from the last one found.
        for l in lines where l.y > bottom && l.y - bottom < Int(space * 14) && bottom >= 0 { bottom = l.y; x0 = min(x0, l.first); x1 = max(x1, l.last) }
        guard bottom > top, x1 > x0 else { return nil }
        let pad = Int(space)
        let left = max(0, x0 - 2 * pad), right = min(w, x1 + 2 * pad)
        let upper = max(0, top - 17 * pad), low = min(h, bottom + 6 * pad)
        return CGRect(x: left, y: upper, width: right - left, height: low - upper)
    }

    static func cropped(_ g: Gray, to r: CGRect) -> Gray {
        let x0 = Int(r.minX), y0 = Int(r.minY), cw = Int(r.width), ch = Int(r.height)
        guard cw > 20, ch > 20 else { return g }
        var out = [UInt8](repeating: 255, count: cw * ch)
        for y in 0..<ch { for x in 0..<cw where y0 + y < g.h && x0 + x < g.w { out[y * cw + x] = g.px[(y0 + y) * g.w + x0 + x] } }
        return Gray(w: cw, h: ch, px: out)
    }

    /// The cleaned page and its size in PDF points.
    static func clean(_ image: CGImage) -> (image: CGImage, size: CGSize)? {
        var g = upright(gray(image, maxSide: 2600))
        // Image rows run top to bottom, so a page tilted anticlockwise needs a clockwise turn back.
        var turn = tilt(binarize(g), w: g.w, h: g.h)
        if abs(turn) < 0.3 { turn = 0 }   // rotating resamples every stroke; not worth it for a hair
        if turn != 0, let src = Self.image(g.px, w: g.w, h: g.h), let r = rotate(src, degrees: turn) { g = gray(r, maxSide: max(g.w, g.h)) }
        g = whiteOutsidePage(flatten(g))
        let inked = binarize(g)
        let space = staffSpace(inked, w: g.w, h: g.h)
        if let space, let crop = pageRegion(inked, w: g.w, h: g.h, space: space) { g = cropped(g, to: crop) }
        let k = space.map { targetSpace / $0 } ?? 900 / CGFloat(g.w)
        // Resample once, to exactly the reader's 2 pixels per point, then keep only ink: after straightening and
        // shrinking, so the edges of the lines stay clean.
        let w = max(1, Int(CGFloat(g.w) * k * 2)), h = max(1, Int(CGFloat(g.h) * k * 2))
        guard let whole = Self.image(g.px, w: g.w, h: g.h) else { return nil }
        let small = gray(whole, maxSide: max(w, h))
        var px = binarize(small).map { $0 ? UInt8(0) : UInt8(255) }
        evenLines(&px, w: small.w, h: small.h)
        guard let out = Self.image(px, w: small.w, h: small.h) else { return nil }
        return (out, CGSize(width: CGFloat(small.w) / 2, height: CGFloat(small.h) / 2))
    }

    /// Staff lines from a photo are ragged: stray specks sit beside a line and are left over when the reader erases it.
    /// Fill each line solid along its length and clear anything hugging it that is only a pixel or two thick.
    static func evenLines(_ px: inout [UInt8], w: Int, h: Int) {
        func run(_ y: Int) -> (Int, Int) {
            var best = (0, -1), start = -1
            for x in 0...w {
                if x < w && px[y * w + x] == 0 { if start < 0 { start = x } }
                else if start >= 0 { if x - start > best.1 - best.0 { best = (start, x - 1) }; start = -1 }
            }
            return best
        }
        let runs = (0..<h).map(run)
        // Rows that are mostly line (a ragged line has partial rows beside its solid ones).
        var band = (0..<h).map { runs[$0].1 - runs[$0].0 > w / 4 }
        for y in 0..<h where band[y] {
            for n in [y - 1, y + 1] where n >= 0 && n < h && !band[n] && (runs[y].0...runs[y].1).filter({ px[n * w + $0] == 0 }).count * 100 > (runs[y].1 - runs[y].0) * 35 {
                for x in runs[y].0...runs[y].1 { px[n * w + x] = 0 }
            }
        }
        let filled = (0..<h).map { run($0) }
        band = filled.map { $0.1 - $0.0 > w / 4 }
        // Specks: a column of ink touching the band that stops within two pixels.
        var y = 0
        while y < h {
            guard band[y] else { y += 1; continue }
            var y1 = y
            while y1 + 1 < h, band[y1 + 1] { y1 += 1 }
            let xs = (y...y1).map { filled[$0] }.filter { $0.1 > $0.0 }
            if let x0 = xs.map(\.0).min(), let x1 = xs.map(\.1).max() {
                for x in x0...x1 {
                    for (start, step) in [(y - 1, -1), (y1 + 1, 1)] {
                        var n = 0, r = start
                        while r >= 0, r < h, px[r * w + x] == 0, n < 4 { n += 1; r += step }
                        if n > 0 && n <= 2 { for i in 0..<n { px[(start + i * step) * w + x] = 255 } }
                    }
                }
            }
            y = y1 + 1
        }
    }

    static func writePDF(_ images: [CGImage], to url: URL) -> Bool {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return false }
        for image in images {
            let size = clean(image) ?? (image, CGSize(width: 900, height: 900 * CGFloat(image.height) / CGFloat(image.width)))
            var page = CGRect(origin: .zero, size: size.size)
            ctx.beginPDFPage([kCGPDFContextMediaBox as String: Data(bytes: &page, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            ctx.interpolationQuality = .none
            ctx.draw(size.image, in: page)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return true
    }
}
