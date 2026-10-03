import Foundation

/// A template that ships with Netherite (localized), offered beside the vault's own templates.
public struct BuiltInTemplate: Identifiable, Hashable, Sendable {
    public var id: String
    /// Localized; also the file name when added to the templates folder.
    public var name: String
    public var symbol: String
    public var body: String
}

public extension Templates {
    /// Text safe to use as a note name: drops characters that break paths or links.
    static func fileName(_ s: String) -> String {
        String(s.replacingOccurrences(of: #"[\\/:*?"<>|#^\[\]]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }

    // MARK: Meeting notes

    /// Splits "Ana, Luis; Marta" (or one per line) into names.
    static func attendees(from s: String) -> [String] {
        s.split(whereSeparator: { ",;\n".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// `yyyy-MM-dd Title` (format from settings).
    static func meetingNoteName(title: String, date: Date, settings: VaultSettings) -> String {
        let t = fileName(title)
        return [format(date, settings.meetingNotes.format), t.isEmpty ? String(localized: "Meeting", bundle: .module) : t]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The template when given, else frontmatter (type, date, attendees, tags) and the standard sections.
    static func meetingNote(title: String, date: Date, attendees: [String], template: String = "") -> String {
        if !template.isEmpty { return render(template, title: title, date: date, attendees: attendees) }
        let props = [Property(key: "type", value: .text("meeting")), Property(key: "date", value: .date(date)),
                     Property(key: "attendees", value: .list(attendees)), Property(key: "tags", value: .list(["meeting"]))]
        return Frontmatter.replacing(in: "# \(title)\n\n" + meetingSections, with: props)
    }

    static var meetingSections: String {
        """
        ## \(String(localized: "Agenda", bundle: .module))

        -\u{20}

        ## \(String(localized: "Notes", bundle: .module))

        ## \(String(localized: "Decisions", bundle: .module))

        ## \(String(localized: "Action items", bundle: .module))

        - [ ]\u{20}

        """
    }

    // MARK: Gallery

    static var builtIns: [BuiltInTemplate] {
        [
            .init(id: "meeting", name: String(localized: "Meeting", bundle: .module), symbol: "person.2", body: """
            ---
            type: meeting
            date: {{date}} {{time}}
            attendees: [{{attendees}}]
            tags: [meeting]
            ---
            # {{title}}

            \(meetingSections)
            """),
            .init(id: "daily-journal", name: String(localized: "Daily journal", bundle: .module), symbol: "book.closed", body: """
            ---
            date: {{date}}
            tags: [journal]
            ---
            # {{date:dddd, D MMMM YYYY}}

            ## \(String(localized: "Grateful for", bundle: .module))

            1.\u{20}

            ## \(String(localized: "Today's focus", bundle: .module))

            - [ ]\u{20}

            ## \(String(localized: "Notes", bundle: .module))

            ## \(String(localized: "Reflection", bundle: .module))

            """),
            .init(id: "weekly-review", name: String(localized: "Weekly review", bundle: .module), symbol: "calendar.badge.checkmark", body: """
            ---
            date: {{date}}
            tags: [review]
            ---
            # {{title}}

            ## \(String(localized: "Wins", bundle: .module))

            -\u{20}

            ## \(String(localized: "Challenges", bundle: .module))

            -\u{20}

            ## \(String(localized: "Lessons learned", bundle: .module))

            -\u{20}

            ## \(String(localized: "Next week's priorities", bundle: .module))

            - [ ]\u{20}

            """),
            .init(id: "project", name: String(localized: "Project", bundle: .module), symbol: "folder.badge.gearshape", body: """
            ---
            status: \(String(localized: "Planning", bundle: .module))
            start: {{date}}
            due:
            tags: [project]
            ---
            # {{title}}

            ## \(String(localized: "Goal", bundle: .module))

            ## \(String(localized: "Milestones", bundle: .module))

            - [ ]\u{20}

            ## \(String(localized: "Tasks", bundle: .module))

            - [ ]\u{20}

            ## \(String(localized: "Resources", bundle: .module))

            ## \(String(localized: "Log", bundle: .module))

            - {{date}}:\u{20}

            """),
            .init(id: "book", name: String(localized: "Book notes", bundle: .module), symbol: "books.vertical", body: """
            ---
            author:
            status: \(String(localized: "To read", bundle: .module))
            rating:
            tags: [book]
            ---
            # {{title}}

            ## \(String(localized: "Summary", bundle: .module))

            ## \(String(localized: "Key ideas", bundle: .module))

            -\u{20}

            ## \(String(localized: "Quotes", bundle: .module))

            >\u{20}

            ## \(String(localized: "My thoughts", bundle: .module))

            """),
            .init(id: "todo", name: String(localized: "To-do list", bundle: .module), symbol: "checklist", body: """
            ---
            tags: [todo]
            ---
            # {{title}}

            - [ ]\u{20}
            - [ ]\u{20}
            - [ ]\u{20}

            """),
            .init(id: "decision", name: String(localized: "Decision record", bundle: .module), symbol: "signpost.right.and.left", body: """
            ---
            status: \(String(localized: "Proposed", bundle: .module))
            date: {{date}}
            tags: [decision]
            ---
            # {{title}}

            ## \(String(localized: "Context", bundle: .module))

            ## \(String(localized: "Options considered", bundle: .module))

            1.\u{20}

            ## \(String(localized: "Decision", bundle: .module))

            ## \(String(localized: "Consequences", bundle: .module))

            """),
        ]
    }
}
