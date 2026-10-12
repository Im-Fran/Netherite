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
        var tokens: [String] = [], sources: [String?] = []   // the text each token replaced, for link destinations
        func token(_ html: String, source: String? = nil) -> String {
            tokens.append(html); sources.append(source); return "\u{E000}\(tokens.count - 1)\u{E001}"
        }

        // The placeholder markers are private-use characters; a note can't smuggle in its own (N-21).
        var src = text.replacingOccurrences(of: "[\u{E000}\u{E001}]", with: "\u{FFFD}", options: .regularExpression)
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
        var taken = IndexSet(), linkTargets = IndexSet()
        let codeMasked = maskCode(src)
        let ns = src as NSString
        func add(_ re: NSRegularExpression, in text: String, _ make: (NSTextCheckingResult) -> String?) {
            for m in re.matches(in: text, range: full(text)) {
                let first = sources.count
                guard let range = Range(m.range), !taken.intersects(integersIn: range),
                      !linkTargets.contains(range.lowerBound), !linkTargets.contains(range.upperBound - 1), let r = make(m) else { continue }
                for i in first..<sources.count where sources[i] == nil { sources[i] = ns.substring(with: m.range) }
                reps.append((m.range, r))
                taken.insert(integersIn: range)
            }
        }
        add(NoteParser.Regex.comment, in: codeMasked) { m in String(repeating: "\n", count: ns.substring(with: m.range).filter { $0 == "\n" }.count) }
        add(NoteParser.Regex.mathBlock, in: codeMasked) { m in
            let tex = ns.substring(with: m.range).dropFirst(2).dropLast(2)
            let lines = ns.substring(with: m.range).filter { $0 == "\n" }.count
            return token("<div class=\"math math-display\" data-tex=\"\(escape(String(tex)))\"></div>") + String(repeating: "\n", count: lines)
        }
        // A Markdown link's destination is a URL and an image's alt is plain text: no token starts or ends inside them
        // (`[Jump](#Intro)` isn't a tag, `![a $x$](…)` keeps its text), but one can wrap them (`==see [a](b)==`).
        for m in NoteParser.Regex.mdLink.matches(in: codeMasked, range: full(codeMasked)) {
            linkTargets.insert(integersIn: (m.range(at: 1).length > 0 ? m.range.location : NSMaxRange(m.range(at: 2)))..<NSMaxRange(m.range))
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
            token("<mark>", source: "==") + ns.substring(with: m.range(at: 2)) + token("</mark>", source: "==")
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
        var walker = HTMLWalker(ctx: ctx, sources: sources.map { $0 ?? "" })
        walker.visit(Document(parsing: splice(ns, reps), options: [.disableSmartOpts]))
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
            let reps = re.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { r -> (NSRange, String)? in
                guard let i = Int(ns.substring(with: r.range(at: 1))), tokens.indices.contains(i) else { return nil }
                return (r.range, tokens[i])
            }
            if reps.isEmpty { break }
            s = splice(ns, reps)
        }
        return s
    }

    /// Replaces non-overlapping ranges in one pass (linear, unlike repeated in-place replacement).
    static func splice(_ ns: NSString, _ reps: [(NSRange, String)]) -> String {
        var out = "", pos = 0
        for (r, s) in reps.sorted(by: { $0.0.location < $1.0.location }) {
            out += ns.substring(with: NSRange(location: pos, length: r.location - pos)) + s
            pos = NSMaxRange(r)
        }
        return out + ns.substring(from: pos)
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
        // Split like the parser does (`enumerateLines` also breaks on \r and U+2028), so its line numbers index here.
        var lines: [String] = []
        text.enumerateLines { l, _ in lines.append(l) }
        let parsed = NoteParser.parse(text)
        if sub.hasPrefix("^") {
            guard let line = parsed.blockIDs[String(sub.dropFirst())], lines.indices.contains(line) else { return "" }
            // A block is its paragraph/list item: walk back to the previous blank line.
            var start = line
            while start > 0, !lines[start - 1].trimmingCharacters(in: .whitespaces).isEmpty, !lines[line].hasPrefix("-") { start -= 1 }
            return lines[start...line].joined(separator: "\n")
        }
        let wanted = sub.split(separator: "#").last.map(String.init) ?? sub
        guard let h = parsed.headings.first(where: { $0.text.caseInsensitiveCompare(wanted) == .orderedSame }),
              lines.indices.contains(h.line) else { return "" }
        let end = min(parsed.headings.first { $0.line > h.line && $0.level <= h.level }?.line ?? lines.count, lines.count)
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

    // MARK: Sanitizing

    static let linkSchemes: Set<String> = ["http", "https", "mailto", "obsidian", "netherite"]
    static let mediaSchemes: Set<String> = ["http", "https", "data"]

    /// `url` when it's relative or uses one of `schemes`. Browsers drop tabs/newlines and leading
    /// control characters before reading the scheme, so the check does too.
    static func safeURL(_ url: String, schemes: Set<String>) -> String? {
        let probe = String(url.unicodeScalars.filter { $0.value > 0x20 })
        guard let m = probe.firstMatch(of: /^([A-Za-z][A-Za-z0-9+.\-]*):/) else { return url }
        return schemes.contains(m.1.lowercased()) ? url : nil
    }

    static let allowedTags: Set<String> = [
        "a", "abbr", "article", "aside", "audio", "b", "bdi", "bdo", "blockquote", "br", "caption", "center", "cite", "code",
        "col", "colgroup", "dd", "del", "details", "dfn", "div", "dl", "dt", "em", "figcaption", "figure", "font", "footer",
        "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "i", "img", "ins", "kbd", "li", "mark", "ol", "p", "pre", "q",
        "rp", "rt", "ruby", "s", "samp", "section", "small", "source", "span", "strike", "strong", "sub", "summary", "sup",
        "table", "tbody", "td", "tfoot", "th", "thead", "tr", "track", "u", "ul", "var", "video", "wbr",
    ]
    static let allowedAttributes: Set<String> = [
        "align", "alt", "cite", "class", "color", "colspan", "controls", "dir", "height", "href", "id", "lang", "loop",
        "muted", "name", "open", "poster", "rel", "reversed", "rowspan", "span", "src", "start", "style", "title", "type",
        "valign", "width",
    ]
    /// Elements whose content is code or raw text, dropped together with it.
    static let droppedWithContent: Set<String> = ["script", "style", "textarea", "title", "template", "noscript", "xmp", "noembed", "noframes", "iframe", "object"]

    /// Raw HTML in notes is allowed (like Obsidian) through an allowlist: the fragment is tokenized the way a browser
    /// reads tags and rebuilt from allowed tags and attributes only, with URLs limited to safe schemes (N-05).
    static func sanitize(_ html: String) -> String {
        let c = Array(html.unicodeScalars)
        var out = String.UnicodeScalarView(), i = 0
        var skipping: String?   // inside a dropped element
        // A tag needs a `>` after it: past the last one every `<` is text, without scanning to the end each time.
        let lastClose = c.lastIndex(of: ">") ?? -1
        func isSpace(_ u: Unicode.Scalar) -> Bool { u == " " || u == "\t" || u == "\n" || u == "\r" || u == "\u{0C}" }
        func emit(_ s: String) { if skipping == nil { out.append(contentsOf: s.unicodeScalars) } }
        while i < c.count {
            guard c[i] == "<" else { if skipping == nil { out.append(c[i]) }; i += 1; continue }
            // Comments, doctypes and processing instructions go entirely.
            if i + 1 < c.count, c[i + 1] == "!" || c[i + 1] == "?" {
                let close: [Unicode.Scalar] = c[i...].starts(with: "<!--".unicodeScalars) ? Array("-->".unicodeScalars) : [">"]
                var j = i + 2
                while j < c.count, !c[j...].starts(with: close) { j += 1 }
                i = min(c.count, j + close.count)
                continue
            }
            guard i < lastClose else { emit("&lt;"); i += 1; continue }
            var j = i + 1
            let closing = j < c.count && c[j] == "/"
            if closing { j += 1 }
            var name = ""
            while j < c.count, c[j].properties.isAlphabetic || (!name.isEmpty && (c[j].properties.numericType != nil || c[j] == "-")) {
                name.unicodeScalars.append(c[j]); j += 1
            }
            guard !name.isEmpty else { emit("&lt;"); i += 1; continue }
            name = name.lowercased()
            // Attributes, read like the HTML tokenizer: unquoted values run to whitespace or `>`.
            var attrs: [(String, String)] = []
            while j < c.count, c[j] != ">" {
                if isSpace(c[j]) || c[j] == "/" { j += 1; continue }
                var key = ""
                repeat { key.unicodeScalars.append(c[j]); j += 1 } while j < c.count && !isSpace(c[j]) && c[j] != "/" && c[j] != ">" && c[j] != "="
                while j < c.count, isSpace(c[j]) { j += 1 }
                var value = ""
                if j < c.count, c[j] == "=" {
                    j += 1
                    while j < c.count, isSpace(c[j]) { j += 1 }
                    if j < c.count, c[j] == "\"" || c[j] == "'" {
                        let q = c[j]; j += 1
                        while j < c.count, c[j] != q { value.unicodeScalars.append(c[j]); j += 1 }
                        j += 1
                    } else {
                        while j < c.count, !isSpace(c[j]), c[j] != ">" { value.unicodeScalars.append(c[j]); j += 1 }
                    }
                }
                attrs.append((key.lowercased(), value))
            }
            // No `>` outside a quote up to the end: the HTML tokenizer would read all of it as this tag, so every
            // later `<` would scan to the end too. The rest is text, in one go.
            guard j < c.count else {
                emit(String(String.UnicodeScalarView(c[i...])).replacingOccurrences(of: "<", with: "&lt;"))
                break
            }
            i = j + 1
            if let s = skipping {
                if closing, name == s { skipping = nil }
                continue
            }
            if droppedWithContent.contains(name) {
                if !closing, c[j - 1] != "/" { skipping = name }
                continue
            }
            guard allowedTags.contains(name) else { continue }
            if closing { emit("</\(name)>"); continue }
            var tag = "<" + name
            for (key, raw) in attrs where allowedAttributes.contains(key) || key.hasPrefix("data-") {
                // Decode entities before checking (`jav&#x61;script:`) and re-escape what was checked.
                // Render markers are dropped so no generated HTML can land inside an attribute.
                var value = decodeEntities(raw).replacingOccurrences(of: "[\u{E000}\u{E001}]", with: "", options: .regularExpression)
                if key == "href" || key == "cite" {
                    guard let v = safeURL(value, schemes: linkSchemes) else { continue }
                    value = v
                } else if key == "src" || key == "poster" {
                    guard let v = safeURL(value, schemes: mediaSchemes) else { continue }
                    value = v
                } else if key.hasPrefix("data-"), key.unicodeScalars.contains(where: { !($0.properties.isAlphabetic || $0.properties.numericType != nil || $0 == "-") }) {
                    continue
                }
                tag += " \(key)=\"\(escape(value))\""
            }
            emit(tag + ">")
        }
        return String(out)
    }

    /// Numeric references (with or without `;`) and the basic named ones; anything else stays literal and gets
    /// re-escaped, so the browser sees exactly what was checked.
    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}"]
        return s.replacing(/&(#[xX][0-9A-Fa-f]+|#[0-9]+|[A-Za-z]+);?/) { m -> String in
            let body = String(m.1)
            if body.hasPrefix("#") {
                let hex = body.dropFirst().first.map { $0 == "x" || $0 == "X" } ?? false
                let digits = body.dropFirst(hex ? 2 : 1)
                guard let n = UInt32(digits, radix: hex ? 16 : 10), n != 0, let u = Unicode.Scalar(n) else { return "\u{FFFD}" }
                return String(Character(u))
            }
            return named[body] ?? String(m.0)
        }
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
    /// The original text of each placeholder token: a destination gets it back, so no tag or link lands in an `href`
    /// (a reference definition or a title the link pattern doesn't cover).
    let sources: [String]
    var result = ""
    private let esc = HTMLRenderer.escape

    init(ctx: RenderContext, sources: [String] = []) { self.ctx = ctx; self.sources = sources }

    mutating func inner(_ m: Markup) -> String {
        var w = HTMLWalker(ctx: ctx, sources: sources)
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
        let dest = HTMLRenderer.restoreTokens(l.destination ?? "", sources)
        let isExternal = dest.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*:"#, options: .regularExpression) != nil
        if isExternal {
            let href = HTMLRenderer.safeURL(dest, schemes: HTMLRenderer.linkSchemes).map { " href=\"\(esc($0))\"" } ?? ""
            result += "<a class=\"external-link\"\(href)>\(inner(l))</a>"
        } else {
            let decoded = dest.removingPercentEncoding ?? dest
            let parts = decoded.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let path = ctx.resolve(parts[0], ctx.source)
            result += "<a class=\"internal-link\(path == nil ? " is-unresolved" : "")\" href=\"\(esc(ctx.linkHref(path, parts[0], parts.count > 1 ? parts[1] : nil)))\">\(inner(l))</a>"
        }
    }

    mutating func visitImage(_ i: Markdown.Image) {
        let src = HTMLRenderer.restoreTokens(i.source ?? "", sources)
        let isExternal = src.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*:"#, options: .regularExpression) != nil
        let url = isExternal ? HTMLRenderer.safeURL(src, schemes: HTMLRenderer.mediaSchemes) ?? ""
            : (ctx.resolve(src.removingPercentEncoding ?? src, ctx.source).map(ctx.assetURL) ?? HTMLRenderer.safeURL(src, schemes: HTMLRenderer.mediaSchemes) ?? "")
        result += "<img src=\"\(esc(url))\" alt=\"\(esc(i.plainText.replacingOccurrences(of: "\u{E000}\\d+\u{E001}", with: "", options: .regularExpression)))\" loading=\"lazy\">"
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
