import Foundation
import Testing
@testable import NetheriteCore

// R5-07: invalid YAML is never rewritten (it would wipe every key), and keys with `: ` are quoted.
@Test func invalidFrontmatterIsNotRewritten() throws {
    let text = "---\ntitle: Meeting: Q3\ntags: [work]\n---\nBody"
    #expect(throws: Frontmatter.InvalidYAML.self) { try Frontmatter.replacing(in: text, with: [Property(key: "due", value: .text(""))]) }
    let out = try Frontmatter.replacing(in: "---\na: 1\n---\nB", with: [Property(key: "a", value: .number(1)), Property(key: "x: y", value: .text("z"))])
    #expect(NoteParser.parse(out).properties == [Property(key: "a", value: .number(1)), Property(key: "x: y", value: .text("z"))])
}
