import Foundation

/// A runtime value in a Bases expression.
public enum BaseValue: Hashable, Sendable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case date(Date)
    case list([BaseValue])

    public init(_ p: PropertyValue) {
        switch p {
        case .text(let s): self = .string(s)
        case .number(let n): self = .number(n)
        case .bool(let b): self = .bool(b)
        case .date(let d): self = .date(d)
        case .list(let l): self = .list(l.map { .string($0) })
        case .null: self = .null
        }
    }

    public var truthy: Bool {
        switch self {
        case .null: false
        case .bool(let b): b
        case .number(let n): n != 0
        case .string(let s): !s.isEmpty
        case .date: true
        case .list(let l): !l.isEmpty
        }
    }

    public var number: Double? {
        switch self {
        case .number(let n): n
        case .bool(let b): b ? 1 : 0
        case .string(let s): Double(s.trimmingCharacters(in: .whitespaces))
        case .date(let d): d.timeIntervalSince1970 * 1000
        default: nil
        }
    }

    public var description: String {
        switch self {
        case .null: ""
        case .bool(let b): b ? "true" : "false"
        case .number(let n): n.rounded() == n && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .string(let s): s
        case .date(let d): Frontmatter.dateString(d, time: true)
        case .list(let l): l.map(\.description).joined(separator: ", ")
        }
    }

    public var isEmpty: Bool {
        switch self {
        case .null: true
        case .string(let s): s.isEmpty
        case .list(let l): l.isEmpty
        default: false
        }
    }

    /// Ordering used by sorting and `<`/`>`: numbers and dates numerically, everything else as text.
    public static func compare(_ a: BaseValue, _ b: BaseValue) -> ComparisonResult {
        switch (a, b) {
        case (.null, .null): return .orderedSame
        case (.null, _): return .orderedAscending
        case (_, .null): return .orderedDescending
        default: break
        }
        if case .string = a, case .string = b {} else if let x = a.number, let y = b.number {
            return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        }
        return a.description.localizedStandardCompare(b.description)
    }

    static func equal(_ a: BaseValue, _ b: BaseValue) -> Bool {
        switch (a, b) {
        case (.string(let x), .string(let y)): return x.caseInsensitiveCompare(y) == .orderedSame
        case (.list(let l), .string): return l.contains { equal($0, b) }
        default: return compare(a, b) == .orderedSame && (a == .null) == (b == .null)
        }
    }
}

/// What an expression can read: one file of the vault.
public struct BaseRow: Sendable, Identifiable {
    public var path: String
    public var properties: [Property]
    public var tags: [String]
    /// Resolved link targets (vault paths).
    public var links: [String]
    public var size: Int
    public var ctime: Date
    public var mtime: Date
    public var id: String { path }

    public init(path: String, properties: [Property] = [], tags: [String] = [], links: [String] = [], size: Int = 0, ctime: Date = .now, mtime: Date = .now) {
        self.path = path; self.properties = properties; self.tags = tags; self.links = links
        self.size = size; self.ctime = ctime; self.mtime = mtime
    }

    public func file(_ key: String) -> BaseValue {
        switch key {
        case "name": .string(path.isMarkdown ? path.noteName : (path as NSString).lastPathComponent)
        case "basename": .string(path.noteName)
        case "path": .string(path)
        case "folder": .string(path.parentFolder)
        case "ext": .string(path.fileExtension)
        case "size": .number(Double(size))
        case "ctime": .date(ctime)
        case "mtime": .date(mtime)
        case "tags": .list(tags.map { .string("#" + $0) })
        case "links": .list(links.map { .string($0) })
        case "properties": .list(properties.map { .string($0.key) })
        default: .null
        }
    }

    public func note(_ key: String) -> BaseValue {
        properties.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }.map { BaseValue($0.value) } ?? .null
    }
}

/// Parsed Bases expression (`status != "done" && file.hasTag("book")`).
public indirect enum BaseExpr: Sendable, Hashable {
    case literal(BaseValue)
    case ident([String])                       // dotted path: file.name, note.x, formula.y, status
    case unary(String, BaseExpr)
    case binary(String, BaseExpr, BaseExpr)
    case call(String, [BaseExpr])              // global function
    case method(BaseExpr, String, [BaseExpr])  // receiver.fn(args)
    case member(BaseExpr, String)              // receiver.prop (e.g. .length)

    public static func parse(_ s: String) -> BaseExpr? {
        var p = ExprParser(tokens: ExprParser.lex(s))
        guard let e = p.expr(0), p.pos == p.tokens.count else { return nil }
        return e
    }
}

public struct BaseEvalContext {
    public var row: BaseRow
    public var formulas: [String: BaseExpr]
    public var now: Date
    var depth = 0

    public init(row: BaseRow, formulas: [String: BaseExpr] = [:], now: Date = .now) {
        self.row = row; self.formulas = formulas; self.now = now
    }

    public func eval(_ e: BaseExpr) -> BaseValue {
        switch e {
        case .literal(let v): return v
        case .ident(let parts): return lookup(parts)
        case .unary(let op, let x):
            let v = eval(x)
            return op == "!" ? .bool(!v.truthy) : (v.number.map { .number(-$0) } ?? .null)
        case .binary(let op, let a, let b): return binary(op, a, b)
        case .call(let name, let args): return call(name, args.map(eval))
        case .member(let r, let name): return method(eval(r), name, [])
        case .method(let r, let name, let args):
            if case .ident(let parts) = r, parts == ["file"] { return fileFunction(name, args.map(eval)) }
            return method(eval(r), name, args.map(eval))
        }
    }

    func lookup(_ parts: [String]) -> BaseValue {
        guard let head = parts.first else { return .null }
        var base: BaseValue
        var rest = parts.dropFirst()
        switch head {
        case "file" where parts.count > 1: base = row.file(parts[1]); rest = rest.dropFirst()
        case "note" where parts.count > 1: base = row.note(parts[1]); rest = rest.dropFirst()
        case "formula" where parts.count > 1:
            guard depth < 8, let f = formulas[parts[1]] else { return .null }
            var sub = self; sub.depth += 1
            base = sub.eval(f); rest = rest.dropFirst()
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null": return .null
        default: base = row.note(head)
        }
        for name in rest { base = method(base, name, []) }
        return base
    }

    func binary(_ op: String, _ a: BaseExpr, _ b: BaseExpr) -> BaseValue {
        if op == "&&" { let l = eval(a); return l.truthy ? .bool(eval(b).truthy) : .bool(false) }
        if op == "||" { let l = eval(a); return l.truthy ? .bool(true) : .bool(eval(b).truthy) }
        let l = eval(a), r = eval(b)
        switch op {
        case "==": return .bool(BaseValue.equal(l, r))
        case "!=": return .bool(!BaseValue.equal(l, r))
        case ">": return .bool(l != .null && r != .null && BaseValue.compare(l, r) == .orderedDescending)
        case "<": return .bool(l != .null && r != .null && BaseValue.compare(l, r) == .orderedAscending)
        case ">=": return .bool(l != .null && r != .null && BaseValue.compare(l, r) != .orderedAscending)
        case "<=": return .bool(l != .null && r != .null && BaseValue.compare(l, r) != .orderedDescending)
        case "+":
            if case .date(let d) = l, case .string(let s) = r { return Self.shift(d, s, 1).map { .date($0) } ?? .null }
            if let x = l.number, let y = r.number, !(isText(l) || isText(r)) { return .number(x + y) }
            return .string(l.description + r.description)
        case "-":
            if case .date(let d) = l, case .string(let s) = r { return Self.shift(d, s, -1).map { .date($0) } ?? .null }
            return l.number.flatMap { x in r.number.map { .number(x - $0) } } ?? .null
        case "*": return l.number.flatMap { x in r.number.map { .number(x * $0) } } ?? .null
        case "/": return l.number.flatMap { x in r.number.flatMap { $0 == 0 ? nil : .number(x / $0) } } ?? .null
        case "%": return l.number.flatMap { x in r.number.flatMap { $0 == 0 ? nil : .number(x.truncatingRemainder(dividingBy: $0)) } } ?? .null
        default: return .null
        }
    }

    private func isText(_ v: BaseValue) -> Bool { if case .string = v { true } else { false } }

    /// `date + "1M"` / `now() - "2 weeks"`.
    static func shift(_ d: Date, _ s: String, _ sign: Int) -> Date? {
        guard let m = s.trimmingCharacters(in: .whitespaces).wholeMatch(of: /(\d+)\s*([a-zA-Z]+)/), let n = Int(m.1) else { return nil }
        let unit: Calendar.Component
        switch String(m.2) {
        case "y", "year", "years": unit = .year
        case "M", "month", "months": unit = .month
        case "w", "week", "weeks": unit = .weekOfYear
        case "d", "day", "days": unit = .day
        case "h", "hour", "hours": unit = .hour
        case "m", "minute", "minutes": unit = .minute
        case "s", "second", "seconds": unit = .second
        default: return nil
        }
        return Calendar.current.date(byAdding: unit, value: n * sign, to: d)
    }

    func fileFunction(_ name: String, _ args: [BaseValue]) -> BaseValue {
        let strs = args.flatMap { v -> [String] in if case .list(let l) = v { l.map(\.description) } else { [v.description] } }
        switch name {
        case "hasTag":
            return .bool(strs.contains { t in
                let t = t.hasPrefix("#") ? String(t.dropFirst()) : t
                return row.tags.contains { $0.caseInsensitiveCompare(t) == .orderedSame || $0.lowercased().hasPrefix(t.lowercased() + "/") }
            })
        case "inFolder":
            return .bool(strs.contains { f in
                let f = f.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return f.isEmpty || row.path.parentFolder == f || row.path.hasPrefix(f + "/")
            })
        case "hasLink":
            return .bool(strs.contains { l in
                let l = l.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                return row.links.contains { $0.caseInsensitiveCompare(l) == .orderedSame || $0.noteName.caseInsensitiveCompare(l.noteName) == .orderedSame }
            })
        case "hasProperty": return .bool(strs.contains { k in row.properties.contains { $0.key.caseInsensitiveCompare(k) == .orderedSame } })
        default: return method(.string(row.path), name, args)
        }
    }

    func call(_ name: String, _ args: [BaseValue]) -> BaseValue {
        switch name {
        case "if": return (args.first?.truthy ?? false) ? (args.count > 1 ? args[1] : .null) : (args.count > 2 ? args[2] : .null)
        case "now": return .date(now)
        case "today": return .date(Calendar.current.startOfDay(for: now))
        case "date": return args.first.flatMap { v in if case .date = v { v } else { Frontmatter.parseDate(v.description).map { .date($0) } } } ?? .null
        case "number": return args.first?.number.map { .number($0) } ?? .null
        case "list": return .list(args.flatMap { if case .list(let l) = $0 { l } else { [$0] } })
        case "min": return args.compactMap(\.number).min().map { .number($0) } ?? .null
        case "max": return args.compactMap(\.number).max().map { .number($0) } ?? .null
        case "link", "file": return args.first ?? .null
        default:
            // Allow `contains(x, y)`-style globals by treating the first argument as the receiver.
            guard let first = args.first else { return .null }
            return method(first, name, Array(args.dropFirst()))
        }
    }

    func method(_ v: BaseValue, _ name: String, _ args: [BaseValue]) -> BaseValue {
        let a0 = args.first
        switch name {
        case "length":
            if case .list(let l) = v { return .number(Double(l.count)) }
            return v == .null ? .null : .number(Double(v.description.count))
        case "isEmpty": return .bool(v.isEmpty)
        case "isTruthy": return .bool(v.truthy)
        case "contains":
            guard let a0 else { return .null }
            if case .list(let l) = v { return .bool(l.contains { BaseValue.equal($0, a0) }) }
            return .bool(v.description.localizedCaseInsensitiveContains(a0.description))
        case "containsAny", "containsAll":
            let items = args.flatMap { if case .list(let l) = $0 { l } else { [$0] } }
            let test: (BaseValue) -> Bool = { x in method(v, "contains", [x]).truthy }
            return .bool(name == "containsAny" ? items.contains(where: test) : items.allSatisfy(test))
        case "startsWith": return .bool(a0.map { v.description.lowercased().hasPrefix($0.description.lowercased()) } ?? false)
        case "endsWith": return .bool(a0.map { v.description.lowercased().hasSuffix($0.description.lowercased()) } ?? false)
        case "lower": return v == .null ? .null : .string(v.description.lowercased())
        case "upper": return v == .null ? .null : .string(v.description.uppercased())
        case "title": return v == .null ? .null : .string(v.description.capitalized)
        case "trim": return .string(v.description.trimmingCharacters(in: .whitespacesAndNewlines))
        case "toString": return .string(v.description)
        case "toFixed": return v.number.map { .string(String(format: "%.\(Int(a0?.number ?? 0))f", $0)) } ?? .null
        case "round":
            let p = pow(10, a0?.number ?? 0)
            return v.number.map { .number(($0 * p).rounded() / p) } ?? .null
        case "floor": return v.number.map { .number($0.rounded(.down)) } ?? .null
        case "ceil": return v.number.map { .number($0.rounded(.up)) } ?? .null
        case "abs": return v.number.map { .number(abs($0)) } ?? .null
        case "join": if case .list(let l) = v { return .string(l.map(\.description).joined(separator: a0?.description ?? ", ")) }; return v
        case "year", "month", "day", "hour", "minute":
            guard case .date(let d) = v else { return .null }
            let c: Calendar.Component = ["year": .year, "month": .month, "day": .day, "hour": .hour, "minute": .minute][name]!
            return .number(Double(Calendar.current.component(c, from: d)))
        case "format":
            guard case .date(let d) = v else { return v }
            return .string(Templates.format(d, a0?.description ?? "yyyy-MM-dd"))
        case "date": if case .date(let d) = v { return .date(Calendar.current.startOfDay(for: d)) }; return .null
        default: return .null
        }
    }
}

/// Tokenizer + precedence-climbing parser.
struct ExprParser {
    enum Tok: Equatable { case num(Double), str(String), ident(String), op(String) }
    var tokens: [Tok]
    var pos = 0

    static func lex(_ s: String) -> [Tok] {
        var out: [Tok] = []
        let c = Array(s)
        var i = 0
        while i < c.count {
            let ch = c[i]
            if ch.isWhitespace { i += 1; continue }
            if ch == "\"" || ch == "'" {
                var j = i + 1, str = ""
                while j < c.count, c[j] != ch { if c[j] == "\\", j + 1 < c.count { j += 1 }; str.append(c[j]); j += 1 }
                out.append(.str(str)); i = j + 1; continue
            }
            if ch.isNumber {
                var j = i
                while j < c.count, c[j].isNumber || c[j] == "." { j += 1 }
                out.append(.num(Double(String(c[i..<j])) ?? 0)); i = j; continue
            }
            if ch.isLetter || ch == "_" {
                var j = i
                while j < c.count, c[j].isLetter || c[j].isNumber || c[j] == "_" || c[j] == "-" && j + 1 < c.count && c[j + 1].isLetter { j += 1 }
                out.append(.ident(String(c[i..<j]))); i = j; continue
            }
            let two = i + 1 < c.count ? String(c[i...i + 1]) : ""
            if ["==", "!=", ">=", "<=", "&&", "||"].contains(two) { out.append(.op(two)); i += 2; continue }
            out.append(.op(String(ch))); i += 1
        }
        return out
    }

    static let precedence: [String: Int] = ["||": 1, "&&": 2, "==": 3, "!=": 3, ">": 4, "<": 4, ">=": 4, "<=": 4, "+": 5, "-": 5, "*": 6, "/": 6, "%": 6]

    mutating func expr(_ minPrec: Int) -> BaseExpr? {
        guard var lhs = unary() else { return nil }
        while pos < tokens.count, case .op(let op) = tokens[pos], let p = Self.precedence[op], p > minPrec {
            pos += 1
            guard let rhs = expr(p) else { return nil }
            lhs = .binary(op, lhs, rhs)
        }
        return lhs
    }

    mutating func unary() -> BaseExpr? {
        if pos < tokens.count, case .op(let op) = tokens[pos], op == "!" || op == "-" {
            pos += 1
            return unary().map { .unary(op, $0) }
        }
        return postfix()
    }

    mutating func postfix() -> BaseExpr? {
        guard var e = primary() else { return nil }
        while pos < tokens.count, tokens[pos] == .op(".") {
            pos += 1
            guard pos < tokens.count, case .ident(let name) = tokens[pos] else { return nil }
            pos += 1
            if pos < tokens.count, tokens[pos] == .op("(") {
                guard let args = arguments() else { return nil }
                e = .method(e, name, args)
            } else if case .ident(let parts) = e {
                e = .ident(parts + [name])
            } else {
                e = .member(e, name)
            }
        }
        return e
    }

    mutating func arguments() -> [BaseExpr]? {
        pos += 1 // (
        var args: [BaseExpr] = []
        if pos < tokens.count, tokens[pos] == .op(")") { pos += 1; return args }
        while true {
            guard let a = expr(0) else { return nil }
            args.append(a)
            guard pos < tokens.count else { return nil }
            if tokens[pos] == .op(",") { pos += 1; continue }
            if tokens[pos] == .op(")") { pos += 1; return args }
            return nil
        }
    }

    mutating func primary() -> BaseExpr? {
        guard pos < tokens.count else { return nil }
        let t = tokens[pos]
        pos += 1
        switch t {
        case .num(let n): return .literal(.number(n))
        case .str(let s): return .literal(.string(s))
        case .ident(let name):
            if pos < tokens.count, tokens[pos] == .op("(") { return arguments().map { .call(name, $0) } }
            return .ident([name])
        case .op("("):
            guard let e = expr(0), pos < tokens.count, tokens[pos] == .op(")") else { return nil }
            pos += 1
            return e
        case .op("["):
            var items: [BaseExpr] = []
            while pos < tokens.count, tokens[pos] != .op("]") {
                guard let e = expr(0) else { return nil }
                items.append(e)
                if pos < tokens.count, tokens[pos] == .op(",") { pos += 1 }
            }
            pos += 1
            return .call("list", items)
        default: return nil
        }
    }
}
