import Foundation
import Testing
@testable import NetheriteCore

// R4-15: a Markdown link title never crosses a blank line, so it can't swallow the links and tags after it.
@Test func mdLinkTitleStopsAtBlankLine() {
    let parsed = NoteParser.parse("[a](b 'x\n\nSome [[Wiki]] and #tag\n\ny')")
    #expect(parsed.links.map(\.target) == ["Wiki"])
    #expect(parsed.tags == ["tag"])
    #expect(NoteParser.parse("[a](b 'x\ny')").links.map(\.target) == ["b"])
}

// R4-14: rewriting a Markdown link on rename keeps its title.
@Test func renameKeepsMarkdownLinkTitle() {
    let text = "See [x](Old.md 'Tip') and [y](Old.md#H \"T2\")\n"
    let out = VaultIndex.rewriteLinks(in: text, parsed: NoteParser.parse(text), newTarget: { _ in "New.md" }, linkText: { $0 })
    #expect(out == "See [x](New.md 'Tip') and [y](New.md#H \"T2\")\n")
}

// R4-13: only a real reference definition hides its `#…` destination from the tags.
@Test func refDefNeedsDestinationAndOptionalTitleOnly() {
    #expect(NoteParser.parse("[r]: is my #todo item").tags == ["todo"])
    #expect(NoteParser.parse("[r]: #Intro\n#real").tags == ["real"])
    #expect(NoteParser.parse("[r]: #Intro 'Title'").tags.isEmpty)
    #expect(NoteParser.parse("[r]: <#Intro> \"t\"").tags.isEmpty)
}
