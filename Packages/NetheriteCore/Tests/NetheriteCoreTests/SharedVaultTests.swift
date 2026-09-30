import Foundation
import Testing
@testable import NetheriteCore

@Test func sharedVaultRoundTrip() throws {
    let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    SharedVault.publish(SharedVault(name: "V", path: dir.path(percentEncoded: false)), to: d)
    SharedVault.publishRecents(["a.md"], to: d)
    #expect(SharedVault.recents(d) == ["a.md"])
    let vault = try #require(SharedVault.current(d)?.resolve())

    let p = try vault.appendToDailyNote("one")
    try vault.appendToDailyNote("two")
    #expect(try vault.read(p) == "one\ntwo\n")
    try vault.createNote(named: "Hello World", content: "---\na: 1\n---\nBody text")
    #expect(vault.searchTitles("hello") == ["Hello World.md"])
    #expect(vault.excerpt("Hello World.md") == "Body text")
    try? FileManager.default.removeItem(at: dir)
}
