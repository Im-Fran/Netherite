import ArgumentParser
import Foundation
import NetheriteCore

@main
struct Netherite: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Work with Netherite (and Obsidian) vaults from the terminal.",
        subcommands: [List.self, SearchCmd.self, New.self, Daily.self, Export.self, Publish.self, Backlinks.self, Tags.self])
}

struct VaultArg: ParsableArguments {
    @Argument(help: "Path to the vault folder.") var vault: String

    @MainActor func load() async throws -> VaultIndex {
        let url = URL(filePath: (vault as NSString).expandingTildeInPath).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir), isDir.boolValue else {
            throw ValidationError("No vault folder at \(vault)")
        }
        let index = VaultIndex(vault: Vault(root: url))
        await index.load()
        return index
    }
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List notes.")
    @OptionGroup var v: VaultArg
    @MainActor func run() async throws {
        for p in try await v.load().markdownFiles { print(p) }
    }
}

struct SearchCmd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "search", abstract: "Search notes (supports tag:, path:, file:, \"phrases\", -exclude).")
    @OptionGroup var v: VaultArg
    @Argument var query: [String]
    @MainActor func run() async throws {
        let index = try await v.load()
        for hit in Search.run(SearchQuery(query.joined(separator: " ")), in: index.notes) {
            print(hit.path)
            for m in hit.matches.prefix(3) { print("  \(m.line + 1): \(m.text.trimmingCharacters(in: .whitespaces))") }
        }
    }
}

struct New: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create a note.")
    @OptionGroup var v: VaultArg
    @Argument var name: String
    @Option var content = ""
    @Option var folder = ""
    @MainActor func run() async throws {
        let vault = Vault(root: URL(filePath: (v.vault as NSString).expandingTildeInPath))
        print(try vault.createNote(in: folder, named: name, content: content))
    }
}

struct Daily: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create (if needed) and print today's daily note path.")
    @OptionGroup var v: VaultArg
    @MainActor func run() async throws {
        let vault = Vault(root: URL(filePath: (v.vault as NSString).expandingTildeInPath))
        let s = vault.settings
        let path = Templates.dailyNotePath(for: .now, settings: s)
        if !vault.exists(path) {
            let tpl = s.dailyNotes.template.isEmpty ? "" : ((try? vault.read(s.dailyNotes.template.hasSuffix(".md") ? s.dailyNotes.template : s.dailyNotes.template + ".md")) ?? "")
            try vault.write(Templates.render(tpl, title: path.noteName), to: path)
        }
        print(path)
    }
}

struct ExportOptions: ParsableArguments {
    @Option(help: "Output folder.") var out: String
    @Option(help: "Only publish this folder.") var folder: String?
    @Flag(help: "Only publish notes with `publish: true`.") var onlyPublished = false
    @Option(help: "Home note path.") var home: String?

    var options: PublishOptions {
        var o = PublishOptions()
        if let folder { o.scope = .folder; o.folder = folder }
        if onlyPublished { o.scope = .published }
        o.home = home ?? ""
        return o
    }
    var outURL: URL { URL(filePath: (out as NSString).expandingTildeInPath).standardizedFileURL }
}

struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Export the vault as a static website.")
    @OptionGroup var v: VaultArg
    @OptionGroup var e: ExportOptions
    @MainActor func run() async throws {
        let index = try await v.load()
        let r = try await SiteExporter.export(index, to: e.outURL, options: e.options, theme: .netherite)
        print("Exported \(r.pages) pages and \(r.attachments) attachments to \(e.outURL.path(percentEncoded: false))")
    }
}

struct Publish: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Export and deploy to Cloudflare Pages (token from CLOUDFLARE_API_TOKEN).")
    @OptionGroup var v: VaultArg
    @OptionGroup var e: ExportOptions
    @Option(help: "Cloudflare account ID.") var account: String
    @Option(help: "Cloudflare Pages project name.") var project: String
    @MainActor func run() async throws {
        guard let token = ProcessInfo.processInfo.environment["CLOUDFLARE_API_TOKEN"], !token.isEmpty else {
            throw ValidationError("Set CLOUDFLARE_API_TOKEN to a token with Cloudflare Pages: Edit permission.")
        }
        let index = try await v.load()
        try await SiteExporter.export(index, to: e.outURL, options: e.options, theme: .netherite)
        let url = try await CloudflarePagesDeployer(accountID: account, projectName: project, apiToken: token)
            .deploy(e.outURL) { print($0) }
        print("Deployed: \(url.absoluteString)")
    }
}

struct Backlinks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List notes linking to a note.")
    @OptionGroup var v: VaultArg
    @Argument(help: "Note name or path.") var note: String
    @MainActor func run() async throws {
        let index = try await v.load()
        guard let path = index.resolver.resolve(note, from: "") else { throw ValidationError("No note named \(note)") }
        for b in index.backlinks(for: path) { print(b.source) }
    }
}

struct Tags: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List tags with note counts.")
    @OptionGroup var v: VaultArg
    @MainActor func run() async throws {
        for t in try await v.load().tagCounts { print("#\(t.tag)\t\(t.count)") }
    }
}
