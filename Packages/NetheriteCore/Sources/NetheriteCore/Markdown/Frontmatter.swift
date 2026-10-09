import Foundation
import Yams

public enum PropertyValue: Hashable, Sendable, Codable {
    case text(String)
    case number(Double)
    case bool(Bool)
    case date(Date)
    case list([String])
    case null

    public var strings: [String] {
        switch self {
        case .text(let s): [s]
        case .list(let l): l
        default: []
        }
    }

    public var displayString: String {
        switch self {
        case .text(let s): s
        case .number(let n): n.rounded() == n && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): b ? "true" : "false"
        case .date(let d): Frontmatter.dateString(d)
        case .list(let l): l.joined(separator: ", ")
        case .null: ""
        }
    }

    /// Value used for sorting/comparing in Bases.
    public var sortKey: String {
        switch self {
        case .number(let n): String(format: "%020.6f", n + 1e12)
        case .date(let d): Frontmatter.dateString(d, time: true)
        default: displayString.lowercased()
        }
    }

    public enum Kind: String, CaseIterable, Sendable { case text, number, checkbox, date, list }
    public var kind: Kind {
        switch self {
        case .number: .number
        case .bool: .checkbox
        case .date: .date
        case .list: .list
        default: .text
        }
    }
}

public struct Property: Hashable, Sendable, Identifiable {
    public var key: String
    public var value: PropertyValue
    public var id: String { key }
    public init(key: String, value: PropertyValue) { self.key = key; self.value = value }
}

public enum Frontmatter {
    /// Locates `---\n…\n---` at the very start of the text.
    public static func locate(in text: String) -> (range: NSRange, yaml: String)? {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return nil }
        let ns = text as NSString
        let re = try! NSRegularExpression(pattern: #"\A---\r?\n([\s\S]*?)(?:^|\n)(?:---|\.\.\.)[ \t]*(?:\r?\n|\z)"#, options: .anchorsMatchLines)
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (m.range, ns.substring(with: m.range(at: 1)))
    }

    public static func parse(_ yaml: String) -> [Property] {
        guard let node = try? Yams.compose(yaml: yaml), case .mapping(let map) = node else { return [] }
        return map.compactMap { k, v in
            guard let key = k.string else { return nil }
            return Property(key: key, value: value(of: v))
        }
    }

    static func value(of node: Node) -> PropertyValue {
        switch node {
        case .sequence(let seq): return .list(seq.compactMap { $0.string })
        case .mapping: return .text((try? Yams.serialize(node: node)) ?? "")
        case .scalar(let s):
            if s.style == .plain {
                if s.string.isEmpty || s.string == "~" || s.string == "null" { return .null }
                if let b = node.bool { return .bool(b) }
                if let i = node.int { return .number(Double(i)) }
                if let d = node.float { return .number(d) }
                if let date = parseDate(s.string) { return .date(date) }
            }
            return .text(s.string)
        default: return .null
        }
    }

    // MARK: Dates

    public static func parseDate(_ s: String) -> Date? {
        for f in [dayFormatter, timeFormatter, timeFormatterT] { if let d = f.date(from: s) { return d } }
        return nil
    }

    public static func dateString(_ d: Date, time: Bool = false) -> String {
        time && Calendar.current.dateComponents([.hour, .minute], from: d) != DateComponents(hour: 0, minute: 0)
            ? timeFormatterT.string(from: d) : dayFormatter.string(from: d)
    }

    static let dayFormatter = formatter("yyyy-MM-dd")
    static let timeFormatter = formatter("yyyy-MM-dd HH:mm")
    static let timeFormatterT = formatter("yyyy-MM-dd'T'HH:mm")
    static func formatter(_ f: String) -> DateFormatter {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.dateFormat = f
        return d
    }

    // MARK: Writing

    public static func serialize(_ props: [Property]) -> String {
        props.map { p in
            switch p.value {
            case .list(let l): l.isEmpty ? "\(p.key): []" : "\(p.key):\n" + l.map { "  - \(scalar($0))" }.joined(separator: "\n")
            case .text(let s): "\(p.key): \(scalar(s))"
            case .null: "\(p.key):"
            case .date(let d): "\(p.key): \(dateString(d, time: true))"
            default: "\(p.key): \(p.value.displayString)"
            }
        }.joined(separator: "\n")
    }

    /// Quotes a scalar only when YAML would otherwise change its meaning.
    static func scalar(_ s: String) -> String {
        let out = (try? Yams.dump(object: s, allowUnicode: true))?.trimmingCharacters(in: .newlines) ?? s
        return out.hasSuffix("\n...") ? String(out.dropLast(4)) : out
    }

    /// Returns `text` with its frontmatter replaced by `props` (removed when empty).
    public static func replacing(in text: String, with props: [Property]) -> String {
        let ns = text as NSString
        let body = locate(in: text).map { ns.substring(from: NSMaxRange($0.range)) } ?? text
        guard !props.isEmpty else { return body }
        return "---\n\(serialize(props))\n---\n" + body
    }
}
