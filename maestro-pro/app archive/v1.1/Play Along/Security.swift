import SwiftUI
import UIKit

// Keeps the sheet music and lyrics out of screenshots and screen recordings.
// - Content is hosted inside a secure text field's canvas, which the system blanks in screenshots and
//   recordings (the same mechanism that hides a password field).
// - While the screen is being recorded the pages are replaced by a notice and playback pauses.
// ponytail: the secure canvas relies on UIKit's view structure, so it falls back to plain display if that
// changes; and nothing can stop a photo of the screen taken with another device. Export to MP4 is not affected.

enum ScreenCapture {
    /// The screen is being recorded. AirPlay to a TV or a second display also counts as capture to the system,
    /// so it's let through while an external screen is attached.
    // ponytail: a recording made while a TV is attached isn't caught; the secure canvas still blanks it.
    static var isCaptured: Bool {
        #if targetEnvironment(macCatalyst)
        return false   // AirPlay from the Mac counts as capture, and the music should show on the TV
        #else
        guard UIApplication.shared.connectedScenes.count(where: { ($0 as? UIWindowScene)?.session.role == .windowExternalDisplayNonInteractive }) == 0,
              UIScreen.screens.count < 2 else { return false }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.contains { $0.session.role == .windowApplication && $0.screen.isCaptured }
        #endif
    }
}

/// Shows its content where screenshots and recordings see nothing.
struct SecureContent<Content: View>: UIViewControllerRepresentable {
    @ViewBuilder let content: Content

    func makeUIViewController(context: Context) -> SecureHost<Content> { SecureHost(root: content) }
    func updateUIViewController(_ vc: SecureHost<Content>, context: Context) { vc.host.rootView = content }
}

/// Hands touches straight to the hosted content: the secure field around it is inert, so UIKit's own hit
/// testing would stop at it and nothing inside would respond.
final class PassThroughView: UIView {
    weak var content: UIView?
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let content else { return super.hitTest(point, with: event) }
        return content.hitTest(convert(point, to: content), with: event)
    }
}

final class SecureHost<Content: View>: UIViewController {
    override func loadView() { view = PassThroughView() }

    let host: UIHostingController<Content>
    private let field = UITextField()

    init(root: Content) {
        host = UIHostingController(rootView: root)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        host.view.backgroundColor = .clear
        addChild(host)
        #if targetEnvironment(macCatalyst)
        let canvas: UIView? = nil
        #else
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        field.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(field)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: view.topAnchor), field.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            field.leadingAnchor.constraint(equalTo: view.leadingAnchor), field.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        field.layoutIfNeeded()
        let canvas = field.subviews.first
        #endif
        let target = canvas ?? view!
        canvas?.isUserInteractionEnabled = true
        host.view.translatesAutoresizingMaskIntoConstraints = false
        target.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: target.topAnchor), host.view.bottomAnchor.constraint(equalTo: target.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: target.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: target.trailingAnchor),
        ])
        host.didMove(toParent: self)
        (view as? PassThroughView)?.content = host.view
    }
}

/// True while the screen is recorded.
@Observable final class CaptureWatcher {
    private(set) var captured = ScreenCapture.isCaptured
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []

    init() {
        for name in [UIScreen.capturedDidChangeNotification, UIScreen.didConnectNotification, UIScreen.didDisconnectNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.captured = ScreenCapture.isCaptured
            })
        }
    }
    deinit { tokens.forEach(NotificationCenter.default.removeObserver) }
}

/// What shows in place of the music while the screen is recorded.
struct RecordingNotice: View {
    var body: some View {
        ContentUnavailableView("Recording Isn’t Allowed", systemImage: "eye.slash",
                               description: Text("Music and lyrics are hidden while the screen is being recorded. Stop recording to carry on."))
    }
}

/// The time of day, in the top corner over the music and lyrics (Settings ▸ Show the Time).
struct ClockBadge: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, style: .time)
                .font(.callout.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.thinMaterial, in: .capsule)
        }
        .allowsHitTesting(false)
        .padding(10)
    }
}
