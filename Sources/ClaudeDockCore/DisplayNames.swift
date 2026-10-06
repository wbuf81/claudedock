import Foundation

/// Org names are often long and share a prefix (a company name, say), which wraps in a
/// 60 pt widget. Drop the leading words every shown org has in common, never emptying a name.
public enum DisplayNames {
    public static func short(_ orgs: [Org]) -> [Org] {
        guard orgs.count > 1 else { return orgs }
        let words = orgs.map { $0.name.split(separator: " ").map(String.init) }
        var shared = 0
        while words.allSatisfy({ shared < $0.count && $0[shared] == words[0][shared] }) { shared += 1 }
        let drop = min(shared, words.map(\.count).min()! - 1)
        guard drop > 0 else { return orgs }
        return zip(orgs, words).map { org, parts in
            var short = org
            short.name = parts.dropFirst(drop).joined(separator: " ")
            return short
        }
    }
}
