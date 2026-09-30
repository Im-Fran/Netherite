import SwiftUI
import TipKit
import TipKit
import NetheriteCore

/// Something a pane can show.
enum Destination: Hashable, Codable {
    case note(String)
    case file(String)
    case canvas(String)
    case base(String)
    case graph
    case localGraph(String)
    case web(URL)

    init(path: String) {
        switch path.fileExtension {
        case "md": self = .note(path)
        case "canvas": self = .canvas(path)
        case "base": self = .base(path)
        default: self = .file(path)
        }
    }

    var path: String? {
        switch self {
        case .note(let p), .file(let p), .canvas(let p), .base(let p): p
        default: nil
        }
    }

    var title: String {
        switch self {
        case .graph: String(localized: "Graph View")
        case .localGraph(let p): String(localized: "Local Graph: \(p.noteName)")
        case .web(let url): url.host() ?? url.absoluteString
        default: path.map { $0.isMarkdown ? $0.noteName : ($0 as NSString).lastPathComponent } ?? ""
        }
    }

    var symbolName: String {
        switch self {
        case .graph: "point.3.connected.trianglepath.dotted"
        case .localGraph: "circle.hexagongrid"
        case .web: "globe"
        default: symbol(for: path ?? "")
        }
    }

    func renamed(from old: String, to new: String) -> Destination {
        if case .localGraph(let p) = self, p == old { return .localGraph(new) }
        guard let p = path, p == old || p.hasPrefix(old + "/") else { return self }
        return Destination(path: new + p.dropFirst(old.count))
    }
}

/// A navigation stack shown in the editor area. Windows have one or two (split) panes.
@MainActor @Observable
final class Pane: Identifiable {
    let id = UUID()
    private(set) var history: [Destination] = []
    private(set) var position = -1
    var reading = false
    /// Line to scroll to / select after opening (heading or block links, search results).
    var pendingLine: Int?

    var current: Destination? { history.indices.contains(position) ? history[position] : nil }
    var canGoBack: Bool { position > 0 }
    var canGoForward: Bool { position < history.count - 1 }

    func open(_ d: Destination, line: Int? = nil) {
        pendingLine = line
        if current == d { return }
        history = Array(history.prefix(position + 1)) + [d]
        position = history.count - 1
    }

    func back() { if canGoBack { position -= 1; pendingLine = nil } }
    func forward() { if canGoForward { position += 1; pendingLine = nil } }

    func replacePaths(from old: String, to new: String) {
        history = history.map { $0.renamed(from: old, to: new) }
    }

    func removePath(_ path: String) {
        let before = current
        history.removeAll { $0.path == path || ($0.path?.hasPrefix(path + "/") ?? false) }
        position = min(max(0, history.firstIndex { $0 == before } ?? history.count - 1), history.count - 1)
    }
}

enum SidebarTab: String, CaseIterable, Identifiable, Codable {
    case files, search, bookmarks, tags
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .files: "Files"
        case .search: "Search"
        case .bookmarks: "Bookmarks"
        case .tags: "Tags"
        }
    }
    var symbol: String {
        switch self {
        case .files: "folder"
        case .search: "magnifyingglass"
        case .bookmarks: "bookmark"
        case .tags: "number"
        }
    }
}

enum ActiveSheet: Identifiable {
    case quickSwitcher, commandPalette, settings, rename(String), templates, importer, publish, workspaces, recovery(String), audio, merge(String), openURL
    var id: String {
        switch self {
        case .rename(let p): "rename:\(p)"
        case .recovery(let p): "recovery:\(p)"
        case .merge(let p): "merge:\(p)"
        default: "\(self)"
        }
    }
}

/// Per-window UI state.
@MainActor @Observable
final class WindowState {
    let model: VaultModel
    var panes: [Pane]
    var focusedPaneID: UUID
    var sidebarTab: SidebarTab = .files
    /// Open by default on the Mac; on iPhone/iPad the inspector is a sheet/overlay, so start closed.
    #if os(macOS)
    var showInspector = true
    #else
    var showInspector = false
    #endif
    var columnVisibility: NavigationSplitViewVisibility = .all
    var sheet: ActiveSheet? {
        didSet {
            switch sheet {
            case .quickSwitcher: NetheriteTips.donate(NetheriteTips.quickSwitcherUsed)
            case .commandPalette: NetheriteTips.donate(NetheriteTips.commandPaletteUsed)
            default: break
            }
        }
    }
    var searchQuery = ""
    var explorerSelection: String?
    var presentingSlides = false
    /// Toolbar tips shown one at a time, in this order.
    @ObservationIgnored let toolbarTips = TipGroup(.ordered) {
        ReadingViewTip()
        QuickSwitcherTip()
        BacklinksTip()
        GraphTip()
        CommandPaletteTip()
    }
    /// Current toolbar tip, or nil while the welcome tour is on screen.
    func toolbarTip<T: Tip>(_ type: T.Type, onboarded: Bool) -> T? {
        onboarded ? toolbarTips.currentTip as? T : nil
    }

    /// Editor tips shown one at a time.
    @ObservationIgnored let editorTips = TipGroup(.ordered) {
        LinkTip()
        SlashCommandTip()
    }

    /// Editor of each pane showing a note, for commands that act on the current editor.
    @ObservationIgnored var editors: [UUID: EditorController] = [:]
    var editor: EditorController? { editors[pane.id] }

    init(model: VaultModel) {
        self.model = model
        let first = Pane()
        panes = [first]
        focusedPaneID = first.id
    }

    var pane: Pane { panes.first { $0.id == focusedPaneID } ?? panes[0] }
    var currentPath: String? { pane.current?.path }
    var currentNote: String? { if case .note(let p) = pane.current { p } else { nil } }

    func open(_ d: Destination, line: Int? = nil, newPane: Bool = false) {
        if newPane { split() }
        pane.open(d, line: line)
        if let p = d.path { model.noteDidOpen(p); explorerSelection = p }
        switch d {
        case .note: NetheriteTips.donate(NetheriteTips.noteOpened)
        case .graph, .localGraph: NetheriteTips.donate(NetheriteTips.graphOpened)
        default: break
        }
    }

    func open(path: String, line: Int? = nil, newPane: Bool = false) {
        open(Destination(path: path), line: line, newPane: newPane)
    }

    /// Follows a link (with optional #heading / #^block) from `source`, creating the note if it doesn't exist.
    func follow(_ link: NoteLink, from source: String?, newPane: Bool = false) {
        let src = source ?? ""
        if let target = model.index.resolver.resolve(link.target, from: src) {
            open(path: target, line: line(for: link.subpath, in: target), newPane: newPane)
        } else if !link.target.isEmpty {
            let folder = link.target.contains("/") ? link.target.parentFolder : model.settings.newNoteFolder
            if let p = model.newNote(in: folder, named: (link.target as NSString).lastPathComponent) {
                open(path: p, newPane: newPane)
            }
        }
    }

    func line(for subpath: String?, in path: String) -> Int? {
        guard let sub = subpath, let parsed = model.index.notes[path]?.parsed else { return nil }
        if sub.hasPrefix("^") { return parsed.blockIDs[String(sub.dropFirst())] }
        let wanted = sub.split(separator: "#").last.map(String.init) ?? sub
        return parsed.headings.first { $0.text.caseInsensitiveCompare(wanted) == .orderedSame }?.line
    }

    func split() {
        guard panes.count < 2 else { focusedPaneID = panes[1].id; return }
        let p = Pane()
        if let c = pane.current { p.open(c) }
        panes.append(p)
        focusedPaneID = p.id
    }

    func closePane(_ p: Pane) {
        guard panes.count > 1 else { return }
        panes.removeAll { $0.id == p.id }
        focusedPaneID = panes[0].id
    }

    // MARK: Commands used by menus, toolbar and palette

    func newNote() {
        let folder = explorerSelection.map { model.index.folders.contains($0) ? $0 : $0.parentFolder }
        if let p = model.newNote(in: folder ?? model.settings.newNoteFolder) { open(path: p) }
    }

    func rename(_ path: String, to name: String) {
        if let new = model.rename(path, to: name) { panes.forEach { $0.replacePaths(from: path, to: new) } }
    }

    func move(_ path: String, toFolder folder: String) {
        let target = folder.isEmpty ? (path as NSString).lastPathComponent : "\(folder)/\((path as NSString).lastPathComponent)"
        if let new = model.move(path, to: target) { panes.forEach { $0.replacePaths(from: path, to: new) } }
    }

    func trash(_ path: String) {
        model.trash(path)
        panes.forEach { $0.removePath(path) }
    }

    func openRandomNote() {
        if let p = model.index.markdownFiles.randomElement() { open(path: p) }
    }
}
