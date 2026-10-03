import SwiftUI
import TipKit

/// Feature-discovery tips. Each shows only while its feature hasn't been used yet, and is
/// invalidated the first time the person uses it (so it never nags).
enum NetheriteTips {
    // Events donated from the places where features are used.
    nonisolated static let noteOpened = Tips.Event(id: "noteOpened")
    nonisolated static let quickSwitcherUsed = Tips.Event(id: "quickSwitcherUsed")
    nonisolated static let commandPaletteUsed = Tips.Event(id: "commandPaletteUsed")
    nonisolated static let linkInserted = Tips.Event(id: "linkInserted")
    nonisolated static let slashUsed = Tips.Event(id: "slashUsed")
    nonisolated static let readingToggled = Tips.Event(id: "readingToggled")
    nonisolated static let searchUsed = Tips.Event(id: "searchUsed")
    nonisolated static let graphOpened = Tips.Event(id: "graphOpened")
    nonisolated static let inspectorUsed = Tips.Event(id: "inspectorUsed")
    nonisolated static let bookmarkAdded = Tips.Event(id: "bookmarkAdded")
    nonisolated static let dailyOpened = Tips.Event(id: "dailyOpened")
    nonisolated static let canvasCardAdded = Tips.Event(id: "canvasCardAdded")
    nonisolated static let baseEdited = Tips.Event(id: "baseEdited")
    nonisolated static let graphInteracted = Tips.Event(id: "graphInteracted")

    /// Tips wait until the welcome tour is finished.
    nonisolated static let onboardingFinished = Tips.Event(id: "onboardingFinished")

    /// Loads the tip store once at launch.
    static func configure() {
        if UserDefaults.standard.bool(forKey: "resetTipsOnLaunch") {
            try? Tips.resetDatastore()
            UserDefaults.standard.set(false, forKey: "resetTipsOnLaunch")
        }
        // Toolbar and editor tips are grouped (one at a time each) and section tips have display caps,
        // so at most one tip per area is on screen.
        try? Tips.configure([.displayFrequency(.immediate), .datastoreLocation(.applicationDefault)])
        if UserDefaults.standard.bool(forKey: "hasSeenOnboarding") { donate(onboardingFinished) }
    }

    /// Donates an event without blocking the caller.
    static func donate(_ event: Tips.Event<Tips.EmptyDonation>) {
        Task { await event.donate() }
    }
}

// MARK: Tips

nonisolated struct QuickSwitcherTip: Tip {
    var title: Text { Text("Jump to Any Note") }
    var message: Text? {
        #if os(macOS)
        Text("Find and open notes by name — or create one — without leaving the keyboard. Press ⌘O.")
        #else
        Text("Find and open notes by name, or create one, right from here.")
        #endif
    }
    var image: Image? { Image(systemName: "magnifyingglass") }
    var rules: [Rule] {
        #Rule(NetheriteTips.onboardingFinished) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.noteOpened) { $0.donations.count >= 2 }
        #Rule(NetheriteTips.quickSwitcherUsed) { $0.donations.count == 0 }
    }
    var options: [any TipOption] { [MaxDisplayCount(2)] }
}

nonisolated struct CommandPaletteTip: Tip {
    var title: Text { Text("Every Action, One Shortcut") }
    var message: Text? {
        #if os(macOS)
        Text("The command palette finds any action by name, from formatting to publishing. Press ⌘P.")
        #else
        Text("The command palette finds any action by name, from formatting to publishing.")
        #endif
    }
    var image: Image? { Image(systemName: "command") }
    var rules: [Rule] {
        #Rule(NetheriteTips.onboardingFinished) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.noteOpened) { $0.donations.count >= 4 }
        #Rule(NetheriteTips.commandPaletteUsed) { $0.donations.count == 0 }
    }
    var options: [any TipOption] { [MaxDisplayCount(2)] }
}

nonisolated struct LinkTip: Tip {
    var title: Text { Text("Link Your Notes") }
    var message: Text? { Text("Type [[ to link to another note. Links build your knowledge graph and show up as backlinks.") }
    var image: Image? { Image(systemName: "link") }
    var rules: [Rule] {
        #Rule(NetheriteTips.onboardingFinished) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.noteOpened) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.linkInserted) { $0.donations.count == 0 }
    }
}

nonisolated struct SlashCommandTip: Tip {
    var title: Text { Text("Insert Anything with /") }
    var message: Text? { Text("Type / at the start of a line for headings, tasks, tables, callouts, math and templates.") }
    var image: Image? { Image(systemName: "slash.circle") }
    var rules: [Rule] {
        #Rule(NetheriteTips.onboardingFinished) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.linkInserted) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.slashUsed) { $0.donations.count == 0 }
    }
}

nonisolated struct ReadingViewTip: Tip {
    var title: Text { Text("Reading View") }
    var message: Text? {
        #if os(macOS)
        Text("See the note fully rendered, with interactive tasks and embeds. Press ⌘E to switch.")
        #else
        Text("See the note fully rendered, with interactive tasks and embeds.")
        #endif
    }
    var image: Image? { Image(systemName: "book") }
    var rules: [Rule] {
        #Rule(NetheriteTips.onboardingFinished) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.noteOpened) { $0.donations.count >= 3 }
        #Rule(NetheriteTips.readingToggled) { $0.donations.count == 0 }
    }
    var options: [any TipOption] { [MaxDisplayCount(2)] }
}

nonisolated struct BacklinksTip: Tip {
    var title: Text { Text("See What Links Here") }
    var message: Text? { Text("Show backlinks, outgoing links, the outline and properties of the current note.") }
    var image: Image? { Image(systemName: "sidebar.right") }
    var rules: [Rule] {
        #Rule(NetheriteTips.onboardingFinished) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.noteOpened) { $0.donations.count >= 2 }
        #Rule(NetheriteTips.inspectorUsed) { $0.donations.count == 0 }
    }
    var options: [any TipOption] { [MaxDisplayCount(2)] }
}

nonisolated struct GraphTip: Tip {
    var title: Text { Text("Explore the Graph") }
    var message: Text? { Text("Open the graph view from this menu to see how your notes connect, or a local graph for just this note.") }
    var image: Image? { Image(systemName: "point.3.connected.trianglepath.dotted") }
    var rules: [Rule] {
        #Rule(NetheriteTips.onboardingFinished) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.linkInserted) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.graphOpened) { $0.donations.count == 0 }
    }
    var options: [any TipOption] { [MaxDisplayCount(2)] }
}

nonisolated struct SearchTip: Tip {
    var title: Text { Text("Search Like a Pro") }
    var message: Text? { Text("Combine words with operators such as tag:, path:, \"exact phrase\" and [property:value].") }
    var image: Image? { Image(systemName: "text.magnifyingglass") }
    var rules: [Rule] {
        #Rule(NetheriteTips.onboardingFinished) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.searchUsed) { $0.donations.count == 0 }
    }
    var options: [any TipOption] { [MaxDisplayCount(3)] }
}

nonisolated struct BookmarksTip: Tip {
    var title: Text { Text("Keep Favorites Close") }
    var message: Text? { Text("Bookmark notes, headings and searches from the ⋯ menu to find them here.") }
    var image: Image? { Image(systemName: "bookmark") }
    var rules: [Rule] {
        #Rule(NetheriteTips.onboardingFinished) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.bookmarkAdded) { $0.donations.count == 0 }
    }
    var options: [any TipOption] { [MaxDisplayCount(3)] }
}

nonisolated struct DailyNoteTip: Tip {
    var title: Text { Text("Today's Note") }
    var message: Text? {
        #if os(macOS)
        Text("One note per day for journaling and quick capture. Press ⇧⌘D anytime.")
        #else
        Text("One note per day for journaling and quick capture.")
        #endif
    }
    var image: Image? { Image(systemName: "calendar") }
    var rules: [Rule] {
        #Rule(NetheriteTips.onboardingFinished) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.noteOpened) { $0.donations.count >= 5 }
        #Rule(NetheriteTips.dailyOpened) { $0.donations.count == 0 }
    }
    var options: [any TipOption] { [MaxDisplayCount(2)] }
}

nonisolated struct CanvasTip: Tip {
    var title: Text { Text("Think on a Canvas") }
    var message: Text? { Text("Double-click (or double-tap) empty space to add a card. Drag the dots on a card's edge to connect it.") }
    var image: Image? { Image(systemName: "rectangle.3.group") }
    var rules: [Rule] {
        #Rule(NetheriteTips.onboardingFinished) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.canvasCardAdded) { $0.donations.count == 0 }
    }
    var options: [any TipOption] { [MaxDisplayCount(3)] }
}

nonisolated struct BasesTip: Tip {
    var title: Text { Text("Your Notes as a Database") }
    var message: Text? { Text("Filter, sort and edit notes by their properties. Switch between table, cards and list views.") }
    var image: Image? { Image(systemName: "tablecells") }
    var rules: [Rule] {
        #Rule(NetheriteTips.onboardingFinished) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.baseEdited) { $0.donations.count == 0 }
    }
    var options: [any TipOption] { [MaxDisplayCount(3)] }
}

nonisolated struct GraphControlsTip: Tip {
    var title: Text { Text("Move Around the Graph") }
    var message: Text? { Text("Drag to pan, pinch to zoom, and select a note to open it. Filters and forces are in these settings.") }
    var image: Image? { Image(systemName: "slider.horizontal.3") }
    var rules: [Rule] {
        #Rule(NetheriteTips.onboardingFinished) { $0.donations.count >= 1 }
        #Rule(NetheriteTips.graphInteracted) { $0.donations.count == 0 }
    }
    var options: [any TipOption] { [MaxDisplayCount(3)] }
}
