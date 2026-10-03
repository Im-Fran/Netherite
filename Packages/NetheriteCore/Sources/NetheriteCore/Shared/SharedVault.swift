import Foundation

/// The vault the app last opened, published through the App Group so the share extension,
/// widgets and intents can read and write the same folder.
public struct SharedVault: Codable, Hashable, Sendable {
    public var name: String
    public var path: String
    /// Minimal bookmark (iOS). On macOS bookmarks are app-specific, so extensions fall back to `path`,
    /// which works for vaults in the shared iCloud container; arbitrary folders need the app open.
    public var bookmark: Data?

    public init(name: String, path: String, bookmark: Data? = nil) {
        self.name = name; self.path = path; self.bookmark = bookmark
    }

    public static let appGroup = "group.cl.franciscosolis.netherite"
    public static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    public static func publish(_ vault: SharedVault, to d: UserDefaults? = defaults) {
        d?.set(try? JSONEncoder().encode(vault), forKey: "sharedVault")
    }

    public static func current(_ d: UserDefaults? = defaults) -> SharedVault? {
        d?.data(forKey: "sharedVault").flatMap { try? JSONDecoder().decode(SharedVault.self, from: $0) }
    }

    public static func publishRecents(_ paths: [String], to d: UserDefaults? = defaults) {
        d?.set(Array(paths.prefix(20)), forKey: "recentNotes")
    }

    public static func recents(_ d: UserDefaults? = defaults) -> [String] {
        d?.stringArray(forKey: "recentNotes") ?? []
    }

    /// The vault folder, via bookmark when it still resolves, else by path.
    /// Starts security-scoped access that is never stopped: prefer `withVault` in long-lived processes.
    public func resolve() -> Vault? {
        guard let url = folderURL() else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return Vault(root: url)
    }

    /// Runs `body` on the vault folder, holding security-scoped access only for its duration.
    /// Returns nil when the vault can't be found.
    public func withVault<T>(_ body: (Vault) throws -> T) rethrows -> T? {
        // Access is started on the resolved URL itself: it carries the security scope, `Vault.root` may not.
        guard let url = folderURL() else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try body(Vault(root: url))
    }

    private func folderURL() -> URL? {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) { return url }
        }
        return FileManager.default.fileExists(atPath: path) ? URL(filePath: path, directoryHint: .isDirectory) : nil
    }
}

public extension Vault {
    /// Appends `text` to the daily note for `date` (creating it), returning its path.
    @discardableResult
    func appendToDailyNote(_ text: String, date: Date = .now) throws -> String {
        let path = Templates.dailyNotePath(for: date, settings: settings)
        // A note that exists but can't be read must not be replaced by just the new text.
        var existing = exists(path) ? try read(path) : ""
        if !existing.isEmpty && !existing.hasSuffix("\n") { existing += "\n" }
        try write(existing + text + "\n", to: path)
        return path
    }

    /// Markdown notes whose name contains `query` (all notes when empty), most recently modified first.
    func searchTitles(_ query: String, limit: Int = 50) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let notes = allFiles().filter { $0.isMarkdown && (q.isEmpty || $0.noteName.localizedCaseInsensitiveContains(q)) }
        let dated = notes.map { p in
            (p, (try? url(for: p).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        return dated.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// First `length` characters of a note's body (frontmatter stripped).
    func excerpt(_ path: String, length: Int = 300) -> String {
        guard let text = try? read(path) else { return "" }
        let body = Frontmatter.locate(in: text).map { (text as NSString).substring(from: NSMaxRange($0.range)) } ?? text
        return String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(length))
    }
}

public extension SharedVault {
    /// `netherite://open?path=…`, built with URLComponents so `&`, `+` and `#` in names survive.
    static func openURL(path: String) -> URL {
        var c = URLComponents()
        c.scheme = "netherite"
        c.host = "open"
        c.queryItems = [URLQueryItem(name: "path", value: path)]
        // URLComponents leaves "+" as-is in queries, which some parsers read as a space.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }
}
