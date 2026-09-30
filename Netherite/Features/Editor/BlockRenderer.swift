import SwiftUI
import WebKit
import NetheriteCore

/// Renders math blocks, Mermaid diagrams and note embeds to images for Live Preview,
/// using one hidden WKWebView (KaTeX/Mermaid are JavaScript). Results are cached by content.
@MainActor
final class BlockRenderer: NSObject, WKNavigationDelegate {
    static let shared = BlockRenderer()

    enum Kind: String { case math, mermaid, html }

    struct Job {
        var key: String
        var kind: Kind
        var source: String
        var width: CGFloat
        var dark: Bool
        var fontSize: CGFloat
    }

    private var cache: [String: PlatformImage] = [:]
    private var queue: [Job] = []
    private var waiting: [String: [() -> Void]] = [:]
    private var running = false
    private var ready = false
    private let webView: WKWebView
    private let scheme = NetheriteSchemeHandler(vault: Vault(root: URL.temporaryDirectory))
    /// Vault whose attachments note embeds may reference.
    var vault: Vault {
        get { scheme.vault }
        set { scheme.vault = newValue }
    }
    #if os(iOS)
    private var attached = false
    #endif

    private override init() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(scheme, forURLScheme: "nth")
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 720, height: 200), configuration: config)
        super.init()
        #if os(macOS)
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        // Otherwise the safe-area inset shifts content down inside the snapshot.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.isScrollEnabled = false
        // iOS 26 draws a scroll-edge effect at the top of scroll views under bars; it would end up in the snapshot.
        webView.scrollView.topEdgeEffect.isHidden = true
        webView.scrollView.bottomEdgeEffect.isHidden = true
        #endif
        webView.navigationDelegate = self
        webView.loadHTMLString(Self.shell, baseURL: URL(string: "nth://web/"))
    }

    static func key(_ kind: Kind, _ source: String, width: CGFloat, dark: Bool, fontSize: CGFloat) -> String {
        "\(kind.rawValue)|\(Int(width))|\(dark)|\(Int(fontSize * 10))|\(source.hashValue)"
    }

    /// Cached image, or nil after scheduling a render; `onReady` runs when it finishes.
    func image(_ kind: Kind, source: String, width: CGFloat, dark: Bool, fontSize: CGFloat, onReady: @escaping () -> Void) -> PlatformImage? {
        let key = Self.key(kind, source, width: width, dark: dark, fontSize: fontSize)
        if let img = cache[key] { return img }
        if waiting[key] != nil { waiting[key]?.append(onReady); return nil }
        waiting[key] = [onReady]
        queue.append(Job(key: key, kind: kind, source: source, width: width, dark: dark, fontSize: fontSize))
        pump()
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        pump()
    }

    private func pump() {
        guard ready, !running, !queue.isEmpty else { return }
        #if os(iOS)
        attachIfNeeded()
        #endif
        running = true
        let job = queue.removeFirst()
        Task {
            let image = await render(job)
            if let image { cache[job.key] = image }
            let callbacks = waiting.removeValue(forKey: job.key) ?? []
            running = false
            if image != nil { callbacks.forEach { $0() } }
            pump()
        }
    }

    private func render(_ job: Job) async -> PlatformImage? {
        webView.frame.size = CGSize(width: job.width, height: 200)
        guard let result = try? await webView.callAsyncJavaScript(
            "return await window.nthRender(kind, source, dark, size)",
            arguments: ["kind": job.kind.rawValue, "source": job.source, "dark": job.dark, "size": Double(job.fontSize)],
            contentWorld: .page),
              let dims = result as? [Double], dims.count == 2, dims[0] > 1, dims[1] > 1 else { return nil }
        let size = CGSize(width: min(job.width, ceil(dims[0])), height: min(4000, ceil(dims[1])))
        webView.frame.size = CGSize(width: job.width, height: size.height)
        // Let WebKit repaint the newly sized area before capturing it.
        try? await Task.sleep(for: .milliseconds(80))
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)
        config.afterScreenUpdates = true
        return try? await webView.takeSnapshot(configuration: config)
    }

    #if os(iOS)
    /// iOS only snapshots web views that are in a window. It stays fully opaque (alpha would carry into
    /// the snapshot) but sits behind the app's root view, so it's never visible.
    private func attachIfNeeded() {
        guard !attached, let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else { return }
        webView.isUserInteractionEnabled = false
        window.insertSubview(webView, at: 0)
        attached = true
    }
    #endif

    static let shell = """
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="stylesheet" href="reader.css"><link rel="stylesheet" href="katex/katex.min.css">
    <link rel="stylesheet" href="hljs/github.min.css" media="(prefers-color-scheme: light)">
    <script src="katex/katex.min.js"></script><script src="mermaid.min.js"></script>
    <style>
      html, body { background: transparent !important; margin: 0; padding: 0; max-width: none; }
      #out { display: inline-block; padding: 4px 0; }
      #out.block { display: block; }
      #out > :first-child, #out .callout:first-child, #out table:first-child { margin-top: 0; }
      #out > :last-child { margin-bottom: 0; }
      body.dark { --text: #e8e8ed; --muted: #98989d; --faint: #3a3a3c; --code-bg: rgba(255,255,255,.07); --link: #B7A6E6; --tag: #C4B5F0; --mark: #6B5B1F; color: #e8e8ed; }
      body.light { --text: #1d1d1f; color: #1d1d1f; }
    </style></head>
    <body><div id="out"></div>
    <script>
    let n = 0;
    window.nthRender = async function (kind, source, dark, size) {
      document.body.className = dark ? 'dark' : 'light';
      document.documentElement.style.setProperty('--size', size + 'px');
      document.documentElement.style.fontSize = size + 'px';
      const out = document.getElementById('out');
      out.className = kind === 'html' ? 'block' : '';
      out.innerHTML = '';
      if (kind === 'math') {
        katex.render(source, out, { displayMode: true, throwOnError: false });
      } else if (kind === 'mermaid') {
        mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'default', securityLevel: 'strict' });
        const { svg } = await Promise.race([
          mermaid.render('m' + (n++), source),
          new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), 5000))
        ]);
        out.innerHTML = svg;
      } else {
        out.innerHTML = source;
        await Promise.all([...out.querySelectorAll('img')].map(i => i.complete ? 0 : new Promise(r => { i.onload = i.onerror = r; })));
        out.querySelectorAll('.math[data-tex]').forEach(el => katex.render(el.dataset.tex, el, { displayMode: el.classList.contains('math-display'), throwOnError: false }));
      }
      // Offscreen web views don't tick requestAnimationFrame, so wait on a timer for layout/fonts.
      await document.fonts.ready;
      await new Promise(r => setTimeout(r, 30));
      const r = out.getBoundingClientRect();
      return [Math.ceil(r.right), Math.ceil(r.bottom)];
    };
    </script></body></html>
    """
}
