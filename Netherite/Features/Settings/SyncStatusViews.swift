import SwiftUI
import NetheriteCore

extension SyncStatus {
    /// Folder = on this device · cloud = waiting to upload · cloud with arrow = syncing · cloud with check = synced.
    var symbol: String {
        switch self {
        case .local: "folder"
        case .pending: "icloud"
        case .syncing: "icloud.and.arrow.up"
        case .synced: "checkmark.icloud"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .local: "Stored Locally"
        case .pending: "Waiting to Sync"
        case .syncing: "Syncing…"
        case .synced: "Synced with iCloud"
        }
    }

    var tint: Color {
        switch self {
        case .local: .secondary
        case .pending: .orange
        case .syncing: .blue
        case .synced: .green
        }
    }
}

/// Sync state icon of a vault; nil status (not scanned yet, or unreadable) shows where it lives instead.
struct SyncStatusIcon: View {
    let status: SyncStatus?
    var isInICloud = false

    var body: some View {
        let symbol = status?.symbol ?? (isInICloud ? "icloud" : "folder")
        Image(systemName: symbol)
            .foregroundStyle(status?.tint ?? .secondary)
            .symbolEffect(.pulse, isActive: status == .syncing)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(Text(status?.label ?? (isInICloud ? "iCloud Drive" : "Stored Locally")))
    }
}

/// "Synced with iCloud" footer under the sidebar, kept current while the vault is open.
struct VaultSyncFooter: View {
    let vault: Vault
    @Environment(AppModel.self) private var app

    var body: some View {
        let key = AppModel.key(vault.root)
        let status = app.storage[key]?.status
        HStack(spacing: 6) {
            SyncStatusIcon(status: status).accessibilityHidden(true)
            Text(status?.label ?? "Checking Sync Status…")
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .task(id: key) {
            while !Task.isCancelled {
                await app.refreshStorage([key])
                // Poll faster while files are moving.
                try? await Task.sleep(for: .seconds(app.storage[key]?.status == .syncing ? 2 : 10))
            }
        }
    }
}
