import AppKit

/// Concrete colours resolved once per render, before drawing any primitives.
///
/// The DIY theme uses quieter light/dark accents for small status glyphs.
/// Increased-contrast appearances retain the system's semantic colours.
struct BatteryStatusColorPalette {
    private static let lightAccents: (charging: UInt32, lowPower: UInt32, highPower: UInt32, critical: UInt32) =
        (0x176C56, 0x815B16, 0x366294, 0xAF3F45)
    private static let darkAccents: (charging: UInt32, lowPower: UInt32, highPower: UInt32, critical: UInt32) =
        (0x71C9AE, 0xDDB46A, 0x91B8E8, 0xF38E91)

    /// The plain discharging baseline: the label colour, matching the renderer's
    /// `foreground` so a `.system` selection is pixel-identical to the old look.
    let discharging: CGColor
    /// True while the discharging role is still the system default. The renderer
    /// then reuses its own exact `foreground`, keeping `.discharging` pixel-for-
    /// pixel identical to the old `.primary` ring on every surface (the Dock's
    /// near-black ink differs from `labelColor`, so a palette colour would drift).
    let dischargingIsSystem: Bool
    let charging: CGColor
    let lowPower: CGColor
    let highPower: CGColor
    let critical: CGColor
    /// The middle Bluetooth glyph colour, resolved from the scene selection.
    let bluetoothIcon: CGColor

    static func resolved(
        appearance: NSAppearance,
        increasedContrast: Bool = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    ) -> Self {
        var result = Self(
            discharging: CGColor(gray: 0, alpha: 1),
            dischargingIsSystem: true,
            charging: CGColor(gray: 1, alpha: 1),
            lowPower: CGColor(gray: 1, alpha: 1),
            highPower: CGColor(gray: 1, alpha: 1),
            critical: CGColor.redFallback,
            bluetoothIcon: CGColor(gray: 0, alpha: 1)
        )
        appearance.performAsCurrentDrawingAppearance {
            // The discharging baseline must equal the renderer's `foreground`
            // (black in light, white in dark), so derive it from the label colour
            // exactly the way `renderEnvironment` derives its ink.
            let isDark = (NSColor.labelColor.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0) > 0.5
            let accents = isDark ? darkAccents : lightAccents
            result = Self(
                discharging: CGColor(gray: isDark ? 1 : 0, alpha: 1),
                dischargingIsSystem: true,
                charging: increasedContrast ? rgb(.systemGreen) : rgb(accents.charging),
                lowPower: increasedContrast ? rgb(.systemYellow) : rgb(accents.lowPower),
                highPower: increasedContrast ? rgb(.systemBlue) : rgb(accents.highPower),
                critical: increasedContrast ? rgb(.systemRed) : rgb(accents.critical),
                bluetoothIcon: rgb(.systemBlue)
            )
        }
        return result
    }

    static func resolved(dark: Bool) -> Self {
        let name: NSAppearance.Name = dark ? .darkAqua : .aqua
        return resolved(appearance: NSAppearance(named: name) ?? NSAppearance.currentDrawing())
    }

    /// Explicit-ink renderers (including headless fixtures) infer appearance
    /// from their supplied ink; live menu-bar rendering supplies its real one.
    static func inferred(foreground: CGColor, critical: CGColor) -> Self {
        let brightness = NSColor(cgColor: foreground)?.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0
        let resolved = resolved(dark: brightness >= 0.5)
        return Self(
            discharging: foreground,
            dischargingIsSystem: true,
            charging: resolved.charging,
            lowPower: resolved.lowPower,
            highPower: resolved.highPower,
            critical: critical,
            bluetoothIcon: BluetoothIconColorResolver.resolve(
                .systemBlue,
                foreground: foreground,
                darkAppearance: brightness >= 0.5
            )
        )
    }

    func color(for role: BatteryStatusColorRole) -> CGColor {
        switch role {
        case .discharging: discharging
        case .charging: charging
        case .lowPower: lowPower
        case .highPower: highPower
        case .critical: critical
        }
    }

    /// Replaces the semantic baselines with the user's per-role selections. The
    /// `.system` roles keep `self`'s resolved baseline, so a real high-contrast
    /// appearance is preserved instead of being re-derived from a light/dark flag.
    func applying(_ statusColors: BatteryStatusColors, darkAppearance: Bool) -> Self {
        guard statusColors.hasOverrides else { return self }
        func resolve(_ role: BatteryStatusColorRole, _ baseline: CGColor) -> CGColor {
            BatteryStatusColorResolver.resolve(
                selection: statusColors.selection(for: role),
                systemBaseline: baseline,
                darkAppearance: darkAppearance
            ).color
        }
        return Self(
            discharging: resolve(.discharging, discharging),
            dischargingIsSystem: statusColors.discharging.isSystem,
            charging: resolve(.charging, charging),
            lowPower: resolve(.lowPower, lowPower),
            highPower: resolve(.highPower, highPower),
            critical: resolve(.critical, critical),
            bluetoothIcon: bluetoothIcon
        )
    }

    /// Replaces the Bluetooth icon colour with the scene's own selection. Kept
    /// separate from the battery status colours because the two settings are
    /// independent.
    func applying(
        bluetoothIcon selection: BluetoothIconColorSelection,
        foreground: CGColor,
        darkAppearance: Bool
    ) -> Self {
        Self(
            discharging: discharging,
            dischargingIsSystem: dischargingIsSystem,
            charging: charging,
            lowPower: lowPower,
            highPower: highPower,
            critical: critical,
            bluetoothIcon: BluetoothIconColorResolver.resolve(
                selection,
                foreground: foreground,
                darkAppearance: darkAppearance
            )
        )
    }

    private static func rgb(_ color: NSColor) -> CGColor {
        color.usingColorSpace(.deviceRGB)?.cgColor ?? color.cgColor
    }

    private static func rgb(_ hex: UInt32) -> CGColor {
        func component(_ shift: UInt32) -> CGFloat { CGFloat((hex >> shift) & 0xFF) / 255 }
        return NSColor(srgbRed: component(16), green: component(8), blue: component(0), alpha: 1).cgColor
    }
}

private extension CGColor {
    static var redFallback: CGColor {
        CGColor(red: 255.0 / 255.0, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
    }
}
