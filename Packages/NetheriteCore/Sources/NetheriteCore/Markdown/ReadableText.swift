import Foundation

extension NoteParser {
    /// One line of a note with its vault links shown as their text: `Back to [[Home|start]]` → `Back to start`.
    /// Used for mention context, where raw `[[…]]` syntax is noise.
    public static func readableLine(_ line: String) -> String {
        let out = NSMutableString(string: line)
        for link in parse(line).links.reversed() where link.range.location != NSNotFound {
            out.replaceCharacters(in: link.range, with: link.displayText)
        }
        return out as String
    }
}
