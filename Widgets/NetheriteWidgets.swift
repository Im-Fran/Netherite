import WidgetKit
import SwiftUI
import AppIntents
import NetheriteCore

@main
struct NetheriteWidgets: WidgetBundle {
    var body: some Widget {
        DailyNoteWidget()
        RecentNotesWidget()
        #if os(iOS)
        NewNoteControl()
        #endif
    }
}

// MARK: Data

struct VaultEntry: TimelineEntry {
    var date: Date
    var vaultName: String?
    var dailyTitle: String
    var dailyExcerpt: String
    var recents: [String]
}

struct VaultProvider: TimelineProvider {
    func placeholder(in context: Context) -> VaultEntry {
        VaultEntry(date: .now, vaultName: "Vault", dailyTitle: Templates.format(.now, "yyyy-MM-dd"),
                   dailyExcerpt: String(localized: "Today's thoughts…"), recents: ["Welcome.md", "Ideas.md", "Projects/Trip.md"])
    }

    func getSnapshot(in context: Context, completion: @escaping (VaultEntry) -> Void) { completion(entry()) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VaultEntry>) -> Void) {
        // The app reloads timelines after saving; also refresh at midnight for the new daily note.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        completion(Timeline(entries: [entry()], policy: .after(midnight)))
    }

    private func entry() -> VaultEntry {
        let shared = SharedVault.current()
        guard let vault = shared?.resolve() else {
            return VaultEntry(date: .now, vaultName: nil, dailyTitle: "", dailyExcerpt: "", recents: [])
        }
        let daily = Templates.dailyNotePath(for: .now, settings: vault.settings)
        let recents = SharedVault.recents().filter(vault.exists)
        return VaultEntry(date: .now, vaultName: shared?.name, dailyTitle: daily.noteName,
                          dailyExcerpt: vault.excerpt(daily, length: 400),
                          recents: recents.isEmpty ? vault.searchTitles("", limit: 8) : recents)
    }
}

private func openURL(_ path: String) -> URL {
    SharedVault.openURL(path: path)
}

private struct NoVaultView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "diamond").font(.title2).foregroundStyle(.tint).widgetAccentable()
            Text("Open a vault in Netherite").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }
}

// MARK: Daily note

struct DailyNoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyNote", provider: VaultProvider()) { entry in
            DailyNoteView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "netherite://daily"))
        }
        .configurationDisplayName("Daily Note")
        .description("Today's daily note at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct DailyNoteView: View {
    let entry: VaultEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.vaultName == nil {
            NoVaultView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Today", systemImage: "calendar").font(.caption.bold()).foregroundStyle(.tint).widgetAccentable()
                    Spacer()
                    if family != .systemSmall {
                        // Quick capture: logs the current time as a new bullet in today's note.
                        Button(intent: LogTimeIntent()) {
                            Label("Log Time", systemImage: "plus")
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                }
                Text(entry.dailyTitle).font(.headline).lineLimit(1)
                Text(entry.dailyExcerpt.isEmpty ? String(localized: "Nothing written yet today.") : entry.dailyExcerpt)
                    .font(.caption)
                    .foregroundStyle(entry.dailyExcerpt.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

// MARK: Recent notes

struct RecentNotesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentNotes", provider: VaultProvider()) { entry in
            RecentNotesView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                // Small widgets are a single tap target and ignore Link: open the most recent note.
                .widgetURL(entry.recents.first.map(openURL))
        }
        .configurationDisplayName("Recent Notes")
        .description("Jump back into the notes you opened last.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RecentNotesView: View {
    let entry: VaultEntry
    @Environment(\.widgetFamily) private var family

    private var limit: Int {
        switch family {
        case .systemSmall: 3
        case .systemLarge: 8
        default: 4
        }
    }

    var body: some View {
        if entry.vaultName == nil {
            NoVaultView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label(entry.vaultName ?? "", systemImage: "clock").font(.caption.bold()).foregroundStyle(.tint).lineLimit(1).widgetAccentable()
                ForEach(entry.recents.prefix(limit), id: \.self) { path in
                    Link(destination: openURL(path)) {
                        Label(path.noteName, systemImage: "doc.text").font(.subheadline).lineLimit(1)
                    }
                }
                if entry.recents.isEmpty { Text("No notes yet").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Control Center

#if os(iOS)
struct NewNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "cl.franciscosolis.netherite.newnote") {
            ControlWidgetButton(action: NewNoteIntent()) {
                Label("New Note", systemImage: "square.and.pencil")
            }
        }
        .displayName("New Note")
        .description("Opens Netherite with a new note.")
    }
}
#endif
