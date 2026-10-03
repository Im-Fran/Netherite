import AppIntents
import Foundation
import NetheriteCore

// Compiled into both the app and the widget extension (interactive widget buttons run these intents).

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noVault
    var localizedStringResource: LocalizedStringResource {
        "Open a vault in Netherite first."
    }
}

/// Runs `body` on the shared vault off the main actor, holding folder access only while it runs.
nonisolated private func withSharedVault<T: Sendable>(_ body: @escaping @Sendable (Vault) throws -> T) async throws -> T {
    try await Task.detached {
        guard let result = try SharedVault.current()?.withVault(body) else { throw IntentError.noVault }
        return result
    }.value
}

nonisolated private func openURL(_ s: String) -> URL { URL(string: s)! }

struct NoteEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Note"
    static let defaultQuery = NoteQuery()
    var id: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id.noteName)", subtitle: id.parentFolder.isEmpty ? nil : "\(id.parentFolder)")
    }
}

struct NoteQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [NoteEntity] { identifiers.map(NoteEntity.init) }
    func entities(matching string: String) async throws -> [NoteEntity] {
        try await withSharedVault { $0.searchTitles(string) }.map(NoteEntity.init)
    }
    func suggestedEntities() async throws -> [NoteEntity] {
        let recents = SharedVault.recents()
        if !recents.isEmpty { return recents.map(NoteEntity.init) }
        return try await withSharedVault { $0.searchTitles("", limit: 20) }.map(NoteEntity.init)
    }
}

struct CreateNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Note"
    static let description = IntentDescription("Creates a note in your Netherite vault.")

    @Parameter(title: "Title") var noteTitle: String
    @Parameter(title: "Content", default: "") var content: String
    @Parameter(title: "Folder", default: "") var folder: String

    func perform() async throws -> some IntentResult & ReturnsValue<NoteEntity> {
        let (folder, noteTitle, content) = (self.folder, self.noteTitle, self.content)
        let path = try await withSharedVault { try $0.createNote(in: folder, named: noteTitle, content: content) }
        return .result(value: NoteEntity(id: path))
    }
}

struct AppendToDailyNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Append to Daily Note"
    static let description = IntentDescription("Adds text to today's daily note.")

    @Parameter(title: "Text") var text: String

    init() {}
    init(text: String) { self.text = text }

    func perform() async throws -> some IntentResult {
        let text = self.text
        _ = try await withSharedVault { try $0.appendToDailyNote(text) }
        return .result()
    }
}

/// Widget quick capture: adds a timestamped bullet to today's note (time taken when tapped).
struct LogTimeIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Time in Daily Note"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        let line = "- " + Templates.format(.now, "HH:mm") + " "
        _ = try await withSharedVault { try $0.appendToDailyNote(line) }
        return .result()
    }
}

struct OpenDailyNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Daily Note"
    static let description = IntentDescription("Opens today's daily note in Netherite.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(openURL("netherite://daily")))
    }
}

struct OpenNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Note"
    static let description = IntentDescription("Opens a note in Netherite.")

    @Parameter(title: "Note") var note: NoteEntity

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(SharedVault.openURL(path: note.id)))
    }
}

struct SearchNotesIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Notes"
    static let description = IntentDescription("Finds notes whose title contains the text.")

    @Parameter(title: "Text") var query: String

    func perform() async throws -> some IntentResult & ReturnsValue<[NoteEntity]> {
        let query = self.query
        return .result(value: try await withSharedVault { $0.searchTitles(query) }.map(NoteEntity.init))
    }
}

/// Starts the app with a new note (Control Center control).
struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New Note"
    static let description = IntentDescription("Opens Netherite with a new note.")

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(openURL("netherite://new")))
    }
}
