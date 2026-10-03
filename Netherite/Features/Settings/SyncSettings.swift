import SwiftUI
import NetheriteCore

/// Vault › Sync: iCloud state of the vault, the files moving right now and the time left.
struct SyncSettingsView: View {
    let model: VaultModel
    @Environment(AppModel.self) private var app

    /// Rows shown at most; a vault being imported can have thousands of files in flight.
    private static let maxRows = 200

    var body: some View {
        let key = AppModel.key(model.vault.root)
        let storage = app.storage[key]
        Form {
            Section { header(storage, progress: app.syncProgress[key]) }
            if let storage, storage.status != .local {
                files(storage)
            }
            Section {
                LabeledContent("Location", value: AppModel.displayLocation(key))
                LabeledContent("Size", value: storage.map { $0.bytes.formatted(.byteCount(style: .file)) } ?? "—")
                LabeledContent("Files", value: storage.map { "\($0.files)" } ?? "—")
            } footer: {
                if storage?.status == .local {
                    Text("This vault is stored only on this device. To sync it with your other devices, move it to iCloud Drive in Netherite Settings › Vaults and Storage.")
                } else {
                    Text("iCloud syncs changes in the background, also while Netherite is closed.")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Sync")
        .pollingSync(of: key)
    }

    @ViewBuilder private func header(_ storage: VaultStorage?, progress: SyncProgress?) -> some View {
        HStack(spacing: 14) {
            SyncStatusIcon(status: storage?.status, isInICloud: key.contains("/Mobile Documents/"))
                .font(.title)
                .frame(width: 52, height: 52)
                .background(.tint.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(storage?.status.label ?? "Checking Sync Status…").font(.headline)
                if let storage, storage.hasChanges {
                    storage.changesSummary.font(.callout).foregroundStyle(.secondary)
                } else if storage?.status == .synced {
                    Text("All changes are in iCloud.").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        if let storage, storage.hasChanges, let progress {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress.fraction)
                HStack {
                    Text("\(progress.remaining.formatted(.byteCount(style: .file))) of \(progress.total.formatted(.byteCount(style: .file))) left")
                    Spacer()
                    progress.timeLeft ?? Text("Estimating time…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func files(_ storage: VaultStorage) -> some View {
        // Moving files first, then the ones waiting.
        let rows = storage.transfers.sorted { ($0.direction == .waiting ? 1 : 0, $0.path) < ($1.direction == .waiting ? 1 : 0, $1.path) }
        Section {
            if rows.isEmpty {
                Label("Everything is up to date", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
            ForEach(rows.prefix(Self.maxRows)) { TransferRow(transfer: $0) }
        } header: {
            Text("Files")
        } footer: {
            if rows.count > Self.maxRows {
                Text("Showing \(Self.maxRows) of \(rows.count) files.")
            }
        }
    }

    private var key: String { AppModel.key(model.vault.root) }
}

private struct TransferRow: View {
    let transfer: SyncTransfer

    var body: some View {
        let name = (transfer.path as NSString).lastPathComponent
        let folder = (transfer.path as NSString).deletingLastPathComponent
        HStack(spacing: 12) {
            Image(systemName: transfer.direction.symbol)
                .foregroundStyle(transfer.direction == .waiting ? Color.secondary : Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1).truncationMode(.middle)
                (folder.isEmpty ? Text(transfer.direction.label) : Text("\(Text(transfer.direction.label)) · \(folder)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(transfer.bytes.formatted(.byteCount(style: .file)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
