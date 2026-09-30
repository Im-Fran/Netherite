import Foundation
import Testing
@testable import NetheriteCore

@Test func canvasFixtureRoundTrip() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../Fixtures/SampleVault/Board.canvas")
    let canvas = try JSONCanvas.parse(String(contentsOf: url, encoding: .utf8))
    #expect(canvas.nodes.map(\.type) == ["text", "file", "link", "group"])
    #expect(canvas.node("a2")?.file == "Welcome.md")
    #expect(canvas.node("a3")?.color == "5")
    #expect(canvas.edges.first?.label == "see" && canvas.edges.first?.fromSide == "right")
    let group = canvas.node("g1")!
    #expect(Set(canvas.children(ofGroup: group).map(\.id)) == ["a1", "a2", "a3"])

    let out = canvas.serialized()
    #expect(out.contains("\n\t\"nodes\": [\n\t\t{\n\t\t\t\"id\": \"a1\""))
    #expect(!out.contains(" : "))
    #expect(try JSONCanvas.parse(out) == canvas)
}

@Test func canvasPreservesUnknownFields() throws {
    let src = #"{"nodes":[{"id":"x","type":"text","text":"a","x":1.5,"y":2,"width":10,"height":20,"custom":{"k":[1,true,null]}}],"edges":[],"meta":"v"}"#
    let c = try JSONCanvas.parse(src)
    #expect(c.nodes[0].extra["custom"] == .object(["k": .array([.number(1), .bool(true), .null])]))
    let again = try JSONCanvas.parse(c.serialized())
    #expect(again == c)
    #expect(again.extra["meta"] == .string("v"))
    #expect(c.serialized().contains("\"x\": 1.5") && c.serialized().contains("\"y\": 2,"))
    #expect(try JSONCanvas.parse("  ").nodes.isEmpty)
}
