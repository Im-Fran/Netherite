import SwiftUI
import NetheriteCore

/// Live Preview Markdown editor on TextKit 2 (NSTextView on macOS, UITextView on iOS).
struct MarkdownTextView {
    var text: String
    var theme: Theme
    var livePreview: Bool
    var readableWidth: Bool
    var spellcheck: Bool
    var controller: EditorController
    var onChange: (String) -> Void
    /// (link target, open in new pane)
    var onOpenLink: (String, Bool) -> Void
    var onOpenTag: (String) -> Void

    static let maxLineWidth: CGFloat = 720

    @MainActor
    final class Coordinator: NSObject {
        var parent: MarkdownTextView
        var active = NSRange(location: NSNotFound, length: 0)
        var updating = false

        init(_ parent: MarkdownTextView) { self.parent = parent }

        var styler: EditorStyler { EditorStyler(theme: parent.theme, livePreview: parent.livePreview) }

        func restyle(_ tv: PlatformTextView, force: Bool = false) {
            #if os(macOS)
            guard let storage = tv.textStorage else { return }
            let sel = tv.selectedRange()
            #else
            let storage = tv.textStorage
            let sel = tv.selectedRange
            #endif
            let lines = (storage.string as NSString).lineRange(for: NSRange(location: min(sel.location, storage.length), length: sel.length))
            guard force || lines != active else { return }
            active = lines
            updating = true
            styler.apply(to: storage, active: lines)
            #if os(macOS)
            tv.typingAttributes = styler.baseAttributes
            #else
            tv.typingAttributes = styler.baseAttributes
            #endif
            updating = false
        }

        func caretRect(_ tv: PlatformTextView) -> CGRect {
            #if os(macOS)
            guard let window = tv.window, let scroll = tv.enclosingScrollView else { return .zero }
            let screen = tv.firstRect(forCharacterRange: tv.selectedRange(), actualRange: nil)
            let inWindow = window.convertFromScreen(screen)
            let local = scroll.convert(inWindow, from: nil)
            return CGRect(x: local.minX, y: scroll.bounds.height - local.maxY, width: max(1, local.width), height: local.height)
            #else
            guard let pos = tv.selectedTextRange?.end else { return .zero }
            return tv.caretRect(for: pos).offsetBy(dx: -tv.contentOffset.x, dy: -tv.contentOffset.y)
            #endif
        }

        func textChanged(_ tv: PlatformTextView) {
            guard !updating else { return }
            restyle(tv, force: true)
            parent.onChange(tv.string)
            parent.controller.updateCompletion(caret: caretRect(tv))
        }

        func selectionChanged(_ tv: PlatformTextView) {
            guard !updating else { return }
            restyle(tv)
            parent.controller.updateCompletion(caret: caretRect(tv))
        }

        /// Handles a click/tap at a character index; returns true when it opened a link or toggled a task.
        func activate(_ tv: PlatformTextView, at index: Int, modifier: Bool) -> Bool {
            #if os(macOS)
            guard let storage = tv.textStorage else { return false }
            #else
            let storage = tv.textStorage
            #endif
            guard index >= 0, index < storage.length else { return false }
            let attrs = storage.attributes(at: index, effectiveRange: nil)
            let inActive = NSLocationInRange(index, active) && parent.livePreview
            if attrs[.netheriteTask] != nil {
                parent.controller.toggleTask(at: index)
                return true
            }
            if let target = attrs[.netheriteLink] as? String, !inActive || modifier {
                parent.onOpenLink(target, modifier)
                return true
            }
            if let tag = attrs[.netheriteTag] as? String, !inActive || modifier {
                parent.onOpenTag(tag)
                return true
            }
            if let url = attrs[.link] as? URL, !inActive || modifier {
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                UIApplication.shared.open(url)
                #endif
                return true
            }
            return false
        }
    }

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(self) }
}

#if os(macOS)
final class NetheriteNSTextView: NSTextView {
    weak var coordinator: MarkdownTextView.Coordinator?
    var readableWidth = true

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
    }

    func updateInsets() {
        let side = readableWidth ? max(24, (bounds.width - MarkdownTextView.maxLineWidth) / 2) : 24
        if textContainerInset.width != side { textContainerInset = NSSize(width: side, height: 20) }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let cmd = event.modifierFlags.contains(.command)
        // characterIndexForInsertion returns the gap; test the glyph under the pointer too.
        for i in [index, index - 1] where i >= 0 {
            if let rect = firstRectForCharacter(i), rect.contains(point),
               coordinator?.activate(self, at: i, modifier: cmd) == true { return }
        }
        super.mouseDown(with: event)
    }

    private func firstRectForCharacter(_ i: Int) -> NSRect? {
        guard let window else { return nil }
        let screen = firstRect(forCharacterRange: NSRange(location: i, length: 1), actualRange: nil)
        let r = convert(window.convertFromScreen(screen), from: nil)
        return r.insetBy(dx: -1, dy: -2)
    }
}

extension MarkdownTextView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let tv = NetheriteNSTextView(usingTextLayoutManager: true)
        tv.coordinator = context.coordinator
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.setAccessibilityLabel(String(localized: "Note editor"))
        scroll.documentView = tv
        configure(tv, context: context)
        tv.string = text
        context.coordinator.restyle(tv, force: true)
        controller.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NetheriteNSTextView else { return }
        let themeChanged = context.coordinator.parent.theme != theme || context.coordinator.parent.livePreview != livePreview
        context.coordinator.parent = self
        controller.textView = tv
        configure(tv, context: context)
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(sel.location, (text as NSString).length), length: 0))
            context.coordinator.restyle(tv, force: true)
        } else if themeChanged {
            context.coordinator.restyle(tv, force: true)
        }
    }

    private func configure(_ tv: NetheriteNSTextView, context: Context) {
        tv.readableWidth = readableWidth
        tv.isContinuousSpellCheckingEnabled = spellcheck
        tv.updateInsets()
    }
}

extension MarkdownTextView.Coordinator: NSTextViewDelegate {
    func textDidChange(_ n: Notification) { if let tv = n.object as? NSTextView { textChanged(tv) } }
    func textViewDidChangeSelection(_ n: Notification) { if let tv = n.object as? NSTextView { selectionChanged(tv) } }

    func textView(_ tv: NSTextView, doCommandBy selector: Selector) -> Bool {
        let c = parent.controller
        switch selector {
        case #selector(NSResponder.moveUp(_:)): return c.handleCompletionKey(.up)
        case #selector(NSResponder.moveDown(_:)): return c.handleCompletionKey(.down)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            if c.handleCompletionKey(.accept) { return true }
            return selector == #selector(NSResponder.insertNewline(_:)) ? continueList(tv) : false
        case #selector(NSResponder.cancelOperation(_:)): return c.handleCompletionKey(.cancel)
        default: return false
        }
    }

    /// Pressing Return in a list continues it ("- ", "1. ", "- [ ] "); on an empty item it ends the list.
    func continueList(_ tv: NSTextView) -> Bool {
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        guard sel.length == 0 else { return false }
        let line = ns.lineRange(for: NSRange(location: sel.location, length: 0))
        let current = ns.substring(with: NSRange(location: line.location, length: sel.location - line.location))
        return ListContinuation.handle(current, lineStart: line.location, caret: sel.location, controller: parent.controller)
    }
}
#else
final class NetheriteUITextView: UITextView {
    var readableWidth = true
    override func layoutSubviews() {
        super.layoutSubviews()
        let side = readableWidth ? max(16, (bounds.width - MarkdownTextView.maxLineWidth) / 2) : 16
        if textContainerInset.left != side { textContainerInset = UIEdgeInsets(top: 16, left: side, bottom: 120, right: side) }
    }
}

extension MarkdownTextView: UIViewRepresentable {
    func makeUIView(context: Context) -> NetheriteUITextView {
        let tv = NetheriteUITextView(usingTextLayoutManager: true)
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.autocapitalizationType = .sentences
        tv.accessibilityLabel = String(localized: "Note editor")
        tv.text = text
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        tv.addGestureRecognizer(tap)
        tv.inputAccessoryView = nil
        configure(tv)
        context.coordinator.restyle(tv, force: true)
        controller.textView = tv
        return tv
    }

    func updateUIView(_ tv: NetheriteUITextView, context: Context) {
        let themeChanged = context.coordinator.parent.theme != theme || context.coordinator.parent.livePreview != livePreview
        context.coordinator.parent = self
        controller.textView = tv
        configure(tv)
        if tv.text != text {
            let sel = tv.selectedRange
            tv.text = text
            tv.selectedRange = NSRange(location: min(sel.location, (text as NSString).length), length: 0)
            context.coordinator.restyle(tv, force: true)
        } else if themeChanged {
            context.coordinator.restyle(tv, force: true)
        }
    }

    private func configure(_ tv: NetheriteUITextView) {
        tv.readableWidth = readableWidth
        tv.spellCheckingType = spellcheck ? .yes : .no
        tv.setNeedsLayout()
    }
}

extension MarkdownTextView.Coordinator: UITextViewDelegate, UIGestureRecognizerDelegate {
    func textViewDidChange(_ tv: UITextView) { textChanged(tv) }
    func textViewDidChangeSelection(_ tv: UITextView) { selectionChanged(tv) }

    func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard text == "\n", range.length == 0 else { return true }
        let ns = tv.text as NSString
        let line = ns.lineRange(for: NSRange(location: range.location, length: 0))
        let current = ns.substring(with: NSRange(location: line.location, length: range.location - line.location))
        return !ListContinuation.handle(current, lineStart: line.location, caret: range.location, controller: parent.controller)
    }

    @objc func tapped(_ g: UITapGestureRecognizer) {
        guard let tv = g.view as? UITextView else { return }
        var p = g.location(in: tv)
        p.x -= tv.textContainerInset.left; p.y -= tv.textContainerInset.top
        guard let tlm = tv.textLayoutManager,
              let frag = tlm.textLayoutFragment(for: p),
              let range = frag.textElement?.elementRange else { return }
        let docStart = tlm.documentRange.location
        let base = tlm.offset(from: docStart, to: range.location)
        let local = CGPoint(x: p.x - frag.layoutFragmentFrame.minX, y: p.y - frag.layoutFragmentFrame.minY)
        for line in frag.textLineFragments where line.typographicBounds.contains(local) {
            let idx = line.characterIndex(for: CGPoint(x: local.x - line.typographicBounds.minX, y: local.y - line.typographicBounds.minY))
            _ = activate(tv, at: base + idx, modifier: false)
            return
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
#endif

/// Continues Markdown lists on Return.
@MainActor
enum ListContinuation {
    static let re = try! NSRegularExpression(pattern: #"^([ \t]*)([-*+] \[.\] |[-*+] |(\d+)([.)]) |> )(.*)$"#)

    static func handle(_ lineBeforeCaret: String, lineStart: Int, caret: Int, controller: EditorController) -> Bool {
        let ns = lineBeforeCaret as NSString
        guard let m = re.firstMatch(in: lineBeforeCaret, range: NSRange(location: 0, length: ns.length)) else { return false }
        let indent = ns.substring(with: m.range(at: 1))
        var marker = ns.substring(with: m.range(at: 2))
        let rest = ns.substring(with: m.range(at: 5))
        if rest.trimmingCharacters(in: .whitespaces).isEmpty {
            // Empty item: remove the marker and end the list.
            controller.replace(NSRange(location: lineStart, length: caret - lineStart), with: "")
            return true
        }
        if m.range(at: 3).location != NSNotFound, let n = Int(ns.substring(with: m.range(at: 3))) {
            marker = "\(n + 1)\(ns.substring(with: m.range(at: 4))) "
        } else if marker.contains("[") {
            marker = String(marker.prefix(1)) + " [ ] "
        }
        controller.insert("\n" + indent + marker)
        return true
    }
}
