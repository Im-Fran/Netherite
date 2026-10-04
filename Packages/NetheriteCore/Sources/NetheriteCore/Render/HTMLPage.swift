import Foundation

public extension HTMLRenderer {
    /// URL of the bundled web assets folder (KaTeX, Mermaid, highlight.js, reader.css/js).
    static var webResources: URL? { Bundle.module.url(forResource: "Web", withExtension: nil) }

    /// Wraps a rendered fragment in a full document. `assets` is the base URL/path of the Web folder.
    /// `baseSize` is the body text size in points (pass the Dynamic Type body size on iOS); `transparentBackground`
    /// lets a non-opaque web view show the app background, unless the theme sets its own; `increaseContrast`
    /// strengthens secondary text and borders; `reduceMotion` drops the heading flash (the system setting is honored by CSS).
    static func page(title: String?, body: String, assets: String, theme: Theme? = nil, fullWidth: Bool = false,
                     initialSubpath: String? = nil, extraHead: String = "", extraBody: String = "",
                     baseSize: Double = 16, transparentBackground: Bool = false, increaseContrast: Bool = false,
                     reduceMotion: Bool = false) -> String {
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
        else if baseSize != 16 { head += "\n<style>:root{--size:\(px(baseSize))}</style>" }
        if transparentBackground, theme?.background == nil { head += "\n<style>html{background:transparent}</style>" }
        if increaseContrast { head += "\n<style>\(increasedContrastCSS)</style>" }
        if reduceMotion { head += "\n<style>.flash{animation:none;outline:2px solid var(--accent)}</style>" }
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

    /// Darker secondary text and borders for Increase Contrast, mixed from the text and background so they
    /// also hold on a theme's own background.
    static let increasedContrastCSS = ":root{--muted:color-mix(in srgb,var(--text) 80%,var(--bg));--faint:color-mix(in srgb,var(--text) 55%,var(--bg))}"

    /// A CSS pixel size that keeps fractions (Dynamic Type body sizes such as 17.5).
    private static func px(_ size: Double) -> String { String(format: "%gpx", size) }

    static func themeCSS(_ t: Theme, baseSize: Double = 16) -> String {
        // Theme files come from the vault (possibly someone else's), so only hex colors, plain font names and
        // simple callout names reach the stylesheet: anything else could close the <style> or inject rules.
        // Colors resolve through `color-scheme`: a theme with a fixed appearance pins it, others use light-dark().
        func color(_ p: Theme.Pair) -> String? {
            guard let light = RGB(hex: p.light)?.hex, let dark = RGB(hex: p.dark)?.hex else { return nil }
            switch t.appearance {
            case .light: return light
            case .dark: return dark
            case nil: return "light-dark(\(light),\(dark))"
            }
        }
        var v: [String] = []
        if let a = t.appearance { v.append("color-scheme:\(a.rawValue)") }
        if let c = t.accent.flatMap(color) { v.append("--accent:\(c)") }
        if let c = t.link.flatMap(color) { v.append("--link:\(c)") }
        if let c = t.tag.flatMap(color) { v.append("--tag:\(c)") }
        if let c = t.highlight.flatMap(color) { v.append("--mark:\(c)") }
        if let bg = t.background, let c = color(bg) {
            v.append("--bg:\(c)")
            // The default text colors assume the default background; a custom one gets text that reads on it.
            if let l = RGB(hex: bg.light), let d = RGB(hex: bg.dark) {
                let (lt, dt) = (Theme.textColors(on: l), Theme.textColors(on: d))
                if let c = color(Theme.Pair(lt.text.hex, dt.text.hex)) { v.append("--text:\(c)") }
                if let c = color(Theme.Pair(lt.muted.hex, dt.muted.hex)) { v.append("--muted:\(c)") }
            }
        }
        // `ui-serif`, `ui-rounded`… are generic families and must stay unquoted.
        func family(_ f: String) -> String? {
            guard !f.contains(where: { "\"'\\<>;{}()".contains($0) || $0.isNewline }) else { return nil }
            return f.hasPrefix("ui-") ? f : "\"\(f)\""
        }
        if let f = t.textFont.flatMap(family) { v.append("--font:\(f), -apple-system, sans-serif") }
        if let f = t.monoFont.flatMap(family) { v.append("--mono:\(f), ui-monospace, monospace") }
        if t.fontScale != nil || baseSize != 16 { v.append("--size:\(px(baseSize * (t.fontScale ?? 1)))") }
        if let l = t.lineHeight { v.append("--line:\(l * 1.28)") }
        var css = ":root{\(v.joined(separator: ";"))}"
        for (category, p) in (t.callouts ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard category.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }), let c = color(p) else { continue }
            let selector = category == "note" ? ".callout"
                : (Theme.calloutTypes[category] ?? [category]).map { ".callout[data-callout=\($0)]" }.joined(separator: ",")
            css += "\(selector){--c:\(c)}"
        }
        return css
    }
}
