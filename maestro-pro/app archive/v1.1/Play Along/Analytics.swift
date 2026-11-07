import Aptabase
import Foundation

/// Anonymous usage counts through Aptabase: which features get used. Never scores, titles, search words, lyrics or file
/// names; only kinds, counts and on/off choices. Events are sent a few seconds after they happen (the SDK on its own
/// only sends on a timer that starts when the app returns from the background, so a fresh launch would send nothing).
enum Analytics {
    private static var flushing = false

    static func start() {
        Aptabase.shared.initialize(appKey: "A-EU-8276562032")
        track("app_started")
    }

    static func track(_ name: String, _ props: [String: Value] = [:]) {
        Aptabase.shared.trackEvent(name, with: props)
        guard !flushing else { return }
        flushing = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            flushing = false
            Aptabase.shared.flush()
        }
    }

    /// The file kind for an event, from its extension.
    static func kind(_ url: URL) -> String { url.pathExtension.lowercased() }
}
