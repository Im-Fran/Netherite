import SwiftUI
import NetheriteCore

nonisolated enum CanvasSide: String, CaseIterable { case top, right, bottom, left }

/// Editing state for one open `.canvas` file. Coordinates: screen = canvas × zoom + offset.
@MainActor @Observable
final class CanvasModel {
    let path: String
    let vault: Vault
    var canvas = JSONCanvas()
    var selection: Set<String> = []
    var selectedEdge: String?
    /// Card chosen as the source of an accessibility "Connect…" action.
    var connectingFrom: String?
    var editing: String?
    var zoom: CGFloat = 1
    var offset: CGSize = .zero
    var viewSize: CGSize = .zero
    var selectMode = false
    /// Edge being dragged out of a node's side handle: (from node, side, pointer in screen space).
    var pendingEdge: (node: String, side: CanvasSide, point: CGPoint)?
    /// Rubber-band rectangle in screen space.
    var marquee: CGRect?
    var loadError: String?

    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var lastSaved: Date?
    @ObservationIgnored private(set) var dirty = false
    @ObservationIgnored private var dragOrigins: [String: CGPoint] = [:]
    @ObservationIgnored private var dragSnapshot: JSONCanvas?
    @ObservationIgnored private var didFit = false

    init(path: String, vault: Vault) {
        self.path = path
        self.vault = vault
        load()
    }

    // MARK: Persistence

    func load() {
        do {
            canvas = try JSONCanvas.parse((try? vault.read(path)) ?? "")
            lastSaved = modificationDate
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private var modificationDate: Date? {
        try? vault.url(for: path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Reloads when the file was changed by another app or device and we have nothing unsaved.
    // ponytail: polled while visible; hook into the vault watcher if canvases ever get indexed.
    func reloadIfChangedExternally() {
        guard !dirty, editing == nil, dragSnapshot == nil, let mod = modificationDate, mod != lastSaved else { return }
        load()
    }

    func scheduleSave() {
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        saveTask?.cancel()
        guard dirty else { return }
        do {
            try vault.write(canvas.serialized(), to: path)
            dirty = false
            lastSaved = modificationDate
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: Undo

    /// Applies a change as one undoable step.
    func mutate(_ name: LocalizedStringResource, _ body: (inout JSONCanvas) -> Void) {
        let before = canvas
        body(&canvas)
        guard canvas != before else { return }
        registerUndo(name, restoring: before)
        scheduleSave()
    }

    private func registerUndo(_ name: LocalizedStringResource, restoring old: JSONCanvas) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { m in
            let current = m.canvas
            m.canvas = old
            m.selection = m.selection.filter { id in old.nodes.contains { $0.id == id } }
            m.registerUndo(name, restoring: current)
            m.scheduleSave()
        }
        um.setActionName(String(localized: name))
    }

    // MARK: Geometry

    func toCanvas(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - offset.width) / zoom, y: (p.y - offset.height) / zoom) }
    func toScreen(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * zoom + offset.width, y: p.y * zoom + offset.height) }

    var viewportCenter: CGPoint { toCanvas(CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)) }

    func zoom(to newZoom: CGFloat, around p: CGPoint) {
        let z = min(4, max(0.1, newZoom))
        offset = CGSize(width: p.x - (p.x - offset.width) * z / zoom, height: p.y - (p.y - offset.height) * z / zoom)
        zoom = z
    }

    func zoomToFit() {
        guard viewSize.width > 0 else { return }
        guard let b = canvas.bounds?.insetBy(dx: -60, dy: -60) else {
            zoom = 1; offset = CGSize(width: viewSize.width / 2, height: viewSize.height / 2); return
        }
        zoom = min(1, min(viewSize.width / b.width, viewSize.height / b.height))
        offset = CGSize(width: (viewSize.width - b.width * zoom) / 2 - b.minX * zoom,
                        height: (viewSize.height - b.height * zoom) / 2 - b.minY * zoom)
    }

    func fitOnce() {
        guard !didFit, viewSize.width > 0 else { return }
        didFit = true
        zoomToFit()
    }

    nonisolated static func anchor(_ f: CGRect, _ side: CanvasSide) -> CGPoint {
        switch side {
        case .top: CGPoint(x: f.midX, y: f.minY)
        case .right: CGPoint(x: f.maxX, y: f.midY)
        case .bottom: CGPoint(x: f.midX, y: f.maxY)
        case .left: CGPoint(x: f.minX, y: f.midY)
        }
    }

    nonisolated static func normal(_ side: CanvasSide) -> CGVector {
        switch side {
        case .top: CGVector(dx: 0, dy: -1)
        case .right: CGVector(dx: 1, dy: 0)
        case .bottom: CGVector(dx: 0, dy: 1)
        case .left: CGVector(dx: -1, dy: 0)
        }
    }

    /// Side of `f` facing point `p` (used when an edge has no explicit side).
    nonisolated static func side(of f: CGRect, facing p: CGPoint) -> CanvasSide {
        let dx = (p.x - f.midX) / max(f.width, 1), dy = (p.y - f.midY) / max(f.height, 1)
        return abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .bottom : .top)
    }

    /// Topmost node under a canvas point, preferring cards over groups.
    func node(at p: CGPoint) -> CanvasNode? {
        let hits = canvas.nodes.filter { $0.frame.contains(p) }
        return hits.last { $0.type != "group" } ?? hits.last
    }

    // MARK: Selection

    func select(_ id: String, additive: Bool) {
        selectedEdge = nil
        if additive { if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } }
        else if !selection.contains(id) { selection = [id] }
    }

    func clearSelection() {
        selection = []; selectedEdge = nil; editing = nil
    }

    func selectAll() { selection = Set(canvas.nodes.map(\.id)) }

    func finishMarquee() {
        guard let m = marquee else { return }
        let a = toCanvas(m.origin), b = toCanvas(CGPoint(x: m.maxX, y: m.maxY))
        let r = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
        selection.formUnion(canvas.nodes.filter { r.intersects($0.frame) }.map(\.id))
        marquee = nil
    }

    // MARK: Moving and resizing

    func dragChanged(_ id: String, translation: CGSize, additive: Bool) {
        if dragSnapshot == nil {
            if !selection.contains(id) { select(id, additive: additive) }
            dragSnapshot = canvas
            var ids = selection
            for g in canvas.nodes where selection.contains(g.id) && g.type == "group" {
                ids.formUnion(canvas.children(ofGroup: g).map(\.id))
            }
            dragOrigins = Dictionary(uniqueKeysWithValues: canvas.nodes.filter { ids.contains($0.id) }.map { ($0.id, CGPoint(x: $0.x, y: $0.y)) })
        }
        for i in canvas.nodes.indices {
            guard let o = dragOrigins[canvas.nodes[i].id] else { continue }
            canvas.nodes[i].x = (o.x + translation.width / zoom).rounded()
            canvas.nodes[i].y = (o.y + translation.height / zoom).rounded()
        }
    }

    func resizeChanged(_ id: String, translation: CGSize) {
        if dragSnapshot == nil {
            dragSnapshot = canvas
            if let n = canvas.node(id) { dragOrigins = [id: CGPoint(x: n.width, y: n.height)] }
        }
        guard let o = dragOrigins[id], let i = canvas.nodes.firstIndex(where: { $0.id == id }) else { return }
        canvas.nodes[i].width = max(60, (o.x + translation.width / zoom).rounded())
        canvas.nodes[i].height = max(40, (o.y + translation.height / zoom).rounded())
    }

    func dragEnded(_ name: LocalizedStringResource) {
        if let before = dragSnapshot, before != canvas {
            registerUndo(name, restoring: before)
            scheduleSave()
        }
        dragSnapshot = nil
        dragOrigins = [:]
    }

    // MARK: Editing text

    @ObservationIgnored private var editSnapshot: JSONCanvas?

    func beginEditing(_ id: String) {
        editSnapshot = canvas
        selection = [id]
        editing = id
    }

    func setText(_ id: String, _ text: String) {
        guard let i = canvas.nodes.firstIndex(where: { $0.id == id }) else { return }
        if canvas.nodes[i].type == "group" { canvas.nodes[i].label = text } else { canvas.nodes[i].text = text }
        scheduleSave()
    }

    func endEditing() {
        if let before = editSnapshot, before != canvas { registerUndo("Edit card", restoring: before) }
        editSnapshot = nil
        editing = nil
    }

    // MARK: Commands

    @discardableResult
    func addNode(_ node: CanvasNode) -> String {
        NetheriteTips.donate(NetheriteTips.canvasCardAdded)
        mutate("Add card") { $0.nodes.append(node) }
        selection = [node.id]
        return node.id
    }

    func addText(at p: CGPoint? = nil) {
        let c = p ?? viewportCenter
        let id = addNode(CanvasNode(type: "text", x: (c.x - 130).rounded(), y: (c.y - 30).rounded(), width: 260, height: 60, text: ""))
        beginEditing(id)
    }

    func addFile(_ file: String) {
        let c = viewportCenter
        let big = file.isMarkdown || ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(file.fileExtension)
        addNode(CanvasNode(type: "file", x: (c.x - 200).rounded(), y: (c.y - 200).rounded(), width: 400, height: big ? 400 : 80, file: file))
    }

    func addLink(_ url: String) {
        let c = viewportCenter
        addNode(CanvasNode(type: "link", x: (c.x - 200).rounded(), y: (c.y - 60).rounded(), width: 400, height: 120, url: url))
    }

    func groupSelection() {
        let frames = canvas.nodes.filter { selection.contains($0.id) }.map(\.frame)
        guard let b = frames.reduce(nil, { (acc: CGRect?, r) in acc.map { $0.union(r) } ?? r })?.insetBy(dx: -40, dy: -40) else { return }
        let g = CanvasNode(type: "group", x: b.minX, y: b.minY, width: b.width, height: b.height, label: String(localized: "Group"))
        mutate("Create group") { $0.nodes.insert(g, at: 0) }
        selection = [g.id]
    }

    func deleteSelection() {
        if let e = selectedEdge {
            mutate("Delete connection") { $0.edges.removeAll { $0.id == e } }
            selectedEdge = nil
            return
        }
        guard !selection.isEmpty else { return }
        let ids = selection
        mutate("Delete") { c in
            c.nodes.removeAll { ids.contains($0.id) }
            c.edges.removeAll { ids.contains($0.fromNode) || ids.contains($0.toNode) }
        }
        selection = []
    }

    func setColor(_ color: String?) {
        let ids = selection, edge = selectedEdge
        mutate("Change color") { c in
            for i in c.nodes.indices where ids.contains(c.nodes[i].id) { c.nodes[i].color = color }
            for i in c.edges.indices where c.edges[i].id == edge { c.edges[i].color = color }
        }
    }

    func connect(from: String, side: CanvasSide, toPoint screen: CGPoint) {
        let p = toCanvas(screen)
        guard let target = node(at: p), target.id != from, let source = canvas.node(from) else { return }
        let toSide = Self.side(of: target.frame, facing: Self.anchor(source.frame, side))
        mutate("Connect cards") { $0.edges.append(CanvasEdge(fromNode: from, fromSide: side.rawValue, toNode: target.id, toSide: toSide.rawValue)) }
    }

    func isConnected(_ a: String, _ b: String) -> Bool {
        canvas.edges.contains { ($0.fromNode == a && $0.toNode == b) || ($0.fromNode == b && $0.toNode == a) }
    }

    /// Colors one node without touching the current selection or selected edge.
    func setColor(_ color: String?, for id: String) {
        mutate("Change color") { c in
            if let i = c.nodes.firstIndex(where: { $0.id == id }) { c.nodes[i].color = color }
        }
    }

    /// Accessibility alternative to dragging a connection handle.
    func connect(from: String, to: String) {
        guard from != to, !isConnected(from, to), let a = canvas.node(from), let b = canvas.node(to) else { return }
        let fs = Self.side(of: a.frame, facing: CGPoint(x: b.frame.midX, y: b.frame.midY))
        let ts = Self.side(of: b.frame, facing: CGPoint(x: a.frame.midX, y: a.frame.midY))
        mutate("Connect cards") { $0.edges.append(CanvasEdge(fromNode: from, fromSide: fs.rawValue, toNode: to, toSide: ts.rawValue)) }
    }

    /// Accessibility alternative to dragging: moves or resizes a node by a fixed step.
    func nudge(_ id: String, dx: Double = 0, dy: Double = 0, dw: Double = 0, dh: Double = 0) {
        mutate(dw != 0 || dh != 0 ? "Resize" : "Move") { c in
            guard let i = c.nodes.firstIndex(where: { $0.id == id }) else { return }
            c.nodes[i].x += dx; c.nodes[i].y += dy
            c.nodes[i].width = max(60, c.nodes[i].width + dw); c.nodes[i].height = max(40, c.nodes[i].height + dh)
        }
    }

    func setEdgeLabel(_ id: String, _ label: String) {
        mutate("Edit label") { c in
            if let i = c.edges.firstIndex(where: { $0.id == id }) { c.edges[i].label = label.isEmpty ? nil : label }
        }
    }
}

/// Obsidian's six preset colors plus hex strings.
enum CanvasColor {
    /// The presets as drawn: color-blind-safe stand-ins when Accessibility › Color Filters is on.
    static var presets: [(id: String, name: LocalizedStringResource, color: Color)] {
        let a = A11y.shared
        return [
            ("1", "Red", a.color(.red, .red)), ("2", "Orange", a.color(.orange, .orange)), ("3", "Yellow", a.color(.yellow, .yellow)),
            ("4", "Green", a.color(.green, .green)), ("5", "Cyan", a.color(.cyan, .cyan)), ("6", "Purple", a.color(.purple, .purple)),
        ]
    }

    /// Spoken name of a card or edge color: the preset's name, or "Custom" for a hex color.
    static func name(_ value: String?) -> String? {
        guard let value else { return nil }
        return presets.first { $0.id == value }.map { String(localized: $0.name) } ?? String(localized: "Custom")
    }

    static func color(_ value: String?) -> Color? {
        guard let value else { return nil }
        if let p = presets.first(where: { $0.id == value }) { return p.color }
        return PlatformColor(hex: value).map { Color($0) }
    }
}
