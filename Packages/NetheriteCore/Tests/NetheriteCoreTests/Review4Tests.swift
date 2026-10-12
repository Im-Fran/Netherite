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

// R4-10: an imported title starting with "." doesn't become a hidden note.
@Test func importedTitleNeverHidden() throws {
    #expect(Writer.safeName(".NET tips") == "NET tips")
    #expect(Writer.safeName(" . .x") == "x")
    #expect(!Writer.safeName("...").isEmpty && !Writer.safeName("...").hasPrefix("."))
    let vault = tempVault()
    try FileManager.default.createDirectory(at: vault.root, withIntermediateDirectories: true)
    let src = vault.root.appending(path: "x.html")
    try Data("<html><head><title>.NET tips</title></head><body><p>hi</p></body></html>".utf8).write(to: src)
    let report = try Importer(vault: vault, destination: "H").run(.html, from: src)
    #expect(report.notes == ["H/NET tips.md"] && vault.allFiles().contains("H/NET tips.md"))
}

// R4-11: unclosed tags don't make HTML parsing quadratic.
@Test func htmlParseLinearWithUnclosedTags() {
    let start = Date()
    let md = HTMLToMarkdown().convert(String(repeating: "x <y z ", count: 8_000))
    #expect(Date().timeIntervalSince(start) < 1)
    #expect(md.hasPrefix("x"))
}

// R4-05: HTML text that looks like Markdown stays literal text.
@Test func htmlTextIsEscaped() {
    let md = HTMLToMarkdown().convert("<p>Use the &lt;b&gt; tag and 2 * 3 * 4, a_b, `x`, ==hi==, then [[x]]</p><p># not a heading</p><p>1. not a list</p><p>- nor this</p><p>Keep <b>bold</b> and C# 2.0</p>")
    #expect(md == ##"""
    Use the &lt;b\> tag and 2 \* 3 \* 4, a\_b, \`x\`, \=\=hi\=\=, then \[\[x\]\]

    \# not a heading

    1\. not a list

    \- nor this

    Keep **bold** and C# 2.0

    """##)
    let parsed = NoteParser.parse(md)
    #expect(parsed.links.isEmpty && parsed.headings.isEmpty && parsed.tags.isEmpty)
}

// R4-04: repeated page and file names link to their own page's copy, and collision renames are reflected.
@Test func notionImportKeepsRepeatedNamesApart() throws {
    let a = "0123456789abcdef0123456789abcdef", b = "fedcba9876543210fedcba9876543210"
    let c = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", d = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    let zip = makeZip([
        ("Alpha \(a).md", Data("![](Alpha%20\(a)/image.png)\n[Notes](Alpha%20\(a)/Notes%20\(c).md)\n[Dup](Dup%20\(c).md)\n".utf8)),
        ("Alpha \(a)/image.png", Data([1])),
        ("Alpha \(a)/Notes \(c).md", Data("alpha notes\n".utf8)),
        ("Beta \(b).md", Data("![](Beta%20\(b)/image.png)\n[Notes](Beta%20\(b)/Notes%20\(d).md)\n[Dup](Dup%20\(d).md)\n".utf8)),
        ("Beta \(b)/image.png", Data([2])),
        ("Beta \(b)/Notes \(d).md", Data("beta notes\n".utf8)),
        ("Dup \(c).md", Data("one\n".utf8)),
        ("Dup \(d).md", Data("two\n".utf8)),
    ])
    let vault = tempVault()
    try FileManager.default.createDirectory(at: vault.root, withIntermediateDirectories: true)
    let url = vault.root.appending(path: "export.zip")
    try zip.write(to: url)
    let report = try Importer(vault: vault, destination: "N").run(.notion, from: url)
    let resolver = LinkResolver(files: vault.allFiles())
    for (page, image, notes, dup) in [("N/Alpha.md", Data([1]), "alpha notes\n", "one\n"), ("N/Beta.md", Data([2]), "beta notes\n", "two\n")] {
        let links = NoteParser.parse(try vault.read(page)).links
        #expect(links.count == 3)
        let targets = links.compactMap { resolver.resolve($0.target, from: page) }
        #expect(targets.count == 3)
        #expect(try Data(contentsOf: vault.url(for: targets[0])) == image)
        #expect(try vault.read(targets[1]) == notes)
        #expect(try vault.read(targets[2]) == dup)
    }
    #expect(report.notes.contains("N/Dup 1.md"))
    try? FileManager.default.removeItem(at: vault.root)
}

@Test func evernoteEmbedsAcrossNotebooksStayApart() throws {
    func enex(_ byte: UInt8) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?><en-export><note><title>N\(byte)</title><content><![CDATA[<en-note><div>x</div></en-note>]]></content>
        <resource><data encoding="base64">\(Data([byte]).base64EncodedString())</data><mime>image/png</mime><resource-attributes><file-name>map.png</file-name></resource-attributes></resource>
        </note></en-export>
        """
    }
    let vault = tempVault()
    let src = vault.root.appending(path: "src")
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    try Data(enex(1).utf8).write(to: src.appending(path: "One.enex"))
    try Data(enex(2).utf8).write(to: src.appending(path: "Two.enex"))
    let report = try Importer(vault: vault, destination: "E").run(.evernote, from: src)
    let resolver = LinkResolver(files: vault.allFiles())
    for note in report.notes {
        let link = try #require(NoteParser.parse(try vault.read(note)).links.first)
        let target = try #require(resolver.resolve(link.target, from: note))
        #expect(try Data(contentsOf: vault.url(for: target)) == Data([note.hasSuffix("N1.md") ? 1 : 2]))
    }
    #expect(report.notes.count == 2)
    try? FileManager.default.removeItem(at: vault.root)
}
