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
            // YAML 1.2 core schema: `no`/`yes` stay text, `012` is decimal and `1:20` isn't sexagesimal.
            if s.style == .plain {
                let v = s.string
                if v.isEmpty || v == "~" || v.lowercased() == "null" { return .null }
                if ["true", "True", "TRUE"].contains(v) { return .bool(true) }
                if ["false", "False", "FALSE"].contains(v) { return .bool(false) }
                if v.range(of: #"^[-+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][-+]?[0-9]+)?$"#, options: .regularExpression) != nil,
                   let d = Double(v) { return .number(d) }
                if let date = parseDate(v) { return .date(date) }
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
    /// Keys whose value didn't change keep their original YAML (quoting, comments, nested values).
    public static func replacing(in text: String, with props: [Property]) -> String {
        let ns = text as NSString
        let fm = locate(in: text)
        let body = fm.map { ns.substring(from: NSMaxRange($0.range)) } ?? text
        guard !props.isEmpty else { return body }
        return "---\n\(fm.flatMap { merge(props, into: $0.yaml) } ?? serialize(props))\n---\n" + body
    }

    /// Rewrites only the top-level keys of `yaml` whose value differs from `props`; nil when the
    /// mapping can't be split into one line block per key.
    static func merge(_ props: [Property], into yaml: String) -> String? {
        guard let node = try? Yams.compose(yaml: yaml), case .mapping(let map) = node else { return nil }
        let lines = yaml.components(separatedBy: "\n")
        var keys: [(key: String, value: PropertyValue, line: Int)] = []
        for (k, v) in map {
            guard let key = k.string, let line = k.mark?.line, line - 1 > (keys.last?.line ?? -1) else { return nil }
            keys.append((key, value(of: v), line - 1))
        }
        guard let first = keys.first else { return nil }
        var out = Array(lines[..<first.line])
        for p in props {
            if let i = keys.firstIndex(where: { $0.key == p.key }), keys[i].value == p.value {
                out += lines[keys[i].line..<(i + 1 < keys.count ? keys[i + 1].line : lines.count)]
            } else {
                out.append(serialize([p]))
            }
        }
        return out.joined(separator: "\n").replacingOccurrences(of: #"\s+\z"#, with: "", options: .regularExpression)
    }
}
