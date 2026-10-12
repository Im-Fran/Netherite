import Foundation
import Testing
@testable import NetheriteCore

@Test func graphBuild() {
    let files = ["A.md", "B.md", "C.md", "D.md", "img.png"]
    let out = ["A.md": ["B.md"], "B.md": ["C.md"], "C.md": [], "D.md": []]
    let unresolved = ["A.md": ["Ghost"]]
    let tags = ["A.md": ["x"], "D.md": ["x"]]
    var s = GraphSettings()
    var g = GraphData.build(files: files, outgoing: out, unresolved: unresolved, tags: tags, settings: s)
    #expect(g.nodes.map(\.id) == ["A.md", "B.md", "C.md", "D.md"])
    #expect(g.edges.count == 2)
    #expect(g.nodes.first { $0.id == "B.md" }?.degree == 2)

    s.showOrphans = false
    g = GraphData.build(files: files, outgoing: out, unresolved: unresolved, tags: tags, settings: s)
    #expect(!g.nodes.contains { $0.id == "D.md" })

    s = GraphSettings(); s.showTags = true; s.showUnresolved = true; s.showAttachments = true
    g = GraphData.build(files: files, outgoing: out, unresolved: unresolved, tags: tags, settings: s)
    #expect(g.nodes.contains { $0.id == "#x" && $0.degree == 2 })
    #expect(g.nodes.contains { $0.id == "unresolved:Ghost" })
    #expect(g.nodes.contains { $0.id == "img.png" })

    // Local graph: depth 1 from C reaches B only; depth 2 reaches A.
    s = GraphSettings()
    g = GraphData.build(files: files, outgoing: out, unresolved: [:], tags: [:], settings: s, focus: "C.md")
    #expect(Set(g.nodes.map(\.id)) == ["B.md", "C.md"])
    s.depth = 2
    g = GraphData.build(files: files, outgoing: out, unresolved: [:], tags: [:], settings: s, focus: "C.md")
    #expect(Set(g.nodes.map(\.id)) == ["A.md", "B.md", "C.md"])

    s = GraphSettings(); s.search = "b"
    g = GraphData.build(files: files, outgoing: out, unresolved: [:], tags: [:], settings: s)
    #expect(g.nodes.map(\.id) == ["B.md"])
}

// R4-08: the graph only rebuilds when links, files or tags change, not on every keystroke.
@MainActor @Test func linkRevisionIgnoresPlainTyping() async throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let vault = Vault(root: dir)
    try vault.write("Hi [[B]]", to: "A.md")
    try vault.write("B", to: "B.md")
    let index = VaultIndex(vault: vault)
    await index.load()
    var seen = index.linkRevision
    index.update("A.md", text: "Hi there [[B]]")
    #expect(index.linkRevision == seen)
    for text in ["Hi there [[B]] [[C]]", "Hi there [[B]] [[C]] #tag", "Hi there"] {
        index.update("A.md", text: text)
        #expect(index.linkRevision > seen)
        seen = index.linkRevision
    }
}
