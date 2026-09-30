import SwiftUI
import Security
import UniformTypeIdentifiers
import NetheriteCore

/// Publish: export the vault as a static site, or deploy it to Cloudflare Pages.
struct PublishView: View {
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    @State private var options = PublishOptions()
    @State private var token = ""
    @State private var exporting = false
    @State private var exportDocument: SiteFolder?
    @State private var busy = false
    @State private var confirmDeploy = false
    @State private var status: String?
    @State private var deployedURL: URL?
    @State private var error: String?

    private var model: VaultModel { window.model }
    private var notes: [String] { model.index.markdownFiles }

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    Picker("Publish", selection: $options.scope) {
                        Text("Whole vault").tag(PublishOptions.Scope.all)
                        Text("One folder").tag(PublishOptions.Scope.folder)
                        Text("Notes with publish: true").tag(PublishOptions.Scope.published)
                    }
                    if options.scope == .folder {
                        Picker("Folder", selection: $options.folder) {
                            ForEach(model.index.folders, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Picker("Home page", selection: $options.home) {
                        Text("Automatic").tag("")
                        ForEach(notes, id: \.self) { Text($0.noteName).tag($0) }
                    }
                    TextField("Site name", text: $options.siteName, prompt: Text(model.name))
                }

                Section {
                    Button("Export to Folder…", systemImage: "folder.badge.plus", action: exportToFolder)
                        .disabled(busy)
                } footer: {
                    Text("Creates HTML pages, search, a graph and tag pages you can host anywhere.")
                }

                Section {
                    TextField("Account ID", text: $options.accountID)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Project name", text: $options.projectName, prompt: Text("my-notes"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("API token", text: $token)
                    Button { confirmDeploy = true } label: {
                        HStack {
                            Label("Deploy", systemImage: "paperplane")
                            if busy { Spacer(); ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(busy || options.accountID.isEmpty || options.projectName.isEmpty || token.isEmpty)
                    if let status { Text(status).foregroundStyle(.secondary) }
                    if let deployedURL {
                        Link(destination: deployedURL) { Label(deployedURL.absoluteString, systemImage: "safari") }
                    }
                } header: {
                    Text("Cloudflare Pages")
                } footer: {
                    Text("The token needs the “Cloudflare Pages: Edit” permission. It's stored in your Keychain, never in the vault.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Publish")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { save(); dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
        .onAppear {
            options = model.vault.loadConfig("publish.json", fallback: PublishOptions())
            token = Keychain.cloudflareToken ?? ""
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .folder,
                      defaultFilename: options.siteName.isEmpty ? "\(model.name) Site" : options.siteName) { result in
            if case .failure(let e) = result { error = e.localizedDescription }
            else { status = String(localized: "Site exported.") }
        }
        .confirmationDialog("Publish to \(options.projectName).pages.dev?", isPresented: $confirmDeploy, titleVisibility: .visible) {
            Button("Publish") { deploy() }
        } message: {
            Text("The notes in the selected scope will be public on the web. Notes with private content should be excluded first.")
        }
        .alert("Publishing failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: {
            Text(error ?? "")
        }
    }

    private func save() { model.vault.saveConfig("publish.json", options) }

    /// Exports into a temporary folder, then hands it to the system save panel.
    private func exportToFolder() {
        save()
        do {
            let dir = try buildSite()
            exportDocument = SiteFolder(wrapper: try FileWrapper(url: dir))
            exporting = true
        } catch { self.error = error.localizedDescription }
    }

    private func buildSite() throws -> URL {
        model.flushAll()
        let dir = URL.temporaryDirectory.appending(path: "netherite-site-\(UUID().uuidString)", directoryHint: .isDirectory)
        let report = try SiteExporter.export(model.index, to: dir, options: options, theme: model.theme)
        status = String(localized: "Built \(report.pages) pages.")
        return dir
    }

    private func deploy() {
        save()
        Keychain.cloudflareToken = token
        deployedURL = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                let dir = try buildSite()
                let deployer = CloudflarePagesDeployer(accountID: options.accountID, projectName: options.projectName, apiToken: token)
                deployedURL = try await deployer.deploy(dir) { msg in Task { @MainActor in status = msg } }
                status = String(localized: "Deployed.")
                try? FileManager.default.removeItem(at: dir)
            } catch {
                self.error = error.localizedDescription
                status = nil
            }
        }
    }
}

/// A built site folder handed to `.fileExporter`.
struct SiteFolder: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    var wrapper: FileWrapper
    init(wrapper: FileWrapper) { self.wrapper = wrapper }
    init(configuration: ReadConfiguration) throws { wrapper = configuration.file }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { wrapper }
}

/// Minimal generic-password Keychain access for the Cloudflare API token.
enum Keychain {
    static let service = "cl.franciscosolis.netherite.cloudflare"

    static var cloudflareToken: String? {
        get {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
            var out: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
            SecItemDelete(base as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var add = base
            add[kSecValueData as String] = Data(newValue.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
