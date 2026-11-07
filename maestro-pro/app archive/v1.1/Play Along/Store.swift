import Security
import StoreKit
import SwiftUI
import UIKit

/// The plans, as on the website: Free, Performer (everything but the editor), Professional (everything).
enum Tier: Int, Comparable {
    case free, performer, professional
    static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }

    var name: String { ["Free", "Performer", "Professional"][rawValue] }

    /// What the plan adds, in the website's words.
    var features: [(symbol: String, text: String)] {
        switch self {
        case .free: []
        case .performer: [
            ("books.vertical", String(localized: "A library of any size, not just three scores")),
            ("play.fill", String(localized: "Play any score back, at the tempo you choose")),
            ("music.note", String(localized: "Notes, bars and a moving line that follow the music")),
            ("magnifyingglass", String(localized: "Search Scores, and find lyrics online")),
            ("dial.medium", String(localized: "Change key, and shape the sound with the equaliser")),
            ("waveform", String(localized: "Stack backing tracks, or play along with Apple Music")),
            ("person.2.wave.2", String(localized: "Play Together on up to eight devices")),
            ("tuningfork", String(localized: "The tuner, and a score that waits for you")),
            ("record.circle", String(localized: "Record a take, then see every note to work on")),
            ("pencil.tip.crop.circle", String(localized: "Annotate with Apple Pencil, export and print")),
        ]
        case .professional: [
            ("checkmark.seal", String(localized: "Everything in Performer")),
            ("music.quarternote.3", String(localized: "The score editor: write and change music")),
            ("rectangle.stack", String(localized: "Build medleys from any score in your library")),
            ("clock.arrow.circlepath", String(localized: "Version history, branches, merges and GitHub sync")),
        ]
        }
    }
}

@Observable final class Store {
    static let shared = Store()

    /// Weekly or annual, plus the one-off lifetime Professional purchase (it counts as Professional in `refresh`).
    static let lifetimeID = "com.tobyjones.MaestroPro.Professional.life"
    static func productID(_ tier: Tier, yearly: Bool) -> String {
        "com.tobyjones.MaestroPro." + (tier == .professional ? "Professional" : "Performer") + (yearly ? ".annual" : ".weekly")
    }
    private static let ids = [productID(.performer, yearly: false), productID(.performer, yearly: true),
                              productID(.professional, yearly: false), productID(.professional, yearly: true), lifetimeID]

    /// Kept between launches so a paid plan doesn't flash locked while the App Store is asked again.
    private(set) var tier = Tier(rawValue: UserDefaults.standard.integer(forKey: "tier")) ?? .free {
        didSet { UserDefaults.standard.set(tier.rawValue, forKey: "tier") }
    }
    private(set) var products: [String: Product] = [:]
    private(set) var trialEligible: Set<String> = []
    private var updates: Task<Void, Never>?

    private init() {
        updates = Task {
            for await result in Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await refresh()
            }
        }
        Task { await load(); await refresh() }
    }

    func load() async {
        guard let list = try? await Product.products(for: Self.ids) else { return }
        products = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        var eligible: Set<String> = []
        for p in list where p.subscription?.introductoryOffer != nil {
            if await p.subscription?.isEligibleForIntroOffer == true { eligible.insert(p.id) }
        }
        trialEligible = eligible
    }

    func refresh() async {
        var best = Tier.free
        for await result in Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            best = max(best, t.productID.contains(".Professional") ? .professional : .performer)
        }
        if await licenceActive() { best = .professional }
        #if DEBUG
        if let s = UserDefaults.standard.string(forKey: "debugTier") { best = ["free": .free, "performer": .performer, "professional": .professional][s] ?? best }
        #endif
        tier = best
    }

    /// True when it went through; false when cancelled or waiting on approval.
    func buy(_ id: String) async throws -> Bool {
        if products[id] == nil { await load() }
        guard let product = products[id] else { throw URLError(.notConnectedToInternet) }
        guard case .success(let result) = try await product.purchase(), case .verified(let t) = result else { return false }
        await t.finish()
        await refresh()
        Analytics.track("purchased", ["product": id])
        return true
    }

    // MARK: Student licence (checked against GoCardless by the feedback API)

    private static let licenceAPI = URL(string: "https://fider-feedback-api.vercel.app/api/student-check")!
    private var licenceKey: String? { UserDefaults.standard.string(forKey: "licenceKey") }

    /// Asks the server. Returns nil when it couldn't be reached, so a licence isn't lost to a bad connection.
    private func checkLicence(_ key: String) async -> (valid: Bool, error: String?)? {
        var req = URLRequest(url: Self.licenceAPI, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["key": key])
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (j["valid"] as? Bool == true, j["error"] as? String)
    }

    /// Redeems a licence key. Returns an error message to show, or nil when access has been granted.
    func redeem(key: String) async -> String? {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let r = await checkLicence(k) else { return String(localized: "Couldn’t check the licence. Check your connection and try again.") }
        guard r.valid else { return r.error ?? String(localized: "That licence key isn’t valid.") }
        let d = UserDefaults.standard
        d.set(k, forKey: "licenceKey"); d.set(Date(), forKey: "licenceChecked")
        await refresh()
        Analytics.track("licence_redeemed", [:])
        return nil
    }

    private var licenceCheckedThisLaunch = false

    /// True while a stored licence is good. It is checked with GoCardless on every launch (then at most daily),
    /// and keeps working offline for up to 14 days since the last good check.
    private func licenceActive() async -> Bool {
        guard let key = licenceKey else { return false }
        let d = UserDefaults.standard
        let last = d.object(forKey: "licenceChecked") as? Date ?? .distantPast
        if licenceCheckedThisLaunch, Date().timeIntervalSince(last) < 86_400 { return true }
        licenceCheckedThisLaunch = true
        guard let r = await checkLicence(key) else { return Date().timeIntervalSince(last) < 14 * 86_400 }
        if r.valid { d.set(Date(), forKey: "licenceChecked"); return true }
        ["licenceKey", "licenceChecked"].forEach(d.removeObject(forKey:))
        return false
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }

    #if DEBUG
    /// The plan to pretend to have, or nil for whatever the App Store says.
    var debugTier: Tier? {
        get { UserDefaults.standard.string(forKey: "debugTier").flatMap { ["free": .free, "performer": .performer, "professional": .professional][$0] } }
        set {
            UserDefaults.standard.set(newValue.map { $0.name.lowercased() }, forKey: "debugTier")
            Task { await refresh() }
        }
    }
    #endif

    // MARK: Gates

    func allows(_ t: Tier) -> Bool { tier >= t }

    /// Runs the action when the plan includes it; otherwise opens the paywall.
    func unlock(_ t: Tier, _ feature: String, _ action: () -> Void) {
        if allows(t) { action() } else { present(t, feature) }
    }

    /// A switch for a feature: reads off without the plan, and opens the paywall instead of turning on.
    func gate(_ t: Tier, _ feature: String, _ b: Binding<Bool>) -> Binding<Bool> {
        Binding { b.wrappedValue && self.allows(t) } set: { v in
            if v, !self.allows(t) { self.present(t, feature) } else { b.wrappedValue = v }
        }
    }

    /// Any other setting: it can be read, but changing it opens the paywall.
    func gate<V>(_ t: Tier, _ feature: String, _ b: Binding<V>) -> Binding<V> {
        Binding { b.wrappedValue } set: { v in if self.allows(t) { b.wrappedValue = v } else { self.present(t, feature) } }
    }

    /// Shown over whatever is on screen (a sheet, a popover, another window), so any button anywhere can open it.
    func present(_ t: Tier, _ feature: String) {
        Analytics.track("paywall_shown", ["tier": t.name, "feature": feature])
        DispatchQueue.main.async {   // let a menu that was tapped finish closing first
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            guard var top = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController else { return }
            while let p = top.presentedViewController, !p.isBeingDismissed { top = p }
            if top is PaywallHost { return }
            let host = PaywallHost(rootView: AnyView(EmptyView()))
            host.rootView = AnyView(PaywallView(required: t, feature: feature) { [weak host] in host?.dismiss(animated: true) })
            host.modalPresentationStyle = .formSheet
            host.preferredContentSize = CGSize(width: 560, height: 860)
            host.overrideUserInterfaceStyle = .dark
            top.present(host, animated: true)
        }
    }
}

final class PaywallHost: UIHostingController<AnyView> {}

// MARK: - The paywall

struct PaywallView: View {
    let required: Tier
    let feature: String
    let close: () -> Void
    /// In onboarding: the quiet way past the paywall, instead of the close button.
    var freeExit: (() -> Void)? = nil

    private let store = Store.shared
    @State private var plan: Tier
    @State private var yearly = true
    @State private var shown = false
    @State private var cardsWidth: CGFloat = 600
    @State private var buying: String?
    @State private var welcome: Tier?
    @State private var failure: String?
    @State private var enteringLicence = false
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    init(required: Tier, feature: String, freeExit: (() -> Void)? = nil, close: @escaping () -> Void) {
        self.required = required; self.feature = feature; self.freeExit = freeExit; self.close = close
        _plan = State(initialValue: required == .free ? .performer : required)
        #if DEBUG
        if CommandLine.arguments.contains("-weekly") { _yearly = State(initialValue: false) }   // screenshots
        #endif
    }

    /// The editor needs Professional, so Performer isn't offered for it.
    private var plans: [Tier] { required == .professional ? [.professional] : [.performer, .professional] }
    private var selectedID: String { Store.productID(plan, yearly: yearly) }
    private var hasTrial: Bool { trial(selectedID) }

    /// The line under the buy button: the price and period, with the trial first when there is one.
    private var priceLine: String {
        let p = price(plan)
        switch (hasTrial, yearly) {
        case (true, true): return String(localized: "Free trial, then \(p) a year")
        case (true, false): return String(localized: "Free trial, then \(p) a week")
        case (false, true): return String(localized: "\(p) a year")
        case (false, false): return String(localized: "\(p) a week")
        }
    }

    private func trial(_ id: String) -> Bool {
        #if DEBUG
        if Self.shotPrices { return id.hasSuffix(".weekly") }
        #endif
        return store.trialEligible.contains(id)
    }

    /// A product's price as the App Store gives it.
    private func quote(_ id: String) -> (display: String, price: Decimal, format: (Decimal) -> String)? {
        #if DEBUG
        // Screenshots: StoreKit's test products only load when run from Xcode, so `-shotprices` stands in with the real prices.
        if Self.shotPrices, let v = ["Performer.weekly": 8, "Professional.weekly": 10, "Performer.annual": 100, "Professional.annual": 120, "Professional.life": 200][id.replacingOccurrences(of: "com.tobyjones.MaestroPro.", with: "")] as Decimal? {
            let f: (Decimal) -> String = { "£" + String(format: "%.2f", NSDecimalNumber(decimal: $0).doubleValue) }
            return (f(v), v, f)
        }
        #endif
        guard let p = store.products[id] else { return nil }
        return (p.displayPrice, p.price, { $0.formatted(p.priceFormatStyle) })
    }
    #if DEBUG
    private static var shotPrices: Bool { CommandLine.arguments.contains("-shotprices") }
    #endif

    var body: some View {
        ZStack {
            PaywallBackdrop()
            ScrollView {
                VStack(spacing: 26) {
                    hero
                    periodSwitch.reveal(shown, 0.35)
                    cards.reveal(shown, 0.45)
                    featureList
                }
                .padding(.horizontal, 24)
                .padding(.top, 54)
                .padding(.bottom, 20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) { buyPanel.reveal(shown, 0.55) }
            if let welcome { WelcomeSeal(tier: welcome).transition(.opacity) }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: close) { Image(systemName: "xmark").font(.callout.weight(.bold)) }
                .buttonStyle(KeyStyle(radius: 16))
                .accessibilityLabel("Close")
                .padding(16)
                .opacity(welcome == nil && freeExit == nil ? 1 : 0)
                .disabled(freeExit != nil)
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .alert("Couldn’t Finish", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) { Button("OK") {} } message: { Text(failure ?? "") }
        .sheet(isPresented: $enteringLicence) { LicenceEntryView() }
        .task {
            withAnimation(.spring(duration: 0.9, bounce: 0.25)) { shown = true }
            if store.products.isEmpty { await store.load() }
        }
        .onChange(of: store.tier) { _, t in if t >= required, welcome == nil { celebrate(t) } }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 14) {
            Medallion(symbol: required == .professional ? "music.quarternote.3" : "music.note", animate: !reduceMotion)
                .scaleEffect(shown ? 1 : 0.4)
                .rotationEffect(.degrees(shown ? 0 : -40))
                .opacity(shown ? 1 : 0)
                .animation(.spring(duration: 1.0, bounce: 0.45), value: shown)
            Text((freeExit != nil ? String(localized: "Choose your plan") : String(localized: "\(String(localized: String.LocalizationValue(feature))) comes with \(required.name)")).uppercased())
                .font(.caption.weight(.heavy)).tracking(1.6)
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.center)
                .reveal(shown, 0.1)
            Text(required == .professional ? String(localized: "Write, revise\nand perform.") : String(localized: "Everything a\nworking musician needs."))
                .font(.custom("Baskerville", size: 38, relativeTo: .largeTitle).weight(.semibold))
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.96, blue: 0.88), Color(red: 0.93, green: 0.8, blue: 0.58)], startPoint: .top, endPoint: .bottom))
                .multilineTextAlignment(.center)
                .engraved(0.6)
                .reveal(shown, 0.18)
            Text(required == .professional
                 ? String(localized: "A full score editor, medleys built from your library, and version control through to GitHub. From first draft to final part, in one app.")
                 : String(localized: "Scores that follow you to the note, hands-free page turns, ensemble sync, recording and review. Built for rehearsal, ready for the stage."))
                .font(.callout)
                .foregroundStyle(Color(red: 0.9, green: 0.84, blue: 0.74).opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .reveal(shown, 0.26)
        }
    }

    // MARK: Plans

    private var periodSwitch: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { y in
                Button { withAnimation(.spring(duration: 0.45, bounce: 0.3)) { yearly = y } } label: {
                    HStack(spacing: 6) {
                        Text(y ? "Annually" : "Weekly")
                        if y { Text("BEST VALUE").font(.caption2.weight(.heavy)).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Theme.accent.opacity(yearly ? 0.0 : 0.22))) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(yearly == y ? Color(red: 0.2, green: 0.12, blue: 0.04) : Color(white: 0.85))
                    .padding(.vertical, 9).frame(maxWidth: .infinity)
                    .background {
                        if yearly == y { Capsule().fill(Color.clear).modifier(BrassPlate(radius: 20)).matchedGeometryEffect(id: "period", in: ns) }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(yearly == y ? .isSelected : [])
            }
        }
        .padding(4)
        .recessed(radius: 22)
        .sensoryFeedback(.selection, trigger: yearly)
    }

    private var cards: some View {
        // Side by side where there's room; stacked as rows on a phone (and the Duo's outer display).
        let rows = cardsWidth < 480
        return AnyLayout(rows ? AnyLayout(VStackLayout(spacing: 14)) : AnyLayout(HStackLayout(spacing: 12))) {
            ForEach(plans, id: \.self) { t in
                PlanCard(tier: t, price: price(t), detail: detail(t), saving: saving(t), note: !yearly && trial(Store.productID(t, yearly: false)) ? String(localized: "3-Day Free Trial Enabled") : nil, selected: plan == t, badge: t == .professional && plans.count > 1 ? String(localized: "EVERYTHING") : nil, row: rows, ns: ns)
                    .onTapGesture { withAnimation(.spring(duration: 0.45, bounce: 0.35)) { plan = t } }
                    .accessibilityAddTraits(plan == t ? [.isButton, .isSelected] : .isButton)
            }
        }
        .sensoryFeedback(.selection, trigger: plan)
        .background(GeometryReader { g in Color.clear.onChange(of: g.size.width, initial: true) { _, w in cardsWidth = w } })
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(plan.features.enumerated()), id: \.element.text) { i, f in
                HStack(spacing: 14) {
                    Image(systemName: f.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 38, height: 38)
                        .recessed(radius: 10)
                        .symbolEffect(.bounce, value: shown)
                    Text(LocalizedStringKey(f.text))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(red: 0.96, green: 0.92, blue: 0.84))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .reveal(shown, 0.55 + Double(i) * 0.06)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .padding(18)
        .modifier(LeatherPad(radius: 18))
        .animation(.spring(duration: 0.5, bounce: 0.25), value: plan)
    }

    // MARK: Buying

    private var buyPanel: some View {
        VStack(spacing: 10) {
            Button { purchase(selectedID) } label: {
                VStack(spacing: 2) {
                    Text(hasTrial ? String(localized: "Start Free Trial") : String(localized: "Get \(plan.name)"))
                        .font(.custom("Baskerville", size: 22, relativeTo: .title2).weight(.bold))
                    Text(quote(selectedID) == nil ? String(localized: "Loading price…") : priceLine)
                        .font(.caption.weight(.semibold)).opacity(0.75)
                        .contentTransition(.numericText())
                }
                .foregroundStyle(Color(red: 0.22, green: 0.13, blue: 0.03))
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .overlay { if buying == selectedID { ProgressView().tint(.black).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 18) } }
            }
            .buttonStyle(CTAStyle(animate: !reduceMotion))
            .disabled(buying != nil || quote(selectedID) == nil)
            .animation(.smooth, value: yearly)
            .animation(.smooth, value: plan)

            Button { purchase(Store.lifetimeID) } label: {
                Text(quote(Store.lifetimeID).map { String(localized: "Or get Professional for life, \($0.display) once") } ?? String(localized: "Or get Professional for life"))
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                    .overlay(alignment: .trailing) { if buying == Store.lifetimeID { ProgressView().offset(x: 26) } }
            }
            .disabled(buying != nil || quote(Store.lifetimeID) == nil)

            HStack(spacing: 18) {
                Button("Already have a licence key?") { enteringLicence = true }
                Button("Restore Purchases") { Task { buying = "restore"; await store.restore(); buying = nil } }
                Button("Terms") { openURL(URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) }
                Button("Privacy") { openURL(URL(string: "https://thecaffeinemediacompany.com/maestro-pro/privacy.html")!) }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(white: 0.75))
            Text("Cancel any time in your Apple Account settings. Subscriptions renew automatically unless cancelled at least 24 hours before the period ends.")
                .font(.caption2).foregroundStyle(Color(white: 0.6)).multilineTextAlignment(.center)
            if let freeExit {
                Button("Continue for Free", action: freeExit)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(white: 0.55))
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [Color(red: 0.08, green: 0.055, blue: 0.042).opacity(0), Color(red: 0.08, green: 0.055, blue: 0.042).opacity(0.96)], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25))
                .ignoresSafeArea()
        }
        .animation(.spring(duration: 0.4), value: plan)
    }

    private func purchase(_ id: String) {
        Task {
            buying = id
            defer { buying = nil }
            do {
                if try await store.buy(id) { celebrate(store.tier) }
            } catch {
                failure = String(localized: "The App Store couldn’t be reached. Check your connection and try again.")
            }
        }
    }

    private func celebrate(_ t: Tier) {
        withAnimation(.spring(duration: 0.6, bounce: 0.3)) { welcome = t }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            close()
        }
    }

    // MARK: Prices

    /// Straight from the App Store, so it is always the price in App Store Connect (blank until it has loaded).
    private func price(_ t: Tier) -> String {
        quote(Store.productID(t, yearly: yearly))?.display ?? "…"
    }

    /// On the annual card: what a year costs less than 52 weekly payments, in money and as a percentage.
    private func saving(_ t: Tier) -> String? {
        guard yearly, let year = quote(Store.productID(t, yearly: true)), let week = quote(Store.productID(t, yearly: false)) else { return nil }
        let full = week.price * 52, saved = full - year.price
        guard saved > 0 else { return nil }
        let percent = Int((Double(truncating: (saved / full) as NSDecimalNumber) * 100).rounded())
        return String(localized: "Save \(year.format(saved)) (\(percent)%) a year")
    }

    /// Annual shows what it comes to each month; weekly just says so.
    private func detail(_ t: Tier) -> String {
        guard let p = quote(Store.productID(t, yearly: yearly)) else { return "" }
        return yearly ? String(localized: "Billed once a year. Works out at \(p.format(p.price / 12)) a month.") : String(localized: "a week")
    }
}

// MARK: - Pieces

private struct PlanCard: View {
    let tier: Tier
    let price: String
    let detail: String
    let saving: String?
    let note: String?
    let selected: Bool
    let badge: String?
    let row: Bool
    let ns: Namespace.ID

    private var blurb: String { tier == .professional ? String(localized: "Everything, including the score editor") : String(localized: "Everything except the score editor") }

    /// One line per plan: the name and what it includes on the left, the price on the right.
    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? Theme.accent : Color(white: 0.5))
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 3) {
                Text(tier.name)
                    .font(.custom("Baskerville", size: 21, relativeTo: .title3).weight(.semibold))
                    .foregroundStyle(Color(red: 0.98, green: 0.94, blue: 0.86))
                Text(blurb).font(.caption2).foregroundStyle(Color(white: 0.62))
                Text(detail).font(.caption.weight(.semibold)).foregroundStyle(Color(white: 0.7))
                if let saving { Text(saving).font(.caption.weight(.bold)).foregroundStyle(Color(red: 0.55, green: 0.9, blue: 0.6)) }
                if selected, let note { Text(note).font(.caption.weight(.bold)).foregroundStyle(Theme.accent) }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(price)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? Theme.accent : Color(white: 0.88))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6).lineLimit(1)
        }
    }

    private var columnContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tier.name)
                    .font(.custom("Baskerville", size: 21, relativeTo: .title3).weight(.semibold))
                    .foregroundStyle(Color(red: 0.98, green: 0.94, blue: 0.86))
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.accent : Color(white: 0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            Text(price)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(selected ? Theme.accent : Color(white: 0.88))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(detail)
                .fixedSize(horizontal: false, vertical: true)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(white: 0.7))
                .contentTransition(.numericText())
            Text(blurb)
                .font(.caption2).foregroundStyle(Color(white: 0.62))
                .fixedSize(horizontal: false, vertical: true)
            if let saving {
                Text(saving).font(.caption.weight(.bold)).foregroundStyle(Color(red: 0.55, green: 0.9, blue: 0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if selected, let note {
                Text(note).font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    var body: some View {
        Group { if row { rowContent } else { columnContent } }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LeatherPad(radius: 18, pressed: !selected))
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 2)
                    .shadow(color: Theme.accent.opacity(0.5), radius: 8, y: 2)
                    .matchedGeometryEffect(id: "plan", in: ns)
            }
        }
        .overlay(alignment: .top) {
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.heavy)).tracking(1.2)
                    .foregroundStyle(Color(red: 0.22, green: 0.13, blue: 0.03))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .modifier(BrassPlate(radius: 8))
                    .offset(y: -11)
            }
        }
        .scaleEffect(selected ? 1 : 0.96)
        .opacity(selected ? 1 : 0.8)
        .contentShape(.rect)
    }
}

/// The main button: brass, breathing gently, with light running across it.
struct CTAStyle: ButtonStyle {
    let animate: Bool
    @State private var sweep = false
    @State private var breathe = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(BrassPlate(radius: 16, pressed: configuration.isPressed))
            .overlay {
                GeometryReader { g in
                    LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.35)
                        .rotationEffect(.degrees(18))
                        .offset(x: sweep ? g.size.width * 1.2 : -g.size.width * 0.5)
                        .blendMode(.overlay)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : breathe ? 1.015 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onAppear {
                guard animate else { return }
                withAnimation(.easeInOut(duration: 1.6).delay(1.2).repeatForever(autoreverses: false)) { sweep = true }
                withAnimation(.easeInOut(duration: 1.4).repeatForever()) { breathe = true }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// A brass disc with the plan's mark, and a lamp-lit ring turning round it.
struct Medallion: View {
    let symbol: String
    let animate: Bool

    var body: some View {
        // Turned by the clock, not a repeating animation: that would leak into the scale and fade it arrives with.
        TimelineView(.animation(paused: !animate)) { ctx in
            let spin = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 * 360
        ZStack {
            Circle()
                .strokeBorder(AngularGradient(colors: [Theme.accent.opacity(0), Theme.accent, Theme.accent.opacity(0)], center: .center), lineWidth: 3)
                .frame(width: 118, height: 118)
                .rotationEffect(.degrees(spin))
                .blur(radius: 0.6)
            Circle().fill(.clear).frame(width: 96, height: 96).modifier(BrassPlate(radius: 48))
            Circle().strokeBorder(Color(red: 0.45, green: 0.31, blue: 0.11).opacity(0.7), lineWidth: 1).frame(width: 80, height: 80)
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(Color(red: 0.3, green: 0.19, blue: 0.06))
                .embossed()
        }
        }
        .accessibilityHidden(true)
    }
}

/// Leather under a reading lamp that drifts, with notes rising through the light.
/// "Already have a licence key?": the key and the email it was sent to, checked online.
struct LicenceEntryView: View {
    @State private var key = ""
    @State private var checking = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Licence key", text: $key).textInputAutocapitalization(.characters)
                } footer: {
                    Text(error ?? String(localized: "Enter the key we emailed you after your payment."))
                        .foregroundStyle(error == nil ? Color.secondary : Color.red)
                }
                Section {
                    Button { redeem() } label: {
                        HStack { Text("Activate"); if checking { Spacer(); ProgressView() } }
                    }
                    .disabled(checking || key.isEmpty)
                }
            }
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle("Licence Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func redeem() {
        checking = true; error = nil
        Task {
            error = await Store.shared.redeem(key: key)
            checking = false
            if error == nil { dismiss() }
        }
    }
}

struct PaywallBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let glyphs = ["♪", "♫", "♩", "♬"]

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                LinearGradient(colors: [Color(red: 0.17, green: 0.12, blue: 0.09), Color(red: 0.06, green: 0.04, blue: 0.03)], startPoint: .top, endPoint: .bottom)
                Grain(kind: .leather, opacity: 0.4, role: .desk)
                RadialGradient(colors: [Theme.accent.opacity(0.24), .clear],
                               center: UnitPoint(x: 0.5 + 0.22 * sin(t / 4.5), y: 0.12 + 0.06 * cos(t / 6)), startRadius: 0, endRadius: 460)
                Canvas { g, size in
                    for i in 0..<16 {
                        let seed = Double(i) * 0.6180339
                        let speed = 0.035 + (seed.truncatingRemainder(dividingBy: 1)) * 0.04
                        let p = (t * speed + seed).truncatingRemainder(dividingBy: 1)
                        let x = size.width * ((seed * 7.3).truncatingRemainder(dividingBy: 1)) + 18 * sin(t * 0.8 + seed * 9)
                        let y = size.height * (1.05 - p * 1.1)
                        let fade = sin(p * .pi)
                        let glyph = Self.glyphs[i % Self.glyphs.count]
                        g.draw(Text(glyph).font(.system(size: 16 + CGFloat(i % 4) * 7)).foregroundStyle(Theme.accent.opacity(0.18 * fade)), at: CGPoint(x: x, y: y))
                    }
                }
                RadialGradient(colors: [.clear, .black.opacity(0.5)], center: .center, startRadius: 240, endRadius: 900)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// After buying: a brass seal and a welcome, with notes bursting out.
private struct WelcomeSeal: View {
    let tier: Tier
    @State private var on = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            ForEach(0..<14, id: \.self) { i in
                let a = Double(i) / 14 * 2 * .pi
                Text(["♪", "♫", "♩", "♬"][i % 4])
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent)
                    .offset(x: on ? cos(a) * 170 : 0, y: on ? sin(a) * 170 : 0)
                    .opacity(on ? 0 : 1)
                    .scaleEffect(on ? 1.4 : 0.3)
            }
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(.clear).frame(width: 110, height: 110).modifier(BrassPlate(radius: 55))
                    Image(systemName: "checkmark")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(Color(red: 0.3, green: 0.19, blue: 0.06))
                        .symbolEffect(.bounce, value: on)
                }
                .scaleEffect(on ? 1 : 0.3)
                Text("Welcome to \(tier.name)")
                    .font(.custom("Baskerville", size: 32, relativeTo: .largeTitle).weight(.semibold))
                    .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.86))
                Text("Everything is unlocked. Enjoy playing.")
                    .font(.callout).foregroundStyle(Color(white: 0.8))
            }
            .opacity(on ? 1 : 0)
        }
        .sensoryFeedback(.success, trigger: on)
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.5)) { on = true }
        }
        .animation(.easeOut(duration: 1.4), value: on)
    }
}

extension View {
    /// Rises into place, out of a blur, after a short delay.
    func reveal(_ shown: Bool, _ delay: Double) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .blur(radius: shown ? 0 : 6)
            .animation(.spring(duration: 0.8, bounce: 0.2).delay(delay), value: shown)
    }
}

#if DEBUG
/// Settings ▸ Debug: open the paywall and onboarding, and pretend to be on any plan.
struct DebugSettings: View {
    @State private var store = Store.shared
    @State private var onboarding = false
    @AppStorage("onboarded") private var onboarded = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Picker("Pretend Plan", selection: Binding { store.debugTier } set: { store.debugTier = $0 }) {
                    Text("App Store (Real)").tag(Tier?.none)
                    ForEach([Tier.free, .performer, .professional], id: \.self) { Text($0.name).tag(Tier?.some($0)) }
                }
                LabeledContent("Current Plan", value: store.tier.name)
                Button("Refresh from App Store", systemImage: "arrow.clockwise") { Task { await store.restore() } }
            } header: { Text("Plan") } footer: {
                Text("Overrides what the App Store says, in debug builds only. A -debugTier launch argument wins over this.")
            }
            Section("Paywall") {
                Button("Show Performer Paywall", systemImage: "music.note") { store.present(.performer, "The tuner") }
                Button("Show Professional Paywall", systemImage: "music.quarternote.3") { store.present(.professional, "The score editor") }
            }
            Section {
                Button("Show Onboarding", systemImage: "sparkles") { onboarding = true }
                Toggle("Onboarding Finished", isOn: $onboarded)
            } header: { Text("Onboarding") } footer: {
                Text("Turn Onboarding Finished off to see it again on the next launch.")
            }
            Section {
                Button("Factory Reset", systemImage: "trash", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Deletes every score, setting, recording, licence and saved sign-in on this device, then quits. The App Store plan is not affected, and a library kept in iCloud will come back from iCloud.")
            }
        }
        .confirmationDialog("Erase everything and quit?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Factory Reset", role: .destructive) { Self.factoryReset() }
        } message: { Text("This can't be undone.") }
        .navigationTitle("Debug")
        .fullScreenCover(isPresented: $onboarding) { OnboardingView { onboarding = false } }
    }

    /// Clears settings and every file the app keeps, then quits so nothing in memory writes them back.
    static func factoryReset() {
        let d = UserDefaults.standard
        if let id = Bundle.main.bundleIdentifier { d.removePersistentDomain(forName: id) }
        d.synchronize()
        let fm = FileManager.default
        let dirs: [URL] = [.documentsDirectory, .applicationSupportDirectory, .cachesDirectory, .temporaryDirectory]
        for dir in dirs {
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: f) }
        }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.tobyjones.PlayAlong"] as CFDictionary)   // the GitHub sign-in
        exit(0)
    }
}
#endif
