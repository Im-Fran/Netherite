import Foundation
import CryptoKit
import UniformTypeIdentifiers

/// Deploys a folder to Cloudflare Pages with the Direct Upload API — the same flow `wrangler pages deploy` uses:
/// upload token → check-missing → upload buckets → upsert-hashes → multipart deployment with a manifest.
public struct CloudflarePagesDeployer: Sendable {
    public var accountID: String
    public var projectName: String
    public var apiToken: String
    public var api = URL(string: "https://api.cloudflare.com/client/v4")!

    public init(accountID: String, projectName: String, apiToken: String) {
        self.accountID = accountID; self.projectName = projectName; self.apiToken = apiToken
    }

    public struct Asset: Sendable, Hashable {
        /// Site path with a leading slash ("/books/x.html").
        public var path: String
        public var hash: String
        public var base64: String
        public var contentType: String
    }

    public struct DeployError: LocalizedError, Sendable {
        public var message: String
        public var errorDescription: String? { message }
    }

    // MARK: Offline pieces (tested)

    /// Wrangler hashes with blake3(base64 + extension) truncated to 32 hex chars. Cloudflare only needs a
    /// stable 32-hex key per content, so we use SHA-256 over the same input (no blake3 in the SDK).
    public static func hash(base64: String, ext: String) -> String {
        SHA256.hash(data: Data((base64 + ext).utf8)).map { String(format: "%02x", $0) }.joined().prefix(32).description
    }

    public static func assets(in dir: URL) throws -> [Asset] {
        let root = dir.standardizedFileURL.path(percentEncoded: false)
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [Asset] = []
        for case let url as URL in e where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let full = url.standardizedFileURL.path(percentEncoded: false)
            let rel = String(full.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let b64 = try Data(contentsOf: url).base64EncodedString()
            let ext = url.pathExtension
            out.append(Asset(path: "/" + rel, hash: hash(base64: b64, ext: ext), base64: b64,
                             contentType: UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"))
        }
        return out.sorted { $0.path < $1.path }
    }

    public static func manifest(_ assets: [Asset]) -> [String: String] {
        Dictionary(assets.map { ($0.path, $0.hash) }, uniquingKeysWith: { a, _ in a })
    }

    /// Groups uploads like wrangler: at most 5000 files / ~40 MB of base64 per request.
    public static func buckets(_ assets: [Asset], maxCount: Int = 5000, maxBytes: Int = 40 * 1024 * 1024) -> [[Asset]] {
        var out: [[Asset]] = [], cur: [Asset] = [], size = 0
        for a in assets {
            if !cur.isEmpty && (cur.count >= maxCount || size + a.base64.utf8.count > maxBytes) { out.append(cur); cur = []; size = 0 }
            cur.append(a); size += a.base64.utf8.count
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    public func request(_ method: String, _ path: String, bearer: String? = nil, json: Any? = nil) throws -> URLRequest {
        var r = URLRequest(url: api.appending(path: path))
        r.httpMethod = method
        r.setValue("Bearer \(bearer ?? apiToken)", forHTTPHeaderField: "Authorization")
        if let json {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return r
    }

    public func deploymentRequest(manifest: [String: String], branch: String = "main", boundary: String = "netherite-\(UUID().uuidString)") throws -> URLRequest {
        var r = try request("POST", "accounts/\(accountID)/pages/projects/\(projectName)/deployments")
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let manifestJSON = String(decoding: try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
        var body = ""
        for (name, value) in [("manifest", manifestJSON), ("branch", branch)] {
            body += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
        }
        body += "--\(boundary)--\r\n"
        r.httpBody = Data(body.utf8)
        return r
    }

    // MARK: Network

    /// Deploys `dir`, creating the project if needed. Returns the deployment URL.
    public func deploy(_ dir: URL, session: URLSession = .shared, progress: @Sendable (String) -> Void = { _ in }) async throws -> URL {
        let assets = try Self.assets(in: dir)
        guard !assets.isEmpty else { throw DeployError(message: String(localized: "There's nothing to deploy in that folder.")) }

        progress(String(localized: "Checking project…"))
        try await ensureProject(session)

        progress(String(localized: "Requesting upload token…"))
        struct JWT: Decodable { var jwt: String }
        let jwt = try await call(try request("GET", "accounts/\(accountID)/pages/projects/\(projectName)/upload-token"), session, as: JWT.self).jwt

        let hashes = assets.map(\.hash)
        let missing = Set(try await call(try request("POST", "pages/assets/check-missing", bearer: jwt, json: ["hashes": hashes]), session, as: [String].self))
        let toUpload = assets.filter { missing.contains($0.hash) }
        for (i, bucket) in Self.buckets(toUpload).enumerated() {
            progress(String(localized: "Uploading files (\(i + 1))…"))
            let payload = bucket.map { ["key": $0.hash, "value": $0.base64, "metadata": ["contentType": $0.contentType], "base64": true] as [String: Any] }
            _ = try await raw(try request("POST", "pages/assets/upload", bearer: jwt, json: payload), session)
        }
        _ = try? await raw(try request("POST", "pages/assets/upsert-hashes", bearer: jwt, json: ["hashes": hashes]), session)

        progress(String(localized: "Creating deployment…"))
        struct Deployment: Decodable { var url: String? }
        let d = try await call(try deploymentRequest(manifest: Self.manifest(assets)), session, as: Deployment.self)
        guard let s = d.url, let url = URL(string: s) else { return URL(string: "https://\(projectName).pages.dev")! }
        return url
    }

    private func ensureProject(_ session: URLSession) async throws {
        let (data, response) = try await session.data(for: try request("GET", "accounts/\(accountID)/pages/projects/\(projectName)"))
        if (response as? HTTPURLResponse)?.statusCode == 200 { return }
        if (response as? HTTPURLResponse)?.statusCode != 404 { throw Self.error(from: data) }
        _ = try await raw(try request("POST", "accounts/\(accountID)/pages/projects",
                                      json: ["name": projectName, "production_branch": "main"]), session)
    }

    private struct Envelope<T: Decodable>: Decodable {
        var success: Bool
        var result: T?
    }

    private func call<T: Decodable>(_ r: URLRequest, _ session: URLSession, as: T.Type) async throws -> T {
        let data = try await raw(r, session)
        guard let e = try? JSONDecoder().decode(Envelope<T>.self, from: data), e.success, let result = e.result else { throw Self.error(from: data) }
        return result
    }

    private func raw(_ r: URLRequest, _ session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: r)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw Self.error(from: data) }
        return data
    }

    static func error(from data: Data) -> DeployError {
        struct E: Decodable { struct M: Decodable { var code: Int?; var message: String }; var errors: [M]? }
        let msg = (try? JSONDecoder().decode(E.self, from: data))?.errors?.map(\.message).joined(separator: "\n")
        return DeployError(message: msg ?? String(localized: "Cloudflare returned an unexpected response."))
    }
}
