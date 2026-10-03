import SwiftUI
import UniformTypeIdentifiers
import NetheriteCore

/// What was shared, normalized.
struct SharedInput {
    var url: URL?
    var text: String?
    var images: [(data: Data, ext: String)] = []
}

@MainActor @Observable
final class ClipModel {
    enum Destination: String, CaseIterable, Identifiable { case newNote, dailyNote; var id: String { rawValue } }
    /// Folder for new clippings; the same localized name is shown in the picker.
    static let folder = String(localized: "Clippings")

    var title = ""
    var body = ""
    var tags = ""
    var destination: Destination = .newNote
    var loading = true
    /// The shared items are read; only the page download may still be running.
    var itemsLoaded = false
    @ObservationIgnored private var fetch: Task<Void, Never>?
    var error: String?
    var fetchFailed = false
    var fallbackBody: String {
        [input.text, input.url.map { "[\(title)](\($0.absoluteString))" }].compactMap { $0 }.joined(separator: "\n\n")
    }
    var input = SharedInput()
    let vault = SharedVault.current()?.resolve()

    func load(_ items: [NSExtensionItem]) async {
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !url.isFileURL {
                input.url = url
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                      let data = try? await loadData(provider, UTType.image) {
                let ext = provider.registeredContentTypes.first { $0.conforms(to: .image) }?.preferredFilenameExtension ?? "png"
                input.images.append((data, ext))
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                input.text = (input.text.map { $0 + "\n\n" } ?? "") + text
            }
        }
        itemsLoaded = true
        if let url = input.url {
            title = url.host() ?? ""
            let task = Task { await fetchPage(url) }
            fetch = task
            await task.value
        } else {
            body = input.text ?? ""
            title = String((input.text ?? String(localized: "Clipping")).split(separator: "\n").first ?? "").prefix(60).description
        }
        if title.isEmpty { title = String(localized: "Clipping") }
        loading = false
    }

    private func fetchPage(_ url: URL) async {
        if let (data, _) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10)), !Task.isCancelled,
           let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
            let clip = HTMLToMarkdown.convert(html, baseURL: url)
            if !clip.title.isEmpty { title = clip.title }
            body = [clip.description.map { "> \($0)" }, input.text, clip.markdown].compactMap { $0 }.joined(separator: "\n\n")
        } else if !Task.isCancelled {
            fetchFailed = true
            body = fallbackBody
        }
    }

    /// Stops a page download still in progress so the clip is saved with just the link.
    func skipFetch() {
        guard loading, itemsLoaded else { return }
        fetch?.cancel()
        if title.isEmpty { title = String(localized: "Clipping") }
        fetchFailed = true
        body = fallbackBody
        loading = false
    }

    private func loadData(_ p: NSItemProvider, _ type: UTType) async throws -> Data? {
        try await withCheckedThrowingContinuation { c in
            _ = p.loadDataRepresentation(for: type) { data, error in
                if let error { c.resume(throwing: error) } else { c.resume(returning: data) }
            }
        }
    }

    /// Writes the clip; returns false (with `error` set) on failure.
    func save() -> Bool {
        guard let vault else { error = String(localized: "Open a vault in Netherite first."); return false }
        do {
            var parts: [String] = []
            for img in input.images {
                let path = vault.availablePath(folder: vault.settings.attachmentFolder, base: String(localized: "Clipped image"), ext: img.ext)
                try vault.write(img.data, to: path)
                parts.append("![[\((path as NSString).lastPathComponent)]]")
            }
            // The daily-note bullet already carries the link, so skip the fetch-failure fallback body there.
            if !body.isEmpty && !(fetchFailed && destination == .dailyNote && body == fallbackBody) { parts.append(body) }
            let tagList = tags.split(whereSeparator: { $0 == "," || $0 == " " }).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }.filter { !$0.isEmpty }
            switch destination {
            case .newNote:
                var props: [Property] = []
                if let url = input.url { props.append(Property(key: "source", value: .text(url.absoluteString))) }
                props.append(Property(key: "clipped", value: .text(Frontmatter.dateString(.now))))
                if !tagList.isEmpty { props.append(Property(key: "tags", value: .list(tagList))) }
                let content = Frontmatter.replacing(in: parts.joined(separator: "\n\n") + "\n", with: props)
                let name = title.replacingOccurrences(of: #"[\\/:*?"<>|#^\[\]]"#, with: "-", options: .regularExpression)
                try vault.createNote(in: Self.folder, named: String(name.prefix(100)), content: content)
            case .dailyNote:
                let link = input.url.map { "[\(title)](\($0.absoluteString))" } ?? title
                let tagText = tagList.map { " #\($0)" }.joined()
                try vault.appendToDailyNote("- " + link + tagText + (parts.isEmpty ? "" : "\n\n" + parts.joined(separator: "\n\n")))
            }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

struct ClipView: View {
    @Bindable var model: ClipModel
    let done: (Bool) -> Void

    var body: some View {
        NavigationStack {
            Form {
                if model.vault == nil {
                    Section {
                        Label("Open a vault in Netherite first, then share again.", systemImage: "exclamationmark.triangle")
                    }
                }
                Section {
                    TextField("Title", text: $model.title)
                    Picker("Save to", selection: $model.destination) {
                        Text("New note in \(ClipModel.folder)").tag(ClipModel.Destination.newNote)
                        Text("Today's daily note").tag(ClipModel.Destination.dailyNote)
                    }
                    TextField("Tags", text: $model.tags, prompt: Text("reading, ideas"))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                Section("Content") {
                    if model.loading {
                        HStack { ProgressView(); Text("Clipping page…").foregroundStyle(.secondary) }
                    } else {
                        if model.fetchFailed {
                            Label("Couldn't download the page, so only the link will be saved.", systemImage: "wifi.exclamationmark")
                                .foregroundStyle(.secondary)
                        }
                        if !model.input.images.isEmpty {
                            Label("^[\(model.input.images.count) image](inflect: true) will be saved to attachments", systemImage: "photo")
                                .foregroundStyle(.secondary)
                        }
                        TextEditor(text: $model.body)
                            .font(.body.monospaced())
                            .frame(minHeight: 200)
                            .accessibilityLabel("Clipped Markdown")
                    }
                }
            }
            .formStyle(.grouped)
            .alert("Couldn't Save the Clip", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") {}
            } message: {
                Text(model.error ?? "")
            }
            .navigationTitle("Clip to Netherite")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { done(false) } }
                ToolbarItem(placement: .confirmationAction) {
                    // Saving while the page downloads keeps just the link.
                    Button("Save") { model.skipFetch(); if model.save() { done(true) } }
                        .disabled(!model.itemsLoaded || model.vault == nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 460)
        #endif
    }
}

#if os(macOS)
import AppKit

final class ShareViewController: NSViewController {
    private let model = ClipModel()

    override func loadView() {
        let host = NSHostingView(rootView: ClipView(model: model) { [weak self] saved in self?.finish(saved) })
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 520)
        view = host
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { await model.load(items) }
    }

    private func finish(_ saved: Bool) {
        if saved { extensionContext?.completeRequest(returningItems: nil) }
        else { extensionContext?.cancelRequest(withError: CocoaError(.userCancelled)) }
    }
}
#else
import UIKit

final class ShareViewController: UIViewController {
    private let model = ClipModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ClipView(model: model) { [weak self] saved in self?.finish(saved) })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { await model.load(items) }
    }

    private func finish(_ saved: Bool) {
        if saved { extensionContext?.completeRequest(returningItems: nil) }
        else { extensionContext?.cancelRequest(withError: CocoaError(.userCancelled)) }
    }
}
#endif
