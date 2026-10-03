import Foundation
import Testing
@testable import NetheriteCore

private func tempDir() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory) }

@Test func syncStatusCombinesFiles() {
    #expect(SyncStatus.combine([.init(isUbiquitous: false)], folderIsUbiquitous: false) == .local)
    #expect(SyncStatus.combine([], folderIsUbiquitous: true) == .synced)
    #expect(SyncStatus.combine([.init(isUbiquitous: true), .init(isUbiquitous: true, isUploaded: false)], folderIsUbiquitous: true) == .pending)
    #expect(SyncStatus.combine([.init(isUbiquitous: true, isUploaded: false), .init(isUbiquitous: true, isDownloading: true)],
                               folderIsUbiquitous: true) == .syncing)
    #expect(SyncStatus.combine([.init(isUbiquitous: true, isUploaded: false, isUploading: true)], folderIsUbiquitous: true) == .syncing)
}

@Test func storageScanCountsFiles() throws {
    let vault = Vault(root: tempDir())
    try vault.write("hello", to: "A.md")
    try vault.write("x", to: "sub/B.md")
    try vault.write(Data([1, 2, 3]), to: "img.png")
    try vault.write("{}", to: ".netherite/app.json")
    let s = VaultStorage.scan(vault.root)
    #expect(s.files == 3)
    #expect(s.notes == 2)
    #expect(s.bytes > 0)
    #expect(s.status == .local)
}

@Test func vaultTrashRestoreAndPurge() throws {
    let parent = tempDir()
    let vault = Vault(root: parent.appending(path: "Notes"))
    try vault.write("keep", to: "A.md")
    let old = Date(timeIntervalSince1970: 1_000_000)
    let trashed = try VaultTrash.trash(vault.root, now: old)
    #expect(!FileManager.default.fileExists(atPath: vault.root.path(percentEncoded: false)))
    var items = VaultTrash.items(in: [parent])
    #expect(items.map(\.name) == ["Notes"])
    #expect(items[0].url.standardizedFileURL == trashed.standardizedFileURL)

    // A new vault took the name meanwhile: restoring renames instead of overwriting.
    try Vault(root: parent.appending(path: "Notes")).write("new", to: "B.md")
    let restored = try VaultTrash.restore(items[0])
    #expect(restored.lastPathComponent == "Notes 1")
    #expect(try Vault(root: restored).read("A.md") == "keep")

    try VaultTrash.trash(restored, now: old)
    try VaultTrash.trash(parent.appending(path: "Notes"), now: .now)
    VaultTrash.purge(in: [parent])
    items = VaultTrash.items(in: [parent])
    #expect(items.count == 1)
    #expect(items[0].name == "Notes")
}

@Test func exportZipsFoldersAndCopiesFiles() throws {
    let vault = Vault(root: tempDir())
    try vault.write("# A", to: "Folder/A.md")
    try vault.write("# B", to: "B.md")
    let out = tempDir()
    let note = try vault.exportArchive("B.md", to: out)
    #expect(note.lastPathComponent == "B.md")
    #expect(try String(contentsOf: note, encoding: .utf8) == "# B")
    let zip = try vault.exportArchive("", to: out)
    #expect(zip.lastPathComponent == "\(vault.name).zip")
    let entries = try ZipReader(data: Data(contentsOf: zip)).entries.map(\.path)
    #expect(entries.contains { $0.hasSuffix("Folder/A.md") })
    #expect(entries.contains { $0.hasSuffix("B.md") })
}

@Test func importItemsCopiesWithoutOverwriting() throws {
    let vault = Vault(root: tempDir())
    try vault.write("old", to: "In/Note.md")
    let src = tempDir()
    try FileManager.default.createDirectory(at: src.appending(path: "Dir"), withIntermediateDirectories: true)
    try Data("new".utf8).write(to: src.appending(path: "Note.md"))
    try Data("d".utf8).write(to: src.appending(path: "Dir/x.md"))
    let paths = try vault.importItems([src.appending(path: "Note.md"), src.appending(path: "Dir")], into: "In")
    #expect(paths == ["In/Note 1.md", "In/Dir"])
    #expect(try vault.read("In/Note.md") == "old")
    #expect(try vault.read("In/Dir/x.md") == "d")
}
