import SwiftUI
import NetheriteCore

/// Presentation mode: the note is split into slides at `---` lines (outside frontmatter and code).
struct SlidesView: View {
    let path: String
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    static func slides(_ text: String) -> [String] {
        var body = text
        if let fm = Frontmatter.locate(in: text) { body = (text as NSString).substring(from: NSMaxRange(fm.range)) }
        var out: [String] = [], current: [String] = [], inFence = false
        for line in body.components(separatedBy: "\n") {
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle() }
            if !inFence, line.trimmingCharacters(in: .whitespaces) == "---" {
                out.append(current.joined(separator: "\n")); current = []
            } else { current.append(line) }
        }
        out.append(current.joined(separator: "\n"))
        return out.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        let slides = Self.slides(window.model.text(of: path))
        let i = min(index, max(0, slides.count - 1))
        let html = slides.isEmpty ? "" : HTMLRenderer.render(slides[i], context: .app(window.model.index, source: path))
        let style = "<style>body{font-size:1.6em;display:flex;flex-direction:column;justify-content:center;min-height:calc(100vh - 150px);max-width:1000px}</style>"
        ZStack(alignment: .bottom) {
            HTMLWebView(html: HTMLRenderer.page(title: nil, body: html, assets: "nth://web/", theme: window.model.theme, extraHead: style),
                        vault: window.model.vault, onAction: { window.handle($0, from: path) })
                .ignoresSafeArea()
            HStack(spacing: 16) {
                Button("Previous slide", systemImage: "chevron.left") { index = max(0, i - 1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(i == 0)
                Text("\(i + 1) / \(max(1, slides.count))").monospacedDigit().foregroundStyle(.secondary)
                Button("Next slide", systemImage: "chevron.right") { index = min(slides.count - 1, i + 1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(i >= slides.count - 1)
                Divider().frame(height: 20)
                Button("End presentation", systemImage: "xmark") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.large)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 24)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
            if v.translation.width < 0 { index = min(slides.count - 1, i + 1) } else { index = max(0, i - 1) }
        })
    }
}
