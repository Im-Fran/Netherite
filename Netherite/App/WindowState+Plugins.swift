import SwiftUI
import TipKit
import NetheriteCore

extension WindowState {
    // MARK: Daily notes

    func openDailyNote(_ date: Date = .now) {
        let s = model.settings
        let path = Templates.dailyNotePath(for: date, settings: s)
        // The index may still be loading at startup: check the disk too so today's note is never overwritten.
        if !model.index.files.contains(path) && !model.vault.exists(path) {
            let content = s.dailyNotes.template.isEmpty ? "" : Templates.render(templateText(s.dailyNotes.template), title: path.noteName, date: date)
            do { try model.vault.write(content, to: path); model.index.didCreate(path) } catch { model.lastError = error.localizedDescription; return }
        }
        open(path: path)
        NetheriteTips.donate(NetheriteTips.dailyOpened)
    }

    /// Opens the previous/next existing daily note relative to the current one (or today).
    func openAdjacentDailyNote(_ delta: Int) {
        let s = model.settings
        let folder = s.dailyNotes.folder
        let f = DateFormatter()
        f.dateFormat = Templates.unicodePattern(s.dailyNotes.format)
        let dated: [(Date, String)] = model.index.markdownFiles
            .filter { $0.parentFolder == folder }
            .compactMap { p in f.date(from: p.noteName).map { ($0, p) } }
            .sorted { $0.0 < $1.0 }
        let current = currentNote.flatMap { f.date(from: $0.noteName) } ?? Calendar.current.startOfDay(for: .now)
        let target = delta < 0 ? dated.last { $0.0 < current } : dated.first { $0.0 > current }
        if let target { open(path: target.1) }
    }

    func newUniqueNote() {
        let s = model.settings
        let name = Templates.uniqueNoteName(for: .now, settings: s)
        let content = s.uniqueNote.template.isEmpty ? "" : Templates.render(templateText(s.uniqueNote.template), title: name)
        if let p = model.newNote(in: s.uniqueNote.folder, named: name, content: content) { open(path: p) }
    }

    /// Reads a template by path or name (resolved like a link).
    func templateText(_ ref: String) -> String {
        let path = model.index.resolver.resolve(ref, from: model.settings.templatesFolder + "/x.md") ?? ref
        return model.text(of: path)
    }

    /// Vault templates, then the built-in gallery.
    var templateChoices: [TemplateChoice] {
        Templates.list(in: model.index, folder: model.settings.templatesFolder).map {
            TemplateChoice(id: $0, name: $0.noteName, symbol: "doc.on.doc", builtIn: false, body: model.text(of: $0))
        } + Templates.builtIns.map { TemplateChoice(id: "builtin:\($0.id)", name: $0.name, symbol: $0.symbol, builtIn: true, body: $0.body) }
    }

    func insertTemplate(_ body: String) {
        guard let note = currentNote else { return }
        let rendered = Templates.render(body, title: note.noteName)
        if let e = editor, !pane.reading {
            e.insert(rendered)
        } else {
            model.edit(note, text: model.text(of: note) + "\n" + rendered)
        }
    }

    /// Creates a note named `title` in `folder` from a template body and opens it.
    func newNote(fromTemplate body: String, title: String, in folder: String) {
        let clean = Templates.fileName(title)
        let name = clean.isEmpty ? String(localized: "Untitled") : clean
        if let p = model.newNote(in: folder, named: name, content: Templates.render(body, title: name)) { open(path: p) }
    }

    // MARK: Meeting notes

    func newMeetingNote(title: String, date: Date, attendees: [String]) {
        let s = model.settings
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let content = Templates.meetingNote(title: trimmed.isEmpty ? String(localized: "Meeting") : trimmed, date: date, attendees: attendees,
                                            template: s.meetingNotes.template.isEmpty ? "" : templateText(s.meetingNotes.template))
        let name = Templates.meetingNoteName(title: trimmed, date: date, settings: s)
        if let p = model.newNote(in: s.meetingNotes.folder, named: name, content: content) { open(path: p) }
    }

    // MARK: Graph

    /// In a new pane beside (or below, on iPhone) the note, or replacing the current pane.
    func openLocalGraph(for path: String, newPane: Bool = true) { open(.localGraph(path), newPane: newPane && panes.count < 2) }

    // MARK: Note composer

    /// Moves the selected text into a new note and leaves a link in its place.
    func extractSelection(_ e: EditorController) {
        guard let source = currentNote else { return }
        let text = e.selectedText
        guard !text.isEmpty else { return }
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        let name = firstLine.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\\/:*?"<>|#^\[\]]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces).prefix(80)
        guard let p = model.newNote(in: source.parentFolder, named: name.isEmpty ? String(localized: "Untitled") : String(name), content: text) else { return }
        e.insert(model.linkText(to: p))
    }

    /// Appends `source` to `target`, repoints links to `source`, then deletes it.
    func merge(_ source: String, into target: String) {
        guard source != target else { return }
        model.save(source)
        let index = model.index
        let body = model.text(of: source)
        model.edit(target, text: model.text(of: target) + "\n\n" + body)
        model.save(target)
        for from in index.backlinks(for: source).map(\.source) where from != source {
            guard let rec = index.notes[from] else { continue }
            let text = VaultIndex.rewriteLinks(in: rec.text, parsed: rec.parsed) { link in
                index.resolver.resolve(link.target, from: from) == source ? target : nil
            } linkText: { index.resolver.linkText(for: $0) }
            if text != rec.text { model.overwrite(from, with: text) }
        }
        trash(source)
        open(path: target)
    }

    // MARK: Web viewer

    func promptWebURL() { sheet = .openURL }

    func openURL(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if !s.contains("://") { s = "https://" + s }
        if let url = URL(string: s) { open(.web(url)) }
    }
}

/// Picks another note to merge the current one into.
struct MergeSheet: View {
    let source: String
    @Environment(WindowState.self) private var window

    var body: some View {
        PaletteView(prompt: "Merge “\(source.noteName)” into…", items: { q in
            window.model.index.markdownFiles.filter { $0 != source }
                .compactMap { p in Search.fuzzyScore(q, p.noteName).map { (p, $0) } }
                .sorted { $0.1 > $1.1 }.prefix(80)
                .map { p, _ in PaletteItem(id: p, title: p.noteName, subtitle: p.parentFolder, symbol: "doc.text") { _ in window.merge(source, into: p) } }
        }, footer: "The current note is appended to the chosen note and moved to the Trash.")
    }
}

struct TemplateChoice: Identifiable {
    var id: String
    var name: String
    var symbol: String
    var builtIn: Bool
    var body: String
}

struct TemplatePicker: View {
    @Environment(WindowState.self) private var window

    var body: some View {
        PaletteView(prompt: "Insert template…", items: { q in
            window.templateChoices.compactMap { t in Search.fuzzyScore(q, t.name).map { (t, $0) } }
                .sorted { ($0.0.builtIn ? 1 : 0, -$0.1) < ($1.0.builtIn ? 1 : 0, -$1.1) }   // keeps each section together
                .map { t, _ in
                    PaletteItem(id: t.id, title: t.name, symbol: t.symbol,
                                section: t.builtIn ? String(localized: "Built-in") : String(localized: "Vault templates")) { _ in window.insertTemplate(t.body) }
                }
        }, footer: "Templates live in the folder set in Settings › Templates.")
    }
}

/// Title + template, then creates and opens the note.
struct NewNoteFromTemplateSheet: View {
    let folder: String
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var choice = ""

    var body: some View {
        let choices = window.templateChoices
        NavigationStack {
            Form {
                TextField("Title", text: $title).onSubmit { create(choices) }
                Picker("Template", selection: $choice) {
                    let own = choices.filter { !$0.builtIn }
                    if !own.isEmpty {
                        Section("Vault templates") { ForEach(own) { Label($0.name, systemImage: $0.symbol).tag($0.id) } }
                    }
                    Section("Built-in") { ForEach(choices.filter(\.builtIn)) { Label($0.name, systemImage: $0.symbol).tag($0.id) } }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #endif
            }
            .formStyle(.grouped)
            .navigationTitle("New Note from Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") { create(choices) }.disabled(choice.isEmpty) }
            }
        }
        .macOnly { $0.frame(minWidth: 420, minHeight: 200) }
        .onAppear { if choice.isEmpty { choice = choices.first?.id ?? "" } }
    }

    private func create(_ choices: [TemplateChoice]) {
        guard let t = choices.first(where: { $0.id == choice }) else { return }
        window.newNote(fromTemplate: t.body, title: title, in: folder)
        dismiss()
    }
}

struct OpenURLSheet: View {
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("URL", text: $url)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit(go)
            }
            .formStyle(.grouped)
            .navigationTitle("Open URL")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Open", action: go).disabled(url.isEmpty) }
            }
        }
        .frame(minWidth: 400, minHeight: 150)
    }

    private func go() { window.openURL(url); dismiss() }
}
