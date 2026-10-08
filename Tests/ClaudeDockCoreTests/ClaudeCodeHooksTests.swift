import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct ClaudeCodeHooksTests {
    /// Another status app's hooks on some of the same events.
    let theirs: [String: Any] = [
        "model": "opus",
        "hooks": [
            "Stop": [["hooks": [["type": "command", "command": "node other/update.js stop"]]]],
            "PreToolUse": [["matcher": "*", "hooks": [["type": "command", "command": "node other/update.js pre"]]]],
        ],
    ]

    func same(_ a: [String: Any], _ b: [String: Any]) -> Bool { NSDictionary(dictionary: a).isEqual(to: b) }

    @Test func commandsWriteOnlyTheMoodAndTime() {
        let tool = ClaudeCodeHooks.command("tool")
        #expect(tool.hasPrefix("cat >/dev/null;"))
        #expect(tool.contains("printf '%s %s\\n' tool"))
        #expect(tool.contains("$PPID"))
        #expect(tool.hasSuffix(ClaudeCodeHooks.marker))
        // A failed write must never show as a hook error in Claude Code.
        #expect(tool.hasSuffix("|| true \(ClaudeCodeHooks.marker)"))
        #expect(tool.contains("Application Support/ClaudeDock/sessions"))
        #expect(!tool.contains("Claude Dock"))
        #expect(ClaudeCodeHooks.command("end").contains("rm -f"))
        // Parallel hooks of one session must not share a temporary name.
        #expect(tool.contains(#""$d/$PPID.$$.tmp" && mv -f "$d/$PPID.$$.tmp""#))
    }

    @Test func installsIntoNothing() {
        let installed = ClaudeCodeHooks.install(into: [:])
        let hooks = installed["hooks"] as! [String: Any]
        #expect(Set(hooks.keys) == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                     "Notification", "PermissionRequest", "Stop", "SessionEnd"])
        let notification = (hooks["Notification"] as! [[String: Any]])[0]
        #expect(notification["matcher"] as? String == "permission_prompt")
        #expect(ClaudeCodeHooks.isInstalled(installed))
        #expect(!ClaudeCodeHooks.isInstalled([:]))
    }

    // Review focus: other apps' hooks stay, in order, and come back untouched.
    @Test func keepsOtherHooksAndRemovesCleanly() {
        let installed = ClaudeCodeHooks.install(into: theirs)
        let stop = (installed["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        #expect(stop.count == 2)
        #expect(((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as? String) == "node other/update.js stop")
        #expect(installed["model"] as? String == "opus")
        #expect(same(ClaudeCodeHooks.remove(from: installed), theirs))
        #expect(same(ClaudeCodeHooks.remove(from: ClaudeCodeHooks.install(into: [:])), [:]))
    }

    @Test func installingTwiceAddsNothing() {
        let once = ClaudeCodeHooks.install(into: theirs)
        #expect(same(ClaudeCodeHooks.install(into: once), once))
    }

    // MARK: The file on disk

    func temp() -> (settings: URL, support: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir.appendingPathComponent("settings.json"), dir.appendingPathComponent("support"))
    }

    @Test func connectThenDisconnectIsByteIdentical() throws {
        let (settings, support) = temp()
        let original = Data("{\n    \"model\" : \"opus\",   \"hooks\": {}\n}\n".utf8)
        try original.write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        #expect(file.isConnected())
        try file.disconnect()
        #expect(!file.isConnected())
        #expect(try Data(contentsOf: settings) == original)
    }

    @Test func disconnectAfterOtherEditsKeepsThem() throws {
        let (settings, support) = temp()
        try Data("{}".utf8).write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        var edited = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        edited["model"] = "sonnet"
        try JSONSerialization.data(withJSONObject: edited).write(to: settings)
        try file.disconnect()
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        #expect(after["model"] as? String == "sonnet")
        #expect(!ClaudeCodeHooks.isInstalled(after))
    }

    @Test func missingOrEmptyFileCountsAsEmpty() throws {
        let (settings, support) = temp()
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        #expect(file.isConnected())
        try Data().write(to: settings)
        try file.connect()
        #expect(file.isConnected())
    }

    // Review focus: JSON with comments or trailing commas must not be overwritten.
    @Test func refusesAFileItCantRead() throws {
        let (settings, support) = temp()
        let original = Data("{ \"model\": \"opus\", // mine\n }".utf8)
        try original.write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        #expect(throws: HookFileError.self) { try file.connect() }
        #expect(try Data(contentsOf: settings) == original)
        #expect(!file.isConnected())
    }

    // An unreadable file is not a missing one: never write over it, never delete it.
    @Test func leavesAnUnreadableFileAlone() throws {
        let (settings, support) = temp()
        let original = Data("{ \"model\": \"opus\" }".utf8)
        try original.write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: settings.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: settings.path) }
        guard (try? Data(contentsOf: settings)) == nil else { return }   // running as root: can't test
        #expect(throws: HookFileError.self) { try file.connect() }
        #expect(throws: HookFileError.self) { try file.disconnect() }
        #expect(!file.isConnected())
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: settings.path)
        #expect(try Data(contentsOf: settings) == original)
    }

    @Test func disconnectingNeverConnectedChangesNothing() throws {
        let (settings, support) = temp()
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.disconnect()
        #expect(!FileManager.default.fileExists(atPath: settings.path))
        let original = Data("{\n  \"model\":   \"opus\"\n}".utf8)
        try original.write(to: settings)
        try file.disconnect()
        #expect(try Data(contentsOf: settings) == original)
    }

    @Test func missingFileComesBackMissing() throws {
        let (settings, support) = temp()
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        #expect(FileManager.default.fileExists(atPath: settings.path))
        try file.disconnect()
        #expect(!FileManager.default.fileExists(atPath: settings.path))
    }

    @Test func followsASymlinkedSettingsFile() throws {
        let (settings, support) = temp()
        let other = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let real = other.appendingPathComponent("real.json")
        let original = Data("{ \"model\": \"opus\" }".utf8)
        try original.write(to: real)
        try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: real)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: settings.path)) != nil)
        let parsed = try JSONSerialization.jsonObject(with: Data(contentsOf: real)) as! [String: Any]
        #expect(ClaudeCodeHooks.isInstalled(parsed))
        try file.disconnect()
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: settings.path)) != nil)
        #expect(try Data(contentsOf: real) == original)
    }
}
