import Foundation

/// An sRGB color, parsed from a theme hex string, with the WCAG contrast math.
public struct RGB: Hashable, Sendable {
    public var r: Double, g: Double, b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    /// `#RRGGBB` or `#RRGGBBAA` (alpha is ignored).
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, var v = UInt64(s, radix: 16) else { return nil }
        if s.count == 8 { v >>= 8 }
        self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    public static let white = RGB(r: 1, g: 1, b: 1)
    public static let black = RGB(r: 0, g: 0, b: 0)

    public var hex: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// WCAG 2 relative luminance.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// WCAG 2 contrast ratio, from 1 to 21.
    public func contrast(with other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public func mixed(with o: RGB, _ t: Double) -> RGB {
        RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }

    /// Darkens (against light colors) or lightens (against dark ones) just enough to reach `ratio`.
    /// Steps are snapped to 8-bit values so the result still passes once written as hex.
    public func ensuring(contrast ratio: Double, against bg: RGB) -> RGB {
        let target: RGB = bg.luminance > 0.179 ? .black : .white
        var t = 0.0, c = self
        while c.contrast(with: bg) < ratio, t < 1 { t = min(1, t + 0.02); c = RGB(hex: mixed(with: target, t).hex) ?? target }
        return c
    }
}

/// Color vision deficiency the app adapts its semantic colors to.
public enum ColorVision: String, CaseIterable, Codable, Sendable {
    case none, protanopia, deuteranopia, tritanopia, grayscale

    /// The hues the app uses to tell things apart (callouts, canvas cards, graph groups, sync states).
    public enum Hue: CaseIterable, Sendable { case red, orange, yellow, green, cyan, blue, purple }

    /// Protanopia/deuteranopia use Okabe–Ito, tritanopia Paul Tol's vibrant set, grayscale hues spread by lightness.
    private var palette: [String] {
        switch self {
        case .none: []
        case .protanopia, .deuteranopia: ["#D55E00", "#E69F00", "#F0E442", "#009E73", "#56B4E9", "#0072B2", "#CC79A7"]
        case .tritanopia: ["#CC3311", "#EE7733", "#F4A6B7", "#009988", "#33BBEE", "#0077BB", "#AA4499"]
        case .grayscale: ["#882255", "#DDAA33", "#EEDD88", "#44AA99", "#88CCEE", "#004488", "#AA4499"]
        }
    }

    /// Safe stand-in for a hue as hex, or nil when colors aren't remapped.
    public func color(_ hue: Hue) -> String? {
        palette.isEmpty ? nil : palette[Hue.allCases.firstIndex(of: hue)!]
    }

    /// The stand-in as a light/dark pair for marks (graph, canvas, sync), at least 3:1 (WCAG non-text contrast)
    /// against the surfaces they sit on. The whole palette shifts by one amount, so hues keep their lightness order.
    public func pair(_ hue: Hue) -> Theme.Pair? {
        Self.marks[self]?[Hue.allCases.firstIndex(of: hue)!]
    }

    /// Mark pairs per mode, computed once (canvas and graph read them on every render).
    private static let marks: [ColorVision: [Theme.Pair]] = Dictionary(uniqueKeysWithValues: allCases.compactMap { v in
        let colors = v.palette.compactMap(RGB.init(hex:))
        guard !colors.isEmpty else { return nil }
        func shifted(on bg: RGB) -> [String] {
            let target: RGB = bg.luminance > 0.179 ? .black : .white
            var t = 0.0
            func mixed(_ c: RGB) -> RGB { RGB(hex: c.mixed(with: target, t).hex)! }
            while t < 1, colors.contains(where: { mixed($0).contrast(with: bg) < 3 }) { t += 0.02 }
            return colors.map { mixed($0).hex }
        }
        let (light, dark) = (shifted(on: surfaces.light), shifted(on: surfaces.dark))
        return (v, zip(light, dark).map { Theme.Pair($0, $1) })
    })

    /// Lowest-contrast surfaces marks are drawn on: grouped/canvas gray in light mode, elevated gray in dark.
    static let surfaces = (light: RGB(hex: "#F2F2F7")!, dark: RGB(hex: "#2C2C2E")!)
}

public extension Theme {
    /// Background colors are checked against when a theme sets none (the reader's white and dark gray).
    static let defaultBackground = Pair("#FFFFFF", "#1E1E1E")

    /// WCAG contrast of two hex colors, nil when one doesn't parse.
    static func contrast(_ a: String, _ b: String) -> Double? {
        guard let a = RGB(hex: a), let b = RGB(hex: b) else { return nil }
        return a.contrast(with: b)
    }

    /// This theme with color-blind-safe semantic colors and accent/link/tag contrast of at least
    /// 4.5:1, or 7:1 with `increaseContrast`, against its background.
    func accessible(increaseContrast: Bool, vision: ColorVision) -> Theme {
        guard increaseContrast || vision != .none else { return self }
        var t = self
        // Text colors start from the palette and get their contrast below; callout borders use the mark pairs.
        func hue(_ h: ColorVision.Hue) -> Pair? { vision.color(h).map { Pair($0, $0) } }
        if vision != .none {
            t.accent = hue(.blue); t.link = hue(.blue); t.tag = hue(.purple); t.highlight = hue(.yellow)
            t.callouts = ["note": vision.pair(.blue), "tip": vision.pair(.green), "warning": vision.pair(.orange),
                          "danger": vision.pair(.red), "example": vision.pair(.purple)].compactMapValues { $0 }
        }
        let ratio = increaseContrast ? 7.0 : 4.5
        func fix(_ p: Pair?, against bg: Pair) -> Pair? {
            func one(_ c: String, _ bg: String) -> String {
                guard let c = RGB(hex: c), let bg = RGB(hex: bg) else { return c }
                return c.ensuring(contrast: ratio, against: bg).hex
            }
            return p.map { Pair(one($0.light, bg.light), one($0.dark, bg.dark)) }
        }
        let bg = t.background ?? Self.defaultBackground
        t.accent = fix(t.accent, against: bg); t.link = fix(t.link, against: bg); t.tag = fix(t.tag, against: bg)
        // The highlight is a fill under body text, so it's the text that needs the contrast.
        t.highlight = fix(t.highlight, against: Pair("#1D1D1F", "#E8E8ED"))
        return t
    }
}
