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
    #expect(SyncStatus.File(isUbiquitous: true, isUploaded: false).transfer == .waiting)
    #expect(SyncStatus.File(isUbiquitous: true, isDownloading: true).transfer == .download)
    #expect(SyncStatus.File(isUbiquitous: true).transfer == nil)
    #expect(SyncStatus.File(isUbiquitous: false, isUploaded: false).transfer == nil)
}

@Test func syncProgressEstimatesTimeLeft() {
    let t0 = Date(timeIntervalSince1970: 0)
    var p = SyncProgress()
    p.record(pending: 1000, at: t0)
    #expect(p.fraction == 0 && p.timeRemaining == nil)
    p.record(pending: 600, at: t0.addingTimeInterval(2))          // 200 B/s
    #expect(p.fraction == 0.4)
    #expect(p.timeRemaining == 3)
    p.record(pending: 900, at: t0.addingTimeInterval(3))          // a new 300 B file joins the run
    #expect(p.total == 1300)
    p.record(pending: 0, at: t0.addingTimeInterval(4))            // done: next run starts fresh
    #expect(p == SyncProgress())
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

@Test func vaultIDFollowsTheFolder() throws {
    let root = tempDir()
    let id = Vault(root: root).stableID
    #expect(Vault(root: root).stableID == id)
    let moved = tempDir()
    try FileManager.default.moveItem(at: root, to: moved)
    #expect(Vault(root: moved).stableID == id)
    #expect(Vault(root: tempDir()).stableID != id)
    // A planted ID can't steer snapshots out of their folder.
    let shared = Vault(root: tempDir())
    shared.saveConfig("id.json", "../../escape")
    #expect(UUID(uuidString: shared.stableID) != nil)
}

// R2-17: a copy gets its own ID, a read-only vault and an undownloaded `id.json` get one that doesn't change.
@Test func vaultIDForCopiesAndUnwritableVaults() throws {
    let ledger = tempDir()
    let a = Vault(root: tempDir())
    let id = a.stableID(ledger: ledger)
    let copy = tempDir()
    try FileManager.default.copyItem(at: a.root, to: copy)
    #expect(Vault(root: copy).stableID(ledger: ledger) != id)
    #expect(a.stableID(ledger: ledger) == id)
    let moved = tempDir()
    try FileManager.default.moveItem(at: a.root, to: moved)
    #expect(Vault(root: moved).stableID(ledger: ledger) == id)

    let readOnly = Vault(root: tempDir())
    try FileManager.default.createDirectory(at: readOnly.root, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.root.path(percentEncoded: false))
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.root.path(percentEncoded: false)) }
    #expect(readOnly.stableID == readOnly.stableID && UUID(uuidString: readOnly.stableID) != nil)

    let cloud = Vault(root: tempDir())
    try FileManager.default.createDirectory(at: cloud.configURL, withIntermediateDirectories: true)
    try Data().write(to: cloud.configURL.appending(path: ".id.json.icloud"))
    #expect(cloud.stableID == cloud.stableID)
    #expect(!FileManager.default.fileExists(atPath: cloud.configURL.appending(path: "id.json").path(percentEncoded: false)))
}

// R2-21: saving an unchanged config doesn't touch the file (no iCloud sync for nothing).
@Test func saveConfigSkipsUnchangedFiles() throws {
    let vault = Vault(root: tempDir())
    #expect(vault.saveConfig("recent.json", ["a.md"]))
    let url = vault.configURL.appending(path: "recent.json")
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: url.path(percentEncoded: false))
    #expect(vault.saveConfig("recent.json", ["a.md"]))
    #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == Date(timeIntervalSince1970: 1000))
    #expect(vault.saveConfig("recent.json", ["b.md"]) && vault.loadConfig("recent.json", fallback: [String]()) == ["b.md"])
}

@Test func vaultFolderNameIsOneFolder() {
    #expect(Vault.folderName(for: "  My Notes ") == "My Notes")
    #expect(Vault.folderName(for: "a/b") == "a-b")
    #expect(Vault.folderName(for: "..") == nil)
    #expect(Vault.folderName(for: "../x") == "-x")
    #expect(Vault.folderName(for: ".hidden") == "hidden")
    #expect(Vault.folderName(for: "  ") == nil)
    // R2-18: dots and spaces mixed at the start go too.
    for name in [". .", ". ..", " . . ", ". .. "] { #expect(Vault.folderName(for: name) == nil, "\(name)") }
    #expect(Vault.folderName(for: " . .x") == "x")
}
