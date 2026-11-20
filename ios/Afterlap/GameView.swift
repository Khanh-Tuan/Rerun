import SwiftUI
import WebKit

/// Shows the bundled game (web/index.html) full-screen in a WKWebView.
/// The game is plain HTML/JS and runs entirely from files inside the app.
struct GameView: UIViewRepresentable {
    private static let background = UIColor(red: 7 / 255, green: 9 / 255, blue: 24 / 255, alpha: 1)

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.websiteDataStore = .default() // keeps best score, stars and skins between launches

        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = Self.background
        web.scrollView.backgroundColor = Self.background
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsLinkPreview = false
        web.navigationDelegate = context.coordinator

        if let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") {
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    /// Opens any outside link in Safari instead of inside the game.
    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url,
               action.navigationType == .linkActivated,
               url.scheme == "http" || url.scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
