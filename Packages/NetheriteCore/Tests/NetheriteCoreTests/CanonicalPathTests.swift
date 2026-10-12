import Foundation
import Testing
@testable import NetheriteCore

@Test func canonicalPathUsesTheSpellingOnDisk() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "canon-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let vault = Vault(root: root)
    try vault.write("x", to: "Folder/Inbox.md")
    #expect(vault.canonicalPath("Folder/Inbox.md") == "Folder/Inbox.md")
    #expect(vault.canonicalPath("/folder/inbox.md") == "Folder/Inbox.md")
    #expect(vault.canonicalPath("Folder/./Inbox.md") == "Folder/Inbox.md")
    #expect(vault.canonicalPath("Folder/Missing.md") == nil)
    #expect(vault.canonicalPath("") == nil)
    #expect(vault.existsExactly("Folder/Inbox.md"))
    #expect(!vault.existsExactly("Folder/inbox.md"))
    #expect(!vault.existsExactly("/Folder/Inbox.md"))
}
