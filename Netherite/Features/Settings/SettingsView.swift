import SwiftUI
import NetheriteCore

struct SettingsView: View {
    @Bindable var model: VaultModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @State private var tipsReset = false
    @State private var themeError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Editor") {
                    Toggle("Readable line length", isOn: $model.settings.readableLineLength)
                    Toggle("Spellcheck", isOn: $model.settings.spellcheck)
                    Toggle("Open notes in reading view", isOn: $model.settings.defaultToReadingMode)
                    Toggle("Use [[Wikilinks]]", isOn: $model.settings.useWikilinks)
                }
                Section("Files and links") {
                    folderField("Default location for new notes", $model.settings.newNoteFolder)
                    folderField("Attachments folder", $model.settings.attachmentFolder)
                }
                Section("Appearance") {
                    Picker("Theme", selection: $model.settings.theme) {
                        ForEach(model.themes) { Text($0.displayName).tag($0.name) }
                    }
                    LabeledContent("Custom themes") {
                        Text(".netherite/themes/*.json").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Button("Create Theme from Current…") { createThemeFile() }
                }
                Section("Daily notes") {
                    folderField("Folder", $model.settings.dailyNotes.folder)
                    textField("Date format", $model.settings.dailyNotes.format)
                    Text("Example: \(Templates.format(.now, model.settings.dailyNotes.format))").font(.caption).foregroundStyle(.secondary)
                    textField("Template file", $model.settings.dailyNotes.template)
                    Toggle("Open daily note on startup", isOn: $model.settings.dailyNotes.openOnStartup)
                }
                Section("Templates") {
                    folderField("Template folder", $model.settings.templatesFolder)
                    Text("Use {{title}}, {{date}}, {{time}} or {{date:YYYY-MM-DD}} in templates.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Unique note creator") {
                    folderField("Folder", $model.settings.uniqueNote.folder)
                    textField("Name format", $model.settings.uniqueNote.format)
                    textField("Template file", $model.settings.uniqueNote.template)
                }
                Section("File recovery") {
                    Stepper("Snapshot every \(model.settings.snapshotIntervalMinutes) min", value: $model.settings.snapshotIntervalMinutes, in: 1...60)
                    Stepper("Keep snapshots for \(model.settings.snapshotRetentionDays) days", value: $model.settings.snapshotRetentionDays, in: 1...90)
                }
                Section("Help") {
                    Button("Show Welcome Tour") { UserDefaults.standard.set(false, forKey: "hasSeenOnboarding") }
                    Button("Show Tips Again") { UserDefaults.standard.set(true, forKey: "resetTipsOnLaunch"); tipsReset = true }
                    if tipsReset {
                        Text("Tips will show again the next time you open Netherite.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Section("About") {
                    LabeledContent("Vault", value: model.vault.root.path(percentEncoded: false))
                    LabeledContent("Notes", value: "\(model.index.markdownFiles.count)")
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                #else
                if isPresented { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                #endif
            }
            .alert("Couldn't Create Theme", isPresented: Binding(get: { themeError != nil }, set: { if !$0 { themeError = nil } })) {
                Button("OK") {}
            } message: { Text(themeError ?? "") }
        }
    }

    /// On iOS a filled text field hides its placeholder, so show the label beside it.
    @ViewBuilder private func textField(_ label: LocalizedStringKey, _ text: Binding<String>) -> some View {
        #if os(iOS)
        LabeledContent(label) { TextField(label, text: text).multilineTextAlignment(.trailing) }
        #else
        TextField(label, text: text)
        #endif
    }

    private func folderField(_ label: LocalizedStringKey, _ binding: Binding<String>) -> some View {
        Picker(label, selection: binding) {
            Text("Vault root").tag("")
            ForEach(model.index.folders, id: \.self) { Text($0).tag($0) }
            if !binding.wrappedValue.isEmpty && !model.index.folders.contains(binding.wrappedValue) {
                Text(binding.wrappedValue).tag(binding.wrappedValue)
            }
        }
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
