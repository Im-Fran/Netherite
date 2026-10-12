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

// R6-02: a note that starts with a horizontal rule isn't read as frontmatter after import.
@Test func importedLeadingRuleIsNotFrontmatter() throws {
    #expect(HTMLToMarkdown().convert("<hr><p>Date: 2020</p><hr><p>Body</p>").hasPrefix("***\n"))
    let enex = """
    <?xml version="1.0" encoding="UTF-8"?>
    <en-export><note><title>Two</title><content><![CDATA[<en-note><hr/><div>Just a sentence.</div><hr/><div>Rest</div></en-note>]]></content><tag>keep</tag></note></en-export>
    """
    let vault = tempVault()
    try FileManager.default.createDirectory(at: vault.root, withIntermediateDirectories: true)
    let url = vault.root.appending(path: "x.enex")
    try Data(enex.utf8).write(to: url)
    let report = try Importer(vault: vault, destination: "E").run(.evernote, from: url)
    let text = try vault.read(try #require(report.notes.first))
    #expect(NoteParser.parse(text).properties == [Property(key: "tags", value: .list(["keep"]))])
    #expect(text.contains("Just a sentence."))
}

// R6-03: a move rewrites links from the disk text of notes edited externally since they were indexed,
// but keeps the in-memory text of the notes the caller marks as unsaved.
@MainActor @Test func moveRewritesFreshDiskText() async throws {
    let vault = tempVault()
    try vault.write("target", to: "A.md")
    try vault.write("links [[A]]", to: "B.md")
    try vault.write("links [[A]]", to: "D.md")
    let index = VaultIndex(vault: vault)
    await index.load()
    try await Task.sleep(for: .milliseconds(1100))
    try vault.write("links [[A]] plus an external edit", to: "B.md")
    index.update("D.md", text: "links [[A]] unsaved")
    try index.move("A.md", to: "C.md", skipping: ["D.md"])
    #expect(try vault.read("B.md") == "links [[C]] plus an external edit")
    #expect(index.notes["B.md"]?.text == "links [[C]] plus an external edit")
    #expect(try vault.read("D.md") == "links [[C]] unsaved")
}

// R6-04: a highlight can end right after a link, and `#` glued to a link isn't a tag.
@Test func highlightAfterLinkAndTagGluedToLink() {
    #expect(HTMLRenderer.render("==see [a](b)== end", context: ctx).contains("<mark>see <a"))
    #expect(!HTMLRenderer.render("after [x](y)#t2", context: ctx).contains("class=\"tag\""))
}

// R6-05: `%%` and `==` split across adjacent text nodes stay literal text.
@Test func escapeAcrossTextNodes() {
    let md = HTMLToMarkdown().convert("<p><span>50%</span><span>%secret</span> <span>2%</span><span>% end</span></p>"
                                      + "<p><span>a=</span><span>=b c=</span><span>=d</span></p>")
    let html = HTMLRenderer.render(md, context: ctx)
    #expect(html.contains("secret"))
    #expect(!html.contains("<mark>"))
}

// R6-06: saving a note keeps its creation date.
@Test func writeKeepsCreationDate() throws {
    let vault = tempVault()
    try vault.write("one", to: "A.md")
    let created = { try vault.url(for: "A.md").resourceValues(forKeys: [.creationDateKey]).creationDate }
    let before = try created()
    Thread.sleep(forTimeInterval: 1.1)
    try vault.write("two", to: "A.md")
    #expect(try created() == before)
    #expect(try vault.read("A.md") == "two")
}
