import Foundation

/// Graph view options, persisted in `.netherite/graph.json`.
public struct GraphSettings: Codable, Hashable, Sendable {
    public var search = ""
    public var showTags = false
    public var showAttachments = false
    public var showOrphans = true
    public var showUnresolved = false
    public var colorByTag = false
    public var linkDistance = 80.0
    public var repelForce = 1.0
    public var nodeSize = 1.0
    public var depth = 1
    public init() {}
}

public struct GraphNode: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable { case note, attachment, tag, unresolved }
    /// Vault path for notes/attachments, "#tag" for tags, "unresolved:target" for missing notes.
    public var id: String
    public var label: String
    public var kind: Kind
    public var degree = 0
    /// First tag of the note, used for group colouring.
    public var group: String?
}

public struct GraphEdge: Hashable, Sendable {
    public var from: String
    public var to: String
}

public struct GraphData: Sendable {
    public var nodes: [GraphNode] = []
    public var edges: [GraphEdge] = []
    public init() {}

    /// Builds the graph. `focus` limits it to nodes within `settings.depth` links of it (either direction).
    public static func build(files: [String], outgoing: [String: [String]], unresolved: [String: [String]],
                             tags: [String: [String]], settings s: GraphSettings, focus: String? = nil) -> GraphData {
        var nodes: [String: GraphNode] = [:]
        var edges = Set<GraphEdge>()
        for f in files where f.isMarkdown || s.showAttachments {
            nodes[f] = GraphNode(id: f, label: f.isMarkdown ? f.noteName : (f as NSString).lastPathComponent,
                                 kind: f.isMarkdown ? .note : .attachment, group: tags[f]?.first?.lowercased())
        }
        for (src, targets) in outgoing where nodes[src] != nil {
            for t in targets where nodes[t] != nil && t != src { edges.insert(GraphEdge(from: src, to: t)) }
        }
        if s.showUnresolved {
            for (src, targets) in unresolved where nodes[src] != nil {
                for t in targets {
                    let id = "unresolved:" + t
                    if nodes[id] == nil { nodes[id] = GraphNode(id: id, label: (t as NSString).lastPathComponent, kind: .unresolved) }
                    edges.insert(GraphEdge(from: src, to: id))
                }
            }
        }
        if s.showTags {
            for (src, list) in tags where nodes[src] != nil {
                for tag in Set(list.map { $0.lowercased() }) {
                    let id = "#" + tag
                    if nodes[id] == nil { nodes[id] = GraphNode(id: id, label: id, kind: .tag) }
                    edges.insert(GraphEdge(from: src, to: id))
                }
            }
        }

        var keep = Set(nodes.keys)
        if let focus, nodes[focus] != nil {
            var adj: [String: [String]] = [:]
            for e in edges { adj[e.from, default: []].append(e.to); adj[e.to, default: []].append(e.from) }
            var seen: Set<String> = [focus]
            var frontier = [focus]
            for _ in 0..<max(1, s.depth) {
                frontier = frontier.flatMap { adj[$0] ?? [] }.filter { seen.insert($0).inserted }
            }
            keep = seen
        }
        let q = s.search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            keep = keep.filter { $0 == focus || nodes[$0]!.label.localizedCaseInsensitiveContains(q) || $0.localizedCaseInsensitiveContains(q) }
        }
        let kept = edges.filter { keep.contains($0.from) && keep.contains($0.to) }
        var degree: [String: Int] = [:]
        for e in kept { degree[e.from, default: 0] += 1; degree[e.to, default: 0] += 1 }
        if !s.showOrphans { keep = keep.filter { degree[$0, default: 0] > 0 || $0 == focus } }

        var out = GraphData()
        out.nodes = keep.sorted().map { var n = nodes[$0]!; n.degree = degree[$0, default: 0]; return n }
        out.edges = kept.sorted { ($0.from, $0.to) < ($1.from, $1.to) }
        return out
    }
}

public extension GraphData {
    @MainActor static func build(from index: VaultIndex, settings: GraphSettings, focus: String? = nil) -> GraphData {
        build(files: index.files, outgoing: index.outgoing, unresolved: index.unresolved,
              tags: index.notes.mapValues(\.parsed.tags), settings: settings, focus: focus)
    }
}
