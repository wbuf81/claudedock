import Foundation
import Testing
@testable import ClaudeDockCore

func tempFile(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("claudedock-tests-\(UUID().uuidString)")
        .appendingPathComponent(name)
}

@Suite struct HistoryStoreTests {
    let a = reading(org: "pikachu", week: 55, weekResetsAt: local(2026, 10, 9, 4), session: 1,
                    sessionResetsAt: local(2026, 10, 6, 16, 20), scoped: ["Fable": 31])
    let b = reading(org: "charizard", week: 0, weekResetsAt: nil)

    @Test func roundTrips() throws {
        let store = HistoryStore(url: tempFile("history.jsonl"))
        try store.append([a, b])
        #expect(store.load() == [a, b])
        try store.append([a])
        #expect(store.load().count == 3)
    }

    @Test func usesTheSpecKeys() throws {
        let store = HistoryStore(url: tempFile("history.jsonl"))
        try store.append([a])
        let line = try String(contentsOf: store.url, encoding: .utf8)
        for key in ["\"t\":", "\"org\":", "\"session\":", "\"sessionResetsAt\":", "\"week\":", "\"weekResetsAt\":", "\"scoped\":"] {
            #expect(line.contains(key))
        }
    }

    @Test func skipsCorruptLines() throws {
        let store = HistoryStore(url: tempFile("history.jsonl"))
        try store.append([a])
        let handle = try FileHandle(forWritingTo: store.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("garbage{\n".utf8))
        try handle.close()
        try store.append([b])
        #expect(store.load() == [a, b])
    }

    @Test func prunesOldReadings() throws {
        let store = HistoryStore(url: tempFile("history.jsonl"))
        let old = reading(week: 10, weekResetsAt: nil, at: designNow.addingTimeInterval(-40 * 86_400))
        try store.append([old, a])
        try store.prune(olderThan: designNow.addingTimeInterval(-35 * 86_400))
        #expect(store.load() == [a])
    }

    @Test func missingFileLoadsEmpty() {
        #expect(HistoryStore(url: tempFile("none.jsonl")).load().isEmpty)
    }
}

@Suite struct ClaudeCodeAccountTests {
    func write(_ text: String) throws -> URL {
        let url = tempFile("claude.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func readsTheOrg() throws {
        let url = try write(#"{"numStartups": 3, "oauthAccount": {"organizationUuid": "00000000-0000-4000-8000-000000000001", "organizationName": "Pikachu"}}"#)
        #expect(ClaudeCodeAccount(url: url).currentOrg() == "00000000-0000-4000-8000-000000000001")
        #expect(ClaudeCodeAccount(url: url).modified() != nil)
    }

    @Test func missingOrMalformedMeansUnknown() throws {
        #expect(ClaudeCodeAccount(url: tempFile("absent.json")).currentOrg() == nil)
        #expect(ClaudeCodeAccount(url: try write("{not json")).currentOrg() == nil)
        #expect(ClaudeCodeAccount(url: try write(#"{"oauthAccount": {}}"#)).currentOrg() == nil)
    }
}
