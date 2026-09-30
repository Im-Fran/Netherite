import SwiftUI
import NetheriteCore

/// A saved window layout (`.netherite/workspaces.json`).
struct Workspace: Codable, Hashable, Identifiable {
    var name: String
    var panes: [Destination]
    var readingModes: [Bool]
    var sidebarTab: SidebarTab
    var showInspector: Bool
    var id: String { name }
}

extension WindowState {
    var workspaces: [Workspace] { model.vault.loadConfig("workspaces.json", fallback: [Workspace]()) }

    func saveWorkspace(named name: String) {
        var all = workspaces.filter { $0.name != name }
        all.append(Workspace(name: name, panes: panes.compactMap(\.current), readingModes: panes.map(\.reading),
                             sidebarTab: sidebarTab, showInspector: showInspector))
        model.vault.saveConfig("workspaces.json", all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    func loadWorkspace(_ w: Workspace) {
        let restored: [Pane] = w.panes.enumerated().map { i, d in
            let p = Pane()
            p.open(d)
            p.reading = w.readingModes.indices.contains(i) ? w.readingModes[i] : false
            return p
        }
        panes = restored.isEmpty ? [Pane()] : Array(restored.prefix(2))
        focusedPaneID = panes[0].id
        sidebarTab = w.sidebarTab
        showInspector = w.showInspector
    }

    func deleteWorkspace(_ w: Workspace) {
        model.vault.saveConfig("workspaces.json", workspaces.filter { $0.name != w.name })
    }
}

struct WorkspacesView: View {
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var list: [Workspace] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Save current layout") {
                    HStack {
                        TextField("Workspace name", text: $name).onSubmit(save)
                        Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section("Saved workspaces") {
                    if list.isEmpty { Text("No workspaces yet").foregroundStyle(.secondary) }
                    ForEach(list) { w in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(w.name)
                                Text(w.panes.map(\.title).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Load") { window.loadWorkspace(w); dismiss() }
                        }
                        .swipeActions { Button("Delete", role: .destructive) { window.deleteWorkspace(w); list = window.workspaces } }
                        .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { window.deleteWorkspace(w); list = window.workspaces } }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Workspaces")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 440, minHeight: 360)
        .onAppear { list = window.workspaces }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        window.saveWorkspace(named: n)
        list = window.workspaces
        name = ""
    }
}
