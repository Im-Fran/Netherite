import Foundation
import Testing
@testable import NetheriteCore

// R11-01: rewriting the key that holds an anchor reserializes the alias that leaned on it, so the note still parses.
@Test func rewritingAnchorKeyKeepsAliasResolvable() throws {
    let date = PropertyValue.date(Frontmatter.parseDate("2024-01-01")!)
    let t = "---\nbase: &d 2024-01-01\nupdated: *d\n---\nT"
    var props = NoteParser.parse(t).properties
    props[0].value = .text("hello")
    let edited = try Frontmatter.replacing(in: t, with: props)
    #expect(NoteParser.parse(edited).property("base") == .text("hello"))
    #expect(NoteParser.parse(edited).property("updated") == date)
    let merged = try Frontmatter.merging("---\nbase: [x]\n---\nS", into: t)
    #expect(NoteParser.parse(merged).property("base") == .list(["2024-01-01", "x"]))
    #expect(NoteParser.parse(merged).property("updated") == date)
}
