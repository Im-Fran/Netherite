import Foundation
import Testing
@testable import NetheriteCore

// R7-01: a note that is a symlink to a file saves through the link.
@Test func writeThroughFileSymlink() throws {
    let vault = tempVault()
    try FileManager.default.createDirectory(at: vault.root, withIntermediateDirectories: true)
    let outside = FileManager.default.temporaryDirectory.appending(path: "out-\(UUID().uuidString).md")
    try Data("real".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(at: vault.url(for: "L.md"), withDestinationURL: outside)
    try vault.write("saved", to: "L.md")
    #expect(try String(contentsOf: outside, encoding: .utf8) == "saved")
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: vault.url(for: "L.md").path(percentEncoded: false)) == outside.path(percentEncoded: false))
}

// R7-02: a move doesn't recreate a linking note that was deleted outside the app; it drops it from the index.
@MainActor @Test func moveSkipsNotesDeletedElsewhere() async throws {
    let vault = tempVault()
    try vault.write("target", to: "A.md")
    try vault.write("links [[A]]", to: "B.md")
    let index = VaultIndex(vault: vault)
    await index.load()
    try FileManager.default.removeItem(at: vault.url(for: "B.md"))
    #expect(try index.move("A.md", to: "C.md").isEmpty)
    #expect(!vault.exists("B.md"))
    #expect(!index.files.contains("B.md"))
}

private let ctx = RenderContext(source: "A.md", resolve: { _, _ in nil }, readNote: { _ in nil },
                                linkHref: { _, t, _ in t }, assetURL: { $0 }, tagHref: { "tag:" + $0 })

// R7-04: a highlight can wrap a wikilink or inline math.
@Test func highlightWrapsWikilinkAndMath() {
    let wiki = HTMLRenderer.render("==see [[w]] ok==", context: ctx)
    #expect(wiki.contains("<mark>see <a") && wiki.contains("ok</mark>"))
    #expect(HTMLRenderer.render("==$x$==", context: ctx).contains("<mark><span class=\"math math-inline\""))
    #expect(!HTMLRenderer.render("[a ==b](c) d==", context: ctx).contains("<mark>"))
}

// R7-03: a `%` or `=` at the edge of an imported text node stays plain text, escaped only when it pairs with a neighbour.
@Test func importEscapesOnlyPairingPercentAndEquals() {
    let c = HTMLToMarkdown()
    #expect(c.convert("<p>Growth was 50%</p>") == "Growth was 50%\n")
    #expect(c.convert("<p><b>20%</b> off, x=</p>") == "**20%** off, x=\n")
    #expect(c.convert("<p><span>50%</span><span>%s</span> <mark>a</mark><span>=</span></p>") == "50%&#37;s ==a==\\=\n")
    #expect(c.convert("<div>a</div><div>=</div><div>=b</div>") == "a\n\\=\n=b\n")
}
