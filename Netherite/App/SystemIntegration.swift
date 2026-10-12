import SwiftUI
@preconcurrency import CoreSpotlight
import WidgetKit
import NetheriteCore

/// Spotlight indexing and widget refreshes, kept out of the vault model.
enum SystemIntegration {
    /// Per vault (keyed by domain), so saving in one vault doesn't cancel another's reindex.
    private static var pending: [String: Task<Void, Never>] = [:]

    /// Debounced: refresh widgets and reindex after a burst of saves.
    static func noteSaved(_ model: VaultModel) {
        let domain = vaultDomain(model)
        pending[domain]?.cancel()
        pending[domain] = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
            NetheriteShortcuts.updateAppShortcutParameters()
            reindex(model)
        }
    }

    /// Replaces this vault's Spotlight items (domain = vault path).
    // ponytail: full reindex each time; switch to per-note updates if vaults get large.
    static func reindex(_ model: VaultModel) {
        let domain = vaultDomain(model)
        let items = model.index.notes.values.map { rec -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = rec.path.noteName
            attrs.contentDescription = String(rec.text.prefix(300))
            attrs.keywords = rec.parsed.tags + rec.parsed.aliases
            attrs.contentModificationDate = rec.modified
            return CSSearchableItem(uniqueIdentifier: domain + "|" + rec.path, domainIdentifier: domain, attributeSet: attrs)
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            index.indexSearchableItems(items)
        }
    }

    private static func vaultDomain(_ model: VaultModel) -> String { model.vault.root.path(percentEncoded: false) }

    /// The `open` deep link for a Spotlight identifier ("vault root|note path"; pre-namespacing ones are a bare path),
    /// routed like any link so a note of another vault opens there (or not at all) and a missing one is skipped.
    /// Both parts may contain "|": the vault is the first prefix naming a known vault; nil when none does.
    static func openLink(forIdentifier id: String) -> URL? {
        var link = URLComponents()
        link.scheme = "netherite"; link.host = "open"
        if !id.contains("|") {
            link.queryItems = [URLQueryItem(name: "path", value: id)]
        } else {
            guard let bar = id.indices.first(where: { id[$0] == "|" && $0 > id.startIndex && AppModel.shared.isKnownVault(String(id[..<$0])) }) else { return nil }
            link.queryItems = [URLQueryItem(name: "path", value: String(id[id.index(after: bar)...])),
                               URLQueryItem(name: "vault", value: String(id[..<bar]))]
        }
        return link.url
    }
}
