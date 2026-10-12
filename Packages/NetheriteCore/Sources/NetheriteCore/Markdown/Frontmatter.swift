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
            let key = scalar(p.key)
            return switch p.value {
            case .list(let l): l.isEmpty ? "\(key): []" : "\(key):\n" + l.map { "  - \(scalar($0))" }.joined(separator: "\n")
            case .text(let s): "\(key): \(scalar(s))"
            case .null: "\(key):"
            case .date(let d): "\(key): \(dateString(d, time: true))"
            default: "\(key): \(p.value.displayString)"
            }
        }.joined(separator: "\n")
    }

    /// Quotes a scalar only when YAML would otherwise change its meaning.
    static func scalar(_ s: String) -> String {
        let out = (try? Yams.dump(object: s, width: -1, allowUnicode: true))?.trimmingCharacters(in: .newlines) ?? s
        return out.hasSuffix("\n...") ? String(out.dropLast(4)) : out
    }

    public struct InvalidYAML: LocalizedError, Sendable {
        public var errorDescription: String? {
            String(localized: "The note's properties aren't valid YAML. Fix them in the editor first.", bundle: .module)
        }
    }

    /// Returns `text` with its frontmatter replaced by `props` (removed when empty).
    /// Keys whose value didn't change keep their original YAML (quoting, comments, nested values).
    /// Throws `InvalidYAML` instead of overwriting a block that isn't a YAML mapping, since its keys couldn't be read.
    /// `verbatim` holds YAML blocks to write as is for keys new to the frontmatter.
    public static func replacing(in text: String, with props: [Property], verbatim: [String: String] = [:]) throws -> String {
        let ns = text as NSString
        let fm = locate(in: text)
        if let fm {
            switch Result(catching: { try Yams.compose(yaml: fm.yaml) }) {
            case .success(nil), .success(.mapping?): break
            default: throw InvalidYAML()
            }
        }
        let body = fm.map { ns.substring(from: NSMaxRange($0.range)) } ?? text
        guard !props.isEmpty else { return body }
        let yaml = fm.flatMap { merge(props, into: $0.yaml, verbatim: verbatim) }
            ?? props.map { verbatim[$0.key] ?? serialize([$0]) }.joined(separator: "\n")
        return "---\n\(yaml)\n---\n" + body
    }

    /// `target` with the properties of `source` added to its frontmatter: tags, aliases and lists are joined
    /// without duplicates, other keys keep the target's value, and keys new to the target keep their original YAML.
    public static func merging(_ source: String, into target: String) throws -> String {
        let props = { (text: String) in locate(in: text).map { parse($0.yaml) } ?? [] }
        let original = props(target)
        var merged = original
        var verbatim: [String: String] = [:]
        let sourceBlocks = locate(in: source).flatMap { blocks($0.yaml)?.keys } ?? []
        for p in props(source) {
            guard let i = merged.firstIndex(where: { $0.key.caseInsensitiveCompare(p.key) == .orderedSame }) else {
                merged.append(p)
                // A block indented as a whole (`  a: 1`) wouldn't sit at the target's top level.
                if let b = sourceBlocks.first(where: { $0.key == p.key }), b.lines.first?.first?.isWhitespace == false {
                    verbatim[p.key] = b.lines.joined(separator: "\n").replacingOccurrences(of: #"\s+\z"#, with: "", options: .regularExpression)
                }
                continue
            }
            // `tags: foo` is a one-item list to the parser, so a scalar on either side still joins.
            var joins = ["tags", "tag", "aliases", "alias"].contains(p.key.lowercased())
            if case .list = p.value { joins = true }
            if case .list = merged[i].value { joins = true }
            let a = merged[i].value.strings
            let new = p.value.strings.filter { !a.contains($0) }
            if joins, !new.isEmpty { merged[i].value = .list(a + new) }
        }
        return merged == original ? target : try replacing(in: target, with: merged, verbatim: verbatim)
    }

    /// Splits a YAML mapping into the lines before its first key and one line block per top-level key;
    /// nil when it isn't a mapping or two keys share a line.
    static func blocks(_ yaml: String) -> (head: [String], keys: [(key: String, value: PropertyValue, lines: [String])])? {
        guard let node = try? Yams.compose(yaml: yaml), case .mapping(let map) = node else { return nil }
        let lines = yaml.components(separatedBy: "\n")
        var starts: [(key: String, value: PropertyValue, line: Int)] = []
        for (k, v) in map {
            guard let key = k.string, let line = k.mark?.line, line - 1 > (starts.last?.line ?? -1) else { return nil }
            starts.append((key, value(of: v), line - 1))
        }
        guard let first = starts.first else { return nil }
        return (Array(lines[..<first.line]), starts.indices.map { i in
            (starts[i].key, starts[i].value, Array(lines[starts[i].line..<(i + 1 < starts.count ? starts[i + 1].line : lines.count)]))
        })
    }

    /// Rewrites only the top-level keys of `yaml` whose value differs from `props`; nil when the
    /// mapping can't be split into one line block per key.
    static func merge(_ props: [Property], into yaml: String, verbatim: [String: String] = [:]) -> String? {
        guard let (head, keys) = blocks(yaml) else { return nil }
        var out = head
        for p in props {
            if let b = keys.first(where: { $0.key == p.key }), b.value == p.value {
                out += b.lines
            } else {
                out.append(verbatim[p.key] ?? serialize([p]))
            }
        }
        return out.joined(separator: "\n").replacingOccurrences(of: #"\s+\z"#, with: "", options: .regularExpression)
    }
}
