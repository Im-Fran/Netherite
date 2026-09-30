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
    var embedImage: ((String) -> PlatformImage?)? = nil
    var blockImage: ((EditorStyler.BlockKind) -> PlatformImage?)? = nil
    /// Changes when the vault's file set changes, so embeds re-resolve.
    var styleToken = 0
    /// SwiftUI header (inline title + properties) placed above the text, scrolling with it.
    var header: AnyView? = nil
    var headerHeight: CGFloat = 0

    static let maxLineWidth: CGFloat = 720

    @MainActor
    final class Coordinator: NSObject {
        var parent: MarkdownTextView
        var active = NSRange(location: NSNotFound, length: 0)
        var updating = false

        init(_ parent: MarkdownTextView) { self.parent = parent }

        var styler: EditorStyler { EditorStyler(theme: parent.theme, livePreview: parent.livePreview, embedImage: parent.embedImage, blockImage: parent.blockImage) }
        var placed: [PlacedEmbed] = []
        #if os(macOS)
        var embedViews: [NSView] = []
        #else
        var embedViews: [UIView] = []
        #endif

        /// Positions images, checkboxes and bullets over the (hidden) Markdown using TextKit 2 layout.
        func layoutEmbeds(_ tv: PlatformTextView) {
            embedViews.forEach { $0.removeFromSuperview() }
            embedViews = []
            guard let tlm = tv.textLayoutManager, let tcm = tlm.textContentManager else { return }
            #if os(macOS)
            let origin = tv.textContainerOrigin
            #else
            let origin = CGPoint(x: tv.textContainerInset.left, y: tv.textContainerInset.top)
            #endif
            #if os(macOS)
            let padding = tv.textContainer?.lineFragmentPadding ?? 0
            #else
            let padding = tv.textContainer.lineFragmentPadding
            #endif
            let start = tcm.documentRange.location
            // Walk fragments from the top with .ensuresLayout so every frame reflects the new paragraph heights
            // (asking for a single location can return stale frames for blocks above it).
            var frames: [Int: CGRect] = [:]   // line start → (x: fragment x, y: line top, height: line height)
            let wanted = Set(placed.map(\.range.location))
            tlm.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { frag in
                let base = tcm.offset(from: start, to: frag.rangeInElement.location)
                let end = tcm.offset(from: start, to: frag.rangeInElement.endLocation)
                for loc in wanted where loc >= base && loc < max(end, base + 1) {
                    let f = frag.layoutFragmentFrame
                    let line = frag.textLineFragments.first { NSLocationInRange(loc - base, $0.characterRange) } ?? frag.textLineFragments.first
                    let lb = line?.typographicBounds ?? CGRect(x: 0, y: 0, width: 0, height: f.height)
                    frames[loc] = CGRect(x: f.minX, y: f.minY + lb.minY, width: 0, height: lb.height)
                }
                return frames.count < wanted.count
            }
            for e in placed {
                guard let line = frames[e.range.location] else { continue }
                // Paragraph indents shift the fragment, so measure from the container edge instead.
                let x = origin.x + padding + e.xOffset
                let view: PlatformView
                switch e.kind {
                case .image(let image, let label):
                    view = Self.imageView(image, label: label, frame: CGRect(x: x, y: origin.y + line.minY + 6, width: e.size.width, height: e.size.height))
                case .checkbox(let done, let label):
                    let frame = CGRect(x: x, y: origin.y + line.minY + (line.height - e.size.height) / 2, width: e.size.width, height: e.size.height)
                    let controller = parent.controller
                    view = Self.checkbox(done: done, label: label, lineHeight: line.height, frame: frame) { controller.toggleTask(at: e.range.location) }
                case .bullet:
                    let frame = CGRect(x: x, y: origin.y + line.minY + (line.height - e.size.height) / 2, width: e.size.width, height: e.size.height)
                    view = Self.bullet(frame: frame)
                }
                tv.addSubview(view)
                embedViews.append(view)
            }
        }

        #if os(macOS)
        typealias PlatformView = NSView

        static func imageView(_ image: NSImage, label: String, frame: CGRect) -> NSView {
            let v = NSImageView(frame: frame)
            v.image = image
            v.imageScaling = .scaleProportionallyUpOrDown
            v.wantsLayer = true
            v.layer?.cornerRadius = 6
            v.layer?.masksToBounds = true
            v.setAccessibilityLabel(label)
            return v
        }

        static func checkbox(done: Bool, label: String, lineHeight: CGFloat, frame: CGRect, toggle: @escaping () -> Void) -> NSView {
            let b = ClosureButton(frame: frame.insetBy(dx: -4, dy: -4), action: toggle)
            b.isBordered = false
            b.image = NSImage(systemSymbolName: done ? "checkmark.square.fill" : "square", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: frame.height, weight: .regular))
            b.contentTintColor = done ? .controlAccentColor : .secondaryLabelColor
            b.setAccessibilityLabel(label.isEmpty ? String(localized: "Task") : label)
            b.setAccessibilityRole(.checkBox)
            b.setAccessibilityValue(done)
            return b
        }

        static func bullet(frame: CGRect) -> NSView {
            let v = NSView(frame: frame)
            v.wantsLayer = true
            v.layer?.cornerRadius = frame.width / 2
            v.layer?.backgroundColor = NSColor.secondaryLabelColor.cgColor
            v.setAccessibilityElement(false)
            return v
        }
        #else
        typealias PlatformView = UIView

        static func imageView(_ image: UIImage, label: String, frame: CGRect) -> UIView {
            let v = UIImageView(frame: frame)
            v.image = image
            v.contentMode = .scaleAspectFit
            v.layer.cornerRadius = 6
            v.clipsToBounds = true
            v.isAccessibilityElement = true
            v.accessibilityLabel = label
            return v
        }

        static func checkbox(done: Bool, label: String, lineHeight: CGFloat, frame: CGRect, toggle: @escaping () -> Void) -> UIView {
            // 44 pt wide hit area; height clamped to the line so neighbouring tasks don't overlap.
            let h = max(frame.height, min(44, lineHeight))
            let hit = CGRect(x: frame.midX - 22, y: frame.midY - h / 2, width: 44, height: h)
            let b = UIButton(type: .system, primaryAction: UIAction { _ in toggle() })
            b.frame = hit
            b.setImage(UIImage(systemName: done ? "checkmark.square.fill" : "square",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: frame.height)), for: .normal)
            b.tintColor = done ? .tintColor : .secondaryLabel
            b.accessibilityLabel = label.isEmpty ? String(localized: "Task") : label
            b.accessibilityTraits = [.button, .toggleButton]
            b.accessibilityValue = done ? "1" : "0"
            return b
        }

        static func bullet(frame: CGRect) -> UIView {
            let v = UIView(frame: frame)
            v.layer.cornerRadius = frame.width / 2
            v.backgroundColor = .secondaryLabel
            v.isAccessibilityElement = false
            v.isUserInteractionEnabled = false
            return v
        }
        #endif

        func restyle(_ tv: PlatformTextView, force: Bool = false) {
            #if os(macOS)
            guard let storage = tv.textStorage else { return }
            let sel = tv.selectedRange()
            #else
            let storage = tv.textStorage
            let sel = tv.selectedRange
            #endif
            // Without focus nothing is "being edited", so everything renders (Obsidian shows syntax only where you type).
            let lines = isFocused(tv)
                ? (storage.string as NSString).lineRange(for: NSRange(location: min(sel.location, storage.length), length: sel.length))
                : NSRange(location: NSNotFound, length: 0)
            guard force || lines != active else { return }
            active = lines
            updating = true
            placed = styler.apply(to: storage, active: lines)
            DispatchQueue.main.async { [weak tv] in if let tv { self.layoutEmbeds(tv) } }
            #if os(macOS)
            tv.typingAttributes = styler.baseAttributes
            #else
            tv.typingAttributes = styler.baseAttributes
            #endif
            updating = false
        }

        func isFocused(_ tv: PlatformTextView) -> Bool {
            #if os(macOS)
            tv.window?.firstResponder === tv
            #else
            tv.isFirstResponder
            #endif
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
            // Only typing opens a completion list; moving the caret just updates or closes an open one.
            if parent.controller.completion != nil { parent.controller.updateCompletion(caret: caretRect(tv)) }
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
    var headerHost: NSHostingView<AnyView>?
    var headerHeight: CGFloat = 0 {
        didSet { if headerHeight != oldValue { updateInsets(force: true) } }
    }

    func setHeader(_ view: AnyView?) {
        guard let view else { headerHost?.removeFromSuperview(); headerHost = nil; return }
        if let headerHost { headerHost.rootView = view } else {
            let host = NSHostingView(rootView: view)
            host.translatesAutoresizingMaskIntoConstraints = true
            addSubview(host)
            headerHost = host
        }
        layoutHeader()
    }

    func layoutHeader() {
        headerHost?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(1, headerHeight))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        updateInsets()
        layoutHeader()
        if widthChanged, let c = coordinator, !c.placed.isEmpty { DispatchQueue.main.async { c.layoutEmbeds(self) } }
    }

    func updateInsets(force: Bool = false) {
        let side = readableWidth ? max(24, (bounds.width - MarkdownTextView.maxLineWidth) / 2) : 24
        // NSTextView insets are symmetric, so the header height is also added below the text (scroll-past space).
        let inset = NSSize(width: side, height: 20 + headerHeight)
        if coordinator?.parent.controller.sideInset != side { coordinator?.parent.controller.sideInset = side }
        let textWidth = (bounds.width - 2 * side - 2 * (textContainer?.lineFragmentPadding ?? 5)).rounded(.down)
        if textWidth > 100, abs((coordinator?.parent.controller.textWidth ?? 0) - textWidth) >= 8 {
            coordinator?.parent.controller.textWidth = textWidth
        }
        if force || textContainerInset != inset {
            textContainerInset = inset
            // TextKit 2 keeps the old viewport layout after an inset change; invalidate so text moves below the header.
            if let tlm = textLayoutManager {
                tlm.invalidateLayout(for: tlm.documentRange)
                tlm.textViewportLayoutController.layoutViewport()
            }
            needsLayout = true
            needsDisplay = true
            layoutHeader()
            if let c = coordinator, !c.placed.isEmpty { DispatchQueue.main.async { c.layoutEmbeds(self) } }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { DispatchQueue.main.async { self.coordinator?.restyle(self, force: true) } }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { DispatchQueue.main.async { self.coordinator?.restyle(self, force: true) } }
        return ok
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateHover(event)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        updateHover(event)
    }

    /// ⌘-hover over an internal link shows a page preview (like Obsidian).
    private func updateHover(_ event: NSEvent) {
        guard let c = coordinator?.parent.controller, let window, let scroll = enclosingScrollView else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard event.modifierFlags.contains(.command), let storage = textStorage else {
            if c.hover != nil { c.hover = nil }
            return
        }
        let i = characterIndexForInsertion(at: point)
        for idx in [i, i - 1] where idx >= 0 && idx < storage.length {
            if let target = storage.attribute(.netheriteLink, at: idx, effectiveRange: nil) as? String,
               let rect = firstRectForCharacter(idx), rect.contains(point) {
                let inScroll = scroll.convert(convert(rect, to: nil), from: nil)
                let flipped = CGRect(x: inScroll.minX, y: scroll.bounds.height - inScroll.maxY, width: inScroll.width, height: inScroll.height)
                if c.hover?.target != target { c.hover = .init(target: target, rect: flipped) }
                return
            }
        }
        if c.hover != nil { c.hover = nil }
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
        // Start after the frontmatter so Live Preview shows the properties header instead of raw YAML.
        tv.setSelectedRange(NSRange(location: Frontmatter.locate(in: text).map { NSMaxRange($0.range) } ?? 0, length: 0))
        context.coordinator.restyle(tv, force: true)
        controller.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NetheriteNSTextView else { return }
        let themeChanged = context.coordinator.parent.theme != theme || context.coordinator.parent.livePreview != livePreview
            || context.coordinator.parent.styleToken != styleToken
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
        tv.headerHeight = header == nil ? 0 : headerHeight
        tv.setHeader(header)
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
    weak var coordinator: MarkdownTextView.Coordinator?
    var readableWidth = true
    var headerHeight: CGFloat = 0
    var headerHost: UIHostingController<AnyView>?
    var onSideInset: ((CGFloat) -> Void)?
    var onTextWidth: ((CGFloat) -> Void)?
    private var lastSide: CGFloat = -1
    private var lastTextWidth: CGFloat = -1

    func setHeader(_ view: AnyView?) {
        guard let view else { headerHost?.view.removeFromSuperview(); headerHost = nil; return }
        if let headerHost { headerHost.rootView = view } else {
            let host = UIHostingController(rootView: view)
            host.view.backgroundColor = .clear
            host.sizingOptions = []
            addSubview(host.view)
            headerHost = host
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side = readableWidth ? max(16, (bounds.width - MarkdownTextView.maxLineWidth) / 2) : 16
        let inset = UIEdgeInsets(top: 16 + headerHeight, left: side, bottom: 120, right: side)
        if onSideInset != nil, lastSide != side { lastSide = side; onSideInset?(side) }
        let textWidth = (bounds.width - 2 * side - 2 * textContainer.lineFragmentPadding).rounded(.down)
        if textWidth > 100, abs(lastTextWidth - textWidth) >= 8 { lastTextWidth = textWidth; onTextWidth?(textWidth) }
        if textContainerInset != inset { textContainerInset = inset }
        // Header scrolls with the content (content coordinates start at y = 0).
        headerHost?.view.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(1, headerHeight))
    }
}

extension MarkdownTextView: UIViewRepresentable {
    func makeUIView(context: Context) -> NetheriteUITextView {
        let tv = NetheriteUITextView(usingTextLayoutManager: true)
        tv.coordinator = context.coordinator
        tv.delegate = context.coordinator
        tv.backgroundColor = .clear
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.smartQuotesType = .no
        tv.smartDashesType = .no
        tv.autocapitalizationType = .sentences
        tv.accessibilityLabel = String(localized: "Note editor")
        // VoiceOver may not reach checkbox overlays inside the text view, so offer the action on the editor itself.
        tv.accessibilityCustomActions = [UIAccessibilityCustomAction(name: String(localized: "Toggle Task")) { [controller] _ in
            guard let done = controller.toggleTask(at: controller.selectedRange.location) else { return false }
            UIAccessibility.post(notification: .announcement, argument: done ? String(localized: "Completed") : String(localized: "Not completed"))
            return true
        }]
        tv.text = text
        tv.selectedRange = NSRange(location: Frontmatter.locate(in: text).map { NSMaxRange($0.range) } ?? 0, length: 0)
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
            || context.coordinator.parent.styleToken != styleToken
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
        tv.headerHeight = header == nil ? 0 : headerHeight
        tv.onSideInset = { [controller] side in DispatchQueue.main.async { controller.sideInset = side } }
        tv.onTextWidth = { [controller] w in DispatchQueue.main.async { controller.textWidth = w } }
        tv.setHeader(header)
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

#if os(macOS)
extension NSView { func setAccessibilityLabelCompat(_ s: String) { setAccessibilityLabel(s) } }

/// NSButton that runs a closure (checkboxes drawn over the editor).
final class ClosureButton: NSButton {
    private let run: () -> Void
    init(frame: NSRect, action: @escaping () -> Void) {
        run = action
        super.init(frame: frame)
        target = self
        self.action = #selector(fire)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}
#else
extension UIView { func setAccessibilityLabelCompat(_ s: String) { isAccessibilityElement = true; accessibilityLabel = s } }
#endif
