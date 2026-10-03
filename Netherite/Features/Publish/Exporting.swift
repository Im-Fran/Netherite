import SwiftUI
import NetheriteCore

/// A note, file, folder or (path "") whole vault to export.
struct ExportRequest: Hashable, Identifiable {
    var vault: Vault
    var path: String
    var id: String { "\(vault.root.path):\(path)" }
}

/// Prepares the export off the main thread (folders become a .zip), then lets the person pick where to save it.
private struct ExportingModifier: ViewModifier {
    @Binding var request: ExportRequest?
    @State private var file: URL?
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .overlay {
                if request != nil && file == nil {
                    ProgressView("Preparing Export…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .task(id: request) {
                guard let request else { return }
                let dir = FileManager.default.temporaryDirectory.appending(path: "Export-\(UUID().uuidString)", directoryHint: .isDirectory)
                do {
                    file = try await Task.detached { try request.vault.exportArchive(request.path, to: dir) }.value
                } catch {
                    self.error = error.localizedDescription
                    self.request = nil
                }
            }
            .fileMover(isPresented: Binding(get: { file != nil }, set: { if !$0 { finish() } }), file: file) { result in
                if case .failure(let e) = result { error = e.localizedDescription }
                finish()
            } onCancellation: {
                finish()
            }
            .alert("Couldn't Export", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
    }

    private func finish() {
        if let file { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        file = nil
        request = nil
    }
}

extension View {
    func exporting(_ request: Binding<ExportRequest?>) -> some View { modifier(ExportingModifier(request: request)) }
}
