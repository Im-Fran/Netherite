import Foundation

/// A forgiving HTML/ENML → Markdown converter for importers (Evernote, Apple Notes, Notion, web pages).
public struct HTMLToMarkdown {
    /// Returns Markdown for an `<img>` (src, alt), e.g. `![[copied.png]]`; nil keeps `![alt](src)`.
    public var image: (String, String) -> String? = { _, _ in nil }
    /// Returns Markdown for an Evernote `<en-media hash=… type=…>`.
    public var media: (String) -> String? = { _ in nil }

    public init() {}

    public func convert(_ html: String) -> String {
        let root = HTMLNode.parse(html)
        let body = root.first("body") ?? root
        var md = block(body, depth: 0)
        md = md.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        md = md.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return md.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// First `<title>` or `<h1>` text, for naming notes.
    public static func title(of html: String) -> String? {
        let root = HTMLNode.parse(html)
        let t = (root.first("title") ?? root.first("h1"))?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t?.isEmpty == false ? t : nil
    }

    // MARK: Rendering

    private static let skip: Set<String> = ["head", "script", "style", "title", "meta", "link", "noscript", "template"]

    private func block(_ n: HTMLNode, depth: Int) -> String {
        var out = ""
        var inline = ""
        func flush() {
            let t = inline.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { out += t + "\n\n" }
            inline = ""
        }
        for c in n.children {
            guard let tag = c.tag else { inline += collapse(c.text); continue }
            if Self.skip.contains(tag) { continue }
            switch tag {
            case "h1", "h2", "h3", "h4", "h5", "h6":
                flush(); out += String(repeating: "#", count: Int(tag.dropFirst())!) + " " + inlineText(c).trimmingCharacters(in: .whitespaces) + "\n\n"
            case "p":
                flush(); out += inlineText(c).trimmingCharacters(in: .whitespaces) + "\n\n"
            case "div", "section", "article", "main", "header", "footer", "en-note", "body", "center", "figure", "details", "summary":
                flush()
                // Evernote/Apple Notes use one <div> per line: keep single line breaks between them.
                if c.children.contains(where: { $0.isBlock }) { out += block(c, depth: depth) }
                else {
                    let t = inlineText(c).trimmingCharacters(in: .whitespaces)
                    out += (t.isEmpty ? "" : t) + "\n"
                }
            case "br": inline += "\n"
            case "hr": flush(); out += "---\n\n"
            case "pre":
                flush()
                let lang = (c.first("code")?.attrs["class"] ?? "").components(separatedBy: " ").first { $0.hasPrefix("language-") }.map { String($0.dropFirst(9)) } ?? ""
                out += "```\(lang)\n" + c.text.trimmingCharacters(in: .newlines) + "\n```\n\n"
            case "blockquote":
                flush()
                out += block(c, depth: depth).trimmingCharacters(in: .newlines).components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n") + "\n\n"
            case "ul", "ol":
                flush(); out += list(c, depth: depth) + (depth == 0 ? "\n" : "")
            case "table":
                flush(); out += table(c) + "\n\n"
            default:
                inline += inlineText(c, wrapping: c)
            }
        }
        flush()
        return out
    }

    private func list(_ n: HTMLNode, depth: Int) -> String {
        let ordered = n.tag == "ol"
        var out = "", i = Int(n.attrs["start"] ?? "") ?? 1
        for li in n.children where li.tag == "li" {
            let indent = String(repeating: "\t", count: depth)
            var marker = ordered ? "\(i). " : "- "
            var kids = li.children
            if let box = li.first("input"), box.attrs["type"] == "checkbox" {
                marker = "- [\(box.attrs["checked"] != nil ? "x" : " ")] "
                box.attrs["type"] = "hidden"   // already rendered as the marker
            } else if li.attrs["class"]?.contains("checked") == true || li.attrs["data-checked"] == "true" {
                marker = "- [x] "
            }
            kids = kids.filter { $0.tag != "ul" && $0.tag != "ol" }
            let text = HTMLNode(tag: "li", children: kids)
            let body = block(text, depth: depth + 1).trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n\n", with: "\n").replacingOccurrences(of: "\n", with: "\n" + indent + "  ")
            out += indent + marker + body + "\n"
            for sub in li.children where sub.tag == "ul" || sub.tag == "ol" { out += list(sub, depth: depth + 1) }
            i += 1
        }
        return out
    }

    private func table(_ n: HTMLNode) -> String {
        let rows = n.all("tr").map { tr in
            tr.children.filter { $0.tag == "td" || $0.tag == "th" }.map {
                inlineText($0).trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: "<br>").replacingOccurrences(of: "|", with: "\\|")
            }
        }.filter { !$0.isEmpty }
        guard let header = rows.first else { return "" }
        let width = rows.map(\.count).max() ?? header.count
        func line(_ r: [String]) -> String { "| " + (r + Array(repeating: "", count: width - r.count)).joined(separator: " | ") + " |" }
        return ([line(header), "|" + Array(repeating: " --- |", count: width).joined()] + rows.dropFirst().map(line)).joined(separator: "\n")
    }

    private func inlineText(_ n: HTMLNode, wrapping: HTMLNode? = nil) -> String {
        if let w = wrapping { return inline(w) }
        return n.children.map(inline).joined()
    }

    private func inline(_ n: HTMLNode) -> String {
        guard let tag = n.tag else { return collapse(n.text) }
        if Self.skip.contains(tag) { return "" }
        let inner = { n.children.map(inline).joined() }
        func wrap(_ m: String) -> String {
            let s = inner()
            let t = s.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return s }
            let lead = s.prefix { $0 == " " }, trail = String(s.reversed().prefix { $0 == " " })
            return lead + m + t + m + trail
        }
        switch tag {
        case "strong", "b": return wrap("**")
        case "em", "i", "cite": return wrap("*")
        case "s", "del", "strike": return wrap("~~")
        case "mark": return wrap("==")
        case "code", "kbd", "samp", "tt": return "`" + n.text + "`"
        case "br": return "\n"
        case "a":
            let text = inner().trimmingCharacters(in: .whitespaces)
            guard let href = n.attrs["href"], !href.isEmpty, !href.hasPrefix("javascript:") else { return text }
            return text.isEmpty || text == href ? "<\(href)>" : "[\(text)](\(href.replacingOccurrences(of: " ", with: "%20")))"
        case "img":
            let src = n.attrs["src"] ?? "", alt = n.attrs["alt"] ?? ""
            return image(src, alt) ?? (src.isEmpty ? "" : "![\(alt)](\(src.replacingOccurrences(of: " ", with: "%20")))")
        case "en-todo": return "- [\(n.attrs["checked"] == "true" ? "x" : " ")] "
        case "en-media": return n.attrs["hash"].flatMap(media) ?? ""
        case "input": return n.attrs["type"] == "checkbox" ? "[\(n.attrs["checked"] != nil ? "x" : " ")] " : ""
        case "sup": return "^" + inner()
        case "p", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "ul", "ol", "table", "tr":
            return "\n" + block(HTMLNode(tag: "div", children: [n]), depth: 0).trimmingCharacters(in: .newlines) + "\n"
        default: return inner()
        }
    }

    private func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

/// Tiny tolerant HTML tree (text nodes have `tag == nil`).
final class HTMLNode {
    var tag: String?
    var attrs: [String: String] = [:]
    var children: [HTMLNode] = []
    var textValue = ""

    init(tag: String?, attrs: [String: String] = [:], children: [HTMLNode] = [], text: String = "") {
        self.tag = tag; self.attrs = attrs; self.children = children; textValue = text
    }

    static let void: Set<String> = ["br", "hr", "img", "input", "meta", "link", "area", "base", "col", "embed", "source", "track", "wbr", "en-todo", "en-media"]
    static let blocks: Set<String> = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "table", "pre", "blockquote", "hr", "section", "article", "figure"]

    var isBlock: Bool { tag.map(Self.blocks.contains) ?? false }
    var text: String { tag == nil ? textValue : children.map(\.text).joined() }

    func first(_ t: String) -> HTMLNode? {
        for c in children { if c.tag == t { return c }; if let f = c.first(t) { return f } }
        return nil
    }

    func all(_ t: String) -> [HTMLNode] { children.flatMap { ($0.tag == t ? [$0] : []) + $0.all(t) } }

    static func parse(_ html: String) -> HTMLNode {
        let root = HTMLNode(tag: "#root")
        var stack = [root]
        let s = html as NSString
        let tagRE = try! NSRegularExpression(pattern: #"<!--[\s\S]*?-->|<!\[CDATA\[([\s\S]*?)\]\]>|<![^>]*>|<\?[^>]*>|<(/?)([A-Za-z][\w:-]*)((?:\s+[^\s=/>]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?)*)\s*(/?)>"#)
        let attrRE = try! NSRegularExpression(pattern: #"([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?"#)
        var last = 0
        func addText(_ t: String) {
            guard !t.isEmpty else { return }
            stack.last!.children.append(HTMLNode(tag: nil, text: decodeEntities(t)))
        }
        for m in tagRE.matches(in: html, range: NSRange(location: 0, length: s.length)) {
            addText(s.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = NSMaxRange(m.range)
            if m.range(at: 1).location != NSNotFound { stack.last!.children.append(HTMLNode(tag: nil, text: s.substring(with: m.range(at: 1)))); continue }
            guard m.range(at: 3).location != NSNotFound else { continue }   // comment / doctype
            let name = s.substring(with: m.range(at: 3)).lowercased()
            if m.range(at: 2).length > 0 {
                // Close the nearest matching open element; ignore strays.
                if let i = stack.lastIndex(where: { $0.tag == name }), i > 0 { stack.removeLast(stack.count - i) }
                continue
            }
            var attrs: [String: String] = [:]
            let raw = s.substring(with: m.range(at: 4))
            for a in attrRE.matches(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) {
                let r = (raw as NSString)
                let key = r.substring(with: a.range(at: 1)).lowercased()
                let val = [2, 3, 4].compactMap { a.range(at: $0).location != NSNotFound ? r.substring(with: a.range(at: $0)) : nil }.first ?? ""
                attrs[key] = decodeEntities(val)
            }
            // Implicitly close <p>/<li>/<tr>/<td> like browsers do.
            if ["p", "li", "tr", "td", "th", "option"].contains(name) || blocks.contains(name),
               let top = stack.last?.tag, (top == "p" && blocks.contains(name)) || (top == name && ["li", "tr", "td", "th", "p", "option"].contains(name)) {
                stack.removeLast()
            }
            let node = HTMLNode(tag: name, attrs: attrs)
            stack.last!.children.append(node)
            if !(void.contains(name) || m.range(at: 5).length > 0) {
                stack.append(node)
                if ["script", "style"].contains(name) {   // raw text until the closing tag
                    let close = s.range(of: "</\(name)", options: .caseInsensitive, range: NSRange(location: last, length: s.length - last))
                    if close.location != NSNotFound { last = close.location }
                }
            }
        }
        addText(s.substring(from: last))
        return root
    }

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "mdash": "—", "ndash": "–",
                     "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "copy": "©", "reg": "®", "trade": "™", "bull": "•"]
        let re = try! NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);"#)
        let ns = s as NSString
        var out = "", last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let e = ns.substring(with: m.range(at: 1))
            if e.hasPrefix("#x"), let v = UInt32(e.dropFirst(2), radix: 16), let u = Unicode.Scalar(v) { out += String(Character(u)) }
            else if e.hasPrefix("#"), let v = UInt32(e.dropFirst()), let u = Unicode.Scalar(v) { out += String(Character(u)) }
            else { out += named[e] ?? ns.substring(with: m.range) }
            last = NSMaxRange(m.range)
        }
        return out + ns.substring(from: last)
    }
}
