import CoreGraphics
import Foundation

// CD+Graphics (.cdg) karaoke: 24-byte packets, 300 a second, that draw a 300×216 sixteen-colour picture.
// The audio is a separate recording. The picture for any moment is rebuilt by replaying from a nearby checkpoint.

nonisolated final class CDGPlayer: @unchecked Sendable {
    static let width = 300, height = 216, packetsPerSecond = 300.0

    private struct Screen {
        var pixels = [UInt8](repeating: 0, count: CDGPlayer.width * CDGPlayer.height)
        // Until the file loads its own colours: black, then the usual sixteen (some files rely on these).
        var palette: [UInt32] = [0x000000, 0xFFFFFF, 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0x00FFFF, 0xFF00FF,
                                 0x808080, 0x800000, 0x008000, 0x000080, 0x808000, 0x008080, 0x800080, 0xC0C0C0].map { 0xFF000000 | $0 }
        var border = 0
    }

    private let packets: [[UInt8]]
    private var checkpoints: [Screen] = []
    private let every = 600   // packets between checkpoints (two seconds)
    private let lock = NSLock()
    private var current = Screen()
    private var at = 0
    private var last: (frame: Int, image: CGImage)?
    private var lastRendered: CGImage?

    var duration: Double { Double(packets.count) / Self.packetsPerSecond }

    init(data: Data) throws {
        var list: [[UInt8]] = []
        // Some files start with a few stray bytes: begin where packets line up (command byte 9 every 24 bytes).
        let known: Set<UInt8> = [1, 2, 6, 20, 24, 28, 30, 31, 38]
        var best = (offset: 0, score: -1)
        for off in 0..<24 {
            var score = 0, k = data.startIndex + off
            while k + 24 <= data.endIndex, score < 2000 {
                if data[k] & 0x3F == 9, known.contains(data[k + 1] & 0x3F) { score += 1 }
                k += 24
            }
            if score > best.score { best = (off, score) }
        }
        var i = data.startIndex + best.offset
        while i + 24 <= data.endIndex {
            list.append(Array(data[i..<i + 24]))
            i += 24
        }
        guard list.count > 300 else { throw ScoreError.unsupported("This CD+Graphics file is too short or damaged.") }
        packets = list
        var s = Screen()
        for (n, p) in list.enumerated() {
            if n % every == 0 { checkpoints.append(s) }
            Self.apply(p, to: &s)
        }
    }

    /// The picture at `t` seconds.
    func image(at t: Double) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        let target = max(0, min(packets.count, Int(t * Self.packetsPerSecond)))
        // Thirty pictures a second is plenty; the same one is handed back until the next is due.
        if let last, last.frame == target / 10 { return last.image }
        defer { if let image = lastRendered { last = (target / 10, image) } }
        if target < at || target / every != at / every {
            current = checkpoints[min(target / every, checkpoints.count - 1)]
            at = (target / every) * every
        }
        while at < target { Self.apply(packets[at], to: &current); at += 1 }
        lastRendered = Self.render(current)
        return lastRendered
    }

    @_optimize(speed)
    private static func render(_ s: Screen) -> CGImage? {
        let w = width, h = height
        var out = [UInt32](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let border = x < 6 || x >= w - 6 || y < 12 || y >= h - 12
                out[y * w + x] = s.palette[border ? s.border : Int(s.pixels[y * w + x] & 15)]
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes: out, count: out.count * 4) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    @_optimize(speed)
    private static func apply(_ p: [UInt8], to s: inout Screen) {
        guard p[0] & 0x3F == 9 else { return }
        let d = Array(p[4..<20])
        let w = width, h = height
        switch p[1] & 0x3F {
        case 1: s.pixels = [UInt8](repeating: d[0] & 15, count: w * h)
        case 2: s.border = Int(d[0] & 15)
        case 6, 38:
            let c0 = d[0] & 15, c1 = d[1] & 15
            let row = Int(d[2] & 0x1F) * 12, col = Int(d[3] & 0x3F) * 6
            guard row + 12 <= h, col + 6 <= w else { return }
            for r in 0..<12 {
                let bits = d[4 + r]
                for c in 0..<6 {
                    let on = bits >> UInt8(5 - c) & 1 == 1
                    let i = (row + r) * w + col + c
                    if p[1] & 0x3F == 6 { s.pixels[i] = on ? c1 : c0 } else { s.pixels[i] ^= on ? c1 : c0 }
                }
            }
        case 20, 24:
            let fill = d[0] & 15, copy = p[1] & 0x3F == 24
            let dx = [0, 6, -6, 0][Int(d[1] >> 4) & 3], dy = [0, 12, -12, 0][Int(d[2] >> 4) & 3]
            guard dx != 0 || dy != 0 else { return }
            var next = s.pixels
            for y in 0..<h {
                for x in 0..<w {
                    var sx = x - dx, sy = y - dy
                    let inside = sx >= 0 && sx < w && sy >= 0 && sy < h
                    sx = (sx + w) % w; sy = (sy + h) % h
                    next[y * w + x] = copy || inside ? s.pixels[sy * w + sx] : fill
                }
            }
            s.pixels = next
        case 30, 31:
            let base = p[1] & 0x3F == 30 ? 0 : 8
            for i in 0..<8 {
                let v = Int(d[2 * i] & 0x3F) << 6 | Int(d[2 * i + 1] & 0x3F)
                let r = UInt32((v >> 8) & 15) * 17, g = UInt32((v >> 4) & 15) * 17, b = UInt32(v & 15) * 17
                s.palette[base + i] = 0xFF000000 | r << 16 | g << 8 | b
            }
        default: break
        }
    }
}
