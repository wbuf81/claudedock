import Foundation

/// The hooks Claude Dock adds to Claude Code's settings so the crab knows what Claude Code is
/// doing. Each writes only a mood and the time to a file named after the Claude Code process
/// (`$PPID` inside a hook), and never reads the hook's input or any transcript.
public enum ClaudeCodeHooks {
    /// Marks our commands, so we find and remove exactly ours.
    public static let marker = "# claude-dock"

    /// (event, matcher, action) for every hook we add.
    static let events: [(event: String, matcher: String?, action: String)] = [
        ("SessionStart", nil, "idle"),
        ("UserPromptSubmit", nil, "thinking"),
        ("PreToolUse", "*", "tool"),
        ("PostToolUse", "*", "thinking"),
        ("Notification", "permission_prompt", "permission"),
        ("PermissionRequest", "*", "permission"),
        ("Stop", nil, "done"),
        ("SessionEnd", nil, "end"),
    ]

    /// The shell command for one action: a mood, or "end" to delete the session's file.
    public static func command(_ action: String) -> String {
        let folder = #"d="$HOME/Library/Application Support/ClaudeDock/sessions""#
        let body = action == "end"
            ? #"rm -f "$d/$PPID" || true"#
            : #"mkdir -p "$d" && printf '%s %s\n' \#(action) "$(date +%s)" > "$d/$PPID.$$.tmp" && mv -f "$d/$PPID.$$.tmp" "$d/$PPID" || true"#
        return "cat >/dev/null; \(folder); \(body) \(marker)"
    }

    public static func isInstalled(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { groups in (groups as? [[String: Any]] ?? []).contains(where: isOurs) }
    }

    /// `settings` with our hooks added after any already there. Installing twice changes nothing.
    public static func install(into settings: [String: Any]) -> [String: Any] {
        var result = remove(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for entry in events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command(entry.action)]]]
            if let matcher = entry.matcher { group["matcher"] = matcher }
            hooks[entry.event] = (hooks[entry.event] as? [[String: Any]] ?? []) + [group]
        }
        result["hooks"] = hooks
        return result
    }

    /// `settings` without our hooks; events and the "hooks" key we emptied are removed too.
    public static func remove(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        var result = settings
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]], groups.contains(where: isOurs) else { continue }
            let kept = groups.filter { !isOurs($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        result["hooks"] = hooks.isEmpty && !((settings["hooks"] as? [String: Any])?.isEmpty ?? false) ? nil : hooks
        return result
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.hasSuffix(marker) == true }
    }
}
