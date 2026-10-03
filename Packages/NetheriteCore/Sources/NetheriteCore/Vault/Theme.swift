import Foundation

/// A theme is a small JSON file in `.netherite/themes/`. Colors are hex strings with light/dark variants.
public struct Theme: Codable, Hashable, Sendable, Identifiable {
    public struct Pair: Codable, Hashable, Sendable {
        public var light: String
        public var dark: String
        public init(_ light: String, _ dark: String) { self.light = light; self.dark = dark }
    }
    /// Appearance a theme forces on the vault window; nil follows the system.
    public enum Appearance: String, Codable, Hashable, Sendable, CaseIterable { case light, dark }

    public var name: String
    public var appearance: Appearance?
    public var accent: Pair?
    public var link: Pair?
    public var tag: Pair?
    public var highlight: Pair?
    public var background: Pair?
    /// Callout colors by category (see `calloutCategory`); missing ones keep the defaults.
    public var callouts: [String: Pair]?
    public var textFont: String?
    public var monoFont: String?
    public var fontScale: Double?
    public var lineHeight: Double?
    public var id: String { name }

    public init(name: String, appearance: Appearance? = nil, accent: Pair? = nil, link: Pair? = nil, tag: Pair? = nil, highlight: Pair? = nil,
                background: Pair? = nil, callouts: [String: Pair]? = nil, textFont: String? = nil, monoFont: String? = nil,
                fontScale: Double? = nil, lineHeight: Double? = nil) {
        self.name = name; self.appearance = appearance; self.accent = accent; self.link = link; self.tag = tag; self.highlight = highlight
        self.background = background; self.callouts = callouts; self.textFont = textFont; self.monoFont = monoFont
        self.fontScale = fontScale; self.lineHeight = lineHeight
    }

    // Decode leniently: a bad or unknown value drops that field, not the whole theme.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try c.decode(String.self, forKey: .name))
        func d<T: Decodable>(_ k: CodingKeys, _ into: inout T?) { into = try? c.decodeIfPresent(T.self, forKey: k) }
        d(.appearance, &appearance); d(.accent, &accent); d(.link, &link); d(.tag, &tag); d(.highlight, &highlight)
        d(.background, &background); d(.callouts, &callouts); d(.textFont, &textFont); d(.monoFont, &monoFont)
        d(.fontScale, &fontScale); d(.lineHeight, &lineHeight)
    }
}

// MARK: Built-in themes

public extension Theme {
    /// Built-in tones. Each is also available as "<name> Light" and "<name> Dark", which force that appearance.
    static let tones: [Theme] = [
        Theme(name: "Netherite", accent: .init("#635385", "#B09EDB"), link: .init("#5B4A8E", "#B7A6E6"),
              tag: .init("#6E5A9E", "#C4B5F0"), highlight: .init("#F4E27A", "#6B5B1F")),
        Theme(name: "Ocean", accent: .init("#0B6E99", "#4FB3E0"), link: .init("#0A5F8A", "#6CC4EC"),
              tag: .init("#00796B", "#4DD0C0"), highlight: .init("#BFE9F5", "#134E5E"), background: .init("#F5F9FC", "#0F1A22")),
        Theme(name: "Forest", accent: .init("#2E7D32", "#7BC47F"), link: .init("#256B29", "#8FD394"),
              tag: .init("#5F6D1A", "#C2CF6B"), highlight: .init("#E3F2C1", "#3B4A16"), background: .init("#F6FAF5", "#121A14")),
        Theme(name: "Ember", accent: .init("#C2410C", "#FF8A50"), link: .init("#B03A0A", "#FF9E6B"),
              tag: .init("#A3367A", "#F28FC0"), highlight: .init("#FFE0B2", "#5C3A12"), background: .init("#FDF8F4", "#1E1612")),
        Theme(name: "Rose", accent: .init("#BE185D", "#F472B6"), link: .init("#A3154F", "#F9A8D4"),
              tag: .init("#8E44AD", "#D7A6F0"), highlight: .init("#FCE4EC", "#5A2338"), background: .init("#FDF7F9", "#1F1418")),
        Theme(name: "Graphite", accent: .init("#3F3F46", "#D4D4D8"), link: .init("#27272A", "#E4E4E7"),
              tag: .init("#52525B", "#A1A1AA"), highlight: .init("#E4E4E7", "#3F3F46"), background: .init("#F7F7F8", "#18181A")),
        Theme(name: "System"),
    ]
    /// Every tone in its Automatic, Light and Dark variants.
    static let builtIns: [Theme] = tones.flatMap { [$0, $0.variant(.light), $0.variant(.dark)] }
    static let netherite = tones[0]
    static let system = tones[tones.count - 1]

    /// The built-in tone this theme is a variant of ("Ocean" for "Ocean Dark"); `name` for custom themes.
    var tone: String {
        Self.tones.first { [$0.name, $0.name + " Light", $0.name + " Dark"].contains(name) }?.name ?? name
    }

    var isBuiltIn: Bool { Self.builtIns.contains { $0.name == name } }

    /// The same tone with another appearance (nil = automatic).
    func variant(_ appearance: Appearance?) -> Theme {
        var t = Self.tones.first { $0.name == tone } ?? self
        t.appearance = appearance
        switch appearance {
        case nil: break
        case .light: t.name += " Light"
        case .dark: t.name += " Dark"
        }
        return t
    }

    /// Localized title for built-in themes; `name` stays the stored id.
    var displayName: String {
        guard isBuiltIn else { return name }
        let tone = Self.localizedTone(tone)
        switch appearance {
        case nil: return tone
        case .light: return String(localized: "\(tone) Light", bundle: .module)
        case .dark: return String(localized: "\(tone) Dark", bundle: .module)
        }
    }

    /// Localized name of a built-in tone.
    static func localizedTone(_ name: String) -> String {
        switch name {
        case "Ocean": String(localized: "Ocean", bundle: .module)
        case "Forest": String(localized: "Forest", bundle: .module)
        case "Ember": String(localized: "Ember", bundle: .module)
        case "Rose": String(localized: "Rose", bundle: .module)
        case "Graphite": String(localized: "Graphite", bundle: .module)
        case "System": String(localized: "System", bundle: .module)
        default: name
        }
    }

    /// Obsidian callout types by color category; any other type is a "note".
    static let calloutTypes: [String: [String]] = [
        "tip": ["tip", "hint", "important", "success", "check", "done"],
        "warning": ["warning", "caution", "attention", "question", "help", "faq"],
        "danger": ["danger", "error", "failure", "fail", "missing", "bug"],
        "example": ["example"],
        "quote": ["quote", "cite"],
    ]

    /// Color category of a callout type: note, tip, warning, danger, example or quote.
    static func calloutCategory(_ type: String) -> String {
        calloutTypes.first { $0.value.contains(type.lowercased()) }?.key ?? "note"
    }
}

public extension Vault {
    var themesURL: URL { configURL.appending(path: "themes", directoryHint: .isDirectory) }

    /// Built-in themes plus any `*.json` in `.netherite/themes/`.
    func themes() -> [Theme] {
        let custom = ((try? FileManager.default.contentsOfDirectory(at: themesURL, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(Theme.self, from: Data(contentsOf: $0)) }
        return Theme.builtIns + custom.filter { !$0.isBuiltIn }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
