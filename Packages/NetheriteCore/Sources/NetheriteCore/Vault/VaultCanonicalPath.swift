import Foundation

extension Vault {
    /// The path as spelled on disk (and so in the index), or nil when nothing is there.
    /// Each component matches exactly or, failing that, ignoring case: APFS finds `inbox.md` for `Inbox.md`,
    /// so `exists` can't tell a path the index knows from another spelling of it.
    public func canonicalPath(_ path: String) -> String? {
        var parts: [String] = []
        for c in Self.normalize(path).split(separator: "/").map(String.init) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: url(for: parts.joined(separator: "/")).path(percentEncoded: false)),
                  let name = names.first(where: { $0 == c }) ?? names.first(where: { $0.caseInsensitiveCompare(c) == .orderedSame })
            else { return nil }
            parts.append(name)
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    /// Whether a file or folder exists with exactly this spelling (case included, already normalized).
    public func existsExactly(_ path: String) -> Bool { canonicalPath(path) == path }
}
