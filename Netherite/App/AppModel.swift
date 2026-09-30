import SwiftUI
import NetheriteCore

struct RecentVault: Codable, Hashable, Identifiable {
    var name: String
    var path: String
    var bookmark: Data?
    var lastOpened: Date
    var id: String { path }
}

/// App-wide state: known vaults and the open `VaultModel`s shared by every window of the same vault.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    nonisolated static let iCloudContainer = "iCloud.cl.franciscosolis.netherite"

    private(set) var recents: [RecentVault] = []
    private(set) var open: [String: VaultModel] = [:]
    var lastError: String?

    private init() {
        if let data = UserDefaults.standard.data(forKey: "recentVaults"),
           let r = try? JSONDecoder().decode([RecentVault].self, from: data) { recents = r }
    }

    var lastVaultPath: String? { recents.max { $0.lastOpened < $1.lastOpened }?.path }

    // MARK: iCloud

    /// `…/Mobile Documents/iCloud~cl~franciscosolis~netherite/Documents`, or nil when iCloud is off / unsigned build.
    nonisolated static func iCloudDocuments() async -> URL? {
        await Task.detached {
            FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainer)?.appending(path: "Documents", directoryHint: .isDirectory)
        }.value
    }

    /// Local fallback location for new vaults.
    static var localDocuments: URL { URL.documentsDirectory }

    // MARK: Opening

    func createVault(named name: String, in parent: URL) throws -> VaultModel {
        let url = parent.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let vault = Vault(root: url)
        if vault.allFiles().isEmpty {
            try vault.write(String(localized: "welcome.note", defaultValue: """
            # Welcome to Netherite

            This is your new vault — a folder of plain Markdown files.

            - Create a note with ⌘N and link it with [[double brackets]].
            - Press ⌘O to jump to any note and ⌘P for every command.
            - Add #tags, callouts and $math$ as you go.

            > [!tip] Your notes are yours
            > Everything lives in this folder, readable by any app.
            """), to: String(localized: "Welcome", comment: "Welcome note file name") + ".md")
        }
        return openVault(at: url)
    }

    /// Canonical key for a vault folder (no trailing slash).
    nonisolated static func key(_ url: URL) -> String {
        var p = url.standardizedFileURL.path(percentEncoded: false)
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// Creates (or reopens) the guide vault in the user's language and opens its start note.
    func createGuideVault(in parent: URL) throws -> VaultModel {
        let spanish = Locale.current.language.languageCode?.identifier == "es"
        let url = parent.appending(path: spanish ? "Guía de Netherite" : "Netherite Guide", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try GuideVault.write(to: Vault(root: url), spanish: spanish)
        let model = openVault(at: url)
        model.noteDidOpen(GuideVault.startNote(spanish: spanish))
        return model
    }

    @discardableResult
    func openVault(at url: URL, bookmark: Data? = nil) -> VaultModel {
        let key = Self.key(url)
        // Extensions, widgets and intents read the most recently opened vault from the App Group.
        SharedVault.publish(SharedVault(name: url.lastPathComponent, path: key,
                                        bookmark: try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)))
        if let m = open[key] { touch(url, bookmark: bookmark); return m }
        _ = url.startAccessingSecurityScopedResource()
        let model = VaultModel(vault: Vault(root: url))
        open[key] = model
        touch(url, bookmark: bookmark ?? makeBookmark(url))
        return model
    }

    /// Reopens a vault by path, resolving its security-scoped bookmark when needed.
    func model(forPath raw: String) -> VaultModel? {
        let path = Self.key(URL(filePath: raw))
        if let m = open[path] { return m }
        guard let recent = recents.first(where: { $0.path == path }) else {
            return FileManager.default.fileExists(atPath: path) ? openVault(at: URL(filePath: path)) : nil
        }
        if let data = recent.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: bookmarkResolveOptions, relativeTo: nil, bookmarkDataIsStale: &stale) {
                return openVault(at: url, bookmark: stale ? nil : data)
            }
        }
        return FileManager.default.fileExists(atPath: path) ? openVault(at: URL(filePath: path)) : nil
    }

    func forget(_ recent: RecentVault) {
        recents.removeAll { $0.id == recent.id }
        persist()
    }

    private func touch(_ url: URL, bookmark: Data?) {
        let path = Self.key(url)
        var r = recents.first { $0.path == path } ?? RecentVault(name: url.lastPathComponent, path: path, bookmark: nil, lastOpened: .now)
        r.lastOpened = .now
        if let bookmark { r.bookmark = bookmark }
        recents.removeAll { $0.path == path }
        recents.insert(r, at: 0)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(recents) { UserDefaults.standard.set(data, forKey: "recentVaults") }
    }

    private func makeBookmark(_ url: URL) -> Data? {
        #if os(macOS)
        try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
    }

    private var bookmarkResolveOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        .withSecurityScope
        #else
        []
        #endif
    }
}
