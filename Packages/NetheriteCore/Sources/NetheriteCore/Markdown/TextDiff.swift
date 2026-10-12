import Foundation

/// The smallest single replacement between two texts, in UTF-16 offsets (what NSTextView/UITextView use),
/// so an editor can apply an outside change as one undoable edit instead of replacing everything.
public enum TextDiff {
    /// Range of `old` to replace and the text to put there; nil when the texts are equal.
    public static func replacement(from old: String, to new: String) -> (range: NSRange, text: String)? {
        let a = Array(old.utf16), b = Array(new.utf16)
        guard a != b else { return nil }
        var start = 0
        while start < a.count, start < b.count, a[start] == b[start] { start += 1 }
        // Never split a surrogate pair.
        if start > 0, UTF16.isLeadSurrogate(a[start - 1]) { start -= 1 }
        var endA = a.count, endB = b.count
        while endA > start, endB > start, a[endA - 1] == b[endB - 1] { endA -= 1; endB -= 1 }
        if endA < a.count, UTF16.isTrailSurrogate(a[endA]) { endA += 1; endB += 1 }
        return (NSRange(location: start, length: endA - start), String(decoding: b[start..<endB], as: UTF16.self))
    }

    /// Where a selection ends up after `range` is replaced by `newLength` UTF-16 units.
    public static func adjust(_ selection: NSRange, replacing range: NSRange, newLength: Int) -> NSRange {
        if selection.location >= NSMaxRange(range) {
            return NSRange(location: selection.location + newLength - range.length, length: selection.length)
        }
        if NSMaxRange(selection) <= range.location { return selection }
        // Overlaps the change: collapse to a caret at the nearest edge that still exists.
        return NSRange(location: selection.location < range.location ? selection.location : range.location + newLength, length: 0)
    }
}
