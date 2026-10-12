import Foundation
import Testing
@testable import NetheriteCore

// R7-01: a note that is a symlink to a file saves through the link.
@Test func writeThroughFileSymlink() throws {
    let vault = tempVault()
    try FileManager.default.createDirectory(at: vault.root, withIntermediateDirectories: true)
    let outside = FileManager.default.temporaryDirectory.appending(path: "out-\(UUID().uuidString).md")
    try Data("real".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(at: vault.url(for: "L.md"), withDestinationURL: outside)
    try vault.write("saved", to: "L.md")
    #expect(try String(contentsOf: outside, encoding: .utf8) == "saved")
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: vault.url(for: "L.md").path(percentEncoded: false)) == outside.path(percentEncoded: false))
}

// R7-02: a move doesn't recreate a linking note that was deleted outside the app; it drops it from the index.
@MainActor @Test func moveSkipsNotesDeletedElsewhere() async throws {
    let vault = tempVault()
    try vault.write("target", to: "A.md")
    try vault.write("links [[A]]", to: "B.md")
    let index = VaultIndex(vault: vault)
    await index.load()
    try FileManager.default.removeItem(at: vault.url(for: "B.md"))
    #expect(try index.move("A.md", to: "C.md").isEmpty)
    #expect(!vault.exists("B.md"))
    #expect(!index.files.contains("B.md"))
}
