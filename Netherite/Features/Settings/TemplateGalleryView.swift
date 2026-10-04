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
                .overlay { if shown.isEmpty && !query.isEmpty { ContentUnavailableView.search(text: query) } }
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't Load Templates", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView()
            }
        }
        .searchable(text: $query)
        .navigationTitle("Template Gallery")
        .task { await load() }
    }

    private func load() async {
        error = nil
        do { entries = try await TemplateCatalog.fetch().entries() }
        catch { self.error = error.localizedDescription }
    }

    private func filtered(_ list: [TemplateCatalog.Entry]) -> [TemplateCatalog.Entry] {
        guard !query.isEmpty else { return list }
        return list.filter { e in ([e.name, e.description] + e.tags).contains { $0.localizedStandardContains(query) } }
    }

    private func row(_ e: TemplateCatalog.Entry) -> some View {
        Label { Text(e.name); Text(e.description) } icon: { Image(systemName: e.symbol) }
    }
}

/// The template's Markdown, and Install.
private struct TemplatePreview: View {
    let model: VaultModel
    let entry: TemplateCatalog.Entry
    @State private var installed = false

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
            ToolbarItem(placement: .confirmationAction) {
                Button(installed ? "Installed" : "Install", systemImage: installed ? "checkmark" : "square.and.arrow.down") {
                    installed = model.addTemplates([entry.builtIn]) == 1
                }
                .disabled(installed)
            }
        }
        .onAppear { installed = model.vault.exists(model.templatePath(entry.builtIn)) }
    }
}
