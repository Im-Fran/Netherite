import SwiftUI
import NetheriteCore

@main
struct NetheriteApp: App {
    @State private var app = AppModel.shared

    init() { NetheriteTips.configure() }

    var body: some Scene {
        WindowGroup(id: "vault", for: String.self) { $vaultPath in
            RootView(vaultPath: $vaultPath)
                .environment(app)
        } defaultValue: {
            AppModel.shared.launchVaultPath
        }
        .commands { NetheriteCommands() }
        // Links (netherite://…, Spotlight) go to an existing window instead of spawning a new one.
        .handlesExternalEvents(matching: [])
        #if os(macOS)
        .defaultSize(width: 1200, height: 780)
        #endif

        #if os(macOS)
        // One tour window for the whole app (a per-window sheet would stack with several vault windows).
        Window("Welcome to Netherite", id: "welcome") { OnboardingView() }
            .windowResizability(.contentSize)
            .defaultPosition(.center)
            .restorationBehavior(.disabled)

        Settings {
            SettingsRoot().environment(app)
        }
        #endif
    }
}

/// Shows the vault picker until a vault is chosen for this window.
struct RootView: View {
    @Binding var vaultPath: String
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    @State private var window: WindowState?
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            if let window {
                VaultWindow(window: window)
                    .id(ObjectIdentifier(window))
                    .tint(Color(pair: window.model.theme.accent, fallback: .accentColor))
            } else {
                VaultPicker { vaultPath = AppModel.key($0.vault.root) }
                    .onOpenURL { url in
                        // netherite://guide opens the guide vault from the start page (and from Shortcuts).
                        guard url.host() == "guide" else { return }
                        Task {
                            let parent = await AppModel.iCloudDocuments() ?? AppModel.localDocuments
                            if let m = try? app.createGuideVault(in: parent) { vaultPath = AppModel.key(m.vault.root) }
                        }
                    }
            }
        }
        #if os(macOS)
        .task { if !hasSeenOnboarding { openWindow(id: "welcome") } }
        .onChange(of: hasSeenOnboarding) { _, seen in if !seen { openWindow(id: "welcome") } }
        #else
        .fullScreenCover(isPresented: Binding(get: { !hasSeenOnboarding }, set: { if !$0 { hasSeenOnboarding = true } })) { OnboardingView() }
        #endif
        .task {
            // Restored windows keep their last vault; the launch preference wins for the first one.
            guard !app.launchApplied else { return }
            app.launchApplied = true
            vaultPath = app.launchVaultPath
            await app.refreshTrash()
            await app.refreshStorage()
        }
        .onChange(of: app.open.keys.sorted()) { _, keys in
            // The vault was deleted or moved into iCloud from Settings: follow it, or go back to the start page.
            guard let window, case let key = AppModel.key(window.model.vault.root), !keys.contains(key) else { return }
            vaultPath = app.relocated[key] ?? ""
        }
        .task(id: vaultPath) {
            // Resolve outside of `body`: opening a vault mutates observed app state.
            window = vaultPath.isEmpty ? nil : app.model(forPath: vaultPath).map { WindowState(model: $0) }
            window?.closeVault = { vaultPath = "" }
        }
    }
}

/// macOS Settings window: Netherite's own settings (each vault's are in its window, under Vault Settings…).
struct SettingsRoot: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        SettingsView()
    }
}

struct NetheriteCommands: Commands {
    @FocusedValue(\.window) private var window
    @FocusedValue(\.editor) private var editor
    @Environment(\.openWindow) private var openWindow

    /// Plugin commands stay visible when no vault window is focused (they're disabled then).
    private func enabled(_ p: CorePlugin) -> Bool { window?.model.settings.isEnabled(p) ?? true }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") { window?.newNote() }.keyboardShortcut("n").disabled(window == nil)
            Button("New Note in New Pane") {
                if let w = window, let p = w.model.newNote() { w.open(path: p, newPane: true) }
            }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(window == nil)
            Button("New Window") { openWindow(id: "vault", value: window?.model.vault.root.path(percentEncoded: false) ?? "") }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("Open Vault…") { openWindow(id: "vault", value: "") }
            Divider()
            Button("Import Files…") { window?.importTarget = "" }.keyboardShortcut("i", modifiers: [.command, .shift]).disabled(window == nil)
            Button("Export Vault…") { window?.export("") }.disabled(window == nil)
            Divider()
            Button("Go to File…") { window?.sheet = .quickSwitcher }.keyboardShortcut("o").disabled(window == nil)
            Button("Command Palette…") { window?.sheet = .commandPalette }.keyboardShortcut("p").disabled(window == nil)
            if enabled(.dailyNotes) {
                Button("Open Today's Daily Note") { window?.openDailyNote() }.keyboardShortcut("d", modifiers: [.command, .shift]).disabled(window == nil)
            }
            if enabled(.meetingNotes) {
                Button("New Meeting Note…") { window?.sheet = .meetingNote }.disabled(window == nil)
            }
        }
        CommandGroup(after: .appSettings) {
            Button("Vault Settings…") { window?.sheet = .vaultSettings(nil) }
                .keyboardShortcut(",", modifiers: [.command, .option]).disabled(window == nil)
        }
        CommandGroup(after: .saveItem) {
            Button("Save") { window?.model.flushAll() }.keyboardShortcut("s").disabled(window == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Search in All Files") {
                window?.sidebarTab = .search; window?.columnVisibility = .all; window?.preferredCompactColumn = .sidebar
            }.keyboardShortcut("f", modifiers: [.command, .shift]).disabled(window == nil)
        }
        CommandMenu("Format") {
            Group {
                Button("Bold") { editor?.wrap("**") }.keyboardShortcut("b")
                Button("Italic") { editor?.wrap("*") }.keyboardShortcut("i")
                Button("Strikethrough") { editor?.wrap("~~") }.keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Highlight") { editor?.wrap("==") }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Inline Code") { editor?.wrap("`") }.keyboardShortcut("c", modifiers: [.command, .option])
                Button("Internal Link") { editor?.wrap("[[", "]]") }.keyboardShortcut("k")
                Divider()
                ForEach(1...3, id: \.self) { level in
                    Button("Heading \(level)") { editor?.toggleLinePrefix(String(repeating: "#", count: level) + " ") }
                        .keyboardShortcut(KeyEquivalent(Character("\(level)")), modifiers: .control)
                }
                Button("Bulleted List") { editor?.toggleLinePrefix("- ") }
                Button("Numbered List") { editor?.toggleLinePrefix("1. ") }
                Button("Checklist") { editor?.toggleLinePrefix("- [ ] ") }.keyboardShortcut("l")
                Button("Quote") { editor?.toggleLinePrefix("> ") }
                if enabled(.templates) {
                    Divider()
                    Button("Insert Template…") { window?.sheet = .templates }.keyboardShortcut("t", modifiers: [.command, .shift])
                }
            }
            .disabled(editor == nil)
        }
        CommandGroup(before: .sidebar) {
            Button("Toggle Reading View") { window?.pane.reading.toggle() }.keyboardShortcut("e").disabled(window?.currentNote == nil)
            if enabled(.graph) {
                Button("Graph View") { window?.open(.graph) }.keyboardShortcut("g", modifiers: [.command, .control]).disabled(window == nil)
            }
            Button("Split Right") { window?.split() }.keyboardShortcut("\\").disabled(window == nil)
            Button("Toggle Inspector") { window?.showInspector.toggle() }.keyboardShortcut("i", modifiers: [.command, .option]).disabled(window == nil)
            Divider()
        }
        CommandGroup(replacing: .help) {
            Button("Welcome Tour") { UserDefaults.standard.set(false, forKey: "hasSeenOnboarding") }
            Button("Open the Guide Vault") {
                Task {
                    let parent = await AppModel.iCloudDocuments() ?? AppModel.localDocuments
                    if let m = try? AppModel.shared.createGuideVault(in: parent) {
                        openWindow(id: "vault", value: AppModel.key(m.vault.root))
                    }
                }
            }
            Button("Show Tips Again on Next Launch") {
                // Takes effect on next launch (TipKit's store can only be reset before it's configured).
                UserDefaults.standard.set(true, forKey: "resetTipsOnLaunch")
            }
            Divider()
            Link("Markdown Syntax Guide", destination: URL(string: "https://www.markdownguide.org/basic-syntax/")!)
        }
    }
}
