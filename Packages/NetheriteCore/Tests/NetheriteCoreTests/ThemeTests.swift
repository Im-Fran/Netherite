import Foundation
import Testing
@testable import NetheriteCore

@Test func contrastRatio() {
    #expect(Theme.contrast("#FFFFFF", "#000000")! > 20.99)
    #expect(Theme.contrast("#635385", "#635385") == 1)
    #expect(abs(Theme.contrast("#767676", "#FFFFFF")! - 4.54) < 0.01)
    #expect(Theme.contrast("nope", "#FFFFFF") == nil)
    #expect(RGB(hex: "#0072B2")?.hex == "#0072B2")
}

/// Checks accent, link (and tag) of every built-in against its background, or white/black without one.
private func meets(_ ratio: Double, _ t: Theme, tag: Bool = false) -> Bool {
    let bg = t.background ?? .init("#FFFFFF", "#000000")
    return ([t.accent, t.link] + (tag ? [t.tag] : [])).allSatisfy { p in
        guard let p else { return true }
        return Theme.contrast(p.light, bg.light)! >= ratio && Theme.contrast(p.dark, bg.dark)! >= ratio
    }
}

@Test func builtInThemesMeetWCAGAA() {
    for t in Theme.builtIns { #expect(meets(4.5, t, tag: true), "\(t.name)") }
}

@Test func increasedContrastAndColorVision() {
    for t in Theme.builtIns {
        #expect(meets(7, t.accessible(increaseContrast: true, vision: .none), tag: true), "\(t.name)")
        // The stricter dark gray stands in for "no background" in the adjustment, so black passes too.
        for v in ColorVision.allCases where v != .none {
            let a = t.accessible(increaseContrast: false, vision: v)
            #expect(meets(4.5, a, tag: true), "\(t.name) \(v)")
            #expect(a.callouts?["danger"] != nil)
        }
    }
    #expect(Theme.netherite.accessible(increaseContrast: false, vision: .none) == .netherite)
    #expect(Theme.netherite.accessible(increaseContrast: false, vision: .deuteranopia).accent?.light == "#0072B2")
}

@Test func themeVariants() throws {
    #expect(Theme.builtIns.count == Theme.tones.count * 3)
    let dark = Theme.netherite.variant(.dark)
    #expect(dark.name == "Netherite Dark" && dark.appearance == .dark && dark.tone == "Netherite" && dark.isBuiltIn)
    #expect(dark.variant(nil) == .netherite)
    #expect(Theme.builtIns.first { $0.name == "Netherite" }?.appearance == nil)   // stored value from older vaults
    #expect(Theme(name: "Mine").tone == "Mine" && !Theme(name: "Mine").isBuiltIn)
    #expect(Theme.calloutCategory("BUG") == "danger" && Theme.calloutCategory("abstract") == "note")

    // Older files (no appearance) and unknown values still decode.
    let old = try JSONDecoder().decode(Theme.self, from: Data(##"{"name":"Old","accent":{"light":"#000000","dark":"#FFFFFF"}}"##.utf8))
    #expect(old.appearance == nil && old.accent != nil)
    let odd = try JSONDecoder().decode(Theme.self, from: Data(#"{"name":"Odd","appearance":"sepia","fontScale":"big"}"#.utf8))
    #expect(odd.appearance == nil && odd.fontScale == nil)
}

@Test func themeCSSFollowsAppearance() {
    let auto = HTMLRenderer.themeCSS(.netherite)
    #expect(auto.contains("--accent:light-dark(#635385,#B09EDB)") && !auto.contains("color-scheme"))
    var dark = Theme.netherite.variant(.dark)
    dark.callouts = ["warning": .init("#E69F00", "#E69F00")]
    dark.textFont = "ui-serif"
    let css = HTMLRenderer.themeCSS(dark)
    #expect(css.contains("color-scheme:dark") && css.contains("--accent:#B09EDB") && !css.contains("light-dark"))
    #expect(css.contains(".callout[data-callout=faq]") && css.contains("--font:ui-serif,"))
    #expect(HTMLRenderer.page(title: nil, body: "", assets: "", theme: dark).contains(##"<meta name="color-scheme" content="dark">"##))
}
