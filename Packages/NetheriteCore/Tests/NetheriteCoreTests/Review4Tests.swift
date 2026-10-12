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

// R4-12: a highlight that starts inside a link and ends after it isn't rendered (it would mis-nest the HTML).
@Test func highlightCannotStraddleLink() {
    let ctx = RenderContext(source: "A.md", resolve: { _, _ in nil }, readNote: { _ in nil },
                            linkHref: { _, t, _ in t }, assetURL: { $0 }, tagHref: { $0 })
    let html = HTMLRenderer.render("[a ==b](c) d==", context: ctx)
    #expect(!html.contains("<mark>"))
    #expect(html.contains(">a ==b</a> d==</p>"))
    #expect(HTMLRenderer.render("==see [a](b) now== and [x ==y== z](w)", context: ctx).components(separatedBy: "<mark>").count == 3)
}

// R4-15 follow-up: unclosed multi-line titles and definitions stay linear (no catastrophic backtracking).
@Test func unclosedLinkTitlesParseLinearly() {
    for text in ["[a](b \"" + String(repeating: "x\n", count: 20_000),
                 String(repeating: "[a](b \"x\n", count: 20_000), String(repeating: "[a](b 'x\n", count: 20_000),
                 String(repeating: "[a](b (x\n", count: 20_000), String(repeating: "[r]: <x\n", count: 20_000)] {
        let start = Date()
        _ = NoteParser.parse(text)
        #expect(Date().timeIntervalSince(start) < 1)
    }
}

// R4-16: a /regex/ term honours "Match case".
@Test func regexSearchHonoursCaseSensitivity() {
    func regex(_ q: SearchQuery) -> NSRegularExpression? { if case .regex(let r)? = q.terms.first { r } else { nil } }
    #expect(regex(SearchQuery("/Foo/"))?.options.contains(.caseInsensitive) == true)
    #expect(regex(SearchQuery("/Foo/", caseSensitive: true))?.options.contains(.caseInsensitive) == false)
    if case .not(.regex(let r))? = SearchQuery("-/Foo/", caseSensitive: true).terms.first { #expect(!r.options.contains(.caseInsensitive)) }
    else { Issue.record("expected a negated regex") }
}

// R4-17: a database folder with `\` round-trips; a stray `]` doesn't glue the rest of the query together.
@Test func databaseFolderEscapesBackslashAndStrayBracket() {
    #expect(BaseFile.database(folder: #"Notes\2024 "Q1""#).entryFolder == #"Notes\2024 "Q1""#)
    #expect(SearchQuery.tokenize("] foo [k:v] bar") == ["]", "foo", "[k:v]", "bar"])
}

// R4-06: note-name dates are Gregorian with Latin digits whatever the locale.
@Test func templateDatesUseGregorianLatinDigits() {
    let date = Date(timeIntervalSince1970: 1_791_763_200)   // 2026-10-12 UTC
    for id in ["th_TH", "ar_SA", "fa_IR", "ja_JP@calendar=japanese", "en_US", "YYYY-MM-DD"] {
        let f = id == "YYYY-MM-DD" ? Templates.formatter(id) : Templates.formatter("yyyy-MM-dd", locale: Locale(identifier: id))
        f.timeZone = TimeZone(identifier: "UTC")
        #expect(f.string(from: date) == "2026-10-12", "\(id)")
        #expect(f.date(from: "2026-10-12") == date, "\(id)")
    }
}
