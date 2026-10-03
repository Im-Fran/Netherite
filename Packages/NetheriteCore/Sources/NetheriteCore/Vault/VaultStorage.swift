import Foundation

/// iCloud state of a whole vault folder, as shown next to every vault.
public enum SyncStatus: Sendable, Hashable {
    /// Not in iCloud (stored on this device or in a picked folder).
    case local
    /// In iCloud, but some files haven't started uploading yet.
    case pending
    /// Files are uploading or downloading right now.
    case syncing
    /// Every file is uploaded and up to date.
    case synced

    /// One file's ubiquity state, read from its URL resource values.
    public struct File: Sendable {
        public var isUbiquitous: Bool
        public var isUploaded: Bool
        public var isUploading: Bool
        public var isDownloading: Bool

        public init(isUbiquitous: Bool, isUploaded: Bool = true, isUploading: Bool = false, isDownloading: Bool = false) {
            self.isUbiquitous = isUbiquitous
            self.isUploaded = isUploaded
            self.isUploading = isUploading
            self.isDownloading = isDownloading
        }
    }

    /// Combines file states: any transfer wins, then anything waiting, otherwise synced.
    /// `folderIsUbiquitous` decides an empty vault (nothing to sync, but it does live in iCloud).
    public static func combine(_ files: [File], folderIsUbiquitous: Bool) -> SyncStatus {
        guard folderIsUbiquitous || files.contains(where: \.isUbiquitous) else { return .local }
        let cloud = files.filter(\.isUbiquitous)
        if cloud.contains(where: { $0.isUploading || $0.isDownloading }) { return .syncing }
        if cloud.contains(where: { !$0.isUploaded }) { return .pending }
        return .synced
    }
}

/// Size, file count and sync state of a vault folder, from one walk of the folder.
public struct VaultStorage: Sendable, Hashable {
    public var bytes: Int64
    public var files: Int
    public var notes: Int
    public var status: SyncStatus

    private static let keys: Set<URLResourceKey> = [
        .isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey, .isUbiquitousItemKey,
        .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey, .ubiquitousItemIsDownloadingKey,
    ]

    /// Walks the folder (hidden files included: they sync and take space too). Call off the main thread.
    public static func scan(_ root: URL) -> VaultStorage {
        var out = VaultStorage(bytes: 0, files: 0, notes: 0, status: .local)
        var states: [SyncStatus.File] = []
        let rootDepth = root.standardizedFileURL.pathComponents.count
        let folderIsUbiquitous = (try? root.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) ?? false
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]) else {
            return out
        }
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: keys), v.isDirectory != true else { continue }
            out.bytes += Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0)
            // Evicted iCloud files appear as hidden `.Name.md.icloud` placeholders: count the real file.
            let name = url.pathExtension == "icloud" ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
            let inHiddenFolder = url.deletingLastPathComponent().pathComponents.dropFirst(rootDepth).contains { $0.hasPrefix(".") }
            if !inHiddenFolder && (!name.hasPrefix(".") || url.pathExtension == "icloud") {
                out.files += 1
                if name.lowercased().hasSuffix(".md") { out.notes += 1 }
            }
            states.append(.init(isUbiquitous: v.isUbiquitousItem ?? false, isUploaded: v.ubiquitousItemIsUploaded ?? true,
                                isUploading: v.ubiquitousItemIsUploading ?? false, isDownloading: v.ubiquitousItemIsDownloading ?? false))
        }
        out.status = SyncStatus.combine(states, folderIsUbiquitous: folderIsUbiquitous)
        return out
    }
}

/// App-level trash for whole vaults: a hidden `.netherite-trash` folder next to the vaults, emptied after 90 days.
/// Moving within the same parent keeps it cheap and, in iCloud, removes the vault from every device.
public enum VaultTrash {
    public static let folderName = ".netherite-trash"
    public static let retentionDays = 90

    public struct Item: Sendable, Hashable, Identifiable {
        public var url: URL
        public var name: String
        public var deletedAt: Date
        public var id: URL { url }

        public func expires(after days: Int = VaultTrash.retentionDays) -> Date { deletedAt.addingTimeInterval(Double(days) * 86_400) }
    }

    /// Moves `vault` to `<parent>/.netherite-trash/<unix time> <name>`; returns the new location.
    @discardableResult
    public static func trash(_ vault: URL, now: Date = .now) throws -> URL {
        let parent = Vault(root: vault.deletingLastPathComponent())
        let target = parent.availablePath(folder: folderName, base: "\(Int(now.timeIntervalSince1970)) \(vault.lastPathComponent)", ext: "")
        try parent.move(vault.lastPathComponent, to: target)
        return parent.url(for: target)
    }

    /// Trashed vaults in each parent folder, newest first.
    public static func items(in parents: [URL]) -> [Item] {
        parents.flatMap { parent -> [Item] in
            let dir = parent.appending(path: folderName, directoryHint: .isDirectory)
            let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            return urls.compactMap { u in
                let parts = u.lastPathComponent.split(separator: " ", maxSplits: 1)
                guard parts.count == 2, let t = Double(parts[0]) else { return nil }
                return Item(url: u, name: String(parts[1]), deletedAt: Date(timeIntervalSince1970: t))
            }
        }.sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Moves a trashed vault back next to the other vaults (renamed if the name is taken); returns its folder.
    @discardableResult
    public static func restore(_ item: Item) throws -> URL {
        let parent = Vault(root: item.url.deletingLastPathComponent().deletingLastPathComponent())
        let target = parent.availablePath(folder: "", base: item.name, ext: "")
        try parent.move(parent.relativePath(of: item.url), to: target)
        return parent.url(for: target)
    }

    public static func delete(_ item: Item) throws {
        var result: Result<Void, Error> = .success(())
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: item.url, options: .forDeleting, error: &coordError) { u in
            result = Result { try FileManager.default.removeItem(at: u) }
        }
        if let coordError { throw coordError }
        try result.get()
    }

    /// Permanently deletes vaults trashed more than `days` ago.
    public static func purge(in parents: [URL], olderThan days: Int = retentionDays, now: Date = .now) {
        for item in items(in: parents) where item.expires(after: days) < now { try? delete(item) }
    }
}

public extension Vault {
    /// Copies a note, file or folder (`""` = the whole vault) into `directory` for exporting.
    /// Folders become a `.zip` (made by file coordination, like the Files app); files are copied as they are.
    func exportArchive(_ path: String, to directory: URL) throws -> URL {
        let source = url(for: path)
        let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let name = path.isEmpty ? self.name : (path as NSString).lastPathComponent
        let target = directory.appending(path: isFolder ? "\(name).zip" : name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        var result: Result<Void, Error> = .success(())
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: source, options: isFolder ? .forUploading : [], error: &coordError) { u in
            result = Result { try FileManager.default.copyItem(at: u, to: target) }
        }
        if let coordError { throw coordError }
        try result.get()
        return target
    }

    /// Copies files or folders from outside the vault into `folder`, renaming on clashes. Returns the new paths.
    @discardableResult
    func importItems(_ urls: [URL], into folder: String) throws -> [String] {
        try FileManager.default.createDirectory(at: url(for: folder), withIntermediateDirectories: true)
        return try urls.map { source in
            let name = source.lastPathComponent as NSString
            let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let path = availablePath(folder: folder, base: isFolder ? name as String : name.deletingPathExtension,
                                     ext: isFolder ? "" : name.pathExtension)
            var result: Result<Void, Error> = .success(())
            var coordError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordError) { u in
                result = Result { try FileManager.default.copyItem(at: u, to: url(for: path)) }
            }
            if let coordError { throw coordError }
            try result.get()
            return path
        }
    }
}
