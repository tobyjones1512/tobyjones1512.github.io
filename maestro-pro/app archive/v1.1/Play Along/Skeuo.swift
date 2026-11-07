import SwiftUI

// The look of the app: real materials, not flat colour. A dark leather desk, paper with fibre, brushed-metal plates, hardware keys
// that press in, and a recessed display with unlit segments showing through. Everything is drawn here, from procedural textures,
// so there are no image files to ship, and it all steps aside in High Contrast.

// MARK: - Textures

/// Noise tiles drawn once by hand into a grey bitmap, centred on mid-grey so an overlay blend lightens and darkens evenly:
/// fine grain, brushed streaks and pebbled leather. Seeded, so the surface looks the same every launch.
enum Texture {
    enum Kind: String { case grain, brushed, leather }

    private static let cache = NSCache<NSString, CGImage>()

    static func image(_ kind: Kind) -> Image {
        if let cached = cache.object(forKey: kind.rawValue as NSString) { return Image(decorative: cached, scale: 1) }
        guard let made = make(kind) else { return Image(systemName: "square") }
        cache.setObject(made, forKey: kind.rawValue as NSString)
        return Image(decorative: made, scale: 1)
    }

    private struct Rng {
        var state: UInt64
        mutating func next() -> Double {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
    }

    private static func make(_ kind: Kind) -> CGImage? {
        let n = 256
        var rng = Rng(state: 0xC0FFEE)
        var px = [Double](repeating: 0.5, count: n * n)
        switch kind {
        case .grain:
            for i in px.indices { px[i] = 0.5 + (rng.next() + rng.next() + rng.next() - 1.5) * 0.45 }
        case .brushed:
            // Each row is its own streak: noise smeared along the row, wrapping so the tile joins up.
            for y in 0..<n {
                let row = (0..<n).map { _ in rng.next() - 0.5 }
                let window = 30
                var sum = (0..<window).reduce(0.0) { $0 + row[$1] }
                for x in 0..<n {
                    px[y * n + x] = 0.5 + sum / Double(window) * 1.5 + (rng.next() - 0.5) * 0.05
                    sum += row[(x + window) % n] - row[x]
                }
            }
        case .leather:
            // Pebbles: many small round dimples with a lit rim, laid down at random (wrapping at the edges).
            for _ in 0..<4200 {
                let cx = Int(rng.next() * Double(n)), cy = Int(rng.next() * Double(n)), r = 1.5 + rng.next() * 1.7, depth = 0.5 + rng.next() * 0.5
                for dy in -6...6 { for dx in -6...6 {
                    let d = (Double(dx * dx + dy * dy)).squareRoot()
                    guard d < r + 1.5 else { continue }
                    // Dark in the dimple, a little light at its rim.
                    let v = d < r ? -(1 - d / r) * 0.3 * depth : (1 - (d - r) / 1.5) * 0.07
                    let i = ((cy + dy + n) % n) * n + (cx + dx + n) % n
                    px[i] += v
                } }
            }
            for i in px.indices { px[i] += (rng.next() - 0.5) * 0.08 }
        }
        // Relief as transparency: light where the noise is above grey, dark where it is below, clear at grey. It then lies on any
        // surface with an ordinary blend, with no need for the surface to be mid-grey.
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for i in px.indices {
            let d = max(-1, min(1, (px[i] - 0.5) * 2)), a = abs(d), light = d > 0
            let v = UInt8(a * 255), c = light ? v : 0
            bytes[i * 4] = c; bytes[i * 4 + 1] = c; bytes[i * 4 + 2] = c; bytes[i * 4 + 3] = v   // premultiplied
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Which material a texture belongs to, so Settings can turn each up or down on its own.
enum SurfaceRole: String, CaseIterable, Identifiable {
    case paper, desk, leather, metal
    var id: String { rawValue }
    var title: String {
        switch self { case .paper: "Paper Grain"; case .desk: "Desk Leather"; case .leather: "Leather Buttons"; case .metal: "Brushed Metal" }
    }
}

/// The surface settings, in one place: a master switch, a strength for each material, and how much shadow and curl the page has.
enum Surfaces {
    static let masterKey = "surface.master", shadeKey = "surface.shade"
    nonisolated static func key(_ role: SurfaceRole) -> String { "surface." + role.rawValue }
    static let all = [masterKey, shadeKey] + SurfaceRole.allCases.map(key)
}

/// A texture laid over a surface, tiled, at the strength Settings gives its material. Off in High Contrast.
struct Grain: View {
    let kind: Texture.Kind
    var opacity = 0.25
    var role: SurfaceRole = .metal
    var blend: BlendMode = .normal
    @AppStorage(Surfaces.masterKey) private var master = true
    @AppStorage("surface.paper") private var paper = 1.0
    @AppStorage("surface.desk") private var desk = 1.0
    @AppStorage("surface.leather") private var leather = 1.0
    @AppStorage("surface.metal") private var metal = 1.0

    private var strength: Double {
        guard master else { return 0 }
        switch role { case .paper: return paper; case .desk: return desk; case .leather: return leather; case .metal: return metal }
    }

    var body: some View {
        if !Palette.shared.highContrast, strength > 0.001 {
            Texture.image(kind)
                .resizable(resizingMode: .tile)
                .opacity(min(1, opacity * strength))
                .blendMode(blend)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - The desk

/// The stage: leather in whatever colour the style chose, lit from above, darker at the corners.
struct StageBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        #if targetEnvironment(macCatalyst)
        Color(.systemBackground).ignoresSafeArea()
        #else
        let dark = scheme == .dark
        ZStack {
            Theme.stage
            Grain(kind: .leather, opacity: dark ? 0.4 : 0.07, role: .desk)
            Grain(kind: .grain, opacity: dark ? 0.12 : 0.1, role: .desk)
            // Light falling from above and the dark at the edges of a lit desk.
            RadialGradient(colors: [.white.opacity(dark ? 0.07 : 0.25), .clear], center: .init(x: 0.5, y: -0.05), startRadius: 0, endRadius: 700)
            RadialGradient(colors: [.clear, .black.opacity(dark ? 0.42 : 0.16)], center: .center, startRadius: 280, endRadius: 1100)
        }
        .ignoresSafeArea()
        #endif
    }
}

// MARK: - Plates, recesses and keys

/// Where a light would catch the edge of a raised thing.
private func bevel(_ radius: CGFloat, top: Double = 0.30, bottom: Double = 0.55) -> some View {
    RoundedRectangle(cornerRadius: radius, style: .continuous)
        .strokeBorder(LinearGradient(colors: [.white.opacity(top), .white.opacity(0.04), .black.opacity(bottom)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
}

struct MetalPlate: ViewModifier {
    var radius: CGFloat = 14
    var screws = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(LinearGradient(colors: [Color(white: 0.43), Color(white: 0.32), Color(white: 0.27)], startPoint: .top, endPoint: .bottom))
                    Grain(kind: .brushed, opacity: 0.22).clipShape(shape)
                    // The sheen along the top where a brushed edge takes the light.
                    shape.fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)))
                    bevel(radius)
                    if screws { Screws(radius: radius) }
                }
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                .shadow(color: .black.opacity(0.45), radius: 22, y: 14)
            }
    }
}

private struct Screws: View {
    let radius: CGFloat
    var body: some View {
        let inset = max(8, radius * 0.6)
        GeometryReader { g in
            ForEach(0..<4, id: \.self) { i in
                Screw().position(x: i % 2 == 0 ? inset : g.size.width - inset, y: i < 2 ? inset : g.size.height - inset)
            }
        }
    }
}

/// A slotted screw head.
struct Screw: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(white: 0.62), Color(white: 0.28)], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 6))
            .frame(width: 7, height: 7)
            .overlay(Capsule().fill(.black.opacity(0.55)).frame(width: 5, height: 1).rotationEffect(.degrees(35)))
            .shadow(color: .black.opacity(0.6), radius: 0.5, y: 0.6)
    }
}

/// Pressed into the surface, with the shadow of the lip across the top.
struct Recessed: ViewModifier {
    var radius: CGFloat = 10
    var tint: Color = .black

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(tint.opacity(0.62))
                    shape.fill(.black.opacity(0.35))
                    // The lip's shadow, drawn as a blurred stroke clipped to the inside.
                    shape.stroke(.black.opacity(0.85), lineWidth: 5).blur(radius: 3.5).offset(y: 2).clipShape(shape)
                    shape.strokeBorder(LinearGradient(colors: [.black.opacity(0.7), .white.opacity(0.16)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
            }
    }
}

extension View {
    func metalPlate(radius: CGFloat = 14, screws: Bool = false) -> some View { modifier(MetalPlate(radius: radius, screws: screws)) }
    func recessed(radius: CGFloat = 10, tint: Color = .black) -> some View { modifier(Recessed(radius: radius, tint: tint)) }

    /// Type pressed into the surface: a dark edge above and a light one below.
    func engraved(_ strength: Double = 1) -> some View {
        shadow(color: .black.opacity(0.7 * strength), radius: 0, x: 0, y: -0.8).shadow(color: .white.opacity(0.18 * strength), radius: 0, x: 0, y: 0.8)
    }
    /// Type standing proud of the surface.
    func embossed(_ strength: Double = 1) -> some View {
        shadow(color: .white.opacity(0.25 * strength), radius: 0, x: 0, y: -0.7).shadow(color: .black.opacity(0.6 * strength), radius: 0.4, x: 0, y: 1)
    }

    /// Marks a key as switched on (its lamp lit), or leaves it plain.
    func lit(_ on: Bool) -> some View { environment(\.keyTint, on ? Theme.accent : nil) }
    func keyTint(_ color: Color?) -> some View { environment(\.keyTint, color) }
}

private struct KeyTintKey: EnvironmentKey { static let defaultValue: Color? = nil }
extension EnvironmentValues { var keyTint: Color? { get { self[KeyTintKey.self] } set { self[KeyTintKey.self] = newValue } } }

/// A hardware key: raised, with a lit edge, that sinks when pressed. `lit` keys glow at the edge like an indicator lamp.
struct KeyStyle: ButtonStyle {
    var radius: CGFloat = 9
    @Environment(\.keyTint) private var tint
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(tint ?? Color(white: 0.9))
            .shadow(color: .black.opacity(0.7), radius: 0, y: pressed ? 0 : -0.6)
            .background {
                ZStack {
                    shape.fill(LinearGradient(colors: pressed ? [Color(white: 0.16), Color(white: 0.22)] : [Color(white: 0.36), Color(white: 0.2)], startPoint: .top, endPoint: .bottom))
                    Grain(kind: .grain, opacity: 0.3).clipShape(shape)
                    if let tint { shape.fill(tint.opacity(pressed ? 0.16 : 0.1)) }
                    bevel(radius, top: pressed ? 0.06 : 0.34, bottom: 0.6)
                    // The lamp: a thin lit line along the bottom edge of a key that is on.
                    if let tint { Capsule().fill(tint).frame(height: 2).padding(.horizontal, radius * 0.8).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 3).opacity(0.85) }
                }
                .shadow(color: .black.opacity(pressed ? 0.2 : 0.55), radius: pressed ? 0.5 : 2, y: pressed ? 0 : 2)
            }
            .offset(y: pressed ? 1 : 0)
            .opacity(enabled ? 1 : 0.42)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

// MARK: - Display

/// A display behind glass: black, with the unlit segments faintly showing and fine scan lines over the lit ones.
struct LCDText: View {
    let text: String
    var size: CGFloat = 26
    var color: Color = Theme.accent

    var body: some View {
        // Unlit segments: an eight in every place the digits can go.
        let ghost = String(text.map { $0.isNumber ? "8" : $0 })
        ZStack(alignment: .trailing) {
            Text(ghost).foregroundStyle(color.opacity(0.07))
            Text(text).foregroundStyle(color)
        }
        .font(.system(size: size, weight: .semibold, design: .monospaced))
        .minimumScaleFactor(0.6).lineLimit(1)
    }
}

/// The glass over a display: a curved reflection and scan lines.
struct DisplayGlass: View {
    var radius: CGFloat = 9
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            Canvas { ctx, size in
                var y: CGFloat = 0
                while y < size.height { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.6)), with: .color(.black.opacity(0.22))); y += 2.4 }
            }
            shape.fill(LinearGradient(colors: [.white.opacity(0.09), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.5)))
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }
}

// MARK: - Leather and stitching

/// A dashed line of thread just inside a shape's edge.
struct Stitching: View {
    var radius: CGFloat = 12
    var inset: CGFloat = 5
    var color: Color = Color(red: 0.86, green: 0.74, blue: 0.5)

    var body: some View {
        RoundedRectangle(cornerRadius: max(0, radius - inset), style: .continuous)
            .inset(by: inset)
            .stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [3.2, 2.6]))
            .shadow(color: .black.opacity(0.55), radius: 0, y: 1)
            .allowsHitTesting(false)
    }
}

/// A pad of dark leather, stitched at the edge.
struct LeatherPad: ViewModifier {
    var radius: CGFloat = 12
    var pressed = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            ZStack {
                shape.fill(LinearGradient(colors: pressed ? [Color(red: 0.16, green: 0.115, blue: 0.09), Color(red: 0.2, green: 0.145, blue: 0.11)] : [Color(red: 0.27, green: 0.195, blue: 0.15), Color(red: 0.16, green: 0.115, blue: 0.09)], startPoint: .top, endPoint: .bottom))
                Grain(kind: .leather, opacity: 0.32, role: .leather).clipShape(shape)
                bevel(radius, top: pressed ? 0.05 : 0.2, bottom: 0.6)
                Stitching(radius: radius)
            }
            .shadow(color: .black.opacity(pressed ? 0.25 : 0.55), radius: pressed ? 1 : 5, y: pressed ? 0 : 4)
        }
    }
}

/// A brass plate, for the one thing on the screen that matters most.
struct BrassPlate: ViewModifier {
    var radius: CGFloat = 12
    var pressed = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            ZStack {
                shape.fill(LinearGradient(colors: pressed ? [Color(red: 0.62, green: 0.46, blue: 0.2), Color(red: 0.78, green: 0.6, blue: 0.3)] : [Color(red: 0.93, green: 0.78, blue: 0.46), Color(red: 0.62, green: 0.45, blue: 0.19)], startPoint: .top, endPoint: .bottom))
                Grain(kind: .brushed, opacity: 0.2).clipShape(shape)
                bevel(radius, top: pressed ? 0.1 : 0.55, bottom: 0.45)
            }
            .shadow(color: .black.opacity(pressed ? 0.25 : 0.55), radius: pressed ? 1 : 5, y: pressed ? 0 : 4)
        }
    }
}
