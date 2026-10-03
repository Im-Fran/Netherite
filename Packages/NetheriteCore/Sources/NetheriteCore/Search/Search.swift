import Foundation

/// Obsidian-style search: space-separated terms are ANDed; supports "exact phrases", `-exclude`,
/// `OR`, `/regex/`, and the operators `tag:`, `path:`, `file:`, `line:`, `section:`, `task:`, `[property:value]`.
public struct SearchQuery: Sendable {
    public enum Term: Sendable {
        case text(String)
        case regex(NSRegularExpression)
        case tag(String)
        case path(String)
        case file(String)
        case line(String)
        case task(String)
        case property(key: String, value: String?)
        indirect case not(Term)
        indirect case or(Term, Term)
    }

    public var terms: [Term]
    public var caseSensitive = false
    public var isEmpty: Bool { terms.isEmpty }

    public init(_ raw: String, caseSensitive: Bool = false) {
        self.caseSensitive = caseSensitive
        var out: [Term] = []
        var pendingOr = false
        // iOS keyboards type smart quotes; treat them as the straight quotes the syntax uses.
        let straight = String(raw.map { "“”„«»".contains($0) ? "\"" : $0 })
        for tok in Self.tokenize(straight) {
            if tok == "OR" { pendingOr = true; continue }
            guard let term = Self.term(tok) else { continue }
            if pendingOr, let last = out.popLast() { out.append(.or(last, term)) } else { out.append(term) }
            pendingOr = false
        }
        terms = out
    }

    static func tokenize(_ s: String) -> [String] {
        var toks: [String] = [], cur = "", quote: Character?, depth = 0
        for c in s {
            if let q = quote { cur.append(c); if c == q { quote = nil }; continue }
            switch c {
            case "\"", "/" where cur.isEmpty || cur == "-" || cur.hasSuffix(":"): quote = c; cur.append(c)
            case "[": depth += 1; cur.append(c)
            case "]": depth -= 1; cur.append(c)
            case " " where depth == 0: if !cur.isEmpty { toks.append(cur); cur = "" }
            default: cur.append(c)
            }
        }
        if !cur.isEmpty { toks.append(cur) }
        return toks
    }

    static func unquote(_ s: String) -> String {
        s.count >= 2 && s.hasPrefix("\"") && s.hasSuffix("\"") ? String(s.dropFirst().dropLast()) : s
    }

    static func term(_ tok: String) -> Term? {
        if tok.hasPrefix("-"), tok.count > 1 { return term(String(tok.dropFirst())).map { .not($0) } }
        if tok.hasPrefix("["), tok.hasSuffix("]") {
            let inner = tok.dropFirst().dropLast()
            let parts = inner.split(separator: ":", maxSplits: 1).map { unquote(String($0).trimmingCharacters(in: .whitespaces)) }
            return parts.first.map { .property(key: $0, value: parts.count > 1 ? parts[1] : nil) }
        }
        if tok.count > 2, tok.hasPrefix("/"), tok.hasSuffix("/") {
            return (try? NSRegularExpression(pattern: String(tok.dropFirst().dropLast()), options: .caseInsensitive)).map { .regex($0) }
        }
        if let colon = tok.firstIndex(of: ":") {
            let op = tok[..<colon].lowercased(), val = unquote(String(tok[tok.index(after: colon)...]))
            switch op {
            case "tag": return .tag(val.hasPrefix("#") ? String(val.dropFirst()) : val)
            case "path": return .path(val)
            case "file": return .file(val)
            case "line", "section", "block", "content": return .line(val)
            case "task", "task-todo", "task-done": return .task(val)
            default: break
            }
        }
        if tok.hasPrefix("#"), tok.count > 1 { return .tag(String(tok.dropFirst())) }
        let t = unquote(tok)
        return t.isEmpty ? nil : .text(t)
    }
}

public struct SearchHit: Identifiable, Sendable {
    public struct Match: Sendable, Hashable { public var line: Int; public var text: String; public var range: NSRange }
    public var path: String
    public var matches: [Match]
    public var id: String { path }
}

public enum Search {
    public static func run(_ query: SearchQuery, in notes: [String: NoteRecord], limit: Int = 500) -> [SearchHit] {
        guard !query.isEmpty else { return [] }
        let opts: String.CompareOptions = query.caseSensitive ? [] : [.caseInsensitive, .diacriticInsensitive]
        var hits: [SearchHit] = []
        for (path, rec) in notes.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
            guard query.terms.allSatisfy({ matches($0, rec, opts) }) else { continue }
            hits.append(SearchHit(path: path, matches: lineMatches(query, rec.text, opts)))
            if hits.count >= limit { break }
        }
        return hits
    }

    static func matches(_ term: SearchQuery.Term, _ rec: NoteRecord, _ opts: String.CompareOptions) -> Bool {
        switch term {
        case .text(let s): rec.text.range(of: s, options: opts) != nil || rec.path.noteName.range(of: s, options: opts) != nil
        case .regex(let re): re.firstMatch(in: rec.text, range: NSRange(location: 0, length: (rec.text as NSString).length)) != nil
        case .tag(let t): rec.parsed.tags.contains { $0.caseInsensitiveCompare(t) == .orderedSame || $0.lowercased().hasPrefix(t.lowercased() + "/") }
        case .path(let p): rec.path.range(of: p, options: opts) != nil
        case .file(let f): rec.path.noteName.range(of: f, options: opts) != nil
        case .line(let l): rec.text.components(separatedBy: "\n").contains { $0.range(of: l, options: opts) != nil }
        case .task(let t): rec.text.components(separatedBy: "\n").contains { $0.range(of: #"^\s*[-*+] \[.\]"#, options: .regularExpression) != nil && $0.range(of: t, options: opts) != nil }
        case .property(let key, let value):
            if let p = rec.parsed.property(key) { value.map { v in p.displayString.range(of: v, options: opts) != nil } ?? true } else { false }
        case .not(let t): !matches(t, rec, opts)
        case .or(let a, let b): matches(a, rec, opts) || matches(b, rec, opts)
        }
    }

    /// Lines to show under a hit (first 20), highlighting text/regex terms.
    static func lineMatches(_ q: SearchQuery, _ text: String, _ opts: String.CompareOptions) -> [SearchHit.Match] {
        var needles: [String] = [], regexes: [NSRegularExpression] = []
        func collect(_ t: SearchQuery.Term) {
            switch t {
            case .text(let s), .line(let s), .task(let s): needles.append(s)
            case .regex(let r): regexes.append(r)
            case .or(let a, let b): collect(a); collect(b)
            default: break
            }
        }
        q.terms.forEach(collect)
        var out: [SearchHit.Match] = []
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            let ns = line as NSString
            var r = NSRange(location: NSNotFound, length: 0)
            for n in needles { let f = ns.range(of: n, options: opts); if f.location != NSNotFound { r = f; break } }
            if r.location == NSNotFound { for re in regexes { if let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) { r = m.range; break } } }
            if r.location != NSNotFound { out.append(.init(line: i, text: line, range: r)); if out.count >= 20 { break } }
        }
        return out
    }

    /// Fuzzy subsequence score for the quick switcher; nil when `query` isn't a subsequence of `candidate`.
    public static func fuzzyScore(_ query: String, _ candidate: String) -> Int? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased()), c = Array(candidate.lowercased())
        var qi = 0, score = 0, last = -1
        for (ci, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            score += (last == ci - 1 ? 5 : 1) + (ci == 0 || " /-_".contains(c[ci - 1]) ? 3 : 0)
            last = ci; qi += 1
        }
        return qi == q.count ? score * 100 - c.count : nil
    }
}
