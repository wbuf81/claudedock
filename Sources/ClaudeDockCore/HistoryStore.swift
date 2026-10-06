import Foundation

/// The reading history: one JSON object per line. Corrupt lines are skipped, so a crash
/// mid-write costs one reading, not the history.
public final class HistoryStore: @unchecked Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeDock/history.jsonl")
    }

    public func append(_ readings: [Reading]) throws {
        guard !readings.isEmpty else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.lines(readings)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    public func load() -> [Reading] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            try? Self.decoder.decode(Reading.self, from: Data(line.utf8))
        }
    }

    /// Rewrites the file without readings older than `cutoff`.
    public func prune(olderThan cutoff: Date) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try Self.lines(load().filter { $0.time >= cutoff }).write(to: url, options: .atomic)
    }

    private static func lines(_ readings: [Reading]) throws -> Data {
        var data = Data()
        for reading in readings {
            data.append(try encoder.encode(reading))
            data.append(0x0A)
        }
        return data
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
