import SwiftUI
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
        case .graph: return String(localized: "Graph view")
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
        return writeNew(path, "views:\n  - type: table\n    name: Table\n    order:\n      - file.name\n")
    }

    private func writeNew(_ path: String, _ content: String) -> String? {
        do { try vault.write(content, to: path); index.didCreate(path); return path }
        catch { lastError = error.localizedDescription; return nil }
    }
}
