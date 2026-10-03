import SwiftUI
import NetheriteCore

/// Netherite › Accessibility: reading and vision preferences for this device (UserDefaults, not per vault).
@MainActor @Observable
final class A11y {
    static let shared = A11y()

    enum EditorFont: String, CaseIterable {
        case system, serif, rounded, monospaced
        /// CSS generic family stored in the theme; `EditorStyler` maps it to the matching system design.
        var family: String? { self == .system ? nil : "ui-" + (self == .monospaced ? "monospace" : rawValue) }
    }

    /// Default editor line height (`EditorStyler`), kept out of the theme unless changed.
    static let defaultLineSpacing = 1.25

    private static let d = UserDefaults.standard
    var useSystemTextSize: Bool { didSet { Self.d.set(useSystemTextSize, forKey: "a11y.systemTextSize") } }
    /// Index into `DynamicTypeSize.allCases`, used when not following the system.
    var textSizeIndex: Int { didSet { Self.d.set(textSizeIndex, forKey: "a11y.textSize") } }
    var editorFont: EditorFont { didSet { Self.d.set(editorFont.rawValue, forKey: "a11y.editorFont") } }
    var editorScale: Double { didSet { Self.d.set(editorScale, forKey: "a11y.editorScale") } }
    var lineSpacing: Double { didSet { Self.d.set(lineSpacing, forKey: "a11y.lineSpacing") } }
    var increaseContrast: Bool { didSet { Self.d.set(increaseContrast, forKey: "a11y.increaseContrast") } }
    var colorVision: ColorVision { didSet { Self.d.set(colorVision.rawValue, forKey: "a11y.colorVision") } }
    var reduceMotion: Bool { didSet { Self.d.set(reduceMotion, forKey: "a11y.reduceMotion") } }
    /// The system's Increase Contrast, mirrored from the environment by `accessibilityRoot`.
    var systemIncreaseContrast = false

    private init() {
        let d = Self.d
        useSystemTextSize = d.object(forKey: "a11y.systemTextSize") as? Bool ?? true
        textSizeIndex = d.object(forKey: "a11y.textSize") as? Int ?? 3
        editorFont = d.string(forKey: "a11y.editorFont").flatMap(EditorFont.init) ?? .system
        editorScale = d.object(forKey: "a11y.editorScale") as? Double ?? 1
        lineSpacing = d.object(forKey: "a11y.lineSpacing") as? Double ?? Self.defaultLineSpacing
        increaseContrast = d.bool(forKey: "a11y.increaseContrast")
        colorVision = d.string(forKey: "a11y.colorVision").flatMap(ColorVision.init) ?? .none
        reduceMotion = d.bool(forKey: "a11y.reduceMotion")
    }

    var textSize: DynamicTypeSize {
        DynamicTypeSize.allCases[min(max(textSizeIndex, 0), DynamicTypeSize.allCases.count - 1)]
    }

    var highContrast: Bool { increaseContrast || systemIncreaseContrast }

    /// The theme as the app should draw it: contrast and color-vision adjustments plus the editor reading options.
    func apply(_ theme: Theme) -> Theme {
        var t = theme.accessible(increaseContrast: highContrast, vision: colorVision)
        if let f = editorFont.family { t.textFont = f }
        if editorScale != 1 { t.fontScale = (t.fontScale ?? 1) * editorScale }
        if lineSpacing != Self.defaultLineSpacing { t.lineHeight = lineSpacing }
        return t
    }

    /// Color-blind-safe stand-in for a semantic hue, or `fallback` when colors aren't remapped.
    func color(_ hue: ColorVision.Hue, _ fallback: Color) -> Color {
        colorVision.color(hue).map { Color(pair: .init($0, $0), fallback: fallback) } ?? fallback
    }
}

extension DynamicTypeSize {
    /// Body text size relative to the default (Large), from the iOS type ramp; scales text the app sizes itself.
    var bodyScale: Double {
        let body: [Double] = [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]
        return body[min(DynamicTypeSize.allCases.firstIndex(of: self) ?? 3, body.count - 1)] / 17
    }
}

extension Theme.Appearance {
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

/// Applies the Accessibility preferences, and a theme's forced appearance, to a window's content.
private struct AccessibilityRoot: ViewModifier {
    var appearance: Theme.Appearance?
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiate

    func body(content: Content) -> some View {
        let a = A11y.shared
        let reduceMotion = a.reduceMotion || systemReduceMotion
        content
            .dynamicTypeSize(a.useSystemTextSize ? .xSmall ... .accessibility5 : a.textSize ... a.textSize)
            // Views already read these environment values; the app's own toggles feed into them here.
            .environment(\._colorSchemeContrast, a.increaseContrast ? .increased : contrast)
            .environment(\._accessibilityReduceMotion, reduceMotion)
            .environment(\._accessibilityDifferentiateWithoutColor, systemDifferentiate || a.colorVision != .none)
            .transaction { if reduceMotion { $0.disablesAnimations = true; $0.animation = nil } }
            .preferredColorScheme(appearance?.colorScheme)
            .onChange(of: contrast, initial: true) { a.systemIncreaseContrast = contrast == .increased }
    }
}

extension View {
    /// Root of every window and sheet: text size, contrast, motion and color-vision preferences.
    func accessibilityRoot(appearance: Theme.Appearance? = nil) -> some View {
        modifier(AccessibilityRoot(appearance: appearance))
    }
}
