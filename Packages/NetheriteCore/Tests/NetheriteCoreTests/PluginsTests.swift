import Foundation
import Testing
@testable import NetheriteCore

@Test func pluginSettingsDecodeLeniently() throws {
    let json = #"{"disabledPlugins": ["canvas", "some-future-plugin"], "meetingNotes": {"folder": "Work/Meetings"}}"#
    var s = try JSONDecoder().decode(VaultSettings.self, from: Data(json.utf8))
    #expect(!s.isEnabled(.canvas))
    #expect(s.isEnabled(.graph))
    #expect(s.meetingNotes.folder == "Work/Meetings")
    #expect(s.meetingNotes.format == "yyyy-MM-dd")
    s.setEnabled(.canvas, true)
    s.setEnabled(.slides, false)
    let again = try JSONDecoder().decode(VaultSettings.self, from: JSONEncoder().encode(s))
    #expect(again.disabledPlugins == ["slides", "some-future-plugin"])
    #expect(try JSONDecoder().decode(VaultSettings.self, from: Data("{}".utf8)).disabledPlugins.isEmpty)
}

@Test func meetingNotes() {
    let date = Frontmatter.parseDate("2026-03-04 09:30")!
    var s = VaultSettings()
    #expect(Templates.meetingNoteName(title: "Kickoff: Q2/plan", date: date, settings: s) == "2026-03-04 Kickoff Q2plan")
    s.meetingNotes.format = ""
    #expect(Templates.meetingNoteName(title: "", date: date, settings: s) == "Meeting")
    #expect(Templates.attendees(from: "Ana, Luis;  Marta\n") == ["Ana", "Luis", "Marta"])

    let note = Templates.meetingNote(title: "Kickoff", date: date, attendees: ["Ana", "Luis"])
    let props = NoteParser.parse(note).properties
    #expect(props.first { $0.key == "type" }?.value == .text("meeting"))
    #expect(props.first { $0.key == "attendees" }?.value == .list(["Ana", "Luis"]))
    #expect(props.first { $0.key == "tags" }?.value == .list(["meeting"]))
    #expect(props.first { $0.key == "date" }?.value == .date(date))
    #expect(note.contains("# Kickoff\n") && note.contains("## Action items\n\n- [ ] "))

    let custom = Templates.meetingNote(title: "Sync", date: date, attendees: ["Ana", "Luis"], template: "{{title}} with {{attendees}} at {{time}}")
    #expect(custom == "Sync with Ana, Luis at 09:30")
}

@Test func builtInTemplates() {
    let all = Templates.builtIns
    #expect(all.count == 7 && Set(all.map(\.id)).count == all.count)
    for t in all {
        let out = Templates.render(t.body, title: "X", attendees: ["Ana"])
        #expect(!out.contains("{{"), "\(t.id) left a placeholder")
        #expect(Frontmatter.locate(in: out) != nil, "\(t.id) has no frontmatter")
    }
    let meeting = NoteParser.parse(Templates.render(all[0].body, title: "X", attendees: ["Ana", "Luis"])).properties
    #expect(meeting.first { $0.key == "attendees" }?.value == .list(["Ana", "Luis"]))
}

@Test func databaseBase() {
    let db = BaseFile.database(folder: "Projects/Q2", boardColumns: ["To Do", "Done"])
    #expect(db.entryFolder == "Projects/Q2")
    let again = BaseFile.parse(db.yaml)
    #expect(again == db)
    #expect(again.views.map(\.kind) == [.table, .board])
    #expect(again.views[1].columns == ["To Do", "Done"])
    #expect(again.views[1].boardProperty == "status")
    #expect(again.views[0].order == ["file.name", "status", "tags", "date"])

    let rows = [
        BaseRow(path: "Projects/Q2/A.md", properties: [Property(key: "status", value: .text("Done"))]),
        BaseRow(path: "Projects/Q2/B.md", properties: [Property(key: "status", value: .text("Blocked"))]),
        BaseRow(path: "Projects/Q2/C.md"),
        BaseRow(path: "Projects/Q2/Q2.base"),
        BaseRow(path: "Other/D.md", properties: [Property(key: "status", value: .text("Done"))]),
    ]
    let matching = again.run(again.views[1], rows: rows)
    #expect(Set(matching.map(\.path)) == ["Projects/Q2/A.md", "Projects/Q2/B.md", "Projects/Q2/C.md"])
    let cols = again.board(again.views[1], rows: matching, property: "status")
    #expect(cols.map(\.value) == [nil, "To Do", "Done", "Blocked"])
    #expect(cols.map { $0.rows.map(\.path) } == [["Projects/Q2/C.md"], [], ["Projects/Q2/A.md"], ["Projects/Q2/B.md"]])

    #expect(BaseFile.parse("filters:\n  or:\n    - file.inFolder(\"X\")\nviews: []").entryFolder == nil)
    #expect(BaseFile.parse("filters: file.inFolder(\"/X/\")\nviews: []").entryFolder == "X")
    #expect(PropertyValue.empty(.checkbox) == .bool(false) && PropertyValue.empty(.list) == .list([]) && PropertyValue.empty(.text) == .null)
}

@Test func unknownViewTypeRoundTrips() {
    let base = BaseFile.parse("views:\n  - type: calendar\n    name: Cal\n    dateProperty: due\n")
    #expect(base.views[0].kind == .table)
    let yaml = BaseFile.parse(base.yaml).yaml
    #expect(yaml.contains("type: calendar") && yaml.contains("dateProperty: due"))
}
