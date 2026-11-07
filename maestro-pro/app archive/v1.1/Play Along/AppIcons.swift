import SwiftUI
import UIKit

/// The icons the app can wear. The pictures and asset sets are drawn by `Tools/make-icons.swift`; each set has light, dark and
/// tinted versions that the Home Screen picks from the system's appearance.
struct AppIconTheme: Identifiable {
    let id: String, name: String, group: String
    /// The asset set to switch to; the original icon is the primary one and has no name.
    var set: String? { id == "Leather" ? nil : "Icon-" + id }
    var preview: Image { Image("IconPreview-" + id) }

    static let all: [AppIconTheme] = [
        .init(id: "Leather", name: "Leather", group: "Classic"), .init(id: "Paper", name: "Paper", group: "Classic"),
        .init(id: "Midnight", name: "Midnight", group: "Classic"), .init(id: "Brass", name: "Brass", group: "Classic"),
        .init(id: "Sunset", name: "Sunset", group: "Classic"), .init(id: "Forest", name: "Forest", group: "Classic"),
        .init(id: "UnionFlag", name: "Union Flag", group: "Flags and Pride"), .init(id: "Pride", name: "Pride", group: "Flags and Pride"),
        .init(id: "TransPride", name: "Trans Pride", group: "Flags and Pride"),
        .init(id: "Piano", name: "Piano", group: "Instruments"), .init(id: "Organ", name: "Organ", group: "Instruments"),
        .init(id: "Guitar", name: "Acoustic Guitar", group: "Instruments"), .init(id: "Bass", name: "Bass", group: "Instruments"),
        .init(id: "Flute", name: "Flute", group: "Instruments"), .init(id: "Clarinet", name: "Clarinet", group: "Instruments"),
        .init(id: "AltoSax", name: "Alto Saxophone", group: "Instruments"), .init(id: "TenorSax", name: "Tenor Saxophone", group: "Instruments"),
        .init(id: "Trumpet", name: "Trumpet", group: "Instruments"),
    ]
    static let groups = ["Classic", "Flags and Pride", "Instruments"]
}

/// Settings ▸ App Icon: a grid of the icons, grouped, with the current one ticked.
struct AppIconPicker: View {
    @State private var current = UIApplication.shared.alternateIconName
    @State private var failure: String?

    /// Mac Catalyst keeps one Dock icon, so there is nothing to choose there.
    static var available: Bool { UIApplication.shared.supportsAlternateIcons }

    var body: some View {
        Section {
            ForEach(AppIconTheme.groups, id: \.self) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringKey(group)).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], alignment: .leading, spacing: 14) {
                        ForEach(AppIconTheme.all.filter { $0.group == group }) { theme in
                            Button { choose(theme) } label: {
                                VStack(spacing: 5) {
                                    theme.preview.resizable().scaledToFit().frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(current == theme.set ? Color.accentColor : .primary.opacity(0.18), lineWidth: current == theme.set ? 3 : 1))
                                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                                    Text(LocalizedStringKey(theme.name)).font(.caption2).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.center)
                                }
                                .frame(width: 84)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(theme.name + " icon")
                            .accessibilityAddTraits(current == theme.set ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
        } header: { Text("App Icon") } footer: {
            Text("Each icon has a light, a dark and a tinted look, so it follows your Home Screen style. iPadOS tells you when the icon changes.")
        }
    }

    private func choose(_ theme: AppIconTheme) {
        Analytics.track("app_icon_changed")
        UIApplication.shared.setAlternateIconName(theme.set) { error in
            Task { @MainActor in
                if let error { failure = error.localizedDescription } else { failure = nil; current = theme.set }
            }
        }
    }
}
