import Foundation

/// The online template gallery: `templates/index.json` on the Netherite site (gh-pages),
/// generated from one `.md` per template and language.
public struct TemplateCatalog: Codable, Sendable {
    public static let url = URL(string: "https://im-fran.github.io/Netherite/templates/index.json")!

    public struct Entry: Codable, Identifiable, Hashable, Sendable {
        public var id: String
        public var lang: String
        public var name: String
        public var description: String
        public var symbol: String
        public var tags: [String]
        public var path: String
        public var body: String

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            lang = try c.decode(String.self, forKey: .lang)
            name = try c.decode(String.self, forKey: .name)
            description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "doc.text"
            tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
            path = try c.decode(String.self, forKey: .path)
            body = try c.decode(String.self, forKey: .body)
        }

        /// As a template `VaultModel.addTemplates` can install.
        public var builtIn: BuiltInTemplate { BuiltInTemplate(id: id, name: name, symbol: symbol, body: body) }
    }

    public var version: Int
    public var templates: [Entry]

    public static func fetch(session: URLSession = .shared) async throws -> TemplateCatalog {
        let (data, response) = try await session.data(from: url)
        return try decode(data, response: response)
    }

    public static func decode(_ data: Data, response: URLResponse) throws -> TemplateCatalog {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(TemplateCatalog.self, from: data)
    }

    /// One entry per template, in the first preferred language it has (`es-CL` → `es`), else English; sorted by name.
    public func entries(for languages: [String] = Locale.preferredLanguages) -> [Entry] {
        let codes = languages.map { Locale(identifier: $0).language.languageCode?.identifier ?? $0 } + ["en"]
        return Dictionary(grouping: templates, by: \.id).values.compactMap { group in
            codes.lazy.compactMap { code in group.first { $0.lang == code } }.first ?? group.first
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
