import SwiftUI
import NetheriteCore

/// Reading mode: the note rendered to HTML with math, diagrams, embeds and interactive tasks.
struct ReaderView: View {
    let path: String
    let text: String
    let pane: Pane
    @Environment(WindowState.self) private var window
    @State private var hover: (path: String, subpath: String?, rect: CGRect)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let model = window.model
        let body = HTMLRenderer.render(text, context: .app(model.index, source: path))
        let sub = pane.pendingLine.flatMap { line in model.index.notes[path]?.parsed.headings.first { $0.line == line }?.text }
        HTMLWebView(
            html: HTMLRenderer.page(title: path.noteName, body: body, assets: "nth://web/", theme: model.theme,
                                    fullWidth: !model.settings.readableLineLength, initialSubpath: sub,
                                    baseSize: ReaderView.baseSize(dynamicTypeSize), transparentBackground: true,
                                    increaseContrast: A11y.shared.highContrast, reduceMotion: A11y.shared.reduceMotion),
            vault: model.vault,
            onAction: { action in
                if case .hover(let p, let sub, let rect) = action { hover = (p, sub, rect) } else { window.handle(action, from: path) }
            })
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Reading view of \(path.noteName)"))
        .overlay(alignment: .topLeading) {
            if let h = hover {
                Color.clear
                    .frame(width: max(1, h.rect.width), height: max(1, h.rect.height))
                    .offset(x: h.rect.minX, y: h.rect.minY)
                    .popover(isPresented: Binding(get: { hover != nil }, set: { if !$0 { hover = nil } })) {
                        PagePreview(link: NoteParser.splitWiki(h.path + (h.subpath.map { "#\($0)" } ?? ""), isEmbed: false), source: path)
                    }
            }
        }
    }
}

extension WindowState {
    func handle(_ action: WebAction, from source: String) {
        switch action {
        case .openPath(let p, let sub, let newPane): open(path: p, line: line(for: sub, in: p), newPane: newPane)
        case .createNote(let target): follow(NoteLink(target: target, isEmbed: false, isWiki: true, range: NSRange(), line: 0), from: source)
        case .tag(let tag): searchQuery = "tag:\(tag)"; sidebarTab = .search; columnVisibility = .all; preferredCompactColumn = .sidebar
        case .external(let url):
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url)
            #endif
        case .task(let line): toggleTask(in: source, line: line)
        case .hover: break
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

/// Hover preview of a linked note (Page preview core plugin).
struct PagePreview: View {
    let link: NoteLink
    let source: String
    @Environment(WindowState.self) private var window
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let index = window.model.index
        Group {
            if let target = index.resolver.resolve(link.target, from: source) {
                let text = target.isMarkdown ? HTMLRenderer.section(of: window.model.text(of: target), subpath: link.subpath) : ""
                let body = target.isMarkdown
                    ? HTMLRenderer.render(text, context: .app(index, source: target))
                    : HTMLRenderer.embed(NoteLink(target: target, isEmbed: true, isWiki: true, range: NSRange(), line: 0), .app(index, source: target))
                HTMLWebView(html: HTMLRenderer.page(title: target.isMarkdown ? target.noteName : nil, body: body, assets: "nth://web/", theme: window.model.theme,
                                                   baseSize: ReaderView.baseSize(dynamicTypeSize), transparentBackground: true,
                                                   increaseContrast: A11y.shared.highContrast, reduceMotion: A11y.shared.reduceMotion),
                            vault: window.model.vault, onAction: { window.handle($0, from: target) })
            } else {
                ContentUnavailableView("“\(link.target)” doesn't exist yet", systemImage: "doc.badge.plus",
                                       description: Text("Click the link to create it."))
            }
        }
        .frame(width: 460, height: 340)
    }
}

extension ReaderView {
    /// Body size the reader scales from: 17 pt on iOS, 16 px on macOS, scaled by Text Size.
    static func baseSize(_ size: DynamicTypeSize) -> Double {
        #if os(iOS)
        17 * size.bodyScale
        #else
        16 * size.bodyScale
        #endif
    }
}
