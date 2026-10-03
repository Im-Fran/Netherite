import SwiftUI
import WebKit
import NetheriteCore

/// In-app browser for external links, with an option to save the page as a note.
struct WebViewer: View {
    let url: URL
    @Environment(WindowState.self) private var window
    @State private var address = ""
    @State private var title: String?
    @State private var current: URL?
    @State private var webView: WKWebView?
    @State private var loading = false
    @State private var loadError: Error?
    @State private var clipping = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { webView?.goBack() } label: { Label("Previous Page", systemImage: "chevron.backward").hitTarget() }
                    .disabled(!(webView?.canGoBack ?? false))
                Button { webView?.goForward() } label: { Label("Next Page", systemImage: "chevron.forward").hitTarget() }
                    .disabled(!(webView?.canGoForward ?? false))
                if loading {
                    ProgressView().controlSize(.small).hitTarget().accessibilityLabel("Loading")
                } else {
                    Button(action: reload) { Label("Reload", systemImage: "arrow.clockwise").hitTarget() }
                }
                TextField("Address", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    #endif
                    .onSubmit { window.openURL(address) }
                if clipping {
                    ProgressView().controlSize(.small).hitTarget().accessibilityLabel("Saving as Note")
                } else {
                    Button(action: saveAsNote) { Label("Save as Note", systemImage: "square.and.arrow.down").hitTarget() }
                        .help("Create a note linking to this page")
                }
                Link(destination: current ?? url) { Label("Open in Browser", systemImage: "safari").hitTarget() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(8)
            Divider()
            HTMLWebView(html: nil, url: url, vault: window.model.vault,
                        onNavigate: { t, u in title = t; current = u; address = u?.absoluteString ?? address },
                        onLoad: { l, e in loading = l; loadError = e },
                        webViewRef: { wv in DispatchQueue.main.async { webView = wv } })
                .overlay {
                    if let loadError {
                        ContentUnavailableView {
                            Label("Couldn't Load Page", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(loadError.localizedDescription)
                        } actions: {
                            Button("Reload", action: reload)
                        }
                        .background(.background)
                    }
                }
        }
        .onAppear { address = url.absoluteString }
    }

    /// Reloads the page, or retries the URL that failed to load.
    private func reload() {
        if let failed = loadError.map({ $0 as NSError })?.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            loadError = nil
            webView?.load(URLRequest(url: failed))
        } else {
            webView?.reload()
        }
    }

    private func saveAsNote() {
        let u = current ?? url
        let name = (title?.isEmpty == false ? title! : (u.host() ?? String(localized: "Web page")))
            .replacingOccurrences(of: #"[\\/:*?"<>|#^\[\]]"#, with: "-", options: .regularExpression)
        clipping = true
        Task {
            defer { clipping = false }
            // Falls back to a link-only note when the page can't be clipped. Creation failures surface in the window alert.
            let body = await WebClipper.clip(webView: webView) ?? "[\(title ?? name)](\(u.absoluteString))"
            let content = "---\nsource: \(u.absoluteString)\nclipped: \(Frontmatter.dateString(.now))\n---\n# \(title ?? name)\n\n\(body)\n"
            if let p = window.model.newNote(named: String(name.prefix(80)), content: content) { window.open(path: p, newPane: true) }
        }
    }
}

/// Extracts the main text of a loaded page as simple Markdown (headings, paragraphs, lists, links).
enum WebClipper {
    static let script = """
    (() => {
      const root = document.querySelector('article, main, [role=main]') || document.body;
      const out = [];
      const walk = (el) => {
        for (const n of el.children) {
          const t = n.tagName;
          if (['SCRIPT','STYLE','NAV','FOOTER','ASIDE','FORM','NOSCRIPT'].includes(t)) continue;
          const text = (n.innerText || '').trim();
          if (/^H[1-6]$/.test(t)) { if (text) out.push('#'.repeat(+t[1]) + ' ' + text); }
          else if (t === 'P') { if (text) out.push(text); }
          else if (t === 'LI') { if (text) out.push('- ' + text); }
          else if (t === 'PRE') { out.push('```\\n' + n.innerText + '\\n```'); }
          else if (t === 'BLOCKQUOTE') { out.push(text.split('\\n').map(l => '> ' + l).join('\\n')); }
          else if (t === 'IMG' && n.src) { out.push('![](' + n.src + ')'); }
          else walk(n);
        }
      };
      walk(root);
      return out.join('\\n\\n');
    })()
    """

    static func clip(webView: WKWebView?) async -> String? {
        guard let webView else { return nil }
        return try? await webView.evaluateJavaScript(script) as? String
    }
}

extension View {
    /// Keeps icon-only controls at least 44pt square on iOS (HIG minimum hit target).
    func hitTarget() -> some View {
        #if os(iOS)
        frame(minWidth: 44, minHeight: 44).contentShape(.rect)
        #else
        self
        #endif
    }
}
