import SwiftUI

/// The Union flag, drawn from its standard 60 by 30 construction and stretched to fill whatever it is given.
struct UnionFlag: View {
    var body: some View {
        Canvas { context, size in
            var c = context
            c.scaleBy(x: size.width / 60, y: size.height / 30)
            let blue = Color(red: 0.004, green: 0.129, blue: 0.412), red = Color(red: 0.784, green: 0.063, blue: 0.18)
            func line(_ a: CGPoint, _ b: CGPoint, _ width: CGFloat, _ color: Color, in ctx: inout GraphicsContext) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(color), lineWidth: width)
            }
            c.fill(Path(CGRect(x: 0, y: 0, width: 60, height: 30)), with: .color(blue))
            line(.init(x: 0, y: 0), .init(x: 60, y: 30), 6, .white, in: &c); line(.init(x: 60, y: 0), .init(x: 0, y: 30), 6, .white, in: &c)
            // The red diagonals sit in four triangles, so each is to one side of the white.
            var triangles = Path()
            for t in [[(30, 15), (60, 15), (60, 30)], [(30, 15), (30, 30), (0, 30)], [(30, 15), (0, 15), (0, 0)], [(30, 15), (30, 0), (60, 0)]] as [[(CGFloat, CGFloat)]] {
                triangles.move(to: CGPoint(x: t[0].0, y: t[0].1)); triangles.addLine(to: CGPoint(x: t[1].0, y: t[1].1)); triangles.addLine(to: CGPoint(x: t[2].0, y: t[2].1)); triangles.closeSubpath()
            }
            c.drawLayer { layer in
                layer.clip(to: triangles)
                line(.init(x: 0, y: 0), .init(x: 60, y: 30), 4, red, in: &layer); line(.init(x: 60, y: 0), .init(x: 0, y: 30), 4, red, in: &layer)
            }
            line(.init(x: 30, y: 0), .init(x: 30, y: 30), 10, .white, in: &c); line(.init(x: 0, y: 15), .init(x: 60, y: 15), 10, .white, in: &c)
            line(.init(x: 30, y: 0), .init(x: 30, y: 30), 6, red, in: &c); line(.init(x: 0, y: 15), .init(x: 60, y: 15), 6, red, in: &c)
        }
        .accessibilityHidden(true)
    }
}

/// The credit at the foot of Settings: the flag, dimmed, with the line in heavy white type over it. The same banner the
/// Remy website ends on.
struct CreditBanner: View {
    private var line: AttributedString {
        var text = AttributedString("Created by Toby Jones in England, UK")
        if let name = text.range(of: "Toby Jones") {
            text[name].link = URL(string: "https://thecaffeinemediacompany.com")
            text[name].underlineStyle = .single
        }
        return text
    }

    var body: some View {
        Text(line)
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(.white)
            .tint(.white)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.9), radius: 0.5, y: 1)
            .shadow(color: .black.opacity(0.7), radius: 4)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26).padding(.horizontal, 18)
            .background {
                ZStack { UnionFlag(); Color.black.opacity(0.25) }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
    }
}
