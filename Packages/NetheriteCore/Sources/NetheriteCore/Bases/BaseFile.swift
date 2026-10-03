import Foundation
import Yams

/// `filters:` tree — `and` / `or` / `not` lists of expression strings or nested trees.
public indirect enum BaseFilter: Hashable, Sendable {
    case expr(String)
    case and([BaseFilter])
    case or([BaseFilter])
    case not([BaseFilter])

    init?(_ node: Node) {
        if let s = node.string { self = .expr(s); return }
        guard case .mapping(let m) = node, let (k, v) = m.first, let key = k.string, let seq = v.sequence else { return nil }
        let kids = seq.compactMap(BaseFilter.init)
        switch key {
        case "and": self = .and(kids)
        case "or": self = .or(kids)
        case "not": self = .not(kids)
        default: return nil
        }
    }

    var node: Node {
        switch self {
        case .expr(let s): Node(s)
        case .and(let k): Node([(Node("and"), Node(k.map(\.node)))])
        case .or(let k): Node([(Node("or"), Node(k.map(\.node)))])
        case .not(let k): Node([(Node("not"), Node(k.map(\.node)))])
        }
    }

    public func matches(_ ctx: BaseEvalContext) -> Bool {
        switch self {
        case .expr(let s): BaseExpr.parse(s).map { ctx.eval($0).truthy } ?? false
        case .and(let k): k.allSatisfy { $0.matches(ctx) }
        case .or(let k): k.isEmpty || k.contains { $0.matches(ctx) }
        case .not(let k): !k.contains { $0.matches(ctx) }
        }
    }
}

public struct BaseSort: Hashable, Sendable {
    public var property: String
    public var ascending: Bool
    public init(property: String, ascending: Bool = true) { self.property = property; self.ascending = ascending }
}

public struct BaseViewConfig: Hashable, Sendable, Identifiable {
    public enum Kind: String, CaseIterable, Sendable { case table, cards, list, board }
    public var type: String
    public var name: String
    public var limit: Int?
    public var filters: BaseFilter?
    public var order: [String]
    public var sort: [BaseSort]
    public var groupBy: BaseSort?
    /// Board columns kept even while no entry has that value (`columns:`, a Netherite extension).
    public var columns: [String] = []
    /// Other keys (summaries, image, plugin settings…) kept verbatim.
    var extra: [String: String] = [:]
    public var id: String { name }
    public var kind: Kind { Kind(rawValue: type) ?? .table }

    public init(type: String = "table", name: String, order: [String] = ["file.name"]) {
        self.type = type; self.name = name; self.order = order; self.limit = nil; self.filters = nil; self.sort = []; self.groupBy = nil
    }
}

/// A parsed `.base` file. Serializes back keeping unknown keys, so edits don't lose data.
public struct BaseFile: Hashable, Sendable {
    public var filters: BaseFilter?
    /// Ordered name → expression.
    public var formulas: [(name: String, expr: String)] = []
    /// property id → display name
    public var displayNames: [String: String] = [:]
    public var views: [BaseViewConfig] = []
    /// Unknown top-level keys, serialized YAML fragments.
    var extra: [(String, String)] = []

    public init() {}

    public static func == (a: BaseFile, b: BaseFile) -> Bool { a.yaml == b.yaml }
    public func hash(into h: inout Hasher) { h.combine(yaml) }

    public static func parse(_ text: String) -> BaseFile {
        var f = BaseFile()
        guard let root = try? Yams.compose(yaml: text), case .mapping(let map) = root else { return f }
        for (k, v) in map {
            guard let key = k.string else { continue }
            switch key {
            case "filters": f.filters = BaseFilter(v)
            case "formulas":
                if case .mapping(let m) = v { f.formulas = m.compactMap { k, v in k.string.flatMap { n in v.string.map { (n, $0) } } } }
            case "properties":
                if case .mapping(let m) = v {
                    for (pk, pv) in m { if let id = pk.string, let dn = pv["displayName"]?.string { f.displayNames[id] = dn } }
                }
            case "views":
                f.views = (v.sequence ?? []).map(view)
            default:
                f.extra.append((key, (try? Yams.serialize(node: v)) ?? ""))
            }
        }
        return f
    }

    static func view(_ n: Node) -> BaseViewConfig {
        var v = BaseViewConfig(type: n["type"]?.string ?? "table", name: n["name"]?.string ?? "View", order: [])
        v.limit = n["limit"]?.int
        v.filters = n["filters"].flatMap(BaseFilter.init)
        v.order = n["order"]?.sequence?.compactMap(\.string) ?? []
        v.sort = (n["sort"]?.sequence ?? []).compactMap(sort)
        v.groupBy = n["groupBy"].flatMap(sort)
        v.columns = n["columns"]?.sequence?.compactMap(\.string) ?? []
        if case .mapping(let m) = n {
            for (k, val) in m {
                guard let key = k.string, !["type", "name", "limit", "filters", "order", "sort", "groupBy", "columns"].contains(key) else { continue }
                v.extra[key] = try? Yams.serialize(node: val)
            }
        }
        return v
    }

    static func sort(_ n: Node) -> BaseSort? {
        if let s = n.string { return BaseSort(property: s) }
        guard let p = n["property"]?.string else { return nil }
        return BaseSort(property: p, ascending: (n["direction"]?.string ?? "ASC").uppercased() != "DESC")
    }

    static func sortNode(_ s: BaseSort) -> Node {
        Node([(Node("property"), Node(s.property)), (Node("direction"), Node(s.ascending ? "ASC" : "DESC"))])
    }

    public var yaml: String {
        var pairs: [(Node, Node)] = []
        if let filters { pairs.append((Node("filters"), filters.node)) }
        if !formulas.isEmpty { pairs.append((Node("formulas"), Node(formulas.map { (Node($0.name), Node($0.expr)) }))) }
        if !displayNames.isEmpty {
            pairs.append((Node("properties"), Node(displayNames.sorted { $0.key < $1.key }.map {
                (Node($0.key), Node([(Node("displayName"), Node($0.value))]))
            })))
        }
        for (k, frag) in extra { if let n = try? Yams.compose(yaml: frag) { pairs.append((Node(k), n)) } }
        pairs.append((Node("views"), Node(views.map { v in
            var p: [(Node, Node)] = [(Node("type"), Node(v.type)), (Node("name"), Node(v.name))]
            if let l = v.limit { p.append((Node("limit"), Node(String(l), .implicit))) }
            if let g = v.groupBy { p.append((Node("groupBy"), Self.sortNode(g))) }
            if let f = v.filters { p.append((Node("filters"), f.node)) }
            if !v.order.isEmpty { p.append((Node("order"), Node(v.order.map { Node($0) }))) }
            if !v.sort.isEmpty { p.append((Node("sort"), Node(v.sort.map(Self.sortNode)))) }
            if !v.columns.isEmpty { p.append((Node("columns"), Node(v.columns.map { Node($0) }))) }
            for (k, frag) in v.extra.sorted(by: { $0.key < $1.key }) { if let n = try? Yams.compose(yaml: frag) { p.append((Node(k), n)) } }
            return Node(p)
        })))
        return (try? Yams.serialize(node: Node(pairs))) ?? ""
    }

    // MARK: Querying

    public var formulaExprs: [String: BaseExpr] {
        Dictionary(formulas.compactMap { f in BaseExpr.parse(f.expr).map { (f.name, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    /// Rows matching the global + view filters, sorted and limited.
    public func run(_ view: BaseViewConfig, rows: [BaseRow], now: Date = .now) -> [BaseRow] {
        let formulas = formulaExprs
        func ctx(_ r: BaseRow) -> BaseEvalContext { BaseEvalContext(row: r, formulas: formulas, now: now) }
        var out = rows.filter { r in
            let c = ctx(r)
            return (filters?.matches(c) ?? true) && (view.filters?.matches(c) ?? true)
        }
        let sorts = (view.groupBy.map { [$0] } ?? []) + view.sort
        if !sorts.isEmpty {
            let keyed = out.map { r in (r, sorts.map { value(of: $0.property, in: ctx(r)) }) }
            out = keyed.sorted { a, b in
                for (i, s) in sorts.enumerated() {
                    let c = BaseValue.compare(a.1[i], b.1[i])
                    if c != .orderedSame { return s.ascending ? c == .orderedAscending : c == .orderedDescending }
                }
                return a.0.path.localizedStandardCompare(b.0.path) == .orderedAscending
            }.map(\.0)
        } else {
            out.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }
        if let l = view.limit, l > 0 { out = Array(out.prefix(l)) }
        return out
    }

    /// Value of a column id (`file.name`, `note.status`, `status`, `formula.x`) for a row.
    public func value(of property: String, in ctx: BaseEvalContext) -> BaseValue {
        ctx.eval(.ident(property.split(separator: ".").map(String.init)))
    }

    public func value(of property: String, row: BaseRow) -> BaseValue {
        value(of: property, in: BaseEvalContext(row: row, formulas: formulaExprs))
    }

    public func displayName(_ property: String) -> String {
        if let d = displayNames[property] { return d }
        if property == "file.name" { return "Name" }
        let parts = property.split(separator: ".")
        return parts.count > 1 && ["note", "formula"].contains(parts[0]) ? parts.dropFirst().joined(separator: ".") : property
    }
}

public extension BaseRow {
    /// Rows for every file in the index (notes carry properties/tags/links).
    @MainActor static func all(from index: VaultIndex) -> [BaseRow] {
        index.files.map { path in
            let rec = index.notes[path]
            let values = rec == nil ? try? index.vault.url(for: path).resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey]) : nil
            return BaseRow(path: path, properties: rec?.parsed.properties ?? [], tags: rec?.parsed.tags ?? [],
                           links: index.outgoing[path] ?? [], size: rec?.text.utf8.count ?? values?.fileSize ?? 0,
                           ctime: rec?.created ?? values?.creationDate ?? .distantPast,
                           mtime: rec?.modified ?? values?.contentModificationDate ?? .distantPast)
        }
    }
}
