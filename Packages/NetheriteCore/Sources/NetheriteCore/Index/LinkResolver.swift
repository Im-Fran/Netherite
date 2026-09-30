import Foundation

/// Resolves link targets the way Obsidian does: by file name anywhere in the vault,
/// by path when one is given, preferring the closest match to the linking note.
public struct LinkResolver: Sendable {
    /// lowercased file name (with extension) → paths
    private var byName: [String: [String]] = [:]
    private var byPath: [String: String] = [:]
    private var extensions: Set<String> = []

    public init(files: [String]) {
        for f in files {
            byName[(f as NSString).lastPathComponent.lowercased(), default: []].append(f)
            byPath[f.lowercased()] = f
            extensions.insert(f.fileExtension)
        }
    }

    public func resolve(_ target: String, from source: String) -> String? {
        var t = target.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return source }
        if t.hasPrefix("/") { t.removeFirst() }
        let candidates = t.fileExtension.isEmpty || !knownExtension(t) ? [t + ".md", t] : [t, t + ".md"]
        for c in candidates {
            let lc = c.lowercased()
            if c.contains("/") {
                if let p = byPath[lc] { return p }
                let rel = ((source.parentFolder as NSString).appendingPathComponent(c) as NSString).standardizingPath.lowercased()
                if let p = byPath[rel] { return p }
                let name = (lc as NSString).lastPathComponent
                if let p = byName[name]?.filter({ $0.lowercased().hasSuffix("/" + lc) }).min(by: { $0.count < $1.count }) { return p }
            } else if let paths = byName[lc] {
                return best(paths, from: source)
            }
        }
        return nil
    }

    private func knownExtension(_ t: String) -> Bool {
        extensions.contains(t.fileExtension)
    }

    private func best(_ paths: [String], from source: String) -> String {
        if paths.count == 1 { return paths[0] }
        let folder = source.parentFolder
        return paths.first { $0.parentFolder == folder } ?? paths.min { ($0.count, $0) < ($1.count, $1) }!
    }

    /// The shortest link text that resolves unambiguously to `path` (Obsidian's "shortest path when possible").
    public func linkText(for path: String) -> String {
        let base = path.isMarkdown ? (path as NSString).deletingPathExtension : path
        let name = (path as NSString).lastPathComponent.lowercased()
        return (byName[name]?.count ?? 0) > 1 ? base : (base as NSString).lastPathComponent
    }
}
