import SwiftUI
import NetheriteCore

/// Vault › Appearance: the vault's theme, picked from a gallery of tones plus a light/dark mode.
struct AppearanceSettingsView: View {
    @Bindable var model: VaultModel
    @State private var themeError: String?

    private var current: Theme { model.vaultTheme }

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 12)], spacing: 12) {
                    ForEach(Theme.tones) { tone in
                        ThemeCard(theme: tone, appearance: current.isBuiltIn ? current.appearance : nil, selected: current.tone == tone.name) {
                            // Keep the mode when switching tones.
                            model.settings.theme = tone.variant(current.isBuiltIn ? current.appearance : nil).name
                        }
                    }
                }
                .padding(.vertical, 4)
                if current.isBuiltIn {
                    Picker("Mode", selection: Binding(get: { current.appearance }, set: { model.settings.theme = current.variant($0).name })) {
                        Text("Automatic").tag(Theme.Appearance?.none)
                        Text("Light").tag(Theme.Appearance?.some(.light))
                        Text("Dark").tag(Theme.Appearance?.some(.dark))
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Theme")
            } footer: {
                if current.isBuiltIn {
                    Text("Automatic follows the system appearance. Light and Dark always use that appearance in this vault.")
                }
            }

            Section {
                ForEach(model.themes.filter { !$0.isBuiltIn }) { theme in
                    Button { model.settings.theme = theme.name } label: {
                        HStack {
                            ThemeSwatches(theme: theme)
                            Text(theme.name).foregroundStyle(.primary)
                            Spacer()
                            if theme.name == current.name {
                                Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(theme.name)
                    .accessibilityAddTraits(theme.name == current.name ? [.isButton, .isSelected] : .isButton)
                }
                Button("Create Theme from Current…") { createThemeFile() }
            } header: {
                Text("Custom Themes")
            } footer: {
                Text("Custom themes are JSON files in \(Text(verbatim: ".netherite/themes").monospaced()).")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Appearance")
        .alert("Couldn't Create Theme", isPresented: Binding(get: { themeError != nil }, set: { if !$0 { themeError = nil } })) {
            Button("OK") {}
        } message: { Text(themeError ?? "") }
    }

    private func createThemeFile() {
        var t = model.vaultTheme
        t.name = String(localized: "\(t.displayName) Custom")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try enc.encode(t)
            try FileManager.default.createDirectory(at: model.vault.themesURL, withIntermediateDirectories: true)
            try data.write(to: model.vault.themesURL.appending(path: "\(t.name).json"))
            model.reloadThemes()
            model.settings.theme = t.name
        } catch {
            themeError = error.localizedDescription
        }
    }
}

/// A tone in the gallery: a miniature note in its colors, drawn in the selected mode.
private struct ThemeCard: View {
    let theme: Theme
    let appearance: Theme.Appearance?
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .environment(\.colorScheme, appearance?.colorScheme ?? colorScheme)
                    .frame(height: 64)
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: selected ? 3 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .tint)
                                .padding(5)
                        }
                    }
                Text(theme.displayName)
                    .font(.callout)
                    .fontWeight(selected ? .semibold : .regular)
                    .multilineTextAlignment(.center)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var preview: some View {
        let accent = Color(pair: theme.accent, fallback: .accentColor)
        return ZStack(alignment: .topLeading) {
            Color(pair: theme.background, fallback: Color(PlatformColor.textBackground))
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(.primary.opacity(0.75)).frame(width: 44, height: 6)
                Capsule().fill(Color(pair: theme.link, fallback: accent)).frame(width: 64, height: 4)
                HStack(spacing: 4) {
                    Capsule().fill(accent).frame(width: 24, height: 9)
                    Capsule().fill(Color(pair: theme.tag, fallback: accent).opacity(0.3)).frame(width: 28, height: 9)
                }
                Capsule().fill(Color(pair: theme.highlight, fallback: .yellow.opacity(0.4))).frame(width: 40, height: 5)
            }
            .padding(10)
        }
    }
}

/// Accent, link and background dots for a custom theme row.
private struct ThemeSwatches: View {
    let theme: Theme
    var body: some View {
        let colors = [Color(pair: theme.background, fallback: Color(PlatformColor.textBackground)),
                      Color(pair: theme.accent, fallback: .accentColor), Color(pair: theme.link, fallback: .accentColor)]
        HStack(spacing: -4) {
            ForEach(colors.indices, id: \.self) { i in
                Circle().fill(colors[i]).overlay(Circle().strokeBorder(.separator)).frame(width: 16, height: 16)
            }
        }
        .accessibilityHidden(true)
    }
}
