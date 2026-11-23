import AppKit
import Testing
@testable import StatusTrioCore

@MainActor
struct BatteryStatusColorBaselineTests {
    /// #188 / high contrast: the ink is opaque black on every light appearance
    /// and opaque white on every dark one, including the accessibility variants.
    /// Each expectation is written literally so the test does not re-derive the
    /// answer with the same `bestMatch` call the renderer uses.
    @Test func inkIsOpaqueAndMatchesEachAppearanceLiterally() throws {
        let cases: [(NSAppearance.Name, CGFloat)] = [
            (.aqua, 0),
            (.darkAqua, 1),
            (.accessibilityHighContrastAqua, 0),
            (.accessibilityHighContrastDarkAqua, 1)
        ]

        for (name, expectedRed) in cases {
            let appearance = try #require(NSAppearance(named: name))
            let environment = StatusIconRenderer.renderEnvironment(size: 20, scale: 2, appearance: appearance)
            let ink = try #require(NSColor(cgColor: environment.foreground)?.usingColorSpace(.deviceRGB))
            #expect(environment.foreground.alpha == 1)
            #expect(ink.redComponent == expectedRed, "\(name.rawValue)")
            #expect(ink.greenComponent == expectedRed, "\(name.rawValue)")
            #expect(ink.blueComponent == expectedRed, "\(name.rawValue)")
        }
    }

    @Test(arguments: [false, true])
    func defaultAccentsMatchTheDIYPalette(dark: Bool) throws {
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        let palette = BatteryStatusColorPalette.resolved(appearance: appearance, increasedContrast: false)
        let expected: [(BatteryStatusColorRole, CGFloat, CGFloat, CGFloat)] = dark
            ? [(.charging, 113, 201, 174), (.lowPower, 221, 180, 106), (.highPower, 145, 184, 232), (.critical, 243, 142, 145)]
            : [(.charging, 23, 108, 86), (.lowPower, 129, 91, 22), (.highPower, 54, 98, 148), (.critical, 175, 63, 69)]
        for (role, red, green, blue) in expected {
            let color = NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
            #expect(palette.color(for: role) == color.cgColor)
        }
    }
}
