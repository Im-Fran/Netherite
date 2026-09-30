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
            AppModel.shared.lastVaultPath ?? ""
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
        .task(id: vaultPath) {
            // Resolve outside of `body`: opening a vault mutates observed app state.
            window = vaultPath.isEmpty ? nil : app.model(forPath: vaultPath).map { WindowState(model: $0) }
        }
    }
}

/// macOS Settings window: edits the most recently used vault.
struct SettingsRoot: View {
    @Environment(AppModel.self) private var app
    var body: some View {
        if let path = app.lastVaultPath, let model = app.model(forPath: path) {
            SettingsView(model: model).frame(width: 560, height: 560)
        } else {
            ContentUnavailableView("Open a Vault to Change Its Settings", systemImage: "gearshape").frame(width: 400, height: 240)
        }
    }
}

struct NetheriteCommands: Commands {
    @FocusedValue(\.window) private var window
    @FocusedValue(\.editor) private var editor
    @Environment(\.openWindow) private var openWindow

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
            Button("Go to File…") { window?.sheet = .quickSwitcher }.keyboardShortcut("o").disabled(window == nil)
            Button("Command Palette…") { window?.sheet = .commandPalette }.keyboardShortcut("p").disabled(window == nil)
            Button("Open Today's Daily Note") { window?.openDailyNote() }.keyboardShortcut("d", modifiers: [.command, .option]).disabled(window == nil)
        }
        CommandGroup(after: .saveItem) {
            Button("Save") { window?.model.flushAll() }.keyboardShortcut("s").disabled(window == nil)
        }
        CommandGroup(after: .textEditing) {
            Button("Search in All Files") {
                window?.sidebarTab = .search; window?.columnVisibility = .all
            }.keyboardShortcut("f", modifiers: [.command, .shift]).disabled(window == nil)
        }
        CommandMenu("Format") {
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
            Divider()
            Button("Insert Template…") { window?.sheet = .templates }.keyboardShortcut("t", modifiers: [.command, .option])
        }
        CommandGroup(before: .sidebar) {
            Button("Toggle Reading View") { window?.pane.reading.toggle() }.keyboardShortcut("e").disabled(window?.currentNote == nil)
            Button("Graph View") { window?.open(.graph) }.keyboardShortcut("g").disabled(window == nil)
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
