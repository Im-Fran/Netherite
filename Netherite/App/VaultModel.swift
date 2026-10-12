import SwiftUI
import NetheriteCore

/// State for one open vault, shared by all windows showing it.
@MainActor @Observable
final class VaultModel {
    let vault: Vault
    let index: VaultIndex
    var settings: VaultSettings { didSet { if settings != oldValue { vault.saveConfig("app.json", settings) } } }
    private(set) var themes: [Theme] = []
    /// The vault's chosen theme, as stored (what publishing and "Create Theme from Current" use).
    var vaultTheme: Theme { themes.first { $0.name == settings.theme } ?? .netherite }
    /// The theme as drawn on this device, after the Accessibility preferences.
    var theme: Theme { A11y.shared.apply(vaultTheme) }
    private(set) var recentFiles: [String] {
        didSet {
            vault.saveConfig("recent.json", recentFiles)
            SharedVault.publishRecents(recentFiles, vault: AppModel.key(vault.root))
        }
    }
    private(set) var dirty: Set<String> = []
    var bookmarks: [Bookmark] = [] { didSet { vault.saveConfig("bookmarks.json", bookmarks) } }
    private var saveTasks: [String: Task<Void, Never>] = [:]
    private var watcher: VaultWatcher?
    /// Windows showing this vault, so file operations and external changes update every one of them.
    @ObservationIgnored private let windows = NSHashTable<WindowState>.weakObjects()
    /// Windows not in the background; the watcher runs while there is at least one.
    @ObservationIgnored private var foregroundWindows = Set<ObjectIdentifier>()
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
        // A file moved or deleted outside this window must not be recreated at its old path.
        guard !isGone(path) else { return }
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
        guard dirty.contains(path), !isGone(path), let text = index.notes[path]?.text else { return }
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
        // Files moved or deleted outside Netherite: drop their unsaved edits (warning about them) and close them.
        let lost = dirty.filter(isGone)
        for p in lost { saveTasks[p]?.cancel(); saveTasks[p] = nil; dirty.remove(p) }
        if let p = lost.first {
            lastError = String(localized: "“\(p.noteName)” was moved or deleted outside Netherite, so its latest changes weren’t saved.")
        }
        guard index.isLoaded else { return }
        let files = Set(index.files)
        for pane in panes { pane.removeMissing(files) }
    }

    /// The file was moved or deleted (paths are only known once the index has loaded).
    private func isGone(_ path: String) -> Bool { index.isLoaded && !index.files.contains(path) }

    func refresh() async { await externalChange() }

    func register(_ window: WindowState) { windows.add(window) }

    private var panes: [Pane] { windows.allObjects.flatMap(\.panes) }

    /// Observes the vault folder while any of its windows is in the foreground
    /// (iOS suspends apps holding file presenters in the background), catching up on resume.
    func window(_ window: WindowState, isForeground: Bool) {
        let id = ObjectIdentifier(window)
        if isForeground { foregroundWindows.insert(id) } else { foregroundWindows.remove(id) }
        let wanted = !foregroundWindows.isEmpty
        guard let watcher, watcher.isWatching != wanted else { return }
        watcher.isWatching = wanted
        if wanted { Task { await externalChange() } }
    }

    // MARK: File operations

    func noteDidOpen(_ path: String) {
        recentFiles = Array(([path] + recentFiles.filter { $0 != path }).prefix(50))
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
        // Line breaks (pasted into a title or rename field) must never reach the file name.
        let clean = newName.split(whereSeparator: \.isNewline).joined(separator: " ")
            .replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
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
        // Drops can carry any text, and a folder can't go inside itself.
        guard index.files.contains(path) || index.folders.contains(path), !target.hasPrefix(path + "/") else { return nil }
        guard !vault.exists(target) || target.lowercased() == path.lowercased() else {
            lastError = String(localized: "A file named “\(target.noteName)” already exists.")
            return nil
        }
        // Flush unsaved edits of the item and, for folders, of every note inside it.
        for p in dirty where p == path || p.hasPrefix(path + "/") { save(p) }
        let result: String? = perform { try index.move(path, to: target); return target }
        if result != nil {
            recentFiles = recentFiles.map { $0 == path || $0.hasPrefix(path + "/") ? target + $0.dropFirst(path.count) : $0 }
            for pane in panes { pane.replacePaths(from: path, to: target) }
        }
        return result
    }

    func trash(_ path: String) {
        // Once trashed, drop pending saves of the item and anything inside it, or they'd recreate the trashed files.
        // If trashing fails they stay, so the edits are still saved.
        guard perform({ try index.trash(path) }) != nil else { return }
        for p in dirty where p == path || p.hasPrefix(path + "/") { saveTasks[p]?.cancel(); saveTasks[p] = nil; dirty.remove(p) }
        recentFiles.removeAll { $0 == path || $0.hasPrefix(path + "/") }
        for pane in panes { pane.removePath(path) }
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
