import SwiftUI
import WebKit

/// lyricsify.com in a browser, for Enhanced lyrics (timed word by word). The site only opens for a person in a
/// browser (it checks before showing a search or a song), so you search it yourself; the app then takes the lyrics
/// from an .lrc file you download there, or from the timed lines on the page you're looking at.
struct LyricsifyBrowser: View {
    let term: String
    let onLyrics: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var page = LyricsifyPage()
    @State private var failure: String?

    private var start: URL {
        let q = term.trimmingCharacters(in: .whitespaces)
        return URL(string: q.isEmpty ? "https://www.lyricsify.com/" : "https://www.lyricsify.com/search?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q))!
    }

    var body: some View {
        NavigationStack {
            LyricsifyWebView(url: start, page: page) { onLyrics($0) }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Lyricsify")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .navigation) {
                        Button("Back", systemImage: "chevron.backward") { page.web?.goBack() }.disabled(!page.canGoBack)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use These Lyrics") {
                            Task {
                                if let lrc = await page.timedLyrics() { onLyrics(lrc) }
                                else { failure = String(localized: "There are no timed lyrics on this page. Open a song, and choose its Enhanced or LRC lyrics.") }
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .top) {
                    Text("Search for the song, open its Enhanced (word-timed) lyrics, then tap Use These Lyrics, or download the .lrc file.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 6).padding(.horizontal)
                        .background(.bar)
                }
                .alert("No Lyrics Here", isPresented: Binding { failure != nil } set: { if !$0 { failure = nil } }) {
                    Button("OK") {}
                } message: { Text(failure ?? "") }
        }
        .pageSheet()
    }
}

/// The open page, for the toolbar to go back and read it.
@Observable final class LyricsifyPage {
    @ObservationIgnored weak var web: WKWebView?
    var canGoBack = false

    /// The timed lines on the page (and in any text boxes), as an LRC file, when there are enough to be lyrics.
    func timedLyrics() async -> String? {
        let script = "[document.body.innerText].concat(Array.from(document.querySelectorAll('textarea, pre, code')).map(e => e.value || e.textContent)).join('\\n')"
        guard let text = try? await web?.evaluateJavaScript(script) as? String else { return nil }
        return Self.lrc(in: text)
    }

    /// Lines that start with a time like [01:23.45], kept in order without repeats.
    nonisolated static func lrc(in text: String) -> String? {
        var seen = Set<String>(), lines: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.range(of: #"^\[\d{1,2}:\d{2}(?:[.:]\d{1,3})?\]"#, options: .regularExpression) != nil, seen.insert(line).inserted else { continue }
            lines.append(line)
        }
        return lines.count >= 3 ? lines.joined(separator: "\n") : nil
    }
}

private struct LyricsifyWebView: UIViewRepresentable {
    let url: URL
    let page: LyricsifyPage
    let onLyrics: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(page: page, onLyrics: onLyrics) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        page.web = web
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
        let page: LyricsifyPage
        let onLyrics: (String) -> Void
        private var saving: URL?
        init(page: LyricsifyPage, onLyrics: @escaping (String) -> Void) { self.page = page; self.onLyrics = onLyrics }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { page.canGoBack = webView.canGoBack }

        /// A lyrics file (rather than a page) is downloaded, to be read.
        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            let response = navigationResponse.response
            let disposition = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
            let isFile = disposition.lowercased().contains("attachment") || response.url?.pathExtension.lowercased() == "lrc" || !navigationResponse.canShowMIMEType
            return isFile ? .download : .allow
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
            let dest = URL.temporaryDirectory.appending(path: UUID().uuidString + "-" + suggestedFilename)
            saving = dest
            return dest
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let url = saving, let text = try? Library.readText(url) else { return }
            try? FileManager.default.removeItem(at: url)
            if LyricsifyPage.lrc(in: text) != nil { onLyrics(text) }   // the whole file, title and offset tags included
        }
    }
}
