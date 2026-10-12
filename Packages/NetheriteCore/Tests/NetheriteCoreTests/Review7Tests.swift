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
