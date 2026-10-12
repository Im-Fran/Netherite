import Foundation
import CryptoKit
import UniformTypeIdentifiers

public struct ImportReport: Sendable {
    public var notes: [String] = []
    public var attachments: [String] = []
    public var warnings: [String] = []
    public var folder = ""
}

/// What kind of export is being imported.
public enum ImportSource: String, CaseIterable, Sendable, Identifiable {
    case evernote, notion, html, markdown
    public var id: String { rawValue }
}

/// Reads an export (file, folder or .zip) and writes notes + attachments into a vault folder. Never overwrites.
public struct Importer: Sendable {
    public let vault: Vault
    public var destination: String
    public var converter: FormatConverter.Options

    public init(vault: Vault, destination: String, converter: FormatConverter.Options = .init()) {
        self.vault = vault; self.destination = destination; self.converter = converter
    }

    public func run(_ source: ImportSource, from url: URL) throws -> ImportReport {
        var w = Writer(vault: vault, root: destination)
        w.shortensLinks = source != .markdown   // a Markdown folder's own links are left as written
        switch source {
        case .evernote: try importENEX(url, &w)
        case .notion: importNotion(try Self.files(at: url), &w)
        case .html: importHTML(try Self.files(at: url), &w)
        case .markdown: importMarkdown(try Self.files(at: url), &w)
        }
        w.finish()
        w.report.folder = destination
        return w.report
    }

    // MARK: Sources

    /// Files of a folder, a .zip, or a single file, as (relative path, data). All the archives in a folder
    /// share one expansion budget, so many ZIPs can't add up past it.
    public static func files(at url: URL, maxTotalSize: Int = ZipReader.maxTotalSize) throws -> [(path: String, data: Data)] {
        var budget = maxTotalSize
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir)
        if isDir.boolValue {
            guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
            let base = url.standardizedFileURL.path(percentEncoded: false)
            var out: [(String, Data)] = []
            for case let f as URL in e where (try? f.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
                let rel = String(f.standardizedFileURL.path(percentEncoded: false).dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let data = try Data(contentsOf: f)
                if f.pathExtension.lowercased() == "zip", let z = try? ZipReader(data: data) { out += try z.files(budget: &budget).map { ($0.path, $0.data) } }
                else { out.append((rel, data)) }
            }
            return out
        }
        let data = try Data(contentsOf: url)
        if url.pathExtension.lowercased() == "zip" { return try ZipReader(data: data).files(budget: &budget) }
        return [(url.lastPathComponent, data)]
    }

    // MARK: Evernote

    func importENEX(_ url: URL, _ w: inout Writer) throws {
        let files = try Self.files(at: url).filter { $0.path.lowercased().hasSuffix(".enex") }
        if files.isEmpty { w.report.warnings.append(String(localized: "No .enex files found.", bundle: .module)) }
        for f in files {
            let notebook = f.path.noteName
            for note in ENEXParser.parse(f.data) {
                var byHash: [String: String] = [:]
                for r in note.resources {
                    let hash = Insecure.MD5.hash(data: r.data).map { String(format: "%02x", $0) }.joined()
                    let ext = r.fileName.fileExtension.isEmpty ? (UTType(mimeType: r.mime)?.preferredFilenameExtension ?? "bin") : r.fileName.fileExtension
                    let base = r.fileName.isEmpty ? hash : r.fileName.noteName
                    if let p = w.attachment(r.data, name: base, ext: ext, folder: files.count > 1 ? notebook : "") {
                        byHash[hash] = embed(p, mime: r.mime)
                    }
                }
                var conv = HTMLToMarkdown()
                conv.media = { byHash[$0] }
                var body = conv.convert(note.content)
                let unused = byHash.filter { !body.contains($0.value) }.map(\.value)
                if !unused.isEmpty { body += "\n" + unused.joined(separator: "\n") + "\n" }
                var props: [Property] = []
                if let c = note.created { props.append(Property(key: "created", value: .date(c))) }
                if let u = note.updated { props.append(Property(key: "updated", value: .date(u))) }
                if !note.tags.isEmpty { props.append(Property(key: "tags", value: .list(note.tags.map { $0.replacingOccurrences(of: " ", with: "-") }))) }
                if let s = note.sourceURL { props.append(Property(key: "source", value: .text(s))) }
                if let a = note.author { props.append(Property(key: "author", value: .text(a))) }
                w.note((try? Frontmatter.replacing(in: body, with: props)) ?? body, name: note.title, folder: files.count > 1 ? notebook : "", converter: nil)
            }
        }
    }

    /// Links by full vault path; `Writer.finish` shortens it once every name is known.
    func embed(_ path: String, mime: String) -> String {
        mime.hasPrefix("image/") || mime.hasPrefix("audio/") || mime.hasPrefix("video/") || mime == "application/pdf"
            ? "![[\(path)]]" : "[[\(path)]]"
    }

    // MARK: HTML (Apple Notes export, generic HTML)

    func importHTML(_ files: [(path: String, data: Data)], _ w: inout Writer) {
        let byPath = Dictionary(files.map { ($0.path.lowercased(), $0.data) }, uniquingKeysWith: { a, _ in a })
        let pages = files.filter { ["html", "htm"].contains($0.path.fileExtension) }
        if pages.isEmpty { w.report.warnings.append(String(localized: "No HTML files found.", bundle: .module)) }
        for page in pages {
            let html = String(decoding: page.data, as: UTF8.self)
            var copied: [String: String] = [:]
            var writer = w
            var conv = HTMLToMarkdown()
            conv.image = { src, alt in
                if let done = copied[src] { return done }
                var data: Data?, name = alt, ext = src.fileExtension
                if src.hasPrefix("data:"), let comma = src.firstIndex(of: ",") {
                    let meta = src[src.index(src.startIndex, offsetBy: 5)..<comma]
                    data = Data(base64Encoded: String(src[src.index(after: comma)...]))
                    ext = UTType(mimeType: String(meta.split(separator: ";").first ?? ""))?.preferredFilenameExtension ?? "png"
                    if name.isEmpty { name = "image" }
                } else if !src.contains("://") {
                    let rel = Importer.join(page.path.parentFolder, src.removingPercentEncoding ?? src)
                    data = byPath[rel.lowercased()]
                    name = (src.removingPercentEncoding ?? src).noteName
                }
                guard let data, let p = writer.attachment(data, name: name.isEmpty ? "image" : name, ext: ext.isEmpty ? "png" : ext, folder: "") else { return nil }
                let md = "![[\(p)]]"
                copied[src] = md
                return md
            }
            let md = conv.convert(html)
            w = writer
            let title = HTMLToMarkdown.title(of: html) ?? page.path.noteName
            w.note(md, name: title, folder: page.path.parentFolder, converter: converter)
        }
    }

    // MARK: Notion (Markdown & CSV export)

    static let notionID = try! NSRegularExpression(pattern: #"\s+[0-9a-f]{32}(?=(\.[A-Za-z0-9]+)?$)"#)

    /// "Page 0123…cdef.md" → "Page.md" for every path component.
    public static func stripNotionIDs(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).map { c in
            let s = String(c)
            return notionID.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: "")
        }.joined(separator: "/")
    }

    func importNotion(_ files: [(path: String, data: Data)], _ w: inout Writer) {
        var clean = Dictionary(files.map { ($0.path, Self.stripNotionIDs($0.path)) }, uniquingKeysWith: { a, _ in a })
        // CSV databases become notes; "_all.csv" duplicates are skipped.
        let csvs = files.filter { $0.path.fileExtension == "csv" && !$0.path.hasSuffix("_all.csv") }
        for c in csvs { clean[c.path] = (clean[c.path]! as NSString).deletingPathExtension + ".md" }

        // Every page and file is written first: pages that share a name get "Name 1", and links must point at that.
        var written: [String: String] = [:]   // export path → vault path
        for f in files where !["md", "csv"].contains(f.path.fileExtension) {
            let target = clean[f.path]!
            if let p = w.attachment(f.data, name: target.noteName, ext: target.fileExtension, folder: target.parentFolder) { written[f.path] = p }
        }
        let pages = files.filter { $0.path.fileExtension == "md" || $0.path.fileExtension == "csv" && clean[$0.path]!.isMarkdown }
        for f in pages {
            let target = clean[f.path]!
            var text = String(decoding: f.data, as: UTF8.self)
            if f.path.fileExtension == "csv" { text = "# \(target.noteName)\n\n" + Self.csvToTable(text) + "\n" }
            // Notion repeats the page title as a leading "# Title"; keep it (it's the note's own heading).
            if let p = w.note(text, name: target.noteName, folder: target.parentFolder, converter: converter) { written[f.path] = p }
        }
        for f in pages where f.path.fileExtension == "md" {
            guard let p = written[f.path] else { continue }
            w.replace(p, with: rewriteNotionLinks(String(decoding: f.data, as: UTF8.self), from: f.path, clean: clean, written: written))
        }
    }

    /// Notion's relative Markdown links → wikilinks by full vault path (`Writer.finish` shortens them).
    func rewriteNotionLinks(_ text: String, from source: String, clean: [String: String], written: [String: String]) -> String {
        let re = try! NSRegularExpression(pattern: #"(!?)\[([^\]\n]*)\]\(([^)\n]+)\)"#)
        let ns = text as NSString
        let out = NSMutableString(string: text)
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let url = ns.substring(with: m.range(at: 3))
            guard !url.contains("://"), !url.hasPrefix("mailto:") else { continue }
            let decoded = url.removingPercentEncoding ?? url
            let rel = Self.join(source.parentFolder, decoded)
            guard let original = clean[rel] != nil ? rel : clean.first(where: { $0.value == Self.stripNotionIDs(rel) })?.key,
                  let path = written[original] else { continue }
            let label = ns.substring(with: m.range(at: 2))
            let name = path.isMarkdown ? path.noteName : (path as NSString).lastPathComponent
            let isEmbed = m.range(at: 1).length > 0
            let full = path.isMarkdown ? (path as NSString).deletingPathExtension : path
            let link = isEmbed || label.isEmpty || label == name ? "[[\(full)]]" : "[[\(full)|\(label)]]"
            out.replaceCharacters(in: m.range, with: (isEmbed ? "!" : "") + link)
        }
        return out as String
    }

    /// Joins a relative reference onto a folder, resolving `.` and `..` (NSString doesn't for relative paths).
    static func join(_ folder: String, _ ref: String) -> String {
        var parts: [Substring] = []
        for c in (folder.isEmpty ? ref : folder + "/" + ref).split(separator: "/") {
            if c == ".." { _ = parts.popLast() } else if c != "." { parts.append(c) }
        }
        return parts.joined(separator: "/")
    }

    /// Minimal RFC 4180 CSV → GFM table.
    public static func csvToTable(_ csv: String) -> String {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false
        var chars = Array(csv.replacingOccurrences(of: "\r\n", with: "\n")).makeIterator()
        var pending: Character? = nil
        while let c = pending ?? chars.next() {
            pending = nil
            if quoted {
                if c == "\"" { if let n = chars.next() { if n == "\"" { field.append("\"") } else { quoted = false; pending = n } } else { quoted = false } }
                else { field.append(c) }
            } else {
                switch c {
                case "\"": quoted = true
                case ",": row.append(field); field = ""
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        rows = rows.filter { !($0.count == 1 && $0[0].isEmpty) }
        guard let header = rows.first else { return "" }
        let width = rows.map(\.count).max() ?? header.count
        func line(_ r: [String]) -> String {
            "| " + (r + Array(repeating: "", count: width - r.count)).map {
                $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: "<br>")
            }.joined(separator: " | ") + " |"
        }
        return ([line(header), "|" + String(repeating: " --- |", count: width)] + rows.dropFirst().map(line)).joined(separator: "\n")
    }

    // MARK: Markdown folders (Bear, Typora, iA Writer…)

    func importMarkdown(_ files: [(path: String, data: Data)], _ w: inout Writer) {
        for f in files where !["md", "markdown", "txt"].contains(f.path.fileExtension) {
            _ = w.attachment(f.data, name: f.path.noteName, ext: f.path.fileExtension, folder: f.path.parentFolder, keepFolder: true)
        }
        for f in files where ["md", "markdown", "txt"].contains(f.path.fileExtension) {
            // Textbundles keep their text in "text.md" inside "Name.textbundle/".
            var folder = f.path.parentFolder, name = f.path.noteName
            if folder.hasSuffix(".textbundle") { name = folder.noteName; folder = folder.parentFolder }
            w.note(String(decoding: f.data, as: UTF8.self), name: name, folder: folder, converter: converter)
        }
    }
}

/// Collects writes so name collisions and the report are handled in one place.
struct Writer {
    let vault: Vault
    let root: String
    var report = ImportReport()
    /// Shorten full-path wikilinks to imported files in `finish` (importers that write links themselves).
    var shortensLinks = false
    /// (path, raw text, converter) — converted after all notes exist so links can resolve.
    private var pending: [(String, String, FormatConverter.Options?)] = []

    init(vault: Vault, root: String) { self.vault = vault; self.root = root }

    /// Archive paths are untrusted: `..`, `.` and empty components never shape the destination.
    func folderPath(_ sub: String) -> String {
        "\(root)/\(sub)".split(separator: "/").filter { $0 != "." && $0 != ".." }.joined(separator: "/")
    }

    static func safeName(_ s: String) -> String {
        let cleaned = s.replacingOccurrences(of: #"[\\/:*?"<>|#^\[\]\n\r\t]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^[.\s]+"#, with: "", options: .regularExpression)   // ".NET tips" would be a hidden file
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? String(localized: "Untitled", bundle: .module) : String(cleaned.prefix(120))
    }

    @discardableResult
    mutating func note(_ text: String, name: String, folder: String, converter: FormatConverter.Options?) -> String? {
        let path = vault.availablePath(folder: folderPath(folder), base: Self.safeName(name))
        do {
            try vault.write(text, to: path)   // reserve the name now; converted in finish()
            pending.append((path, text, converter))
            report.notes.append(path)
            return path
        } catch { report.warnings.append("\(name): \(error.localizedDescription)"); return nil }
    }

    /// New text for a note already written (links computed once every name is reserved).
    mutating func replace(_ path: String, with text: String) {
        guard let i = pending.firstIndex(where: { $0.0 == path }) else { return }
        do { try vault.write(text, to: path); pending[i].1 = text }
        catch { report.warnings.append("\(path.noteName): \(error.localizedDescription)") }
    }

    @discardableResult
    mutating func attachment(_ data: Data, name: String, ext: String, folder: String, keepFolder: Bool = false) -> String? {
        let dir = keepFolder ? folderPath(folder) : folderPath(["Attachments", folder].filter { !$0.isEmpty }.joined(separator: "/"))
        let path = vault.availablePath(folder: dir, base: Self.safeName(name), ext: ext.lowercased())
        do { try vault.write(data, to: path); report.attachments.append(path); return path }
        catch { report.warnings.append("\(name).\(ext): \(error.localizedDescription)"); return nil }
    }

    /// Link shortening and format conversion run over every imported note once all names are known.
    mutating func finish() {
        let files = report.notes + report.attachments
        // Full-path links to imported files become what Obsidian writes: the shortest text that is unambiguous
        // in the whole vault, so two "image.png" or "Notes" never resolve to each other.
        let resolver = LinkResolver(files: shortensLinks ? vault.allFiles() : [])
        let full = Dictionary(files.map { ($0.isMarkdown ? ($0 as NSString).deletingPathExtension : $0, $0) }, uniquingKeysWith: { a, _ in a })
        let wikiTarget = try! NSRegularExpression(pattern: #"(?<=\[\[)[^\[\]|#\n]+"#)
        for (path, text, opts) in pending {
            var out = text
            if shortensLinks {
                let ns = text as NSString
                out = HTMLRenderer.splice(ns, wikiTarget.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
                    full[ns.substring(with: m.range)].map { (m.range, resolver.linkText(for: $0)) }
                })
            }
            if let opts { out = FormatConverter(options: opts, files: files).convert(out, path: path) }
            if out != text { try? vault.write(out, to: path) }
        }
        pending = []
    }
}
