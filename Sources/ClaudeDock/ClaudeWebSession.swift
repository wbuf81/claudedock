import AppKit
import WebKit

enum WebSessionError: Error {
    case signedOut
    case badResult
    case http(Int)
}

/// The app's own claude.ai session, kept in the app's website data store (separate from
/// Safari, Chrome and the Claude desktop app). Requests run as fetch() inside a hidden
/// claude.ai page, so they carry the session cookie and look like the site's own requests.
/// Only GET requests are ever made.
@MainActor
final class ClaudeWebSession: NSObject, WKNavigationDelegate {
    var onSignedIn: (() -> Void)?

    private static let home = URL(string: "https://claude.ai/settings/usage")!
    private static let login = URL(string: "https://claude.ai/login")!

    private let dataStore = WKWebsiteDataStore.default()
    private lazy var fetcher = makeWebView()
    private var fetcherReady = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var signInWindow: NSWindow?
    private var signInView: WKWebView?

    /// GETs a claude.ai API path and returns the response body.
    func getJSON(_ path: String) async throws -> Data {
        await loadFetcher()
        let script = """
        const r = await fetch(path, { credentials: 'include', headers: { accept: 'application/json' } });
        return { status: r.status, body: await r.text() };
        """
        let value = try await fetcher.callAsyncJavaScript(script, arguments: ["path": path], in: nil, contentWorld: .page)
        guard let result = value as? [String: Any],
              let status = (result["status"] as? NSNumber)?.intValue,
              let body = result["body"] as? String else { throw WebSessionError.badResult }
        if status == 401 || status == 403 { throw WebSessionError.signedOut }
        guard status == 200 else { throw WebSessionError.http(status) }
        return Data(body.utf8)
    }

    func showSignIn() {
        if let window = signInWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let size = NSSize(width: 520, height: 720)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let hint = NSTextField(wrappingLabelWithString: "Sign in to claude.ai once. Claude Dock only reads your usage. If Google sign-in is blocked here, use “Continue with email”.")
        hint.font = .systemFont(ofSize: 12)
        hint.frame = NSRect(x: 12, y: size.height - 46, width: size.width - 24, height: 38)
        hint.autoresizingMask = [.width, .minYMargin]
        let view = makeWebView()
        view.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height - 52)
        view.autoresizingMask = [.width, .height]
        container.addSubview(hint)
        container.addSubview(view)
        view.load(URLRequest(url: Self.login))

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Sign in to claude.ai"
        window.contentView = container
        window.isReleasedWhenClosed = false
        window.center()
        signInWindow = window
        signInView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        watchForSignIn()
    }

    /// Deletes this app's claude.ai cookies and storage.
    func signOut() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        await dataStore.removeData(ofTypes: types, for: records.filter { $0.displayName.contains("claude.ai") })
        fetcherReady = false
    }

    // MARK: Private

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 640), configuration: config)
        view.navigationDelegate = self
        return view
    }

    private func loadFetcher() async {
        guard !fetcherReady else { return }
        fetcher.load(URLRequest(url: Self.home))
        await withCheckedContinuation { waiters.append($0) }
    }

    /// The sign-in page is a web app that may not fire navigation events when it finishes,
    /// so poll for a working session every 2 seconds while the window is open.
    private func watchForSignIn() {
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(2))
                guard let self, let window = self.signInWindow, window.isVisible else {
                    self?.signInWindow = nil
                    self?.signInView = nil
                    return
                }
                if (try? await self.getJSON("/api/organizations")) != nil {
                    window.close()
                    self.signInWindow = nil
                    self.signInView = nil
                    self.onSignedIn?()
                    return
                }
            }
        }
    }

    private func finished(_ webView: WKWebView, ok: Bool) {
        guard webView === fetcher else { return }
        fetcherReady = ok
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished(webView, ok: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finished(webView, ok: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finished(webView, ok: false)
    }
}
