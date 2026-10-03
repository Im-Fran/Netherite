import SwiftUI
import TipKit
import CoreSpotlight
import UniformTypeIdentifiers
import NetheriteCore

/// One window on a vault: sidebar · editor pane(s) · inspector.
struct VaultWindow: View {
    @State var window: WindowState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        @Bindable var window = window
        NavigationSplitView(columnVisibility: $window.columnVisibility, preferredCompactColumn: $window.preferredCompactColumn) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 400)
        } detail: {
            PanesView()
                .inspector(isPresented: $window.showInspector) {
                    InspectorView()
                        .inspectorColumnWidth(min: 240, ideal: 290, max: 420)
                }
        }
        .environment(window)
        .focusedSceneValue(\.window, window)
        .sheet(item: $window.sheet) { sheet in
            // Sheets are their own presentations: give them the theme's appearance too.
            sheetView(sheet).environment(window).preferredColorScheme(window.model.theme.appearance?.colorScheme)
        }
        #if os(macOS)
        .sheet(isPresented: $window.presentingSlides) {
            slides.frame(minWidth: 900, minHeight: 600).preferredColorScheme(window.model.theme.appearance?.colorScheme)
        }
        #else
        .fullScreenCover(isPresented: $window.presentingSlides) { slides }
        #endif
        .confirmationDialog("Delete “\(window.pendingTrash?.noteName ?? "")”?",
                            isPresented: Binding(get: { window.pendingTrash != nil }, set: { if !$0 { window.pendingTrash = nil } }),
                            titleVisibility: .visible, presenting: window.pendingTrash) { p in
            Button("Move to Trash", role: .destructive) { window.trash(p) }
        } message: { _ in
            Text("You can restore it from the Trash.")
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { window.model.lastError != nil }, set: { if !$0 { window.model.lastError = nil } })) {
            Button("OK") { window.model.lastError = nil }
        } message: {
            Text(window.model.lastError ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            // A suspended app shouldn't keep a file presenter registered (it can stall coordinated writes from extensions).
            switch phase {
            case .active: window.model.resumeWatching()
            case .background: window.model.flushAll(); window.model.suspendWatching()
            default: window.model.flushAll()
            }
        }
        .task {
            if sizeClass == .compact { window.showInspector = false }
            if window.model.settings.dailyNotes.openOnStartup { window.openDailyNote() }
            else if window.pane.current == nil, let last = window.model.recentFiles.first(where: window.model.vault.exists) {
                window.open(path: last)
            }
        }
        .onOpenURL { url in handleDeepLink(url) }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let path = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String { window.open(path: SystemIntegration.path(fromIdentifier: path).path) }
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .navigationTitle(window.pane.current?.title ?? window.model.name)
        .snapshotting(window.model)
        .exporting($window.exportRequest)
        .fileImporter(isPresented: Binding(get: { window.importTarget != nil }, set: { if !$0 { window.importTarget = nil } }),
                      allowedContentTypes: [.item, .folder], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await window.importFiles(urls); window.importTarget = nil }
            case .failure(let e): window.model.lastError = e.localizedDescription
            }
        }
    }

    @ViewBuilder private var slides: some View {
        if let note = window.currentNote {
            SlidesView(path: note).environment(window)
        }
    }

    @ViewBuilder private func sheetView(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .quickSwitcher: QuickSwitcher()
        case .commandPalette: CommandPalette()
        case .settings:
            // SettingsView only has a Done button on iOS; give the Mac sheet a way out.
            SettingsView().macOnly {
                $0.frame(minWidth: 520, minHeight: 520)
                    .safeAreaInset(edge: .bottom) {
                        HStack { Spacer(); Button("Done") { window.sheet = nil }.keyboardShortcut(.defaultAction) }.padding().background(.bar)
                    }
            }
        case .vaultSettings(let page): VaultSettingsView(model: window.model, initialPage: page)
        case .rename(let p): RenameSheet(path: p)
        case .templates: TemplatePicker()
        case .importer: ImporterView()
        case .publish: PublishView()
        case .workspaces: WorkspacesView()
        case .recovery(let p): FileRecoveryView(path: p)
        case .audio: AudioRecorderView()
        case .merge(let p): MergeSheet(source: p)
        case .openURL: OpenURLSheet()
        }
    }

    /// netherite://open?path=Folder/Note.md · netherite://new?name=…&content=… · netherite://daily · netherite://search?query=…
    private func handleDeepLink(_ url: URL) {
        let q = Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { a, _ in a }
        switch url.host() {
        case "open": if let p = q["path"] ?? q["file"] { window.open(path: p.hasSuffix(".md") || p.contains(".") ? p : p + ".md") }
        case "new":
            if let p = window.model.newNote(named: q["name"], content: q["content"] ?? "") { window.open(path: p) }
        case "daily": window.openDailyNote()
        case "search": window.searchQuery = q["query"] ?? ""; window.sidebarTab = .search; window.preferredCompactColumn = .sidebar
        default: break
        }
    }
}

/// Editor area: one pane, or two side by side.
struct PanesView: View {
    @Environment(WindowState.self) private var window
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if window.panes.count > 1 {
            // Side by side is too narrow on iPhone: stack panes top to bottom there.
            let layout = sizeClass == .compact ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                ForEach(window.panes) { pane in
                    PaneView(pane: pane)
                    if pane.id != window.panes.last?.id { Divider() }
                }
            }
        } else {
            PaneView(pane: window.panes[0])
        }
    }
}

struct PaneView: View {
    @Bindable var pane: Pane
    @Environment(WindowState.self) private var window
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("hasSeenOnboarding") private var onboarded = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { window.focusedPaneID = pane.id })
            .overlay(alignment: .top) {
                if window.panes.count > 1 && window.focusedPaneID == pane.id {
                    Rectangle().fill(Color.accentColor).frame(height: 2)
                }
            }
            .toolbar { toolbar }
            .onChange(of: pane.reading) { NetheriteTips.donate(NetheriteTips.readingToggled) }
    }

    @ViewBuilder private var content: some View {
        switch pane.current {
        case .note(let p): NoteEditorView(path: p, pane: pane).id(p)
        case .file(let p): FilePreview(path: p).id(p)
        case .canvas(let p): CanvasEditor(path: p).id(p)
        case .base(let p): BaseView(path: p).id(p)
        case .graph: GraphView(focus: nil)
        case .localGraph(let p): GraphView(focus: p).id(p)
        case .web(let url): WebViewer(url: url)
        case nil: EmptyPane()
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if window.focusedPaneID == pane.id || window.panes.count == 1 {
            // On iPhone, history and the inspector toggle move into the More menu to keep the bar uncluttered.
            if !compact {
                ToolbarItemGroup(placement: .navigation) {
                    Button("Back", systemImage: "chevron.backward") { pane.back() }
                        .disabled(!pane.canGoBack)
                        .keyboardShortcut("[", modifiers: .command)
                    Button("Forward", systemImage: "chevron.forward") { pane.forward() }
                        .disabled(!pane.canGoForward)
                        .keyboardShortcut("]", modifiers: .command)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                #if os(iOS)
                // On iPhone the sidebar (and its Go to File button) is off screen while a note is open.
                if sizeClass == .compact {
                    Button("Go to File", systemImage: "magnifyingglass") { window.sheet = .quickSwitcher }
                }
                #endif
                if case .note = pane.current {
                    Toggle(isOn: $pane.reading) {
                        Label("Reading View", systemImage: pane.reading ? "book.fill" : "book")
                    }
                    .keyboardShortcut("e")
                    .help("Toggle reading view (⌘E)")
                    .popoverTip(window.toolbarTip(ReadingViewTip.self, onboarded: onboarded), arrowEdge: .top)
                }
                Menu {
                    moreMenu
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .popoverTip(window.toolbarTip(GraphTip.self, onboarded: onboarded), arrowEdge: .top)
                .popoverTip(compact ? window.toolbarTip(BacklinksTip.self, onboarded: onboarded) : nil, arrowEdge: .top)
                if !compact {
                    Button("Toggle Inspector", systemImage: "sidebar.right", action: toggleInspector)
                        .help("Show or hide backlinks, outline and properties")
                        .popoverTip(window.toolbarTip(BacklinksTip.self, onboarded: onboarded), arrowEdge: .top)
                }
            }
        }
    }

    private var compact: Bool { sizeClass == .compact }

    private func toggleInspector() {
        window.showInspector.toggle()
        NetheriteTips.donate(NetheriteTips.inspectorUsed)
    }

    @ViewBuilder private var moreMenu: some View {
        if compact {
            // One row of round buttons at the top of the menu, like the system's palette menus.
            ControlGroup {
                Button("Back", systemImage: "chevron.backward") { pane.back() }.disabled(!pane.canGoBack)
                Button("Forward", systemImage: "chevron.forward") { pane.forward() }.disabled(!pane.canGoForward)
                Button("Toggle Inspector", systemImage: "sidebar.right", action: toggleInspector)
            }
            .controlGroupStyle(.palette)
        }
        if let p = pane.current?.path {
            Button("Open in New Pane", systemImage: "rectangle.split.2x1") { window.split() }
            if window.panes.count > 1 { Button("Close Pane", systemImage: "xmark.rectangle") { window.closePane(pane) } }
            Divider()
            if case .note(let n) = pane.current {
                Menu("Open Local Graph", systemImage: "circle.hexagongrid") {
                    Button("In New Pane", systemImage: "rectangle.split.2x1") { window.openLocalGraph(for: n) }
                    Button("Full Window", systemImage: "rectangle") { window.openLocalGraph(for: n, newPane: false) }
                }
                Button("Start Presentation", systemImage: "play.rectangle") { window.presentingSlides = true }
            }
            Button(window.model.isBookmarked(p) ? "Remove Bookmark" : "Bookmark", systemImage: "bookmark") {
                if window.model.isBookmarked(p) { window.model.removeBookmark(.file(p)) } else { window.model.addBookmark(.file(p)) }
            }
            Button("Copy Link", systemImage: "link") { copyToPasteboard(window.model.linkText(to: p)) }
            ShareLink(item: window.model.vault.url(for: p))
            Button("Rename…", systemImage: "pencil") { window.sheet = .rename(p) }
            Button("Snapshots…", systemImage: "clock.arrow.circlepath") { window.sheet = .recovery(p) }
            Button("Export…", systemImage: "square.and.arrow.up.on.square") { window.export(p) }
            #if os(macOS)
            Button("Reveal in Finder", systemImage: "finder") { NSWorkspace.shared.activateFileViewerSelecting([window.model.vault.url(for: p)]) }
            #endif
            Divider()
            Button("Delete…", systemImage: "trash", role: .destructive) { window.pendingTrash = p }
        } else if window.panes.count > 1 {
            Button("Close Pane", systemImage: "xmark.rectangle") { window.closePane(pane) }
        }
    }
}

struct EmptyPane: View {
    @Environment(WindowState.self) private var window

    var body: some View {
        ContentUnavailableView {
            Label("No File Is Open", systemImage: "doc.text")
        } description: {
            Text("Create a note or jump to one with the quick switcher.")
        } actions: {
            Button("Create New Note") { window.newNote() }
                .buttonStyle(.borderedProminent)
            Button("Go to File…") { window.sheet = .quickSwitcher }
            Button("Open Today's Daily Note") { window.openDailyNote() }
        }
        .overlay(alignment: .bottom) {
            TipView(DailyNoteTip()).frame(maxWidth: 420).padding()
        }
    }
}

/// Images, PDFs, audio and video shown through the web view (same renderer as embeds).
struct FilePreview: View {
    let path: String
    @Environment(WindowState.self) private var window

    var body: some View {
        let link = NoteLink(target: path, isEmbed: true, isWiki: true, range: NSRange(), line: 0)
        let html = HTMLRenderer.embed(link, .app(window.model.index, source: path))
        HTMLWebView(html: HTMLRenderer.page(title: (path as NSString).lastPathComponent, body: html, assets: "nth://web/", fullWidth: true),
                    vault: window.model.vault, onAction: { window.handle($0, from: path) })
    }
}
