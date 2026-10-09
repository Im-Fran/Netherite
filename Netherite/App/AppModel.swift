import SwiftUI
import NetheriteCore

struct RecentVault: Codable, Hashable, Identifiable {
    var name: String
    var path: String
    var bookmark: Data?
    var lastOpened: Date
    var id: String { path }
    var isInICloud: Bool { path.contains("/Mobile Documents/") }
}

/// App-wide state: known vaults and the open `VaultModel`s shared by every window of the same vault.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    nonisolated static let iCloudContainer = "iCloud.cl.franciscosolis.netherite"

    private(set) var recents: [RecentVault] = []
    private(set) var open: [String: VaultModel] = [:]
    /// Size and sync state of known vaults, keyed by path (refreshed by `refreshStorage`).
    private(set) var storage: [String: VaultStorage] = [:]
    /// Progress and time left of each vault's current iCloud transfers, measured across `refreshStorage` calls.
    private(set) var syncProgress: [String: SyncProgress] = [:]
    /// Vaults in Recently Deleted (refreshed by `refreshTrash`).
    private(set) var trashed: [VaultTrash.Item] = []
    /// Where a vault moved (into iCloud), so windows showing it follow it instead of closing.
    private(set) var relocated: [String: String] = [:]
    /// The launch preference is applied once, to the first window.
    var launchApplied = false
    var lastError: String?

    private init() {
        if let data = UserDefaults.standard.data(forKey: "recentVaults"),
           let r = try? JSONDecoder().decode([RecentVault].self, from: data) {
            // Rebasing can make two entries (same vault, old containers) collide: keep the newest.
            var seen = Set<String>()
            recents = r.map { var v = $0; v.path = Self.rebased(v.path); return v }
                .sorted { $0.lastOpened > $1.lastOpened }
                .filter { seen.insert($0.path).inserted }
        }
    }

    var lastVaultPath: String? { recents.max { $0.lastOpened < $1.lastOpened }?.path }

    /// Vault to show on launch, per Settings › General (also in the system Settings app on iOS); "" is the start page.
    var launchVaultPath: String {
        switch UserDefaults.standard.string(forKey: "launchBehavior") {
        case "picker": ""
        case "vault": UserDefaults.standard.string(forKey: "launchVaultPath").flatMap { p in recents.first { $0.path == p }?.path } ?? lastVaultPath ?? ""
        default: lastVaultPath ?? ""
        }
    }

    // MARK: iCloud

    /// `…/Mobile Documents/iCloud~cl~franciscosolis~netherite/Documents`, or nil when iCloud is off / unsigned build.
    nonisolated static func iCloudDocuments() async -> URL? {
        await Task.detached {
            FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainer)?.appending(path: "Documents", directoryHint: .isDirectory)
        }.value
    }

    /// Local fallback location for new vaults.
    nonisolated static var localDocuments: URL { URL.documentsDirectory }

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

    /// iOS moves the app's data container on reinstall and update, so absolute paths inside it go stale;
    /// rebase them onto the current container. Paths elsewhere (iCloud Drive, picked folders) are unchanged.
    nonisolated static func rebased(_ path: String) -> String {
        #if os(iOS)
        let marker = "/Containers/Data/Application/"
        guard let r = path.range(of: marker), let slash = path[r.upperBound...].firstIndex(of: "/") else { return path }
        return key(URL.homeDirectory) + path[slash...]
        #else
        return path
        #endif
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
        if let m = open[key] { publishShared(url); touch(url, bookmark: bookmark); return m }
        // Returns false for folders that need no security scope (app container, iCloud); only unreadable ones are an error.
        if !url.startAccessingSecurityScopedResource() && !FileManager.default.isReadableFile(atPath: key) {
            lastError = String(localized: "Netherite can’t access “\(url.lastPathComponent)”. Open the folder again to grant access.")
        }
        publishShared(url)
        let model = VaultModel(vault: Vault(root: url))
        open[key] = model
        touch(url, bookmark: bookmark ?? makeBookmark(url))
        return model
    }

    /// Reopens a vault by path, resolving its security-scoped bookmark when needed.
    func model(forPath raw: String) -> VaultModel? {
        let path = Self.rebased(Self.key(URL(filePath: raw)))
        if let m = open[path] { return m }
        guard let recent = recents.first(where: { $0.path == path }) else {
            return FileManager.default.fileExists(atPath: path) ? openVault(at: URL(filePath: path)) : nil
        }
        if let data = recent.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: bookmarkResolveOptions, relativeTo: nil, bookmarkDataIsStale: &stale) {
                // A stale bookmark may point to the folder's new location: replace the old entry, don't duplicate it.
                if Self.key(url) != path { recents.removeAll { $0.path == path } }
                return openVault(at: url, bookmark: stale ? nil : data)
            }
        }
        return FileManager.default.fileExists(atPath: path) ? openVault(at: URL(filePath: path)) : nil
    }

    func forget(_ recent: RecentVault) {
        recents.removeAll { $0.id == recent.id }
        persist()
    }

    // MARK: Managing vaults

    /// Folders Netherite creates vaults in; their vaults can go to Recently Deleted.
    nonisolated static func vaultParents() async -> [URL] {
        [await iCloudDocuments(), localDocuments].compactMap { $0 }
    }

    private func close(_ path: String) {
        open[path]?.flushAll()
        open[path] = nil
    }

    /// Moves a vault to Recently Deleted (permanently deleted after 90 days). Vaults in folders Netherite didn't
    /// create go to the system Trash on the Mac; on iOS those can only be removed from the list.
    func trashVault(_ recent: RecentVault) async throws {
        let url = URL(filePath: recent.path, directoryHint: .isDirectory)
        let parents = await Self.vaultParents().map(Self.key)
        if parents.contains(Self.key(url.deletingLastPathComponent())) {
            close(recent.path)
            _ = try await Task.detached { try VaultTrash.trash(url) }.value
        } else {
            #if os(macOS)
            close(recent.path)
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            #else
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: String(localized: "“\(recent.name)” is in a folder Netherite didn’t create. Remove it from the list, then delete the folder in the Files app.")])
            #endif
        }
        forget(recent)
        await refreshTrash()
    }

    /// Permanently deletes vaults trashed over 90 days ago and reloads Recently Deleted.
    func refreshTrash() async {
        let parents = await Self.vaultParents()
        trashed = await Task.detached {
            VaultTrash.purge(in: parents)
            return VaultTrash.items(in: parents)
        }.value
        publishSettingsSummary()
    }

    func restore(_ item: VaultTrash.Item) async throws {
        let url = try await Task.detached { try VaultTrash.restore(item) }.value
        touch(url, bookmark: makeBookmark(url))
        await refreshTrash()
    }

    func deleteForever(_ item: VaultTrash.Item) async throws {
        try await Task.detached { try VaultTrash.delete(item) }.value
        await refreshTrash()
    }

    /// Moves a vault stored on this device into iCloud Drive; the system uploads it from there.
    func moveToICloud(_ recent: RecentVault) async throws {
        guard let docs = await Self.iCloudDocuments() else { throw Self.iCloudUnavailable }
        let source = URL(filePath: recent.path, directoryHint: .isDirectory)
        let target = docs.appending(path: Vault(root: docs).availablePath(folder: "", base: recent.name, ext: ""), directoryHint: .isDirectory)
        close(recent.path)
        try await Task.detached {
            try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            try FileManager.default.setUbiquitous(true, itemAt: source, destinationURL: target)
        }.value
        recents.removeAll { $0.path == recent.path }
        relocated[recent.path] = Self.key(target)
        touch(target, bookmark: makeBookmark(target))
        await refreshStorage([Self.key(target)])
    }

    /// Copies a folder picked in Files/Finder into iCloud Drive as a new vault, and opens it.
    func importFolderToICloud(_ source: URL) async throws -> VaultModel {
        guard let docs = await Self.iCloudDocuments() else { throw Self.iCloudUnavailable }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let path = try await Task.detached { () throws -> String in
            try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
            return try Vault(root: docs).importItems([source], into: "")[0]
        }.value
        return openVault(at: docs.appending(path: path, directoryHint: .isDirectory))
    }

    private static var iCloudUnavailable: CocoaError {
        CocoaError(.ubiquitousFileUnavailable, userInfo: [NSLocalizedDescriptionKey: String(localized: "iCloud Drive isn’t available. Sign in to iCloud and turn on iCloud Drive for Netherite.")])
    }

    /// Rescans the size and sync state of the given vaults (every known vault by default).
    func refreshStorage(_ paths: [String]? = nil) async {
        let paths = paths ?? recents.map(\.path)
        let results = await Task.detached {
            paths.map { p in (p, FileManager.default.isReadableFile(atPath: p) ? VaultStorage.scan(URL(filePath: p, directoryHint: .isDirectory)) : nil) }
        }.value
        for (p, s) in results {
            storage[p] = s
            syncProgress[p, default: SyncProgress()].record(pending: s?.pendingBytes ?? 0)
        }
        publishSettingsSummary()
    }

    /// The info rows of Netherite's page in the system Settings app (iOS) read these defaults.
    private func publishSettingsSummary() {
        let known = recents.compactMap { r in storage[r.path].map { (r, $0) } }
        func summary(_ list: [(RecentVault, VaultStorage)]) -> String {
            "\(list.count) · " + list.reduce(Int64(0)) { $0 + $1.1.bytes }.formatted(.byteCount(style: .file))
        }
        let d = UserDefaults.standard
        d.set(summary(known.filter { $0.0.isInICloud }), forKey: "info.icloud")
        d.set(summary(known.filter { !$0.0.isInICloud }), forKey: "info.local")
        d.set("\(trashed.count)", forKey: "info.trash")
        d.set(Self.versionString, forKey: "info.version")
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))"
    }

    /// Where a vault lives, for people: sandbox paths mean nothing on iOS, so name the place instead;
    /// the Mac shows the folder path, abbreviated against the real home folder (the sandbox's home is the container).
    static func displayLocation(_ path: String) -> String {
        #if os(iOS)
        if path.contains("/Mobile Documents/") { return String(localized: "iCloud Drive") }
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return String(localized: "On This iPhone")
        case .pad: return String(localized: "On This iPad")
        default: return String(localized: "On This Device")
        }
        #else
        guard let pw = getpwuid(getuid()) else { return path }
        let home = String(cString: pw.pointee.pw_dir)
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        #endif
    }

    func touch(_ url: URL, bookmark: Data?) {
        let path = Self.key(url)
        var r = recents.first { $0.path == path } ?? RecentVault(name: url.lastPathComponent, path: path, bookmark: nil, lastOpened: .now)
        r.lastOpened = .now
        if let bookmark { r.bookmark = bookmark }
        recents.removeAll { $0.path == path }
        recents.insert(r, at: 0)
        persist()
    }

    /// Extensions, widgets and intents read the most recently opened vault from the App Group.
    /// The bookmark is made after security-scoped access starts, or it comes back nil on iOS.
    private func publishShared(_ url: URL) {
        SharedVault.publish(SharedVault(name: url.lastPathComponent, path: Self.key(url),
                                        bookmark: try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)))
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
