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

// R11-02: an alias copied in a merge keeps the source's value instead of a same-named anchor in the target.
@Test func mergedAliasIgnoresTargetAnchor() throws {
    let out = try Frontmatter.merging("---\nother: &d 2020-01-01\nupdated: *d\n---\nS", into: "---\nother: x\nmine: &d 1999-01-01\n---\nT")
    #expect(NoteParser.parse(out).property("updated") == .date(Frontmatter.parseDate("2020-01-01")!))
    #expect(NoteParser.parse(out).property("mine") == .date(Frontmatter.parseDate("1999-01-01")!))
}
