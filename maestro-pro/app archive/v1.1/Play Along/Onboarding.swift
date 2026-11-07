import SwiftUI

/// Shows the onboarding over the app on the first launch, until it has been finished once.
struct OnboardingGate: ViewModifier {
    @AppStorage("onboarded") private var onboarded = false

    private var skip: Bool {
        #if DEBUG
        // Screenshot hooks launch with arguments; they shouldn't land on the welcome.
        let args = CommandLine.arguments.dropFirst()
        return !args.contains("-onboarding") && args.contains { $0.hasPrefix("-") }
        #else
        false
        #endif
    }

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding { !onboarded && !skip } set: { if !$0 { onboarded = true } }) {
            OnboardingView { onboarded = true }
        }
    }
}

struct OnboardingView: View {
    let finish: () -> Void

    private enum Step: Int, CaseIterable { case welcome, howItWorks, editor, instrument, look, plans, missOut, survey }
    @State private var showSurvey = false
    @State private var step = Step.welcome
    @State private var forward = true
    @AppStorage("instrumentKey") private var instrumentKey = InstrumentKey.concert.rawValue
    @AppStorage("highlight") private var highlight = "Amber"
    @AppStorage("darkPaper") private var darkPaper = false
    @AppStorage("advancedMode") private var advanced = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            PaywallBackdrop()
            Group {
                switch step {
                case .welcome: page(button: ("Get Started", nil)) { WelcomePage() }
                case .howItWorks: page(button: ("Continue", nil)) { HowItWorksPage(tint: Theme.highlight(highlight), dark: darkPaper) }
                case .editor: page(button: ("Continue", nil)) { EditorPage(dark: darkPaper) }
                case .instrument: page(button: ("Continue", nil)) { InstrumentPage(key: $instrumentKey) }
                case .look: page(button: ("Looks Good", nil)) { LookPage(highlight: $highlight, darkPaper: $darkPaper, advanced: $advanced) }
                case .plans:
                    PaywallView(required: .performer, feature: "", freeExit: { go(.missOut) }, close: done)
                case .missOut: page(button: ("See the Plans", { go(.plans, back: true) })) { MissOutPage() }
                case .survey: page(button: ("Take the \(DiversitySurvey.name.replacingOccurrences(of: "Userbase Diversity ", with: ""))", { showSurvey = true })) { SurveyPage() }
                }
            }
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
        }
        .overlay(alignment: .top) {
            if step.rawValue < Step.plans.rawValue { progress.padding(.top, 18) }
        }
        .overlay(alignment: .topLeading) {
            if step != .welcome, step != .plans, step != .survey {
                Button { go(Step(rawValue: step.rawValue - 1) ?? .welcome, back: true) } label: { Image(systemName: "chevron.left").font(.callout.weight(.bold)) }
                    .buttonStyle(KeyStyle(radius: 16))
                    .accessibilityLabel("Back")
                    .padding(16)
                    .transition(.opacity)
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { g in
            guard step.rawValue < Step.plans.rawValue, abs(g.translation.width) > abs(g.translation.height) else { return }
            if g.translation.width < -60 { next() } else if g.translation.width > 60, step != .welcome { go(Step(rawValue: step.rawValue - 1)!, back: true) }
        })
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .sensoryFeedback(.selection, trigger: step)
        .sheet(isPresented: $showSurvey, onDismiss: finish) { SafariView(url: DiversitySurvey.url).ignoresSafeArea() }
        .onAppear {
            Analytics.track("onboarding_started")
            #if DEBUG
            if let i = CommandLine.arguments.firstIndex(of: "-onboardingStep"), i + 1 < CommandLine.arguments.count, let n = Int(CommandLine.arguments[i + 1]) { step = Step(rawValue: n) ?? .welcome }   // screenshot hook
            #endif
        }
    }

    /// One page of the tour, with its big brass button and, on the last tour page, nothing else.
    private func page<Content: View>(button: (title: String, action: (() -> Void)?), @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                content()
                    .padding(.horizontal, 28)
                    .padding(.top, 70)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            VStack(spacing: 12) {
                Button { (button.action ?? next)() } label: {
                    Text(button.title)
                        .font(.custom("Baskerville", size: 22, relativeTo: .title2).weight(.bold))
                        .foregroundStyle(Color(red: 0.22, green: 0.13, blue: 0.03))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                }
                .buttonStyle(CTAStyle(animate: !reduceMotion && (step == .welcome || step == .missOut)))
                if step == .missOut || step == .survey {
                    Button(step == .survey ? String(localized: "Not Now") : String(localized: "Continue for Free"), action: step == .survey ? finish : done)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color(white: 0.55))
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 18)
            .frame(maxWidth: 560)
        }
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(0..<Step.plans.rawValue, id: \.self) { i in
                Capsule()
                    .fill(i <= step.rawValue ? Theme.accent : Color(white: 0.35))
                    .frame(width: i == step.rawValue ? 26 : 8, height: 8)
            }
        }
        .animation(.spring(duration: 0.5, bounce: 0.35), value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(step.rawValue + 1) of \(Step.plans.rawValue)")
    }

    private func next() { if let n = Step(rawValue: step.rawValue + 1) { go(n) } }

    private func go(_ s: Step, back: Bool = false) {
        forward = !back
        withAnimation(.spring(duration: 0.6, bounce: 0.2)) { step = s }
        if s == .missOut { Analytics.track("onboarding_continue_free_tapped") }
    }

    /// Past the plans (bought, or carrying on free): one last, optional ask before the app.
    private func done() {
        Analytics.track("onboarding_finished", ["tier": Store.shared.tier.name])
        go(.survey)
    }
}

// MARK: - Pages

private struct Headline: View {
    let kicker: String
    let title: String
    let text: String
    let shown: Bool

    var body: some View {
        VStack(spacing: 12) {
            Text(kicker.uppercased())
                .font(.caption.weight(.heavy)).tracking(1.6)
                .foregroundStyle(Theme.accent)
                .reveal(shown, 0.05)
            Text(title)
                .font(.custom("Baskerville", size: 36, relativeTo: .largeTitle).weight(.semibold))
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.96, blue: 0.88), Color(red: 0.93, green: 0.8, blue: 0.58)], startPoint: .top, endPoint: .bottom))
                .multilineTextAlignment(.center)
                .engraved(0.6)
                .reveal(shown, 0.12)
            Text(text)
                .font(.callout)
                .foregroundStyle(Color(red: 0.9, green: 0.84, blue: 0.74).opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .reveal(shown, 0.2)
        }
    }
}

/// Animates in once, when the page first shows.
private struct Appear: ViewModifier {
    @Binding var shown: Bool
    func body(content: Content) -> some View {
        content.onAppear { withAnimation(.spring(duration: 0.9, bounce: 0.25)) { shown = true } }
    }
}

private struct WelcomePage: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 40)
            Medallion(symbol: "music.note", animate: !reduceMotion)
                .scaleEffect(shown ? 1.15 : 0.4)
                .rotationEffect(.degrees(shown ? 0 : -60))
                .opacity(shown ? 1 : 0)
                .animation(.spring(duration: 1.1, bounce: 0.45), value: shown)
            Headline(kicker: String(localized: "Welcome to Maestro Pro"), title: String(localized: "Your scores.\nRehearsed, performed, written."),
                     text: String(localized: "Maestro Pro reads your sheet music and follows it to the note, turns pages hands-free, and lets you write and revise the parts themselves. A minute of setup and you're ready."),
                     shown: shown)
            if UIDevice.current.userInterfaceIdiom == .phone && !PhoneViewer.isDuo {
                Label("On iPhone, Maestro Pro only views the scores you add on your iPad or Mac. It isn't the full app.", systemImage: "info.circle")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .reveal(shown, 0.3)
            }
            Spacer(minLength: 20)
        }
        .modifier(Appear(shown: $shown))
    }
}

private struct HowItWorksPage: View {
    let tint: Color
    let dark: Bool
    @State private var shown = false

    private let steps = [
        ("square.and.arrow.down", String(localized: "Bring in your scores"), String(localized: "PDF, MusicXML, MIDI or karaoke files, read on the device.")),
        ("waveform", String(localized: "Add a backing track"), String(localized: "Optional. Your own recording, synced to the score's tempo and key.")),
        ("play.fill", "Perform", String(localized: "Notes light as they sound and pages turn hands-free, in rehearsal or on stage.")),
    ]

    var body: some View {
        VStack(spacing: 28) {
            Headline(kicker: String(localized: "How it works"), title: String(localized: "From the page\nto the performance."),
                     text: String(localized: "Every note timed to the beat, so the score keeps up with you."), shown: shown)
            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                VStack(spacing: 22) {
                    PlayAlongDemo(time: t, tint: tint, dark: dark)
                        .frame(height: 150)
                        .reveal(shown, 0.3)
                    VStack(spacing: 12) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                            let on = Int(t / 2.4) % steps.count == i
                            HStack(spacing: 14) {
                                Image(systemName: s.0)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(on ? Color(red: 0.22, green: 0.13, blue: 0.03) : Theme.accent)
                                    .frame(width: 42, height: 42)
                                    .background { if on { Circle().fill(.clear).modifier(BrassPlate(radius: 21)) } else { Circle().fill(.black.opacity(0.3)) } }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.1).font(.headline).foregroundStyle(Color(red: 0.98, green: 0.94, blue: 0.86))
                                    Text(s.2).font(.subheadline).foregroundStyle(Color(white: 0.72)).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .modifier(LeatherPad(radius: 16, pressed: !on))
                            .scaleEffect(on ? 1 : 0.97)
                            .animation(.spring(duration: 0.5, bounce: 0.3), value: on)
                            .reveal(shown, 0.4 + Double(i) * 0.1)
                        }
                    }
                }
            }
        }
        .modifier(Appear(shown: $shown))
    }
}

/// A line of music on paper: the moving line sweeps across, lighting each note and its bar as it passes.
struct PlayAlongDemo: View {
    let time: Double
    let tint: Color
    let dark: Bool
    var period = 4.8

    // (start, length) in beats over two bars of four crotchets, and a staff step for the height. Only crotchets:
    // the drawing has no flags, beams or dots, so anything shorter or dotted would read as a wrong count.
    static let notes: [(Double, Double, Int)] = [(0, 1, 2), (1, 1, 4), (2, 1, 6), (3, 1, 4), (4, 1, 3), (5, 1, 5), (6, 1, 4), (7, 1, 2)]

    var body: some View {
        Canvas { g, size in
            let paper = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12)
            g.fill(paper, with: .color(Theme.paper(dark: dark)))
            let ink: Color = dark ? Color(white: 0.92) : Color(red: 0.12, green: 0.09, blue: 0.07)
            let left: CGFloat = 26, right = size.width - 18, gap: CGFloat = 11
            let top = size.height / 2 - gap * 2
            let beatW = (right - left - 20) / 8
            let x0 = left + 20
            let beat = (time.truncatingRemainder(dividingBy: period)) / period * 8

            // The bar being played, washed in the highlight.
            let bar = Int(beat / 4)
            g.fill(Path(CGRect(x: x0 + CGFloat(bar * 4) * beatW - 6, y: top - 14, width: beatW * 4, height: gap * 4 + 28)), with: .color(tint.opacity(0.14)))

            for i in 0..<5 {
                let y = top + CGFloat(i) * gap
                g.stroke(Path { $0.move(to: CGPoint(x: left, y: y)); $0.addLine(to: CGPoint(x: right, y: y)) }, with: .color(ink.opacity(0.6)), lineWidth: 1)
            }
            for b in [x0 + beatW * 4 - 6, right] {
                g.stroke(Path { $0.move(to: CGPoint(x: b, y: top)); $0.addLine(to: CGPoint(x: b, y: top + gap * 4)) }, with: .color(ink.opacity(0.7)), lineWidth: 1.2)
            }
            for n in Self.notes {
                let lit = beat >= n.0 && beat < n.0 + n.1
                let x = x0 + CGFloat(n.0) * beatW + 8
                let y = top + gap * 4 - CGFloat(n.2) * gap / 2
                let r: CGFloat = lit ? 7.5 : 6.2
                let head = Path(ellipseIn: CGRect(x: x - r, y: y - r * 0.75, width: r * 2, height: r * 1.5)).applying(.init(translationX: -x, y: -y).concatenating(.init(rotationAngle: -0.35)).concatenating(.init(translationX: x, y: y)))
                let c = lit ? tint : ink
                if lit { g.fill(Path(ellipseIn: CGRect(x: x - 16, y: y - 16, width: 32, height: 32)), with: .color(tint.opacity(0.25))) }
                if n.1 >= 2 { g.stroke(head, with: .color(c), lineWidth: 1.8) } else { g.fill(head, with: .color(c)) }
                g.stroke(Path { $0.move(to: CGPoint(x: x + r - 1, y: y)); $0.addLine(to: CGPoint(x: x + r - 1, y: y - 32)) }, with: .color(c), lineWidth: 1.4)
            }
            let lineX = x0 + CGFloat(beat) * beatW
            g.fill(Path(roundedRect: CGRect(x: lineX - 1.5, y: top - 18, width: 3, height: gap * 4 + 36), cornerRadius: 1.5), with: .color(tint))
        }
        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
        .accessibilityLabel("A line of music with each note lighting as the moving line passes it")
    }
}

private struct EditorPage: View {
    let dark: Bool
    @State private var shown = false

    var body: some View {
        VStack(spacing: 26) {
            Headline(kicker: String(localized: "The score editor"), title: String(localized: "Write it.\nRevise it. Own it."),
                     text: String(localized: "Correct a wrong note, write a new part or build a medley for the set. The editor keeps every bar correct as you go, and every version is saved."), shown: shown)
            TimelineView(.animation) { ctx in
                EditorDemo(time: ctx.date.timeIntervalSinceReferenceDate, dark: dark)
            }
            .reveal(shown, 0.3)
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                Text("Included with Professional")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color(red: 0.93, green: 0.8, blue: 0.58))
            .reveal(shown, 0.5)
        }
        .modifier(Appear(shown: $shown))
    }
}

/// The editor at work: notes written in, then accents, dynamics and a repeat, with the tool palette following along.
private struct EditorDemo: View {
    let time: Double
    let dark: Bool
    var period = 10.0

    private static let tools = [("Notes", "music.note"), ("Marks", "chevron.up"), ("Dynamics", "speaker.wave.2"), ("Bars", "repeat"), ("Erase", "eraser")]
    private static let notes = PlayAlongDemo.notes

    var body: some View {
        let p = time.truncatingRemainder(dividingBy: period) / period * 4
        let phase = Int(p), local = p - Double(phase)
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Array(Self.tools.enumerated()), id: \.offset) { i, t in
                    let on = i == phase
                    Label(t.0, systemImage: t.1)
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .foregroundStyle(on ? Color(red: 0.22, green: 0.13, blue: 0.03) : Color(white: 0.85))
                        .background { if on { Capsule().fill(.clear).modifier(BrassPlate(radius: 14)) } }
                        .animation(.spring(duration: 0.35, bounce: 0.4), value: phase)
                }
            }
            .padding(5)
            .metalPlate(radius: 18)
            Canvas { g, size in draw(g, size, phase: phase, local: local) }
                .frame(height: 160)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
        }
        .accessibilityElement()
        .accessibilityLabel("The score editor writing notes, then adding accents, dynamics and a repeat")
    }

    private func draw(_ g: GraphicsContext, _ size: CGSize, phase: Int, local: Double) {
        g.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12), with: .color(Theme.paper(dark: dark)))
        let ink: Color = dark ? Color(white: 0.92) : Color(red: 0.12, green: 0.09, blue: 0.07)
        let amber = Theme.accent
        let left: CGFloat = 26, right = size.width - 18, gap: CGFloat = 11
        let top = size.height / 2 - gap * 2 + 2
        let beatW = (right - left - 24) / 8, x0 = left + 22
        for i in 0..<5 {
            let y = top + CGFloat(i) * gap
            g.stroke(Path { $0.move(to: CGPoint(x: left, y: y)); $0.addLine(to: CGPoint(x: right, y: y)) }, with: .color(ink.opacity(0.6)), lineWidth: 1)
        }
        let line = { (x: CGFloat, w: CGFloat) in
            g.fill(Path(CGRect(x: x - w / 2, y: top, width: w, height: gap * 4)), with: .color(ink))
        }
        line(x0 + beatW * 4 - 6, 1.2)

        // Notes: written one by one in the first phase, each dropping onto the staff.
        let written = phase == 0 ? min(Self.notes.count, Int(local * Double(Self.notes.count + 1))) : Self.notes.count
        for (i, n) in Self.notes.prefix(written).enumerated() {
            let fresh = phase == 0 && i == written - 1
            let drop = fresh ? CGFloat(max(0, 1 - (local * Double(Self.notes.count + 1) - Double(i)) * 3)) * -18 : 0
            let x = x0 + CGFloat(n.0) * beatW + 8
            let y = top + gap * 4 - CGFloat(n.2) * gap / 2 + drop
            let c = fresh ? amber : ink
            let head = Path(ellipseIn: CGRect(x: x - 6.2, y: y - 4.6, width: 12.4, height: 9.2))
                .applying(.init(translationX: -x, y: -y).concatenating(.init(rotationAngle: -0.35)).concatenating(.init(translationX: x, y: y)))
            if n.1 >= 2 { g.stroke(head, with: .color(c), lineWidth: 1.8) } else { g.fill(head, with: .color(c)) }
            g.stroke(Path { $0.move(to: CGPoint(x: x + 5.2, y: y)); $0.addLine(to: CGPoint(x: x + 5.2, y: y - 32)) }, with: .color(c), lineWidth: 1.4)

            // Accents above, added in the second phase.
            if phase >= 1, i % 2 == 0, phase > 1 || Double(i) / Double(Self.notes.count) < local {
                let ay = top - 30   // clear of the highest stem
                let col = phase == 1 && Double(i + 2) / Double(Self.notes.count) > local ? amber : ink
                g.stroke(Path { $0.move(to: CGPoint(x: x - 5, y: ay - 4)); $0.addLine(to: CGPoint(x: x + 4, y: ay)); $0.addLine(to: CGPoint(x: x - 5, y: ay + 4)) }, with: .color(col), lineWidth: 1.4)
            }
        }
        if phase == 0, written < Self.notes.count {
            // The insertion point, waiting for the next note.
            let n = Self.notes[written]
            let x = x0 + CGFloat(n.0) * beatW + 8
            g.fill(Path(roundedRect: CGRect(x: x - 1, y: top - 10, width: 2, height: gap * 4 + 20), cornerRadius: 1), with: .color(amber.opacity(0.8)))
        }

        // Dynamics below: mf, then a crescendo that grows across the second bar.
        if phase >= 2 {
            let dy = top + gap * 4 + 22
            let col = phase == 2 ? amber : ink
            g.draw(Text("mf").font(.custom("Baskerville-BoldItalic", size: 18)).foregroundColor(col), at: CGPoint(x: x0 + 10, y: dy))
            let grow = phase == 2 ? CGFloat(min(1, local * 1.6)) : 1
            let hx = x0 + beatW * 4, hw = beatW * 3.4 * grow
            g.stroke(Path { $0.move(to: CGPoint(x: hx + hw, y: dy - 6)); $0.addLine(to: CGPoint(x: hx, y: dy)); $0.addLine(to: CGPoint(x: hx + hw, y: dy + 6)) }, with: .color(col), lineWidth: 1.3)
        }

        // A closing repeat: dots, a thin and a thick line.
        if phase >= 3 {
            let a = phase == 3 ? min(1, local * 3) : 1
            var r = g
            r.opacity = a
            let col = phase == 3 ? amber : ink
            r.fill(Path(CGRect(x: right - 4, y: top, width: 4, height: gap * 4)), with: .color(col))
            r.fill(Path(CGRect(x: right - 9, y: top, width: 1.2, height: gap * 4)), with: .color(col))
            for k in [1.5, 2.5] { r.fill(Path(ellipseIn: CGRect(x: right - 17, y: top + gap * CGFloat(k) - 2, width: 4, height: 4)), with: .color(col)) }
        } else {
            line(right, 1.2)
        }
    }
}

private struct SurveyPage: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 30) {
            Spacer(minLength: 30)
            Medallion(symbol: "person.3.fill", animate: !reduceMotion)
                .scaleEffect(shown ? 1 : 0.4)
                .opacity(shown ? 1 : 0)
                .animation(.spring(duration: 1.0, bounce: 0.45), value: shown)
            Headline(kicker: String(localized: "One last thing"), title: String(localized: "Help us build\nfor every musician."),
                     text: String(localized: "The \(DiversitySurvey.name) tells us who Maestro Pro is reaching, so we can make it work for every kind of musician. It's optional, and it opens right here in the app."),
                     shown: shown)
            Spacer(minLength: 20)
        }
        .modifier(Appear(shown: $shown))
    }
}

private struct InstrumentPage: View {
    @Binding var key: String
    @State private var shown = false
    @State private var picked: String?

    private let instruments: [(name: String, symbol: String, key: InstrumentKey)] = [
        ("Piano", "pianokeys", .concert), ("Guitar", "guitars", .concert), ("Voice", "music.mic", .concert),
        ("Flute", "wind", .concert), ("Violin", "music.note", .concert), ("Clarinet", "music.note", .bFlat),
        ("Trumpet", "music.note", .bFlat), ("Alto Sax", "music.note", .eFlat), ("Tenor Sax", "music.note", .tenor),
    ]

    var body: some View {
        VStack(spacing: 26) {
            Headline(kicker: String(localized: "Make it yours"), title: String(localized: "What do you play?"),
                     text: String(localized: "Maestro Pro shows the music in your instrument's key, so it matches the part in front of you."), shown: shown)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                ForEach(Array(instruments.enumerated()), id: \.offset) { i, ins in
                    let on = picked == ins.name
                    Button {
                        withAnimation(.spring(duration: 0.45, bounce: 0.4)) { picked = ins.name; key = ins.key.rawValue }
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: ins.symbol)
                                .font(.title2.weight(.semibold))
                                .symbolEffect(.bounce, value: on)
                            Text(ins.name).font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(on ? Color(red: 0.22, green: 0.13, blue: 0.03) : Color(red: 0.96, green: 0.92, blue: 0.84))
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background {
                            if on { RoundedRectangle(cornerRadius: 16).fill(.clear).modifier(BrassPlate(radius: 16)) }
                            else { RoundedRectangle(cornerRadius: 16).fill(.clear).modifier(LeatherPad(radius: 16)) }
                        }
                        .scaleEffect(on ? 1.04 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .reveal(shown, 0.25 + Double(i) * 0.04)
                }
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Color(white: 0.7))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.smooth, value: key)
                .reveal(shown, 0.6)
        }
        .sensoryFeedback(.selection, trigger: picked)
        .modifier(Appear(shown: $shown))
    }

    private var caption: String { whereShown + String(localized: " You can change this any time in the Inspector.") }

    private var whereShown: String {
        switch InstrumentKey(rawValue: key) ?? .concert {
        case .concert: String(localized: "Music shows at concert pitch, as written.")
        case .bFlat: String(localized: "Music shows in B♭, a tone above concert pitch, to match your part.")
        case .eFlat: String(localized: "Music shows in E♭, to match your part.")
        case .tenor: String(localized: "Music shows in B♭ for tenor sax, to match your part.")
        }
    }
}

private struct LookPage: View {
    @Binding var highlight: String
    @Binding var darkPaper: Bool
    @Binding var advanced: Bool
    @State private var shown = false
    @Namespace private var ns

    var body: some View {
        VStack(spacing: 24) {
            Headline(kicker: String(localized: "Make it yours"), title: String(localized: "Set the stand."),
                     text: String(localized: "Pick how the music looks while it plays. Everything here is in Settings later."), shown: shown)
            TimelineView(.animation) { ctx in
                PlayAlongDemo(time: ctx.date.timeIntervalSinceReferenceDate, tint: Theme.highlight(highlight), dark: darkPaper)
            }
            .frame(height: 140)
            .animation(.smooth, value: darkPaper)
            .reveal(shown, 0.25)

            VStack(alignment: .leading, spacing: 18) {
                row(String(localized: "Highlight Colour")) {
                    HStack(spacing: 14) {
                        ForEach(Theme.highlights, id: \.name) { h in
                            Button { withAnimation(.spring(duration: 0.35, bounce: 0.4)) { highlight = h.name } } label: {
                                Circle().fill(h.color).frame(width: 30, height: 30).padding(4)
                                    .overlay { if highlight == h.name { Circle().strokeBorder(.white, lineWidth: 2).matchedGeometryEffect(id: "ring", in: ns) } }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(h.name)
                            .accessibilityAddTraits(highlight == h.name ? .isSelected : [])
                        }
                    }
                }
                row(String(localized: "Sheet Music")) {
                    Picker("Sheet Music", selection: $darkPaper.animation(.smooth)) {
                        Text("Light Paper").tag(false)
                        Text("Dark Paper").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                row(String(localized: "How Much to Show")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Mode", selection: $advanced.animation(.smooth)) {
                            Text("Simple").tag(false)
                            Text("Advanced").tag(true)
                        }
                        .pickerStyle(.segmented)
                        Text(advanced ? String(localized: "Every tool on show: editors, sync, Play Together, sharing.") : String(localized: "Just the essentials: open, play along, change tempo and key."))
                            .font(.caption).foregroundStyle(Color(white: 0.65))
                            .contentTransition(.opacity)
                    }
                }
            }
            .padding(18)
            .modifier(LeatherPad(radius: 18))
            .reveal(shown, 0.4)
        }
        .sensoryFeedback(.selection, trigger: highlight)
        .modifier(Appear(shown: $shown))
    }

    private func row<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption2.weight(.heavy)).tracking(1.2).foregroundStyle(Color(red: 0.93, green: 0.8, blue: 0.58))
            content()
        }
    }
}

/// After "Continue for Free": what stays locked, before letting them go.
private struct MissOutPage: View {
    @State private var shown = false
    @State private var struck = false

    var body: some View {
        VStack(spacing: 24) {
            Headline(kicker: String(localized: "Before you go"), title: String(localized: "Here's what\nyou'd miss."),
                     text: String(localized: "Free lets you view the sheet music for up to three scores. These stay locked:"), shown: shown)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(Tier.performer.features.enumerated()), id: \.offset) { i, f in
                    HStack(spacing: 14) {
                        Image(systemName: f.symbol)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color(white: 0.55))
                            .frame(width: 34, height: 34)
                            .recessed(radius: 9)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accent).offset(x: 4, y: 4)
                                    .scaleEffect(struck ? 1 : 0.1).opacity(struck ? 1 : 0)
                                    .animation(.spring(duration: 0.4, bounce: 0.5).delay(0.6 + Double(i) * 0.07), value: struck)
                            }
                        Text(f.text)
                            .font(.callout)
                            .foregroundStyle(Color(white: struck ? 0.6 : 0.9))
                            .strikethrough(struck, color: Color(white: 0.5))
                            .animation(.easeOut(duration: 0.3).delay(0.6 + Double(i) * 0.07), value: struck)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .reveal(shown, 0.2 + Double(i) * 0.05)
                }
            }
            .padding(18)
            .modifier(LeatherPad(radius: 18, pressed: true))
        }
        .onAppear {
            withAnimation(.spring(duration: 0.9, bounce: 0.25)) { shown = true }
            struck = true
        }
    }
}
