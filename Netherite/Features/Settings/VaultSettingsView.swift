import SwiftUI
import NetheriteCore

/// One vault's preferences (stored in `.netherite/app.json`, so they sync with the vault), kept apart from
/// Netherite's own settings. iPhone/iPad push pages from a list; the Mac shows a sidebar of pages.
struct VaultSettingsView: View {
    let model: VaultModel
    /// Page to open first (the sync footer opens Sync).
    var initialPage: VaultSettingsPage?
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    @State private var selection: VaultSettingsPage = .sync
    #else
    @State private var path: [VaultSettingsPage] = []
    #endif

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(VaultSettingsPage.sections, id: \.self) { section in
                    Section {
                        ForEach(section) { page in
                            SettingsTile(page.title, symbol: page.symbol, tint: page.tint).tag(page)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .navigationTitle(model.name)
        } detail: {
            NavigationStack { VaultSettingsPageView(model: model, page: selection) }
        }
        .frame(minWidth: 760, minHeight: 540)
        .safeAreaInset(edge: .bottom) {
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding().background(.bar)
        }
        .onAppear { if let initialPage { selection = initialPage } }
        #else
        NavigationStack(path: $path) {
            VaultSettingsHome(model: model)
                .navigationDestination(for: VaultSettingsPage.self) { VaultSettingsPageView(model: model, page: $0) }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { if let initialPage, path.isEmpty { path = [initialPage] } }
        #endif
    }
}

#if os(iOS)
/// Root list of a vault's settings: the vault and its sync state, then its pages.
private struct VaultSettingsHome: View {
    let model: VaultModel
    @Environment(AppModel.self) private var app
    @ScaledMetric private var tile = 48.0

    var body: some View {
        let status = app.storage[AppModel.key(model.vault.root)]?.status
        Form {
            Section {
                NavigationLink(value: VaultSettingsPage.sync) {
                    HStack(spacing: 14) {
                        SyncStatusIcon(status: status, isInICloud: model.vault.root.path.contains("/Mobile Documents/"))
                            .font(.title2)
                            .frame(width: tile, height: tile)
                            .background(.tint.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name).font(.title3.bold())
                            Text(status?.label ?? "Checking Sync Status…").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
            ForEach(VaultSettingsPage.sections.dropFirst(), id: \.self) { section in
                Section {
                    ForEach(section) { page in
                        NavigationLink(value: page) { SettingsTile(page.title, symbol: page.symbol, tint: page.tint) }
                    }
                }
            }
            Section("About") {
                LabeledContent("Location", value: AppModel.displayLocation(AppModel.key(model.vault.root)))
                LabeledContent("Notes", value: "\(model.index.markdownFiles.count)")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Vault Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

enum VaultSettingsPage: String, CaseIterable, Identifiable, Hashable {
    case sync, editor, files, appearance, dailyNotes, templates, plugins, recovery
    var id: String { rawValue }

    /// Grouping of the list: sync on its own, then how the vault works, then extras.
    static let sections: [[VaultSettingsPage]] = [[.sync], [.editor, .files, .appearance], [.dailyNotes, .templates, .plugins, .recovery]]

    var title: LocalizedStringKey {
        switch self {
        case .sync: "Sync"
        case .editor: "Editor"
        case .files: "Files and Links"
        case .appearance: "Appearance"
        case .dailyNotes: "Daily Notes"
        case .templates: "Templates"
        case .plugins: "Plugins"
        case .recovery: "File Recovery"
        }
    }

    var symbol: String {
        switch self {
        case .sync: "arrow.triangle.2.circlepath.icloud"
        case .editor: "character.cursor.ibeam"
        case .files: "folder"
        case .appearance: "paintpalette"
        case .dailyNotes: "calendar"
        case .templates: "doc.on.doc"
        case .plugins: "puzzlepiece.extension"
        case .recovery: "clock.arrow.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .sync: .blue
        case .editor: .indigo
        case .files: .cyan
        case .appearance: .purple
        case .dailyNotes: .red
        case .templates: .orange
        case .plugins: .pink
        case .recovery: .green
        }
    }
}

/// A page with its own layout, or one of the simple forms below.
struct VaultSettingsPageView: View {
    let model: VaultModel
    let page: VaultSettingsPage

    var body: some View {
        switch page {
        case .sync: SyncSettingsView(model: model)
        case .appearance: AppearanceSettingsView(model: model)
        case .plugins: PluginsSettingsView(model: model)
        default: VaultSettingsForm(model: model, page: page)
        }
    }
}

struct VaultSettingsForm: View {
    @Bindable var model: VaultModel
    let page: VaultSettingsPage
    @State private var snapshotBytes: Int64?
    @State private var confirmClearSnapshots = false
    @State private var error: String?

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .navigationTitle(page.title)
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .editor:
            Section {
                Toggle("Readable Line Length", isOn: $model.settings.readableLineLength)
                Toggle("Spellcheck", isOn: $model.settings.spellcheck)
                Toggle("Open Notes in Reading View", isOn: $model.settings.defaultToReadingMode)
                Toggle("Use [[Wikilinks]]", isOn: $model.settings.useWikilinks)
            }
        case .files:
            Section {
                folderField("Default Location for New Notes", $model.settings.newNoteFolder)
                folderField("Attachments Folder", $model.settings.attachmentFolder)
            }
        case .dailyNotes:
            Section {
                folderField("Folder", $model.settings.dailyNotes.folder)
                textField("Date Format", $model.settings.dailyNotes.format)
                Text("Example: \(Templates.format(.now, model.settings.dailyNotes.format))").font(.caption).foregroundStyle(.secondary)
                textField("Template File", $model.settings.dailyNotes.template)
                Toggle("Open Daily Note on Startup", isOn: $model.settings.dailyNotes.openOnStartup)
            }
        case .templates:
            Section {
                folderField("Template Folder", $model.settings.templatesFolder)
            } footer: {
                Text("Use {{title}}, {{date}}, {{time}} or {{date:YYYY-MM-DD}} in templates.")
            }
            AddBuiltInTemplatesButton(model: model)
            Section("Unique Note Creator") {
                folderField("Folder", $model.settings.uniqueNote.folder)
                textField("Name Format", $model.settings.uniqueNote.format)
                textField("Template File", $model.settings.uniqueNote.template)
            }
        case .recovery:
            recovery
        case .sync, .appearance, .plugins:
            EmptyView()
        }
    }

    @ViewBuilder private var recovery: some View {
        Section {
            Picker("Take a Snapshot Every", selection: $model.settings.snapshotIntervalMinutes) {
                ForEach(Self.options([1, 5, 10, 15, 30, 60], model.settings.snapshotIntervalMinutes), id: \.self) { Text("\($0) min").tag($0) }
            }
            Picker("Keep Snapshots For", selection: $model.settings.snapshotRetentionDays) {
                ForEach(Self.options([1, 7, 14, 30, 60, 90], model.settings.snapshotRetentionDays), id: \.self) { Text("\($0) days").tag($0) }
            }
        } footer: {
            Text("Netherite saves a copy of each changed note on this interval. Open a note’s snapshots from its More menu.")
        }
        Section {
            LabeledContent("Space Used", value: snapshotBytes.map { $0.formatted(.byteCount(style: .file)) } ?? "—")
            Button("Delete All Snapshots", role: .destructive) { confirmClearSnapshots = true }
                .disabled(snapshotBytes == 0)
        } footer: {
            Text("Snapshots are stored only on this device and never sync.")
        }
        .task(id: confirmClearSnapshots) {
            let root = SnapshotStore(vault: model.vault).root
            snapshotBytes = await Task.detached { VaultStorage.scan(root).bytes }.value
        }
        .confirmationDialog("Delete All Snapshots?", isPresented: $confirmClearSnapshots, titleVisibility: .visible) {
            Button("Delete All Snapshots", role: .destructive) {
                do { try FileManager.default.removeItem(at: SnapshotStore(vault: model.vault).root) } catch { self.error = error.localizedDescription }
            }
        } message: {
            Text("Earlier versions of this vault’s notes can no longer be restored.")
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
    }

    /// Preset values, plus the current one when it was set to something else.
    private static func options(_ presets: [Int], _ current: Int) -> [Int] { Array(Set(presets + [current])).sorted() }

    /// On iOS a filled text field hides its placeholder, so show the label beside it.
    @ViewBuilder private func textField(_ label: LocalizedStringKey, _ text: Binding<String>) -> some View {
        #if os(iOS)
        LabeledContent(label) { TextField(label, text: text).multilineTextAlignment(.trailing) }
        #else
        TextField(label, text: text)
        #endif
    }

    private func folderField(_ label: LocalizedStringKey, _ binding: Binding<String>) -> some View {
        VaultFolderPicker(label: label, selection: binding, folders: model.index.folders)
    }
}

/// Picker of the vault's folders, keeping a configured folder that doesn't exist (yet).
struct VaultFolderPicker: View {
    let label: LocalizedStringKey
    @Binding var selection: String
    let folders: [String]

    var body: some View {
        Picker(label, selection: $selection) {
            Text("Vault root").tag("")
            ForEach(folders, id: \.self) { Text($0).tag($0) }
            if !selection.isEmpty && !folders.contains(selection) {
                Text(selection).tag(selection)
            }
        }
    }
}
