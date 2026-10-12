import Foundation
import Testing
@testable import NetheriteCore

// R9-01: tags and aliases join even when one side is a scalar, and so does any key with a list on either side.
@Test func mergeJoinsScalarAndListTagsAndAliases() throws {
    let tags = NoteParser.parse(try Frontmatter.merging("---\ntags: foo\n---\nS", into: "---\ntags:\n  - a\n---\nT")).tags
    #expect(tags == ["a", "foo"])
    let back = NoteParser.parse(try Frontmatter.merging("---\ntags:\n  - b\n---\nS", into: "---\ntags: a\n---\nT")).tags
    #expect(back == ["a", "b"])
    let aliases = NoteParser.parse(try Frontmatter.merging("---\naliases: s\n---\nS", into: "---\naliases: [t]\n---\nT")).aliases
    #expect(aliases == ["t", "s"])
    let list = NoteParser.parse(try Frontmatter.merging("---\nx: b\n---\nS", into: "---\nx: [a]\n---\nT")).property("x")
    #expect(list == .list(["a", "b"]))
    // Two scalars of another key keep the target's value, and nothing new leaves the target untouched.
    #expect(try Frontmatter.merging("---\nx: b\n---\nS", into: "---\nx: a\n---\nT") == "---\nx: a\n---\nT")
    #expect(try Frontmatter.merging("---\ntags: a\n---\nS", into: "---\ntags: a # c\n---\nT") == "---\ntags: a # c\n---\nT")
}

// R9-02: keys new to the target keep their YAML: nested mappings, dates and hex aren't reserialized.
@Test func mergeCopiesNewKeysVerbatim() throws {
    let source = "---\ngeo:\n  lat: 1\n  lng: 2\nwhen: 2024-01-02T10:30:15\nn: 0x1F\n---\nS"
    let block = "geo:\n  lat: 1\n  lng: 2\nwhen: 2024-01-02T10:30:15\nn: 0x1F"
    #expect(try Frontmatter.merging(source, into: "---\nx: 1\n---\nT") == "---\nx: 1\n\(block)\n---\nT")
    #expect(try Frontmatter.merging(source, into: "T") == "---\n\(block)\n---\nT")
    // A joined list is still reserialized next to the verbatim keys.
    let out = try Frontmatter.merging("---\ntags: [b]\nn: 0x1F\n---\nS", into: "---\ntags: [a]\n---\nT")
    #expect(out == "---\ntags:\n  - a\n  - b\nn: 0x1F\n---\nT")
}
