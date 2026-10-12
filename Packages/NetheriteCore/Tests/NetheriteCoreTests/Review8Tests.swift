import Foundation
import Testing
@testable import NetheriteCore

// R8-01: a symlinked note is dated by its target, so external edits to the target are seen.
@MainActor @Test func refreshSeesEditsThroughSymlink() async throws {
    let vault = tempVault()
    try FileManager.default.createDirectory(at: vault.root, withIntermediateDirectories: true)
    let outside = FileManager.default.temporaryDirectory.appending(path: "out-\(UUID().uuidString).md")
    try Data("v1".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(at: vault.url(for: "B.md"), withDestinationURL: outside)
    let index = VaultIndex(vault: vault)
    await index.load()
    try Data("v2".utf8).write(to: outside)
    try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(60)], ofItemAtPath: outside.path(percentEncoded: false))
    await index.refreshFromDisk()
    #expect(index.notes["B.md"]?.text == "v2")
}

// R8-02: an `=` line inside a blockquote or a nested list item stays text, not a setext heading underline.
@Test func importEscapesEqualsLineInQuotesAndLists() {
    let c = HTMLToMarkdown()
    #expect(c.convert("<blockquote><div>Title</div><div>=</div></blockquote>") == "> Title\n> \\=\n")
    let nested = c.convert("<ul><li>a<ul><li>b<ul><li>c<br>=</li></ul></li></ul></li></ul>")
    #expect(nested.hasSuffix("\\=\n"), "\(nested.debugDescription)")
}

// R8-03: literal U+E000/U+E001 in code, links, images or entities can't pose as the importer's `%`/`=` markers.
@Test func importNeutralizesLiteralMarkers() {
    let md = HTMLToMarkdown().convert("<pre>a\u{E000}\u{E001}b</pre><p><code>x\u{E000}y</code> <a href=\"u\u{E001}\">l</a> <img src=\"s\u{E000}\" alt=\"&#xE001;\"></p>")
    #expect(!md.contains("%") && !md.contains("=") && !md.contains("\u{E000}") && !md.contains("\u{E001}"), "\(md.debugDescription)")
}

// R8-04: a tag right after inline math renders as a tag, as the index counts it.
@Test func tagAfterInlineMathRenders() {
    let ctx = RenderContext(source: "A.md", resolve: { _, _ in nil }, readNote: { _ in nil },
                            linkHref: { _, t, _ in t }, assetURL: { $0 }, tagHref: { "tag:" + $0 })
    #expect(NoteParser.parse("$x$#tag").tags == ["tag"])
    #expect(HTMLRenderer.render("$x$#tag", context: ctx).contains("<a class=\"tag\" href=\"tag:tag\">#tag</a>"))
    #expect(HTMLRenderer.render("==$x$==", context: ctx).contains("<mark>"))
}
