import SwiftUI
import NetheriteCore

/// Netherite › Accessibility: app-wide reading and vision preferences for this device.
struct AccessibilitySettingsView: View {
    var body: some View {
        Form {
            Section {
                Text("Netherite follows the text size, contrast and motion settings of your device.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Accessibility")
    }
}
