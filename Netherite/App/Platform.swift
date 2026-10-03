import SwiftUI
import NetheriteCore

#if os(macOS)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformFontDescriptor = NSFontDescriptor
#else
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformFontDescriptor = UIFontDescriptor
#endif

extension PlatformColor {
    nonisolated convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let a = s.count == 8 ? CGFloat(v & 0xFF) / 255 : 1
        let rgb = s.count == 8 ? v >> 8 : v
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: a)
    }

    /// Dynamic color from a theme pair (light/dark).
    /// nonisolated: SwiftUI resolves dynamic colors off the main thread, and a main-actor provider traps there.
    nonisolated static func pair(_ p: Theme.Pair?, fallback: PlatformColor) -> PlatformColor {
        guard let p, let light = PlatformColor(hex: p.light), let dark = PlatformColor(hex: p.dark) else { return fallback }
        #if os(macOS)
        return NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua]) != nil ? dark : light }
        #else
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
        #endif
    }

    #if os(macOS)
    static var label: NSColor { .labelColor }
    static var secondaryLabel: NSColor { .secondaryLabelColor }
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }
    static var quaternaryFill: NSColor { .quaternaryLabelColor.withAlphaComponent(0.08) }
    static var codeBackground: NSColor { .quaternaryLabelColor.withAlphaComponent(0.12) }
    static var accent: NSColor { .controlAccentColor }
    #else
    static var quaternaryFill: UIColor { .quaternarySystemFill }
    static var codeBackground: UIColor { .tertiarySystemFill }
    static var accent: UIColor { .tintColor }
    #endif
}

extension Color {
    init(pair: Theme.Pair?, fallback: Color) {
        #if os(macOS)
        self = pair.map { Color(nsColor: .pair($0, fallback: .labelColor)) } ?? fallback
        #else
        self = pair.map { Color(uiColor: .pair($0, fallback: .label)) } ?? fallback
        #endif
    }
}

/// SF Symbol for a vault file, used in the explorer, switcher and tabs.
func symbol(for path: String, isFolder: Bool = false) -> String {
    if isFolder { return "folder" }
    switch path.fileExtension {
    case "md": return "doc.text"
    case "canvas": return "rectangle.3.group"
    case "base": return "tablecells"
    case "png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "bmp": return "photo"
    case "pdf": return "doc.richtext"
    case "m4a", "mp3", "wav", "ogg", "flac", "aac", "webm", "3gp": return "waveform"
    case "mp4", "mov", "mkv", "ogv": return "film"
    default: return "doc"
    }
}

extension View {
    /// Applies a modifier only on macOS / iOS without #if noise at call sites.
    @ViewBuilder func macOnly(_ f: (Self) -> some View) -> some View {
        #if os(macOS)
        f(self)
        #else
        self
        #endif
    }
}
