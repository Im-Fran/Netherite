import SwiftUI
import TipKit
import NetheriteCore

/// A bookmarked file, folder, heading, block or search (stored in `.netherite/bookmarks.json`).
struct Bookmark: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case file, folder, search, heading, graph }
    var kind: Kind
    var path: String?
    var subpath: String?
    var query: String?
    var title: String?
    var id: String { "\(kind.rawValue):\(path ?? ""):\(subpath ?? ""):\(query ?? "")" }

    static func file(_ p: String) -> Bookmark { Bookmark(kind: .file, path: p) }
    static func folder(_ p: String) -> Bookmark { Bookmark(kind: .folder, path: p) }
    static func search(_ q: String) -> Bookmark { Bookmark(kind: .search, query: q) }
    static func heading(_ p: String, _ h: String) -> Bookmark { Bookmark(kind: .heading, path: p, subpath: h) }

    var displayTitle: String {
        if let title { return title }
        switch kind {
        case .search: return query ?? ""
        case .heading: return "\(path?.noteName ?? "") › \(subpath ?? "")"
        case .graph: return String(localized: "Graph View")
        default: return path.map { $0.isMarkdown ? $0.noteName : ($0 as NSString).lastPathComponent } ?? ""
        }
    }

    var symbolName: String {
        switch kind {
        case .search: "magnifyingglass"
        case .heading: "number"
        case .folder: "folder"
        case .graph: "point.3.connected.trianglepath.dotted"
        case .file: symbol(for: path ?? "")
        }
    }
}

extension VaultModel {
    func addBookmark(_ b: Bookmark) {
        guard !bookmarks.contains(b) else { return }
        bookmarks.append(b)
        NetheriteTips.donate(NetheriteTips.bookmarkAdded)
    }

    func removeBookmark(_ b: Bookmark) { bookmarks.removeAll { $0 == b } }

    func isBookmarked(_ path: String) -> Bool { bookmarks.contains { $0.kind == .file && $0.path == path } }

    @discardableResult
    func newCanvas(in folder: String) -> String? {
        let path = vault.availablePath(folder: folder, base: String(localized: "Untitled"), ext: "canvas")
        return writeNew(path, #"{"nodes":[],"edges":[]}"#)
    }

    @discardableResult
    func newBase(in folder: String) -> String? {
        let path = vault.availablePath(folder: folder, base: String(localized: "Untitled"), ext: "base")
        return writeNew(path, "views:\n  - type: table\n    name: \(String(localized: "Table"))\n    order:\n      - file.name\n")
    }

    /// A database: folder `name` for its entries, and `name.base` beside it with a table and a status board.
    @discardableResult
    func newDatabase(named name: String, in parent: String) -> String? {
        let clean = Templates.fileName(name)
        do {
            let folder = try index.createFolder(in: parent, named: clean.isEmpty ? String(localized: "Untitled") : clean)
            let base = BaseFile.database(folder: folder, boardColumns: [String(localized: "To Do"), String(localized: "In Progress"), String(localized: "Done")])
            return writeNew(vault.availablePath(folder: parent, base: (folder as NSString).lastPathComponent, ext: "base"), base.yaml)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// `Meetings.base` beside the meeting notes folder, newest first.
    func newMeetingsBase() -> String? {
        let folder = settings.meetingNotes.folder
        var base = BaseFile.database(folder: folder, properties: ["date", "attendees"])
        base.views[0].name = String(localized: "Meetings")
        base.views[0].sort = [BaseSort(property: "date", ascending: false)]
        return writeNew(vault.availablePath(folder: folder.parentFolder, base: String(localized: "Meetings"), ext: "base"), base.yaml)
    }

    /// Copies templates into the templates folder, never overwriting; returns how many were added.
    @discardableResult
    func addTemplates(_ list: [BuiltInTemplate] = Templates.builtIns) -> Int {
        list.filter { t in
            let path = templatePath(t)
            return !vault.exists(path) && writeNew(path, t.body) != nil
        }.count
    }

    /// Where `addTemplates` writes `t`.
    func templatePath(_ t: BuiltInTemplate) -> String {
        "\(settings.templatesFolder)/\(Templates.fileName(t.name)).md"
    }

    private func writeNew(_ path: String, _ content: String) -> String? {
        do { try vault.write(content, to: path); index.didCreate(path); return path }
        catch { lastError = error.localizedDescription; return nil }
    }
}
