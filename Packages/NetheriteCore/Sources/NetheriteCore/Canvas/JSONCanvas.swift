import Foundation
import CoreGraphics

/// Any JSON value, used to keep fields we don't understand when round-tripping `.canvas` files.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): if n.rounded() == n && abs(n) < 1e15 { try c.encode(Int(n)) } else { try c.encode(n) }
        case .bool(let b): try c.encode(b)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        case .null: try c.encodeNil()
        }
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Decodes known keys in order and collects the rest into `extra`.
private func decodeExtra(_ decoder: Decoder, known: [String]) throws -> [String: JSONValue] {
    let c = try decoder.container(keyedBy: AnyKey.self)
    var extra: [String: JSONValue] = [:]
    for k in c.allKeys where !known.contains(k.stringValue) { extra[k.stringValue] = try c.decode(JSONValue.self, forKey: k) }
    return extra
}

private func encodeNumber(_ v: Double, _ key: String, _ c: inout KeyedEncodingContainer<AnyKey>) throws {
    if v.rounded() == v { try c.encode(Int(v), forKey: AnyKey(key)) } else { try c.encode(v, forKey: AnyKey(key)) }
}

/// A node of a JSON Canvas (https://jsoncanvas.org). `type` is "text", "file", "link" or "group".
public struct CanvasNode: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var type: String
    public var x: Double, y: Double, width: Double, height: Double
    public var color: String?
    public var text: String?
    public var file: String?
    public var subpath: String?
    public var url: String?
    public var label: String?
    public var background: String?
    public var backgroundStyle: String?
    public var extra: [String: JSONValue] = [:]

    public init(id: String = CanvasNode.newID(), type: String, x: Double, y: Double, width: Double, height: Double,
                color: String? = nil, text: String? = nil, file: String? = nil, subpath: String? = nil, url: String? = nil, label: String? = nil) {
        self.id = id; self.type = type; self.x = x; self.y = y; self.width = width; self.height = height
        self.color = color; self.text = text; self.file = file; self.subpath = subpath; self.url = url; self.label = label
    }

    /// 16 hex chars, like Obsidian.
    public static func newID() -> String { String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16)) }

    static let known = ["id", "type", "x", "y", "width", "height", "color", "text", "file", "subpath", "url", "label", "background", "backgroundStyle"]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func s(_ k: String) throws -> String? { try c.decodeIfPresent(String.self, forKey: AnyKey(k)) }
        func d(_ k: String) throws -> Double { try c.decodeIfPresent(Double.self, forKey: AnyKey(k)) ?? 0 }
        id = try s("id") ?? CanvasNode.newID()
        type = try s("type") ?? "text"
        x = try d("x"); y = try d("y"); width = try d("width"); height = try d("height")
        color = try s("color"); text = try s("text"); file = try s("file"); subpath = try s("subpath")
        url = try s("url"); label = try s("label"); background = try s("background"); backgroundStyle = try s("backgroundStyle")
        extra = try decodeExtra(decoder, known: Self.known)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(id, forKey: AnyKey("id"))
        try c.encode(type, forKey: AnyKey("type"))
        for (k, v) in [("text", text), ("file", file), ("subpath", subpath), ("url", url), ("label", label),
                       ("background", background), ("backgroundStyle", backgroundStyle)] {
            try c.encodeIfPresent(v, forKey: AnyKey(k))
        }
        try encodeNumber(x, "x", &c); try encodeNumber(y, "y", &c)
        try encodeNumber(width, "width", &c); try encodeNumber(height, "height", &c)
        try c.encodeIfPresent(color, forKey: AnyKey("color"))
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) { try c.encode(v, forKey: AnyKey(k)) }
    }

    public var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

public struct CanvasEdge: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var fromNode: String
    public var fromSide: String?
    public var fromEnd: String?
    public var toNode: String
    public var toSide: String?
    public var toEnd: String?
    public var color: String?
    public var label: String?
    public var extra: [String: JSONValue] = [:]

    public init(id: String = CanvasNode.newID(), fromNode: String, fromSide: String?, toNode: String, toSide: String?) {
        self.id = id; self.fromNode = fromNode; self.fromSide = fromSide; self.toNode = toNode; self.toSide = toSide
    }

    static let known = ["id", "fromNode", "fromSide", "fromEnd", "toNode", "toSide", "toEnd", "color", "label"]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func s(_ k: String) throws -> String? { try c.decodeIfPresent(String.self, forKey: AnyKey(k)) }
        id = try s("id") ?? CanvasNode.newID()
        fromNode = try s("fromNode") ?? ""; toNode = try s("toNode") ?? ""
        fromSide = try s("fromSide"); fromEnd = try s("fromEnd"); toSide = try s("toSide"); toEnd = try s("toEnd")
        color = try s("color"); label = try s("label")
        extra = try decodeExtra(decoder, known: Self.known)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        for (k, v) in [("id", id as String?), ("fromNode", fromNode), ("fromSide", fromSide), ("fromEnd", fromEnd),
                       ("toNode", toNode), ("toSide", toSide), ("toEnd", toEnd), ("color", color), ("label", label)] {
            try c.encodeIfPresent(v, forKey: AnyKey(k))
        }
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) { try c.encode(v, forKey: AnyKey(k)) }
    }
}

public struct JSONCanvas: Codable, Hashable, Sendable {
    public var nodes: [CanvasNode] = []
    public var edges: [CanvasEdge] = []
    public var extra: [String: JSONValue] = [:]

    public init(nodes: [CanvasNode] = [], edges: [CanvasEdge] = []) { self.nodes = nodes; self.edges = edges }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        nodes = try c.decodeIfPresent([CanvasNode].self, forKey: AnyKey("nodes")) ?? []
        edges = try c.decodeIfPresent([CanvasEdge].self, forKey: AnyKey("edges")) ?? []
        extra = try decodeExtra(decoder, known: ["nodes", "edges"])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(nodes, forKey: AnyKey("nodes"))
        try c.encode(edges, forKey: AnyKey("edges"))
        for (k, v) in extra.sorted(by: { $0.key < $1.key }) { try c.encode(v, forKey: AnyKey(k)) }
    }

    /// Empty or invalid text decodes to an empty canvas (Obsidian treats a blank file the same way).
    public static func parse(_ text: String) throws -> JSONCanvas {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return JSONCanvas() }
        return try JSONDecoder().decode(JSONCanvas.self, from: Data(text.utf8))
    }

    /// Tab-indented JSON with `"key": value`, matching Obsidian's `JSON.stringify(data, null, "\t")`.
    /// Written by hand so key order is stable (JSONEncoder doesn't guarantee it).
    public func serialized() -> String {
        let nodeObjs = nodes.map { n -> [(String, JSONValue)] in
            var p: [(String, JSONValue)] = [("id", .string(n.id)), ("type", .string(n.type))]
            for (k, v) in [("text", n.text), ("file", n.file), ("subpath", n.subpath), ("url", n.url), ("label", n.label),
                           ("background", n.background), ("backgroundStyle", n.backgroundStyle)] { if let v { p.append((k, .string(v))) } }
            p += [("x", .number(n.x)), ("y", .number(n.y)), ("width", .number(n.width)), ("height", .number(n.height))]
            if let c = n.color { p.append(("color", .string(c))) }
            return p + n.extra.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        }
        let edgeObjs = edges.map { e -> [(String, JSONValue)] in
            var p: [(String, JSONValue)] = []
            for (k, v) in [("id", e.id as String?), ("fromNode", e.fromNode), ("fromSide", e.fromSide), ("fromEnd", e.fromEnd),
                           ("toNode", e.toNode), ("toSide", e.toSide), ("toEnd", e.toEnd), ("color", e.color), ("label", e.label)] {
                if let v { p.append((k, .string(v))) }
            }
            return p + e.extra.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        }
        var top: [String] = [
            "\t\"nodes\": " + JSONWriter.array(nodeObjs.map { JSONWriter.object($0, 2) }, 1),
            "\t\"edges\": " + JSONWriter.array(edgeObjs.map { JSONWriter.object($0, 2) }, 1),
        ]
        top += extra.sorted { $0.key < $1.key }.map { "\t" + JSONWriter.string($0.key) + ": " + JSONWriter.value($0.value, 1) }
        return "{\n" + top.joined(separator: ",\n") + "\n}"
    }

    public func node(_ id: String) -> CanvasNode? { nodes.first { $0.id == id } }

    /// Bounding box of all nodes (nil when empty).
    public var bounds: CGRect? {
        nodes.map(\.frame).reduce(nil) { acc, r in acc.map { $0.union(r) } ?? r }
    }

    /// Nodes whose frame lies fully inside `group`'s frame.
    public func children(ofGroup group: CanvasNode) -> [CanvasNode] {
        nodes.filter { $0.id != group.id && group.frame.contains($0.frame) }
    }
}

/// Minimal deterministic pretty JSON writer (tabs, `"key": value`).
enum JSONWriter {
    static func string(_ s: String) -> String {
        var o = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": o += "\\\""
            case "\\": o += "\\\\"
            case "\n": o += "\\n"
            case "\r": o += "\\r"
            case "\t": o += "\\t"
            case _ where u.value < 0x20: o += String(format: "\\u%04x", u.value)
            default: o.unicodeScalars.append(u)
            }
        }
        return o + "\""
    }

    static func number(_ n: Double) -> String {
        n.rounded() == n && abs(n) < 1e15 ? String(Int(n)) : String(n)
    }

    static func indent(_ level: Int) -> String { String(repeating: "\t", count: level) }

    static func array(_ items: [String], _ level: Int) -> String {
        items.isEmpty ? "[]" : "[\n" + items.map { indent(level + 1) + $0 }.joined(separator: ",\n") + "\n" + indent(level) + "]"
    }

    static func object(_ pairs: [(String, JSONValue)], _ level: Int) -> String {
        pairs.isEmpty ? "{}" : "{\n" + pairs.map { indent(level + 1) + string($0.0) + ": " + value($0.1, level + 1) }.joined(separator: ",\n") + "\n" + indent(level) + "}"
    }

    static func value(_ v: JSONValue, _ level: Int) -> String {
        switch v {
        case .string(let s): string(s)
        case .number(let n): number(n)
        case .bool(let b): b ? "true" : "false"
        case .null: "null"
        case .array(let a): array(a.map { value($0, level + 1) }, level)
        case .object(let o): object(o.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }, level)
        }
    }
}
