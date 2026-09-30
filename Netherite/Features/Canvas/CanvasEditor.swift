import SwiftUI
import NetheriteCore

/// Infinite canvas editor for `.canvas` (JSON Canvas) files.
struct CanvasEditor: View {
    let path: String
    @Environment(WindowState.self) private var window
    @Environment(\.undoManager) private var undoManager
    @State private var model: CanvasModel?

    var body: some View {
        Group {
            if let model {
                CanvasSurface(model: model)
            } else {
                ProgressView()
            }
        }
        .onAppear { if model == nil { model = CanvasModel(path: path, vault: window.model.vault) } }
        .onChange(of: undoManager, initial: true) { model?.undoManager = undoManager }
        .onChange(of: model == nil) { model?.undoManager = undoManager }
        .onDisappear { model?.save() }
    }
}

private let space = "canvas"

struct CanvasSurface: View {
    @Bindable var model: CanvasModel
    @Environment(WindowState.self) private var window
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panStart: CGSize?
    @State private var zoomStart: CGFloat?
    @State private var addingFile = false
    @State private var addingLink = false
    @State private var linkText = ""
    @State private var labelingEdge: String?
    @State private var labelText = ""
    @State private var hovering: CGPoint?
    #if os(macOS)
    @State private var scrollMonitor: Any?
    #endif

    private var additive: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.shift) || model.selectMode
        #else
        model.selectMode
        #endif
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                grid
                background
                world
                if let m = model.marquee {
                    Rectangle().fill(Color.accentColor.opacity(0.1))
                        .overlay(Rectangle().strokeBorder(Color.accentColor, lineWidth: 1))
                        .frame(width: m.width, height: m.height)
                        .offset(x: m.minX, y: m.minY)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(.named(space))
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(magnify)
            .onAppear { model.viewSize = geo.size; model.fitOnce() }
            .onChange(of: geo.size) { model.viewSize = geo.size; model.fitOnce() }
        }
        .overlay(alignment: .top) { toolbar.padding(12) }
        .overlay(alignment: .bottomTrailing) { zoomControls.padding(12) }
        .overlay {
            if let e = model.loadError {
                ContentUnavailableView("Couldn't read canvas", systemImage: "exclamationmark.triangle", description: Text(e))
            }
        }
        .background(Color.canvasBackground)
        .sheet(isPresented: $addingFile) { fileSheet }
        .alert("Add web page", isPresented: $addingLink) {
            TextField("https://", text: $linkText)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                var s = linkText.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { if !s.contains("://") { s = "https://" + s }; model.addLink(s) }
                linkText = ""
            }
        }
        .alert("Connection label", isPresented: Binding(get: { labelingEdge != nil }, set: { if !$0 { labelingEdge = nil } })) {
            TextField("Label", text: $labelText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let e = labelingEdge { model.setEdgeLabel(e, labelText) } }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                model.reloadIfChangedExternally()
            }
        }
        #if os(macOS)
        .onContinuousHover(coordinateSpace: .local) { phase in
            if case .active(let p) = phase { hovering = p } else { hovering = nil }
        }
        .onAppear(perform: installScrollMonitor)
        .onDisappear { if let m = scrollMonitor { NSEvent.removeMonitor(m) }; scrollMonitor = nil }
        #endif
    }

    // MARK: Layers

    private var grid: some View {
        Canvas { ctx, size in
            var step = 20 * model.zoom
            while step < 10 { step *= 2 }
            let ox = model.offset.width.truncatingRemainder(dividingBy: step)
            let oy = model.offset.height.truncatingRemainder(dividingBy: step)
            let dot = max(1, min(2, model.zoom * 1.5))
            var path = Path()
            var x = ox - step
            while x < size.width + step {
                var y = oy - step
                while y < size.height + step {
                    path.addEllipse(in: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
                    y += step
                }
                x += step
            }
            ctx.fill(path, with: .color(.secondary.opacity(0.35)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Empty space: pan (or rubber-band select), tap to deselect, double-tap to add a text card.
    private var background: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(space))
                    .onChanged { v in
                        if additive || model.marquee != nil {
                            model.marquee = CGRect(x: min(v.startLocation.x, v.location.x), y: min(v.startLocation.y, v.location.y),
                                                   width: abs(v.location.x - v.startLocation.x), height: abs(v.location.y - v.startLocation.y))
                        } else {
                            if panStart == nil { panStart = model.offset }
                            model.offset = CGSize(width: panStart!.width + v.translation.width, height: panStart!.height + v.translation.height)
                        }
                    }
                    .onEnded { _ in panStart = nil; model.finishMarquee() }
            )
            .onTapGesture(count: 2, coordinateSpace: .named(space)) { p in model.addText(at: model.toCanvas(p)) }
            .onTapGesture { model.endEditing(); model.clearSelection() }
            .accessibilityLabel("Canvas")
            .accessibilityHint("Double-tap to add a card")
    }

    private var world: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.canvas.nodes.filter { $0.type == "group" }) { node in nodeView(node) }
            ForEach(model.canvas.edges) { edge in EdgeView(model: model, edge: edge) { labelText = edge.label ?? ""; labelingEdge = edge.id } }
            ForEach(model.canvas.nodes.filter { $0.type != "group" }) { node in nodeView(node) }
            if let pending = model.pendingEdge, let n = model.canvas.node(pending.node) {
                let from = CanvasModel.anchor(n.frame, pending.side)
                EdgeShape(from: from, fromSide: pending.side, to: model.toCanvas(pending.point), toSide: nil, arrow: true)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2 / model.zoom, dash: [6 / model.zoom]))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 1, height: 1, alignment: .topLeading)
        .scaleEffect(model.zoom, anchor: .topLeading)
        .offset(model.offset)
    }

    private func nodeView(_ node: CanvasNode) -> some View {
        CanvasNodeView(model: model, node: node, additive: additive)
            .frame(width: node.width, height: node.height)
            .offset(x: node.x, y: node.y)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if zoomStart == nil { zoomStart = model.zoom }
                let target = zoomStart! * v.magnification
                model.zoom(to: target, around: v.startLocation)
            }
            .onEnded { _ in zoomStart = nil }
    }

    // MARK: Chrome

    private var toolbar: some View {
        HStack(spacing: 2) {
            tool("Add card", "note.text.badge.plus") { model.addText() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            tool("Add note from vault", "doc.badge.plus") { addingFile = true }
            tool("Add web page", "link.badge.plus") { addingLink = true }
            Divider().frame(height: 24)
            tool("Group selection", "rectangle.dashed") { model.groupSelection() }
                .disabled(model.selection.isEmpty)
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Menu {
                Button("No color") { model.setColor(nil) }
                ForEach(CanvasColor.presets, id: \.id) { p in
                    Button { model.setColor(p.id) } label: { Label(String(localized: p.name), systemImage: "circle.fill").tint(p.color) }
                }
            } label: {
                Label("Color", systemImage: "paintpalette").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
            .menuStyle(.button).buttonStyle(.borderless).fixedSize()
            .disabled(model.selection.isEmpty && model.selectedEdge == nil)
            .help("Color")
            tool("Delete", "trash") { model.deleteSelection() }
                .disabled((model.selection.isEmpty && model.selectedEdge == nil) || model.editing != nil)
                .keyboardShortcut(.delete, modifiers: [])
            Divider().frame(height: 24)
            Toggle(isOn: $model.selectMode) {
                Label("Select mode", systemImage: "rectangle.dashed.and.paperclip").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
            }
            .toggleStyle(.button).buttonStyle(.borderless)
            .help("Drag on empty space to select (or hold ⇧)")
            // Hidden shortcuts
            Button("Select all") { model.selectAll() }.keyboardShortcut("a").hidden().frame(width: 0)
                .disabled(model.editing != nil)
            Button("Deselect") { model.endEditing(); model.clearSelection() }.keyboardShortcut(.escape, modifiers: []).hidden().frame(width: 0)
        }
        .padding(.horizontal, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            tool("Zoom out", "minus.magnifyingglass") { model.zoom(to: model.zoom / 1.25, around: center) }
                .keyboardShortcut("-")
            Text("\(Int(model.zoom * 100))%").font(.caption.monospacedDigit()).frame(minWidth: 44)
                .accessibilityLabel("Zoom \(Int(model.zoom * 100)) percent")
            tool("Zoom in", "plus.magnifyingglass") { model.zoom(to: model.zoom * 1.25, around: center) }
                .keyboardShortcut("=")
            tool("Zoom to fit", "arrow.up.left.and.down.right.magnifyingglass") { withAnimation(reduceMotion ? nil : .smooth) { model.zoomToFit() } }
                .keyboardShortcut("0")
        }
        .padding(.horizontal, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private var center: CGPoint { CGPoint(x: model.viewSize.width / 2, y: model.viewSize.height / 2) }

    private func tool(_ label: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol).labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
    }

    private var fileSheet: some View {
        PaletteView(prompt: "Add a file to the canvas…", items: { q in
            window.model.index.files.filter { $0 != model.path }
                .compactMap { p in Search.fuzzyScore(q, p).map { (p, $0) } }
                .sorted { $0.1 > $1.1 }.prefix(80)
                .map { p, _ in
                    PaletteItem(id: p, title: p.isMarkdown ? p.noteName : (p as NSString).lastPathComponent,
                                subtitle: p.parentFolder.isEmpty ? nil : p.parentFolder, symbol: symbol(for: p)) { _ in model.addFile(p) }
                }
        })
    }

    #if os(macOS)
    /// Scroll to pan, ⌘-scroll to zoom — only while the pointer is over the canvas.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let p = hovering, model.editing == nil else { return event }
            if event.modifierFlags.contains(.command) {
                model.zoom(to: model.zoom * (1 + event.scrollingDeltaY * 0.01), around: p)
            } else {
                model.offset.width += event.scrollingDeltaX
                model.offset.height += event.scrollingDeltaY
            }
            return nil
        }
    }
    #endif
}

extension Color {
    static var canvasBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

// MARK: Edges

nonisolated struct EdgeShape: Shape {
    var from: CGPoint
    var fromSide: CanvasSide
    var to: CGPoint
    var toSide: CanvasSide?
    var arrow: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let d = max(40, min(150, hypot(to.x - from.x, to.y - from.y) / 2))
        let n1 = CanvasModel.normal(fromSide)
        let c1 = CGPoint(x: from.x + n1.dx * d, y: from.y + n1.dy * d)
        let n2 = toSide.map(CanvasModel.normal) ?? CGVector(dx: 0, dy: 0)
        let c2 = CGPoint(x: to.x + n2.dx * d, y: to.y + n2.dy * d)
        p.move(to: from)
        p.addCurve(to: to, control1: c1, control2: c2)
        if arrow {
            // Arrowhead along the curve's final tangent.
            let dir = CGVector(dx: to.x - c2.x, dy: to.y - c2.y)
            let len = max(hypot(dir.dx, dir.dy), 0.001)
            let u = CGVector(dx: dir.dx / len, dy: dir.dy / len)
            let s: CGFloat = 12
            let back = CGPoint(x: to.x - u.dx * s, y: to.y - u.dy * s)
            p.move(to: to)
            p.addLine(to: CGPoint(x: back.x - u.dy * s * 0.5, y: back.y + u.dx * s * 0.5))
            p.move(to: to)
            p.addLine(to: CGPoint(x: back.x + u.dy * s * 0.5, y: back.y - u.dx * s * 0.5))
        }
        return p
    }

    static func midpoint(from: CGPoint, fromSide: CanvasSide, to: CGPoint, toSide: CanvasSide) -> CGPoint {
        let d = max(40, min(150, hypot(to.x - from.x, to.y - from.y) / 2))
        let n1 = CanvasModel.normal(fromSide), n2 = CanvasModel.normal(toSide)
        let c1 = CGPoint(x: from.x + n1.dx * d, y: from.y + n1.dy * d)
        let c2 = CGPoint(x: to.x + n2.dx * d, y: to.y + n2.dy * d)
        return CGPoint(x: 0.125 * from.x + 0.375 * c1.x + 0.375 * c2.x + 0.125 * to.x,
                       y: 0.125 * from.y + 0.375 * c1.y + 0.375 * c2.y + 0.125 * to.y)
    }
}

struct EdgeView: View {
    let model: CanvasModel
    let edge: CanvasEdge
    let editLabel: () -> Void

    var body: some View {
        if let a = model.canvas.node(edge.fromNode), let b = model.canvas.node(edge.toNode) {
            let fs = edge.fromSide.flatMap(CanvasSide.init(rawValue:)) ?? CanvasModel.side(of: a.frame, facing: CGPoint(x: b.frame.midX, y: b.frame.midY))
            let ts = edge.toSide.flatMap(CanvasSide.init(rawValue:)) ?? CanvasModel.side(of: b.frame, facing: CGPoint(x: a.frame.midX, y: a.frame.midY))
            let from = CanvasModel.anchor(a.frame, fs), to = CanvasModel.anchor(b.frame, ts)
            let selected = model.selectedEdge == edge.id
            let color = CanvasColor.color(edge.color) ?? .secondary
            let shape = EdgeShape(from: from, fromSide: fs, to: to, toSide: ts, arrow: (edge.toEnd ?? "arrow") != "none")
            ZStack(alignment: .topLeading) {
                shape.stroke(selected ? Color.accentColor : color, style: StrokeStyle(lineWidth: selected ? 3 : 2, lineCap: .round))
                shape.stroke(Color.white.opacity(0.001), lineWidth: 16)   // generous hit area
                    .contentShape(shape.stroke(lineWidth: 16))
                    .onTapGesture { model.selection = []; model.selectedEdge = edge.id }
                    .onTapGesture(count: 2) { editLabel() }
                    .contextMenu {
                        Button("Edit label…", systemImage: "character.cursor.ibeam", action: editLabel)
                        Button("Delete", systemImage: "trash", role: .destructive) { model.selectedEdge = edge.id; model.deleteSelection() }
                    }
                if let label = edge.label, !label.isEmpty {
                    let mid = EdgeShape.midpoint(from: from, fromSide: fs, to: to, toSide: ts)
                    Text(label)
                        .font(.callout)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.canvasBackground, in: .capsule)
                        .fixedSize()
                        .position(mid)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 1, height: 1, alignment: .topLeading)
            .accessibilityElement()
            .accessibilityLabel("Connection from \(a.displayTitle) to \(b.displayTitle)")
            .accessibilityValue(edge.label ?? "")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(named: "Edit label", editLabel)
            .accessibilityAction(named: "Delete") { model.selectedEdge = edge.id; model.deleteSelection() }
        }
    }
}

extension CanvasNode {
    var displayTitle: String {
        switch type {
        case "file": (file ?? "").noteName
        case "link": url ?? ""
        case "group": label ?? String(localized: "Group")
        default: String((text ?? "").prefix(40))
        }
    }
}
