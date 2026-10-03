import Foundation

/// A vault is a plain folder of Markdown files. Paths are always vault-relative and "/"-separated.
public struct Vault: Sendable, Hashable {
    public let root: URL
    public static let configFolder = ".netherite"

    public init(root: URL) { self.root = root.standardizedFileURL }

    public var name: String { root.lastPathComponent }
    public var configURL: URL { root.appending(path: Self.configFolder, directoryHint: .isDirectory) }

    public func url(for path: String) -> URL {
        path.isEmpty ? root : root.appending(path: path)
    }

    public func relativePath(of url: URL) -> String {
        let base = root.path(percentEncoded: false)
        let full = url.standardizedFileURL.path(percentEncoded: false)
        guard full.hasPrefix(base) else { return url.lastPathComponent }
        return String(full.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: Listing

    /// All files (not folders) in the vault, skipping hidden entries such as `.netherite` or `.obsidian`.
    public func allFiles() -> [String] {
        entries().filter { !$0.isFolder }.map(\.path)
    }

    public func entries() -> [(path: String, isFolder: Bool)] {
        guard let e = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var out: [(String, Bool)] = []
        for case let url as URL in e {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            // iCloud placeholders look like ".Name.md.icloud" and are skipped as hidden files;
            // `startDownloadingUbiquitousItem` is triggered by the app for those.
            out.append((relativePath(of: url), isDir))
        }
        return out.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
    }

    /// Asks iCloud to download evicted files (shown on disk as hidden `.Name.md.icloud` placeholders).
    public func downloadPlaceholders() {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsPackageDescendants]) else { return }
        for case let url as URL in e where url.pathExtension == "icloud" && url.lastPathComponent.hasPrefix(".") {
            let name = String(url.deletingPathExtension().lastPathComponent.dropFirst())
            try? FileManager.default.startDownloadingUbiquitousItem(at: url.deletingLastPathComponent().appending(path: name))
        }
    }

    // MARK: Reading and writing (coordinated, so iCloud and other apps stay consistent)

    public func read(_ path: String) throws -> String {
        var result: Result<String, Error> = .failure(CocoaError(.fileReadUnknown))
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url(for: path), options: [], error: &coordError) { u in
            result = Result { try String(contentsOf: u, encoding: .utf8) }
        }
        if let coordError { throw coordError }
        return try result.get()
    }

    public func readData(_ path: String) throws -> Data {
        try Data(contentsOf: url(for: path))
    }

    public func write(_ text: String, to path: String) throws {
        try write(Data(text.utf8), to: path)
    }

    public func write(_ data: Data, to path: String) throws {
        let target = url(for: path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var result: Result<Void, Error> = .success(())
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordError) { u in
            result = Result { try data.write(to: u, options: .atomic) }
        }
        if let coordError { throw coordError }
        try result.get()
    }

    public func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: path).path(percentEncoded: false))
    }

    /// Returns `folder/base.ext`, or `folder/base 1.ext`, `base 2.ext`… when taken.
    public func availablePath(folder: String, base: String, ext: String = "md") -> String {
        func make(_ n: Int) -> String {
            let name = n == 0 ? base : "\(base) \(n)"
            let file = ext.isEmpty ? name : "\(name).\(ext)"
            return folder.isEmpty ? file : "\(folder)/\(file)"
        }
        var n = 0
        while exists(make(n)) { n += 1 }
        return make(n)
    }

    @discardableResult
    public func createNote(in folder: String = "", named base: String = "Untitled", content: String = "") throws -> String {
        let path = availablePath(folder: folder, base: base)
        try write(content, to: path)
        return path
    }

    @discardableResult
    public func createFolder(in folder: String = "", named base: String = "Untitled") throws -> String {
        let path = availablePath(folder: folder, base: base, ext: "")
        try FileManager.default.createDirectory(at: url(for: path), withIntermediateDirectories: true)
        return path
    }

    public func move(_ from: String, to: String) throws {
        let src = url(for: from), dst = url(for: to)
        try FileManager.default.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        var result: Result<Void, Error> = .success(())
        var coordError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: src, options: .forMoving, writingItemAt: dst, options: .forReplacing, error: &coordError) { s, d in
            result = Result { try FileManager.default.moveItem(at: s, to: d) }
        }
        if let coordError { throw coordError }
        try result.get()
    }

    /// Vault-local trash (Obsidian's convention), used where the system Trash isn't available (iOS).
    public static let trashFolder = ".trash"

    /// Moves to the system Trash when possible; otherwise into the vault's `.trash` folder. Never deletes.
    public func trash(_ path: String) throws {
        do { try FileManager.default.trashItem(at: url(for: path), resultingItemURL: nil) }
        catch { try moveToVaultTrash(path) }
    }

    /// Moves a file or folder into `.trash` (hidden, so never listed or indexed), renaming on clashes.
    @discardableResult
    public func moveToVaultTrash(_ path: String) throws -> String {
        let name = (path as NSString).lastPathComponent as NSString
        let target = availablePath(folder: Self.trashFolder, base: name.deletingPathExtension, ext: name.pathExtension)
        try move(path, to: target)
        return target
    }
}

public extension String {
    /// "Folder/Note.md" → "Note"
    var noteName: String { ((self as NSString).lastPathComponent as NSString).deletingPathExtension }
    /// "Folder/Note.md" → "Folder" ("" at root)
    var parentFolder: String { (self as NSString).deletingLastPathComponent }
    var fileExtension: String { (self as NSString).pathExtension.lowercased() }
    var isMarkdown: Bool { fileExtension == "md" }
}
