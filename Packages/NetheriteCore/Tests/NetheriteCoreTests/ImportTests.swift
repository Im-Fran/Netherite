import Foundation
import Testing
import Compression
import CryptoKit
@testable import NetheriteCore

/// Builds a ZIP in memory (first entry stored, the rest deflated) to exercise ZipReader.
func makeZip(_ files: [(String, Data)]) -> Data {
    var out = Data(), central = Data()
    func le16(_ v: Int) -> Data { Data([UInt8(v & 0xff), UInt8(v >> 8 & 0xff)]) }
    func le32(_ v: Int) -> Data { le16(v & 0xffff) + le16(v >> 16 & 0xffff) }
    for (i, (name, data)) in files.enumerated() {
        var payload = data, method = 0
        if i > 0 {
            var buf = [UInt8](repeating: 0, count: data.count + 64)
            let n = data.withUnsafeBytes { compression_encode_buffer(&buf, buf.count, $0.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB) }
            payload = Data(buf.prefix(n)); method = 8
        }
        let nameData = Data(name.utf8), offset = out.count
        let local: [Data] = [le32(0x04034b50), le16(20), le16(0x800), le16(method), le32(0), le32(0),
                             le32(payload.count), le32(data.count), le16(nameData.count), le16(0), nameData, payload]
        local.forEach { out.append($0) }
        let entry: [Data] = [le32(0x02014b50), le16(20), le16(20), le16(0x800), le16(method), le32(0), le32(0),
                             le32(payload.count), le32(data.count), le16(nameData.count), le16(0), le16(0), le16(0), le16(0),
                             le32(0), le32(offset), nameData]
        entry.forEach { central.append($0) }
    }
    let cdOffset = out.count
    out.append(central)
    let end: [Data] = [le32(0x06054b50), le16(0), le16(0), le16(files.count), le16(files.count), le32(central.count), le32(cdOffset), le16(0)]
    end.forEach { out.append($0) }
    return out
}

func tempVault() -> Vault { Vault(root: FileManager.default.temporaryDirectory.appending(path: "imp-\(UUID().uuidString)")) }

@Test func zipReaderStoredAndDeflate() throws {
    let text = String(repeating: "Hello deflate! ", count: 50)
    let zip = try ZipReader(data: makeZip([("a.txt", Data("stored".utf8)), ("dir/b.md", Data(text.utf8)), ("__MACOSX/x", Data())]))
    let files = try zip.files()
    #expect(files.map(\.path) == ["a.txt", "dir/b.md"])
    #expect(String(decoding: files[0].data, as: UTF8.self) == "stored")
    #expect(String(decoding: files[1].data, as: UTF8.self) == text)
    #expect(throws: (any Error).self) { try ZipReader(data: Data("nope".utf8)) }
}

@Test func htmlToMarkdown() {
    let html = """
    <html><head><title>T</title><style>p{}</style></head><body>
    <h2>Title &amp; more</h2><p>Some <b>bold</b>, <i>it</i>, <a href="https://x.com">link</a> and <code>x&lt;y</code>.</p>
    <ul><li>One<ul><li>Nested</li></ul></li><li><input type="checkbox" checked>Done</li></ul>
    <ol start="3"><li>Three</li></ol>
    <blockquote><p>Quote</p></blockquote>
    <table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2|3</td></tr></table>
    <pre><code class="language-swift">let a = 1 &lt; 2</code></pre><hr><img src="pic.png" alt="Pic">
    </body></html>
    """
    let md = HTMLToMarkdown().convert(html)
    #expect(md.contains("## Title & more"))
    #expect(md.contains("Some **bold**, *it*, [link](https://x.com) and `x<y`."))
    #expect(md.contains("- One\n\t- Nested"))
    #expect(md.contains("- [x] Done"))
    #expect(md.contains("3. Three"))
    #expect(md.contains("> Quote"))
    #expect(md.contains("| A | B |\n| --- | --- |\n| 1 | 2\\|3 |"))
    #expect(md.contains("```swift\nlet a = 1 < 2\n```"))
    #expect(md.contains("---") && md.contains("![Pic](pic.png)"))
    #expect(!md.contains("p{}"))
    #expect(HTMLToMarkdown.title(of: html) == "T")
}

@Test func evernoteImport() throws {
    let png = Data([0x89, 0x50, 0x4e, 0x47, 1, 2, 3])
    let hash = Insecure.MD5.hash(data: png).map { String(format: "%02x", $0) }.joined()
    let enex = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE en-export SYSTEM "http://xml.evernote.com/pub/evernote-export4.dtd">
    <en-export><note><title>Trip / Plan</title>
    <content><![CDATA[<?xml version="1.0"?><en-note><div><en-todo checked="true"/>Book flight</div><div><en-todo/>Pack</div>
    <table><tr><td>Day</td><td>City</td></tr><tr><td>1</td><td>Tokyo</td></tr></table><div><en-media hash="\(hash)" type="image/png"/></div></en-note>]]></content>
    <created>20240301T101500Z</created><updated>20240302T080000Z</updated><tag>travel</tag><tag>big trip</tag>
    <note-attributes><source-url>https://example.com</source-url></note-attributes>
    <resource><data encoding="base64">\(png.base64EncodedString())</data><mime>image/png</mime><resource-attributes><file-name>map.png</file-name></resource-attributes></resource>
    </note></en-export>
    """
    let vault = tempVault()
    let file = vault.root.appending(path: "src/Notebook.enex")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(enex.utf8).write(to: file)
    let report = try Importer(vault: vault, destination: "Imported/Notebook").run(.evernote, from: file)
    #expect(report.notes == ["Imported/Notebook/Trip Plan.md"])
    #expect(report.attachments == ["Imported/Notebook/Attachments/map.png"])
    let text = try vault.read(report.notes[0])
    #expect(text.contains("- [x] Book flight") && text.contains("- [ ] Pack"))
    #expect(text.contains("| Day | City |") && text.contains("![[map.png]]"))
    let p = NoteParser.parse(text)
    #expect(p.property("tags") == .list(["travel", "big-trip"]))
    #expect(p.property("source") == .text("https://example.com"))
    if case .date = p.property("created") {} else { Issue.record("created missing") }
    try? FileManager.default.removeItem(at: vault.root)
}

@Test func notionImportFromZip() throws {
    let id = "0123456789abcdef0123456789abcdef", id2 = "fedcba9876543210fedcba9876543210"
    let zip = makeZip([
        ("Home \(id).md", Data("# Home\nSee [Child](Home%20\(id)/Child%20\(id2).md) and ![img](Home%20\(id)/pic.png)\n".utf8)),
        ("Home \(id)/Child \(id2).md", Data("# Child\n[Back](../Home%20\(id).md)\n".utf8)),
        ("Home \(id)/pic.png", Data([1, 2, 3])),
        ("Home \(id)/Tasks \(id2).csv", Data("Name,Status\n\"Buy, milk\",Done\nWalk,\"To \"\"do\"\"\"\n".utf8)),
        ("Home \(id)/Tasks \(id2)_all.csv", Data("x\n".utf8)),
    ])
    let vault = tempVault()
    let url = vault.root.appending(path: "export.zip")
    try FileManager.default.createDirectory(at: vault.root, withIntermediateDirectories: true)
    try zip.write(to: url)
    let report = try Importer(vault: vault, destination: "Notion").run(.notion, from: url)
    #expect(Set(report.notes) == ["Notion/Home.md", "Notion/Home/Child.md", "Notion/Home/Tasks.md"])
    #expect(try vault.read("Notion/Home.md").contains("See [[Child]] and ![[pic.png]]"))
    #expect(try vault.read("Notion/Home/Child.md").contains("[[Home|Back]]"))
    #expect(try vault.read("Notion/Home/Tasks.md").contains("| Buy, milk | Done |\n| Walk | To \"do\" |"))
    #expect(Importer.stripNotionIDs("A \(id)/B \(id2).md") == "A/B.md")
    try? FileManager.default.removeItem(at: vault.root)
}

@Test func htmlFolderImport() throws {
    let vault = tempVault()
    let src = vault.root.appending(path: "src")
    try FileManager.default.createDirectory(at: src.appending(path: "imgs"), withIntermediateDirectories: true)
    try Data("<html><head><title>Apple Note</title></head><body><div>Line <mark>one</mark></div><div><img src=\"imgs/a%20b.png\"></div></body></html>".utf8)
        .write(to: src.appending(path: "Note.html"))
    try Data([9, 9]).write(to: src.appending(path: "imgs/a b.png"))
    let report = try Importer(vault: vault, destination: "Apple").run(.html, from: src)
    #expect(report.notes == ["Apple/Apple Note.md"])
    #expect(report.attachments == ["Apple/Attachments/a b.png"])
    let text = try vault.read("Apple/Apple Note.md")
    #expect(text.contains("Line ==one==") && text.contains("![[a b.png]]"))
    try? FileManager.default.removeItem(at: vault.root)
}

@Test func formatConverter() {
    let files = ["Notes/Other Note.md", "202401011200 Zettel.md"]
    var o = FormatConverter.Options()
    o.zettelkastenLinks = true
    let c = FormatConverter(options: o, files: files)
    let src = """
    ---
    alias: Old, Name
    tag: a
    tags: [b]
    ---
    #multi word tag# and #single# plus ::hl:: and ^^roam^^ and #[[Roam Tag]]
    - {{[[TODO]]}} task
    - {{[[DONE]]}} done
    [Other](Notes/Other%20Note.md) [ext](https://x.com) <mark>m</mark> [[202401011200]]
    `#not a tag# ::code::`
    # Heading #
    """
    let out = c.convert(src, path: "A.md")
    #expect(out.contains("#multi-word-tag and #single plus ==hl== and ==roam== and [[Roam Tag]]"))
    #expect(out.contains("- [ ] task") && out.contains("- [x] done"))
    #expect(out.contains("[[Other Note|Other]] [ext](https://x.com) ==m== [[202401011200 Zettel|Zettel]]"))
    #expect(out.contains("`#not a tag# ::code::`"))
    #expect(out.contains("# Heading #"))
    let p = NoteParser.parse(out)
    #expect(p.property("aliases") == .list(["Old", "Name"]))
    #expect(p.property("tags") == .list(["b", "a"]))
    #expect(p.property("alias") == nil)
}

@Test func csvToTable() {
    #expect(Importer.csvToTable("a,b\n1,\"x\ny\"\n") == "| a | b |\n| --- | --- |\n| 1 | x<br>y |")
}
