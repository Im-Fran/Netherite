import Foundation

/// What to publish and how the site is titled. Stored in `.netherite/publish.json` by the app.
public struct PublishOptions: Codable, Hashable, Sendable {
    public enum Scope: String, Codable, CaseIterable, Sendable { case all, folder, published }
    public var scope: Scope = .all
    /// Folder for `.folder` scope.
    public var folder = ""
    /// Note path used as the home page (falls back to Home/Welcome/index).
    public var home = ""
    public var siteName = ""
    public var accountID = ""
    public var projectName = ""
    public init() {}
}

/// Turns a vault into a static website: one page per note, search, graph, tag pages and backlinks.
@MainActor
public enum SiteExporter {
    public struct Report: Sendable {
        public var pages: Int
        public var attachments: Int
    }

    /// Files written directly into `out` (existing unrelated files are left alone).
    @discardableResult
    public static func export(_ index: VaultIndex, to out: URL, options: PublishOptions = .init(), theme: Theme? = nil) throws -> Report {
        let fm = FileManager.default
        try fm.createDirectory(at: out, withIntermediateDirectories: true)

        let notes = index.markdownFiles.filter { included($0, index, options) }
        let published = Set(notes)
        let siteName = options.siteName.isEmpty ? index.vault.name : options.siteName
        let home = homeNote(notes, options)

        // Assets: bundled web resources + site chrome.
        let assets = out.appending(path: "assets", directoryHint: .isDirectory)
        if let web = HTMLRenderer.webResources {
            try? fm.removeItem(at: assets)
            try fm.copyItem(at: web, to: assets)
        }
        try Data(siteCSS.utf8).write(to: assets.appending(path: "site.css"))
        try Data(siteJS.utf8).write(to: assets.appending(path: "site.js"))
        try Data(graphJS.utf8).write(to: assets.appending(path: "graph.js"))

        let attachments = AttachmentLog()
        func write(_ html: String, _ rel: String) throws {
            let url = out.appending(path: rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(html.utf8).write(to: url)
        }

        // Notes
        var tags: [String: [String]] = [:]
        for path in notes {
            guard let rec = index.notes[path] else { continue }
            let rel = pagePath(path)
            try write(page(index: index, source: path, text: rec.text, rel: rel, published: published, home: home,
                           siteName: siteName, theme: theme, attachments: attachments), rel)
            for t in Set(rec.parsed.tags.map { $0.lowercased() }) { tags[t, default: []].append(path) }
        }
        if let home, let rec = index.notes[home] {
            try write(page(index: index, source: home, text: rec.text, rel: "index.html", published: published, home: home,
                           siteName: siteName, theme: theme, attachments: attachments), "index.html")
        } else {
            let list = notes.map { "- [[\($0)|\($0.noteName)]]" }.joined(separator: "\n")
            try write(page(index: index, source: "", text: "# \(siteName)\n\n\(list)", rel: "index.html", published: published, home: nil,
                           siteName: siteName, theme: theme, attachments: attachments, title: siteName), "index.html")
        }

        // Tag pages
        for (tag, paths) in tags {
            let body = "<ul>" + paths.sorted().map { "<li><a class=\"internal-link\" href=\"../\(pagePath($0))\">\(HTMLRenderer.escape($0.noteName))</a></li>" }.joined() + "</ul>"
            try write(shell(title: "#\(tag)", body: body, prefix: "../", current: nil, notes: notes, siteName: siteName, theme: theme), "tags/\(slug(tag)).html")
        }

        // 404 (served from any depth on hosts like Cloudflare Pages, so links are root-absolute)
        try write(shell(title: String(localized: "Page not found"), body: "<p><a href=\"/\">\(HTMLRenderer.escape(siteName))</a></p>",
                        prefix: "/", current: nil, notes: notes, siteName: siteName, theme: theme), "404.html")

        // Search index and graph data (JSON + JS so they also work when opened from file://)
        let search = notes.compactMap { p -> [String: String]? in
            guard let rec = index.notes[p] else { return nil }
            let body = rec.parsed.frontmatterRange.map { (rec.text as NSString).substring(from: NSMaxRange($0)) } ?? rec.text
            return ["title": p.noteName, "path": pagePath(p), "text": String(body.prefix(4000))]
        }
        let searchJSON = try json(search)
        try Data(searchJSON.utf8).write(to: out.appending(path: "search.json"))
        try Data("window.NETHERITE_SEARCH = \(searchJSON);".utf8).write(to: assets.appending(path: "search-index.js"))

        let nodes = notes.map { ["id": pagePath($0), "label": $0.noteName] }
        let links = notes.flatMap { s in (index.outgoing[s] ?? []).filter(published.contains).map { ["source": pagePath(s), "target": pagePath($0)] } }
        let graphJSON = try json(["nodes": nodes, "links": links])
        try Data(graphJSON.utf8).write(to: out.appending(path: "graph.json"))
        try Data("window.NETHERITE_GRAPH = \(graphJSON);".utf8).write(to: assets.appending(path: "graph-data.js"))
        try write(shell(title: String(localized: "Graph view"), body: "<canvas id=\"graph\" aria-label=\"Graph of linked notes\"></canvas><script src=\"assets/graph-data.js\"></script><script src=\"assets/graph.js\"></script>",
                        prefix: "", current: nil, notes: notes, siteName: siteName, theme: theme, wide: true), "graph.html")

        // Attachments referenced by published pages
        var copied = 0
        for p in attachments.paths where !p.isMarkdown {
            let dst = out.appending(path: "files/" + p)
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: dst)
            if (try? fm.copyItem(at: index.vault.url(for: p), to: dst)) != nil { copied += 1 }
        }
        return Report(pages: notes.count, attachments: copied)
    }

    // MARK: Scope

    static func included(_ path: String, _ index: VaultIndex, _ o: PublishOptions) -> Bool {
        let templates = index.vault.settings.templatesFolder
        if !templates.isEmpty && path.hasPrefix(templates + "/") { return false }   // templates aren't content
        return switch o.scope {
        case .all: true
        case .folder: o.folder.isEmpty || path.hasPrefix(o.folder + "/")
        case .published: index.notes[path]?.parsed.property("publish") == .bool(true)
        }
    }

    static func homeNote(_ notes: [String], _ o: PublishOptions) -> String? {
        if notes.contains(o.home) { return o.home }
        for name in ["home", "welcome", "index", "readme"] {
            if let p = notes.first(where: { $0.noteName.lowercased() == name }) { return p }
        }
        return nil
    }

    // MARK: Paths

    public nonisolated static func slug(_ s: String) -> String {
        let out = HTMLRenderer.slug(s)
        return out.isEmpty ? "untitled" : out
    }

    /// "Books/Thinking, Fast and Slow.md" → "books/thinking-fast-and-slow.html"
    // ponytail: two notes that slug to the same name collide; add a numeric suffix map if that shows up.
    public nonisolated static func pagePath(_ path: String) -> String {
        let parts = (path as NSString).deletingPathExtension.split(separator: "/").map { slug(String($0)) }
        return parts.joined(separator: "/") + ".html"
    }

    static func prefix(for rel: String) -> String {
        String(repeating: "../", count: rel.split(separator: "/").count - 1)
    }

    // MARK: Pages

    static func page(index: VaultIndex, source: String, text: String, rel: String, published: Set<String>, home: String?,
                     siteName: String, theme: Theme?, attachments: AttachmentLog, title: String? = nil) -> String {
        let pre = prefix(for: rel)
        let resolver = index.resolver
        let notes = index.notes
        let ctx = RenderContext(
            source: source,
            resolve: { resolver.resolve($0, from: $1) },
            readNote: { published.contains($0) ? notes[$0]?.text : nil },
            linkHref: { path, _, sub in
                guard let path, published.contains(path) || !path.isMarkdown else { return unresolvedHref }
                if !path.isMarkdown { attachments.add(path); return pre + fileURL(path) }
                let anchor = sub.map { s in "#" + (s.hasPrefix("^") ? s : HTMLRenderer.slug(s.split(separator: "#").last.map(String.init) ?? s)) } ?? ""
                return pre + pagePath(path) + anchor
            },
            assetURL: { attachments.add($0); return pre + fileURL($0) },
            tagHref: { pre + "tags/" + slug($0) + ".html" })
        var ctxStatic = ctx
        ctxStatic.interactiveTasks = false
        var body = HTMLRenderer.render(text, context: ctxStatic)
        // Links to unpublished or missing notes become plain text.
        body = body.replacingOccurrences(of: #"<a class="internal-link is-unresolved" href="\#(unresolvedHref)"[^>]*>(.*?)</a>"#,
                                         with: "<span class=\"is-unresolved\">$1</span>", options: .regularExpression)
            .replacingOccurrences(of: #"<a class="internal-link" href="\#(unresolvedHref)"[^>]*>(.*?)</a>"#,
                                  with: "<span class=\"is-unresolved\">$1</span>", options: .regularExpression)

        let backlinks = source.isEmpty ? [] : index.backlinks(for: source).map(\.source).filter(published.contains)
        if !backlinks.isEmpty {
            body += "<section class=\"backlinks\"><h2>" + HTMLRenderer.escape(String(localized: "Links to this page")) + "</h2><ul>"
                + backlinks.map { "<li><a class=\"internal-link\" href=\"\(pre)\(pagePath($0))\">\(HTMLRenderer.escape($0.noteName))</a></li>" }.joined()
                + "</ul></section>"
        }
        let pageTitle = title ?? source.noteName
        return shell(title: pageTitle, body: body, prefix: pre, current: source, notes: Array(published).sorted(), siteName: siteName, theme: theme)
    }

    nonisolated static let unresolvedHref = "netherite-unresolved"

    nonisolated static func fileURL(_ path: String) -> String {
        "files/" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)
    }

    /// Page chrome: sidebar (search + file tree), content, scripts.
    // ponytail: the file tree is rebuilt for every page (O(pages²) string work); cache per depth if vaults get huge.
    static func shell(title: String, body: String, prefix pre: String, current: String?, notes: [String], siteName: String,
                      theme: Theme?, wide: Bool = false) -> String {
        let nav = """
        <nav class="site-nav" aria-label="Site">
          <a class="site-name" href="\(pre)index.html">\(HTMLRenderer.escape(siteName))</a>
          <input id="site-search" type="search" placeholder="\(HTMLRenderer.escape(String(localized: "Search")))" aria-label="\(HTMLRenderer.escape(String(localized: "Search notes")))" autocomplete="off">
          <ul id="search-results" hidden></ul>
          <a class="graph-link" href="\(pre)graph.html">\(HTMLRenderer.escape(String(localized: "Graph view")))</a>
          \(tree(notes, prefix: pre, current: current))
        </nav>
        """
        let head = "<link rel=\"stylesheet\" href=\"\(pre)assets/site.css\"><script>window.NETHERITE_ROOT = \"\(pre)\";</script>"
        let scripts = "<script src=\"\(pre)assets/search-index.js\"></script><script src=\"\(pre)assets/site.js\"></script>"
        let main = "<main class=\"\(wide ? "wide" : "")\"><h1 class=\"inline-title\">\(HTMLRenderer.escape(title))</h1>\(body)</main>"
        return HTMLRenderer.page(title: nil, body: nav + main, assets: pre + "assets/", theme: theme, fullWidth: true,
                                 extraHead: head, extraBody: scripts)
            .replacingOccurrences(of: "<title></title>", with: "<title>\(HTMLRenderer.escape(title)) · \(HTMLRenderer.escape(siteName))</title>")
    }

    static func tree(_ notes: [String], prefix pre: String, current: String?) -> String {
        var byFolder: [String: [String]] = [:]
        for n in notes { byFolder[n.parentFolder, default: []].append(n) }
        let folders = Set(notes.flatMap { n -> [String] in
            var out: [String] = [], f = n.parentFolder
            while !f.isEmpty { out.append(f); f = f.parentFolder }
            return out
        })
        func build(_ folder: String) -> String {
            let sub = folders.filter { $0.parentFolder == folder }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let files = (byFolder[folder] ?? []).sorted { $0.noteName.localizedStandardCompare($1.noteName) == .orderedAscending }
            var h = "<ul>"
            for f in sub {
                let open = current?.hasPrefix(f + "/") == true ? " open" : ""
                h += "<li><details\(open)><summary>\(HTMLRenderer.escape((f as NSString).lastPathComponent))</summary>\(build(f))</details></li>"
            }
            for n in files {
                let cur = n == current ? " class=\"current\" aria-current=\"page\"" : ""
                h += "<li><a\(cur) href=\"\(pre)\(pagePath(n))\">\(HTMLRenderer.escape(n.noteName))</a></li>"
            }
            return h + "</ul>"
        }
        return "<div class=\"file-tree\">\(build(""))</div>"
    }

    static func json(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    // MARK: Site assets

    static let siteCSS = """
    body.full-width { max-width: none; padding: 0; }
    .site-nav { position: fixed; inset: 0 auto 0 0; width: 260px; overflow: auto; padding: 20px 16px; box-sizing: border-box;
      border-right: 1px solid var(--faint); font-size: .92em; background: var(--bg); }
    .site-name { display: block; font-weight: 700; font-size: 1.2em; color: var(--text); margin-bottom: 12px; }
    #site-search { width: 100%; box-sizing: border-box; padding: 8px 10px; border-radius: 8px; border: 1px solid var(--faint);
      background: var(--code-bg); color: var(--text); font: inherit; min-height: 36px; }
    #search-results { list-style: none; padding: 0; margin: 8px 0; }
    #search-results li { padding: 6px 0; border-bottom: 1px solid var(--faint); }
    #search-results small { display: block; color: var(--muted); }
    .graph-link { display: block; margin: 12px 0; }
    .file-tree ul { list-style: none; padding-left: 12px; margin: 0; }
    .file-tree > ul { padding-left: 0; }
    .file-tree li { margin: 3px 0; }
    .file-tree summary { cursor: pointer; color: var(--muted); }
    .file-tree a.current { font-weight: 700; color: var(--text); }
    main { margin-left: 260px; padding: 32px 40px 120px; max-width: var(--width); }
    main.wide { max-width: none; }
    .backlinks { margin-top: 3em; border-top: 1px solid var(--faint); font-size: .92em; }
    .backlinks h2 { font-size: 1em; color: var(--muted); }
    span.is-unresolved { color: var(--muted); }
    #graph { width: 100%; height: calc(100vh - 160px); display: block; border: 1px solid var(--faint); border-radius: 12px; cursor: grab; }
    @media (max-width: 820px) {
      .site-nav { position: static; width: auto; border-right: none; border-bottom: 1px solid var(--faint); }
      main { margin-left: 0; padding: 24px 16px 80px; }
    }
    """

    static let siteJS = """
    (function () {
      const input = document.getElementById('site-search'), out = document.getElementById('search-results');
      const data = window.NETHERITE_SEARCH || [], root = window.NETHERITE_ROOT || '';
      const esc = s => s.replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
      if (!input) return;
      input.addEventListener('input', () => {
        const q = input.value.trim().toLowerCase();
        if (!q) { out.hidden = true; out.innerHTML = ''; return; }
        const hits = data.filter(d => d.title.toLowerCase().includes(q) || d.text.toLowerCase().includes(q)).slice(0, 30);
        out.innerHTML = hits.map(d => {
          const i = d.text.toLowerCase().indexOf(q);
          const snip = i < 0 ? '' : d.text.slice(Math.max(0, i - 40), i + 60);
          return '<li><a href="' + root + d.path + '">' + esc(d.title) + '</a><small>' + esc(snip) + '</small></li>';
        }).join('') || '<li><small>No results</small></li>';
        out.hidden = false;
      });
    })();
    """

    /// Tiny force layout on a canvas; honours prefers-reduced-motion by settling before drawing.
    static let graphJS = """
    (function () {
      const g = window.NETHERITE_GRAPH, c = document.getElementById('graph');
      if (!g || !c) return;
      const ctx = c.getContext('2d'), dpr = window.devicePixelRatio || 1;
      const css = getComputedStyle(document.documentElement);
      const color = n => css.getPropertyValue(n).trim();
      const nodes = g.nodes.map((n, i) => ({ ...n, x: Math.cos(i) * 200 * Math.random(), y: Math.sin(i) * 200 * Math.random(), vx: 0, vy: 0, deg: 0 }));
      const byId = Object.fromEntries(nodes.map(n => [n.id, n]));
      const links = g.links.filter(l => byId[l.source] && byId[l.target]).map(l => ({ s: byId[l.source], t: byId[l.target] }));
      links.forEach(l => { l.s.deg++; l.t.deg++; });
      let scale = 1, ox = 0, oy = 0, alpha = 1;
      function resize() { c.width = c.clientWidth * dpr; c.height = c.clientHeight * dpr; }
      function step() {
        for (const a of nodes) for (const b of nodes) {
          if (a === b) continue;
          const dx = a.x - b.x, dy = a.y - b.y, d2 = dx * dx + dy * dy + 0.01, f = 900 / d2;
          a.vx += dx * f * alpha; a.vy += dy * f * alpha;
        }
        for (const l of links) {
          const dx = l.t.x - l.s.x, dy = l.t.y - l.s.y, d = Math.sqrt(dx * dx + dy * dy) || 1, f = (d - 80) * 0.02 * alpha;
          l.s.vx += dx / d * f; l.s.vy += dy / d * f; l.t.vx -= dx / d * f; l.t.vy -= dy / d * f;
        }
        for (const n of nodes) { n.vx -= n.x * 0.01 * alpha; n.vy -= n.y * 0.01 * alpha; n.x += n.vx; n.y += n.vy; n.vx *= 0.6; n.vy *= 0.6; }
        alpha *= 0.985;
      }
      function draw() {
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.clearRect(0, 0, c.clientWidth, c.clientHeight);
        ctx.translate(c.clientWidth / 2 + ox, c.clientHeight / 2 + oy); ctx.scale(scale, scale);
        ctx.strokeStyle = color('--faint'); ctx.lineWidth = 1 / scale;
        for (const l of links) { ctx.beginPath(); ctx.moveTo(l.s.x, l.s.y); ctx.lineTo(l.t.x, l.t.y); ctx.stroke(); }
        ctx.fillStyle = color('--accent'); ctx.font = (12 / scale) + 'px -apple-system, sans-serif'; ctx.textAlign = 'center';
        for (const n of nodes) {
          const r = 4 + Math.sqrt(n.deg) * 2;
          ctx.beginPath(); ctx.arc(n.x, n.y, r, 0, Math.PI * 2); ctx.fill();
          if (scale > 0.6) { ctx.fillStyle = color('--text'); ctx.fillText(n.label, n.x, n.y + r + 12 / scale); ctx.fillStyle = color('--accent'); }
        }
      }
      function loop() { step(); draw(); if (alpha > 0.02) requestAnimationFrame(loop); }
      function toWorld(e) { const r = c.getBoundingClientRect(); return { x: (e.clientX - r.left - c.clientWidth / 2 - ox) / scale, y: (e.clientY - r.top - c.clientHeight / 2 - oy) / scale }; }
      function hit(e) { const p = toWorld(e); return nodes.find(n => Math.hypot(n.x - p.x, n.y - p.y) < 8 + Math.sqrt(n.deg) * 2); }
      let drag = null, pan = null;
      c.addEventListener('pointerdown', e => { drag = hit(e); pan = drag ? null : { x: e.clientX - ox, y: e.clientY - oy, moved: false }; c.setPointerCapture(e.pointerId); });
      c.addEventListener('pointermove', e => {
        if (drag) { const p = toWorld(e); drag.x = p.x; drag.y = p.y; drag.moved = true; draw(); }
        else if (pan) { ox = e.clientX - pan.x; oy = e.clientY - pan.y; draw(); }
      });
      c.addEventListener('pointerup', e => { if (drag && !drag.moved) location.href = (window.NETHERITE_ROOT || '') + drag.id; if (drag) drag.moved = false; drag = null; pan = null; });
      c.addEventListener('wheel', e => { e.preventDefault(); scale = Math.min(4, Math.max(0.2, scale * (e.deltaY < 0 ? 1.1 : 0.9))); draw(); }, { passive: false });
      window.addEventListener('resize', () => { resize(); draw(); });
      resize();
      if (matchMedia('(prefers-reduced-motion: reduce)').matches) { while (alpha > 0.02) step(); draw(); } else loop();
    })();
    """
}

/// Collects attachment paths referenced while rendering (closures must be Sendable).
final class AttachmentLog: @unchecked Sendable {
    private let lock = NSLock()
    private var set = Set<String>()
    func add(_ p: String) { lock.lock(); set.insert(p); lock.unlock() }
    var paths: Set<String> { lock.lock(); defer { lock.unlock() }; return set }
}
