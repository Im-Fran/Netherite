import Foundation

/// Templates, daily notes and unique notes. Formats accept both Unicode (`yyyy-MM-dd`) and
/// Obsidian/Moment tokens (`YYYY-MM-DD`, `dddd`, `A`), so settings copied from Obsidian work.
public enum Templates {
    @MainActor
    public static func list(in index: VaultIndex, folder: String) -> [String] {
        guard !folder.isEmpty else { return [] }
        return index.markdownFiles.filter { $0.hasPrefix(folder + "/") }
    }

    /// Replaces `{{title}}`, `{{date}}`, `{{time}}`, `{{date:FORMAT}}`, `{{time:FORMAT}}` and `{{attendees}}` (comma separated).
    public static func render(_ template: String, title: String, date: Date = .now, attendees: [String] = []) -> String {
        let re = try! NSRegularExpression(pattern: #"\{\{\s*(title|date|time|attendees)(?::([^}]*))?\s*\}\}"#, options: .caseInsensitive)
        let ns = template as NSString
        var out = "", last = 0
        for m in re.matches(in: template, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let key = ns.substring(with: m.range(at: 1)).lowercased()
            let fmt = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces) : nil
            switch key {
            case "title": out += title
            case "date": out += format(date, fmt ?? "yyyy-MM-dd")
            case "attendees": out += attendees.joined(separator: ", ")
            default: out += format(date, fmt ?? "HH:mm")
            }
            last = NSMaxRange(m.range)
        }
        return out + ns.substring(from: last)
    }

    public static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = unicodePattern(pattern)
        return f.string(from: date)
    }

    /// Converts Moment.js tokens to Unicode date-format tokens (no-op for Unicode patterns).
    public static func unicodePattern(_ p: String) -> String {
        guard p.contains("Y") || p.contains("[") || p.contains("D") || p.contains("A") || p.contains("dddd") else { return p }
        let map: [(String, String)] = [("YYYY", "yyyy"), ("YY", "yy"), ("dddd", "EEEE"), ("ddd", "EEE"), ("DD", "dd"), ("Do", "d"), ("D", "d"), ("A", "a"), ("X", "")]
        var out = "", i = p.startIndex
        outer: while i < p.endIndex {
            if p[i] == "[" , let close = p[i...].firstIndex(of: "]") {       // [literal]
                out += "'" + p[p.index(after: i)..<close] + "'"; i = p.index(after: close); continue
            }
            for (from, to) in map where p[i...].hasPrefix(from) { out += to; i = p.index(i, offsetBy: from.count); continue outer }
            out.append(p[i]); i = p.index(after: i)
        }
        return out
    }

    public static func dailyNotePath(for date: Date, settings: VaultSettings) -> String {
        let name = format(date, settings.dailyNotes.format)
        let folder = settings.dailyNotes.folder
        return (folder.isEmpty ? name : "\(folder)/\(name)") + ".md"
    }

    public static func uniqueNoteName(for date: Date, settings: VaultSettings) -> String {
        format(date, settings.uniqueNote.format)
    }
}
