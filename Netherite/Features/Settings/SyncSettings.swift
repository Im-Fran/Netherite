import SwiftUI
import NetheriteCore

/// Vault › Sync: iCloud state of the vault, the files moving right now and the time left.
struct SyncSettingsView: View {
    let model: VaultModel

    var body: some View {
        Form {
            Section {
                VaultSyncFooter(vault: model.vault)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Sync")
    }
}
