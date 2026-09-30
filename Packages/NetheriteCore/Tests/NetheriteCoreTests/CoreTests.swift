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
