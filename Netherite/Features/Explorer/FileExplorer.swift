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
    @State private var expanded: Set<String> = []
    @State private var confirmDelete: String?

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
        .contextMenu { folderMenu("") }
        .onChange(of: window.explorerSelection) { _, new in
            guard let new, index.files.contains(new), window.currentPath != new else { return }
            window.open(path: new)
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
                    Button("New note") { window.newNote() }
                }
            } else if !index.isLoaded {
                ProgressView()
            }
        }
        .confirmationDialog("Delete “\(confirmDelete?.noteName ?? "")”?", isPresented: .init(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { if let p = confirmDelete { window.trash(p) } }
        } message: {
            Text("You can restore it from the Trash.")
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
                        .dropDestination(for: String.self) { paths, _ in
                            paths.filter { $0 != node.path }.forEach { window.move($0, toFolder: node.path) }
                            expanded.insert(node.path)
                            return true
                        }
                }
                .tag(node.path)
                .draggable(node.path)
                .contextMenu { folderMenu(node.path); itemMenu(node.path) }
            )
        }
        return AnyView(
            Label(node.name, systemImage: symbol(for: node.path))
                .lineLimit(1)
                .tag(node.path)
                .draggable(node.path)
                .contextMenu { itemMenu(node.path) }
        )
    }

    @ViewBuilder private func folderMenu(_ folder: String) -> some View {
        Button("New note", systemImage: "square.and.pencil") {
            if let p = window.model.newNote(in: folder) { window.open(path: p) }
        }
        Button("New folder", systemImage: "folder.badge.plus") {
            if let p = window.model.newFolder(in: folder) { expanded.insert(folder); window.sheet = .rename(p) }
        }
        Button("New canvas", systemImage: "rectangle.3.group") {
            if let p = window.model.newCanvas(in: folder) { window.open(path: p) }
        }
        Button("New base", systemImage: "tablecells") {
            if let p = window.model.newBase(in: folder) { window.open(path: p) }
        }
        Divider()
    }

    @ViewBuilder private func itemMenu(_ path: String) -> some View {
        if !window.model.index.folders.contains(path) {
            Button("Open in new pane", systemImage: "rectangle.split.2x1") { window.open(path: path, newPane: true) }
            Button("Bookmark", systemImage: "bookmark") { window.model.addBookmark(.file(path)) }
        }
        Button("Rename…", systemImage: "pencil") { window.sheet = .rename(path) }
        #if os(macOS)
        Button("Reveal in Finder", systemImage: "finder") { NSWorkspace.shared.activateFileViewerSelecting([window.model.vault.url(for: path)]) }
        #endif
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) { confirmDelete = path }
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
        .frame(minWidth: 360, minHeight: 160)
        .onAppear { name = window.model.index.folders.contains(path) ? (path as NSString).lastPathComponent : path.noteName }
    }

    private func commit() {
        window.rename(path, to: name)
        dismiss()
    }
}
