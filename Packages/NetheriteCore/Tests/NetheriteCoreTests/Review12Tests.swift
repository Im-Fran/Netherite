import Foundation
import Testing
import Yams
@testable import NetheriteCore

// R12-01: when a kept alias loses its anchor, only that block is rewritten; comments and nested maps elsewhere survive.
@Test func brokenAliasKeepsUnrelatedYAML() throws {
    let t = "---\n# keep me\nmeta:\n  a: 1\n  b: [x]\nbase: &d 2024-01-01\nupdated: *d\n---\nT"
    var props = NoteParser.parse(t).properties
    props[1].value = .text("hi")
    let out = try Frontmatter.replacing(in: t, with: props)
    #expect(out.hasPrefix("---\n# keep me\nmeta:\n  a: 1\n  b: [x]\nbase: hi\n"))
    #expect(NoteParser.parse(out).property("updated") == .date(Frontmatter.parseDate("2024-01-01")!))
}

// R12-01: an alias to a nested map stays a map after its anchor's key is rewritten.
@Test func brokenAliasToMapStaysMap() throws {
    let t = "---\nbase: &b\n  x: 1\nchild: *b\n---\nT"
    var props = NoteParser.parse(t).properties
    props[0].value = .text("hi")
    let out = try Frontmatter.replacing(in: t, with: props)
    let node = try Yams.compose(yaml: Frontmatter.locate(in: out)!.yaml)
    #expect(node?["child"]?["x"]?.int == 1)
    #expect(NoteParser.parse(out).property("base") == .text("hi"))
}
