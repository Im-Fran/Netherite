import SwiftUI
import NetheriteCore

#if os(macOS)
typealias PlatformTextView = NSTextView
#else
typealias PlatformTextView = UITextView
extension UITextView {
    var string: String { text ?? "" }
}
#endif

/// Imperative handle on the editor used by toolbars, menus, the command palette and completions.
@MainActor @Observable
final class EditorController {
    struct Completion: Equatable {
        enum Kind { case link, embed, tag, slash }
        var kind: Kind
        var query: String
        /// Range to replace, including the trigger (`[[`, `#`, `/`).
        var range: NSRange
        var caret: CGRect
    }

    @ObservationIgnored weak var textView: PlatformTextView?
    var completion: Completion?
    var completionIndex = 0
    var completionCount = 0
    @ObservationIgnored var acceptCompletion: (() -> Void)?

    var text: String { textView?.string ?? "" }
    var selectedRange: NSRange {
        get {
            #if os(macOS)
            textView?.selectedRange() ?? NSRange(location: 0, length: 0)
            #else
            textView?.selectedRange ?? NSRange(location: 0, length: 0)
            #endif
        }
        set {
            #if os(macOS)
            textView?.setSelectedRange(newValue)
            #else
            textView?.selectedRange = newValue
            #endif
        }
    }
    var selectedText: String { (text as NSString).substring(with: selectedRange) }

    /// Replaces `range` through the text view so it participates in undo.
    func replace(_ range: NSRange, with string: String, select: NSRange? = nil) {
        guard let tv = textView else { return }
        #if os(macOS)
        if tv.shouldChangeText(in: range, replacementString: string) {
            tv.textStorage?.replaceCharacters(in: range, with: string)
            tv.didChangeText()
        }
        #else
        if let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
           let end = tv.position(from: start, offset: range.length),
           let r = tv.textRange(from: start, to: end) {
            tv.replace(r, withText: string)
        }
        #endif
        selectedRange = select ?? NSRange(location: range.location + (string as NSString).length, length: 0)
    }

    func insert(_ s: String) { replace(selectedRange, with: s) }

    /// Wraps the selection with markers (bold, italic…) or removes them if already wrapped.
    func wrap(_ prefix: String, _ suffix: String? = nil) {
        let suffix = suffix ?? prefix
        let r = selectedRange, ns = text as NSString
        let p = (prefix as NSString).length, s = (suffix as NSString).length
        if r.location >= p, NSMaxRange(r) + s <= ns.length,
           ns.substring(with: NSRange(location: r.location - p, length: p)) == prefix,
           ns.substring(with: NSRange(location: NSMaxRange(r), length: s)) == suffix {
            let outer = NSRange(location: r.location - p, length: r.length + p + s)
            replace(outer, with: ns.substring(with: r), select: NSRange(location: outer.location, length: r.length))
        } else {
            replace(r, with: prefix + ns.substring(with: r) + suffix, select: NSRange(location: r.location + p, length: r.length))
        }
        focus()
    }

    /// Sets (or toggles off) a line prefix such as "# ", "- ", "> ", "- [ ] " on every selected line.
    func toggleLinePrefix(_ prefix: String) {
        let ns = text as NSString
        let lines = ns.lineRange(for: selectedRange)
        let block = ns.substring(with: lines)
        let strip = try! NSRegularExpression(pattern: #"^(#{1,6} |[-*+] \[.\] |[-*+] |\d+\. |> )"#, options: .anchorsMatchLines)
        let parts = block.components(separatedBy: "\n")
        let allHave = parts.filter { !$0.isEmpty }.allSatisfy { $0.hasPrefix(prefix) }
        let out = parts.enumerated().map { i, line -> String in
            if line.isEmpty && i == parts.count - 1 { return line }
            let bare = strip.stringByReplacingMatches(in: line, range: NSRange(location: 0, length: (line as NSString).length), withTemplate: "")
            return allHave ? bare : prefix + bare
        }.joined(separator: "\n")
        replace(lines, with: out, select: NSRange(location: lines.location, length: (out as NSString).length - (out.hasSuffix("\n") ? 1 : 0)))
        focus()
    }

    /// Toggles `- [ ]` ↔ `- [x]` on the line at `location`.
    func toggleTask(at location: Int) {
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: location, length: 0))
        let s = ns.substring(with: line) as NSString
        let r = s.range(of: #"\[(.)\]"#, options: .regularExpression)
        guard r.location != NSNotFound else { return }
        let done = s.substring(with: NSRange(location: r.location + 1, length: 1)) != " "
        let keep = selectedRange
        replace(NSRange(location: line.location + r.location + 1, length: 1), with: done ? " " : "x", select: keep)
    }

    func scrollTo(line: Int) {
        let ns = text as NSString
        var loc = 0
        for _ in 0..<line { let r = ns.lineRange(for: NSRange(location: loc, length: 0)); if NSMaxRange(r) >= ns.length { break }; loc = NSMaxRange(r) }
        let range = NSRange(location: loc, length: 0)
        selectedRange = range
        #if os(macOS)
        textView?.scrollRangeToVisible(ns.lineRange(for: range))
        #else
        textView?.scrollRangeToVisible(ns.lineRange(for: range))
        #endif
        focus()
    }

    func focus() {
        #if os(macOS)
        if let tv = textView { tv.window?.makeFirstResponder(tv) }
        #else
        textView?.becomeFirstResponder()
        #endif
    }

    /// Replaces the active completion trigger + query with `replacement`, swallowing an auto-inserted `]]`.
    func complete(with replacement: String, cursorOffsetFromEnd: Int = 0) {
        guard let c = completion else { return }
        var range = c.range
        let ns = text as NSString
        if c.kind == .link || c.kind == .embed, NSMaxRange(range) + 2 <= ns.length,
           ns.substring(with: NSRange(location: NSMaxRange(range), length: 2)) == "]]" { range.length += 2 }
        completion = nil
        let end = range.location + (replacement as NSString).length - cursorOffsetFromEnd
        replace(range, with: replacement, select: NSRange(location: end, length: 0))
    }

    // MARK: Completion detection

    static let linkTrigger = try! NSRegularExpression(pattern: #"(!?)\[\[([^\[\]\n]*)$"#)
    static let tagTrigger = try! NSRegularExpression(pattern: #"(?:^|\s)(#[\p{L}\p{N}_\-/]*)$"#)
    static let slashTrigger = try! NSRegularExpression(pattern: #"(?:^|\s)(/[\p{L}\p{N} ]{0,20})$"#)

    /// Looks at the text before the caret to decide whether to show a completion list.
    func updateCompletion(caret: CGRect) {
        let r = selectedRange
        guard r.length == 0 else { completion = nil; return }
        let ns = text as NSString
        let line = ns.lineRange(for: NSRange(location: r.location, length: 0))
        let before = ns.substring(with: NSRange(location: line.location, length: r.location - line.location))
        let bns = before as NSString
        let full = NSRange(location: 0, length: bns.length)
        var next: Completion?
        if let m = Self.linkTrigger.firstMatch(in: before, range: full) {
            next = Completion(kind: m.range(at: 1).length > 0 ? .embed : .link, query: bns.substring(with: m.range(at: 2)),
                              range: NSRange(location: line.location + m.range.location, length: m.range.length), caret: caret)
        } else if let m = Self.tagTrigger.firstMatch(in: before, range: full), m.range(at: 1).length > 1 {
            next = Completion(kind: .tag, query: String(bns.substring(with: m.range(at: 1)).dropFirst()),
                              range: NSRange(location: line.location + m.range(at: 1).location, length: m.range(at: 1).length), caret: caret)
        } else if let m = Self.slashTrigger.firstMatch(in: before, range: full) {
            next = Completion(kind: .slash, query: String(bns.substring(with: m.range(at: 1)).dropFirst()),
                              range: NSRange(location: line.location + m.range(at: 1).location, length: m.range(at: 1).length), caret: caret)
        }
        if next?.kind != completion?.kind || next?.query != completion?.query { completionIndex = 0 }
        completion = next
    }

    /// Keyboard navigation for the completion list; returns true when handled.
    func handleCompletionKey(_ key: CompletionKey) -> Bool {
        guard completion != nil, completionCount > 0 else { return false }
        switch key {
        case .up: completionIndex = (completionIndex - 1 + completionCount) % completionCount
        case .down: completionIndex = (completionIndex + 1) % completionCount
        case .accept: acceptCompletion?()
        case .cancel: completion = nil
        }
        return true
    }
    enum CompletionKey { case up, down, accept, cancel }
}
