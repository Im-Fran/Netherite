import SwiftUI
import NetheriteCore

/// Vault › Plugins: which optional features this vault uses, and their options.
struct PluginsSettingsView: View {
    @Bindable var model: VaultModel

    var body: some View {
        Form {
            Section {
                ForEach(CorePlugin.allCases) { p in
                    Toggle(isOn: Binding(get: { model.settings.isEnabled(p) }, set: { model.settings.setEnabled(p, $0) })) {
                        Label {
                            Text(p.title)
                            Text(p.summary)
                        } icon: {
                            PluginIcon(plugin: p)
                        }
                    }
                }
            } header: {
                Text("Core Plugins")
            } footer: {
                Text("Turned-off plugins disappear from the command palette and menus. Your notes are never changed.")
            }
            Section("Options") {
                if model.settings.isEnabled(.dailyNotes) {
                    NavigationLink { VaultSettingsForm(model: model, page: .dailyNotes) } label: { optionLabel(.dailyNotes) }
                }
                if model.settings.isEnabled(.templates) || model.settings.isEnabled(.uniqueNote) {
                    NavigationLink { VaultSettingsForm(model: model, page: .templates) } label: { optionLabel(.templates) }
                }
                if model.settings.isEnabled(.meetingNotes) {
                    NavigationLink { MeetingNotesSettings(model: model) } label: { optionLabel(.meetingNotes) }
                }
                if model.settings.isEnabled(.fileRecovery) {
                    NavigationLink { VaultSettingsForm(model: model, page: .recovery) } label: { optionLabel(.fileRecovery) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Plugins")
    }

    private func optionLabel(_ p: CorePlugin) -> some View {
        Label { Text(p.title) } icon: { PluginIcon(plugin: p) }
    }
}

private struct PluginIcon: View {
    let plugin: CorePlugin
    @ScaledMetric private var size = 28.0

    var body: some View {
        Image(systemName: plugin.symbol)
            .font(.system(size: size * 0.55))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(plugin.tint.gradient, in: .rect(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Plugins › Meeting notes.
struct MeetingNotesSettings: View {
    @Bindable var model: VaultModel
    @State private var created: String?

    var body: some View {
        Form {
            Section {
                VaultFolderPicker(label: "Folder", selection: $model.settings.meetingNotes.folder, folders: model.index.folders)
                field("Date Format", $model.settings.meetingNotes.format)
                Text("Example: \(Templates.meetingNoteName(title: String(localized: "Kickoff"), date: .now, settings: model.settings))")
                    .font(.caption).foregroundStyle(.secondary)
                field("Template File", $model.settings.meetingNotes.template)
            } footer: {
                Text("Leave the template empty to use the built-in layout. Templates can use {{title}}, {{date}}, {{time}} and {{attendees}}.")
            }
            if model.settings.isEnabled(.bases) {
                Section {
                    Button("Create Meetings Database", systemImage: "tablecells") { created = model.newMeetingsBase() }
                } footer: {
                    if let created { Text("Created “\(created)”.") } else {
                        Text("Adds a base listing your meetings with their date and attendees.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Meeting Notes")
    }

    /// On iOS a filled text field hides its placeholder, so show the label beside it.
    @ViewBuilder private func field(_ label: LocalizedStringKey, _ text: Binding<String>) -> some View {
        #if os(iOS)
        LabeledContent(label) { TextField(label, text: text).multilineTextAlignment(.trailing) }
        #else
        TextField(label, text: text)
        #endif
    }
}

/// Writes the built-in templates into the templates folder, skipping names already there.
struct AddBuiltInTemplatesButton: View {
    let model: VaultModel
    @State private var added: Int?

    var body: some View {
        Section {
            Button("Add Built-in Templates to Folder", systemImage: "square.and.arrow.down.on.square") { added = model.addTemplates() }
            NavigationLink { TemplateGalleryView(model: model) } label: {
                Label("Browse Template Gallery", systemImage: "square.grid.2x2")
            }
        } footer: {
            if let added { Text("Added \(added) templates.") } else if model.settings.templatesFolder.isEmpty {
                Text("Choose a templates folder to enable these.")
            } else {
                Text("Meeting, daily journal, weekly review, project, book notes, to-do list and decision record. Existing files are kept.")
            }
        }
        .disabled(model.settings.templatesFolder.isEmpty)
    }
}

extension CorePlugin {
    var title: LocalizedStringKey {
        switch self {
        case .dailyNotes: "Daily Notes"
        case .uniqueNote: "Unique Note Creator"
        case .templates: "Templates"
        case .meetingNotes: "Meeting Notes"
        case .bases: "Databases"
        case .canvas: "Canvas"
        case .slides: "Slides"
        case .audioRecorder: "Audio Recorder"
        case .webViewer: "Web Viewer"
        case .workspaces: "Workspaces"
        case .publish: "Publish"
        case .noteComposer: "Note Composer"
        case .randomNote: "Random Note"
        case .fileRecovery: "File Recovery"
        case .graph: "Graph View"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .dailyNotes: "Open a note for today, named by its date."
        case .uniqueNote: "Create notes named with a timestamp."
        case .templates: "Insert templates or start new notes from one."
        case .meetingNotes: "Create meeting notes with attendees, agenda and action items."
        case .bases: "Show notes as tables, cards and boards you can edit."
        case .canvas: "Arrange notes, images and links on an infinite board."
        case .slides: "Present a note as slides, split by ---."
        case .audioRecorder: "Record audio and embed it in the current note."
        case .webViewer: "Open web pages in a pane."
        case .workspaces: "Save and restore layouts of open panes."
        case .publish: "Export the vault as a website."
        case .noteComposer: "Merge notes, or extract a selection into a new note."
        case .randomNote: "Open a random note."
        case .fileRecovery: "Keep snapshots of notes to restore earlier versions."
        case .graph: "See how your notes link to each other."
        }
    }

    var symbol: String {
        switch self {
        case .dailyNotes: "calendar"
        case .uniqueNote: "number.square"
        case .templates: "doc.on.doc"
        case .meetingNotes: "person.2"
        case .bases: "tablecells"
        case .canvas: "rectangle.3.group"
        case .slides: "play.rectangle"
        case .audioRecorder: "mic"
        case .webViewer: "globe"
        case .workspaces: "rectangle.3.offgrid"
        case .publish: "paperplane"
        case .noteComposer: "arrow.triangle.merge"
        case .randomNote: "shuffle"
        case .fileRecovery: "clock.arrow.circlepath"
        case .graph: "point.3.connected.trianglepath.dotted"
        }
    }

    var tint: Color {
        switch self {
        case .dailyNotes, .audioRecorder: .red
        case .uniqueNote: .gray
        case .templates, .slides: .orange
        case .meetingNotes: .teal
        case .bases, .fileRecovery: .green
        case .canvas, .graph: .purple
        case .webViewer: .blue
        case .workspaces: .indigo
        case .publish: .cyan
        case .noteComposer: .brown
        case .randomNote: .mint
        }
    }
}
