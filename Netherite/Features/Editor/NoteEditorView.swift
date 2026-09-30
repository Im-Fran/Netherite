import SwiftUI
import NetheriteCore

/// Editor for one Markdown note: inline title, Live Preview text, completions, and reading mode.
struct NoteEditorView: View {
    let path: String
    @Bindable var pane: Pane
    @Environment(WindowState.self) private var window
    @State private var controller = EditorController()
    @State private var title = ""
    @FocusState private var titleFocused: Bool

    private var model: VaultModel { window.model }

    var body: some View {
        let text = model.text(of: path)
        VStack(spacing: 0) {
            if pane.reading {
                ReaderView(path: path, text: text, pane: pane)
            } else {
                editor(text)
            }
        }
        .onAppear { title = path.noteName; window.editors[pane.id] = controller; jumpIfNeeded() }
        .onChange(of: path) { title = path.noteName; controller.completion = nil; jumpIfNeeded() }
        .onChange(of: pane.pendingLine) { jumpIfNeeded() }
        .onDisappear { model.save(path) }
        .focusedSceneValue(\.editor, controller)
    }

    private func editor(_ text: String) -> some View {
        VStack(spacing: 0) {
            TextField("Title", text: $title)
                .font(.largeTitle.bold())
                .textFieldStyle(.plain)
                .focused($titleFocused)
                .onSubmit { commitTitle(); controller.focus() }
                .onChange(of: titleFocused) { if !titleFocused { commitTitle() } }
                .frame(maxWidth: model.settings.readableLineLength ? MarkdownTextView.maxLineWidth : .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .accessibilityLabel("Note title")

            MarkdownTextView(
                text: text, theme: model.theme, livePreview: true,
                readableWidth: model.settings.readableLineLength, spellcheck: model.settings.spellcheck,
                controller: controller,
                onChange: { model.edit(path, text: $0) },
                onOpenLink: { target, newPane in
                    window.follow(NoteParser.splitWiki(target, isEmbed: false), from: path, newPane: newPane)
                },
                onOpenTag: { tag in
                    window.searchQuery = "tag:\(tag)"
                    window.sidebarTab = .search
                    window.columnVisibility = .all
                },
                embedImage: { [model, path] target in
                    guard let p = model.index.resolver.resolve(target, from: path),
                          ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"].contains(p.fileExtension) else { return nil }
                    return ImageCache.shared.image(at: model.vault.url(for: p))
                },
                styleToken: model.index.files.count
            )
            .overlay(alignment: .topLeading) { CompletionOverlay(controller: controller, sourcePath: path) }
            .overlay(alignment: .topLeading) {
                if let h = controller.hover {
                    Color.clear
                        .frame(width: max(1, h.rect.width), height: max(1, h.rect.height))
                        .offset(x: h.rect.minX, y: h.rect.minY)
                        .popover(isPresented: Binding(get: { controller.hover != nil }, set: { if !$0 { controller.hover = nil } })) {
                            PagePreview(link: NoteParser.splitWiki(h.target, isEmbed: false), source: path)
                        }
                }
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) { FormattingBar(controller: controller) }
        }
        #endif
    }

    private func commitTitle() {
        let clean = title.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean != path.noteName else { title = path.noteName; return }
        window.rename(path, to: clean)
    }

    private func jumpIfNeeded() {
        guard let line = pane.pendingLine else { return }
        pane.pendingLine = nil
        DispatchQueue.main.async { controller.scrollTo(line: line) }
    }
}

/// Formatting shortcuts shown above the iOS keyboard and in the macOS Format menu.
struct FormattingBar: View {
    let controller: EditorController
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                button("Link", "link") { controller.wrap("[[", "]]") }
                button("Tag", "number") { controller.insert("#") }
                button("Bold", "bold") { controller.wrap("**") }
                button("Italic", "italic") { controller.wrap("*") }
                button("Highlight", "highlighter") { controller.wrap("==") }
                button("Code", "chevron.left.forwardslash.chevron.right") { controller.wrap("`") }
                button("Heading", "textformat.size") { controller.toggleLinePrefix("## ") }
                button("Bulleted list", "list.bullet") { controller.toggleLinePrefix("- ") }
                button("Task", "checklist") { controller.toggleLinePrefix("- [ ] ") }
                button("Quote", "text.quote") { controller.toggleLinePrefix("> ") }
                button("Command", "slash.circle") { controller.insert("/") }
            }
        }
    }

    private func button(_ label: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(label, systemImage: symbol).labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44) }
    }
}

// MARK: Completions

struct CompletionItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String?
    var symbol: String
    var replacement: String
    var cursorBack = 0
}

struct CompletionOverlay: View {
    @Bindable var controller: EditorController
    let sourcePath: String
    @Environment(WindowState.self) private var window

    var body: some View {
        if let c = controller.completion {
            let items = self.items(for: c)
            if !items.isEmpty {
                ScrollViewReader { proxy in
                    List(Array(items.enumerated()), id: \.element.id) { i, item in
                        Button { accept(item) } label: {
                            HStack {
                                Image(systemName: item.symbol).foregroundStyle(.secondary).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).lineLimit(1)
                                    if let s = item.subtitle { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(i == controller.completionIndex ? Color.accentColor.opacity(0.18) : Color.clear)
                        .id(i)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(width: 320, height: min(CGFloat(items.count) * 44 + 8, 280))
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
                    .shadow(radius: 12, y: 4)
                    .offset(x: max(8, c.caret.minX - 12), y: c.caret.maxY + 6)
                    .onChange(of: controller.completionIndex) { proxy.scrollTo(controller.completionIndex) }
                }
                .onAppear { bind(items) }
                .onChange(of: items.map(\.id)) { bind(items) }
            }
        }
    }

    private func bind(_ items: [CompletionItem]) {
        controller.completionCount = items.count
        controller.completionIndex = min(controller.completionIndex, max(0, items.count - 1))
        controller.acceptCompletion = { [items] in
            if items.indices.contains(controller.completionIndex) { accept(items[controller.completionIndex]) }
        }
    }

    private func accept(_ item: CompletionItem) {
        controller.complete(with: item.replacement, cursorOffsetFromEnd: item.cursorBack)
    }

    private func items(for c: EditorController.Completion) -> [CompletionItem] {
        let index = window.model.index
        switch c.kind {
        case .link, .embed:
            let bang = c.kind == .embed ? "!" : ""
            if let hash = c.query.firstIndex(of: "#") {
                let note = String(c.query[..<hash]), q = String(c.query[c.query.index(after: hash)...])
                guard let target = note.isEmpty ? sourcePath : index.resolver.resolve(note, from: sourcePath),
                      let parsed = index.notes[target]?.parsed else { return [] }
                return parsed.headings.filter { q.isEmpty || $0.text.localizedCaseInsensitiveContains(q) }.prefix(30).map {
                    CompletionItem(id: "h\($0.line)", title: $0.text, subtitle: String(repeating: "#", count: $0.level), symbol: "number",
                                   replacement: "\(bang)[[\(note)#\($0.text)]]")
                }
            }
            let pool = c.query.isEmpty ? window.model.recentFiles.filter { index.files.contains($0) } + index.files : index.files
            var seen = Set<String>()
            return pool.compactMap { p -> (String, Int)? in
                guard seen.insert(p).inserted else { return nil }
                let name = p.isMarkdown ? p.noteName : (p as NSString).lastPathComponent
                return Search.fuzzyScore(c.query, name).map { (p, $0) } ?? Search.fuzzyScore(c.query, p).map { (p, $0 / 2) }
            }
            .sorted { $0.1 > $1.1 }.prefix(40).map { p, _ in
                let link = index.resolver.linkText(for: p)
                return CompletionItem(id: p, title: p.isMarkdown ? p.noteName : (p as NSString).lastPathComponent,
                                      subtitle: p.parentFolder.isEmpty ? nil : p.parentFolder, symbol: symbol(for: p),
                                      replacement: "\(bang)[[\(link)]]")
            } + (c.query.isEmpty || index.files.contains(where: { $0.noteName.caseInsensitiveCompare(c.query) == .orderedSame }) ? [] : [
                CompletionItem(id: "new", title: c.query, subtitle: String(localized: "Link to new note"), symbol: "plus", replacement: "\(bang)[[\(c.query)]]")
            ])
        case .tag:
            return index.tagCounts.filter { Search.fuzzyScore(c.query, $0.tag) != nil }.prefix(30).map {
                CompletionItem(id: $0.tag, title: "#\($0.tag)", subtitle: "\($0.count)", symbol: "number", replacement: "#\($0.tag) ")
            }
        case .slash:
            return SlashCommand.all(model: window.model).filter { c.query.isEmpty || Search.fuzzyScore(c.query, $0.title) != nil }.map {
                CompletionItem(id: $0.id, title: $0.title, subtitle: nil, symbol: $0.symbol, replacement: $0.text, cursorBack: $0.cursorBack)
            }
        }
    }
}

/// Snippets offered after typing `/` in the editor.
struct SlashCommand: Identifiable {
    var id: String
    var title: String
    var symbol: String
    var text: String
    var cursorBack = 0

    @MainActor static func all(model: VaultModel) -> [SlashCommand] {
        let now = Date.now
        let date = Frontmatter.dateString(now)
        let time = now.formatted(date: .omitted, time: .shortened)
        var list: [SlashCommand] = [
            .init(id: "h1", title: String(localized: "Heading 1"), symbol: "textformat.size.larger", text: "# "),
            .init(id: "h2", title: String(localized: "Heading 2"), symbol: "textformat.size", text: "## "),
            .init(id: "h3", title: String(localized: "Heading 3"), symbol: "textformat.size.smaller", text: "### "),
            .init(id: "ul", title: String(localized: "Bulleted list"), symbol: "list.bullet", text: "- "),
            .init(id: "ol", title: String(localized: "Numbered list"), symbol: "list.number", text: "1. "),
            .init(id: "task", title: String(localized: "Task"), symbol: "checklist", text: "- [ ] "),
            .init(id: "quote", title: String(localized: "Quote"), symbol: "text.quote", text: "> "),
            .init(id: "callout", title: String(localized: "Callout"), symbol: "exclamationmark.bubble", text: "> [!note]\n> ", cursorBack: 0),
            .init(id: "code", title: String(localized: "Code block"), symbol: "chevron.left.forwardslash.chevron.right", text: "```\n\n```", cursorBack: 4),
            .init(id: "math", title: String(localized: "Math block"), symbol: "function", text: "$$\n\n$$", cursorBack: 3),
            .init(id: "mermaid", title: String(localized: "Mermaid diagram"), symbol: "flowchart", text: "```mermaid\ngraph TD\n  A --> B\n```", cursorBack: 4),
            .init(id: "table", title: String(localized: "Table"), symbol: "tablecells", text: "| Column | Column |\n| --- | --- |\n|  |  |", cursorBack: 5),
            .init(id: "hr", title: String(localized: "Divider"), symbol: "minus", text: "---\n"),
            .init(id: "footnote", title: String(localized: "Footnote"), symbol: "textformat.superscript", text: "[^1]"),
            .init(id: "date", title: String(localized: "Insert date"), symbol: "calendar", text: date),
            .init(id: "time", title: String(localized: "Insert time"), symbol: "clock", text: time),
        ]
        for t in Templates.list(in: model.index, folder: model.settings.templatesFolder) {
            list.append(.init(id: "tpl:\(t)", title: String(localized: "Template: \(t.noteName)"), symbol: "doc.on.doc",
                              text: Templates.render(model.text(of: t), title: "", date: now)))
        }
        return list
    }
}

/// Small cache for images shown inline in the editor.
final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, PlatformImage>()

    /// Keyed by path + modification date, so a replaced attachment shows its new content.
    func image(at url: URL) -> PlatformImage? {
        let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path(percentEncoded: false))|\(mod)" as NSString
        if let i = cache.object(forKey: key) { return i }
        #if os(macOS)
        guard let i = NSImage(contentsOf: url) else { return nil }
        #else
        guard let i = UIImage(contentsOfFile: url.path(percentEncoded: false)) else { return nil }
        #endif
        cache.setObject(i, forKey: key)
        return i
    }
}
