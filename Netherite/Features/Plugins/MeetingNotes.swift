import SwiftUI
import NetheriteCore

/// Meeting notes › New meeting note: title, date and attendees, optionally starting the audio recorder.
struct MeetingNoteSheet: View {
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = Date.now
    @State private var attendees = ""
    @State private var record = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    DatePicker("Date", selection: $date)
                }
                Section {
                    TextField("Attendees", text: $attendees, prompt: Text("Names, separated by commas"), axis: .vertical)
                        .autocorrectionDisabled()
                    let names = Templates.attendees(from: attendees)
                    if !names.isEmpty {
                        Text(names.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                            .accessibilityLabel(Text("\(names.count) attendees"))
                    }
                }
                if window.model.settings.isEnabled(.audioRecorder) {
                    Toggle("Start Audio Recording", isOn: $record)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Meeting Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: create) }
            }
        }
        .macOnly { $0.frame(minWidth: 420, minHeight: 320) }
    }

    private func create() {
        window.newMeetingNote(title: title, date: date, attendees: Templates.attendees(from: attendees))
        // Replacing the sheet presents the recorder, which embeds the recording in the new (current) note.
        if record { window.sheet = .audio } else { dismiss() }
    }
}
