import AppKit
import WebKit
import ClaudeDockCore

/// The app's own claude.ai session, kept in the app's website data store (separate from
/// Safari, Chrome and the Claude desktop app). Requests run as fetch() inside a hidden
/// claude.ai page, so they carry the session cookie and look like the site's own requests.
/// Only GET requests are ever made.
///
/// The hidden page is a tiny claude.ai document rather than the claude.ai web app, so no
/// site scripts run all day. If the site's bot check blocks requests from it, the full
/// usage page (which can pass the check) is used instead until the app restarts.
@MainActor
final class ClaudeWebSession: NSObject, WKNavigationDelegate {
    var onSignedIn: (() -> Void)?

    private static let lightHome = URL(string: "https://claude.ai/robots.txt")!
    private static let fullHome = URL(string: "https://claude.ai/settings/usage")!
    private static let login = URL(string: "https://claude.ai/login")!

    private let dataStore = WKWebsiteDataStore.default()
    private lazy var fetcher = makeWebView()
    private var page = PageLoadState()
    private var useFullPage = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var signInWindow: NSWindow?
    private var signInView: WKWebView?

    /// GETs a claude.ai API path and returns the response body.
    func getJSON(_ path: String) async throws -> Data {
        try await loadFetcher()
        let script = """
        const r = await fetch(path, { credentials: 'include', headers: { accept: 'application/json' } });
        return { status: r.status, body: await r.text() };
        """
        let value: Any?
        do {
            value = try await fetcher.callAsyncJavaScript(script, arguments: ["path": path], in: nil, contentWorld: .page)
        } catch {
            page.invalidate()  // the page broke; load it again next time
            throw error
        }
        guard let result = value as? [String: Any],
              let status = (result["status"] as? NSNumber)?.intValue,
              let body = result["body"] as? String else { throw WebSessionError.badResult }
        switch SessionResponse.classify(status: status, body: body) {
        case .ok:
            return Data(body.utf8)
        case .signedOut:
            throw WebSessionError.signedOut
        case .forbidden:
            throw WebSessionError.forbidden
        case .blocked:
            page.invalidate()
            // The full usage page can pass the bot check; switch to it and ask again now,
            // rather than leaving the widget empty until the next refresh.
            guard !useFullPage else { throw WebSessionError.blocked }
            useFullPage = true
            return try await getJSON(path)
        case .failed(let code):
            throw WebSessionError.http(code)
        }
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
        page.invalidate()
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

    /// Loads the hidden page if needed. Callers that arrive while a load is running wait for
    /// it instead of starting another, and everyone fails fast if the load fails.
    private func loadFetcher() async throws {
        if page.isReady { return }
        if page.claimLoad() {
            fetcher.load(URLRequest(url: useFullPage ? Self.fullHome : Self.lightHome))
        }
        await withCheckedContinuation { waiters.append($0) }
        guard page.isReady else { throw WebSessionError.notReady }
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
        page.finished(ok: ok)
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

    /// macOS can end a hidden page's web process under memory pressure; reload it next time.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finished(webView, ok: false)
    }
}
