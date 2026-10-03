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

    /// Status color, remapped for the color-vision setting; the symbol and label carry the state too.
    var tint: Color {
        let a = A11y.shared
        return switch self {
        case .local: .secondary
        case .pending: a.color(.orange, .orange)
        case .syncing: a.color(.blue, .blue)
        case .synced: a.color(.green, .green)
        }
    }
}

/// Sync state icon of a vault; nil status (not scanned yet, or unreadable) shows where it lives instead.
struct SyncStatusIcon: View {
    let status: SyncStatus?
    var isInICloud = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let symbol = status?.symbol ?? (isInICloud ? "icloud" : "folder")
        Image(systemName: symbol)
            .foregroundStyle(status?.tint ?? .secondary)
            .symbolEffect(.pulse, isActive: status == .syncing && !reduceMotion)
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel(Text(status?.label ?? (isInICloud ? "iCloud Drive" : "Stored Locally")))
    }
}

extension SyncTransfer.Direction {
    var symbol: String {
        switch self {
        case .upload: "arrow.up.circle"
        case .download: "arrow.down.circle"
        case .waiting: "clock"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .upload: "Uploading"
        case .download: "Downloading"
        case .waiting: "Waiting"
        }
    }
}

extension VaultStorage {
    /// Files are moving or waiting to.
    var hasChanges: Bool { status == .pending || status == .syncing }

    /// "Syncing 3 files", or "Waiting to sync 3 files".
    var changesSummary: Text {
        status == .syncing ? Text("Syncing \(transfers.count) files") : Text("Waiting to sync \(transfers.count) files")
    }
}

extension SyncProgress {
    /// "About 2 min left", once the speed is known.
    var timeLeft: Text? {
        timeRemaining.map { t in
            Text("About \(Duration.seconds(max(1, t)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))) left")
        }
    }
}

/// Polls a vault's storage and sync state while the view is on screen, faster while files are moving.
private struct SyncPolling: ViewModifier {
    let key: String
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.task(id: key) {
            while !Task.isCancelled {
                await app.refreshStorage([key])
                try? await Task.sleep(for: .seconds(app.storage[key]?.hasChanges == true ? 2 : 10))
            }
        }
    }
}

extension View {
    func pollingSync(of key: String) -> some View { modifier(SyncPolling(key: key)) }
}

/// Footer under the sidebar, shown only while the vault has changes to sync; opens Vault Settings › Sync.
struct VaultSyncFooter: View {
    let vault: Vault
    let open: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let key = AppModel.key(vault.root)
        let storage = app.storage[key]
        // The stack stays, empty, while everything is synced, so polling keeps running.
        VStack(spacing: 0) {
            if let storage, storage.hasChanges {
                Divider()
                Button(action: open) {
                    HStack(spacing: 6) {
                        SyncStatusIcon(status: storage.status).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            storage.changesSummary
                            app.syncProgress[key]?.timeLeft?.foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Shows the files being synced")
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .default, value: storage?.hasChanges)
        .pollingSync(of: key)
    }
}
