import AppIntents

struct NetheriteShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: CreateNoteIntent(), phrases: [
            "Create a note in \(.applicationName)",
        ], shortTitle: "Create Note", systemImageName: "square.and.pencil")
        AppShortcut(intent: AppendToDailyNoteIntent(), phrases: [
            "Add to my daily note in \(.applicationName)",
        ], shortTitle: "Append to Daily Note", systemImageName: "text.append")
        AppShortcut(intent: OpenDailyNoteIntent(), phrases: [
            "Open today's note in \(.applicationName)",
        ], shortTitle: "Open Daily Note", systemImageName: "calendar")
        AppShortcut(intent: OpenNoteIntent(), phrases: [
            "Open \(\.$note) in \(.applicationName)",
        ], shortTitle: "Open Note", systemImageName: "doc.text")
        AppShortcut(intent: SearchNotesIntent(), phrases: [
            "Search notes in \(.applicationName)",
        ], shortTitle: "Search Notes", systemImageName: "magnifyingglass")
    }
}
