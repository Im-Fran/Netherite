import SwiftUI
import NetheriteCore

/// State for one open vault, shared by all windows showing it.
@MainActor @Observable
final class VaultModel {
    let vault: Vault
    let index: VaultIndex
    var settings: VaultSettings { didSet { if settings != oldValue { vault.saveConfig("app.json", settings) } } }
    private(set) var themes: [Theme] = []
    var theme: Theme { themes.first { $0.name == settings.theme } ?? .netherite }
    private(set) var recentFiles: [String]
    private(set) var dirty: Set<String> = []
    var bookmarks: [Bookmark] = [] { didSet { vault.saveConfig("bookmarks.json", bookmarks) } }
    private var saveTasks: [String: Task<Void, Never>] = [:]
    private var watcher: VaultWatcher?
    var lastError: String?

    init(vault: Vault) {
        self.vault = vault
        index = VaultIndex(vault: vault)
        settings = vault.settings
        recentFiles = vault.loadConfig("recent.json", fallback: [String]())
        themes = vault.themes()
        bookmarks = vault.loadConfig("bookmarks.json", fallback: [Bookmark]())
        Task.detached { [vault] in vault.downloadPlaceholders() }
        Task {
            await index.load()
            SystemIntegration.reindex(self)
            NetheriteShortcuts.updateAppShortcutParameters()
        }
        watcher = VaultWatcher(url: vault.root) { [weak self] in
            Task { @MainActor in await self?.externalChange() }
        }
    }

    var name: String { vault.name }

    func reloadThemes() { themes = vault.themes() }

    // MARK: Editing and saving

    func text(of path: String) -> String {
        index.notes[path]?.text ?? (try? vault.read(path)) ?? ""
    }

    /// Updates the index immediately and writes to disk after a short pause in typing.
    func edit(_ path: String, text: String) {
        index.update(path, text: text)
        dirty.insert(path)
        saveTasks[path]?.cancel()
        saveTasks[path] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.save(path)
        }
    }

    func save(_ path: String) {
        saveTasks[path]?.cancel(); saveTasks[path] = nil
        guard dirty.contains(path), let text = index.notes[path]?.text else { return }
        do {
            try vault.write(text, to: path)
            dirty.remove(path)
            SystemIntegration.noteSaved(self)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func flushAll() { for p in dirty { save(p) } }

    private func externalChange() async {
        Task.detached { [vault = self.vault] in vault.downloadPlaceholders() }
        await index.refreshFromDisk(skipping: dirty)
    }

    func refresh() async { await externalChange() }

    /// Stops observing the vault folder (iOS suspends apps holding file presenters in the background).
    func suspendWatching() { watcher?.isWatching = false }

    /// Resumes observing and picks up whatever changed while suspended.
    func resumeWatching() {
        guard let watcher, !watcher.isWatching else { return }
        watcher.isWatching = true
        Task { await externalChange() }
    }

    // MARK: File operations

    func noteDidOpen(_ path: String) {
        recentFiles.removeAll { $0 == path }
        recentFiles.insert(path, at: 0)
        if recentFiles.count > 50 { recentFiles.removeLast(recentFiles.count - 50) }
        vault.saveConfig("recent.json", recentFiles)
        SharedVault.publishRecents(recentFiles)
    }

    @discardableResult
    func newNote(in folder: String? = nil, named name: String? = nil, content: String = "") -> String? {
        perform {
            try index.createNote(in: folder ?? settings.newNoteFolder,
                                 named: name ?? String(localized: "Untitled", comment: "Default new note name"), content: content)
        }
    }

    @discardableResult
    func newFolder(in folder: String = "") -> String? {
        perform { try index.createFolder(in: folder, named: String(localized: "Untitled", comment: "Default new note name")) }
    }

    /// Renames the file's base name (keeping extension/folder); returns the new path.
    @discardableResult
    func rename(_ path: String, to newName: String) -> String? {
        let clean = newName.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }
        let ext = path.fileExtension
        let isFolder = index.folders.contains(path)
        let file = isFolder || ext.isEmpty ? clean : "\(clean).\(ext)"
        let target = path.parentFolder.isEmpty ? file : "\(path.parentFolder)/\(file)"
        return move(path, to: target)
    }

    @discardableResult
    func move(_ path: String, to target: String) -> String? {
        guard target != path else { return path }
        guard !vault.exists(target) || target.lowercased() == path.lowercased() else {
            lastError = String(localized: "A file named “\(target.noteName)” already exists.")
            return nil
        }
        // Flush unsaved edits of the item and, for folders, of every note inside it.
        for p in dirty where p == path || p.hasPrefix(path + "/") { save(p) }
        let result: String? = perform { try index.move(path, to: target); return target }
        if result != nil { recentFiles = recentFiles.map { $0 == path ? target : $0 } }
        return result
    }

    func trash(_ path: String) {
        // Drop pending saves of the item and anything inside it, or they'd recreate the trashed files.
        for p in dirty where p == path || p.hasPrefix(path + "/") { saveTasks[p]?.cancel(); saveTasks[p] = nil; dirty.remove(p) }
        _ = perform { try index.trash(path) }
        recentFiles.removeAll { $0 == path || $0.hasPrefix(path + "/") }
    }

    /// Writes new content for a file (not via the editor) and reindexes it.
    func overwrite(_ path: String, with text: String) {
        do {
            try vault.write(text, to: path)
            if !index.files.contains(path) { index.didCreate(path) }
            else if path.isMarkdown { index.update(path, text: text) }
        } catch { lastError = error.localizedDescription }
    }

    /// Saves binary data (attachments, recordings) into the attachment folder; returns its vault path.
    func saveAttachment(_ data: Data, name: String, ext: String) -> String? {
        let path = vault.availablePath(folder: settings.attachmentFolder, base: name, ext: ext)
        do { try vault.write(data, to: path); index.didCreate(path); return path } catch { lastError = error.localizedDescription; return nil }
    }

    private func perform<T>(_ body: () throws -> T) -> T? {
        do { return try body() } catch { lastError = error.localizedDescription; return nil }
    }

    /// `[[link]]` text for a path relative to the active note.
    func linkText(to path: String) -> String {
        let t = index.resolver.linkText(for: path)
        return settings.useWikilinks ? "[[\(t)]]" : "[\(path.noteName)](\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path))"
    }
}

/// Watches the vault folder (including iCloud updates) through file coordination.
nonisolated final class VaultWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let onChange: @Sendable () -> Void
    private var pending: DispatchWorkItem?

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        presentedItemURL = url
        self.onChange = onChange
        super.init()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        NSFileCoordinator.addFilePresenter(self)
    }

    deinit { if isWatching { NSFileCoordinator.removeFilePresenter(self) } }

    /// Registers/unregisters the presenter with file coordination. Main-thread only.
    var isWatching = true {
        didSet {
            guard isWatching != oldValue else { return }
            if isWatching { NSFileCoordinator.addFilePresenter(self) } else { NSFileCoordinator.removeFilePresenter(self) }
        }
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func presentedItemDidChange() { changed() }
    func presentedSubitemDidChange(at url: URL) { changed() }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { changed() }
    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        changed()
        completionHandler(nil)
    }
}
