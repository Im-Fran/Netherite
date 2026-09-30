import Foundation
import Markdown

/// Hooks the renderer uses to reach the vault. The app points these at custom URL schemes,
/// the publisher at relative file paths.
public struct RenderContext: Sendable {
    public var source: String
    public var resolve: @Sendable (_ target: String, _ from: String) -> String?
    public var readNote: @Sendable (_ path: String) -> String?
    /// href for an internal link (`path` nil when unresolved).
    public var linkHref: @Sendable (_ path: String?, _ target: String, _ subpath: String?) -> String
    /// src for an embedded file (image, audio, pdf…).
    public var assetURL: @Sendable (_ path: String) -> String
    public var tagHref: @Sendable (_ tag: String) -> String
    public var depth = 0
    public var interactiveTasks = true

    public init(source: String,
                resolve: @escaping @Sendable (String, String) -> String?,
                readNote: @escaping @Sendable (String) -> String?,
                linkHref: @escaping @Sendable (String?, String, String?) -> String,
                assetURL: @escaping @Sendable (String) -> String,
                tagHref: @escaping @Sendable (String) -> String) {
        self.source = source; self.resolve = resolve; self.readNote = readNote
        self.linkHref = linkHref; self.assetURL = assetURL; self.tagHref = tagHref
    }
}

public enum HTMLRenderer {
    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "heic", "avif"]
    static let audioExts: Set<String> = ["mp3", "m4a", "wav", "ogg", "flac", "aac", "3gp", "webm"]
    static let videoExts: Set<String> = ["mp4", "mov", "mkv", "ogv"]

    /// Renders a note's Markdown to an HTML fragment.
    public static func render(_ text: String, context ctx: RenderContext) -> String {
        var tokens: [String] = []
        func token(_ html: String) -> String { tokens.append(html); return "\u{E000}\(tokens.count - 1)\u{E001}" }

        var src = text
        var props = ""
        if let fm = Frontmatter.locate(in: src) {
            let parsed = Frontmatter.parse(fm.yaml)
            if !parsed.isEmpty, ctx.depth == 0 {
                props = "<table class=\"properties\">" + parsed.map {
                    "<tr><th>\(escape($0.key))</th><td>\(escape($0.value.displayString))</td></tr>"
                }.joined() + "</table>\n"
            }
            src = blankLines(src, fm.range)
        }

        // Footnote definitions are collected and removed (lines kept blank so task line numbers stay valid).
        var footnotes: [(String, String)] = []
        let fnDef = try! NSRegularExpression(pattern: #"^\[\^([^\]]+)\]:[ \t]*(.*)$"#, options: .anchorsMatchLines)
        for m in fnDef.matches(in: src, range: full(src)).reversed() where !inCode(src, m.range) {
            let ns = src as NSString
            footnotes.insert((ns.substring(with: m.range(at: 1)), ns.substring(with: m.range(at: 2))), at: 0)
            src = ns.replacingCharacters(in: m.range, with: "")
        }

        // Replace OFM syntax outside code with placeholder tokens, back to front so ranges stay valid.
        var reps: [(NSRange, String)] = []
        let codeMasked = maskCode(src)
        let ns = src as NSString
        func add(_ re: NSRegularExpression, in text: String, _ make: (NSTextCheckingResult) -> String?) {
            for m in re.matches(in: text, range: full(text)) where !reps.contains(where: { NSIntersectionRange($0.0, m.range).length > 0 }) {
                if let r = make(m) { reps.append((m.range, r)) }
            }
        }
        add(NoteParser.Regex.comment, in: codeMasked) { m in String(repeating: "\n", count: ns.substring(with: m.range).filter { $0 == "\n" }.count) }
        add(NoteParser.Regex.mathBlock, in: codeMasked) { m in
            let tex = ns.substring(with: m.range).dropFirst(2).dropLast(2)
            let lines = ns.substring(with: m.range).filter { $0 == "\n" }.count
            return token("<div class=\"math math-display\" data-tex=\"\(escape(String(tex)))\"></div>") + String(repeating: "\n", count: lines)
        }
        add(NoteParser.Regex.inlineMath, in: codeMasked) { m in
            token("<span class=\"math math-inline\" data-tex=\"\(escape(String(ns.substring(with: m.range).dropFirst().dropLast())))\"></span>")
        }
        let masked = NoteParser.maskedText(src)
        add(NoteParser.Regex.wiki, in: masked) { m in
            let link = NoteParser.splitWiki(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: "\\|", with: "|"), isEmbed: m.range(at: 1).length > 0)
            return token(link.isEmbed ? embed(link, ctx) : anchor(link, ctx))
        }
        add(try! NSRegularExpression(pattern: #"(==)(?=\S)(.+?)(?<=\S)(==)"#), in: masked) { m in
            token("<mark>") + ns.substring(with: m.range(at: 2)) + token("</mark>")
        }
        add(NoteParser.Regex.tag, in: masked) { m in
            let tag = ns.substring(with: m.range(at: 1))
            guard tag.contains(where: { !$0.isNumber }) else { return nil }
            return token("<a class=\"tag\" href=\"\(escape(ctx.tagHref(tag)))\">#\(escape(tag))</a>")
        }
        add(try! NSRegularExpression(pattern: #"\[\^([^\]\s]+)\](?!:)"#), in: masked) { m in
            let label = escape(ns.substring(with: m.range(at: 1)))
            return token("<sup class=\"footnote-ref\"><a href=\"#fn-\(label)\" id=\"fnref-\(label)\">\(label)</a></sup>")
        }
        add(try! NSRegularExpression(pattern: #"[ \t]\^([A-Za-z0-9\-]+)[ \t]*$"#, options: .anchorsMatchLines), in: masked) { m in
            token("<a class=\"block-id\" id=\"^\(escape(ns.substring(with: m.range(at: 1))))\"></a>")
        }
        let out = NSMutableString(string: src)
        for (r, s) in reps.sorted(by: { $0.0.location > $1.0.location }) { out.replaceCharacters(in: r, with: s) }

        var walker = HTMLWalker(ctx: ctx)
        walker.visit(Document(parsing: out as String, options: [.disableSmartOpts]))
        var html = props + walker.result

        if !footnotes.isEmpty {
            var sub = ctx; sub.depth += 1
            html += "<section class=\"footnotes\"><hr><ol>" + footnotes.map { label, body in
                let inner = render(body, context: sub).replacingOccurrences(of: #"^<p>|</p>\s*$"#, with: "", options: .regularExpression)
                return "<li id=\"fn-\(escape(label))\">\(inner) <a href=\"#fnref-\(escape(label))\" class=\"footnote-back\">↩︎</a></li>"
            }.joined() + "</ol></section>"
        }
        return restoreTokens(html, tokens)
    }

    static func restoreTokens(_ html: String, _ tokens: [String]) -> String {
        guard !tokens.isEmpty else { return html }
        let re = try! NSRegularExpression(pattern: "\u{E000}(\\d+)\u{E001}")
        var s = html
        // Tokens can nest (highlight around a link), so repeat until stable.
        for _ in 0..<3 {
            let ns = s as NSString
            let matches = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty { break }
            let m = NSMutableString(string: s)
            for r in matches.reversed() { m.replaceCharacters(in: r.range, with: tokens[Int(ns.substring(with: r.range(at: 1)))!]) }
            s = m as String
        }
        return s
    }

    // MARK: Links and embeds

    static func anchor(_ link: NoteLink, _ ctx: RenderContext) -> String {
        let path = ctx.resolve(link.target, ctx.source)
        let text = link.alias ?? (link.target.isEmpty ? (link.subpath ?? "") : link.target + (link.subpath.map { " > \($0)" } ?? ""))
        let cls = path == nil ? "internal-link is-unresolved" : "internal-link"
        return "<a class=\"\(cls)\" href=\"\(escape(ctx.linkHref(path, link.target, link.subpath)))\" data-href=\"\(escape(link.target + (link.subpath.map { "#\($0)" } ?? "")))\">\(escape(text))</a>"
    }

    public static func embed(_ link: NoteLink, _ ctx: RenderContext) -> String {
        guard let path = ctx.resolve(link.target, ctx.source) else {
            return "<span class=\"embed is-unresolved\">\(escape(link.target))</span>"
        }
        let ext = path.fileExtension
        let src = escape(ctx.assetURL(path))
        if imageExts.contains(ext) {
            var size = ""
            if let a = link.alias, let m = a.wholeMatch(of: /(\d+)(?:x(\d+))?/) {
                size = " width=\"\(m.1)\"" + (m.2.map { " height=\"\($0)\"" } ?? "")
            }
            return "<img class=\"embed-image\" src=\"\(src)\" alt=\"\(escape(link.alias ?? path.noteName))\"\(size) loading=\"lazy\">"
        }
        if audioExts.contains(ext) { return "<audio controls src=\"\(src)\"></audio>" }
        if videoExts.contains(ext) { return "<video controls src=\"\(src)\"></video>" }
        if ext == "pdf" { return "<iframe class=\"embed-pdf\" src=\"\(src)\"></iframe>" }
        guard ext == "md", ctx.depth < 3, let text = ctx.readNote(path) else {
            return anchor(link, ctx)
        }
        var sub = ctx
        sub.depth += 1
        sub.source = path
        let body = render(section(of: text, subpath: link.subpath), context: sub)
        return "<div class=\"embed markdown-embed\"><div class=\"embed-title\"><a class=\"internal-link\" href=\"\(escape(ctx.linkHref(path, link.target, link.subpath)))\">\(escape(link.alias ?? path.noteName))</a></div>\(body)</div>"
    }

    /// Extracts the part of a note a `#Heading` or `#^block` subpath points at.
    public static func section(of text: String, subpath: String?) -> String {
        guard let sub = subpath, !sub.isEmpty else { return text }
        let lines = text.components(separatedBy: "\n")
        let parsed = NoteParser.parse(text)
        if sub.hasPrefix("^") {
            guard let line = parsed.blockIDs[String(sub.dropFirst())] else { return "" }
            // A block is its paragraph/list item: walk back to the previous blank line.
            var start = line
            while start > 0, !lines[start - 1].trimmingCharacters(in: .whitespaces).isEmpty, !lines[line].hasPrefix("-") { start -= 1 }
            return lines[start...line].joined(separator: "\n")
        }
        let wanted = sub.split(separator: "#").last.map(String.init) ?? sub
        guard let h = parsed.headings.first(where: { $0.text.caseInsensitiveCompare(wanted) == .orderedSame }) else { return "" }
        let end = parsed.headings.first { $0.line > h.line && $0.level <= h.level }?.line ?? lines.count
        return lines[h.line..<end].joined(separator: "\n")
    }

    // MARK: Helpers

    public static func escape(_ s: String) -> String {
        var o = ""
        o.reserveCapacity(s.utf8.count)
        for c in s {
            switch c {
            case "&": o += "&amp;"
            case "<": o += "&lt;"
            case ">": o += "&gt;"
            case "\"": o += "&quot;"
            default: o.append(c)
            }
        }
        return o
    }

    /// Raw HTML in notes is allowed (like Obsidian) but scripts, event handlers and `javascript:` URLs are stripped.
    static func sanitize(_ html: String) -> String {
        html.replacingOccurrences(of: #"(?is)<(script|iframe|object|embed|style)\b.*?(</\1\s*>|$)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</?(script|iframe|object|embed|style)\b[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+on[a-z]+\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)(href|src)\s*=\s*(["']?)\s*javascript:"#, with: "$1=$2#", options: .regularExpression)
    }

    static func full(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    static func blankLines(_ s: String, _ r: NSRange) -> String {
        let ns = s as NSString
        return ns.replacingCharacters(in: r, with: String(repeating: "\n", count: ns.substring(with: r).filter { $0 == "\n" }.count))
    }

    static func maskCode(_ s: String) -> String {
        var u = Array(s.utf16)
        for r in NoteParser.Regex.fenced.matches(in: s, range: full(s)) { NoteParser.blank(&u, r.range) }
        let s2 = String(utf16CodeUnits: u, count: u.count)
        for r in NoteParser.Regex.inlineCode.matches(in: s2, range: full(s2)) { NoteParser.blank(&u, r.range) }
        return String(utf16CodeUnits: u, count: u.count)
    }

    static func inCode(_ s: String, _ r: NSRange) -> Bool {
        let masked = maskCode(s) as NSString
        return masked.substring(with: r) != (s as NSString).substring(with: r)
    }

    static func slug(_ s: String) -> String {
        s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
    }
}

/// CommonMark/GFM → HTML with escaping, heading anchors, callouts, interactive tasks and code/mermaid blocks.
struct HTMLWalker: MarkupWalker {
    var ctx: RenderContext
    var result = ""
    private let esc = HTMLRenderer.escape

    init(ctx: RenderContext) { self.ctx = ctx }

    mutating func inner(_ m: Markup) -> String {
        var w = HTMLWalker(ctx: ctx)
        for c in m.children { w.visit(c) }
        return w.result
    }

    mutating func visitDocument(_ d: Document) { descendInto(d) }

    mutating func visitHeading(_ h: Markdown.Heading) {
        let text = h.plainText.replacingOccurrences(of: "\u{E000}\\d+\u{E001}", with: "", options: .regularExpression)
        result += "<h\(h.level) id=\"\(HTMLRenderer.slug(text))\" data-heading=\"\(esc(text.trimmingCharacters(in: .whitespaces)))\">\(inner(h))</h\(h.level)>\n"
    }

    mutating func visitParagraph(_ p: Paragraph) { result += "<p>\(inner(p))</p>\n" }
    mutating func visitText(_ t: Markdown.Text) { result += esc(t.string) }
    mutating func visitSoftBreak(_ s: SoftBreak) { result += "<br>\n" }   // Obsidian keeps single line breaks
    mutating func visitLineBreak(_ l: LineBreak) { result += "<br>\n" }
    mutating func visitThematicBreak(_ t: ThematicBreak) { result += "<hr>\n" }
    mutating func visitEmphasis(_ e: Emphasis) { result += "<em>\(inner(e))</em>" }
    mutating func visitStrong(_ s: Strong) { result += "<strong>\(inner(s))</strong>" }
    mutating func visitStrikethrough(_ s: Strikethrough) { result += "<del>\(inner(s))</del>" }
    mutating func visitInlineCode(_ c: InlineCode) { result += "<code>\(esc(c.code))</code>" }
    mutating func visitHTMLBlock(_ h: HTMLBlock) { result += HTMLRenderer.sanitize(h.rawHTML) }
    mutating func visitInlineHTML(_ h: InlineHTML) { result += HTMLRenderer.sanitize(h.rawHTML) }

    mutating func visitCodeBlock(_ c: CodeBlock) {
        let lang = (c.language ?? "").lowercased()
        if lang == "mermaid" {
            result += "<pre class=\"mermaid\">\(esc(c.code))</pre>\n"
        } else if lang == "math" {
            result += "<div class=\"math math-display\" data-tex=\"\(esc(c.code))\"></div>\n"
        } else {
            let cls = lang.isEmpty ? "nohighlight" : "language-\(esc(lang))"
            result += "<pre><code class=\"\(cls)\">\(esc(c.code))</code></pre>\n"
        }
    }

    mutating func visitLink(_ l: Markdown.Link) {
        let dest = l.destination ?? ""
        let isExternal = dest.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*:"#, options: .regularExpression) != nil
        if isExternal {
            result += "<a class=\"external-link\" href=\"\(esc(dest))\">\(inner(l))</a>"
        } else {
            let decoded = dest.removingPercentEncoding ?? dest
            let parts = decoded.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let path = ctx.resolve(parts[0], ctx.source)
            result += "<a class=\"internal-link\(path == nil ? " is-unresolved" : "")\" href=\"\(esc(ctx.linkHref(path, parts[0], parts.count > 1 ? parts[1] : nil)))\">\(inner(l))</a>"
        }
    }

    mutating func visitImage(_ i: Markdown.Image) {
        let src = i.source ?? ""
        let isExternal = src.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*:"#, options: .regularExpression) != nil
        let url = isExternal ? src : (ctx.resolve(src.removingPercentEncoding ?? src, ctx.source).map(ctx.assetURL) ?? src)
        result += "<img src=\"\(esc(url))\" alt=\"\(esc(i.plainText))\" loading=\"lazy\">"
    }

    mutating func visitUnorderedList(_ l: UnorderedList) { result += "<ul>\n\(inner(l))</ul>\n" }
    mutating func visitOrderedList(_ l: OrderedList) {
        result += "<ol\(l.startIndex != 1 ? " start=\"\(l.startIndex)\"" : "")>\n\(inner(l))</ol>\n"
    }

    mutating func visitListItem(_ li: ListItem) {
        if let cb = li.checkbox {
            let line = (li.range?.lowerBound.line ?? 1) - 1
            let checked = cb == .checked ? " checked" : ""
            let disabled = ctx.interactiveTasks && ctx.depth == 0 ? "" : " disabled"
            result += "<li class=\"task-list-item\(checked.isEmpty ? "" : " is-checked")\"><input type=\"checkbox\" class=\"task-checkbox\" data-line=\"\(line)\"\(checked)\(disabled)> \(stripParagraph(inner(li)))</li>\n"
        } else {
            result += "<li>\(stripParagraph(inner(li)))</li>\n"
        }
    }

    /// Tight list items render without wrapping <p>.
    private func stripParagraph(_ s: String) -> String {
        guard s.hasPrefix("<p>") else { return s }
        if let r = s.range(of: "</p>\n") { return String(s[s.index(s.startIndex, offsetBy: 3)..<r.lowerBound]) + String(s[r.upperBound...]) }
        return s
    }

    mutating func visitBlockQuote(_ q: BlockQuote) {
        let body = inner(q)
        let re = try! NSRegularExpression(pattern: #"^<p>\[!([\w-]+)\]([+-]?)[ \t]*(.*?)(?:<br>\n|</p>\n)"#, options: .dotMatchesLineSeparators)
        let ns = body as NSString
        guard let m = re.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)) else {
            result += "<blockquote>\n\(body)</blockquote>\n"
            return
        }
        let type = ns.substring(with: m.range(at: 1)).lowercased()
        let fold = ns.substring(with: m.range(at: 2))
        var title = ns.substring(with: m.range(at: 3))
        if title.isEmpty { title = type.prefix(1).uppercased() + type.dropFirst() }
        var rest = ns.substring(from: NSMaxRange(m.range))
        if ns.substring(with: m.range).hasSuffix("<br>\n") { rest = "<p>" + rest }
        let content = "<div class=\"callout-content\">\(rest)</div>"
        if fold.isEmpty {
            result += "<div class=\"callout\" data-callout=\"\(esc(type))\"><div class=\"callout-title\">\(title)</div>\(content)</div>\n"
        } else {
            result += "<details class=\"callout\" data-callout=\"\(esc(type))\"\(fold == "+" ? " open" : "")><summary class=\"callout-title\">\(title)</summary>\(content)</details>\n"
        }
    }

    mutating func visitTable(_ t: Markdown.Table) {
        result += "<table>\n<thead><tr>"
        let aligns = t.columnAlignments
        for (i, cell) in t.head.cells.enumerated() {
            result += "<th\(align(aligns, i))>\(inner(cell))</th>"
        }
        result += "</tr></thead>\n<tbody>\n"
        for row in t.body.rows {
            result += "<tr>"
            for (i, cell) in row.cells.enumerated() { result += "<td\(align(aligns, i))>\(inner(cell))</td>" }
            result += "</tr>\n"
        }
        result += "</tbody></table>\n"
    }

    private func align(_ a: [Markdown.Table.ColumnAlignment?], _ i: Int) -> String {
        guard i < a.count, let x = a[i] else { return "" }
        switch x {
        case .left: return " style=\"text-align:left\""
        case .center: return " style=\"text-align:center\""
        case .right: return " style=\"text-align:right\""
        }
    }
}
