import Foundation
import Testing
@testable import NetheriteCore

@Test func sharedVaultRoundTrip() throws {
    let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    SharedVault.publish(SharedVault(name: "V", path: dir.path(percentEncoded: false)), to: d)
    SharedVault.publishRecents(["a.md"], vault: dir.path(percentEncoded: false), to: d)
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

@Test func deepLinkEscapesSpecialCharacters() {
    let path = "Q&A/C++ notes #1.md"
    let url = SharedVault.openURL(path: path)
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    #expect(url.host() == "open")
    #expect(items?.first { $0.name == "path" }?.value == path)
}

@Test func recentsBelongToTheSharedVault() {
    let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    SharedVault.publish(SharedVault(name: "A", path: "/a"), to: d)
    SharedVault.publishRecents(["a.md"], vault: "/a", to: d)
    SharedVault.publishRecents(["b.md"], vault: "/b", to: d)   // another open vault: ignored
    #expect(SharedVault.recents(d) == ["a.md"])
    SharedVault.publish(SharedVault(name: "B", path: "/b"), to: d)
    #expect(SharedVault.recents(d).isEmpty)
}

@Test func withdrawingTheSharedVault() {
    let d = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
    SharedVault.publish(SharedVault(name: "A", path: "/a"), to: d)
    SharedVault.withdraw("/other", replacingWith: nil, in: d)
    #expect(SharedVault.current(d)?.path == "/a")
    SharedVault.withdraw("/a", replacingWith: SharedVault(name: "B", path: "/b"), in: d)
    #expect(SharedVault.current(d)?.path == "/b")
    SharedVault.withdraw("/b", replacingWith: nil, in: d)
    #expect(SharedVault.current(d) == nil)
}

@Test func deepLinksCarryTheVault() {
    let items = { (url: URL) in Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) }) }
    let open = SharedVault.openURL(path: "a.md", vault: "/V a&b")
    #expect(items(open)["vault"] == "/V a&b")
    #expect(items(open)["path"] == "a.md")
    let daily = SharedVault.dailyURL(vault: "/V")
    #expect(daily.host() == "daily" && items(daily)["vault"] == "/V")
    #expect(SharedVault.dailyURL(vault: nil).absoluteString == "netherite://daily")
}
