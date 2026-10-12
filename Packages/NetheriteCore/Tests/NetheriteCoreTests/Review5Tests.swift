import Foundation
import Testing
@testable import NetheriteCore

private let ctx = RenderContext(source: "A.md", resolve: { _, _ in nil }, readNote: { _ in nil },
                                linkHref: { _, t, _ in t }, assetURL: { $0 }, tagHref: { "tag:" + $0 })

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

// R5-02: imported text can't turn into a setext heading, a fence, strikethrough, math or a hidden comment.
@Test func htmlTextEscapesObsidianSyntax() {
    let md = HTMLToMarkdown().convert("<p>Title<br>---</p><p>~~~</p><p>~~gone~~ costs $5 and $6, %%hidden%%</p>")
    let parsed = NoteParser.parse(md)
    #expect(parsed.headings.isEmpty)
    #expect(md.contains("\\---") && md.contains("\\~\\~\\~") && !md.contains("%%"))
    let html = HTMLRenderer.render(md, context: ctx)
    #expect(html.contains("hidden") && html.contains("$5 and $6") && html.contains("~~gone~~") && !html.contains("<del>") && !html.contains("math"))
}

// R5-03: `%%comments%%` (and frontmatter, code, math) never reach the published search index.
@MainActor @Test func publishedSearchSkipsComments() async throws {
    let vault = tempVault()
    try vault.write("---\nsecret: fm\n---\nHello %%private note%% world `code` $x^2$\n", to: "A.md")
    let index = VaultIndex(vault: vault)
    await index.load()
    let out = vault.root.appending(path: "site")
    defer { try? FileManager.default.removeItem(at: vault.root) }
    _ = try await SiteExporter.export(index, to: out)
    let search = try String(contentsOf: out.appending(path: "search.json"), encoding: .utf8)
    #expect(search.contains("Hello world"))
    #expect(!search.contains("private") && !search.contains("secret") && !search.contains("code") && !search.contains("x^2"))
}
