import Foundation

/// Which org Claude Code is signed into. Reads one field from Claude Code's config file
/// and nothing else.
public struct ClaudeCodeAccount: Sendable {
    public var url: URL

    public init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")) {
        self.url = url
    }

    public func currentOrg() -> String? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any] else { return nil }
        return account["organizationUuid"] as? String
    }

    public func modified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
