import SwiftUI
import NetheriteCore

/// First screen: create a vault (iCloud or on this device), open a folder, or reopen a recent vault.
struct VaultPicker: View {
    let onOpen: (VaultModel) -> Void
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var useICloud = true
    @State private var iCloudURL: URL?
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("Netherite").font(.largeTitle.bold())
                        Text("Your thoughts, in plain Markdown files you own.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                Section("Create a new vault") {
                    TextField("Vault name", text: $name)
                    Toggle("Store in iCloud Drive", isOn: $useICloud)
                        .disabled(iCloudURL == nil)
                    if iCloudURL == nil {
                        Text("iCloud Drive isn't available. The vault will be stored on this device.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Create Vault", action: create)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Open") {
                    Button("Open Folder as Vault…", systemImage: "folder") { importing = true }
                }

                if !app.recents.isEmpty {
                    Section("Recent vaults") {
                        ForEach(app.recents) { r in
                            Button {
                                if let m = app.model(forPath: r.path) { onOpen(m) } else { error = String(localized: "“\(r.name)” couldn't be opened.") }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(r.name)
                                    Text(r.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                            }
                            .contextMenu { Button("Remove from list", role: .destructive) { app.forget(r) } }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Welcome")
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): onOpen(app.openVault(at: url))
            case .failure(let e): error = e.localizedDescription
            }
        }
        .alert("Couldn't open vault", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
        .task {
            iCloudURL = await AppModel.iCloudDocuments()
            useICloud = iCloudURL != nil
        }
    }

    private func create() {
        let parent = useICloud ? (iCloudURL ?? AppModel.localDocuments) : AppModel.localDocuments
        do { onOpen(try app.createVault(named: name.trimmingCharacters(in: .whitespaces), in: parent)) }
        catch { self.error = error.localizedDescription }
    }
}
