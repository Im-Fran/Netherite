import Foundation
import Testing
@testable import NetheriteCore

@MainActor @Test func exportsSampleVault() async throws {
    let vaultURL = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../Fixtures/SampleVault").standardizedFileURL
    let index = VaultIndex(vault: Vault(root: vaultURL))
    await index.load()
    let out = FileManager.default.temporaryDirectory.appending(path: "netherite-site-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: out) }

    let report = try SiteExporter.export(index, to: out)
    #expect(report.pages == index.markdownFiles.filter { !$0.hasPrefix("Templates/") }.count)
    func read(_ p: String) throws -> String { try String(contentsOf: out.appending(path: p), encoding: .utf8) }
    for f in ["index.html", "welcome.html", "projects/japan-trip.html", "graph.html", "404.html", "search.json",
              "assets/reader.css", "assets/site.js", "assets/katex/katex.min.js", "files/Attachments/ingot.png", "tags/books.html"] {
        #expect(FileManager.default.fileExists(atPath: out.appending(path: f).path(percentEncoded: false)), "missing \(f)")
    }
    let trip = try read("projects/japan-trip.html")
    #expect(trip.contains("href=\"../welcome.html\""))
    #expect(trip.contains("href=\"../books/thinking-fast-and-slow.html\""))
    #expect(trip.contains("href=\"../assets/reader.css\""))
    let evergreen = try read("evergreen-notes.html")
    #expect(evergreen.contains("<span class=\"is-unresolved\">Missing note</span>"))
    let welcome = try read("welcome.html")
    #expect(welcome.contains("src=\"files/Attachments/ingot.png\""))
    #expect(welcome.contains("Links to this page"))   // backlinks
    #expect(welcome.contains("href=\"tags/ideas-writing.html\""))

    let search = try JSONSerialization.jsonObject(with: Data(read("search.json").utf8)) as? [[String: String]]
    #expect(search?.contains { $0["path"] == "projects/japan-trip.html" && $0["title"] == "Japan Trip" } == true)

    var published = PublishOptions(); published.scope = .folder; published.folder = "Books"
    let out2 = out.appending(path: "books-only")
    #expect(try SiteExporter.export(index, to: out2, options: published).pages == 1)
}

@Test func cloudflareRequests() throws {
    let dir = FileManager.default.temporaryDirectory.appending(path: "netherite-cf-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir.appending(path: "a"), withIntermediateDirectories: true)
    try Data("<h1>hi</h1>".utf8).write(to: dir.appending(path: "index.html"))
    try Data("body{}".utf8).write(to: dir.appending(path: "a/s.css"))

    let assets = try CloudflarePagesDeployer.assets(in: dir)
    #expect(assets.map(\.path) == ["/a/s.css", "/index.html"])
    #expect(assets.allSatisfy { $0.hash.count == 32 && $0.hash.allSatisfy(\.isHexDigit) })
    #expect(assets.first { $0.path == "/index.html" }?.contentType == "text/html")
    #expect(CloudflarePagesDeployer.hash(base64: "YQ==", ext: "html") == CloudflarePagesDeployer.hash(base64: "YQ==", ext: "html"))
    #expect(CloudflarePagesDeployer.manifest(assets)["/index.html"] == assets[1].hash)
    #expect(CloudflarePagesDeployer.buckets(assets, maxCount: 1).count == 2)

    let d = CloudflarePagesDeployer(accountID: "acc", projectName: "site", apiToken: "tok")
    let check = try d.request("POST", "pages/assets/check-missing", bearer: "jwt", json: ["hashes": ["x"]])
    #expect(check.url?.absoluteString == "https://api.cloudflare.com/client/v4/pages/assets/check-missing")
    #expect(check.value(forHTTPHeaderField: "Authorization") == "Bearer jwt")

    let deploy = try d.deploymentRequest(manifest: ["/index.html": "abc"], boundary: "B")
    #expect(deploy.url?.absoluteString == "https://api.cloudflare.com/client/v4/accounts/acc/pages/projects/site/deployments")
    #expect(deploy.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=B")
    let body = String(decoding: deploy.httpBody ?? Data(), as: UTF8.self)
    #expect(body.contains("name=\"manifest\"\r\n\r\n{\"/index.html\":\"abc\"}\r\n"))
    #expect(body.hasSuffix("--B--\r\n"))
}
