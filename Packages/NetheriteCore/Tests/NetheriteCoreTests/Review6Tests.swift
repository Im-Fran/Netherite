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
