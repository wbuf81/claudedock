import CoreServices
import Foundation

/// Notices Claude Code working: while it runs it appends to its transcripts in
/// `~/.claude/projects` every few seconds. Watches that folder with FSEvents and reports only
/// *that* a transcript changed, and when. It never opens the files.
public final class ClaudeCodeActivity: @unchecked Sendable {
    public let folder: URL
    private let onActivity: @Sendable (Date) -> Void
    private let queue = DispatchQueue(label: "ClaudeDock.ClaudeCodeActivity")
    private var stream: FSEventStreamRef?

    public init(folder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects"),
                onActivity: @escaping @Sendable (Date) -> Void) {
        self.folder = folder
        self.onActivity = onActivity
    }

    deinit { stop() }

    /// Starts watching. A folder that doesn't exist (Claude Code never ran) reports nothing.
    public func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ClaudeCodeActivity>.fromOpaque(info).takeUnretainedValue()
            let changed = Unmanaged<NSArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            if changed.contains(where: { $0.hasSuffix(".jsonl") }) { watcher.onActivity(Date()) }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        // Up to a second's latency: FSEvents batches a busy second's writes into one report.
        guard let stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
