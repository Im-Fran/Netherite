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

// R5-01: a `#` or `[` in an imported folder name doesn't cut the full-path links to its files.
@Test func importFolderWithLinkSyntaxKeepsLinks() throws {
    let a = "0123456789abcdef0123456789abcdef"
    let zip = makeZip([
        ("C# [x] \(a).md", Data("![](C%23%20%5Bx%5D%20\(a)/pic.png)\n".utf8)),
        ("C# [x] \(a)/pic.png", Data([7])),
    ])
    let vault = tempVault()
    try FileManager.default.createDirectory(at: vault.root, withIntermediateDirectories: true)
    let url = vault.root.appending(path: "export.zip")
    try zip.write(to: url)
    let report = try Importer(vault: vault, destination: "N").run(.notion, from: url)
    let page = try #require(report.notes.first)
    let links = NoteParser.parse(try vault.read(page)).links
    let target = try #require(links.first.flatMap { LinkResolver(files: vault.allFiles()).resolve($0.target, from: page) })
    #expect(try Data(contentsOf: vault.url(for: target)) == Data([7]))
    try? FileManager.default.removeItem(at: vault.root)
}
