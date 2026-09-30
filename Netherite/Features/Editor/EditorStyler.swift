import SwiftUI
import NetheriteCore

extension NSAttributedString.Key {
    static let netheriteLink = NSAttributedString.Key("netherite.link")      // String: raw link target
    static let netheriteTask = NSAttributedString.Key("netherite.task")      // Bool: checkbox done state
    static let netheriteTag = NSAttributedString.Key("netherite.tag")        // String: tag text
    static let netheriteMarker = NSAttributedString.Key("netherite.marker")  // Bool: hideable syntax
}

/// Maps `MarkdownHighlighter` spans to text attributes. Markers outside the active lines are collapsed
/// (Live Preview); inside them they're shown dimmed so the syntax stays editable.
@MainActor
struct EditorStyler {
    var theme: Theme
    var livePreview = true

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

    /// Restyles the whole storage. `active` is the range of lines holding the selection.
    func apply(to storage: NSTextStorage, active: NSRange) {
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
        storage.endEditing()
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
        case .comment: s.addAttribute(.foregroundColor, value: PlatformColor.tertiaryLabel, range: r)
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
            let p = paragraph.mutableCopy() as! NSMutableParagraphStyle
            p.firstLineHeadIndent = baseSize; p.headIndent = baseSize
            s.addAttributes([.foregroundColor: PlatformColor.secondaryLabel, .paragraphStyle: p], range: r)
        case .callout(let type):
            let c = Self.calloutColor(type)
            s.addAttributes([.foregroundColor: c, .font: font(bold: true), .backgroundColor: c.withAlphaComponent(0.08)], range: r)
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
