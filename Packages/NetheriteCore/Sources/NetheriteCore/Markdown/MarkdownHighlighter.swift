import Foundation

/// Platform-free description of how to style Markdown source for Live Preview.
/// The editor maps each span kind to fonts/colors, and hides `.marker` spans outside the active line.
public struct StyleSpan: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case heading(Int)
        case bold, italic, strike, highlight
        case inlineCode, codeBlock, codeFence
        case math, mathBlock
        case comment
        case link(target: String, embed: Bool)
        case url(String)
        case tag
        case quote
        case callout(String)
        case calloutBody(String)
        /// A whole GFM table (header, separator and rows).
        case table
        case listMarker
        case task(done: Bool)
        case rule
        case frontmatter
        case footnoteRef
        case blockID
        /// Syntax characters (`**`, `[[`, `#`…) that Live Preview hides when the cursor is elsewhere.
        case marker
    }
    public var range: NSRange
    public var kind: Kind
    public init(_ range: NSRange, _ kind: Kind) { self.range = range; self.kind = kind }
}

public enum MarkdownHighlighter {
    public static func spans(_ text: String) -> [StyleSpan] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var out: [StyleSpan] = []
        var taken: [NSRange] = []   // regions closed to inline styling (code, math, comments, frontmatter)
        func free(_ r: NSRange) -> Bool { !taken.contains { NSIntersectionRange($0, r).length > 0 } }
        func each(_ re: NSRegularExpression, in range: NSRange = full, _ body: (NSTextCheckingResult) -> Void) {
            re.enumerateMatches(in: text, range: range) { m, _, _ in if let m { body(m) } }
        }

        if let fm = Frontmatter.locate(in: text) {
            out.append(.init(fm.range, .frontmatter)); taken.append(fm.range)
        }
        each(R.fenced) { m in
            guard free(m.range) else { return }
            out.append(.init(m.range, .codeBlock))
            let open = ns.lineRange(for: NSRange(location: m.range.location, length: 0))
            out.append(.init(NSIntersectionRange(open, m.range), .codeFence))
            let last = ns.lineRange(for: NSRange(location: max(m.range.location, NSMaxRange(m.range) - 1), length: 0))
            if last.location != open.location { out.append(.init(NSIntersectionRange(last, m.range), .codeFence)) }
            taken.append(m.range)
        }
        each(R.mathBlock) { m in guard free(m.range) else { return }; out.append(.init(m.range, .mathBlock)); taken.append(m.range) }
        each(R.comment) { m in guard free(m.range) else { return }; out.append(.init(m.range, .comment)); taken.append(m.range) }
        each(R.inlineCode) { m in
            guard free(m.range) else { return }
            out.append(.init(m.range, .inlineCode))
            out.append(.init(m.range(at: 1), .marker)); out.append(.init(m.range(at: 3), .marker))
            taken.append(m.range)
        }
        each(R.inlineMath) { m in guard free(m.range) else { return }; out.append(.init(m.range, .math)); taken.append(m.range) }

        // Block-level (line based)
        // Only the line prefix has to be outside code/math, so a quote line with `inline code` still counts.
        each(R.heading) { m in
            guard free(m.range(at: 1)) else { return }
            out.append(.init(m.range, .heading(m.range(at: 2).length)))
            out.append(.init(m.range(at: 1), .marker))
        }
        each(R.callout) { m in
            guard free(m.range(at: 1)) else { return }
            let type = ns.substring(with: m.range(at: 2)).lowercased()
            out.append(.init(m.range, .callout(type)))
            out.append(.init(m.range(at: 1), .marker))
            // Following "> " lines are the callout body.
            var next = NSMaxRange(ns.lineRange(for: m.range))
            while next < ns.length {
                let line = ns.lineRange(for: NSRange(location: next, length: 0))
                guard ns.substring(with: line).hasPrefix(">") else { break }
                out.append(.init(line, .calloutBody(type)))
                next = NSMaxRange(line)
            }
        }
        // Tables: a "|…" line followed by a separator row, then any further "|…" lines.
        var loc = 0
        while loc < ns.length {
            let line = ns.lineRange(for: NSRange(location: loc, length: 0))
            let next = NSMaxRange(line)
            if ns.substring(with: line).trimmingCharacters(in: .whitespaces).hasPrefix("|"), next < ns.length, free(line) {
                let sep = ns.lineRange(for: NSRange(location: next, length: 0))
                if ns.substring(with: sep).range(of: #"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$"#, options: .regularExpression) != nil {
                    var end = NSMaxRange(sep)
                    while end < ns.length {
                        let row = ns.lineRange(for: NSRange(location: end, length: 0))
                        guard ns.substring(with: row).trimmingCharacters(in: .whitespaces).hasPrefix("|") else { break }
                        end = NSMaxRange(row)
                    }
                    var r = NSRange(location: line.location, length: end - line.location)
                    if r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 10 { r.length -= 1 }
                    out.append(.init(r, .table))
                    loc = end
                    continue
                }
            }
            loc = max(next, loc + 1)
        }
        each(R.quote) { m in guard free(m.range(at: 1)) else { return }; out.append(.init(m.range, .quote)); out.append(.init(m.range(at: 1), .marker)) }
        each(R.task) { m in guard free(m.range(at: 1)) else { return }; out.append(.init(m.range(at: 1), .task(done: ns.substring(with: m.range(at: 2)) != " "))) }
        each(R.list) { m in guard free(m.range(at: 1)) else { return }; out.append(.init(m.range(at: 1), .listMarker)) }
        each(R.rule) { m in guard free(m.range) else { return }; out.append(.init(m.range, .rule)) }
        each(R.blockID) { m in guard free(m.range(at: 1)) else { return }; out.append(.init(m.range(at: 1), .blockID)) }

        // Links first so emphasis inside aliases still works, but link syntax isn't mistaken for emphasis.
        each(R.wiki) { m in
            guard free(m.range) else { return }
            let inner = ns.substring(with: m.range(at: 2))
            let target = NoteParser.splitWiki(inner, isEmbed: false).target
            out.append(.init(m.range, .link(target: target, embed: m.range(at: 1).length == 3)))
            out.append(.init(m.range(at: 1), .marker)); out.append(.init(m.range(at: 3), .marker))
            if m.range(at: 1).length == 2, let bar = inner.firstIndex(of: "|") {   // hide "target|" and show only the alias
                let len = inner.utf16.distance(from: inner.startIndex, to: bar) + 1
                out.append(.init(NSRange(location: m.range(at: 2).location, length: len), .marker))
            }
            taken.append(m.range(at: 1)); taken.append(m.range(at: 3))
        }
        each(R.mdLink) { m in
            guard free(m.range) else { return }
            let url = ns.substring(with: m.range(at: 4))
            let isExternal = url.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*:"#, options: .regularExpression) != nil
            out.append(.init(m.range, isExternal ? .url(url) : .link(target: url.removingPercentEncoding ?? url, embed: m.range(at: 1).length > 0)))
            out.append(.init(m.range(at: 1), .marker)); out.append(.init(m.range(at: 3), .marker))
            taken.append(m.range(at: 3))
        }
        each(R.bareURL) { m in guard free(m.range) else { return }; out.append(.init(m.range, .url(ns.substring(with: m.range)))) }
        each(R.tag) { m in guard free(m.range) else { return }; if ns.substring(with: m.range(at: 1)).contains(where: { !$0.isNumber }) { out.append(.init(m.range, .tag)) } }
        each(R.footnoteRef) { m in guard free(m.range) else { return }; out.append(.init(m.range, .footnoteRef)) }

        for (re, kind) in [(R.bold, StyleSpan.Kind.bold), (R.strike, .strike), (R.highlight, .highlight), (R.italic, .italic)] {
            each(re) { m in
                guard free(m.range) else { return }
                out.append(.init(m.range, kind))
                out.append(.init(m.range(at: 1), .marker)); out.append(.init(m.range(at: 3), .marker))
                if kind == .bold { taken.append(m.range(at: 1)); taken.append(m.range(at: 3)) }
            }
        }
        return out
    }

    enum R {
        static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: .anchorsMatchLines) }
        static let fenced = NoteParser.Regex.fenced
        static let mathBlock = NoteParser.Regex.mathBlock
        static let comment = NoteParser.Regex.comment
        static let inlineCode = re(#"(`+)([^`\n](?:.*?[^`\n])??)(\1)"#)
        static let inlineMath = NoteParser.Regex.inlineMath
        static let heading = re(#"^((#{1,6})[ \t]+).*$"#)
        static let callout = re(#"^(>[ \t]*\[!([\w-]+)\][+-]?[ \t]*).*$"#)
        static let quote = re(#"^(>[ \t]?).*$"#)
        static let task = re(#"^[ \t]*(?:[-*+]|\d+[.)])[ \t]+(\[(.)\])"#)
        static let list = re(#"^[ \t]*([-*+]|\d+[.)])[ \t]+"#)
        static let rule = re(#"^(?:-{3,}|\*{3,}|_{3,})[ \t]*$"#)
        static let blockID = re(#"[ \t](\^[A-Za-z0-9\-]+)[ \t]*$"#)
        static let wiki = re(#"(!?\[\[)([^\[\]\n]+?)(\]\])"#)
        static let mdLink = re(#"(!?\[)([^\]\n]*)(\]\(<?([^)>\s]+)>?(?:[ \t]+"[^"]*")?\))"#)
        static let bareURL = re(#"(?<![(<\[])\bhttps?://[^\s<>()\[\]]+[^\s<>()\[\].,;:!?'"]"#)
        static let tag = NoteParser.Regex.tag
        static let footnoteRef = re(#"\[\^[^\]\s]+\](?!:)"#)
        static let bold = re(#"(\*\*|__)(?=\S)(.+?)(?<=\S)(\1)"#)
        static let italic = re(#"(?<![*_\w\\])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_\\])(\1)(?![*_\w])"#)
        static let strike = re(#"(~~)(?=\S)(.+?)(?<=\S)(~~)"#)
        static let highlight = re(#"(==)(?=\S)(.+?)(?<=\S)(==)"#)
    }
}
