// Draws every app icon (light, dark and tinted) and its small in-app preview, and writes the asset catalogs.
// Run from the project folder:  swiftc -O -o /tmp/make-icons Tools/make-icons.swift && /tmp/make-icons
import AppKit
import CoreGraphics
import CoreText
import Foundation

let root = FileManager.default.currentDirectoryPath + "/Play Along/Assets.xcassets"
let fontURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/Play Along/Bravura.otf")
let bravura: CTFont = {
    let d = CTFontManagerCreateFontDescriptorsFromData(try! Data(contentsOf: fontURL) as CFData) as! [CTFontDescriptor]
    return CTFontCreateWithFontDescriptor(d[0], 600, nil)
}()

enum Look { case light, dark }

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
func hex(_ v: UInt32, _ a: Double = 1) -> CGColor { rgb(Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255, a) }
func shade(_ c: CGColor, _ f: Double) -> CGColor {
    let k = c.components!; return rgb(min(1, k[0] * f), min(1, k[1] * f), min(1, k[2] * f), c.alpha)
}
func gradient(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locs)!
}

struct Canvas {
    let ctx: CGContext
    let look: Look
    var dark: Bool { look == .dark }
    func pick(_ light: CGColor, _ darkColor: CGColor) -> CGColor { dark ? darkColor : light }

    func linear(_ g: CGGradient, from: CGPoint, to: CGPoint) { ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]) }
    func radial(_ g: CGGradient, at c: CGPoint, r: CGFloat) { ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [.drawsAfterEndLocation]) }
    func background(_ top: CGColor, _ bottom: CGColor, glow: CGColor? = nil) {
        linear(gradient([top, bottom]), from: CGPoint(x: 0, y: 1024), to: CGPoint(x: 0, y: 0))
        if let glow { radial(gradient([glow, glow.copy(alpha: 0)!]), at: CGPoint(x: 512, y: 560), r: 620) }
    }
    func shadowed(_ blur: CGFloat = 24, dy: CGFloat = -14, alpha: Double = 0.5, _ body: () -> Void) {
        ctx.saveGState(); ctx.setShadow(offset: CGSize(width: 0, height: dy), blur: blur, color: rgb(0, 0, 0, alpha)); body(); ctx.restoreGState()
    }
    func fill(_ path: CGPath, _ g: CGGradient, from: CGPoint, to: CGPoint) {
        ctx.saveGState(); ctx.addPath(path); ctx.clip(); linear(g, from: from, to: to); ctx.restoreGState()
    }
    func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }
    /// A thick line along a path, filled with a gradient across its width.
    func tube(_ path: CGPath, width: CGFloat, _ g: CGGradient, across: (CGPoint, CGPoint)) {
        ctx.saveGState()
        ctx.addPath(path); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.replacePathWithStrokedPath(); ctx.clip()
        linear(g, from: across.0, to: across.1)
        ctx.restoreGState()
    }
    func clef(center: CGPoint, height: CGFloat, color: CGColor) {
        var glyph = CTFontGetGlyphWithName(bravura, "gClef" as CFString)
        if glyph == 0 { var ch: UniChar = 0xE050; CTFontGetGlyphsForCharacters(bravura, &ch, &glyph, 1) }
        guard let p = CTFontCreatePathForGlyph(bravura, glyph, nil) else { return }
        let b = p.boundingBoxOfPath, s = height / b.height
        var t = CGAffineTransform(translationX: center.x - b.midX * s, y: center.y - b.midY * s).scaledBy(x: s, y: s)
        let path = p.copy(using: &t)!
        shadowed(18, dy: -8, alpha: 0.5) { ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath() }
    }
    func staff(y: CGFloat, spacing: CGFloat, from x0: CGFloat, to x1: CGFloat, color: CGColor, width: CGFloat = 7) {
        for i in 0..<5 { ctx.setFillColor(color); ctx.fill(CGRect(x: x0, y: y + CGFloat(i - 2) * spacing - width / 2, width: x1 - x0, height: width)) }
    }
}

struct Theme {
    let id: String, name: String, group: String
    let draw: (Canvas) -> Void
}

// MARK: Classic themes

func classicClef(_ c: Canvas, mark: CGColor, lines: CGColor) {
    c.staff(y: 512, spacing: 70, from: 110, to: 914, color: lines)
    c.clef(center: CGPoint(x: 350, y: 512), height: 430, color: mark)
    c.shadowed(10, dy: -6, alpha: 0.4) { c.ctx.setFillColor(mark); c.ctx.fill(CGRect(x: 690, y: 512 - 140 - 3, width: 14, height: 286)) }
}

let themes: [Theme] = [
    Theme(id: "Leather", name: "Leather", group: "Classic") { c in
        c.background(c.pick(hex(0xF1E6D0), hex(0x2B1E15)), c.pick(hex(0xD6C3A0), hex(0x0E0905)), glow: c.pick(hex(0xFFF6E0, 0.7), hex(0x8A5A22, 0.55)))
        classicClef(c, mark: c.pick(hex(0x4A2C12), hex(0xE9B960)), lines: c.pick(hex(0x4A2C12, 0.35), hex(0xE9B960, 0.3)))
    },
    Theme(id: "Paper", name: "Paper", group: "Classic") { c in
        c.background(c.pick(hex(0xFCF8EE), hex(0x2A2A2C)), c.pick(hex(0xE9E0CB), hex(0x111112)))
        classicClef(c, mark: c.pick(hex(0x1B1B1D), hex(0xF1EBDD)), lines: c.pick(hex(0x1B1B1D, 0.5), hex(0xF1EBDD, 0.4)))
    },
    Theme(id: "Midnight", name: "Midnight", group: "Classic") { c in
        c.background(c.pick(hex(0x24407E), hex(0x0E1A38)), c.pick(hex(0x0B1636), hex(0x03060F)), glow: c.pick(hex(0x6C8FE0, 0.5), hex(0x2D4B96, 0.5)))
        classicClef(c, mark: c.pick(hex(0xEDF1FA), hex(0xC8D4F0)), lines: hex(0xEDF1FA, 0.3))
    },
    Theme(id: "Brass", name: "Brass", group: "Classic") { c in
        c.background(c.pick(hex(0xF3CE7B), hex(0x8A6620)), c.pick(hex(0xA9771F), hex(0x3D2A08)), glow: c.pick(hex(0xFFF1C4, 0.8), hex(0xD8A640, 0.4)))
        classicClef(c, mark: c.pick(hex(0x1D1405), hex(0x140E03)), lines: hex(0x1D1405, 0.35))
    },
    Theme(id: "Sunset", name: "Sunset", group: "Classic") { c in
        c.background(c.pick(hex(0xFF9A56), hex(0x7A2E58)), c.pick(hex(0x8E3F9C), hex(0x1D0F3A)), glow: c.pick(hex(0xFFD07A, 0.7), hex(0xE0663A, 0.45)))
        classicClef(c, mark: c.pick(hex(0xFFF4E2), hex(0xFFD9A8)), lines: hex(0xFFF4E2, 0.4))
    },
    Theme(id: "Forest", name: "Forest", group: "Classic") { c in
        c.background(c.pick(hex(0x4FA37A), hex(0x103A2A)), c.pick(hex(0x1D5C44), hex(0x04130D)), glow: c.pick(hex(0xBDEBC9, 0.6), hex(0x2E8F66, 0.45)))
        classicClef(c, mark: c.pick(hex(0xF1FAEC), hex(0xC6EBCB)), lines: hex(0xF1FAEC, 0.35))
    },
]

// MARK: Flags and Pride

func stripes(_ c: Canvas, _ colors: [UInt32]) {
    let h = 1024.0 / Double(colors.count)
    for (i, v) in colors.enumerated() {
        let base = hex(v)
        c.ctx.setFillColor(c.dark ? shade(base, 0.5) : base)
        c.ctx.fill(CGRect(x: 0, y: 1024 - Double(i + 1) * h, width: 1024, height: h + 1))
    }
    c.radial(gradient([rgb(1, 1, 1, c.dark ? 0.08 : 0.2), rgb(1, 1, 1, 0)]), at: CGPoint(x: 512, y: 760), r: 600)
}

func whiteClef(_ c: Canvas) {
    c.clef(center: CGPoint(x: 512, y: 512), height: 560, color: c.pick(hex(0xFFFFFF), hex(0xEDEDED)))
}

func unionFlag(_ c: Canvas) {
    let ctx = c.ctx
    ctx.saveGState()
    // The 60 by 30 flag drawn at 1024 tall, then the middle square shown.
    let s = 1024.0 / 30.0
    ctx.translateBy(x: -(60 * s - 1024) / 2, y: 0)
    ctx.scaleBy(x: s, y: s)
    func y(_ v: Double) -> Double { 30 - v }   // the flag is drawn top-down
    let dim = c.dark ? 0.55 : 1.0
    ctx.setFillColor(shade(hex(0x012169), dim)); ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 30))
    func line(_ a: (Double, Double), _ b: (Double, Double), _ w: Double, _ color: CGColor) {
        ctx.setStrokeColor(color); ctx.setLineWidth(w); ctx.move(to: CGPoint(x: a.0, y: y(a.1))); ctx.addLine(to: CGPoint(x: b.0, y: y(b.1))); ctx.strokePath()
    }
    let white = shade(hex(0xFFFFFF), dim), red = shade(hex(0xC8102E), dim)
    line((0, 0), (60, 30), 6, white); line((60, 0), (0, 30), 6, white)
    ctx.saveGState()
    // The red diagonals are cut into four triangles so each sits to one side of the white.
    let t = CGMutablePath()
    for p in [[(30.0, 15.0), (60, 15), (60, 30)], [(30, 15), (30, 30), (0, 30)], [(30, 15), (0, 15), (0, 0)], [(30, 15), (30, 0), (60, 0)]] {
        t.move(to: CGPoint(x: p[0].0, y: y(p[0].1))); t.addLine(to: CGPoint(x: p[1].0, y: y(p[1].1))); t.addLine(to: CGPoint(x: p[2].0, y: y(p[2].1))); t.closeSubpath()
    }
    ctx.addPath(t); ctx.clip()
    line((0, 0), (60, 30), 4, red); line((60, 0), (0, 30), 4, red)
    ctx.restoreGState()
    line((30, 0), (30, 30), 10, white); line((0, 15), (60, 15), 10, white)
    line((30, 0), (30, 30), 6, red); line((0, 15), (60, 15), 6, red)
    ctx.restoreGState()
    c.radial(gradient([rgb(1, 1, 1, c.dark ? 0.05 : 0.16), rgb(1, 1, 1, 0)]), at: CGPoint(x: 512, y: 780), r: 560)
    // A plate behind the clef so it reads over the crosses.
    c.shadowed(30, dy: -16, alpha: 0.55) {
        ctx.setFillColor(c.pick(hex(0xFBF7EC), hex(0x2A2A30)))
        ctx.addPath(c.rounded(CGRect(x: 292, y: 232, width: 440, height: 560), 120)); ctx.fillPath()
    }
    c.clef(center: CGPoint(x: 512, y: 512), height: 430, color: c.pick(hex(0x012169), hex(0xEDEFF7)))
}

let flagThemes: [Theme] = [
    Theme(id: "UnionFlag", name: "Union Flag", group: "Flags and Pride") { unionFlag($0) },
    Theme(id: "Pride", name: "Pride", group: "Flags and Pride") { c in
        stripes(c, [0xE40303, 0xFF8C00, 0xFFED00, 0x008026, 0x004DFF, 0x750787]); whiteClef(c)
    },
    Theme(id: "TransPride", name: "Trans Pride", group: "Flags and Pride") { c in
        stripes(c, [0x5BCEFA, 0xF5A9B8, 0xFFFFFF, 0xF5A9B8, 0x5BCEFA]); c.clef(center: CGPoint(x: 512, y: 512), height: 560, color: c.pick(hex(0x2B2B33), hex(0xEDEDED)))
    },
]

// MARK: Instruments

func instrumentBackground(_ c: Canvas, _ top: UInt32, _ bottom: UInt32, glow: UInt32) {
    c.background(c.pick(hex(top), shade(hex(top), 0.4)), c.pick(hex(bottom), shade(hex(bottom), 0.35)), glow: c.pick(hex(glow, 0.55), hex(glow, 0.25)))
}
func metal(_ c: Canvas, base: UInt32) -> CGGradient {
    let b = hex(base), k = c.dark ? 0.9 : 1.0
    return gradient([shade(b, 0.55 * k), shade(b, 1.35 * k), shade(b, 1.0 * k), shade(b, 0.5 * k)], [0, 0.3, 0.62, 1])
}

func piano(_ c: Canvas) {
    instrumentBackground(c, 0x3B3B42, 0x121216, glow: 0x9A8CC8)
    let ctx = c.ctx
    // White keys in perspective-free front view, black keys above.
    let keys = 5, w = 170.0, x0 = (1024 - w * Double(keys)) / 2, top = 250.0, bottom = 800.0
    c.shadowed(30, dy: -18, alpha: 0.6) {
        ctx.setFillColor(hex(0x0B0B0D)); ctx.addPath(c.rounded(CGRect(x: x0 - 30, y: top - 30, width: w * Double(keys) + 60, height: bottom - top + 60), 36)); ctx.fillPath()
    }
    for i in 0..<keys {
        let r = CGRect(x: x0 + Double(i) * w + 4, y: top, width: w - 8, height: bottom - top)
        c.fill(c.rounded(r, 22), gradient([c.pick(hex(0xFFFFFF), hex(0xEDEDF0)), c.pick(hex(0xD9D6CE), hex(0xA8A6A2))]), from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY))
    }
    for i in [0, 1, 3] {
        let r = CGRect(x: x0 + Double(i + 1) * w - 52, y: top + 190, width: 104, height: 360)
        c.shadowed(14, dy: -10, alpha: 0.6) { c.fill(c.rounded(r, 16), gradient([hex(0x4A4A52), hex(0x08080A)]), from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY)) }
    }
}

func organ(_ c: Canvas) {
    instrumentBackground(c, 0x6B4A2B, 0x24150A, glow: 0xD9A15A)
    let heights = [330.0, 440, 560, 660, 560, 440, 330], w = 96.0, gap = 24.0
    let total = Double(heights.count) * (w + gap) - gap, x0 = (1024 - total) / 2
    for (i, h) in heights.enumerated() {
        let x = x0 + Double(i) * (w + gap), r = CGRect(x: x, y: 190, width: w, height: h)
        c.shadowed(16, dy: -10, alpha: 0.5) { c.fill(c.rounded(r, 26), metal(c, base: 0xD7D9DE), from: CGPoint(x: r.minX, y: 0), to: CGPoint(x: r.maxX, y: 0)) }
        // The mouth and the foot.
        c.ctx.setFillColor(rgb(0, 0, 0, 0.55)); c.ctx.addPath(c.rounded(CGRect(x: x + 16, y: 190 + h * 0.22, width: w - 32, height: 34), 8)); c.ctx.fillPath()
        c.ctx.setFillColor(rgb(0, 0, 0, 0.35)); c.ctx.fill(CGRect(x: x + 6, y: 190 + h - 12, width: w - 12, height: 6))
    }
}

/// A guitar standing upright, centred, then turned.
func guitar(_ c: Canvas, bass: Bool) {
    if bass { instrumentBackground(c, 0x52211F, 0x1A0A0A, glow: 0xE0584D) } else { instrumentBackground(c, 0x2F5A63, 0x0B1E22, glow: 0x6FC2CF) }
    let ctx = c.ctx
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512); ctx.rotate(by: .pi / 7); ctx.translateBy(x: -512, y: -512)
    let body: CGColor = bass ? hex(0x1B1B1F) : hex(0xC9803A), wood = c.pick(body, shade(body, 0.8))
    let neckLen = bass ? 470.0 : 380.0
    // Neck and headstock.
    let neckW = bass ? 78.0 : 88.0
    let neck = CGRect(x: 512 - neckW / 2, y: 560, width: neckW, height: neckLen)
    c.shadowed(14, dy: -8, alpha: 0.5) {
        ctx.setFillColor(hex(0x3A2412)); ctx.addPath(c.rounded(neck, 14)); ctx.fillPath()
        ctx.setFillColor(hex(0x2A1809)); ctx.addPath(c.rounded(CGRect(x: 512 - neckW / 2 - 12, y: 560 + neckLen - 4, width: neckW + 24, height: 130), 26)); ctx.fillPath()
    }
    for i in 0..<(bass ? 4 : 6) {   // tuning pegs
        let side = i % 2 == 0 ? -1.0 : 1.0, row = Double(i / 2)
        ctx.setFillColor(hex(0xD8D8DC)); ctx.fillEllipse(in: CGRect(x: 512 + side * (neckW / 2 + 22) - 12, y: 560 + neckLen + 18 + row * 38, width: 24, height: 24))
    }
    // The body: two bouts and a waist.
    let upper = CGRect(x: 512 - 150, y: 470, width: 300, height: 300), lower = CGRect(x: 512 - (bass ? 190 : 220), y: 130, width: bass ? 380 : 440, height: bass ? 400 : 460)
    let path = CGMutablePath()
    path.addEllipse(in: upper); path.addEllipse(in: lower); path.addRect(CGRect(x: 512 - 120, y: 360, width: 240, height: 200))
    c.shadowed(30, dy: -18, alpha: 0.6) {
        ctx.addPath(path); ctx.setFillColor(wood); ctx.fillPath(using: .winding)
    }
    ctx.saveGState(); ctx.addPath(path); ctx.clip(using: .winding)
    c.radial(gradient([rgb(1, 1, 1, 0.28), rgb(1, 1, 1, 0)]), at: CGPoint(x: 440, y: 480), r: 420)
    c.linear(gradient([rgb(0, 0, 0, 0), rgb(0, 0, 0, 0.45)]), from: CGPoint(x: 512, y: 480), to: CGPoint(x: 512, y: 100))
    ctx.restoreGState()
    if bass {   // pickguard and pickups
        ctx.setFillColor(rgb(1, 1, 1, 0.85)); ctx.addPath(c.rounded(CGRect(x: 420, y: 250, width: 190, height: 120), 40)); ctx.fillPath()
        ctx.setFillColor(hex(0x0E0E10)); ctx.fill(CGRect(x: 440, y: 330, width: 140, height: 26)); ctx.fill(CGRect(x: 440, y: 284, width: 140, height: 26))
    } else {    // sound hole and rosette
        ctx.setFillColor(rgb(0, 0, 0, 0.85)); ctx.fillEllipse(in: CGRect(x: 512 - 72, y: 310, width: 144, height: 144))
        ctx.setStrokeColor(hex(0xF1D9A8)); ctx.setLineWidth(10); ctx.strokeEllipse(in: CGRect(x: 512 - 82, y: 300, width: 164, height: 164))
    }
    // Strings and bridge.
    let n = bass ? 4 : 6
    ctx.setStrokeColor(rgb(1, 1, 1, 0.8)); ctx.setLineWidth(bass ? 5 : 3)
    for i in 0..<n {
        let x = 512 - neckW / 2 + 12 + (neckW - 24) * Double(i) / Double(n - 1)
        ctx.move(to: CGPoint(x: x, y: 190)); ctx.addLine(to: CGPoint(x: x, y: 560 + neckLen)); ctx.strokePath()
    }
    ctx.setFillColor(hex(0x1C120A)); ctx.addPath(c.rounded(CGRect(x: 512 - 80, y: 178, width: 160, height: 24), 8)); ctx.fillPath()
    ctx.restoreGState()
}

func flute(_ c: Canvas) {
    instrumentBackground(c, 0x3F6AA8, 0x0F2142, glow: 0x9CC4F2)
    let ctx = c.ctx
    ctx.saveGState(); ctx.translateBy(x: 512, y: 512); ctx.rotate(by: .pi / 4); ctx.translateBy(x: -512, y: -512)
    let r = CGRect(x: 120, y: 512 - 46, width: 784, height: 92)
    c.shadowed(24, dy: -16, alpha: 0.55) { c.fill(c.rounded(r, 46), metal(c, base: 0xDFE3EA), from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY)) }
    // The embouchure hole, the keys, and the joints.
    ctx.setFillColor(rgb(0, 0, 0, 0.55)); ctx.fillEllipse(in: CGRect(x: 220, y: 512 - 18, width: 70, height: 36))
    for i in 0..<6 {
        let x = 400.0 + Double(i) * 78
        c.shadowed(8, dy: -5, alpha: 0.5) { c.fill(CGPath(ellipseIn: CGRect(x: x, y: 512 - 30, width: 60, height: 60), transform: nil), metal(c, base: 0xF2F4F8), from: CGPoint(x: x, y: 560), to: CGPoint(x: x + 60, y: 470)) }
    }
    for x in [330.0, 700.0] { ctx.setFillColor(rgb(0, 0, 0, 0.3)); ctx.fill(CGRect(x: x, y: 512 - 46, width: 10, height: 92)) }
    ctx.restoreGState()
}

func clarinet(_ c: Canvas) {
    instrumentBackground(c, 0x5B3A78, 0x1A0F26, glow: 0xB58AE0)
    let ctx = c.ctx
    ctx.saveGState(); ctx.translateBy(x: 512, y: 512); ctx.rotate(by: -.pi / 9); ctx.translateBy(x: -512, y: -512)
    let black = c.pick(hex(0x1A1A1E), hex(0x232328))
    // Bell, body, barrel and mouthpiece.
    let bell = CGMutablePath(); bell.move(to: CGPoint(x: 470, y: 170)); bell.addQuadCurve(to: CGPoint(x: 400, y: 120), control: CGPoint(x: 460, y: 130)); bell.addLine(to: CGPoint(x: 624, y: 120)); bell.addQuadCurve(to: CGPoint(x: 554, y: 170), control: CGPoint(x: 564, y: 130)); bell.addLine(to: CGPoint(x: 554, y: 300)); bell.addLine(to: CGPoint(x: 470, y: 300)); bell.closeSubpath()
    c.shadowed(24, dy: -14, alpha: 0.55) {
        ctx.setFillColor(black); ctx.addPath(bell); ctx.fillPath()
        ctx.addPath(c.rounded(CGRect(x: 476, y: 290, width: 72, height: 560), 20)); ctx.fillPath()
        ctx.addPath(c.rounded(CGRect(x: 484, y: 840, width: 56, height: 70), 16)); ctx.fillPath()
    }
    let mouth = CGMutablePath(); mouth.move(to: CGPoint(x: 490, y: 900)); mouth.addLine(to: CGPoint(x: 534, y: 900)); mouth.addLine(to: CGPoint(x: 522, y: 990)); mouth.addLine(to: CGPoint(x: 502, y: 990)); mouth.closeSubpath()
    ctx.setFillColor(hex(0x0C0C0E)); ctx.addPath(mouth); ctx.fillPath()
    // Highlight along the wood, silver rings and keys.
    ctx.setFillColor(rgb(1, 1, 1, 0.14)); ctx.fill(CGRect(x: 492, y: 300, width: 12, height: 540))
    for y in [288.0, 520, 700, 838] { c.fill(c.rounded(CGRect(x: 468, y: y, width: 88, height: 22), 8), metal(c, base: 0xE6E8EE), from: CGPoint(x: 468, y: 0), to: CGPoint(x: 556, y: 0)) }
    for (i, y) in [350.0, 420, 570, 630, 760].enumerated() {
        let x = i % 2 == 0 ? 440.0 : 530.0
        c.shadowed(6, dy: -4, alpha: 0.5) { c.fill(CGPath(ellipseIn: CGRect(x: x, y: y, width: 54, height: 54), transform: nil), metal(c, base: 0xE9EBF0), from: CGPoint(x: x, y: y + 54), to: CGPoint(x: x + 54, y: y)) }
    }
    ctx.restoreGState()
}

func sax(_ c: Canvas, alto: Bool) {
    if alto { instrumentBackground(c, 0x7A2B2B, 0x230909, glow: 0xF08A6A) } else { instrumentBackground(c, 0x2F4A2F, 0x0C170C, glow: 0x9CD18A) }
    let ctx = c.ctx, base: UInt32 = alto ? 0xF2C14E : 0xC98A3C
    let scale = alto ? 1.0 : 1.12
    ctx.saveGState(); ctx.translateBy(x: 512, y: 512); ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: -512, y: -512)
    // The body: from the neck down the tube and round the bow, to the bell.
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 400, y: 905))
    p.addCurve(to: CGPoint(x: 520, y: 860), control1: CGPoint(x: 450, y: 930), control2: CGPoint(x: 500, y: 910))
    p.addCurve(to: CGPoint(x: 500, y: 330), control1: CGPoint(x: 560, y: 760), control2: CGPoint(x: 540, y: 520))
    p.addCurve(to: CGPoint(x: 700, y: 210), control1: CGPoint(x: 480, y: 220), control2: CGPoint(x: 620, y: 170))
    c.shadowed(26, dy: -16, alpha: 0.55) { c.tube(p, width: 108, metal(c, base: base), across: (CGPoint(x: 440, y: 0), CGPoint(x: 640, y: 0))) }
    // The bell flares up and to the right.
    let bell = CGMutablePath()
    bell.move(to: CGPoint(x: 646, y: 232)); bell.addCurve(to: CGPoint(x: 790, y: 410), control1: CGPoint(x: 740, y: 250), control2: CGPoint(x: 780, y: 330)); bell.addLine(to: CGPoint(x: 882, y: 470)); bell.addCurve(to: CGPoint(x: 700, y: 180), control1: CGPoint(x: 900, y: 300), control2: CGPoint(x: 830, y: 190)); bell.closeSubpath()
    c.shadowed(20, dy: -12, alpha: 0.5) { c.fill(bell, metal(c, base: base), from: CGPoint(x: 650, y: 200), to: CGPoint(x: 880, y: 470)) }
    ctx.setFillColor(rgb(0, 0, 0, 0.55)); ctx.fillEllipse(in: CGRect(x: 780, y: 396, width: 120, height: 84))
    // Neck, mouthpiece and keys.
    ctx.setFillColor(hex(0x16110C)); ctx.addPath(c.rounded(CGRect(x: 300, y: 888, width: 120, height: 36), 16)); ctx.fillPath()
    c.fill(c.rounded(CGRect(x: 396, y: 884, width: 40, height: 44), 12), metal(c, base: 0xDADCE2), from: CGPoint(x: 396, y: 0), to: CGPoint(x: 436, y: 0))
    for (i, y) in [800.0, 700, 600, 500, 400].enumerated() {
        let x = i % 2 == 0 ? 440.0 : 540.0
        c.shadowed(6, dy: -4, alpha: 0.5) { c.fill(CGPath(ellipseIn: CGRect(x: x, y: y, width: 56, height: 56), transform: nil), metal(c, base: 0xF4E3B0), from: CGPoint(x: x, y: y + 56), to: CGPoint(x: x + 56, y: y)) }
    }
    ctx.restoreGState()
}

func trumpet(_ c: Canvas) {
    instrumentBackground(c, 0x8A5A12, 0x2B1A04, glow: 0xFFD27A)
    let ctx = c.ctx, gold = 0xF0BD3F
    let g = metal(c, base: UInt32(gold))
    func tube(_ path: CGPath, _ w: CGFloat) { c.shadowed(18, dy: -12, alpha: 0.5) { c.tube(path, width: w, g, across: (CGPoint(x: 0, y: 700), CGPoint(x: 0, y: 300))) } }
    // The big loop under the valves, and the lead pipe back to the mouthpiece.
    let loop = CGMutablePath(); loop.move(to: CGPoint(x: 330, y: 560)); loop.addLine(to: CGPoint(x: 250, y: 560)); loop.addCurve(to: CGPoint(x: 250, y: 330), control1: CGPoint(x: 120, y: 560), control2: CGPoint(x: 120, y: 330)); loop.addLine(to: CGPoint(x: 640, y: 330))
    tube(loop, 44)
    let lead = CGMutablePath(); lead.move(to: CGPoint(x: 150, y: 640)); lead.addLine(to: CGPoint(x: 640, y: 640)); tube(lead, 40)
    // The bell.
    let bell = CGMutablePath(); bell.move(to: CGPoint(x: 600, y: 610)); bell.addLine(to: CGPoint(x: 700, y: 610)); bell.addCurve(to: CGPoint(x: 900, y: 790), control1: CGPoint(x: 800, y: 610), control2: CGPoint(x: 860, y: 700)); bell.addLine(to: CGPoint(x: 900, y: 180)); bell.addCurve(to: CGPoint(x: 700, y: 360), control1: CGPoint(x: 860, y: 270), control2: CGPoint(x: 800, y: 360)); bell.addLine(to: CGPoint(x: 600, y: 360)); bell.closeSubpath()
    c.shadowed(22, dy: -14, alpha: 0.5) { c.fill(bell, g, from: CGPoint(x: 0, y: 800), to: CGPoint(x: 0, y: 180)) }
    ctx.setFillColor(rgb(0, 0, 0, 0.45)); ctx.fillEllipse(in: CGRect(x: 870, y: 360, width: 60, height: 260))
    // The mouthpiece, and the three valves with their buttons.
    c.fill(c.rounded(CGRect(x: 100, y: 612, width: 70, height: 56), 16), metal(c, base: 0xDADCE2), from: CGPoint(x: 0, y: 668), to: CGPoint(x: 0, y: 612))
    for i in 0..<3 {
        let x = 360.0 + Double(i) * 84
        c.shadowed(10, dy: -8, alpha: 0.5) { c.fill(c.rounded(CGRect(x: x, y: 300, width: 56, height: 400), 14), g, from: CGPoint(x: x, y: 0), to: CGPoint(x: x + 56, y: 0)) }
        ctx.setFillColor(hex(0x2A1A04)); ctx.fill(CGRect(x: x + 26, y: 700, width: 4, height: 60))
        c.shadowed(8, dy: -5, alpha: 0.5) { c.fill(CGPath(ellipseIn: CGRect(x: x + 2, y: 748, width: 52, height: 52), transform: nil), metal(c, base: 0xF4F0E6), from: CGPoint(x: x, y: 800), to: CGPoint(x: x + 56, y: 748)) }
    }
}

let instrumentThemes: [Theme] = [
    Theme(id: "Piano", name: "Piano", group: "Instruments", draw: piano),
    Theme(id: "Organ", name: "Organ", group: "Instruments", draw: organ),
    Theme(id: "Guitar", name: "Acoustic Guitar", group: "Instruments") { guitar($0, bass: false) },
    Theme(id: "Bass", name: "Bass", group: "Instruments") { guitar($0, bass: true) },
    Theme(id: "Flute", name: "Flute", group: "Instruments", draw: flute),
    Theme(id: "Clarinet", name: "Clarinet", group: "Instruments", draw: clarinet),
    Theme(id: "AltoSax", name: "Alto Saxophone", group: "Instruments") { sax($0, alto: true) },
    Theme(id: "TenorSax", name: "Tenor Saxophone", group: "Instruments") { sax($0, alto: false) },
    Theme(id: "Trumpet", name: "Trumpet", group: "Instruments", draw: trumpet),
]

// MARK: Output

func render(_ theme: Theme, _ look: Look, size: Int = 1024, tinted: Bool = false) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setShouldAntialias(true)
    theme.draw(Canvas(ctx: ctx, look: look))
    var image = ctx.makeImage()!
    if tinted {
        // The tinted variant is grey: the system colours it. Lifted a little so the mark stays bright against the dark ground.
        let g = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        g.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let gray = g.makeImage()!
        let out = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        out.draw(gray, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        image = out.makeImage()!
    }
    if size == 1024 { return image }
    let small = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    small.interpolationQuality = .high
    small.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return small.makeImage()!
}

func png(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let fm = FileManager.default
var manifest: [[String: String]] = []
for theme in themes + flagThemes + instrumentThemes {
    let isDefault = theme.id == "Leather"
    let setName = isDefault ? "AppIcon" : "Icon-" + theme.id
    let dir = URL(fileURLWithPath: root + "/" + setName + ".appiconset")
    try? fm.removeItem(at: dir)
    try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
    png(render(theme, .light), to: dir.appending(path: "light.png"))
    png(render(theme, .dark), to: dir.appending(path: "dark.png"))
    png(render(theme, .dark, tinted: true), to: dir.appending(path: "tinted.png"))
    let contents = """
    {
      "images" : [
        { "filename" : "light.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
        { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
        { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
    try! contents.write(to: dir.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
    // A small picture for the chooser in Settings (app icon sets can't be read back as images).
    let previewDir = URL(fileURLWithPath: root + "/IconPreview-" + theme.id + ".imageset")
    try? fm.removeItem(at: previewDir)
    try! fm.createDirectory(at: previewDir, withIntermediateDirectories: true)
    png(render(theme, .light, size: 240), to: previewDir.appending(path: "preview.png"))
    try! """
    { "images" : [ { "filename" : "preview.png", "idiom" : "universal", "scale" : "1x" } ], "info" : { "author" : "xcode", "version" : 1 } }
    """.write(to: previewDir.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
    manifest.append(["id": theme.id, "name": theme.name, "group": theme.group, "set": isDefault ? "" : setName])
    print("drew", theme.name)
}
