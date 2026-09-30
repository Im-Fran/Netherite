import SwiftUI
import WebKit
import NetheriteCore

/// Serves `nth://web/…` (bundled KaTeX/Mermaid/highlight.js/reader assets) and `nth://vault/…` (vault files)
/// so rendered notes work inside the sandbox without file:// access.
final class NetheriteSchemeHandler: NSObject, WKURLSchemeHandler {
    let vault: Vault
    init(vault: Vault) { self.vault = vault }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let host = url.host() else { return fail(task) }
        let rel = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let file: URL?
        switch host {
        case "web": file = HTMLRenderer.webResources?.appending(path: rel)
        case "vault": file = vault.url(for: rel)
        default: file = nil
        }
        guard let file, let data = try? Data(contentsOf: file) else { return fail(task) }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                        headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)", "Access-Control-Allow-Origin": "*"])!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func fail(_ task: any WKURLSchemeTask) { task.didFailWithError(URLError(.fileDoesNotExist)) }

    nonisolated static func vaultURL(_ path: String) -> String {
        "nth://vault/" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)
    }
}

import UniformTypeIdentifiers

/// Actions coming out of a rendered page.
enum WebAction {
    case openPath(String, subpath: String?, newPane: Bool)
    case createNote(String)
    case tag(String)
    case external(URL)
    case task(line: Int)
    case hover(path: String, subpath: String?, rect: CGRect)
}

extension RenderContext {
    /// Context for rendering inside the app, backed by a snapshot of the index.
    @MainActor static func app(_ index: VaultIndex, source: String) -> RenderContext {
        let resolver = index.resolver
        let notes = index.notes
        let vault = index.vault
        return RenderContext(
            source: source,
            resolve: { resolver.resolve($0, from: $1) },
            readNote: { notes[$0]?.text ?? (try? vault.read($0)) },
            linkHref: { path, target, sub in
                let q = sub.map { "?sub=" + ($0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") } ?? ""
                if let path { return "nth://open/" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path) + q }
                return "nth://new/" + (target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target)
            },
            assetURL: NetheriteSchemeHandler.vaultURL,
            tagHref: { "nth://tag/" + ($0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0) })
    }
}

struct HTMLWebView {
    var html: String?
    var url: URL?
    let vault: Vault
    var onAction: (WebAction) -> Void = { _ in }
    /// For the web viewer: reports title and URL changes.
    var onNavigate: ((String?, URL?) -> Void)?
    var webViewRef: ((WKWebView) -> Void)?

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLWebView
        var lastHTML: String?
        var lastURL: URL?
        init(_ p: HTMLWebView) { parent = p }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = action.request.url else { return .allow }
            let newPane: Bool
            #if os(macOS)
            newPane = action.modifierFlags.contains(.command)
            #else
            newPane = false
            #endif
            if url.scheme == "nth" {
                let rel = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                switch url.host() {
                case "open":
                    let sub = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "sub" }?.value
                    parent.onAction(.openPath(rel, subpath: sub, newPane: newPane))
                    return .cancel
                case "new": parent.onAction(.createNote(rel)); return .cancel
                case "tag": parent.onAction(.tag(rel)); return .cancel
                default: return .allow
                }
            }
            if action.navigationType == .linkActivated, parent.onNavigate == nil {
                parent.onAction(.external(url))
                return .cancel
            }
            return .allow
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.onNavigate?(webView.title, webView.url)
        }

        func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            if type == "task", let line = body["line"] as? Int { parent.onAction(.task(line: line)) }
            if type == "hover", let href = body["href"] as? String, let url = URL(string: href), url.host() == "open" {
                let rel = url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let sub = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "sub" }?.value
                func n(_ k: String) -> CGFloat { CGFloat((body[k] as? NSNumber)?.doubleValue ?? 0) }
                parent.onAction(.hover(path: rel, subpath: sub, rect: CGRect(x: n("x"), y: n("y"), width: n("w"), height: n("h"))))
            }
        }
    }

    @MainActor func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(NetheriteSchemeHandler(vault: vault), forURLScheme: "nth")
        config.userContentController.add(WeakHandler(context.coordinator), name: "netherite")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        #if os(macOS)
        wv.setValue(false, forKey: "drawsBackground")
        #else
        wv.isOpaque = false
        wv.backgroundColor = .clear
        #endif
        wv.allowsBackForwardNavigationGestures = onNavigate != nil
        webViewRef?(wv)
        return wv
    }

    func update(_ wv: WKWebView, context: Context) {
        context.coordinator.parent = self
        if let html, html != context.coordinator.lastHTML {
            context.coordinator.lastHTML = html
            wv.loadHTMLString(html, baseURL: URL(string: "nth://web/"))
        } else if let url, url != context.coordinator.lastURL {
            context.coordinator.lastURL = url
            wv.load(URLRequest(url: url))
        }
    }
}

/// Avoids the retain cycle between WKUserContentController and the coordinator.
@MainActor final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

#if os(macOS)
extension HTMLWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ v: WKWebView, context: Context) { update(v, context: context) }
}
#else
extension HTMLWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ v: WKWebView, context: Context) { update(v, context: context) }
}
#endif
