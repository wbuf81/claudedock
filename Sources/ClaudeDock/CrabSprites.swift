import AppKit

/// The crab's animation frames, read once from the app bundle (`Contents/Resources/crab`), or
/// from the repo's `Resources/crab` when run with `swift run` from the repo.
@MainActor
enum CrabSprites {
    static let frameCount = 24
    static let frameDuration: CFTimeInterval = 0.07

    private static var cache: [String: [CGImage]] = [:]

    static func frames(_ mood: String) -> [CGImage] {
        if let cached = cache[mood] { return cached }
        let loaded = (0..<frameCount).compactMap { index -> CGImage? in
            let name = String(format: "%02d.png", index)
            guard let folder = folder?.appendingPathComponent(mood),
                  let image = NSImage(contentsOf: folder.appendingPathComponent(name)) else { return nil }
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        cache[mood] = loaded.count == frameCount ? loaded : []
        return cache[mood]!
    }

    private static let folder: URL? = {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("crab"),
           FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/crab")
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }()
}
