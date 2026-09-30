import SwiftUI
import NetheriteCore

/// Reading mode: the note rendered to HTML with math, diagrams, embeds and interactive tasks.
struct ReaderView: View {
    let path: String
    let text: String
    let pane: Pane
    @Environment(WindowState.self) private var window

    var body: some View {
        let model = window.model
        let body = HTMLRenderer.render(text, context: .app(model.index, source: path))
        let sub = pane.pendingLine.flatMap { line in model.index.notes[path]?.parsed.headings.first { $0.line == line }?.text }
        HTMLWebView(
            html: HTMLRenderer.page(title: path.noteName, body: body, assets: "nth://web/", theme: model.theme,
                                    fullWidth: !model.settings.readableLineLength, initialSubpath: sub),
            vault: model.vault,
            onAction: { window.handle($0, from: path) })
        .accessibilityLabel(Text("Reading view of \(path.noteName)"))
    }
}

extension WindowState {
    func handle(_ action: WebAction, from source: String) {
        switch action {
        case .openPath(let p, let sub, let newPane): open(path: p, line: line(for: sub, in: p), newPane: newPane)
        case .createNote(let target): follow(NoteLink(target: target, isEmbed: false, isWiki: true, range: NSRange(), line: 0), from: source)
        case .tag(let tag): searchQuery = "tag:\(tag)"; sidebarTab = .search; columnVisibility = .all
        case .external(let url):
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
        case .task(let line): toggleTask(in: source, line: line)
        }
    }

    func toggleTask(in path: String, line: Int) {
        var lines = model.text(of: path).components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return }
        let l = lines[line]
        if let r = l.range(of: #"\[( |x|X)\]"#, options: .regularExpression) {
            lines[line] = l.replacingCharacters(in: r, with: l[r] == "[ ]" ? "[x]" : "[ ]")
            model.edit(path, text: lines.joined(separator: "\n"))
        }
    }
}

extension NoteLink {
    init(target: String, isEmbed: Bool, isWiki: Bool, range: NSRange, line: Int) {
        self = NoteParser.splitWiki(target, isEmbed: isEmbed)
        self.range = range
        self.line = line
    }
}
