import Foundation
import Testing
@testable import NetheriteCore

let sample = """
---
tags: [project, travel/japan]
aliases: [JP]
rating: 4
done: false
date: 2024-05-01
related: "[[Budget]]"
---
# Japan Trip
See [[Flights#Outbound|flights]] and ![[map.png]] plus [md](Notes/Hotels.md).
Inline #idea and #2024 (not a tag) and `[[NotALink]]` #in-code-no

```
[[AlsoNotALink]] #nope
```
$$ #notmath $$
%% [[Hidden]] %%
- [ ] book ryokan ^task1
- [x] ask Keiko
## Budget ##
Footnote here[^1].

[^1]: The note.
"""

@Test func parsesOFM() {
    let p = NoteParser.parse(sample)
    #expect(p.links.map(\.target) == ["Budget", "Flights", "map.png", "Notes/Hotels.md"])
    #expect(p.links[1].subpath == "Outbound" && p.links[1].alias == "flights")
    #expect(p.links[2].isEmbed)
    #expect(p.tags == ["project", "travel/japan", "idea", "in-code-no"])
    #expect(p.aliases == ["JP"])
    #expect(p.headings.map(\.text) == ["Japan Trip", "Budget"])
    #expect(p.headings.map(\.level) == [1, 2])
    #expect(p.blockIDs["task1"] != nil)
    #expect(p.tasks.open == 1 && p.tasks.done == 1)
    #expect(p.footnotes.first?.label == "1")
    #expect(p.property("rating") == .number(4))
    #expect(p.property("done") == .bool(false))
    if case .date = p.property("date") {} else { Issue.record("date not parsed") }
}

@Test func frontmatterRoundTrip() {
    let props = [Property(key: "tags", value: .list(["a", "b c"])), Property(key: "title", value: .text("Hi: there"))]
    let text = Frontmatter.replacing(in: "body", with: props)
    #expect(NoteParser.parse(text).properties == props)
    #expect(Frontmatter.replacing(in: text, with: []) == "body")
}

@Test func resolvesLinks() {
    let r = LinkResolver(files: ["A.md", "x/B.md", "y/B.md", "img/map.png", "x/C.md"])
    #expect(r.resolve("A", from: "x/C.md") == "A.md")
    #expect(r.resolve("B", from: "y/Z.md") == "y/B.md")
    #expect(r.resolve("x/B", from: "A.md") == "x/B.md")
    #expect(r.resolve("map.png", from: "A.md") == "img/map.png")
    #expect(r.resolve("Missing", from: "A.md") == nil)
    #expect(r.linkText(for: "x/B.md") == "x/B")
    #expect(r.linkText(for: "x/C.md") == "C")
}

@MainActor @Test func indexBacklinksAndRename() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let vault = Vault(root: dir)
    try vault.write("Link to [[B]] and [[B#H|alias]].", to: "A.md")
    try vault.write("# H\nB mentions A plainly.", to: "B.md")
    try vault.write("[b](B.md)", to: "sub/C.md")
    let index = VaultIndex(vault: vault)
    await index.load()
    #expect(index.backlinks(for: "B.md").map(\.source) == ["A.md", "sub/C.md"])
    #expect(index.unlinkedMentions(for: "A.md").map(\.source) == ["B.md"])

    let changed = try index.move("B.md", to: "folder/Renamed.md")
    #expect(Set(changed) == ["A.md", "sub/C.md"])
    #expect(try vault.read("A.md") == "Link to [[Renamed]] and [[Renamed#H|alias]].")
    #expect(try vault.read("sub/C.md") == "[b](folder/Renamed.md)")
    #expect(index.backlinks(for: "folder/Renamed.md").count == 2)
    try? FileManager.default.removeItem(at: dir)
}

@Test func searchOperators() {
    let notes = [
        "a.md": NoteRecord(path: "a.md", text: "Hello world #x\n- [ ] buy milk", parsed: NoteParser.parse("Hello world #x\n- [ ] buy milk"), modified: .now, created: .now),
        "b.md": NoteRecord(path: "b.md", text: "---\nstatus: draft\n---\nhello there", parsed: NoteParser.parse("---\nstatus: draft\n---\nhello there"), modified: .now, created: .now),
    ]
    #expect(Search.run(SearchQuery("hello"), in: notes).map(\.path) == ["a.md", "b.md"])
    #expect(Search.run(SearchQuery("hello -world"), in: notes).map(\.path) == ["b.md"])
    #expect(Search.run(SearchQuery("tag:#x"), in: notes).map(\.path) == ["a.md"])
    #expect(Search.run(SearchQuery("[status:draft]"), in: notes).map(\.path) == ["b.md"])
    #expect(Search.run(SearchQuery("task:milk"), in: notes).map(\.path) == ["a.md"])
    #expect(Search.run(SearchQuery("\"hello world\""), in: notes).map(\.path) == ["a.md"])
    #expect(Search.run(SearchQuery("/wor.d/"), in: notes).map(\.path) == ["a.md"])
    #expect(Search.run(SearchQuery("zzz OR there"), in: notes).map(\.path) == ["b.md"])
    #expect(Search.fuzzyScore("jt", "Japan Trip") != nil)
    #expect(Search.fuzzyScore("xz", "Japan Trip") == nil)
}

@Test func highlighterSpans() {
    let t = "# Title\nSome **bold** and *it* with [[Note|alias]] and `code **x**` #tag\n- [x] done"
    let spans = MarkdownHighlighter.spans(t)
    let ns = t as NSString
    func texts(_ k: StyleSpan.Kind) -> [String] { spans.filter { $0.kind == k }.map { ns.substring(with: $0.range) } }
    #expect(texts(.heading(1)) == ["# Title"])
    #expect(texts(.bold) == ["**bold**"])
    #expect(texts(.italic) == ["*it*"])
    #expect(texts(.inlineCode) == ["`code **x**`"])
    #expect(texts(.tag) == ["#tag"])
    #expect(texts(.task(done: true)) == ["[x]"])
    #expect(texts(.link(target: "Note", embed: false)) == ["[[Note|alias]]"])
    #expect(texts(.marker).contains("Note|"))
}

@Test func templates() {
    var c = DateComponents(); c.year = 2024; c.month = 3; c.day = 9; c.hour = 14; c.minute = 5
    let d = Calendar.current.date(from: c)!
    #expect(Templates.render("# {{title}} {{date}} {{time}} {{date:YYYY/MM/DD}}", title: "T", date: d) == "# T 2024-03-09 14:05 2024/03/09")
    var s = VaultSettings(); s.dailyNotes.folder = "Journal"; s.dailyNotes.format = "YYYY-MM-DD"
    #expect(Templates.dailyNotePath(for: d, settings: s) == "Journal/2024-03-09.md")
    #expect(Templates.unicodePattern("[Week] ww") == "'Week' ww")
}

@Test func rendersHTML() {
    let files = ["Other.md", "img.png"]
    let r = LinkResolver(files: files)
    let ctx = RenderContext(
        source: "A.md", resolve: { r.resolve($0, from: $1) },
        readNote: { $0 == "Other.md" ? "# Sec\nembedded body\n# Next\nno" : nil },
        linkHref: { p, t, _ in p.map { "open:\($0)" } ?? "new:\(t)" },
        assetURL: { "asset:\($0)" }, tagHref: { "tag:\($0)" })
    let md = """
    ---
    k: v
    ---
    Link [[Other|alias]] and [[Missing]] ==hi== #tag <b onclick="x()">b</b><script>alert(1)</script>
    ![[img.png|100]]
    ![[Other#Sec]]
    `[[nope]]` $x^2$
    > [!warning] Careful
    > body
    - [x] done
    Ref[^a]

    [^a]: foot
    """
    let html = HTMLRenderer.render(md, context: ctx)
    #expect(html.contains("<table class=\"properties\">"))
    #expect(html.contains("href=\"open:Other.md\""))
    #expect(html.contains(">alias</a>"))
    #expect(html.contains("is-unresolved\" href=\"new:Missing\""))
    #expect(html.contains("<mark>hi</mark>"))
    #expect(html.contains("href=\"tag:tag\""))
    #expect(!html.contains("<script>alert") && !html.contains("onclick"))
    #expect(html.contains("src=\"asset:img.png\" alt=\"100\" width=\"100\""))
    #expect(html.contains("embedded body") && !html.contains("no</p>"))
    #expect(html.contains("<code>[[nope]]</code>"))
    #expect(html.contains("data-tex=\"x^2\""))
    #expect(html.contains("data-callout=\"warning\"") && html.contains("Careful"))
    #expect(html.contains("data-line=\"9\" checked"))
    #expect(html.contains("id=\"fn-a\""))
}

@Test func quoteMarkersHiddenNextToInlineCode() {
    let t = "> [!tip] Title\n> Use `> [!note]` here\n> more"
    let ns = t as NSString
    let spans = MarkdownHighlighter.spans(t)
    let markers = spans.filter { $0.kind == .marker }.map { ns.substring(with: $0.range) }
    #expect(markers.contains("> "))
    #expect(spans.filter { $0.kind == .calloutBody("tip") }.count == 2)
}

@Test func detectsTables() {
    let t = "Intro\n| A | B |\n| --- | :-: |\n| 1 | 2 |\nAfter"
    let ns = t as NSString
    let tables = MarkdownHighlighter.spans(t).filter { $0.kind == .table }.map { ns.substring(with: $0.range) }
    #expect(tables == ["| A | B |\n| --- | :-: |\n| 1 | 2 |"])
}

@MainActor @Test(arguments: [false, true]) func guideVaultLinksResolve(spanish: Bool) async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let vault = Vault(root: dir)
    try GuideVault.write(to: vault, spanish: spanish)
    let index = VaultIndex(vault: vault)
    await index.load()
    #expect(index.files.contains(GuideVault.startNote(spanish: spanish)))
    // Only the deliberate "create me" link may be unresolved.
    let missing = index.unresolved.values.flatMap { $0 }
    #expect(missing == [spanish ? "Mi primera idea" : "My first idea"])
    #expect(try JSONCanvas.parse(vault.read(spanish ? "Tablero guía.canvas" : "Guide board.canvas")).nodes.count == 3)
    try? FileManager.default.removeItem(at: dir)
}
