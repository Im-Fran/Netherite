import SwiftUI
import CoreSpotlight
import WidgetKit
import NetheriteCore

/// Spotlight indexing and widget refreshes, kept out of the vault model.
enum SystemIntegration {
    private static var pending: Task<Void, Never>?

    /// Debounced: refresh widgets and reindex after a burst of saves.
    static func noteSaved(_ model: VaultModel) {
        pending?.cancel()
        pending = Task {
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
        let domain = model.vault.root.path(percentEncoded: false)
        let items = model.index.notes.values.map { rec -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = rec.path.noteName
            attrs.contentDescription = String(rec.text.prefix(300))
            attrs.keywords = rec.parsed.tags + rec.parsed.aliases
            attrs.contentModificationDate = rec.modified
            return CSSearchableItem(uniqueIdentifier: rec.path, domainIdentifier: domain, attributeSet: attrs)
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            index.indexSearchableItems(items)
        }
    }
}
