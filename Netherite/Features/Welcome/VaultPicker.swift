import SwiftUI
import NetheriteCore

/// Start page: create a vault, open a folder, explore the guide vault, or reopen a recent vault.
struct VaultPicker: View {
    let onOpen: (VaultModel) -> Void
    @Environment(AppModel.self) private var app
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var iCloudURL: URL?
    @State private var importing = false
    @State private var creating = false
    @State private var error: String?

    /// Three 300-pt cards plus gaps; the grid and the recents list share this width so their edges line up.
    private static let contentWidth: CGFloat = 3 * 300 + 2 * 16
    private static let minRowWidth: CGFloat = 3 * 220 + 2 * 16

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    hero
                    // Cards and recents share one width so their edges line up. The cards form a centered row
                    // (692–932 pt, equal heights) when it fits, otherwise a column (iPhone, narrow split views).
                    VStack(spacing: 32) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 16) { cards }
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minWidth: Self.minRowWidth)
                            VStack(spacing: 16) { cards }
                        }
                        if !app.recents.isEmpty { recents }
                    }
                    .frame(maxWidth: Self.contentWidth)

                    Button("Take the Welcome Tour", systemImage: "play.circle") { hasSeenOnboarding = false }
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .background(.background)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .sheet(isPresented: $creating) {
            CreateVaultSheet(iCloudURL: iCloudURL) { onOpen($0) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): onOpen(app.openVault(at: url))
            case .failure(let e): error = e.localizedDescription
            }
        }
        .alert("Couldn't Open Vault", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
        .task { iCloudURL = await AppModel.iCloudDocuments() }
    }

    @ViewBuilder private var cards: some View {
        ActionCard(symbol: "plus.square.on.square", tint: .accentColor, title: "Create a Vault",
                   detail: iCloudURL == nil ? "A new folder for your notes on this device." : "A new folder for your notes, synced with iCloud Drive.") {
            creating = true
        }
        ActionCard(symbol: "folder", tint: .blue, title: "Open a Folder",
                   detail: "Use any folder of Markdown files — including an Obsidian vault.") {
            importing = true
        }
        ActionCard(symbol: "graduationcap", tint: .orange, title: "Explore the Guide",
                   detail: "A sample vault that teaches Netherite with interactive notes.") {
            openGuide()
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(.rect(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                .accessibilityHidden(true)
            Text("Netherite")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Your thoughts, in plain Markdown files you own.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var recents: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Vaults").font(.headline).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(app.recents) { r in
                    Button {
                        if let m = app.model(forPath: r.path) { onOpen(m) } else { error = String(localized: "“\(r.name)” couldn't be opened.") }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: r.path.contains("Mobile Documents") ? "icloud" : "folder")
                                .foregroundStyle(.tint)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).foregroundStyle(.primary)
                                Text(r.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Remove from List", role: .destructive) { app.forget(r) } }
                    if r.id != app.recents.last?.id { Divider().padding(.leading, 50) }
                }
            }
            .background(.background.secondary, in: .rect(cornerRadius: 12))
        }
    }

    private func openGuide() {
        Task {
            let parent = await AppModel.iCloudDocuments() ?? AppModel.localDocuments
            do { onOpen(try app.createGuideVault(in: parent)) } catch { self.error = error.localizedDescription }
        }
    }
}

/// A large tappable option on the start page.
private struct ActionCard: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let action: () -> Void
    @State private var hovering = false
    @ScaledMetric private var iconBox: CGFloat = 44

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: iconBox, height: iconBox)
                    .background(tint.opacity(0.14), in: .rect(cornerRadius: 10, style: .continuous))
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(18)
            // Bounded ideal width lets the row fit; maxHeight .infinity keeps every card in a row the same height.
            .frame(idealWidth: 220, maxWidth: .infinity, minHeight: 170, maxHeight: .infinity, alignment: .topLeading)
            .background(.background.secondary, in: .rect(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(hovering ? tint.opacity(0.6) : Color.clear, lineWidth: 1.5))
            .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Name + location for a new vault.
private struct CreateVaultSheet: View {
    let iCloudURL: URL?
    let onCreate: (VaultModel) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var useICloud = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Vault name", text: $name, prompt: Text("My Notes"))
                    .onSubmit(create)
                Toggle("Store in iCloud Drive", isOn: $useICloud)
                    .disabled(iCloudURL == nil)
                if iCloudURL == nil {
                    Text("iCloud Drive isn't available, so the vault will be stored on this device.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle("Create a Vault")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 220)
        #endif
        .onAppear { useICloud = iCloudURL != nil }
    }

    private func create() {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        let parent = useICloud ? (iCloudURL ?? AppModel.localDocuments) : AppModel.localDocuments
        do {
            let model = try app.createVault(named: clean, in: parent)
            dismiss()
            onCreate(model)
        } catch {
            self.error = error.localizedDescription
            AccessibilityNotification.Announcement(error.localizedDescription).post()
        }
    }
}
