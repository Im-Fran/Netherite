import Foundation
import Testing
@testable import NetheriteCore

private let rows = [
    BaseRow(path: "Books/Thinking.md", properties: [Property(key: "author", value: .text("Kahneman")), Property(key: "rating", value: .number(4)), Property(key: "status", value: .text("read"))], tags: ["books"], links: ["Evergreen.md"]),
    BaseRow(path: "Books/Atomic.md", properties: [Property(key: "author", value: .text("Clear")), Property(key: "rating", value: .number(5)), Property(key: "status", value: .text("reading"))], tags: ["books/self"]),
    BaseRow(path: "Welcome.md", properties: [Property(key: "status", value: .text("active"))], tags: ["meta"]),
    BaseRow(path: "Attachments/ingot.png"),
]

@Test func expressions() {
    let ctx = BaseEvalContext(row: rows[0], formulas: ["double": BaseExpr.parse("rating * 2")!])
    func e(_ s: String) -> BaseValue { ctx.eval(BaseExpr.parse(s)!) }
    #expect(e("status == \"read\"") == .bool(true))
    #expect(e("note.rating >= 4 && !file.hasTag(\"meta\")") == .bool(true))
    #expect(e("file.name") == .string("Thinking"))
    #expect(e("file.folder") == .string("Books"))
    #expect(e("file.ext == \"md\"") == .bool(true))
    #expect(e("formula.double + 1") == .number(9))
    #expect(e("author.lower().startsWith(\"kah\")") == .bool(true))
    #expect(e("author.length") == .number(8))
    #expect(e("if(rating > 4, \"great\", \"ok\")") == .string("ok"))
    #expect(e("file.hasLink(\"Evergreen\")") == .bool(true))
    #expect(e("file.inFolder(\"Books\")") == .bool(true))
    #expect(e("file.hasProperty(\"author\")") == .bool(true))
    #expect(e("contains(author, \"hne\")") == .bool(true))
    #expect(e("unknownFn(1)") == .null)
    #expect(e("missing.isEmpty()") == .bool(true))
    #expect(e("now() > date(\"2020-01-01\")") == .bool(true))
    #expect(BaseExpr.parse("a ==") == nil)
}

@Test func fixtureBase() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../Fixtures/SampleVault/Library.base")
    let base = BaseFile.parse(try String(contentsOf: url, encoding: .utf8))
    #expect(base.views.first?.name == "Books")
    #expect(base.views.first?.order == ["file.name", "author", "rating", "status"])
    let result = base.run(base.views[0], rows: rows)
    #expect(result.map(\.path) == ["Books/Atomic.md", "Books/Thinking.md"])
}

@Test func viewSortLimitAndRoundTrip() {
    var base = BaseFile.parse("""
    filters:
      or:
        - file.hasTag("books")
        - status == "active"
    formulas:
      score: rating * 10
    properties:
      author:
        displayName: Writer
    summaries:
      avg: values.mean()
    views:
      - type: cards
        name: Top
        limit: 2
        order: [file.name, formula.score]
        sort:
          - property: rating
            direction: DESC
        image: cover
    """)
    #expect(base.displayName("author") == "Writer")
    #expect(base.run(base.views[0], rows: rows).map(\.path) == ["Books/Atomic.md", "Books/Thinking.md"])
    #expect(base.value(of: "formula.score", row: rows[1]) == .number(50))
    base.views[0].sort = [BaseSort(property: "file.name")]
    base.views.append(BaseViewConfig(name: "All"))
    let again = BaseFile.parse(base.yaml)
    #expect(again == base)
    #expect(again.views[0].extra["image"] != nil)
    #expect(base.yaml.contains("summaries"))
    #expect(again.run(again.views[0], rows: rows).map(\.path) == ["Books/Atomic.md", "Books/Thinking.md"])
}
