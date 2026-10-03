import SwiftUI
import NetheriteCore

extension NSAttributedString.Key {
    static let netheriteLink = NSAttributedString.Key("netherite.link")      // String: raw link target
    static let netheriteTask = NSAttributedString.Key("netherite.task")      // Bool: checkbox done state
    static let netheriteTag = NSAttributedString.Key("netherite.tag")        // String: tag text
    static let netheriteMarker = NSAttributedString.Key("netherite.marker")  // Bool: hideable syntax
}

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

/// An image embed rendered inline by Live Preview.
struct PlacedEmbed {
    enum Kind {
        /// Rendered image; `label` is what VoiceOver reads ("Table", "Equation: …", the file name…).
        case image(PlatformImage, label: String)
        /// Clickable task checkbox; `range.location` is the task line start, `label` the task text.
        case checkbox(done: Bool, label: String)
        case bullet
    }
    /// Anchor: the line start of the element.
    var range: NSRange
    var kind: Kind
    var size: CGSize
    /// Horizontal offset from the line start (nested list indentation).
    var xOffset: CGFloat = 0
}

/// Maps `MarkdownHighlighter` spans to text attributes. Markers outside the active lines are collapsed
/// (Live Preview); inside them they're shown dimmed so the syntax stays editable.
@MainActor
struct EditorStyler {
    var theme: Theme
    var livePreview = true
    /// Resolves an embed target to an image (nil when it isn't an image in the vault).
    var embedImage: ((String) -> PlatformImage?)? = nil
    /// Rendered preview for a block (math, Mermaid, note embed); nil while rendering or when not applicable.
    var blockImage: ((BlockKind) -> PlatformImage?)? = nil

    enum BlockKind: Hashable {
        case math(String)
        case mermaid(String)
        case noteEmbed(String)
        /// Markdown rendered like reading view (tables, callouts).
        case markdown(String)
    }
    var maxEmbedWidth: CGFloat = 560

    #if os(macOS)
    var baseSize: CGFloat { 15 * (theme.fontScale ?? 1) }
    #else
    var baseSize: CGFloat { PlatformFont.preferredFont(forTextStyle: .body).pointSize * (theme.fontScale ?? 1) }
    #endif

    func font(size: CGFloat? = nil, bold: Bool = false, italic: Bool = false, mono: Bool = false) -> PlatformFont {
        let s = size ?? baseSize
        var f: PlatformFont
        if mono {
            f = theme.monoFont.flatMap { PlatformFont(name: $0, size: s * 0.92) } ?? .monospacedSystemFont(ofSize: s * 0.92, weight: bold ? .semibold : .regular)
        } else {
            f = theme.textFont.flatMap { PlatformFont(name: $0, size: s) } ?? .systemFont(ofSize: s, weight: bold ? .bold : .regular)
            if bold, theme.textFont != nil { f = f.with(traits: .bold) }
        }
        return italic ? f.with(traits: .italic) : f
    }

    var paragraph: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineHeightMultiple = theme.lineHeight ?? 1.25
        p.paragraphSpacing = baseSize * 0.35
        return p
    }

    var indented: NSParagraphStyle {
        let p = paragraph.mutableCopy() as! NSMutableParagraphStyle
        p.firstLineHeadIndent = baseSize
        p.headIndent = baseSize
        return p
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font(), .foregroundColor: PlatformColor.label, .paragraphStyle: paragraph]
    }

    var linkColor: PlatformColor { .pair(theme.link, fallback: .accent) }
    var tagColor: PlatformColor { .pair(theme.tag, fallback: .accent) }
    var highlightColor: PlatformColor { .pair(theme.highlight, fallback: .systemYellow.withAlphaComponent(0.35)) }

    static func calloutColor(_ type: String) -> PlatformColor {
        switch type {
        case "tip", "hint", "important", "success", "check", "done": .systemGreen
        case "warning", "caution", "attention", "question", "help", "faq": .systemOrange
        case "danger", "error", "failure", "fail", "missing", "bug": .systemRed
        case "example": .systemPurple
        case "quote", "cite": .systemGray
        default: .systemBlue
        }
    }

    /// Paragraph style that makes hidden lines take (almost) no vertical space.
    static let collapsed: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = 0.01
        p.maximumLineHeight = 0.01
        p.paragraphSpacing = 0
        p.paragraphSpacingBefore = 0
        return p
    }()

    /// Restyles the whole storage. `active` is the range of lines holding the selection.
    /// Returns image embeds (outside the active lines) that the editor should draw inline.
    @discardableResult
    func apply(to storage: NSTextStorage, active: NSRange) -> [PlacedEmbed] {
        let text = storage.string
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)
        let spans = MarkdownHighlighter.spans(text)
        for span in spans where span.kind != .marker { style(span, storage) }
        for span in spans where span.kind == .marker {
            let hide = livePreview && NSIntersectionRange(span.range, active).length == 0
                && !(span.range.location >= active.location && span.range.location <= NSMaxRange(active))
            storage.addAttribute(.netheriteMarker, value: true, range: span.range)
            if hide {
                storage.addAttributes([.font: PlatformFont.systemFont(ofSize: 0.01), .foregroundColor: PlatformColor.clear], range: span.range)
            } else {
                storage.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: span.range)
            }
        }
        let ns = text as NSString
        // Live Preview shows properties in the header above the text, so collapse the YAML unless the caret is in it.
        if livePreview, let fm = spans.first(where: { $0.kind == .frontmatter })?.range,
           NSIntersectionRange(fm, active).length == 0, !NSLocationInRange(active.location, fm) {
            storage.addAttributes([.font: PlatformFont.systemFont(ofSize: 0.01), .foregroundColor: PlatformColor.clear,
                                   .paragraphStyle: Self.collapsed, .netheriteMarker: true], range: fm)
        }
        var placed: [PlacedEmbed] = []
        if livePreview {
            placed += decorateLists(spans, ns, storage, active: active)
            collapseInactiveFences(spans, ns, storage, active: active)
        }
        if livePreview, let blockImage {
            for (range, kind) in blocks(spans, ns) {
                let lines = ns.lineRange(for: range)
                // A block only renders when it owns its lines and the caret is elsewhere.
                guard ns.substring(with: lines).trimmingCharacters(in: .whitespacesAndNewlines) == ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines),
                      NSIntersectionRange(lines, active).length == 0, !NSLocationInRange(lines.location, active),
                      let image = blockImage(kind) else { continue }
                let size = image.size
                let first = ns.lineRange(for: NSRange(location: lines.location, length: 0))
                storage.addAttributes([.font: PlatformFont.systemFont(ofSize: 0.01), .foregroundColor: PlatformColor.clear,
                                       .backgroundColor: PlatformColor.clear, .paragraphStyle: Self.collapsed], range: lines)
                let para = NSMutableParagraphStyle()
                para.minimumLineHeight = size.height + 12
                para.maximumLineHeight = size.height + 12
                storage.addAttribute(.paragraphStyle, value: para, range: first)
                placed.removeAll { NSLocationInRange($0.range.location, lines) }
                placed.append(PlacedEmbed(range: NSRange(location: lines.location, length: 0), kind: .image(image, label: Self.label(kind)), size: size))
            }
        }
        if livePreview, let embedImage {
            for span in spans {
                guard case .link(let target, true) = span.kind else { continue }
                // Images render only when the embed is the whole line (like a block); inline embeds stay links.
                let line = ns.lineRange(for: span.range)
                guard ns.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines) == ns.substring(with: span.range),
                      NSIntersectionRange(line, active).length == 0, !NSLocationInRange(line.location, active),
                      let image = embedImage(target) else { continue }
                // `![[img.png|300]]` / `|300x200` sets the size, like Obsidian.
                let inner = ns.substring(with: span.range)
                let alias = inner.contains("|") ? inner.split(separator: "|").last.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "]")) } : nil
                let dims = alias?.split(separator: "x").compactMap { Double($0) } ?? []
                var size = image.size
                if let w = dims.first, size.width > 0 { size = CGSize(width: w, height: dims.count > 1 ? dims[1] : w * size.height / size.width) }
                if size.width > maxEmbedWidth, size.width > 0 { size = CGSize(width: maxEmbedWidth, height: maxEmbedWidth * size.height / size.width) }
                storage.addAttributes([.font: PlatformFont.systemFont(ofSize: 0.01), .foregroundColor: PlatformColor.clear], range: line)
                let para = NSMutableParagraphStyle()
                para.minimumLineHeight = size.height + 12
                para.maximumLineHeight = size.height + 12
                storage.addAttribute(.paragraphStyle, value: para, range: line)
                placed.append(PlacedEmbed(range: NSRange(location: line.location, length: 0),
                                          kind: .image(image, label: String(localized: "Image: \((target as NSString).lastPathComponent)")), size: size))
            }
        }
        storage.endEditing()
        return placed
    }

    /// Spoken description of a rendered block.
    static func label(_ kind: BlockKind) -> String {
        switch kind {
        case .math(let tex): String(localized: "Equation: \(tex)")
        case .mermaid: String(localized: "Diagram")
        case .noteEmbed(let raw): String(localized: "Embedded note: \(raw.trimmingCharacters(in: CharacterSet(charactersIn: "![]")))")
        case .markdown(let md):
            md.hasPrefix(">")
                ? String(localized: "Callout: \(md.split(separator: "\n").first.map { $0.replacingOccurrences(of: #"^>\s*\[![\w-]+\][+-]?\s*"#, with: "", options: .regularExpression) } ?? "")")
                : String(localized: "Table")
        }
    }

    /// Block-level elements Live Preview can replace with a rendered image.
    private func blocks(_ spans: [StyleSpan], _ ns: NSString) -> [(NSRange, BlockKind)] {
        var out: [(NSRange, BlockKind)] = []
        for (i, span) in spans.enumerated() {
            switch span.kind {
            case .mathBlock:
                out.append((span.range, .math(String(ns.substring(with: span.range).dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines))))
            case .codeBlock:
                let block = ns.substring(with: span.range)
                guard block.hasPrefix("```mermaid") || block.hasPrefix("~~~mermaid") else { continue }
                var lines = block.components(separatedBy: "\n")
                lines.removeFirst()
                if let last = lines.last, last.hasPrefix("```") || last.hasPrefix("~~~") || last.isEmpty { lines.removeLast() }
                out.append((span.range, .mermaid(lines.joined(separator: "\n"))))
            case .link(let target, true) where target.isMarkdown || target.fileExtension.isEmpty:
                out.append((span.range, .noteEmbed(ns.substring(with: span.range))))
            case .table:
                out.append((span.range, .markdown(ns.substring(with: span.range))))
            case .callout:
                // Header plus the "> " body lines that follow it.
                var range = ns.lineRange(for: span.range)
                for next in spans[(i + 1)...] {
                    guard case .calloutBody = next.kind, next.range.location == NSMaxRange(range) else { continue }
                    range = NSUnionRange(range, next.range)
                }
                if range.length > 0, ns.character(at: NSMaxRange(range) - 1) == 10 { range.length -= 1 }
                out.append((range, .markdown(ns.substring(with: range))))
            default: continue
            }
        }
        return out
    }

    /// Replaces "- [ ]" with a real checkbox and "-"/"*"/"+" with a bullet on inactive lines.
    private func decorateLists(_ spans: [StyleSpan], _ ns: NSString, _ storage: NSTextStorage, active: NSRange) -> [PlacedEmbed] {
        var out: [PlacedEmbed] = []
        var taskLines = Set<Int>()
        let hidden: [NSAttributedString.Key: Any] = [.font: PlatformFont.systemFont(ofSize: 0.01), .foregroundColor: PlatformColor.clear, .netheriteMarker: true]
        func prepare(_ line: NSRange, prefixEnd: Int, room: CGFloat) -> CGFloat? {
            guard NSIntersectionRange(line, active).length == 0, !NSLocationInRange(line.location, active) else { return nil }
            let leading = ns.substring(with: line).prefix { $0 == " " || $0 == "\t" }
            let indent = CGFloat(leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }) * baseSize * 0.4
            var end = prefixEnd
            while end < NSMaxRange(line), ns.character(at: end) == 32 { end += 1 }
            storage.addAttributes(hidden, range: NSRange(location: line.location, length: end - line.location))
            let p = (storage.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle ?? paragraph).mutableCopy() as! NSMutableParagraphStyle
            p.firstLineHeadIndent = indent + room
            p.headIndent = indent + room
            storage.addAttribute(.paragraphStyle, value: p, range: line)
            return indent
        }
        for span in spans {
            guard case .task(let done) = span.kind else { continue }
            let line = ns.lineRange(for: span.range)
            taskLines.insert(line.location)
            if let indent = prepare(line, prefixEnd: NSMaxRange(span.range), room: baseSize * 1.6) {
                let text = ns.substring(with: line).replacingOccurrences(of: #"^\s*(?:[-*+]|\d+[.)])\s+\[.\]\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(PlacedEmbed(range: NSRange(location: line.location, length: 0), kind: .checkbox(done: done, label: text),
                                       size: CGSize(width: baseSize * 1.1, height: baseSize * 1.1), xOffset: indent))
            }
        }
        for span in spans where span.kind == .listMarker {
            let line = ns.lineRange(for: span.range)
            let marker = ns.substring(with: span.range)
            guard !taskLines.contains(line.location), ["-", "*", "+"].contains(marker) else { continue }
            if let indent = prepare(line, prefixEnd: NSMaxRange(span.range), room: baseSize * 1.2) {
                out.append(PlacedEmbed(range: NSRange(location: line.location, length: 0), kind: .bullet,
                                       size: CGSize(width: baseSize * 0.4, height: baseSize * 0.4), xOffset: indent + baseSize * 0.35))
            }
        }
        return out
    }

    /// Hides ``` fences of code blocks the caret isn't in (the block keeps its background).
    private func collapseInactiveFences(_ spans: [StyleSpan], _ ns: NSString, _ storage: NSTextStorage, active: NSRange) {
        for block in spans where block.kind == .codeBlock {
            let lines = ns.lineRange(for: block.range)
            guard NSIntersectionRange(lines, active).length == 0, !NSLocationInRange(lines.location, active) else { continue }
            for fence in spans where fence.kind == .codeFence && NSLocationInRange(fence.range.location, block.range) {
                storage.addAttributes([.font: PlatformFont.systemFont(ofSize: 0.01), .foregroundColor: PlatformColor.clear,
                                       .backgroundColor: PlatformColor.clear, .paragraphStyle: Self.collapsed],
                                      range: ns.lineRange(for: fence.range))
            }
        }
    }

    private func style(_ span: StyleSpan, _ s: NSTextStorage) {
        let r = span.range
        switch span.kind {
        case .heading(let level):
            let scale: [CGFloat] = [1.75, 1.45, 1.25, 1.1, 1.0, 0.95]
            s.addAttribute(.font, value: font(size: baseSize * scale[min(max(level, 1), 6) - 1], bold: true), range: r)
            if level >= 6 { s.addAttribute(.foregroundColor, value: PlatformColor.secondaryLabel, range: r) }
        case .bold: s.addAttribute(.font, value: currentFont(s, r).with(traits: .bold), range: r)
        case .italic: s.addAttribute(.font, value: currentFont(s, r).with(traits: .italic), range: r)
        case .strike:
            s.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: PlatformColor.secondaryLabel], range: r)
        case .highlight: s.addAttribute(.backgroundColor, value: highlightColor, range: r)
        case .inlineCode: s.addAttributes([.font: font(mono: true), .backgroundColor: PlatformColor.codeBackground], range: r)
        case .codeBlock: s.addAttributes([.font: font(mono: true), .backgroundColor: PlatformColor.codeBackground], range: r)
        case .codeFence: s.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: r)
        case .math, .mathBlock: s.addAttributes([.font: font(mono: true), .foregroundColor: linkColor], range: r)
        case .comment: s.addAttribute(.foregroundColor, value: PlatformColor.secondaryLabel, range: r)
        case .link(let target, _):
            s.addAttributes([.foregroundColor: linkColor, .netheriteLink: target,
                             .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: linkColor.withAlphaComponent(0.35)], range: r)
        case .url(let url):
            s.addAttribute(.foregroundColor, value: linkColor, range: r)
            if let u = URL(string: url) { s.addAttribute(.link, value: u, range: r) }
        case .tag:
            s.addAttributes([.foregroundColor: tagColor, .backgroundColor: tagColor.withAlphaComponent(0.12),
                             .netheriteTag: (s.string as NSString).substring(with: r)], range: r)
        case .quote:
            s.addAttributes([.foregroundColor: PlatformColor.secondaryLabel, .paragraphStyle: indented], range: r)
        case .callout(let type):
            // Title text in label colour: tinted system colours fall below 4.5:1 on light backgrounds; the tint stays on the fill.
            let c = Self.calloutColor(type)
            s.addAttributes([.foregroundColor: PlatformColor.label, .font: font(bold: true), .backgroundColor: c.withAlphaComponent(0.10),
                             .paragraphStyle: indented], range: r)
        case .table: break
        case .calloutBody(let type):
            s.addAttributes([.backgroundColor: Self.calloutColor(type).withAlphaComponent(0.06), .paragraphStyle: indented,
                             .foregroundColor: PlatformColor.label], range: r)
        case .listMarker: s.addAttribute(.foregroundColor, value: PlatformColor.accent, range: r)
        case .task(let done):
            s.addAttributes([.foregroundColor: done ? PlatformColor.accent : PlatformColor.secondaryLabel, .font: font(mono: true),
                             .netheriteTask: done], range: r)
            if done {
                let line = (s.string as NSString).lineRange(for: r)
                let rest = NSRange(location: NSMaxRange(r), length: NSMaxRange(line) - NSMaxRange(r))
                s.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: PlatformColor.secondaryLabel], range: rest)
            }
        case .rule: s.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: r)
        case .frontmatter:
            s.addAttributes([.font: font(size: baseSize * 0.9, mono: true), .foregroundColor: PlatformColor.secondaryLabel], range: r)
        case .footnoteRef: s.addAttributes([.foregroundColor: linkColor, .baselineOffset: 4, .font: font(size: baseSize * 0.75)], range: r)
        case .blockID: s.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: r)
        case .marker: break
        }
    }

    private func currentFont(_ s: NSTextStorage, _ r: NSRange) -> PlatformFont {
        (s.attribute(.font, at: r.location, effectiveRange: nil) as? PlatformFont) ?? font()
    }
}

extension PlatformFont {
    enum Trait { case bold, italic }
    func with(traits t: Trait) -> PlatformFont {
        #if os(macOS)
        let sym: NSFontDescriptor.SymbolicTraits = t == .bold ? .bold : .italic
        let d = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(sym))
        return NSFont(descriptor: d, size: pointSize) ?? self
        #else
        let sym: UIFontDescriptor.SymbolicTraits = t == .bold ? .traitBold : .traitItalic
        guard let d = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(sym)) else { return self }
        return UIFont(descriptor: d, size: pointSize)
        #endif
    }
}
