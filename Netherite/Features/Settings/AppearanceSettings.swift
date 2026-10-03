import SwiftUI
import NetheriteCore

/// Vault › Appearance: the vault's theme.
struct AppearanceSettingsView: View {
    @Bindable var model: VaultModel
    @State private var themeError: String?

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $model.settings.theme) {
                    ForEach(model.themes) { Text($0.displayName).tag($0.name) }
                }
                LabeledContent("Custom themes") {
                    Text(".netherite/themes/*.json").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Button("Create Theme from Current…") { createThemeFile() }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
        .alert("Couldn't Create Theme", isPresented: Binding(get: { themeError != nil }, set: { if !$0 { themeError = nil } })) {
            Button("OK") {}
        } message: { Text(themeError ?? "") }
    }

    private func createThemeFile() {
        var t = model.theme
        t.name = String(localized: "\(t.displayName) Custom")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try enc.encode(t)
            try FileManager.default.createDirectory(at: model.vault.themesURL, withIntermediateDirectories: true)
            try data.write(to: model.vault.themesURL.appending(path: "\(t.name).json"))
            model.reloadThemes()
            model.settings.theme = t.name
        } catch {
            themeError = error.localizedDescription
        }
    }
}
