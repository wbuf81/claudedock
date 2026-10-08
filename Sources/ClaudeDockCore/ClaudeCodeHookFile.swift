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
        .appendingPathComponent("Library/Application Support/ClaudeDock")

    public init(settings: URL = defaultSettings, support: URL = defaultSupport) {
        self.settings = settings
        self.support = support
    }

    /// The real file: a symlinked settings.json is followed, so writes keep the link.
    private var target: URL { settings.resolvingSymlinksInPath() }
    private var backup: URL { support.appendingPathComponent("settings-before-connect.json") }
    private var written: URL { support.appendingPathComponent("settings-after-connect.json") }
    /// Present when settings.json didn't exist before we connected, so disconnecting deletes it again.
    private var wasMissing: URL { support.appendingPathComponent("settings-was-missing") }

    public func isConnected() -> Bool {
        guard let data = try? read(), let parsed = try? parse(data) else { return false }
        return ClaudeCodeHooks.isInstalled(parsed)
    }

    /// The settings bytes, or nil when there is no file. Any other failure (permissions…)
    /// throws: an unreadable file is not a missing one, and must never be written over.
    private func read() throws -> Data? {
        do {
            return try Data(contentsOf: target)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        } catch {
            throw HookFileError.unreadable("\(settings.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) can't be read, so Claude Dock left it alone.")
        }
    }

    public func connect() throws {
        let before = try read()
        let parsed = try parse(before)
        guard !ClaudeCodeHooks.isInstalled(parsed) else { return }
        let after = try encode(ClaudeCodeHooks.install(into: parsed))
        let fm = FileManager.default
        try fm.createDirectory(at: support, withIntermediateDirectories: true)
        try (before ?? Data()).write(to: backup, options: .atomic)
        try after.write(to: written, options: .atomic)
        if before == nil { try Data().write(to: wasMissing, options: .atomic) } else { try? fm.removeItem(at: wasMissing) }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try after.write(to: target, options: .atomic)
    }

    public func disconnect() throws {
        let fm = FileManager.default
        let current = try read()
        if let current, let mine = try? Data(contentsOf: written), mine == current {
            if fm.fileExists(atPath: wasMissing.path) {
                try fm.removeItem(at: target)
            } else if let original = try? Data(contentsOf: backup) {
                try original.write(to: target, options: .atomic)
            } else {
                try encode(ClaudeCodeHooks.remove(from: try parse(current))).write(to: target, options: .atomic)
            }
        } else {
            let parsed = try parse(current)
            if ClaudeCodeHooks.isInstalled(parsed) {
                try encode(ClaudeCodeHooks.remove(from: parsed)).write(to: target, options: .atomic)
            }
        }
        for url in [written, backup, wasMissing] { try? fm.removeItem(at: url) }
    }

    /// The settings as a dictionary; a missing or empty file is an empty one.
    private func parse(_ data: Data?) throws -> [String: Any] {
        guard let data, !String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
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
