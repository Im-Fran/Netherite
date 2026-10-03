import SwiftUI
import NetheriteCore

/// Vault › Plugins: which optional features this vault uses.
struct PluginsSettingsView: View {
    @Bindable var model: VaultModel

    var body: some View {
        Form {
            Section {
                Text("Plugins add optional features to this vault.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Plugins")
    }
}
