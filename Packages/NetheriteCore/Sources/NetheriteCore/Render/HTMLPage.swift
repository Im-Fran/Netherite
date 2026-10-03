import Foundation

public extension HTMLRenderer {
    /// URL of the bundled web assets folder (KaTeX, Mermaid, highlight.js, reader.css/js).
    static var webResources: URL? { Bundle.module.url(forResource: "Web", withExtension: nil) }

    /// Wraps a rendered fragment in a full document. `assets` is the base URL/path of the Web folder.
    /// `baseSize` is the body text size in points (pass the Dynamic Type body size on iOS); `transparentBackground`
    /// lets a non-opaque web view show the app background, unless the theme sets its own.
    static func page(title: String?, body: String, assets: String, theme: Theme? = nil, fullWidth: Bool = false,
                     initialSubpath: String? = nil, extraHead: String = "", extraBody: String = "",
                     baseSize: Double = 16, transparentBackground: Bool = false) -> String {
        let a = assets.hasSuffix("/") ? assets : assets + "/"
        let needsMath = body.contains("class=\"math ")
        let needsMermaid = body.contains("class=\"mermaid\"")
        let needsCode = body.contains("<pre><code class=\"language-")
        var head = """
        <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <link rel="stylesheet" href="\(a)reader.css">
        """
        if needsMath { head += "\n<link rel=\"stylesheet\" href=\"\(a)katex/katex.min.css\"><script src=\"\(a)katex/katex.min.js\"></script>" }
        if needsCode {
            head += "\n<link rel=\"stylesheet\" href=\"\(a)hljs/github.min.css\" media=\"(prefers-color-scheme: light)\">"
            head += "<link rel=\"stylesheet\" href=\"\(a)hljs/github-dark.min.css\" media=\"(prefers-color-scheme: dark)\"><script src=\"\(a)hljs/highlight.min.js\"></script>"
        }
        if needsMermaid { head += "\n<script src=\"\(a)mermaid.min.js\"></script>" }
        if let theme { head += "\n<style>\(themeCSS(theme, baseSize: baseSize))</style>" }
        else if baseSize != 16 { head += "\n<style>:root{--size:\(Int(baseSize))px}</style>" }
        if transparentBackground, theme?.background == nil { head += "\n<style>html{background:transparent}</style>" }
        if let sub = initialSubpath {
            let json = (try? String(data: JSONEncoder().encode(sub), encoding: .utf8)) ?? "\"\""
            head += "\n<script>window.netheriteInitialSubpath = \(json);</script>"
        }
        head += "\n<script src=\"\(a)reader.js\"></script>" + extraHead
        let titleHTML = title.map { "<div class=\"inline-title\">\(escape($0))</div>" } ?? ""
        return """
        <!doctype html><html><head>\(head)<title>\(escape(title ?? ""))</title></head>
        <body class="\(fullWidth ? "full-width" : "")">\(titleHTML)\(body)\(extraBody)</body></html>
        """
    }

    static func themeCSS(_ t: Theme, baseSize: Double = 16) -> String {
        func vars(_ pick: (Theme.Pair) -> String) -> String {
            var v: [String] = []
            if let p = t.accent { v.append("--accent:\(pick(p))") }
            if let p = t.link { v.append("--link:\(pick(p))") }
            if let p = t.tag { v.append("--tag:\(pick(p))") }
            if let p = t.highlight { v.append("--mark:\(pick(p))") }
            if let p = t.background { v.append("--bg:\(pick(p))") }
            return v.joined(separator: ";")
        }
        var css = ":root{\(vars { $0.light })"
        if let f = t.textFont { css += ";--font:\"\(f)\", -apple-system, sans-serif" }
        if let f = t.monoFont { css += ";--mono:\"\(f)\", ui-monospace, monospace" }
        if t.fontScale != nil || baseSize != 16 { css += ";--size:\(Int(baseSize * (t.fontScale ?? 1)))px" }
        if let l = t.lineHeight { css += ";--line:\(l * 1.28)" }
        return css + "}@media (prefers-color-scheme: dark){:root{\(vars { $0.dark })}}"
    }
}
