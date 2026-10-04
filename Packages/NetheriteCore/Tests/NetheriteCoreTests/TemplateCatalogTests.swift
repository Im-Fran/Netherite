import Foundation
import Testing
@testable import NetheriteCore

private let catalogJSON = #"""
{"version": 1, "future": true, "templates": [
 {"id": "meeting", "lang": "en", "name": "Meeting", "description": "Agenda", "symbol": "person.2", "tags": ["work"], "path": "templates/en/meeting.md", "body": "# {{title}}\n"},
 {"id": "meeting", "lang": "es", "name": "Reunión", "description": "Agenda", "symbol": "person.2", "tags": ["trabajo"], "path": "templates/es/meeting.md", "body": "# {{title}}\n"},
 {"id": "recipe", "lang": "en", "name": "Recipe", "path": "templates/en/recipe.md", "body": "## Ingredients\n"}
]}
"""#

private func response(_ code: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(url: TemplateCatalog.url, statusCode: code, httpVersion: nil, headerFields: nil)!
}

@Test func templateCatalogPicksLanguage() throws {
    let c = try TemplateCatalog.decode(Data(catalogJSON.utf8), response: response())
    #expect(c.templates.count == 3)
    #expect(c.entries(for: ["es-CL"]).map(\.name) == ["Recipe", "Reunión"])
    #expect(c.entries(for: ["pt-BR"]).map(\.name) == ["Meeting", "Recipe"])
    let recipe = try #require(c.templates.first { $0.id == "recipe" })
    #expect(recipe.symbol == "doc.text" && recipe.tags.isEmpty && recipe.description.isEmpty)
    #expect(recipe.builtIn.name == "Recipe" && recipe.builtIn.body == "## Ingredients\n")
}

@Test func templateCatalogRejectsBadResponses() {
    #expect(throws: (any Error).self) { try TemplateCatalog.decode(Data(catalogJSON.utf8), response: response(404)) }
    #expect(throws: (any Error).self) { try TemplateCatalog.decode(Data("<html>".utf8), response: response()) }
}
