import Foundation

public extension HTMLRenderer {
    /// URL of the bundled web assets folder (KaTeX, Mermaid, highlight.js, reader.css/js).
    static var webResources: URL? { Bundle.module.url(forResource: "Web", withExtension: nil) }

    /// Wraps a rendered fragment in a full document. `assets` is the base URL/path of the Web folder.
    /// `baseSize` is the body text size in points (pass the Dynamic Type body size on iOS); `transparentBackground`
    /// lets a non-opaque web view show the app background, unless the theme sets its own; `increaseContrast`
    /// strengthens secondary text and borders.
    static func page(title: String?, body: String, assets: String, theme: Theme? = nil, fullWidth: Bool = false,
                     initialSubpath: String? = nil, extraHead: String = "", extraBody: String = "",
                     baseSize: Double = 16, transparentBackground: Bool = false, increaseContrast: Bool = false) -> String {
        let a = assets.hasSuffix("/") ? assets : assets + "/"
        let needsMath = body.contains("class=\"math ")
        let needsMermaid = body.contains("class=\"mermaid\"")
        let needsCode = body.contains("<pre><code class=\"language-")
        var head = """
        <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="\(theme?.appearance?.rawValue ?? "light dark")">
        <link rel="stylesheet" href="\(a)reader.css">
        """
        if needsMath { head += "\n<link rel=\"stylesheet\" href=\"\(a)katex/katex.min.css\"><script src=\"\(a)katex/katex.min.js\"></script>" }
        if needsCode {
            // A theme with a fixed appearance gets that code style only; otherwise follow the system.
            func media(_ s: Theme.Appearance) -> String {
                theme?.appearance.map { $0 == s ? "all" : "not all" } ?? "(prefers-color-scheme: \(s.rawValue))"
            }
            head += "\n<link rel=\"stylesheet\" href=\"\(a)hljs/github.min.css\" media=\"\(media(.light))\">"
            head += "<link rel=\"stylesheet\" href=\"\(a)hljs/github-dark.min.css\" media=\"\(media(.dark))\"><script src=\"\(a)hljs/highlight.min.js\"></script>"
        }
        if needsMermaid { head += "\n<script src=\"\(a)mermaid.min.js\"></script>" }
        if let theme { head += "\n<style>\(themeCSS(theme, baseSize: baseSize))</style>" }
        else if baseSize != 16 { head += "\n<style>:root{--size:\(Int(baseSize))px}</style>" }
        if transparentBackground, theme?.background == nil { head += "\n<style>html{background:transparent}</style>" }
        if increaseContrast { head += "\n<style>\(increasedContrastCSS)</style>" }
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

    /// Darker secondary text and borders for Increase Contrast.
    static let increasedContrastCSS = ":root{--muted:light-dark(#3a3a3c,#c7c7cc);--faint:light-dark(#6e6e73,#8e8e93)}"

    static func themeCSS(_ t: Theme, baseSize: Double = 16) -> String {
        // Colors resolve through `color-scheme`: a theme with a fixed appearance pins it, others use light-dark().
        func color(_ p: Theme.Pair) -> String {
            switch t.appearance {
            case .light: p.light
            case .dark: p.dark
            case nil: "light-dark(\(p.light),\(p.dark))"
            }
        }
        var v: [String] = []
        if let a = t.appearance { v.append("color-scheme:\(a.rawValue)") }
        if let p = t.accent { v.append("--accent:\(color(p))") }
        if let p = t.link { v.append("--link:\(color(p))") }
        if let p = t.tag { v.append("--tag:\(color(p))") }
        if let p = t.highlight { v.append("--mark:\(color(p))") }
        if let p = t.background { v.append("--bg:\(color(p))") }
        // `ui-serif`, `ui-rounded`… are generic families and must stay unquoted.
        func family(_ f: String) -> String { f.hasPrefix("ui-") ? f : "\"\(f)\"" }
        if let f = t.textFont { v.append("--font:\(family(f)), -apple-system, sans-serif") }
        if let f = t.monoFont { v.append("--mono:\(family(f)), ui-monospace, monospace") }
        if t.fontScale != nil || baseSize != 16 { v.append("--size:\(Int(baseSize * (t.fontScale ?? 1)))px") }
        if let l = t.lineHeight { v.append("--line:\(l * 1.28)") }
        var css = ":root{\(v.joined(separator: ";"))}"
        for (category, p) in (t.callouts ?? [:]).sorted(by: { $0.key < $1.key }) {
            let selector = category == "note" ? ".callout"
                : (Theme.calloutTypes[category] ?? [category]).map { ".callout[data-callout=\($0)]" }.joined(separator: ",")
            css += "\(selector){--c:\(color(p))}"
        }
        return css
    }
}
