import Foundation

/// Small readability-style HTML → Markdown for the web clipper.
// ponytail: regex conversion, good for articles; swap for a real DOM parser if clips of complex pages matter.
enum HTMLToMarkdown {
    struct Clip { var title: String; var description: String?; var markdown: String }

    static func convert(_ html: String, baseURL: URL?) -> Clip {
        let title = first(#"<title[^>]*>([\s\S]*?)</title>"#, in: html).map(decode)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let desc = first(#"<meta[^>]+(?:name|property)=["'](?:og:)?description["'][^>]+content=["']([^"']*)["']"#, in: html).map(decode)

        var body = first(#"<article[^>]*>([\s\S]*?)</article>"#, in: html)
            ?? first(#"<main[^>]*>([\s\S]*?)</main>"#, in: html)
            ?? first(#"<body[^>]*>([\s\S]*?)</body>"#, in: html) ?? html
        for tag in ["script", "style", "noscript", "nav", "header", "footer", "aside", "form", "svg", "iframe"] {
            body = replace(#"<\#(tag)\b[\s\S]*?</\#(tag)>"#, in: body, with: "")
        }
        body = replace(#"<!--[\s\S]*?-->"#, in: body, with: "")
        body = replace(#"<pre[^>]*>([\s\S]*?)</pre>"#, in: body) { "\n\n```\n" + stripTags($0[1]) + "\n```\n\n" }
        for level in 1...6 {
            body = replace(#"<h\#(level)[^>]*>([\s\S]*?)</h\#(level)>"#, in: body) { "\n\n" + String(repeating: "#", count: level) + " " + stripTags($0[1]).trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" }
        }
        body = replace(#"<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#, in: body) { m in
            let text = stripTags(m[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            let href = URL(string: decode(m[1]), relativeTo: baseURL)?.absoluteString ?? m[1]
            return text.isEmpty ? "" : "[\(text)](\(href))"
        }
        body = replace(#"<img[^>]+src=["']([^"']+)["'][^>]*>"#, in: body) { m in
            "![](\(URL(string: decode(m[1]), relativeTo: baseURL)?.absoluteString ?? m[1]))"
        }
        body = replace(#"<(strong|b)\b[^>]*>([\s\S]*?)</\1>"#, in: body) { "**\($0[2])**" }
        body = replace(#"<(em|i)\b[^>]*>([\s\S]*?)</\1>"#, in: body) { "*\($0[2])*" }
        body = replace(#"<code[^>]*>([\s\S]*?)</code>"#, in: body) { "`\($0[1])`" }
        body = replace(#"<li[^>]*>"#, in: body, with: "\n- ")
        body = replace(#"<blockquote[^>]*>"#, in: body, with: "\n\n> ")
        body = replace(#"<br\s*/?>"#, in: body, with: "\n")
        body = replace(#"</?(p|div|section|ul|ol|table|tr|blockquote)\b[^>]*>"#, in: body, with: "\n\n")
        body = decode(stripTags(body))
        body = replace(#"[ \t]+\n"#, in: body, with: "\n")
        body = replace(#"\n{3,}"#, in: body, with: "\n\n")
        return Clip(title: title, description: desc, markdown: body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Helpers

    static func first(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)),
              m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
        return (s as NSString).substring(with: m.range(at: 1))
    }

    static func replace(_ pattern: String, in s: String, with template: String) -> String {
        s.replacingOccurrences(of: pattern, with: template, options: [.regularExpression, .caseInsensitive])
    }

    static func replace(_ pattern: String, in s: String, _ transform: ([String]) -> String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return s }
        let ns = s as NSString
        var out = "", last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let groups = (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
            out += transform(groups)
            last = NSMaxRange(m.range)
        }
        return out + ns.substring(from: last)
    }

    static func stripTags(_ s: String) -> String { replace(#"<[^>]+>"#, in: s, with: "") }

    static func decode(_ s: String) -> String {
        var o = s
        for (k, v) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"), ("&amp;", "&")] {
            o = o.replacingOccurrences(of: k, with: v)
        }
        return replace(#"&#(\d+);"#, in: o) { m in Int(m[1]).flatMap(UnicodeScalar.init).map { String(Character($0)) } ?? m[0] }
    }
}
