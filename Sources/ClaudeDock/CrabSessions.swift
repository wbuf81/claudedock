import CoreServices
import Foundation
import ClaudeDockCore

/// Reads the files Claude Dock's hooks write, one per Claude Code process, whenever one
/// changes. Files of processes that have exited are deleted.
final class CrabSessions: @unchecked Sendable {
    let folder: URL
    private let onChange: @Sendable ([CrabSession]) -> Void
    private let queue = DispatchQueue(label: "ClaudeDock.CrabSessions")
    private var stream: FSEventStreamRef?

    init(folder: URL = ClaudeCodeHookFile.defaultSupport.appendingPathComponent("sessions"),
         onChange: @escaping @Sendable ([CrabSession]) -> Void) {
        self.folder = folder
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        guard stream == nil else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<CrabSessions>.fromOpaque(info).takeUnretainedValue().readNow()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
        reload()
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Reads the folder again (also used by a timer, since a process can exit without a write).
    func reload() { queue.async { self.readNow() } }

    private func readNow() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var sessions: [CrabSession] = []
        for name in names {
            guard let pid = Int32(name) else { continue }   // skips "<pid>.<n>.tmp"
            let url = folder.appendingPathComponent(name)
            guard Self.isAlive(pid) else { try? FileManager.default.removeItem(at: url); continue }
            if let text = try? String(contentsOf: url, encoding: .utf8), let session = Crab.parse(text, pid: pid) {
                sessions.append(session)
            }
        }
        onChange(sessions)
    }

    /// The process exists (EPERM means it exists but isn't ours).
    static func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }
}
