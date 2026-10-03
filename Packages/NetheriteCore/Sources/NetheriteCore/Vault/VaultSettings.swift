import Foundation

/// Per-vault settings stored in `<vault>/.netherite/app.json` (so they sync with the vault).
public struct VaultSettings: Codable, Hashable, Sendable {
    public var theme = "Netherite"
    public var newNoteFolder = ""
    public var attachmentFolder = "Attachments"
    public var readableLineLength = true
    public var spellcheck = true
    public var showLineNumbers = false
    public var defaultToReadingMode = false
    public var useWikilinks = true
    public var dailyNotes = DailyNotes()
    public var templatesFolder = "Templates"
    public var uniqueNote = UniqueNote()
    public var snapshotIntervalMinutes = 5
    public var snapshotRetentionDays = 7

    public struct DailyNotes: Codable, Hashable, Sendable {
        public var folder = "Daily"
        public var format = "yyyy-MM-dd"
        public var template = ""
        public var openOnStartup = false
    }
    public struct UniqueNote: Codable, Hashable, Sendable {
        public var folder = ""
        public var format = "yyyyMMddHHmm"
        public var template = ""
    }

    public init() {}

    // Decode leniently so older/newer files keep working.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func d<T: Decodable>(_ k: CodingKeys, _ into: inout T) { if let v = try? c.decode(T.self, forKey: k) { into = v } }
        d(.theme, &theme); d(.newNoteFolder, &newNoteFolder); d(.attachmentFolder, &attachmentFolder)
        d(.readableLineLength, &readableLineLength); d(.spellcheck, &spellcheck); d(.showLineNumbers, &showLineNumbers)
        d(.defaultToReadingMode, &defaultToReadingMode); d(.useWikilinks, &useWikilinks); d(.dailyNotes, &dailyNotes)
        d(.templatesFolder, &templatesFolder); d(.uniqueNote, &uniqueNote)
        d(.snapshotIntervalMinutes, &snapshotIntervalMinutes); d(.snapshotRetentionDays, &snapshotRetentionDays)
    }
}

public extension Vault {
    /// Loads a JSON config file from `.netherite/`, returning `fallback` when missing or unreadable.
    func loadConfig<T: Decodable>(_ name: String, as: T.Type = T.self, fallback: T) -> T {
        guard let data = try? Data(contentsOf: configURL.appending(path: name)) else { return fallback }
        return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
    }

    func saveConfig<T: Encodable>(_ name: String, _ value: T) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(value) else { return }
        try? FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
        try? data.write(to: configURL.appending(path: name), options: .atomic)
    }

    var settings: VaultSettings { loadConfig("app.json", fallback: VaultSettings()) }
}
