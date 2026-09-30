import Foundation
import Observation

public struct NoteRecord: Sendable {
    public var path: String
    public var text: String
    public var parsed: ParsedNote
    public var modified: Date
    public var created: Date
}

public struct Backlink: Identifiable, Sendable {
    public var source: String
    public var contexts: [(line: Int, text: String)]
    public var id: String { source }
}

/// In-memory index of a vault: every note's text and structure plus the resolved link graph.
// ponytail: whole vault kept in memory (fine up to ~10k notes); move text to SQLite FTS5 beyond that.
@MainActor @Observable
public final class VaultIndex {
    public let vault: Vault
    public private(set) var files: [String] = []
    public private(set) var folders: [String] = []
    public private(set) var notes: [String: NoteRecord] = [:]
    public private(set) var resolver = LinkResolver(files: [])
    /// source → resolved targets (unique, in order)
    public private(set) var outgoing: [String: [String]] = [:]
    /// target → sources
    public private(set) var incoming: [String: Set<String>] = [:]
    /// source → link targets that don't exist yet
    public private(set) var unresolved: [String: [String]] = [:]
    public private(set) var isLoaded = false
    /// Bumped on every change so views can cheaply observe "anything changed".
    public private(set) var revision = 0

    public init(vault: Vault) { self.vault = vault }

    // MARK: Loading

    public func load() async {
        let vault = self.vault
        let (entries, records) = await Task.detached(priority: .userInitiated) {
            let entries = vault.entries()
            var records: [String: NoteRecord] = [:]
            for e in entries where !e.isFolder && e.path.isMarkdown {
                if let r = Self.record(vault, e.path) { records[e.path] = r }
            }
            return (entries, records)
        }.value
        files = entries.filter { !$0.isFolder }.map(\.path)
        folders = entries.filter(\.isFolder).map(\.path)
        notes = records
        relinkAll()
        isLoaded = true
    }

    nonisolated static func record(_ vault: Vault, _ path: String) -> NoteRecord? {
        guard let text = try? vault.read(path) else { return nil }
        let values = try? vault.url(for: path).resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return NoteRecord(path: path, text: text, parsed: NoteParser.parse(text),
                          modified: values?.contentModificationDate ?? .now, created: values?.creationDate ?? .now)
    }

    /// Re-scans the folder structure and re-reads files whose modification date changed (external edits, iCloud).
    /// Paths in `skipping` (unsaved editor buffers) keep their in-memory text.
    public func refreshFromDisk(skipping: Set<String> = []) async {
        let vault = self.vault
        var known = notes.mapValues(\.modified)
        for p in skipping { known[p] = .distantFuture }
        let (entries, changed) = await Task.detached {
            let entries = vault.entries()
            var changed: [String: NoteRecord] = [:]
            for e in entries where !e.isFolder && e.path.isMarkdown {
                let mod = try? vault.url(for: e.path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if known[e.path] == .distantFuture { continue }
                if known[e.path] == nil || mod != known[e.path] { if let r = Self.record(vault, e.path) { changed[e.path] = r } }
            }
            return (entries, changed)
        }.value
        let newFiles = entries.filter { !$0.isFolder }.map(\.path)
        let removed = Set(files).subtracting(newFiles)
        guard !changed.isEmpty || !removed.isEmpty || newFiles.count != files.count || entries.filter(\.isFolder).count != folders.count else { return }
        files = newFiles
        folders = entries.filter(\.isFolder).map(\.path)
        for r in removed { notes[r] = nil }
        notes.merge(changed) { _, new in new }
        relinkAll()
    }

    // MARK: Updates

    /// Updates a note from editor text (the caller persists it).
    public func update(_ path: String, text: String) {
        guard notes[path]?.text != text else { return }
        let now = Date.now
        notes[path] = NoteRecord(path: path, text: text, parsed: NoteParser.parse(text), modified: now, created: notes[path]?.created ?? now)
        relink(path)
        revision += 1
    }

    public func didCreate(_ path: String, isFolder: Bool = false) {
        if isFolder {
            folders.append(path); folders.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        } else {
            files.append(path); files.sort { $0.localizedStandardCompare($1) == .orderedAscending }
            if path.isMarkdown, let r = Self.record(vault, path) { notes[path] = r }
        }
        relinkAll()
    }

    public func didDelete(_ path: String) {
        files.removeAll { $0 == path || $0.hasPrefix(path + "/") }
        folders.removeAll { $0 == path || $0.hasPrefix(path + "/") }
        notes = notes.filter { $0.key != path && !$0.key.hasPrefix(path + "/") }
        relinkAll()
    }

    // MARK: Create / move / delete (disk + index)

    @discardableResult
    public func createNote(in folder: String = "", named name: String = "Untitled", content: String = "") throws -> String {
        let path = try vault.createNote(in: folder, named: name, content: content)
        didCreate(path)
        return path
    }

    @discardableResult
    public func createFolder(in folder: String = "", named name: String = "Untitled") throws -> String {
        let path = try vault.createFolder(in: folder, named: name)
        didCreate(path, isFolder: true)
        return path
    }

    public func trash(_ path: String) throws {
        try vault.trash(path)
        didDelete(path)
    }

    /// Moves/renames a file or folder and rewrites every link that pointed into it.
    /// Returns the paths of notes whose text was rewritten.
    @discardableResult
    public func move(_ from: String, to: String) throws -> [String] {
        guard from != to else { return [] }
        let oldResolver = resolver
        let isFolder = folders.contains(from)
        let moved: [(String, String)] = isFolder
            ? files.filter { $0.hasPrefix(from + "/") }.map { ($0, to + $0.dropFirst(from.count)) }
            : [(from, to)]
        let movedMap = Dictionary(moved, uniquingKeysWith: { a, _ in a })
        let affected = Set(moved.flatMap { incoming[$0.0] ?? [] })
        try vault.move(from, to: to)

        // Update in-memory state for moved files
        files = files.map { movedMap[$0] ?? $0 }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        folders = folders.map { $0 == from ? to : ($0.hasPrefix(from + "/") ? to + $0.dropFirst(from.count) : $0) }
        for (old, new) in moved {
            if var r = notes.removeValue(forKey: old) { r.path = new; notes[new] = r }
        }
        resolver = LinkResolver(files: files)

        var rewritten: [String] = []
        for oldSource in affected {
            let source = movedMap[oldSource] ?? oldSource
            guard let rec = notes[source] else { continue }
            let text = Self.rewriteLinks(in: rec.text, parsed: rec.parsed) { link in
                guard let target = oldResolver.resolve(link.target, from: oldSource), let newTarget = movedMap[target] else { return nil }
                return newTarget
            } linkText: { resolver.linkText(for: $0) }
            if text != rec.text {
                try vault.write(text, to: source)
                notes[source]?.text = text
                notes[source]?.parsed = NoteParser.parse(text)
                rewritten.append(source)
            }
        }
        relinkAll()
        return rewritten
    }

    /// Replaces links for which `newTarget` returns a path, keeping subpaths, aliases and embed markers.
    public nonisolated static func rewriteLinks(in text: String, parsed: ParsedNote,
                                                newTarget: (NoteLink) -> String?, linkText: (String) -> String) -> String {
        let ns = NSMutableString(string: text)
        for link in parsed.links.reversed() where link.range.location != NSNotFound {
            guard let target = newTarget(link) else { continue }
            let replacement: String
            if link.isWiki {
                replacement = (link.isEmbed ? "!" : "") + "[[" + linkText(target) + (link.subpath.map { "#" + $0 } ?? "") + (link.alias.map { "|" + $0 } ?? "") + "]]"
            } else {
                let encoded = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "()"))) ?? target
                replacement = (link.isEmbed ? "!" : "") + "[" + (link.alias ?? "") + "](" + encoded + (link.subpath.map { "#" + $0 } ?? "") + ")"
            }
            ns.replaceCharacters(in: link.range, with: replacement)
        }
        return ns as String
    }

    // MARK: Link graph

    private func relinkAll() {
        resolver = LinkResolver(files: files)
        outgoing = [:]; incoming = [:]; unresolved = [:]
        for path in notes.keys { link(path) }
        revision += 1
    }

    private func relink(_ path: String) {
        for t in outgoing[path] ?? [] { incoming[t]?.remove(path) }
        outgoing[path] = nil; unresolved[path] = nil
        link(path)
    }

    private func link(_ path: String) {
        guard let rec = notes[path] else { return }
        var out: [String] = [], missing: [String] = []
        for l in rec.parsed.links {
            if let t = resolver.resolve(l.target, from: path) {
                if t != path, !out.contains(t) { out.append(t); incoming[t, default: []].insert(path) }
            } else if !missing.contains(l.target) { missing.append(l.target) }
        }
        outgoing[path] = out
        unresolved[path] = missing
    }

    // MARK: Queries

    public func resolve(_ link: NoteLink, from source: String) -> String? { resolver.resolve(link.target, from: source) }

    public var markdownFiles: [String] { files.filter(\.isMarkdown) }

    public func backlinks(for path: String) -> [Backlink] {
        (incoming[path] ?? []).sorted().compactMap { source in
            guard let rec = notes[source] else { return nil }
            let lines = rec.text.components(separatedBy: "\n")
            let ctx = rec.parsed.links.filter { resolver.resolve($0.target, from: source) == path && $0.range.location != NSNotFound }
                .map { (line: $0.line, text: $0.line < lines.count ? lines[$0.line] : "") }
            return Backlink(source: source, contexts: ctx)
        }
    }

    /// Plain-text mentions of the note's name or aliases that aren't links yet.
    public func unlinkedMentions(for path: String) -> [Backlink] {
        let names = [path.noteName] + (notes[path]?.parsed.aliases ?? [])
        let pattern = names.filter { !$0.isEmpty }.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        guard !pattern.isEmpty, let re = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])(?:\(pattern))(?![\\p{L}\\p{N}])", options: .caseInsensitive) else { return [] }
        var out: [Backlink] = []
        for (source, rec) in notes where source != path {
            let masked = NoteParser.maskedText(rec.text) as NSString
            let linkRanges = rec.parsed.links.map(\.range)
            var ctx: [(Int, String)] = []
            let lines = rec.text.components(separatedBy: "\n")
            let starts = NoteParser.lineStartOffsets(Array(rec.text.utf16))
            for m in re.matches(in: masked as String, range: NSRange(location: 0, length: masked.length))
            where !linkRanges.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
                let line = (starts.lastIndex { $0 <= m.range.location } ?? 0)
                if !ctx.contains(where: { $0.0 == line }) { ctx.append((line, lines[line])) }
            }
            if !ctx.isEmpty { out.append(Backlink(source: source, contexts: ctx.map { (line: $0.0, text: $0.1) })) }
        }
        return out.sorted { $0.source < $1.source }
    }

    /// Tag → number of notes, including parents of nested tags ("a/b" counts toward "a").
    public var tagCounts: [(tag: String, count: Int)] {
        var counts: [String: (String, Int)] = [:]
        for rec in notes.values {
            var seen = Set<String>()
            for tag in rec.parsed.tags {
                let parts = tag.split(separator: "/")
                for i in 1...max(1, parts.count) {
                    let t = parts.prefix(i).joined(separator: "/")
                    if seen.insert(t.lowercased()).inserted { counts[t.lowercased(), default: (t, 0)].1 += 1 }
                }
            }
        }
        return counts.values.map { (tag: $0.0, count: $0.1) }.sorted { $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
    }

    public func notes(taggedWith tag: String) -> [String] {
        let t = tag.lowercased()
        return notes.values.filter { $0.parsed.tags.contains { $0.lowercased() == t || $0.lowercased().hasPrefix(t + "/") } }.map(\.path).sorted()
    }

    /// All property keys used in the vault with their most common kind and usage count.
    public var propertyKeys: [(key: String, kind: PropertyValue.Kind, count: Int)] {
        var agg: [String: (String, [PropertyValue.Kind: Int])] = [:]
        for rec in notes.values {
            for p in rec.parsed.properties { agg[p.key.lowercased(), default: (p.key, [:])].1[p.value.kind, default: 0] += 1 }
        }
        return agg.values.map { key, kinds in
            (key: key, kind: kinds.max { $0.value < $1.value }!.key, count: kinds.values.reduce(0, +))
        }.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }
}
