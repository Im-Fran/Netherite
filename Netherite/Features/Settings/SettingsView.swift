import SwiftUI
import NetheriteCore

/// Settings: app-wide pages (launch, vaults and storage, Recently Deleted) plus the open vault's preferences.
/// iPhone/iPad get a Settings-app style list of pages; the Mac gets a tabbed Settings window.
struct SettingsView: View {
    var model: VaultModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsView(model: model) }
            Tab("Vaults", systemImage: "externaldrive.badge.icloud") {
                NavigationStack { VaultsSettingsView().settingsDestinations(model: model) }
            }
            if let model {
                ForEach(VaultSettingsPage.allCases) { page in
                    Tab(page.title, systemImage: page.symbol) { VaultSettingsForm(model: model, page: page) }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        #else
        NavigationStack {
            SettingsHome(model: model)
                .settingsDestinations(model: model)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #endif
    }
}

enum SettingsRoute: Hashable {
    case general, vaults, recentlyDeleted
    case vault(String)
    case page(VaultSettingsPage)
}

extension View {
    func settingsDestinations(model: VaultModel?) -> some View {
        navigationDestination(for: SettingsRoute.self) { route in
            switch route {
            case .general: GeneralSettingsView(model: model)
            case .vaults: VaultsSettingsView()
            case .recentlyDeleted: RecentlyDeletedView()
            case .vault(let path): VaultDetailView(path: path)
            case .page(let page): if let model { VaultSettingsForm(model: model, page: page) }
            }
        }
    }
}

// MARK: Home (iOS)

/// Root list, laid out like the system Settings app: a header card, then rows with colored icons.
private struct SettingsHome: View {
    let model: VaultModel?
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section {
                SettingsHeader()
                NavigationLink(value: SettingsRoute.vaults) {
                    LabeledContent {
                        Text("\(app.recents.count)")
                    } label: {
                        SettingsTile("Vaults and Storage", symbol: "externaldrive.badge.icloud", tint: .blue)
                    }
                }
            }
            if let model {
                Section {
                    ForEach(VaultSettingsPage.allCases) { page in
                        NavigationLink(value: SettingsRoute.page(page)) { SettingsTile(page.title, symbol: page.symbol, tint: page.tint) }
                    }
                } header: {
                    Text("“\(model.name)” Vault")
                }
            }
            Section("Netherite") {
                NavigationLink(value: SettingsRoute.general) { SettingsTile("General", symbol: "gearshape", tint: .gray) }
                NavigationLink(value: SettingsRoute.recentlyDeleted) {
                    LabeledContent {
                        Text(app.trashed.isEmpty ? "" : "\(app.trashed.count)")
                    } label: {
                        SettingsTile("Recently Deleted", symbol: "trash", tint: .red)
                    }
                }
            }
            if let model {
                Section("About") {
                    LabeledContent("Location", value: AppModel.displayLocation(AppModel.key(model.vault.root)))
                    LabeledContent("Notes", value: "\(model.index.markdownFiles.count)")
                    LabeledContent("Version", value: AppModel.versionString)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task { await app.refreshTrash() }
    }
}

/// App icon, name and a line about what's here (like the header of the system Notes settings).
private struct SettingsHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image("Logo")
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            Text("Netherite").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text("Manage your vaults and their iCloud storage, recover deleted vaults, and choose how each vault looks and works.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

/// A row label with a white symbol on a colored rounded square.
struct SettingsTile: View {
    let title: LocalizedStringKey
    let symbol: String
    let tint: Color
    @ScaledMetric private var size: CGFloat = 30

    init(_ title: LocalizedStringKey, symbol: String, tint: Color) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(tint.gradient, in: .rect(cornerRadius: size * 0.27, style: .continuous))
        }
    }
}

// MARK: General

struct GeneralSettingsView: View {
    var model: VaultModel?
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @AppStorage("launchBehavior") private var launchBehavior = "last"
    @AppStorage("launchVaultPath") private var launchVaultPath = ""
    @AppStorage("showGuideOnStartPage") private var showGuide = true
    @State private var tipsReset = false

    var body: some View {
        Form {
            #if os(macOS)
            Section { SettingsHeader() }
            #endif
            Section {
                Picker("Open on Launch", selection: $launchBehavior) {
                    Text("Last Opened Vault").tag("last")
                    Text("Start Page").tag("picker")
                    Text("A Specific Vault").tag("vault")
                }
                if launchBehavior == "vault" {
                    Picker("Vault", selection: $launchVaultPath) {
                        if !app.recents.contains(where: { $0.path == launchVaultPath }) { Text("Choose…").tag(launchVaultPath) }
                        ForEach(app.recents) { Text($0.name).tag($0.path) }
                    }
                }
            } header: {
                Text("Startup")
            } footer: {
                Text("Choose what Netherite shows when you open it.")
            }
            Section {
                Toggle("Show the Guide and Welcome Tour", isOn: $showGuide)
            } header: {
                Text("Start Page")
            } footer: {
                Text("Hides the “Explore the Guide” card and the welcome tour button on the start page.")
            }
            Section("Help") {
                Button("Show Welcome Tour") { UserDefaults.standard.set(false, forKey: "hasSeenOnboarding") }
                Button("Show Tips Again") { UserDefaults.standard.set(true, forKey: "resetTipsOnLaunch"); tipsReset = true }
                if tipsReset {
                    Text("Tips will show again the next time you open Netherite.").font(.callout).foregroundStyle(.secondary)
                }
            }
            #if os(iOS)
            Section {
                Button("Open Netherite in the Settings App") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } footer: {
                Text("These preferences and a storage summary also appear in the Settings app.")
            }
            #else
            Section("About") {
                LabeledContent("Version", value: AppModel.versionString)
                if let model { LabeledContent("Vault", value: AppModel.displayLocation(AppModel.key(model.vault.root))) }
            }
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

// MARK: Vaults and storage

struct VaultsSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var importing = false
    @State private var working = false
    @State private var error: String?
    @State private var iCloudAvailable = false

    var body: some View {
        let cloud = app.recents.filter(\.isInICloud), local = app.recents.filter { !$0.isInICloud }
        Form {
            Section { StorageSummary(cloud: cloud, local: local) }
            if !cloud.isEmpty { Section("iCloud Drive") { ForEach(cloud) { VaultRow(recent: $0) } } }
            if !local.isEmpty { Section(localHeader) { ForEach(local) { VaultRow(recent: $0) } } }
            Section {
                Button("Import Folder into iCloud…", systemImage: "icloud.and.arrow.up") { importing = true }
                    .disabled(!iCloudAvailable || working)
                NavigationLink(value: SettingsRoute.recentlyDeleted) {
                    LabeledContent("Recently Deleted", value: app.trashed.isEmpty ? "" : "\(app.trashed.count)")
                }
            } footer: {
                Text(iCloudAvailable
                     ? "Importing copies a folder of notes from Files into iCloud Drive as a new vault; the original stays where it is."
                     : "Sign in to iCloud and turn on iCloud Drive to sync vaults between your devices.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Vaults and Storage")
        .overlay { if working { ProgressView("Copying to iCloud…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            working = true
            Task {
                defer { working = false }
                do { _ = try await app.importFolderToICloud(url); await app.refreshStorage() } catch { self.error = error.localizedDescription }
            }
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
        .refreshable { await app.refreshStorage() }
        .task {
            iCloudAvailable = await AppModel.iCloudDocuments() != nil
            await app.refreshTrash()
            // ponytail: polling rescans every vault; switch to NSMetadataQuery if large vaults make this costly.
            while !Task.isCancelled {
                await app.refreshStorage()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var localHeader: LocalizedStringKey {
        #if os(macOS)
        "On This Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "On This iPad" : "On This iPhone"
        #endif
    }
}

/// Segmented bar of the space vaults use, like iPhone Storage.
private struct StorageSummary: View {
    let cloud: [RecentVault]
    let local: [RecentVault]
    @Environment(AppModel.self) private var app

    var body: some View {
        let cloudBytes = bytes(cloud), localBytes = bytes(local)
        let total = max(1, cloudBytes + localBytes)
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent {
                Text((cloudBytes + localBytes).formatted(.byteCount(style: .file)))
            } label: {
                Text("Used by Vaults").font(.headline)
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Rectangle().fill(.blue.gradient).frame(width: geo.size.width * Double(cloudBytes) / Double(total))
                    Rectangle().fill(.gray.gradient)
                }
                .clipShape(.capsule)
            }
            .frame(height: 10)
            .accessibilityHidden(true)
            HStack(spacing: 16) {
                legend("iCloud Drive", .blue, cloudBytes)
                legend("This Device", .gray, localBytes)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func bytes(_ list: [RecentVault]) -> Int64 { list.reduce(0) { $0 + (app.storage[$1.path]?.bytes ?? 0) } }

    private func legend(_ title: LocalizedStringKey, _ color: Color, _ bytes: Int64) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
            Text(bytes.formatted(.byteCount(style: .file))).foregroundStyle(.secondary)
        }
    }
}

private struct VaultRow: View {
    let recent: RecentVault
    @Environment(AppModel.self) private var app

    var body: some View {
        let s = app.storage[recent.path]
        NavigationLink(value: SettingsRoute.vault(recent.path)) {
            HStack(spacing: 12) {
                SyncStatusIcon(status: s?.status, isInICloud: recent.isInICloud).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recent.name)
                    if let s {
                        Text("\(s.notes) notes · \(s.bytes.formatted(.byteCount(style: .file)))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct VaultDetailView: View {
    let path: String
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var export: ExportRequest?
    @State private var confirmTrash = false
    @State private var working = false
    @State private var error: String?
    @State private var iCloudAvailable = false

    var body: some View {
        if let recent = app.recents.first(where: { $0.path == path }) {
            form(recent)
        } else {
            ContentUnavailableView("Vault Not Found", systemImage: "questionmark.folder")
        }
    }

    private func form(_ recent: RecentVault) -> some View {
        let s = app.storage[recent.path]
        return Form {
            Section {
                HStack(spacing: 14) {
                    SyncStatusIcon(status: s?.status, isInICloud: recent.isInICloud)
                        .font(.title)
                        .frame(width: 52, height: 52)
                        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recent.name).font(.title3.bold())
                        Text(s?.status.label ?? "Checking Sync Status…").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent("Location", value: AppModel.displayLocation(recent.path))
                LabeledContent("Size", value: s.map { $0.bytes.formatted(.byteCount(style: .file)) } ?? "—")
                LabeledContent("Notes", value: s.map { "\($0.notes)" } ?? "—")
                LabeledContent("Files", value: s.map { "\($0.files)" } ?? "—")
                LabeledContent("Last Opened", value: recent.lastOpened.formatted(.relative(presentation: .named)))
                #if os(macOS)
                Button("Show in Finder", systemImage: "finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: recent.path)])
                }
                #endif
            }
            Section {
                Button("Export Vault…", systemImage: "square.and.arrow.up") {
                    export = ExportRequest(vault: Vault(root: URL(filePath: recent.path, directoryHint: .isDirectory)), path: "")
                }
                if !recent.isInICloud && iCloudAvailable {
                    Button("Move to iCloud Drive", systemImage: "icloud.and.arrow.up") { run { try await app.moveToICloud(recent) } }
                }
            } footer: {
                Text(recent.isInICloud ? "Export saves a .zip copy of the whole vault." : "Moving to iCloud Drive syncs the vault to your other devices.")
            }
            Section {
                Button("Remove from List", systemImage: "minus.circle") { app.forget(recent); dismiss() }
                Button("Move to Recently Deleted", systemImage: "trash", role: .destructive) { confirmTrash = true }
                    .foregroundStyle(.red)
            } footer: {
                Text("Deleted vaults stay in Recently Deleted for 90 days, then are removed for good.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(recent.name)
        .disabled(working)
        .overlay { if working { ProgressView().controlSize(.large) } }
        .exporting($export)
        .confirmationDialog("Delete “\(recent.name)”?", isPresented: $confirmTrash, titleVisibility: .visible) {
            Button("Move to Recently Deleted", role: .destructive) { run { try await app.trashVault(recent); dismiss() } }
        } message: {
            Text("The vault and all its notes move to Recently Deleted on every device. You can restore it for 90 days.")
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
        .task { iCloudAvailable = await AppModel.iCloudDocuments() != nil }
    }

    private func run(_ body: @escaping () async throws -> Void) {
        working = true
        Task {
            defer { working = false }
            do { try await body() } catch { self.error = error.localizedDescription }
        }
    }
}

struct RecentlyDeletedView: View {
    @Environment(AppModel.self) private var app
    @State private var pendingDelete: VaultTrash.Item?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(app.trashed) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "folder").foregroundStyle(.secondary).frame(width: 24).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text(remaining(item)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        #if os(macOS)
                        Button("Recover") { run { try await app.restore(item) } }
                        Button("Delete", role: .destructive) { pendingDelete = item }
                        #endif
                    }
                    .contextMenu {
                        Button("Recover", systemImage: "arrow.uturn.backward") { run { try await app.restore(item) } }
                        Button("Delete Now", systemImage: "trash", role: .destructive) { pendingDelete = item }
                    }
                    #if os(iOS)
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Delete", systemImage: "trash") { pendingDelete = item }.tint(.red)
                        Button("Recover", systemImage: "arrow.uturn.backward") { run { try await app.restore(item) } }.tint(.blue)
                    }
                    #endif
                }
            } footer: {
                if !app.trashed.isEmpty {
                    Text("Vaults are permanently deleted 90 days after you delete them.")
                }
            }
        }
        .overlay {
            if app.trashed.isEmpty {
                ContentUnavailableView("No Deleted Vaults", systemImage: "trash",
                                       description: Text("Vaults you delete stay here for 90 days."))
            }
        }
        .navigationTitle("Recently Deleted")
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")” Permanently?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { item in
            Button("Delete Permanently", role: .destructive) { run { try await app.deleteForever(item) } }
        } message: { _ in
            Text("This can’t be undone.")
        }
        .alert("Something Went Wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
        .task { await app.refreshTrash() }
    }

    private func remaining(_ item: VaultTrash.Item) -> String {
        let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: item.expires()).day ?? 0)
        return String(localized: "\(days) days remaining")
    }

    private func run(_ body: @escaping () async throws -> Void) {
        Task { do { try await body() } catch { self.error = error.localizedDescription } }
    }
}

// MARK: Vault preferences

enum VaultSettingsPage: String, CaseIterable, Identifiable, Hashable {
    case editor, files, appearance, dailyNotes, templates, recovery
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .editor: "Editor"
        case .files: "Files and links"
        case .appearance: "Appearance"
        case .dailyNotes: "Daily notes"
        case .templates: "Templates"
        case .recovery: "File recovery"
        }
    }

    var symbol: String {
        switch self {
        case .editor: "character.cursor.ibeam"
        case .files: "folder"
        case .appearance: "paintpalette"
        case .dailyNotes: "calendar"
        case .templates: "doc.on.doc"
        case .recovery: "clock.arrow.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .editor: .blue
        case .files: .cyan
        case .appearance: .purple
        case .dailyNotes: .red
        case .templates: .orange
        case .recovery: .green
        }
    }
}

struct VaultSettingsForm: View {
    @Bindable var model: VaultModel
    let page: VaultSettingsPage
    @State private var themeError: String?
    @State private var snapshotBytes: Int64?
    @State private var confirmClearSnapshots = false

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .navigationTitle(page.title)
            .alert("Couldn't Create Theme", isPresented: Binding(get: { themeError != nil }, set: { if !$0 { themeError = nil } })) {
                Button("OK") {}
            } message: { Text(themeError ?? "") }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .editor:
            Section {
                Toggle("Readable line length", isOn: $model.settings.readableLineLength)
                Toggle("Spellcheck", isOn: $model.settings.spellcheck)
                Toggle("Open notes in reading view", isOn: $model.settings.defaultToReadingMode)
                Toggle("Use [[Wikilinks]]", isOn: $model.settings.useWikilinks)
            }
        case .files:
            Section {
                folderField("Default location for new notes", $model.settings.newNoteFolder)
                folderField("Attachments folder", $model.settings.attachmentFolder)
            }
        case .appearance:
            Section {
                Picker("Theme", selection: $model.settings.theme) {
                    ForEach(model.themes) { Text($0.displayName).tag($0.name) }
                }
                LabeledContent("Custom themes") {
                    Text(".netherite/themes/*.json").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Button("Create Theme from Current…") { createThemeFile() }
            }
        case .dailyNotes:
            Section {
                folderField("Folder", $model.settings.dailyNotes.folder)
                textField("Date format", $model.settings.dailyNotes.format)
                Text("Example: \(Templates.format(.now, model.settings.dailyNotes.format))").font(.caption).foregroundStyle(.secondary)
                textField("Template file", $model.settings.dailyNotes.template)
                Toggle("Open daily note on startup", isOn: $model.settings.dailyNotes.openOnStartup)
            }
        case .templates:
            Section {
                folderField("Template folder", $model.settings.templatesFolder)
            } footer: {
                Text("Use {{title}}, {{date}}, {{time}} or {{date:YYYY-MM-DD}} in templates.")
            }
            Section("Unique note creator") {
                folderField("Folder", $model.settings.uniqueNote.folder)
                textField("Name format", $model.settings.uniqueNote.format)
                textField("Template file", $model.settings.uniqueNote.template)
            }
        case .recovery:
            recovery
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
            Button("Delete All Snapshots", role: .destructive) { try? FileManager.default.removeItem(at: SnapshotStore(vault: model.vault).root) }
        } message: {
            Text("Earlier versions of this vault’s notes can no longer be restored.")
        }
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
