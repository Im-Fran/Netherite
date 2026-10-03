import Foundation
import Testing
@testable import NetheriteCore

@Test func vaultTrashKeepsFilesAndHidesThem() throws {
    let vault = Vault(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    try vault.write("one", to: "A.md")
    try vault.write("two", to: "sub/A.md")
    #expect(try vault.moveToVaultTrash("A.md") == ".trash/A.md")
    #expect(try vault.moveToVaultTrash("sub/A.md") == ".trash/A 1.md")
    try vault.write("x", to: "folder/x.md")
    #expect(try vault.moveToVaultTrash("folder") == ".trash/folder")
    #expect(try vault.read(".trash/A 1.md") == "two")
    #expect(try vault.read(".trash/folder/x.md") == "x")
    #expect(!vault.allFiles().contains { $0.hasPrefix(".trash") })
}

@MainActor @Test func refreshKeepsEditsMadeDuringScan() async throws {
    let vault = Vault(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    try vault.write("v1", to: "A.md")
    let index = VaultIndex(vault: vault)
    await index.load()
    // An older save lands on disk (watcher fires), then the user types while the scan runs.
    try vault.write("disk", to: "A.md")
    try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: vault.url(for: "A.md").path(percentEncoded: false))
    let refresh = Task { await index.refreshFromDisk() }
    await Task.yield()
    index.update("A.md", text: "typed")
    await refresh.value
    #expect(index.notes["A.md"]?.text == "typed")
}

@MainActor @Test func refreshIgnoresOwnSaves() async throws {
    let vault = Vault(root: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    try vault.write("v1", to: "A.md")
    let index = VaultIndex(vault: vault)
    await index.load()
    index.update("A.md", text: "v2")
    try vault.write("v2", to: "A.md")
    let revision = index.revision
    await index.refreshFromDisk()
    #expect(index.revision == revision)
    #expect(index.notes["A.md"]?.text == "v2")
}
