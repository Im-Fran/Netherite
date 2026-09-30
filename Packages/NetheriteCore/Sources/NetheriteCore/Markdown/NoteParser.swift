import Foundation
import Yams

public struct NoteLink: Hashable, Sendable {
    /// Link target as written: "Note", "Folder/Note", "image.png". Empty means the current note.
    public var target: String
    /// Heading ("Heading") or block ("^id") part after `#`.
    public var subpath: String?
    public var alias: String?
    public var isEmbed: Bool
    /// True for `[[wikilinks]]`, false for `[text](path)`.
    public var isWiki: Bool
    /// UTF-16 range of the whole link in the note text.
    public var range: NSRange
    public var line: Int

    public var displayText: String { alias ?? (target.isEmpty ? (subpath ?? "") : target.noteName + (subpath.map { " > \($0)" } ?? "")) }
}

public struct Heading: Hashable, Sendable, Identifiable {
    public var level: Int
    public var text: String
    public var line: Int
    public var range: NSRange
    public var id: Int { line }
}

public struct Footnote: Hashable, Sendable, Identifiable {
    public var label: String
    public var text: String
    public var line: Int
    public var id: String { label }
}

public struct ParsedNote: Sendable, Hashable {
    public var properties: [Property] = []
    /// UTF-16 range of the frontmatter block including the `---` fences.
    public var frontmatterRange: NSRange?
    public var links: [NoteLink] = []
    /// Tags without `#`, in order of appearance (inline and `tags:` property).
    public var tags: [String] = []
    public var headings: [Heading] = []
    /// Block id → line
    public var blockIDs: [String: Int] = [:]
    public var footnotes: [Footnote] = []
    public var aliases: [String] = []
    public var words = 0
    public var characters = 0
    public var tasks = (open: 0, done: 0)

    public static func == (a: ParsedNote, b: ParsedNote) -> Bool {
        a.properties == b.properties && a.links == b.links && a.tags == b.tags && a.headings == b.headings
            && a.blockIDs == b.blockIDs && a.footnotes == b.footnotes && a.words == b.words && a.characters == b.characters
    }
    public func hash(into h: inout Hasher) { h.combine(links); h.combine(tags); h.combine(words) }

    public func property(_ key: String) -> PropertyValue? {
        properties.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }
}

/// Extracts Obsidian-Flavored-Markdown structure (links, tags, headings, blocks, properties) from note text.
/// Works on a "masked" copy where code, math and comments are blanked out, so offsets stay identical.
public enum NoteParser {
    public static func parse(_ text: String) -> ParsedNote {
        var note = ParsedNote()
        let ns = text as NSString
        var units = Array(text.utf16)

        // Frontmatter
        if let fm = Frontmatter.locate(in: text) {
            note.frontmatterRange = fm.range
            note.properties = Frontmatter.parse(fm.yaml)
            blank(&units, fm.range)
        }
        maskRegions(&units)
        let masked = String(utf16CodeUnits: units, count: units.count)
        let lineStarts = lineStartOffsets(units)
        func line(at loc: Int) -> Int { max(0, lineStarts.lastIndex { $0 <= loc } ?? 0) }

        // Links
        for m in Regex.wiki.matches(in: masked, range: NSRange(location: 0, length: units.count)) {
            let inner = ns.substring(with: m.range(at: 2)).replacingOccurrences(of: "\\|", with: "|")
            var link = splitWiki(inner, isEmbed: m.range(at: 1).length > 0)
            link.range = m.range
            link.line = line(at: m.range.location)
            note.links.append(link)
        }
        for m in Regex.mdLink.matches(in: masked, range: NSRange(location: 0, length: units.count)) {
            let raw = ns.substring(with: m.range(at: 3))
            // External URLs (any "scheme:") are not vault links.
            guard raw.range(of: #"^[A-Za-z][A-Za-z0-9+.\-]*:"#, options: .regularExpression) == nil else { continue }
            let decoded = raw.removingPercentEncoding ?? raw
            var parts = decoded.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let target = parts.removeFirst()
            let alias = ns.substring(with: m.range(at: 2))
            note.links.append(NoteLink(target: target, subpath: parts.first, alias: alias.isEmpty ? nil : alias,
                                       isEmbed: m.range(at: 1).length > 0, isWiki: false, range: m.range, line: line(at: m.range.location)))
        }
        // Links inside frontmatter string values ("related: [[Other]]")
        for prop in note.properties {
            for s in prop.value.strings {
                for m in Regex.wiki.matches(in: s, range: NSRange(location: 0, length: (s as NSString).length)) {
                    var link = splitWiki((s as NSString).substring(with: m.range(at: 2)), isEmbed: false)
                    link.range = NSRange(location: NSNotFound, length: 0)
                    note.links.append(link)
                }
            }
        }
        note.links.sort { ($0.range.location == NSNotFound ? -1 : $0.range.location) < ($1.range.location == NSNotFound ? -1 : $1.range.location) }

        // Tags: from properties then inline
        if let v = note.property("tags") ?? note.property("tag") {
            note.tags += v.strings.flatMap { $0.split(whereSeparator: { $0 == "," || $0 == " " }) }
                .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "# ")) }.filter { !$0.isEmpty }
        }
        if let v = note.property("aliases") ?? note.property("alias") { note.aliases = v.strings }
        for m in Regex.tag.matches(in: masked, range: NSRange(location: 0, length: units.count)) {
            let tag = ns.substring(with: m.range(at: 1))
            if tag.contains(where: { !$0.isNumber }) { note.tags.append(tag) }
        }

        // Headings, blocks, footnotes, tasks (line based on masked text)
        var idx = 0
        masked.enumerateLines { lineText, _ in
            defer { idx += 1 }
            let start = lineStarts[min(idx, lineStarts.count - 1)]
            let lns = lineText as NSString
            if let m = Regex.heading.firstMatch(in: lineText, range: NSRange(location: 0, length: lns.length)) {
                let title = lns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
                note.headings.append(Heading(level: m.range(at: 1).length, text: title, line: idx,
                                             range: NSRange(location: start, length: lns.length)))
            }
            if let m = Regex.blockID.firstMatch(in: lineText, range: NSRange(location: 0, length: lns.length)) {
                note.blockIDs[lns.substring(with: m.range(at: 1))] = idx
            }
            if let m = Regex.footnoteDef.firstMatch(in: lineText, range: NSRange(location: 0, length: lns.length)) {
                note.footnotes.append(Footnote(label: lns.substring(with: m.range(at: 1)), text: lns.substring(with: m.range(at: 2)), line: idx))
            }
            if let m = Regex.task.firstMatch(in: lineText, range: NSRange(location: 0, length: lns.length)) {
                if lns.substring(with: m.range(at: 1)) == " " { note.tasks.open += 1 } else { note.tasks.done += 1 }
            }
        }

        let body = note.frontmatterRange.map { ns.substring(from: NSMaxRange($0)) } ?? text
        (note.words, note.characters) = countWords(body)
        return note
    }

    public static func splitWiki(_ inner: String, isEmbed: Bool) -> NoteLink {
        var rest = inner, alias: String?
        if let bar = rest.firstIndex(of: "|") { alias = String(rest[rest.index(after: bar)...]); rest = String(rest[..<bar]) }
        var subpath: String?
        if let hash = rest.firstIndex(of: "#") { subpath = String(rest[rest.index(after: hash)...]); rest = String(rest[..<hash]) }
        return NoteLink(target: rest.trimmingCharacters(in: .whitespaces), subpath: subpath?.trimmingCharacters(in: .whitespaces),
                        alias: alias, isEmbed: isEmbed, isWiki: true, range: NSRange(location: 0, length: 0), line: 0)
    }

    public static func countWords(_ s: String) -> (words: Int, characters: Int) {
        var words = 0
        s.enumerateSubstrings(in: s.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
        return (words, s.count)
    }

    // MARK: Masking

    static func blank(_ u: inout [UInt16], _ r: NSRange) {
        for i in r.location..<min(NSMaxRange(r), u.count) where u[i] != 10 { u[i] = 32 }
    }

    /// Blanks fenced code, `$$` math blocks, inline code, inline math and `%%comments%%`.
    static func maskRegions(_ u: inout [UInt16]) {
        let s = String(utf16CodeUnits: u, count: u.count)
        for r in Regex.fenced.matches(in: s, range: NSRange(location: 0, length: u.count)) { blank(&u, r.range) }
        let s2 = String(utf16CodeUnits: u, count: u.count)
        for re in [Regex.mathBlock, Regex.comment, Regex.inlineCode, Regex.inlineMath] {
            for r in re.matches(in: s2, range: NSRange(location: 0, length: u.count)) { blank(&u, r.range) }
        }
    }

    public static func maskedText(_ text: String) -> String {
        var u = Array(text.utf16)
        if let fm = Frontmatter.locate(in: text) { blank(&u, fm.range) }
        maskRegions(&u)
        return String(utf16CodeUnits: u, count: u.count)
    }

    static func lineStartOffsets(_ u: [UInt16]) -> [Int] {
        var starts = [0]
        for (i, c) in u.enumerated() where c == 10 { starts.append(i + 1) }
        return starts
    }

    enum Regex {
        static let wiki = try! NSRegularExpression(pattern: #"(!?)\[\[([^\[\]\n]+?)\]\]"#)
        static let mdLink = try! NSRegularExpression(pattern: #"(!?)\[([^\]\n]*)\]\(<?([^)>\s]+)>?(?:\s+"[^"]*")?\)"#)
        static let tag = try! NSRegularExpression(pattern: #"(?:^|(?<=[\s(\[{,]))#([\p{L}\p{N}_\-/]+)"#, options: .anchorsMatchLines)
        static let heading = try! NSRegularExpression(pattern: #"^(#{1,6})\s+(.+?)\s*#*\s*$"#)
        static let blockID = try! NSRegularExpression(pattern: #"(?:^|\s)\^([A-Za-z0-9\-]+)\s*$"#)
        static let footnoteDef = try! NSRegularExpression(pattern: #"^\[\^([^\]]+)\]:\s*(.*)$"#)
        static let task = try! NSRegularExpression(pattern: #"^\s*(?:[-*+]|\d+[.)])\s+\[(.)\]"#)
        static let fenced = try! NSRegularExpression(pattern: #"^([ \t]*)(`{3,}|~{3,})[^\n]*\n[\s\S]*?(?:^\1\2[`~]*[ \t]*$|\z)"#, options: .anchorsMatchLines)
        static let mathBlock = try! NSRegularExpression(pattern: #"\$\$[\s\S]*?\$\$"#)
        static let comment = try! NSRegularExpression(pattern: #"%%[\s\S]*?%%"#)
        static let inlineCode = try! NSRegularExpression(pattern: #"(`+)[^`\n][\s\S]*?\1"#)
        static let inlineMath = try! NSRegularExpression(pattern: #"(?<![\\$])\$(?=\S)[^$\n]+?(?<=\S)\$(?!\d)"#)
    }
}
