import Foundation
import Testing
@testable import NetheriteCore

private func renderPlain(_ md: String) -> String {
    HTMLRenderer.render(md, context: RenderContext(
        source: "A.md", resolve: { _, _ in nil }, readNote: { _ in nil },
        linkHref: { _, t, _ in "new:\(t)" }, assetURL: { "asset:\($0)" }, tagHref: { "tag:\($0)" }))
}

// MARK: N-04 · paths stay inside the vault

@Test func vaultPathsAreConfined() throws {
    let vault = tempVault()
    let root = vault.root.path(percentEncoded: false)
    for p in ["../../escaped/pwn.md", "/etc/passwd", "a/../../../b.md", "./x/./../..", "..%2F.."] {
        #expect(vault.url(for: p).standardizedFileURL.path(percentEncoded: false).hasPrefix(root), "\(p)")
    }
    #expect(vault.url(for: "a/../b.md") == vault.url(for: "b.md"))
    #expect(Vault.normalize("a//./b/../c.md") == "a/c.md")
    // Deep links / intents end up in createNote with untrusted folder and name.
    let path = try vault.createNote(in: "../..", named: "../x")
    #expect(path == "x.md" && vault.exists("x.md"))
    try? FileManager.default.removeItem(at: vault.root)
}

@Test func zipImportCannotEscape() throws {
    let vault = tempVault()
    let zip = vault.root.appending(path: "evil.zip")
    try FileManager.default.createDirectory(at: vault.root, withIntermediateDirectories: true)
    try makeZip([("../../escaped/pwn.md", Data("x".utf8)), ("../../LaunchAgents/a.plist", Data("p".utf8))]).write(to: zip)
    let report = try Importer(vault: vault, destination: "In").run(.markdown, from: zip)
    #expect(report.notes == ["In/escaped/pwn.md"])
    #expect(report.attachments == ["In/LaunchAgents/a.plist"])
    #expect(vault.exists("In/escaped/pwn.md"))
    #expect(!FileManager.default.fileExists(atPath: vault.root.deletingLastPathComponent().appending(path: "escaped").path(percentEncoded: false)))
    try? FileManager.default.removeItem(at: vault.root)
}

// MARK: N-38 · hostile ZIPs fail instead of crashing

@Test func zipRejectsBogusSizes() throws {
    #expect(throws: ZipReader.ZipError.self) { try ZipReader.inflate(Data(), expected: 10) }
    #expect(throws: ZipReader.ZipError.self) { try ZipReader.inflate(Data([1, 2]), expected: 1 << 40) }
    let zip = try ZipReader(data: makeZip([("a.txt", Data("a".utf8)), ("b.txt", Data(repeating: 65, count: 5000))]))
    #expect(throws: ZipReader.ZipError.self) { try zip.files(maxTotalSize: 1000) }
    #expect(try zip.files().count == 2)
}

// MARK: N-20 / N-21 / N-40 · renderer robustness

@Test func embedSectionWithOtherLineBreaks() {
    let text = "intro\rmore\u{2028}x\n# Head\nbody ^blk\n# Next"
    #expect(HTMLRenderer.section(of: text, subpath: "Head").contains("body"))
    #expect(HTMLRenderer.section(of: text, subpath: "^blk").contains("body"))
}

@Test func forgedPlaceholderMarkers() {
    let html = renderPlain("a \u{E000}7\u{E001} [[x]] \u{E000}0\u{E001}")
    #expect(!html.contains("\u{E000}") && html.contains("new:x"))
    #expect(HTMLRenderer.restoreTokens("\u{E000}9\u{E001}", ["a"]) == "\u{E000}9\u{E001}")
}

@Test func renderIsLinearInLinks() {
    let md = (0..<8000).map { "[[Note \($0)]]" }.joined(separator: " ")
    let start = Date()
    let html = renderPlain(md)
    #expect(html.contains("new:Note 7999"))
    #expect(Date().timeIntervalSince(start) < 2)
}
