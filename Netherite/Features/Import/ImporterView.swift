import SwiftUI
import UniformTypeIdentifiers
import NetheriteCore

extension ImportSource {
    var title: LocalizedStringKey {
        switch self {
        case .evernote: "Evernote (.enex)"
        case .notion: "Notion (Markdown & CSV export)"
        case .html: "HTML / Apple Notes export"
        case .markdown: "Markdown folder (Bear, Typora…)"
        }
    }

    var hint: LocalizedStringKey {
        switch self {
        case .evernote: "Choose an .enex file exported from Evernote, or a folder of them."
        case .notion: "Export from Notion as “Markdown & CSV”, then choose the .zip or its unzipped folder."
        case .html: "Choose a folder or .zip of .html files. Apple Notes can export to HTML via Exporter apps or Shortcuts."
        case .markdown: "Choose a folder or .zip of Markdown files. Folder structure is kept."
        }
    }

    var types: [UTType] {
        switch self {
        case .evernote: [UTType(filenameExtension: "enex") ?? .xml, .folder]
        case .notion, .markdown: [.zip, .folder]
        case .html: [.zip, .folder, .html]
        }
    }

    var defaultFolderName: String {
        switch self {
        case .evernote: "Evernote"
        case .notion: "Notion"
        case .html: "HTML"
        case .markdown: "Markdown"
        }
    }
}

/// Importer + Format converter sheet.
struct ImporterView: View {
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    @State private var source: ImportSource = .evernote
    @State private var sourceURL: URL?
    @State private var destination = ""
    @State private var options = FormatConverter.Options()
    @State private var picking = false
    @State private var running = false
    @State private var report: ImportReport?
    @State private var error: String?
    @State private var confirmConvert: ConvertScope?
    @State private var convertMessage: String?
    @State private var convertProgress: Double?

    enum ConvertScope: Identifiable { case vault, note(String); var id: String { if case .note(let p) = self { p } else { "vault" } } }

    var body: some View {
        NavigationStack {
            Form {
                if let report { resultSection(report) }

                Section {
                    Picker("Import from", selection: $source) {
                        ForEach(ImportSource.allCases) { Text($0.title).tag($0) }
                    }
                    Text(source.hint).font(.callout).foregroundStyle(.secondary)
                    LabeledContent("Source") {
                        Button(sourceURL?.lastPathComponent ?? String(localized: "Choose…")) { picking = true }
                            .accessibilityHint("Pick the export file or folder")
                    }
                    TextField("Destination folder", text: $destination, prompt: Text(defaultDestination))
                } header: {
                    Text("Import")
                } footer: {
                    Text("Notes are copied into your vault. Existing files are never overwritten.")
                }

                Section("Format converter") {
                    Toggle("Convert Markdown links to [[wikilinks]]", isOn: $options.markdownLinksToWikilinks)
                    Toggle("Bear #multi word tags# and ::highlights::", isOn: Binding(
                        get: { options.bearTags && options.bearHighlights },
                        set: { options.bearTags = $0; options.bearHighlights = $0 }))
                    Toggle("Roam #[[tags]], ^^highlights^^ and {{[[TODO]]}}", isOn: $options.roam)
                    Toggle("HTML <mark> to ==highlights==", isOn: $options.htmlMarks)
                    Toggle("Legacy alias/tag/cssclass properties", isOn: $options.legacyProperties)
                    Toggle("Zettelkasten [[UID]] to full links", isOn: $options.zettelkastenLinks)
                    Menu("Convert Existing Notes…") {
                        if let note = window.currentNote {
                            Button("Current Note (\(note.noteName))") { confirmConvert = .note(note) }
                        }
                        Button("All Notes in Vault") { confirmConvert = .vault }
                    }
                    .disabled(running)
                    if let convertProgress {
                        // Indeterminate while converting off the main thread, determinate while writing back.
                        if convertProgress == 0 {
                            ProgressView { Text("Converting notes…") }
                        } else {
                            ProgressView(value: convertProgress) { Text("Saving converted notes…") }
                        }
                    }
                    if let convertMessage {
                        Label(convertMessage, systemImage: "checkmark.circle").foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .interactiveDismissDisabled(running)
            .navigationTitle("Import Notes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(report == nil ? "Cancel" : "Done") { dismiss() }.disabled(running) }
                ToolbarItem(placement: .confirmationAction) {
                    if running { ProgressView().controlSize(.small).accessibilityLabel("Importing") }
                    else { Button("Import", action: runImport).disabled(sourceURL == nil) }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 540)
        #endif
        .fileImporter(isPresented: $picking, allowedContentTypes: source.types) { result in
            switch result {
            case .success(let url): sourceURL = url; report = nil
            case .failure(let e): error = e.localizedDescription
            }
        }
        .onChange(of: source) { sourceURL = nil; report = nil }
        .alert("Import Failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirmConvert != nil }, set: { if !$0 { confirmConvert = nil } }),
                            titleVisibility: .visible, presenting: confirmConvert) { scope in
            Button("Convert", role: .destructive) { convert(scope) }
        } message: { _ in
            Text("This rewrites notes in place. Snapshots in File recovery let you restore earlier versions.")
        }
    }

    private var defaultDestination: String {
        String(localized: "Imported", comment: "Default import destination folder") + "/" + (sourceURL.map { $0.deletingPathExtension().lastPathComponent } ?? source.defaultFolderName)
    }

    private var confirmTitle: String {
        switch confirmConvert {
        case .note(let p): String(localized: "Convert “\(p.noteName)”?")
        default: String(localized: "Convert all \(window.model.index.markdownFiles.count) notes?")
        }
    }

    @ViewBuilder private func resultSection(_ r: ImportReport) -> some View {
        Section("Import complete") {
            Label("\(r.notes.count) notes", systemImage: "doc.text")
            Label("\(r.attachments.count) attachments", systemImage: "paperclip")
            if !r.warnings.isEmpty {
                DisclosureGroup {
                    ForEach(r.warnings, id: \.self) { Text($0).font(.callout) }
                } label: {
                    Label {
                        Text("\(r.warnings.count) warnings")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }
            Button("Open Imported Folder", systemImage: "folder") {
                window.sidebarTab = .files
                window.columnVisibility = .all
                if let first = r.notes.first { window.open(path: first) }
                window.explorerSelection = r.folder
                dismiss()
            }
            .disabled(r.notes.isEmpty)
        }
    }

    private func runImport() {
        guard let url = sourceURL else { return }
        let dest = destination.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).isEmpty ? defaultDestination : destination.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let importer = Importer(vault: window.model.vault, destination: dest, converter: options)
        let kind = source
        running = true
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let r = try await Task.detached { try importer.run(kind, from: url) }.value
                report = r
                await window.model.refresh()
                AccessibilityNotification.Announcement(String(localized: "Imported \(r.notes.count) notes")).post()
            } catch {
                self.error = error.localizedDescription
            }
            running = false
        }
    }

    /// Converts off the main thread, then writes the changed notes back with progress.
    private func convert(_ scope: ConvertScope) {
        let model = window.model
        let converter = FormatConverter(options: options, files: model.index.files)
        let paths: [String] = switch scope {
        case .note(let p): [p]
        case .vault: model.index.markdownFiles
        }
        let texts = paths.map { ($0, model.text(of: $0)) }
        running = true
        convertMessage = nil
        convertProgress = 0
        Task {
            defer { running = false; convertProgress = nil }
            let changes = await Task.detached {
                texts.compactMap { p, text -> (String, String)? in
                    let out = converter.convert(text, path: p)
                    return out == text ? nil : (p, out)
                }
            }.value
            for (i, (p, out)) in changes.enumerated() {
                model.overwrite(p, with: out)
                convertProgress = Double(i + 1) / Double(max(1, changes.count))
                if i % 20 == 0 { await Task.yield() }
            }
            convertMessage = String(localized: "Converted \(changes.count) of \(paths.count) notes.")
            AccessibilityNotification.Announcement(convertMessage ?? "").post()
        }
    }
}
