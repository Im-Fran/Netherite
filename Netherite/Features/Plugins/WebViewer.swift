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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("Back", systemImage: "chevron.backward") { webView?.goBack() }.disabled(!(webView?.canGoBack ?? false))
                Button("Forward", systemImage: "chevron.forward") { webView?.goForward() }.disabled(!(webView?.canGoForward ?? false))
                Button("Reload", systemImage: "arrow.clockwise") { webView?.reload() }
                TextField("Address", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { window.openURL(address) }
                Button("Save as Note", systemImage: "square.and.arrow.down", action: saveAsNote)
                    .help("Create a note linking to this page")
                Link(destination: current ?? url) { Label("Open in Browser", systemImage: "safari") }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(8)
            Divider()
            HTMLWebView(html: nil, url: url, vault: window.model.vault,
                        onNavigate: { t, u in title = t; current = u; address = u?.absoluteString ?? address },
                        webViewRef: { wv in DispatchQueue.main.async { webView = wv } })
        }
        .onAppear { address = url.absoluteString }
    }

    private func saveAsNote() {
        let u = current ?? url
        let name = (title?.isEmpty == false ? title! : (u.host() ?? "Web page"))
            .replacingOccurrences(of: #"[\\/:*?"<>|#^\[\]]"#, with: "-", options: .regularExpression)
        Task {
            let body = await WebClipper.clip(webView: webView) ?? ""
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
