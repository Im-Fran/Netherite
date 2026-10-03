import Foundation

/// Optional features a vault can turn off (Settings › Plugins). Raw values match Obsidian's core plugin ids.
public enum CorePlugin: String, CaseIterable, Sendable, Identifiable {
    case dailyNotes = "daily-notes"
    case uniqueNote = "zk-prefixer"
    case templates
    case meetingNotes = "meeting-notes"
    case bases
    case canvas
    case slides
    case audioRecorder = "audio-recorder"
    case webViewer = "webviewer"
    case workspaces
    case publish
    case noteComposer = "note-composer"
    case randomNote = "random-note"
    case fileRecovery = "file-recovery"
    case graph

    public var id: String { rawValue }
}

public extension VaultSettings {
    /// Every plugin is on unless the vault turned it off.
    func isEnabled(_ plugin: CorePlugin) -> Bool { !disabledPlugins.contains(plugin.rawValue) }

    mutating func setEnabled(_ plugin: CorePlugin, _ on: Bool) {
        if on { disabledPlugins.remove(plugin.rawValue) } else { disabledPlugins.insert(plugin.rawValue) }
    }
}
