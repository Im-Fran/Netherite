import Foundation
import Testing
@testable import NetheriteCore

private let ctx = RenderContext(source: "A.md", resolve: { _, _ in nil }, readNote: { _ in nil },
                                linkHref: { _, t, _ in t }, assetURL: { $0 }, tagHref: { "tag:" + $0 })

// R6-01: long scalars (values, list items, keys) aren't folded at 80 columns into invalid YAML.
@Test func longScalarsStayValidYAML() throws {
    let long = String(repeating: "word ", count: 30) + "end"
    let longKey = String(repeating: "k ", count: 50) + "z"
    let props = [Property(key: "aliases", value: .list([long, "a\nb: c"])), Property(key: "q", value: .text(long + ": colon")),
                 Property(key: longKey, value: .text(long))]
    let out = try Frontmatter.replacing(in: "Body", with: props)
    #expect(NoteParser.parse(out).properties == props)
    #expect(throws: Never.self) { try Frontmatter.replacing(in: out, with: []) }
}
