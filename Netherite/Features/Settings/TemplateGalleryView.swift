import SwiftUI
import NetheriteCore

/// Settings › Templates › Template Gallery: templates published on the Netherite website, installed into the templates folder.
struct TemplateGalleryView: View {
    let model: VaultModel
    @State private var entries: [TemplateCatalog.Entry]?
    @State private var error: String?
    @State private var query = ""

    var body: some View {
        Group {
            if let entries {
                let shown = filtered(entries)
                List(shown) { e in
                    NavigationLink { TemplatePreview(model: model, entry: e) } label: { row(e) }
                }
                .searchable(text: $query)
                .overlay {
                    if shown.isEmpty {
                        if query.isEmpty {
                            ContentUnavailableView("No Templates Yet", systemImage: "square.grid.2x2", description: Text("Check back later for new templates."))
                        } else {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                }
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't Load Templates", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView("Loading Templates…")
            }
        }
        .navigationTitle("Template Gallery")
        .task { if entries == nil { await load() } }
    }

    private func load() async {
        error = nil
        do { entries = try await TemplateCatalog.fetch().entries() }
        catch {
            let offline: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost]
            if let e = error as? URLError, offline.contains(e.code) { self.error = e.localizedDescription }
            else { self.error = String(localized: "The template gallery isn't available right now.") }
        }
    }

    private func filtered(_ list: [TemplateCatalog.Entry]) -> [TemplateCatalog.Entry] {
        guard !query.isEmpty else { return list }
        return list.filter { e in ([e.name, e.description] + e.tags).contains { $0.localizedStandardContains(query) } }
    }

    private func row(_ e: TemplateCatalog.Entry) -> some View {
        Label {
            VStack(alignment: .leading) {
                Text(e.name)
                Text(e.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        } icon: { Image(systemName: e.symbol) }
    }
}

/// The template's Markdown, and Install.
private struct TemplatePreview: View {
    let model: VaultModel
    let entry: TemplateCatalog.Entry
    @State private var installed = false
    @State private var failed = false

    var body: some View {
        ScrollView {
            Text(entry.body)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(entry.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(installed ? "Installed" : "Install", systemImage: installed ? "checkmark" : "square.and.arrow.down") {
                    model.addTemplates([entry.builtIn])
                    installed = model.vault.exists(model.templatePath(entry.builtIn))
                    failed = !installed
                }
                .disabled(installed)
            }
        }
        .alert("Couldn't Install Template", isPresented: $failed) { Button("OK") { model.lastError = nil } } message: { Text(model.lastError ?? "") }
        .onAppear { installed = model.vault.exists(model.templatePath(entry.builtIn)) }
    }
}
