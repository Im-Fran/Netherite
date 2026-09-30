import Foundation

/// Obsidian's Format converter: rewrites syntax from other apps into Obsidian-Flavored Markdown.
/// Code blocks and inline code are never touched.
public struct FormatConverter: Sendable {
    public struct Options: Sendable, Hashable, Codable {
        /// `[text](Other%20Note.md)` → `[[Other Note|text]]` (only relative links to notes that exist).
        public var markdownLinksToWikilinks = true
        /// Bear `#multi word tag#` → `#multi-word-tag`.
        public var bearTags = true
        /// Bear `::highlight::` → `==highlight==`.
        public var bearHighlights = true
        /// Roam `#[[tag]]` → `[[tag]]`, `^^highlight^^` → `==highlight==`, `{{[[TODO]]}}`/`{{[[DONE]]}}` → `[ ]`/`[x]`.
        public var roam = true
        /// `<mark>x</mark>` → `==x==`.
        public var htmlMarks = true
        /// `alias:`/`tag:`/`cssclass:` → `aliases:`/`tags:`/`cssclasses:` lists.
        public var legacyProperties = true
        /// Zettelkasten `[[202401011200]]` → `[[202401011200 Title|Title]]` when a note starting with the UID exists.
        public var zettelkastenLinks = false

        public init() {}
    }

    public var options: Options
    /// Vault-relative note paths used to resolve links (markdown links, Zettelkasten UIDs).
    public var files: [String]

    public init(options: Options = Options(), files: [String] = []) { self.options = options; self.files = files }

    public func convert(_ text: String, path: String = "") -> String {
        var s = text
        let o = options
        if o.legacyProperties { s = convertProperties(s) }
        if o.htmlMarks { s = replace(s, #"<mark>([\s\S]*?)</mark>"#) { "==\($0[1])==" } }
        if o.roam {
            s = replace(s, #"\{\{\[\[TODO\]\]\}\}"#) { _ in "[ ]" }
            s = replace(s, #"\{\{\[\[DONE\]\]\}\}"#) { _ in "[x]" }
            s = replace(s, #"#\[\[([^\]\n]+)\]\]"#) { "[[\($0[1])]]" }
            s = replace(s, #"\^\^([^\^\n]+)\^\^"#) { "==\($0[1])==" }
        }
        if o.bearHighlights { s = replace(s, #"::([^:\n]+)::"#) { "==\($0[1])==" } }
        if o.bearTags {
            s = replace(s, #"(?<![\w#&])#([\p{L}\p{N}_][^#\n]*?[^\s#])#(?![\w#])"#) { m in
                "#" + m[1].replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            }
        }
        if o.markdownLinksToWikilinks, !files.isEmpty {
            let resolver = LinkResolver(files: files)
            s = replace(s, #"(?<!!)\[([^\]\n]*)\]\(<?([^)>\s]+)>?\)"#) { m in
                let url = m[2]
                guard url.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*:"#, options: .regularExpression) == nil else { return m[0] }
                let decoded = url.removingPercentEncoding ?? url
                let parts = decoded.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                guard parts[0].isMarkdown || parts[0].fileExtension.isEmpty,
                      let target = resolver.resolve(parts[0], from: path), target.isMarkdown else { return m[0] }
                let link = resolver.linkText(for: target) + (parts.count > 1 && !parts[1].isEmpty ? "#" + parts[1] : "")
                return m[1].isEmpty || m[1] == target.noteName ? "[[\(link)]]" : "[[\(link)|\(m[1])]]"
            }
        }
        if o.zettelkastenLinks, !files.isEmpty {
            let names = files.filter(\.isMarkdown).map(\.noteName)
            s = replace(s, #"\[\[(\d{8,14})\]\]"#) { m in
                guard let full = names.first(where: { $0.hasPrefix(m[1] + " ") }) else { return m[0] }
                return "[[\(full)|\(full.dropFirst(m[1].count + 1))]]"
            }
        }
        return s
    }

    /// Regex replace outside fenced/inline code. `make` receives the match groups (0 = whole match).
    func replace(_ text: String, _ pattern: String, _ make: ([String]) -> String) -> String {
        let re = try! NSRegularExpression(pattern: pattern)
        let masked = HTMLRenderer.maskCode(text) as NSString
        let ns = text as NSString
        let out = NSMutableString(string: text)
        for m in re.matches(in: masked as String, range: NSRange(location: 0, length: masked.length)).reversed() {
            guard masked.substring(with: m.range) == ns.substring(with: m.range) else { continue }   // touches code
            let groups = (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
            out.replaceCharacters(in: m.range, with: make(groups))
        }
        return out as String
    }

    func convertProperties(_ text: String) -> String {
        guard let fm = Frontmatter.locate(in: text) else { return text }
        var props = Frontmatter.parse(fm.yaml)
        var changed = false
        for (old, new) in [("alias", "aliases"), ("tag", "tags"), ("cssclass", "cssclasses")] {
            guard let i = props.firstIndex(where: { $0.key == old }) else { continue }
            let values = props[i].value.strings.flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }.filter { !$0.isEmpty }
            if let j = props.firstIndex(where: { $0.key == new }) {
                props[j].value = .list(props[j].value.strings + values.filter { !props[j].value.strings.contains($0) })
                props.remove(at: i)
            } else {
                props[i] = Property(key: new, value: .list(values))
            }
            changed = true
        }
        return changed ? Frontmatter.replacing(in: text, with: props) : text
    }
}
