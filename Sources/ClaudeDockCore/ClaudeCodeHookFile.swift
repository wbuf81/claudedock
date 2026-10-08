import Foundation

public enum HookFileError: Error, Equatable {
    /// Claude Code's settings file isn't plain JSON (comments, trailing commas…): we leave it alone.
    case unreadable(String)
}

/// Connects and disconnects Claude Dock's hooks in `~/.claude/settings.json`. Before the first
/// change it keeps a backup, and remembers exactly what it wrote: disconnecting before anyone
/// else changed the file puts the original bytes back.
public struct ClaudeCodeHookFile: Sendable {
    public var settings: URL
    public var support: URL

    public static let defaultSettings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    public static let defaultSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude Dock")

    public init(settings: URL = defaultSettings, support: URL = defaultSupport) {
        self.settings = settings
        self.support = support
    }

    private var backup: URL { support.appendingPathComponent("settings-before-connect.json") }
    private var written: URL { support.appendingPathComponent("settings-after-connect.json") }

    public func isConnected() -> Bool { (try? read()).map(ClaudeCodeHooks.isInstalled) ?? false }

    public func connect() throws {
        let before = (try? Data(contentsOf: settings)) ?? Data()
        let parsed = try read()
        guard !ClaudeCodeHooks.isInstalled(parsed) else { return }
        let after = try encode(ClaudeCodeHooks.install(into: parsed))
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try before.write(to: backup, options: .atomic)
        try after.write(to: written, options: .atomic)
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try after.write(to: settings, options: .atomic)
    }

    public func disconnect() throws {
        let current = (try? Data(contentsOf: settings)) ?? Data()
        if let mine = try? Data(contentsOf: written), mine == current, let original = try? Data(contentsOf: backup) {
            try original.write(to: settings, options: .atomic)
        } else {
            try encode(ClaudeCodeHooks.remove(from: try read())).write(to: settings, options: .atomic)
        }
        try? FileManager.default.removeItem(at: written)
        try? FileManager.default.removeItem(at: backup)
    }

    /// The settings as a dictionary; a missing or empty file is an empty one.
    private func read() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settings),
              !String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data), let dictionary = object as? [String: Any] else {
            throw HookFileError.unreadable("\(settings.lastPathComponent) isn't plain JSON, so Claude Dock left it alone.")
        }
        return dictionary
    }

    private func encode(_ dictionary: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}
