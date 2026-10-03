import SwiftUI
import TipKit
import NetheriteCore

/// Force-directed layout. Positions live outside observation; `frame` bumps once per tick to redraw.
@Observable
final class GraphSimulation {
    private(set) var data = GraphData()
    var frame = 0
    private(set) var settled = true
    /// Bumped when the simulation needs to (re)start its tick loop.
    private(set) var generation = 0

    @ObservationIgnored var positions: [String: CGPoint] = [:]
    @ObservationIgnored private var velocities: [String: CGVector] = [:]
    @ObservationIgnored var pinned: String?
    @ObservationIgnored private var alpha = 1.0
    @ObservationIgnored var settings = GraphSettings()
    @ObservationIgnored private(set) var neighbours: [String: Set<String>] = [:]

    /// Replaces the graph, keeping positions of nodes that survive.
    func load(_ new: GraphData, reduceMotion: Bool) {
        data = new
        neighbours = [:]
        for e in new.edges { neighbours[e.from, default: []].insert(e.to); neighbours[e.to, default: []].insert(e.from) }
        let golden = Double.pi * (3 - 5.0.squareRoot())
        for (i, n) in new.nodes.enumerated() where positions[n.id] == nil {
            // Sunflower seeding: deterministic and already roughly spread out.
            let r = 12 * Double(i).squareRoot(), a = Double(i) * golden
            positions[n.id] = CGPoint(x: r * cos(a), y: r * sin(a))
        }
        let ids = Set(new.nodes.map(\.id))
        positions = positions.filter { ids.contains($0.key) }
        velocities = velocities.filter { ids.contains($0.key) }
        reheat(reduceMotion: reduceMotion)
    }

    func reheat(reduceMotion: Bool, alpha a: Double = 1) {
        alpha = max(alpha, a)
        if reduceMotion {
            // No animation: settle synchronously.
            for _ in 0..<300 where alpha > 0.005 { step() }
            settled = true
            frame += 1
        } else {
            settled = false
            generation += 1
        }
    }

    /// One tick; returns false once the layout has cooled down.
    @discardableResult
    func tick() -> Bool {
        step()
        frame += 1
        if alpha <= 0.005 && pinned == nil { settled = true }
        return !settled
    }

    // ponytail: O(n²) repulsion, fine up to ~2k nodes; switch to Barnes–Hut (quadtree) beyond that.
    private func step() {
        let nodes = data.nodes
        let repel = 3000 * settings.repelForce
        var force: [String: CGVector] = [:]
        for i in nodes.indices {
            let a = nodes[i].id
            guard let pa = positions[a] else { continue }
            var f = CGVector(dx: -pa.x * 0.02, dy: -pa.y * 0.02)   // centre gravity
            for j in nodes.indices where j != i {
                guard let pb = positions[nodes[j].id] else { continue }
                var dx = pa.x - pb.x, dy = pa.y - pb.y
                var d2 = dx * dx + dy * dy
                if d2 < 0.01 { dx = Double(i - j) * 0.1; dy = 0.1; d2 = 0.02 }
                let k = repel / max(d2, 25)
                let d = d2.squareRoot()
                f.dx += dx / d * k; f.dy += dy / d * k
            }
            force[a] = f
        }
        for e in data.edges {
            guard let pa = positions[e.from], let pb = positions[e.to] else { continue }
            let dx = pb.x - pa.x, dy = pb.y - pa.y
            let d = max((dx * dx + dy * dy).squareRoot(), 0.01)
            let k = (d - settings.linkDistance) * 0.05
            force[e.from, default: .zero].dx += dx / d * k; force[e.from, default: .zero].dy += dy / d * k
            force[e.to, default: .zero].dx -= dx / d * k; force[e.to, default: .zero].dy -= dy / d * k
        }
        for n in nodes where n.id != pinned {
            guard let p = positions[n.id], let f = force[n.id] else { continue }
            var v = velocities[n.id] ?? .zero
            v.dx = (v.dx + f.dx * alpha) * 0.6
            v.dy = (v.dy + f.dy * alpha) * 0.6
            velocities[n.id] = v
            positions[n.id] = CGPoint(x: p.x + v.dx, y: p.y + v.dy)
        }
        alpha *= 0.985
    }

    func radius(_ n: GraphNode) -> CGFloat {
        (4 + CGFloat(Double(n.degree).squareRoot()) * 2.2) * settings.nodeSize
    }

    /// Half of the minimum on-screen target (44 pt on touch, 16 pt with a pointer).
    #if os(iOS)
    static let minHitRadius: CGFloat = 22
    #else
    static let minHitRadius: CGFloat = 8
    #endif

    func hit(_ world: CGPoint, scale: CGFloat) -> GraphNode? {
        data.nodes.last { n in
            guard let p = positions[n.id] else { return false }
            return hypot(p.x - world.x, p.y - world.y) <= max(radius(n), Self.minHitRadius / scale)
        }
    }
}

struct GraphView: View {
    let focus: String?
    @Environment(WindowState.self) private var window
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 12
    @State private var sim = GraphSimulation()
    @State private var settings = GraphSettings()
    @State private var loaded = false
    @State private var offset: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var gestureScale: CGFloat = 1
    @State private var panStart: CGSize?
    @State private var draggingNode: String?
    @State private var hovered: String?
    @State private var showSettings = false

    private var model: VaultModel { window.model }
    private var zoom: CGFloat { scale * gestureScale }

    var body: some View {
        GeometryReader { geo in
            canvas(size: geo.size)
                .gesture(dragGesture(size: geo.size))
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { gestureScale = $0.magnification }
                    .onEnded { scale = clampZoom(scale * $0.magnification); gestureScale = 1 })
                .onTapGesture(coordinateSpace: .local) { tap($0, size: geo.size) }
                #if os(macOS)
                .onContinuousHover { phase in
                    if case .active(let p) = phase { hovered = sim.hit(toWorld(p, size: geo.size), scale: zoom)?.id } else { hovered = nil }
                }
                #endif
        }
        .background(.background)
        .overlay(alignment: .topTrailing) { controls.padding(12) }
        .navigationTitle(focus.map { String(localized: "Local Graph: \($0.noteName)") } ?? String(localized: "Graph View"))
        .task(id: rebuildKey) {
            if !loaded {
                settings = model.vault.loadConfig("graph.json", fallback: GraphSettings())
                loaded = true
            }
            sim.settings = settings
            sim.load(GraphData.build(from: model.index, settings: settings, focus: focus), reduceMotion: reduceMotion)
        }
        .task(id: sim.generation) {
            while !Task.isCancelled && sim.tick() {
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        .onChange(of: settings) { _, new in
            guard loaded else { return }
            model.vault.saveConfig("graph.json", new)
        }
    }

    /// Anything that changes which nodes/edges exist or how the layout behaves.
    private var rebuildKey: String {
        "\(model.index.revision)|\(focus ?? "")|\(settings.hashValue)|\(loaded)"
    }

    // MARK: Drawing

    private func canvas(size: CGSize) -> some View {
        let data = sim.data
        let active = window.panes.lazy.compactMap { if case .note(let p) = $0.current { p } else { nil } }.first ?? focus
        let highlight = hovered.map { Set([$0]).union(sim.neighbours[$0] ?? []) }
        let accent = Color.accentColor
        let tagColor = Color(pair: model.theme.tag, fallback: .purple)
        let groups: [Color] = [.blue, .green, .orange, .pink, .teal, .indigo, .mint, .brown]
        let colorByTag = settings.colorByTag
        let shapes = differentiateWithoutColor
        let edgeOpacity = contrast == .increased ? 0.7 : 0.35
        let unresolvedOpacity = contrast == .increased ? 1.0 : (shapes ? 0.7 : 0.4)
        let labelSize = self.labelSize
        let _ = sim.frame   // observe ticks
        return Canvas { ctx, size in
            ctx.translateBy(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
            ctx.scaleBy(x: zoom, y: zoom)
            let lineWidth = 1 / zoom
            for e in data.edges {
                guard let a = sim.positions[e.from], let b = sim.positions[e.to] else { continue }
                let lit = highlight.map { $0.contains(e.from) && $0.contains(e.to) && (e.from == hovered || e.to == hovered) } ?? false
                var path = Path(); path.move(to: a); path.addLine(to: b)
                ctx.stroke(path, with: .color(lit ? accent : Color.secondary.opacity(highlight == nil ? edgeOpacity : 0.12)),
                           lineWidth: lit ? lineWidth * 2 : lineWidth)
            }
            let labelOpacity = min(1, max(0, (zoom - 0.7) / 0.5))
            for n in data.nodes {
                guard let p = sim.positions[n.id] else { continue }
                let r = sim.radius(n)
                let dimmed = highlight.map { !$0.contains(n.id) } ?? false
                var color: Color = switch n.kind {
                case .note: colorByTag ? (n.group.map { groups[$0.unicodeScalars.reduce(0) { $0 + Int($1.value) } % groups.count] } ?? .secondary) : .secondary
                case .attachment: .gray
                case .tag: tagColor
                case .unresolved: Color.secondary.opacity(unresolvedOpacity)
                }
                if n.id == active { color = accent }
                if n.id == hovered { color = accent }
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                let shading = GraphicsContext.Shading.color(color.opacity(dimmed ? 0.25 : 1))
                if shapes && n.kind != .note {
                    // Differentiate Without Color: tags are diamonds, attachments squares, unresolved hollow.
                    switch n.kind {
                    case .tag:
                        var d = Path()
                        d.move(to: CGPoint(x: p.x, y: rect.minY)); d.addLine(to: CGPoint(x: rect.maxX, y: p.y))
                        d.addLine(to: CGPoint(x: p.x, y: rect.maxY)); d.addLine(to: CGPoint(x: rect.minX, y: p.y)); d.closeSubpath()
                        ctx.fill(d, with: shading)
                    case .attachment: ctx.fill(Path(rect.insetBy(dx: r * 0.1, dy: r * 0.1)), with: shading)
                    default: ctx.stroke(Path(ellipseIn: rect.insetBy(dx: lineWidth, dy: lineWidth)), with: shading, lineWidth: 2 * lineWidth)
                    }
                } else {
                    ctx.fill(Path(ellipseIn: rect), with: shading)
                }
                let showLabel = n.id == hovered || n.id == active
                let opacity = showLabel ? 1 : labelOpacity * (dimmed ? 0.3 : 1)
                if opacity > 0.02 {
                    ctx.draw(Text(n.label).font(.system(size: labelSize / max(zoom, 0.6))).foregroundStyle(.primary.opacity(opacity)),
                             at: CGPoint(x: p.x, y: p.y + r + 8 / zoom), anchor: .top)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Graph with \(data.nodes.count) nodes and \(data.edges.count) links"))
        .accessibilityChildren {
            // List alternative for VoiceOver: every node as a button that opens it.
            ForEach(data.nodes) { n in
                Button(n.label) { open(n, newPane: false) }
                    .accessibilityHint(Text("\(n.degree) links"))
            }
        }
    }

    // MARK: Coordinates and gestures

    private func toWorld(_ p: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(x: (p.x - size.width / 2 - offset.width) / zoom, y: (p.y - size.height / 2 - offset.height) / zoom)
    }

    private func clampZoom(_ z: CGFloat) -> CGFloat { min(max(z, 0.1), 6) }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { v in
                if panStart == nil && draggingNode == nil {
                    if let n = sim.hit(toWorld(v.startLocation, size: size), scale: zoom) {
                        draggingNode = n.id
                        sim.pinned = n.id
                    } else {
                        panStart = offset
                    }
                }
                if let id = draggingNode {
                    sim.positions[id] = toWorld(v.location, size: size)
                    // With Reduce Motion the layout settles synchronously, so only do that once on release.
                    if reduceMotion { sim.frame += 1 } else { sim.reheat(reduceMotion: false, alpha: 0.3) }
                } else if let start = panStart {
                    offset = CGSize(width: start.width + v.translation.width, height: start.height + v.translation.height)
                }
            }
            .onEnded { _ in
                NetheriteTips.donate(NetheriteTips.graphInteracted)
                if draggingNode != nil { sim.pinned = nil; sim.reheat(reduceMotion: reduceMotion, alpha: 0.1) }
                draggingNode = nil
                panStart = nil
            }
    }

    private func tap(_ p: CGPoint, size: CGSize) {
        guard let n = sim.hit(toWorld(p, size: size), scale: zoom) else { return }
        #if os(macOS)
        let newPane = NSEvent.modifierFlags.contains(.command)
        #else
        let newPane = false
        #endif
        open(n, newPane: newPane)
    }

    private func open(_ n: GraphNode, newPane: Bool) {
        switch n.kind {
        case .note, .attachment: window.open(path: n.id, newPane: newPane)
        case .tag: window.searchQuery = "tag:\(n.label.dropFirst())"; window.sidebarTab = .search; window.columnVisibility = .all; window.preferredCompactColumn = .sidebar
        case .unresolved: window.follow(NoteParser.splitWiki(String(n.id.dropFirst("unresolved:".count)), isEmbed: false), from: nil, newPane: newPane)
        }
    }

    // MARK: Settings panel

    /// nil under Reduce Motion so panel and zoom changes happen without animation.
    private var motion: Animation? { reduceMotion ? nil : .default }

    private func iconButton(_ title: LocalizedStringKey, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button { withAnimation(motion, action) } label: {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(minWidth: 28, minHeight: 28)
                #if os(iOS)
                .frame(minWidth: 44, minHeight: 44)
                #endif
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(Text(title))
    }

    private var controls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 4) {
                iconButton("Zoom Out", "minus.magnifyingglass") { scale = clampZoom(scale / 1.3) }
                iconButton("Zoom In", "plus.magnifyingglass") { scale = clampZoom(scale * 1.3) }
                iconButton("Reset View", "scope") { scale = 1; offset = .zero }
                iconButton("Graph Settings", "slider.horizontal.3") { showSettings.toggle() }
                    .popoverTip(GraphControlsTip(), arrowEdge: .trailing)
            }
            .padding(6)
            .glassEffect(in: .capsule)

            if showSettings {
                Form {
                    TextField("Search files", text: $settings.search)
                    if focus != nil {
                        Stepper("Depth: \(settings.depth)", value: $settings.depth, in: 1...3)
                    }
                    Toggle("Tags", isOn: $settings.showTags)
                    Toggle("Attachments", isOn: $settings.showAttachments)
                    Toggle("Orphans", isOn: $settings.showOrphans)
                    Toggle("Unresolved links", isOn: $settings.showUnresolved)
                    Toggle("Color by tag", isOn: $settings.colorByTag)
                    LabeledContent("Link distance") { Slider(value: $settings.linkDistance, in: 30...250) }
                    LabeledContent("Repel force") { Slider(value: $settings.repelForce, in: 0.2...4) }
                    LabeledContent("Node size") { Slider(value: $settings.nodeSize, in: 0.5...3) }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .frame(width: 280, height: focus != nil ? 460 : 420)
                .glassEffect(in: .rect(cornerRadius: 16))
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
            }
        }
    }
}
