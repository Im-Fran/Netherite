import SwiftUI
import NetheriteCore

struct PaletteItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var symbol: String
    var shortcut: String?
    var action: (_ alternate: Bool) -> Void
}

/// Keyboard-driven filter list used by the quick switcher, command palette and template picker.
struct PaletteView: View {
    let prompt: LocalizedStringKey
    let items: (String) -> [PaletteItem]
    var footer: LocalizedStringKey?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    var body: some View {
        let list = items(query)
        VStack(spacing: 0) {
            TextField(prompt, text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(14)
                .focused($focused)
                .autocorrectionDisabled()
                .onSubmit { run(list, alternate: false) }
                .onKeyPress(.upArrow) { selection = max(0, selection - 1); return .handled }
                .onKeyPress(.downArrow) { selection = min(list.count - 1, selection + 1); return .handled }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) || press.modifiers.contains(.shift) else { return .ignored }
                    run(list, alternate: true); return .handled
                }
                .onKeyPress(.escape) { dismiss(); return .handled }
            Divider()
            ScrollViewReader { proxy in
                List(Array(list.enumerated()), id: \.element.id) { i, item in
                    Button { selection = i; run(list, alternate: false) } label: {
                        HStack {
                            Image(systemName: item.symbol).foregroundStyle(.secondary).frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).lineLimit(1)
                                if let s = item.subtitle { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            }
                            Spacer()
                            if let k = item.shortcut { Text(k).font(.caption.monospaced()).foregroundStyle(.secondary) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(i == selection ? Color.accentColor.opacity(0.18) : Color.clear)
                    .id(i)
                }
                .listStyle(.plain)
                .onChange(of: selection) { proxy.scrollTo(selection) }
            }
            if let footer {
                Divider()
                Text(footer).font(.caption).foregroundStyle(.secondary).padding(8)
            }
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 360, idealHeight: 440)
        .onAppear { focused = true }
        .onChange(of: query) { selection = 0 }
        .presentationDetents([.large])
    }

    private func run(_ list: [PaletteItem], alternate: Bool) {
        guard list.indices.contains(selection) else { return }
        dismiss()
        let item = list[selection]
        DispatchQueue.main.async { item.action(alternate) }
    }
}

struct QuickSwitcher: View {
    @Environment(WindowState.self) private var window

    var body: some View {
        PaletteView(prompt: "Find or create a note…", items: items,
                    footer: "↩ open · ⌘↩ open in new pane · ⇧↩ create")
    }

    private func items(_ q: String) -> [PaletteItem] {
        let index = window.model.index
        let pool: [String] = q.isEmpty ? window.model.recentFiles.filter(index.files.contains) + index.files : index.files
        var seen = Set<String>()
        var scored: [(String, Int)] = []
        for p in pool where seen.insert(p).inserted {
            let name = p.isMarkdown ? p.noteName : (p as NSString).lastPathComponent
            let aliases = index.notes[p]?.parsed.aliases ?? []
            let best = ([name] + aliases).compactMap { Search.fuzzyScore(q, $0) }.max() ?? Search.fuzzyScore(q, p).map { $0 / 2 }
            if let best { scored.append((p, q.isEmpty ? 0 : best)) }
        }
        if !q.isEmpty { scored.sort { $0.1 > $1.1 } }
        var out = scored.prefix(100).map { p, _ in
            PaletteItem(id: p, title: p.isMarkdown ? p.noteName : (p as NSString).lastPathComponent,
                        subtitle: p.parentFolder.isEmpty ? nil : p.parentFolder, symbol: symbol(for: p)) { alt in
                window.open(path: p, newPane: alt)
            }
        }
        if !q.isEmpty, !index.files.contains(where: { $0.noteName.caseInsensitiveCompare(q) == .orderedSame }) {
            out.append(PaletteItem(id: "create", title: String(localized: "Create “\(q)”"), symbol: "plus") { _ in
                if let p = window.model.newNote(named: q) { window.open(path: p) }
            })
        }
        return out
    }
}

struct CommandPalette: View {
    @Environment(WindowState.self) private var window

    var body: some View {
        PaletteView(prompt: "Type a command…", items: { q in
            AppCommands.all(window: window, editor: window.editor).compactMap { c in
                (q.isEmpty ? 0 : Search.fuzzyScore(q, c.title)).map { (c, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .map { c, _ in PaletteItem(id: c.id, title: c.title, symbol: c.symbol, shortcut: c.shortcut) { _ in c.run() } }
        })
    }
}

/// Every command available from the palette. Menus reuse these actions.
struct AppCommand: Identifiable {
    var id: String
    var title: String
    var symbol: String
    var shortcut: String?
    var run: () -> Void
}

enum AppCommands {
    @MainActor static func all(window w: WindowState, editor e: EditorController?) -> [AppCommand] {
        let note = w.currentNote
        let path = w.currentPath
        var c: [AppCommand] = [
            .init(id: "new", title: String(localized: "Create new note"), symbol: "square.and.pencil", shortcut: "⌘N") { w.newNote() },
            .init(id: "newpane", title: String(localized: "Create new note in new pane"), symbol: "rectangle.split.2x1") {
                if let p = w.model.newNote() { w.open(path: p, newPane: true) }
            },
            .init(id: "switcher", title: String(localized: "Quick switcher: Open note"), symbol: "magnifyingglass", shortcut: "⌘O") { w.sheet = .quickSwitcher },
            .init(id: "search", title: String(localized: "Search: Search in all files"), symbol: "text.magnifyingglass", shortcut: "⇧⌘F") {
                w.sidebarTab = .search; w.columnVisibility = .all
            },
            .init(id: "graph", title: String(localized: "Graph view: Open graph view"), symbol: "point.3.connected.trianglepath.dotted", shortcut: "⌘G") { w.open(.graph) },
            .init(id: "daily", title: String(localized: "Daily notes: Open today's daily note"), symbol: "calendar", shortcut: "⌥⌘D") { w.openDailyNote() },
            .init(id: "daily-prev", title: String(localized: "Daily notes: Open previous daily note"), symbol: "chevron.backward") { w.openAdjacentDailyNote(-1) },
            .init(id: "daily-next", title: String(localized: "Daily notes: Open next daily note"), symbol: "chevron.forward") { w.openAdjacentDailyNote(1) },
            .init(id: "unique", title: String(localized: "Unique note creator: Create new unique note"), symbol: "number.square") { w.newUniqueNote() },
            .init(id: "random", title: String(localized: "Random note: Open random note"), symbol: "shuffle") { w.openRandomNote() },
            .init(id: "canvas", title: String(localized: "Canvas: Create new canvas"), symbol: "rectangle.3.group") {
                if let p = w.model.newCanvas(in: w.model.settings.newNoteFolder) { w.open(path: p) }
            },
            .init(id: "base", title: String(localized: "Bases: Create new base"), symbol: "tablecells") {
                if let p = w.model.newBase(in: w.model.settings.newNoteFolder) { w.open(path: p) }
            },
            .init(id: "workspaces", title: String(localized: "Workspaces: Manage workspaces"), symbol: "rectangle.3.offgrid") { w.sheet = .workspaces },
            .init(id: "web", title: String(localized: "Web viewer: Open URL"), symbol: "globe") { w.promptWebURL() },
            .init(id: "record", title: String(localized: "Audio recorder: Start recording"), symbol: "mic") { w.sheet = .audio },
            .init(id: "import", title: String(localized: "Importer: Import notes"), symbol: "square.and.arrow.down") { w.sheet = .importer },
            .init(id: "publish", title: String(localized: "Publish: Publish vault"), symbol: "paperplane") { w.sheet = .publish },
            .init(id: "split", title: String(localized: "Split right"), symbol: "rectangle.split.2x1", shortcut: "⌘\\") { w.split() },
            .init(id: "back", title: String(localized: "Navigate back"), symbol: "chevron.backward", shortcut: "⌘[") { w.pane.back() },
            .init(id: "forward", title: String(localized: "Navigate forward"), symbol: "chevron.forward", shortcut: "⌘]") { w.pane.forward() },
            .init(id: "inspector", title: String(localized: "Toggle right sidebar"), symbol: "sidebar.right") { w.showInspector.toggle() },
            .init(id: "sidebar", title: String(localized: "Toggle left sidebar"), symbol: "sidebar.left") {
                w.columnVisibility = w.columnVisibility == .detailOnly ? .all : .detailOnly
            },
            .init(id: "settings", title: String(localized: "Open settings"), symbol: "gearshape", shortcut: "⌘,") { w.sheet = .settings },
            .init(id: "reload", title: String(localized: "Reload vault from disk"), symbol: "arrow.clockwise") { Task { await w.model.refresh() } },
        ]
        if let path {
            c += [
                .init(id: "rename", title: String(localized: "Rename file"), symbol: "pencil") { w.sheet = .rename(path) },
                .init(id: "bookmark", title: String(localized: "Bookmark current file"), symbol: "bookmark") { w.model.addBookmark(.file(path)) },
                .init(id: "copylink", title: String(localized: "Copy link to file"), symbol: "link") { copyToPasteboard(w.model.linkText(to: path)) },
                .init(id: "recovery", title: String(localized: "File recovery: Open snapshots"), symbol: "clock.arrow.circlepath") { w.sheet = .recovery(path) },
                .init(id: "delete", title: String(localized: "Delete current file"), symbol: "trash") { w.trash(path) },
            ]
        }
        if let note {
            c += [
                .init(id: "read", title: String(localized: "Toggle reading view"), symbol: "book", shortcut: "⌘E") { w.pane.reading.toggle() },
                .init(id: "localgraph", title: String(localized: "Graph view: Open local graph"), symbol: "circle.hexagongrid") { w.openLocalGraph(for: note) },
                .init(id: "slides", title: String(localized: "Slides: Start presentation"), symbol: "play.rectangle") { w.presentingSlides = true },
                .init(id: "template", title: String(localized: "Templates: Insert template"), symbol: "doc.on.doc", shortcut: "⌥⌘T") { w.sheet = .templates },
                .init(id: "merge", title: String(localized: "Note composer: Merge current file with another file"), symbol: "arrow.triangle.merge") { w.sheet = .merge(note) },
            ]
        }
        if let e, note != nil {
            c += [
                .init(id: "bold", title: String(localized: "Toggle bold"), symbol: "bold", shortcut: "⌘B") { e.wrap("**") },
                .init(id: "italic", title: String(localized: "Toggle italic"), symbol: "italic", shortcut: "⌘I") { e.wrap("*") },
                .init(id: "strike", title: String(localized: "Toggle strikethrough"), symbol: "strikethrough") { e.wrap("~~") },
                .init(id: "highlight", title: String(localized: "Toggle highlight"), symbol: "highlighter") { e.wrap("==") },
                .init(id: "code", title: String(localized: "Toggle code"), symbol: "chevron.left.forwardslash.chevron.right") { e.wrap("`") },
                .init(id: "comment", title: String(localized: "Toggle comment"), symbol: "eye.slash") { e.wrap("%%") },
                .init(id: "link", title: String(localized: "Add internal link"), symbol: "link", shortcut: "⌘K") { e.wrap("[[", "]]") },
                .init(id: "task", title: String(localized: "Toggle checklist"), symbol: "checklist", shortcut: "⌘L") { e.toggleLinePrefix("- [ ] ") },
                .init(id: "bullet", title: String(localized: "Toggle bullet list"), symbol: "list.bullet") { e.toggleLinePrefix("- ") },
                .init(id: "numbered", title: String(localized: "Toggle numbered list"), symbol: "list.number") { e.toggleLinePrefix("1. ") },
                .init(id: "quote", title: String(localized: "Toggle blockquote"), symbol: "text.quote") { e.toggleLinePrefix("> ") },
                .init(id: "extract", title: String(localized: "Note composer: Extract selection to new note"), symbol: "scissors") { w.extractSelection(e) },
            ]
            for level in 1...6 {
                c.append(.init(id: "h\(level)", title: String(localized: "Set heading \(level)"), symbol: "textformat.size", shortcut: level <= 3 ? "⌃\(level)" : nil) {
                    e.toggleLinePrefix(String(repeating: "#", count: level) + " ")
                })
            }
        }
        return c
    }
}

func copyToPasteboard(_ s: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
    #else
    UIPasteboard.general.string = s
    #endif
}

// MARK: Focused editor

struct FocusedEditorKey: FocusedValueKey { typealias Value = EditorController }
extension FocusedValues {
    var editor: EditorController? {
        get { self[FocusedEditorKey.self] }
        set { self[FocusedEditorKey.self] = newValue }
    }
}

struct FocusedWindowKey: FocusedValueKey { typealias Value = WindowState }
extension FocusedValues {
    var window: WindowState? {
        get { self[FocusedWindowKey.self] }
        set { self[FocusedWindowKey.self] = newValue }
    }
}
