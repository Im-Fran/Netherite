import SwiftUI
import NetheriteCore

struct FileNode: Identifiable, Hashable {
    var path: String
    var name: String
    var isFolder: Bool
    var children: [FileNode] = []
    var id: String { path }

    /// Builds the folder tree; folders first, then files, both in Finder order.
    static func tree(files: [String], folders: [String]) -> [FileNode] {
        var byParent: [String: [FileNode]] = [:]
        for f in folders { byParent[f.parentFolder, default: []].append(FileNode(path: f, name: (f as NSString).lastPathComponent, isFolder: true)) }
        for f in files {
            let name = f.isMarkdown ? f.noteName : (f as NSString).lastPathComponent
            byParent[f.parentFolder, default: []].append(FileNode(path: f, name: name, isFolder: false))
        }
        func build(_ parent: String) -> [FileNode] {
            (byParent[parent] ?? []).map { n in
                var n = n
                if n.isFolder { n.children = build(n.path) }
                return n
            }.sorted { a, b in a.isFolder != b.isFolder ? a.isFolder : a.name.localizedStandardCompare(b.name) == .orderedAscending }
        }
        return build("")
    }
}

struct FileExplorer: View {
    @Environment(WindowState.self) private var window
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded: Set<String> = []

    var body: some View {
        @Bindable var window = window
        let index = window.model.index
        let nodes = FileNode.tree(files: index.files, folders: index.folders)
        List(selection: $window.explorerSelection) {
            ForEach(nodes) { node in row(node) }
        }
        .dropDestination(for: String.self) { paths, _ in
            paths.forEach { window.move($0, toFolder: "") }
            return true
        }
        #if os(iOS)
        // Empty-area menu; a plain `.contextMenu` would lift the whole list on iOS.
        .contextMenu(forSelectionType: String.self) { selection in
            if selection.isEmpty { folderMenu("") }
        }
        #else
        .contextMenu { folderMenu("") }
        #endif
        .onChange(of: window.explorerSelection) { _, new in
            guard let new, index.files.contains(new) else { return }
            if window.currentPath != new { window.open(path: new) } else { window.preferredCompactColumn = .detail }
        }
        .onChange(of: window.currentPath) { _, path in
            guard let path else { return }
            var parent = path.parentFolder
            while !parent.isEmpty { expanded.insert(parent); parent = parent.parentFolder }
        }
        .overlay {
            if index.isLoaded && nodes.isEmpty {
                ContentUnavailableView {
                    Label("No notes yet", systemImage: "doc.text")
                } actions: {
                    Button("New Note") { window.newNote() }
                }
            } else if !index.isLoaded {
                ProgressView()
            }
        }
    }

    private func row(_ node: FileNode) -> AnyView {
        if node.isFolder {
            return AnyView(
                DisclosureGroup(isExpanded: Binding(get: { expanded.contains(node.path) },
                                                    set: { if $0 { expanded.insert(node.path) } else { expanded.remove(node.path) } })) {
                    ForEach(node.children) { row($0) }
                } label: {
                    Label(node.name, systemImage: "folder")
                        #if os(iOS)
                        // Tapping a folder only expands it; selecting it would push the empty detail on iPhone.
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(reduceMotion ? nil : .default) { if expanded.contains(node.path) { expanded.remove(node.path) } else { expanded.insert(node.path) } } }
                        #endif
                        .dropDestination(for: String.self) { paths, _ in
                            paths.filter { $0 != node.path }.forEach { window.move($0, toFolder: node.path) }
                            expanded.insert(node.path)
                            return true
                        }
                }
                .tag(node.path)
                #if os(iOS)
                .selectionDisabled()
                #endif
                .draggable(node.path)
                .contextMenu { folderMenu(node.path); itemMenu(node.path) }
                #if os(iOS)
                .swipeActions(allowsFullSwipe: false) { swipeMenu(node.path) }
                #endif
            )
        }
        return AnyView(
            Label(node.name, systemImage: symbol(for: node.path))
                .lineLimit(1)
                .tag(node.path)
                .draggable(node.path)
                .contextMenu { itemMenu(node.path) }
                #if os(iOS)
                .swipeActions(allowsFullSwipe: false) { swipeMenu(node.path) }
                #endif
        )
    }

    @ViewBuilder private func folderMenu(_ folder: String) -> some View {
        Button("New Note", systemImage: "square.and.pencil") {
            if let p = window.model.newNote(in: folder) { window.open(path: p) }
        }
        Button("New Folder", systemImage: "folder.badge.plus") {
            if let p = window.model.newFolder(in: folder) { expanded.insert(folder); window.sheet = .rename(p) }
        }
        let settings = window.model.settings
        if settings.isEnabled(.templates) {
            Button("New Note from Template…", systemImage: "doc.badge.plus") { window.sheet = .newFromTemplate(folder) }
        }
        if settings.isEnabled(.meetingNotes) {
            Button("New Meeting Note…", systemImage: "person.2") { window.sheet = .meetingNote }
        }
        if settings.isEnabled(.canvas) {
            Button("New Canvas", systemImage: "rectangle.3.group") {
                if let p = window.model.newCanvas(in: folder) { window.open(path: p) }
            }
        }
        if settings.isEnabled(.bases) {
            Button("New Base", systemImage: "tablecells") {
                if let p = window.model.newBase(in: folder) { window.open(path: p) }
            }
            Button("New Database…", systemImage: "tablecells.badge.ellipsis") { window.sheet = .newDatabase(folder) }
        }
        Button("Import Files…", systemImage: "square.and.arrow.down") { window.importTarget = folder }
        if folder.isEmpty {
            Button("Export Vault…", systemImage: "square.and.arrow.up.on.square") { window.export("") }
        }
        Divider()
    }

    @ViewBuilder private func itemMenu(_ path: String) -> some View {
        if !window.model.index.folders.contains(path) {
            Button("Open in New Pane", systemImage: "rectangle.split.2x1") { window.open(path: path, newPane: true) }
            Button("Bookmark", systemImage: "bookmark") { window.model.addBookmark(.file(path)) }
        }
        Button("Rename…", systemImage: "pencil") { window.sheet = .rename(path) }
        Button("Export…", systemImage: "square.and.arrow.up.on.square") { window.export(path) }
        #if os(macOS)
        Button("Reveal in Finder", systemImage: "finder") { NSWorkspace.shared.activateFileViewerSelecting([window.model.vault.url(for: path)]) }
        #endif
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) { window.pendingTrash = path }
    }

    /// No `.destructive` role: it would animate the row away before the user confirms.
    @ViewBuilder private func swipeMenu(_ path: String) -> some View {
        Button("Delete…", systemImage: "trash") { window.pendingTrash = path }.tint(.red)
        Button("Rename…", systemImage: "pencil") { window.sheet = .rename(path) }
    }
}

/// Sheet for renaming a file or folder.
struct RenameSheet: View {
    let path: String
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .onSubmit(commit)
            }
            .formStyle(.grouped)
            .navigationTitle("Rename")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Rename", action: commit).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
        .macOnly { $0.frame(minWidth: 360, minHeight: 160) }
        .onAppear { name = window.model.index.folders.contains(path) ? (path as NSString).lastPathComponent : path.noteName }
    }

    private func commit() {
        window.rename(path, to: name)
        dismiss()
    }
}
