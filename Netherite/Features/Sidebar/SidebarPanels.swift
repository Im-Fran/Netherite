import SwiftUI
import TipKit
import NetheriteCore

struct SidebarView: View {
    @Environment(WindowState.self) private var window
    @AppStorage("hasSeenOnboarding") private var onboarded = false

    var body: some View {
        @Bindable var window = window
        VStack(spacing: 0) {
            Picker("Sidebar", selection: $window.sidebarTab) {
                ForEach(SidebarTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            switch window.sidebarTab {
            case .files: FileExplorer()
            case .search: SearchPanel()
            case .bookmarks: BookmarksPanel()
            case .tags: TagsPanel()
            }
            Divider()
            VaultSyncFooter(vault: window.model.vault)
        }
        .navigationTitle(window.model.name)
        .toolbar {
            #if os(iOS)
            // iPhone has no menu bar, so Settings and switching vaults need a visible entry point.
            ToolbarItem(placement: .topBarLeading) {
                Menu("Vault", systemImage: "books.vertical") {
                    Button("Vault Settings", systemImage: "slider.horizontal.3") { window.sheet = .vaultSettings(nil) }
                    Button("Netherite Settings", systemImage: "gearshape") { window.sheet = .settings }
                    Button("Import Files…", systemImage: "square.and.arrow.down") { window.importTarget = "" }
                    Button("Export Vault…", systemImage: "square.and.arrow.up.on.square") { window.export("") }
                    Divider()
                    Button("Switch Vault…", systemImage: "arrow.left.arrow.right") { window.model.flushAll(); window.closeVault?() }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) { sidebarActions }
            #else
            ToolbarItemGroup { sidebarActions }
            #endif
        }
    }

    @ViewBuilder private var sidebarActions: some View {
        Button("Go to File", systemImage: "magnifyingglass") { window.sheet = .quickSwitcher }
            .help("Go to file (⌘O)")
            .popoverTip(window.toolbarTip(QuickSwitcherTip.self, onboarded: onboarded), arrowEdge: .top)
        Button("Command Palette", systemImage: "command") { window.sheet = .commandPalette }
            .help("Command palette (⌘P)")
            .popoverTip(window.toolbarTip(CommandPaletteTip.self, onboarded: onboarded), arrowEdge: .top)
        Button("New Note", systemImage: "square.and.pencil") { window.newNote() }
            .keyboardShortcut("n")
            .help("New note (⌘N)")
    }
}

// MARK: Search

struct SearchPanel: View {
    @Environment(WindowState.self) private var window
    @State private var hits: [SearchHit] = []
    @State private var caseSensitive = false
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var window = window
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $window.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Toggle(isOn: $caseSensitive) {
                    Text("Aa")
                        #if os(iOS)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        #endif
                }
                .toggleStyle(.button)
                .accessibilityLabel("Match Case")
                .help("Match case")
                Menu {
                    Button("Bookmark Search", systemImage: "bookmark") { window.model.addBookmark(.search(window.searchQuery)) }
                        .disabled(window.searchQuery.isEmpty)
                    Divider()
                    Text("Operators: tag: path: file: line: task: [prop:value] \"phrase\" -exclude OR /regex/")
                } label: {
                    Label("Search Options", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        #if os(iOS)
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        #endif
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
            .padding(.horizontal, 10)

            TipView(SearchTip())
                .padding(.horizontal, 10)
                .padding(.top, 8)
            if !window.searchQuery.isEmpty {
                Text("\(hits.count) results").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }
            List {
                ForEach(hits) { hit in
                    Section {
                        ForEach(hit.matches, id: \.self) { m in
                            Button { window.open(path: hit.path, line: m.line) } label: {
                                highlighted(m).font(.callout).lineLimit(3)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Button { window.open(path: hit.path) } label: {
                            Label(hit.path.noteName, systemImage: symbol(for: hit.path)).font(.headline)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .overlay {
                if window.searchQuery.isEmpty {
                    ContentUnavailableView("Search Your Vault", systemImage: "magnifyingglass",
                                           description: Text("Find text, tags and properties across all your notes."))
                } else if hits.isEmpty {
                    ContentUnavailableView.search(text: window.searchQuery)
                }
            }
        }
        .task(id: "\(window.searchQuery)|\(caseSensitive)|\(window.model.index.revision)") {
            try? await Task.sleep(for: .milliseconds(150))
            if !window.searchQuery.isEmpty { NetheriteTips.donate(NetheriteTips.searchUsed) }
            let query = SearchQuery(window.searchQuery, caseSensitive: caseSensitive)
            let notes = window.model.index.notes
            hits = await Task.detached { Search.run(query, in: notes) }.value
        }
        .onAppear { focused = true }
    }

    private func highlighted(_ m: SearchHit.Match) -> Text {
        let ns = m.text as NSString
        guard m.range.location != NSNotFound, NSMaxRange(m.range) <= ns.length else { return Text(m.text) }
        let start = max(0, m.range.location - 40)
        let prefix = (start > 0 ? "…" : "") + ns.substring(with: NSRange(location: start, length: m.range.location - start))
        return Text(prefix) + Text(ns.substring(with: m.range)).bold().foregroundStyle(Color.accentColor) + Text(ns.substring(from: NSMaxRange(m.range)))
    }
}

// MARK: Tags

struct TagNode: Identifiable {
    var tag: String
    var name: String
    var count: Int
    var children: [TagNode]?
    var id: String { tag }
}

struct TagsPanel: View {
    @Environment(WindowState.self) private var window

    var body: some View {
        let counts = window.model.index.tagCounts
        List {
            OutlineGroup(tree(counts), children: \.children) { node in
                Button {
                    window.searchQuery = "tag:\(node.tag)"
                    window.sidebarTab = .search
                } label: {
                    HStack {
                        Label(node.name, systemImage: "number")
                        Spacer()
                        Text("\(node.count)").foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .overlay {
            if counts.isEmpty { ContentUnavailableView("No Tags", systemImage: "number", description: Text("Add #tags to your notes to see them here.")) }
        }
    }

    private func tree(_ counts: [(tag: String, count: Int)]) -> [TagNode] {
        func build(_ prefix: String) -> [TagNode]? {
            let depth = prefix.isEmpty ? 0 : prefix.split(separator: "/").count
            let kids = counts.filter {
                let parts = $0.tag.split(separator: "/")
                return parts.count == depth + 1 && (prefix.isEmpty || $0.tag.lowercased().hasPrefix(prefix.lowercased() + "/"))
            }
            guard !kids.isEmpty else { return nil }
            return kids.map { TagNode(tag: $0.tag, name: String($0.tag.split(separator: "/").last ?? ""), count: $0.count, children: build($0.tag)) }
        }
        return build("") ?? []
    }
}

// MARK: Bookmarks

struct BookmarksPanel: View {
    @Environment(WindowState.self) private var window

    var body: some View {
        let model = window.model
        List {
            TipView(BookmarksTip())
            ForEach(model.bookmarks) { b in
                Button { open(b) } label: { Label(b.displayTitle, systemImage: b.symbolName) }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Remove Bookmark", systemImage: "bookmark.slash", role: .destructive) { model.removeBookmark(b) } }
            }
            .onMove { model.bookmarks.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { model.bookmarks.remove(atOffsets: $0) }
        }
        .overlay {
            if model.bookmarks.isEmpty {
                ContentUnavailableView("No Bookmarks", systemImage: "bookmark", description: Text("Bookmark notes, headings and searches to find them quickly."))
            }
        }
    }

    private func open(_ b: Bookmark) {
        switch b.kind {
        case .file: if let p = b.path { window.open(path: p) }
        case .heading: if let p = b.path { window.open(path: p, line: window.line(for: b.subpath, in: p)) }
        case .search: window.searchQuery = b.query ?? ""; window.sidebarTab = .search
        case .folder: window.sidebarTab = .files; window.explorerSelection = b.path
        case .graph: window.open(.graph)
        }
    }
}
