import SwiftUI
import CryptoKit
import NetheriteCore

/// Periodic snapshots of changed notes, stored outside the vault (Application Support) so they never sync.
struct SnapshotStore {
    let vault: Vault

    var root: URL {
        let id = SHA256.hash(data: Data(vault.root.path(percentEncoded: false).utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return URL.applicationSupportDirectory.appending(path: "Netherite/Snapshots/\(id)", directoryHint: .isDirectory)
    }

    private func folder(for path: String) -> URL { root.appending(path: path, directoryHint: .isDirectory) }

    struct Snapshot: Identifiable, Hashable {
        var url: URL
        var date: Date
        var id: URL { url }
    }

    func snapshots(for path: String) -> [Snapshot] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder(for: path), includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { u in
            Double(u.deletingPathExtension().lastPathComponent).map { Snapshot(url: u, date: Date(timeIntervalSince1970: $0)) }
        }.sorted { $0.date > $1.date }
    }

    /// Saves `text` unless it equals the latest snapshot.
    func save(_ text: String, for path: String) {
        if let last = snapshots(for: path).first, (try? String(contentsOf: last.url, encoding: .utf8)) == text { return }
        let dir = folder(for: path)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: dir.appending(path: "\(Int(Date.now.timeIntervalSince1970)).md"))
    }

    func prune(olderThan days: Int) {
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86_400)
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        for case let u as URL in e where u.pathExtension == "md" {
            if let t = Double(u.deletingPathExtension().lastPathComponent), Date(timeIntervalSince1970: t) < cutoff {
                try? FileManager.default.removeItem(at: u)
            }
        }
    }
}

/// Takes snapshots of notes modified since the last pass, on the interval set in Settings.
struct SnapshotModifier: ViewModifier {
    let model: VaultModel
    @State private var lastPass = Date.distantPast

    func body(content: Content) -> some View {
        content.task(id: model.settings.snapshotIntervalMinutes) {
            let store = SnapshotStore(vault: model.vault)
            store.prune(olderThan: model.settings.snapshotRetentionDays)
            while !model.index.isLoaded && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(300)) }
            while !Task.isCancelled {
                // The first pass (distantPast) snapshots everything so there's always a baseline.
                for rec in model.index.notes.values where rec.modified >= lastPass {
                    store.save(rec.text, for: rec.path)
                }
                lastPass = .now
                try? await Task.sleep(for: .seconds(max(60, model.settings.snapshotIntervalMinutes * 60)))
            }
        }
    }
}

extension View {
    func snapshotting(_ model: VaultModel) -> some View { modifier(SnapshotModifier(model: model)) }
}

struct FileRecoveryView: View {
    let path: String
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    @State private var selection: SnapshotStore.Snapshot?
    @State private var snapshots: [SnapshotStore.Snapshot] = []

    var body: some View {
        NavigationSplitView {
            List(snapshots, selection: $selection) { s in
                Text(s.date.formatted(date: .abbreviated, time: .shortened)).tag(s)
            }
            .navigationTitle(path.noteName)
            .overlay { if snapshots.isEmpty { ContentUnavailableView("No snapshots yet", systemImage: "clock.arrow.circlepath") } }
        } detail: {
            if let s = selection, let text = try? String(contentsOf: s.url, encoding: .utf8) {
                ScrollView {
                    Text(text).font(.body.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Copy", systemImage: "doc.on.doc") { copyToPasteboard(text) }
                        Button("Restore", systemImage: "arrow.uturn.backward") {
                            SnapshotStore(vault: window.model.vault).save(window.model.text(of: path), for: path)
                            window.model.edit(path, text: text)
                            window.model.save(path)
                            dismiss()
                        }
                        .help("Replace the current note with this snapshot (the current version is snapshotted first)")
                    }
                }
            } else {
                ContentUnavailableView("Select a snapshot", systemImage: "clock")
            }
        }
        .frame(minWidth: 700, minHeight: 460)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .onAppear { snapshots = SnapshotStore(vault: window.model.vault).snapshots(for: path); selection = snapshots.first }
    }
}
