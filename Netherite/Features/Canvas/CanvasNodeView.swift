import SwiftUI
import NetheriteCore

/// One card (or group) on the canvas, with selection chrome, resize and connection handles.
struct CanvasNodeView: View {
    let model: CanvasModel
    let node: CanvasNode
    let additive: Bool
    @Environment(WindowState.self) private var window
    @State private var hovered = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var selected: Bool { model.selection.contains(node.id) }
    private var editing: Bool { model.editing == node.id }
    private var tint: Color? { CanvasColor.color(node.color) }
    private var isGroup: Bool { node.type == "group" }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(background)
            .overlay(border)
            .overlay(alignment: .topLeading) { if isGroup { groupLabel } }
            .overlay { if selected || hovered { handles } }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { activate() }
            .onTapGesture { model.select(node.id, additive: additive) }
            .gesture(moveGesture, including: editing ? .subviews : .all)
            .contextMenu { menu }
            #if os(macOS)
            .onHover { hovered = $0 }
            #endif
            .modifier(CanvasNodeAccessibility(model: model, node: node, title: accessibilityTitle, selected: selected, activate: activate))
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch node.type {
        case "text": textCard
        case "file": FileCard(path: node.file ?? "", subpath: node.subpath)
        case "link": linkCard
        default: Color.clear
        }
    }

    @ViewBuilder private var textCard: some View {
        if editing {
            TextEditor(text: Binding(get: { node.text ?? "" }, set: { model.setText(node.id, $0) }))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .onDisappear { if model.editing == node.id { model.endEditing() } }
        } else {
            ScrollView {
                Text(Self.markdown(node.text ?? ""))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .scrollDisabled(true)
            .overlay {
                if (node.text ?? "").isEmpty { Text(Self.editHint).foregroundStyle(.secondary) }
            }
        }
    }

    private var linkCard: some View {
        let url = URL(string: node.url ?? "")
        return VStack(alignment: .leading, spacing: 6) {
            Label(url?.host() ?? node.url ?? "", systemImage: "globe").font(.headline).lineLimit(1)
            Text(node.url ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
        .padding(12)
    }

    private var groupLabel: some View {
        Group {
            if editing {
                TextField("Group", text: Binding(get: { node.label ?? "" }, set: { model.setText(node.id, $0) }))
                    .textFieldStyle(.plain)
                    .onSubmit { model.endEditing() }
                    .frame(width: 200)
            } else {
                Text(node.label ?? "").lineLimit(1)
            }
        }
        .font(.title3.weight(.semibold))
        .foregroundStyle(.primary)   // tint is shown by the group fill/border; tinted text fails contrast
        .alignmentGuide(.top) { d in d[.bottom] + 4 }
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: isGroup ? 16 : 10, style: .continuous)
        if isGroup {
            shape.fill((tint ?? .secondary).opacity(0.08))
        } else {
            shape.fill(.background).overlay(shape.fill((tint ?? .clear).opacity(0.1)))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: isGroup ? 16 : 10, style: .continuous)
            .strokeBorder(selected ? Color.accentColor : (tint ?? Color.secondary.opacity(contrast == .increased ? 0.8 : 0.35)),
                          lineWidth: selected ? 2.5 : (tint == nil && contrast != .increased ? 1 : 2))
    }

    // MARK: Handles

    private func connectLabel(_ side: CanvasSide) -> Text {
        switch side {
        case .top: Text("Connect from top side")
        case .right: Text("Connect from right side")
        case .bottom: Text("Connect from bottom side")
        case .left: Text("Connect from left side")
        }
    }

    private var handles: some View {
        GeometryReader { geo in
            let f = CGRect(origin: .zero, size: geo.size)
            ForEach(CanvasSide.allCases, id: \.self) { side in
                let p = CanvasModel.anchor(f, side)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                    .frame(width: handleSize, height: handleSize)   // touch target, constant on screen
                    .contentShape(Circle())
                    .position(p)
                    .gesture(
                        DragGesture(coordinateSpace: .named("canvas"))
                            .onChanged { v in model.pendingEdge = (node.id, side, v.location) }
                            .onEnded { v in model.pendingEdge = nil; model.connect(from: node.id, side: side, toPoint: v.location) }
                    )
                    .accessibilityLabel(connectLabel(side))
            }
            if selected {
                Image(systemName: "arrow.down.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.background)
                    .frame(width: 18, height: 18)
                    .background(Color.accentColor, in: .rect(cornerRadius: 4))
                    .frame(width: handleSize, height: handleSize)
                    .contentShape(Rectangle())
                    .position(x: f.maxX, y: f.maxY)
                    .gesture(
                        DragGesture(coordinateSpace: .named("canvas"))
                            .onChanged { v in model.resizeChanged(node.id, translation: v.translation) }
                            .onEnded { _ in model.dragEnded("Resize") }
                    )
                    .accessibilityLabel("Resize")
            }
        }
    }

    /// Handles live inside the zoomed canvas, so divide by zoom to keep a fixed on-screen hit area.
    private var handleSize: CGFloat {
        #if os(iOS)
        44 / max(model.zoom, 0.1)
        #else
        28 / max(model.zoom, 0.1)
        #endif
    }

    static var editHint: LocalizedStringKey {
        #if os(iOS)
        "Double-tap to edit"
        #else
        "Double-click to edit"
        #endif
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("canvas"))
            .onChanged { v in model.dragChanged(node.id, translation: v.translation, additive: additive) }
            .onEnded { _ in model.dragEnded("Move") }
    }

    // MARK: Actions

    private func activate() {
        switch node.type {
        case "text", "group": model.beginEditing(node.id)
        case "file":
            if let f = node.file { window.open(path: f, line: node.subpath.flatMap { window.line(for: $0.hasPrefix("#") ? String($0.dropFirst()) : $0, in: f) }) }
        case "link": if let u = node.url.flatMap(URL.init(string:)) { window.open(.web(u)) }
        default: break
        }
    }

    @ViewBuilder private var menu: some View {
        switch node.type {
        case "text": Button("Edit", systemImage: "pencil") { model.beginEditing(node.id) }
        case "group": Button("Rename Group", systemImage: "pencil") { model.beginEditing(node.id) }
        case "file", "link": Button("Open", systemImage: "arrow.up.forward.square") { activate() }
        default: EmptyView()
        }
        Menu("Color") {
            Button("No Color") { model.selection = [node.id]; model.setColor(nil) }
            ForEach(CanvasColor.presets, id: \.id) { p in
                Button(String(localized: p.name)) { model.selection = [node.id]; model.setColor(p.id) }
            }
        }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) {
            if !model.selection.contains(node.id) { model.selection = [node.id] }
            model.deleteSelection()
        }
    }

    private var accessibilityTitle: String {
        switch node.type {
        case "file": String(localized: "Note card: \(node.displayTitle)")
        case "link": String(localized: "Web page card: \(node.displayTitle)")
        case "group": String(localized: "Group: \(node.displayTitle)")
        default: (node.text ?? "").isEmpty ? String(localized: "Empty text card") : String(localized: "Text card: \(node.text ?? "")")
        }
    }

    /// Canvas text cards use inline Markdown; headings are shown bold.
    static func markdown(_ s: String) -> AttributedString {
        let prepared = s.components(separatedBy: "\n").map { line -> String in
            if let r = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) { return "**\(line[r.upperBound...])**" }
            return line
        }.joined(separator: "\n")
        return (try? AttributedString(markdown: prepared, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// A vault file shown inside a card: image, or the note's title and an excerpt.
struct FileCard: View {
    let path: String
    let subpath: String?
    @Environment(WindowState.self) private var window

    var body: some View {
        let url = window.model.vault.url(for: path)
        if ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"].contains(path.fileExtension), let img = loadImage(url) {
            img.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(.rect(cornerRadius: 10))
        } else if path.isMarkdown {
            VStack(alignment: .leading, spacing: 8) {
                Label(path.noteName + (subpath ?? ""), systemImage: "doc.text").font(.headline).lineLimit(1)
                Divider()
                Text(CanvasNodeView.markdown(excerpt))
                    .font(.callout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
            }
            .padding(12)
        } else {
            Label((path as NSString).lastPathComponent, systemImage: symbol(for: path)).font(.headline).padding(12)
        }
    }

    private var excerpt: String {
        let text = window.model.text(of: path)
        let body = subpath.map { HTMLRenderer.section(of: text, subpath: $0.hasPrefix("#") ? String($0.dropFirst()) : $0) } ?? text
        let ns = body as NSString
        let start = Frontmatter.locate(in: body).map { NSMaxRange($0.range) } ?? 0
        return String(ns.substring(from: start).prefix(1200))
    }

    private func loadImage(_ url: URL) -> Image? {
        ImageCache.shared.image(at: url).map(Image.init(platformImage:))
    }
}

/// VoiceOver / Switch Control alternatives to the drag-only canvas gestures.
private struct CanvasNodeAccessibility: ViewModifier {
    let model: CanvasModel
    let node: CanvasNode
    let title: String
    let selected: Bool
    let activate: () -> Void

    func body(content: Content) -> some View {
        base(content)
            .accessibilityActions {
                // One action that opens a searchable picker, instead of one action per card.
                Button(String(localized: "Connect…")) { model.connectingFrom = node.id }
                Button(String(localized: "No Color")) { model.setColor(nil, for: node.id) }
                ForEach(CanvasColor.presets, id: \.id) { p in
                    Button(String(localized: "Color: \(String(localized: p.name))")) { model.setColor(p.id, for: node.id) }
                }
            }
    }

    private func announce(_ s: String) { AccessibilityNotification.Announcement(s).post() }

    private func resize(_ d: Double) {
        let before = model.canvas.node(node.id)?.frame.size
        model.nudge(node.id, dw: d, dh: d)
        announce(model.canvas.node(node.id)?.frame.size == before ? String(localized: "Minimum size") : String(localized: "Resized"))
    }

    private func base(_ content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction(named: "Open") { activate() }
            .accessibilityAction(named: "Delete") { model.selection = [node.id]; model.deleteSelection() }
            .accessibilityAction(named: "Move left") { model.nudge(node.id, dx: -40); announce(String(localized: "Moved")) }
            .accessibilityAction(named: "Move right") { model.nudge(node.id, dx: 40); announce(String(localized: "Moved")) }
            .accessibilityAction(named: "Move up") { model.nudge(node.id, dy: -40); announce(String(localized: "Moved")) }
            .accessibilityAction(named: "Move down") { model.nudge(node.id, dy: 40); announce(String(localized: "Moved")) }
            .accessibilityAction(named: "Make larger") { resize(40) }
            .accessibilityAction(named: "Make smaller") { resize(-40) }
    }
}
