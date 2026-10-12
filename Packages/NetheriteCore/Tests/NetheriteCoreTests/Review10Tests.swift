import Foundation
import Testing
@testable import NetheriteCore

// R10-01: a number, date or checkbox in the target joins a source list instead of being replaced by it.
@Test func mergeKeepsNonTextScalarsWhenJoiningLists() throws {
    let x = { (target: String) in NoteParser.parse(try Frontmatter.merging("---\nx: [a]\n---\nS", into: "---\nx: \(target)\n---\nT")).property("x") }
    #expect(try x("5") == .list(["5", "a"]))
    #expect(try x("2024-01-02") == .list(["2024-01-02", "a"]))
    #expect(try x("true") == .list(["true", "a"]))
}

// R10-02: a key copied verbatim with an alias whose anchor stays behind is reserialized, so the target still parses.
@Test func mergeReserializesAliasWithoutAnchor() throws {
    let out = try Frontmatter.merging("---\nbase: &d 2024-01-01\nupdated: *d\n---\nS", into: "---\nbase: 2023-01-01\n---\nT")
    #expect(NoteParser.parse(out).property("updated") == .date(Frontmatter.parseDate("2024-01-01")!))
    #expect(NoteParser.parse(out).property("base") == .date(Frontmatter.parseDate("2023-01-01")!))
}

// R10-03: following an unresolved link names the new note without its `.md`, and creates none for other file types.
@Test func newNoteNameForUnresolvedLinks() {
    #expect(LinkResolver.newNoteName(for: "Plan.md") == "Plan")
    #expect(LinkResolver.newNoteName(for: "Sub/My Note.MD") == "My Note")
    #expect(LinkResolver.newNoteName(for: "Plan") == "Plan")
    #expect(LinkResolver.newNoteName(for: "Release v1.2") == "Release v1.2")
    #expect(LinkResolver.newNoteName(for: "Diagram.canvas") == nil)
    #expect(LinkResolver.newNoteName(for: "Tasks.base") == nil)
    #expect(LinkResolver.newNoteName(for: "img/photo.png") == nil)
}
