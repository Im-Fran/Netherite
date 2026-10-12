import Foundation
import Testing
@testable import NetheriteCore

// R8-01: a symlinked note is dated by its target, so external edits to the target are seen.
@MainActor @Test func refreshSeesEditsThroughSymlink() async throws {
    let vault = tempVault()
    try FileManager.default.createDirectory(at: vault.root, withIntermediateDirectories: true)
    let outside = FileManager.default.temporaryDirectory.appending(path: "out-\(UUID().uuidString).md")
    try Data("v1".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(at: vault.url(for: "B.md"), withDestinationURL: outside)
    let index = VaultIndex(vault: vault)
    await index.load()
    try Data("v2".utf8).write(to: outside)
    try FileManager.default.setAttributes([.modificationDate: Date.now.addingTimeInterval(60)], ofItemAtPath: outside.path(percentEncoded: false))
    await index.refreshFromDisk()
    #expect(index.notes["B.md"]?.text == "v2")
}
