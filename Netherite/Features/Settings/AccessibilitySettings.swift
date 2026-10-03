import SwiftUI
import NetheriteCore

/// Netherite › Accessibility: app-wide reading and vision preferences for this device.
struct AccessibilitySettingsView: View {
    @Bindable private var a11y = A11y.shared
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Form {
            Section {
                Toggle("Use System Text Size", isOn: $a11y.useSystemTextSize)
                if !a11y.useSystemTextSize {
                    Slider(value: Binding(get: { Double(a11y.textSizeIndex) }, set: { a11y.textSizeIndex = Int($0.rounded()) }),
                           in: 0...Double(DynamicTypeSize.allCases.count - 1), step: 1) {
                        Text("Text Size")
                    } minimumValueLabel: {
                        Image(systemName: "textformat.size.smaller").accessibilityHidden(true)
                    } maximumValueLabel: {
                        Image(systemName: "textformat.size.larger").accessibilityHidden(true)
                    }
                    .accessibilityValue(Text(a11y.textSize.bodyScale, format: .percent.precision(.fractionLength(0))))
                }
            } header: {
                Text("Text Size")
            } footer: {
                Text("Sets the size of text in Netherite only, including the larger accessibility sizes.")
            }

            Section {
                Picker("Font", selection: $a11y.editorFont) {
                    ForEach(A11y.EditorFont.allCases, id: \.self) { f in
                        Text(f.title).fontDesign(f.design).tag(f)
                    }
                }
                percentSlider("Font Size", value: $a11y.editorScale, in: 0.8...2, step: 0.05)
                LabeledContent {
                    Slider(value: $a11y.lineSpacing, in: 1...2, step: 0.05) { Text("Line Spacing") }
                        .accessibilityValue(Text(a11y.lineSpacing, format: .number.precision(.fractionLength(2))))
                } label: {
                    Text("Line Spacing")
                    Text(a11y.lineSpacing, format: .number.precision(.fractionLength(2))).monospacedDigit()
                }
                // Sample at the editor's size: platform body size × Text Size × Font Size.
                let size = 17 * typeSize.bodyScale * a11y.editorScale
                Text("Notes are plain Markdown files you can open anywhere. Pick what’s most comfortable to read.")
                    .font(.system(size: size, design: a11y.editorFont.design))
                    .lineSpacing((a11y.lineSpacing - 1) * size)
            } header: {
                Text("Editor and Reading View")
            }

            Section {
                Toggle("Increase Contrast", isOn: $a11y.increaseContrast)
            } footer: {
                Text("Darkens links, tags and borders. Netherite also follows Increase Contrast in your device’s Accessibility settings.")
            }

            Section {
                Picker("Color Vision", selection: $a11y.colorVision) {
                    ForEach(ColorVision.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Replaces theme, callout, canvas, graph and sync colors with ones that stay distinguishable, and adds shapes where color alone tells things apart.")
            }

            Section {
                Toggle("Reduce Motion", isOn: $a11y.reduceMotion)
            } footer: {
                Text("Turns off animations in Netherite. It’s always on when Reduce Motion is on for your device.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Accessibility")
    }

    private func percentSlider(_ title: LocalizedStringKey, value: Binding<Double>, in range: ClosedRange<Double>, step: Double) -> some View {
        LabeledContent {
            Slider(value: value, in: range, step: step) { Text(title) }
                .accessibilityValue(Text(value.wrappedValue, format: .percent.precision(.fractionLength(0))))
        } label: {
            Text(title)
            Text(value.wrappedValue, format: .percent.precision(.fractionLength(0))).monospacedDigit()
        }
    }
}

private extension A11y.EditorFont {
    var title: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .serif: "Serif"
        case .rounded: "Rounded"
        case .monospaced: "Monospaced"
        }
    }

    var design: Font.Design {
        switch self {
        case .system: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }
}

private extension ColorVision {
    var title: LocalizedStringKey {
        switch self {
        case .none: "Off"
        case .protanopia: "Red/Green (Protanopia)"
        case .deuteranopia: "Green/Red (Deuteranopia)"
        case .tritanopia: "Blue/Yellow (Tritanopia)"
        case .grayscale: "Grayscale-Safe"
        }
    }
}
