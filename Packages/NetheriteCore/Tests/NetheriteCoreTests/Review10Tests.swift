import Foundation
import Testing
@testable import NetheriteCore

// R10-01: a number, date or checkbox in the target joins a source list instead of being replaced by it.
@Test func mergeKeepsNonTextScalarsWhenJoiningLists() throws {
    let x = { (target: String) in NoteParser.parse(try Frontmatter.merging("---\nx: [a]\n---\nS", into: "---\nx: \(target)\n---\nT")).property("x") }
    #expect(try x("5") == .list(["5", "a"]))
    #expect(try x("2024-01-02") == .list(["2024-01-02", "a"]))
    #expect(try x("true") == .list(["true", "a"]))
}
