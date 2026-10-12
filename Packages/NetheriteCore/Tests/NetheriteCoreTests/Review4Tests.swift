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
