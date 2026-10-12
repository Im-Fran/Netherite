import Foundation
import CryptoKit

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
    /// Ids of turned-off `CorePlugin`s; unknown ids are kept but ignored.
    public var disabledPlugins: Set<String> = []
    public var meetingNotes = MeetingNotes()

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
    public struct MeetingNotes: Codable, Hashable, Sendable {
        public var folder = "Meetings"
        /// Date prefix of the note name (`yyyy-MM-dd Title`).
        public var format = "yyyy-MM-dd"
        public var template = ""

        public init() {}
        public init(from decoder: Decoder) throws {
            self.init()
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let v = try? c.decode(String.self, forKey: .folder) { folder = v }
            if let v = try? c.decode(String.self, forKey: .format) { format = v }
            if let v = try? c.decode(String.self, forKey: .template) { template = v }
        }
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
        d(.disabledPlugins, &disabledPlugins); d(.meetingNotes, &meetingNotes)
    }
}

public extension Vault {
    /// Loads a JSON config file from `.netherite/`, returning `fallback` when missing or unreadable.
    func loadConfig<T: Decodable>(_ name: String, as: T.Type = T.self, fallback: T) -> T {
        guard let data = try? Data(contentsOf: configURL.appending(path: name)) else { return fallback }
        return (try? JSONDecoder().decode(T.self, from: data)) ?? fallback
    }

    /// Writes a JSON config file to `.netherite/`, unless it already holds exactly that (every write is a sync,
    /// and a possible conflict, in iCloud). Returns whether the file now holds `value`.
    @discardableResult
    func saveConfig<T: Encodable>(_ name: String, _ value: T) -> Bool {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(value) else { return false }
        let url = configURL.appending(path: name)
        if (try? Data(contentsOf: url)) == data { return true }
        try? FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    var settings: VaultSettings { loadConfig("app.json", fallback: VaultSettings()) }

    /// Stable identifier stored in the vault, so data kept on the device (File Recovery snapshots)
    /// follows the folder when it moves or is renamed.
    var stableID: String { storedID ?? newStableID() }

    /// `stableID`, telling a copy of a vault from a moved one: `ledger` is a device-local folder that records which
    /// folder holds each ID. When that folder still exists with the same ID, this one is a copy and gets its own.
    func stableID(ledger: URL) -> String {
        let path = Self.canonicalPath(root)
        var id = stableID
        if let owner = try? String(contentsOf: ledger.appending(path: id + ".owner"), encoding: .utf8),
           Self.canonicalPath(URL(filePath: owner)) != path,
           Vault(root: URL(filePath: owner, directoryHint: .isDirectory)).storedID == id {
            id = newStableID()
        }
        let record = ledger.appending(path: id + ".owner")
        if (try? String(contentsOf: record, encoding: .utf8)) != path {
            try? FileManager.default.createDirectory(at: ledger, withIntermediateDirectories: true)
            try? path.write(to: record, atomically: true, encoding: .utf8)
        }
        return id
    }

    /// The ID in `id.json`. The file travels with the vault, so only a well-formed UUID is trusted as a folder name.
    private var storedID: String? {
        loadConfig("id.json", fallback: String?.none).flatMap(UUID.init(uuidString:))?.uuidString
    }

    private func newStableID() -> String {
        let id = UUID().uuidString
        // While `id.json` is still an iCloud placeholder, a new ID would sync over the real one; a read-only vault
        // can't keep one. Either way an ID from the path stays the same on every call.
        let placeholder = configURL.appending(path: ".id.json.icloud").path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: placeholder), saveConfig("id.json", id) else {
            return Data(SHA256.hash(data: Data(Self.canonicalPath(root).utf8))).withUnsafeBytes {
                UUID(uuid: $0.loadUnaligned(as: uuid_t.self)).uuidString
            }
        }
        return id
    }

    /// One spelling per folder (symlinks resolved, no trailing `/`), so the ledger and the hash compare paths, not text.
    private static func canonicalPath(_ url: URL) -> String {
        let path = url.resolvingSymlinksInPath().path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// A vault name as one folder name: separators become dashes and leading dots go (`..`, hidden folders); nil when empty.
    static func folderName(for name: String) -> String? {
        // By scalar and with the same set as the trim, so neither `.\u{301}` nor `\u{200B}.` can leave a dot in front.
        let scalars = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .unicodeScalars.drop { $0 == "." || CharacterSet.whitespacesAndNewlines.contains($0) }   // `. ..` too
        let clean = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
