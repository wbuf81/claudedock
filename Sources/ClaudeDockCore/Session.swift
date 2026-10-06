import Foundation

/// How the app should treat a claude.ai response.
public enum SessionResponse: Equatable, Sendable {
    case ok
    /// 401: the session is gone.
    case signedOut
    /// 403 with a JSON error: the session may be gone, or just this org's access.
    case forbidden
    /// 403 with a web page: a bot check, not a sign-out.
    case blocked
    case failed(Int)

    public static func classify(status: Int, body: String) -> SessionResponse {
        switch status {
        case 200: return .ok
        case 401: return .signedOut
        case 403:
            let first = body.first(where: { !$0.isWhitespace })
            return first == "{" || first == "[" ? .forbidden : .blocked
        default: return .failed(status)
        }
    }
}

/// Whether the hidden claude.ai page can run requests. One load at a time; anything that
/// breaks the page (a crashed web process, a failed script) sends it back to needing a load.
public struct PageLoadState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable { case needsLoad, loading, ready }

    public private(set) var phase: Phase = .needsLoad

    public init() {}

    public var isReady: Bool { phase == .ready }

    /// True when the caller should start a load; false while one is running or the page is ready.
    public mutating func claimLoad() -> Bool {
        guard phase == .needsLoad else { return false }
        phase = .loading
        return true
    }

    public mutating func finished(ok: Bool) { phase = ok ? .ready : .needsLoad }

    public mutating func invalidate() { phase = .needsLoad }
}
