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

// R13-01: a rewritten alias block keeps non-ASCII text literal and on one line.
@Test func rewrittenAliasKeepsUnicodeLiteral() throws {
    let long = String(repeating: "palabra ", count: 15) + "fin"
    let t = "---\nautor: &a José Núñez 🎉\nrevisor: *a\nnota: &n \(long)\notra: *n\n---\nT"
    var props = NoteParser.parse(t).properties
    props[0].value = .text("Otra")
    props[2].value = .text("x")
    let out = try Frontmatter.replacing(in: t, with: props)
    #expect(out.contains("revisor: \"José Núñez 🎉\"") || out.contains("revisor: José Núñez 🎉"))
    #expect(out.contains("otra: \(long)\n"))
}

// R13-01: emoji are written literally by every serialize path, and literal `\U…` text is untouched.
@Test func emojiPropertiesStayLiteral() throws {
    let props = [Property(key: "t", value: .text("José 🎉")), Property(key: "raw", value: .text(#"x\U0001F389"#)),
                 Property(key: "q", value: .text(#"say "hi" \U0001F389 🎉"#))]
    let out = try Frontmatter.replacing(in: "B", with: props)
    #expect(out.contains("🎉"))
    #expect(NoteParser.parse(out).properties.map(\.value) == props.map(\.value))
}

// R14-01: a literal `\U…` inside a `"` that isn't a double-quoted scalar is never rewritten.
@Test func literalEscapesOutsideDoubleQuotesSurvive() throws {
    let props = [Property(key: "k", value: .text(#"a "b \U0001F600 c" d"#)), Property(key: "n", value: .text(#"a "x \U0000000A y" z"#))]
    let out = try Frontmatter.replacing(in: "B", with: props)
    #expect(NoteParser.parse(out).properties.map(\.value) == props.map(\.value))
    let t = "---\nbase: &d printf(\"\\U0001F600\")\nupdated: *d\n---\nT"
    var p2 = NoteParser.parse(t).properties
    let before = p2[1].value
    p2[0].value = .text("hi")
    #expect(NoteParser.parse(try Frontmatter.replacing(in: t, with: p2)).property("updated") == before)
}

// R14-02: bases keep accents and emoji literal and long expressions on one line.
@Test func baseFileWritesUnicodeLiterally() throws {
    let long = "file.inFolder(\"Proyectos/Año 2026\") && note.autor == \"José\" && note.estado == \"en curso 🎉\" && priority > 2"
    let yaml = "filters: '\(long.replacingOccurrences(of: "'", with: "''"))'\nviews:\n  - type: table\n    name: Próximos 🎉\n"
    let out = BaseFile.parse(yaml).yaml
    #expect(out.contains("Próximos 🎉"))
    #expect(out.contains("Año 2026"))
    #expect(!out.contains(#"\x"#))
}

// R15-01: one stray quote elsewhere doesn't keep every emoji escaped.
@Test func strayQuoteDoesNotBlockLiteralEmoji() throws {
    let yaml = "filters: 'width == \"5'\nproperties:\n  note.a:\n    displayName: \"Á 🎉\"\nviews:\n  - type: table\n    name: Próximos 🎉\n    note: a \"b\n"
    let out = BaseFile.parse(yaml).yaml
    #expect(!out.contains(#"\U0001F389"#))
    #expect(BaseFile.parse(out).yaml == out)
}

// R16-01: the per-line retry stays bounded when a stray quote meets many emoji lines.
@Test func strayQuoteWithManyEmojiStaysFast() throws {
    let keys = (0..<400).map { "  k\($0): \"🎉 \($0)\"" }.joined(separator: "\n")
    let text = "---\nmeta:\n  bad: 'x\"y'\n\(keys)\n---\nT"
    let start = Date()
    _ = NoteParser.parse(text)
    #expect(Date().timeIntervalSince(start) < 0.2)
}
