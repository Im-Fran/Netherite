import Foundation
import Testing
@testable import NetheriteCore

@Test func textDiffFindsTheSmallestReplacement() {
    #expect(TextDiff.replacement(from: "same", to: "same") == nil)
    let r = TextDiff.replacement(from: "status: draft\nBody", to: "status: final\nBody")!
    #expect(r.range == NSRange(location: 8, length: 5) && r.text == "final")
    let ins = TextDiff.replacement(from: "ab", to: "aXb")!
    #expect(ins.range == NSRange(location: 1, length: 0) && ins.text == "X")
    // Changes inside an emoji replace the whole surrogate pair.
    let emoji = TextDiff.replacement(from: "a😀b", to: "a😁b")!
    #expect(emoji.range == NSRange(location: 1, length: 2) && emoji.text == "😁")
    for (old, new) in [("x😀", "x😀😀"), ("😀😀", "😀"), ("", "abc"), ("abc", "")] {
        let d = TextDiff.replacement(from: old, to: new)!
        #expect((old as NSString).replacingCharacters(in: d.range, with: d.text) == new)
    }
}

@Test func textDiffKeepsTheCaretOnTheSameText() {
    let change = NSRange(location: 2, length: 3)
    #expect(TextDiff.adjust(NSRange(location: 10, length: 1), replacing: change, newLength: 1) == NSRange(location: 8, length: 1))
    #expect(TextDiff.adjust(NSRange(location: 1, length: 1), replacing: change, newLength: 1) == NSRange(location: 1, length: 1))
    #expect(TextDiff.adjust(NSRange(location: 3, length: 0), replacing: change, newLength: 1) == NSRange(location: 3, length: 0))
}
