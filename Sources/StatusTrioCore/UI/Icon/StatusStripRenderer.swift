import AppKit
import CoreText

@MainActor
enum StatusStripRenderer {
    private static let height: CGFloat = 24

    nonisolated static func width(_ strip: StatusStrip) -> CGFloat {
        switch strip.layout {
        case .divider, .gauge: 125
        case .batteryWordmark: 134
        case .capsule: 128
        case .unified: 138
        case .connection: 154
        case .alerts: strip.hasAlert ? 88 : 24
        }
    }

    static func imageSize(_ strip: StatusStrip, size: CGFloat) -> CGSize {
        let height = min(36, max(16, size))
        return CGSize(width: width(strip) * height / Self.height, height: height)
    }

    static func canUseTemplate(_ scene: IconSceneState) -> Bool {
        let monochrome = scene.colorRoles.allSatisfy { role in
            role == .primary || role == .inactive || (role == .discharging && scene.statusColors.discharging.isSystem)
        }
        guard monochrome, let strip = scene.statusStrip,
              !strip.showsAirPodsSymbol || scene.bluetoothIconColor == .primary,
              !strip.showsOutageInCenter,
              !(strip.layout == .alerts && strip.hasAlert),
              !(strip.layout == .connection && strip.link == .offline) else { return false }
        if case let .symbol(center) = scene.center, case .image = center.source { return false }
        if case let .symbol(accessory) = scene.outerRing?.accessory, case .image = accessory.source { return false }
        return true
    }

    static func image(scene: IconSceneState, size: CGFloat, scale: CGFloat,
                      appearance: NSAppearance, phase: ChargingEffectPhase? = nil) -> NSImage? {
        guard let strip = scene.statusStrip, size.isFinite, scale.isFinite, scale > 0 else { return nil }
        let bounds = CGRect(origin: .zero, size: imageSize(strip, size: size))
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return bitmap(size: bounds.size, scale: scale) { context in
            draw(scene: scene, bounds: bounds, in: context, dark: dark, phase: phase, appearance: appearance)
        }
    }

    static func indicatorImage(scene: IconSceneState, scale: CGFloat, appearance: NSAppearance) -> NSImage? {
        guard scene.footer != nil, scale.isFinite, scale > 0 else { return nil }
        let strip = scene.statusStrip ?? StatusStrip(layout: .divider, previewScene: scene)
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return bitmap(size: CGSize(width: 43, height: height), scale: scale) { context in
            painter(scene: scene, strip: strip, in: context, dark: dark, appearance: appearance)
                .indicator(at: 11, y: height / 2, width: 18)
        }
    }

    private static func bitmap(size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> NSImage? {
        guard let context = CGContext(data: nil, width: Int(ceil(size.width * scale)),
                                     height: Int(ceil(size.height * scale)), bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        draw(context)
        guard let bitmap = context.makeImage() else { return nil }
        // Keep the requested backing resolution even when the logical width is fractional.
        let representation = NSBitmapImageRep(cgImage: bitmap)
        representation.size = size
        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }

    static func draw(scene: IconSceneState, bounds: CGRect, in context: CGContext,
                     dark: Bool, phase: ChargingEffectPhase?, dock: Bool = false, appearance: NSAppearance? = nil) {
        guard let strip = scene.statusStrip else { return }
        let frame = dock ? CGSize(width: 96, height: 96) : CGSize(width: width(strip), height: height)
        let scale = min(bounds.width / frame.width, bounds.height / frame.height)
        guard scale > 0 else { return }
        context.saveGState()
        context.translateBy(x: bounds.midX - frame.width * scale / 2, y: bounds.midY - frame.height * scale / 2)
        context.scaleBy(x: scale, y: scale)
        let painter = painter(scene: scene, strip: strip, in: context, dark: dark, appearance: appearance)
        let phase = scene.outerRing?.effect == nil ? nil : phase
        if dock { painter.drawDock(phase: phase) }
        else { painter.draw(phase: phase) }
        context.restoreGState()
    }

    private static func painter(scene: IconSceneState, strip: StatusStrip, in context: CGContext,
                                dark: Bool, appearance: NSAppearance?) -> Painter {
        let ink = CGColor(gray: dark ? 0.96 : 0.09, alpha: 1)
        let palette = (appearance.map { BatteryStatusColorPalette.resolved(appearance: $0) }
            ?? BatteryStatusColorPalette.resolved(dark: dark))
            .applying(scene.statusColors, darkAppearance: dark)
            .applying(bluetoothIcon: scene.bluetoothIconColor, foreground: ink, darkAppearance: dark)
        return Painter(context: context, scene: scene, strip: strip, dark: dark, ink: ink, palette: palette)
    }

    private struct Painter {
        let context: CGContext
        let scene: IconSceneState
        let strip: StatusStrip
        let dark: Bool
        let ink: CGColor
        let palette: BatteryStatusColorPalette
        var energyInk: CGColor { color(scene.outerRing?.segments.first?.color ?? .primary) }
        var number: String { strip.battery.map { "\($0)%" } ?? "\u{2013}" }
        var segments: [RingSegmentState] { scene.outerRing?.segments ?? [] }
        var showsBatteryReadout: Bool { strip.battery == nil || scene.outerRing?.accessory != nil }
        var showsChargingBolt: Bool {
            guard strip.usesSystemBattery, strip.energy == .charging,
                  case let .symbol(value) = scene.outerRing?.accessory else { return false }
            return value.source == .primitive(.bolt)
        }
        var batteryStroke: Double { scene.outerRing?.strokeScale ?? RingStrokeStyle.regular.scale }

        func draw(phase: ChargingEffectPhase?) {
            let w = StatusStripRenderer.width(strip)
            switch strip.layout {
            case .divider, .batteryWordmark, .capsule, .gauge:
                center(at: 13, y: 12)
                if strip.layout == .divider { rule(at: 27) }
                if strip.layout == .capsule { pill(x: 28, width: 53, tint: ink) }
                if strip.layout == .batteryWordmark && strip.usesSystemBattery {
                    wordmark(at: 49)
                    power(at: 77, y: 14.7, phase: phase)
                } else {
                    energy(at: 47, y: 14, phase: phase)
                }
                primaryTrack(x: 33, y: 5.25, width: strip.layout == .batteryWordmark ? 48 : 42, phase: phase)
            case .unified:
                pill(x: 2, width: w - 4, tint: ink)
                energy(at: 24, y: 14, phase: phase)
                primaryTrack(x: 10, y: 5.25, width: 42, phase: phase)
                rule(at: 56)
                center(at: 70, y: 12)
                rule(at: 84)
            case .connection:
                energy(at: 22, y: 14, phase: phase)
                primaryTrack(x: 8, y: 5.25, width: 40, phase: phase)
                let label: String? = switch strip.centerShowsNetwork ? strip.link : .unknown {
                case let .wifi(band): band
                case .wired: "LAN"
                default: nil
                }
                pill(x: 55, width: 49, tint: strip.link == .offline ? palette.critical : ink)
                let sideWarning = strip.link == .offline && !strip.showsOutageInCenter
                center(at: label == nil && !sideWarning ? 79.5 : 66.5, y: 12, maxWidth: 21)
                if let label { text(label, x: 89, y: 12, size: 9, maxWidth: 22, tint: ink) }
                if sideWarning { symbol("wifi.slash", x: 92, y: 12, size: 14, tint: palette.critical) }
            case .alerts:
                guard strip.hasAlert else {
                    if showsChargingBolt { power(at: 12, y: 13.5, phase: phase) }
                    else { symbol("checkmark", x: 12, y: 12, size: 15, tint: ink) }
                    if let phase { meter(x: 6, y: 3.5, width: 12, progress: 1, tint: energyInk,
                                         stroke: batteryStroke, phase: phase) }
                    return
                }
                pill(x: 2, width: w - 4, tint: palette.critical)
                if strip.lowBattery { energy(at: strip.link == .offline ? 23 : 34, y: 12, forceBattery: true) }
                if strip.link == .offline {
                    symbol("wifi.slash", x: strip.lowBattery ? 69 : w / 2, y: 12, size: 16, tint: palette.critical)
                }
                if let phase { meter(x: 17, y: 4, width: 22, progress: 1, tint: energyInk,
                                     stroke: batteryStroke, phase: phase) }
                return
            }
            indicator(at: w - 33, y: 12, width: 18)
        }

        func drawDock(phase: ChargingEffectPhase?) {
            if strip.layout == .alerts {
                if strip.hasAlert {
                    rounded(CGRect(x: 7, y: 29, width: 82, height: 38), tint: faded(palette.critical, 0.17), radius: 12)
                    if strip.lowBattery {
                        text(number, x: strip.link == .offline ? 32 : 48, y: 50, size: 20, maxWidth: 45, tint: palette.critical)
                    }
                    if strip.link == .offline {
                        symbol("wifi.slash", x: strip.lowBattery ? 70 : 48, y: 50, size: 20, tint: palette.critical)
                    }
                } else if showsChargingBolt {
                    power(at: 48, y: 58, phase: phase, size: 24)
                } else {
                    symbol("checkmark", x: 48, y: 55, size: 38, tint: ink)
                }
                if let phase { meter(x: 30, y: 39.5, width: 36, progress: 1, tint: energyInk,
                                     stroke: batteryStroke, phase: phase) }
                return
            }

            switch strip.layout {
            case .unified:
                rounded(CGRect(x: 4, y: 9, width: 88, height: 77), tint: faded(ink, 0.11), radius: 12)
                rounded(CGRect(x: 43, y: 16, width: 1, height: 18), tint: faded(ink, 0.25), radius: 0.5)
            case .divider:
                rounded(CGRect(x: 11, y: 37, width: 74, height: 1), tint: faded(ink, 0.25), radius: 0.5)
            case .capsule:
                rounded(CGRect(x: 5, y: 40, width: 86, height: 45), tint: faded(ink, 0.13), radius: 12)
            case .connection:
                rounded(CGRect(x: 5, y: 10, width: 50, height: 28), tint: faded(strip.link == .offline ? palette.critical : ink, 0.16), radius: 8)
            default: break
            }

            if strip.usesSystemBattery {
                if strip.layout == .batteryWordmark {
                    let body = CGRect(x: 15, y: 52, width: 56, height: 24)
                    context.setStrokeColor(energyInk)
                    context.setLineWidth(1.75)
                    context.addPath(CGPath(roundedRect: body, cornerWidth: 6, cornerHeight: 6, transform: nil))
                    context.strokePath()
                    rounded(CGRect(x: 73, y: 59, width: 3, height: 10), tint: energyInk, radius: 1)
                    if showsBatteryReadout { batteryDigits(at: 43, y: 64, size: 16, maxWidth: 48) }
                    power(at: 86, y: 64, phase: phase, size: 16)
                } else {
                    if showsBatteryReadout {
                        text(number, x: 43, y: 64, size: min(30, 23 * accessoryScale), maxWidth: 59, tint: energyInk)
                    }
                    power(at: 81, y: 65, phase: phase, size: 17)
                }
            } else if !strip.airPodsLevels.isEmpty {
                airPodsReadout(at: 48, y: 64, width: 70, fontSize: 20, symbolSize: 17)
            } else if let accessory = scene.outerRing?.accessory {
                switch accessory {
                case let .text(value):
                    text(value.text, x: 48, y: 64, size: min(28, 22 * value.scale), maxWidth: 73, tint: color(value.color))
                case let .symbol(value):
                    sourceSymbol(value, x: 48, y: 64, size: min(24, 19 * value.scale), tint: color(value.color))
                }
            }
            primaryTrack(x: 13, y: 44, width: 70, phase: phase)

            if strip.layout == .connection, strip.centerShowsNetwork, case let .wifi(label?) = strip.link {
                center(at: 17, y: 24, symbolSize: 19, maxWidth: 21)
                text(label, x: 40, y: 24, size: 9.5, maxWidth: 22, tint: ink)
            } else if strip.layout == .connection && strip.centerShowsNetwork && strip.link == .wired {
                center(at: 17, y: 24, symbolSize: 19, maxWidth: 21)
                text("LAN", x: 40, y: 24, size: 9.5, maxWidth: 22, tint: ink)
            } else { center(at: strip.layout == .connection ? 30 : 23, y: 24, symbolSize: 21) }
            indicator(at: strip.layout == .connection ? 66 : 59, y: 24,
                      width: strip.layout == .connection ? 14 : 19, symbolSize: 18, verticalHeight: 16)
        }

        func color(_ role: IconColorRole) -> CGColor {
            StatusIconRenderer.sceneColor(for: role, foreground: ink, statusPalette: palette)
        }

        func wordmark(at x: CGFloat) {
            let rect = CGRect(x: x - 17, y: 8, width: 34, height: 12)
            context.setStrokeColor(energyInk)
            context.setLineWidth(0.9)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil))
            context.strokePath()
            rounded(CGRect(x: rect.maxX + 1, y: 11, width: 2, height: 5), tint: energyInk, radius: 0.8)
            if showsBatteryReadout { batteryDigits(at: x, y: 14, size: 9, maxWidth: 26) }
        }

        func batteryDigits(at x: CGFloat, y: CGFloat, size: CGFloat, maxWidth: CGFloat) {
            text(strip.battery.map(String.init) ?? "\u{2013}", x: x, y: y,
                 size: min(size * 1.32, size * accessoryScale), maxWidth: maxWidth, tint: energyInk)
        }

        var accessoryScale: Double {
            switch scene.outerRing?.accessory {
            case let .text(value): value.scale
            case let .symbol(value): value.scale
            case nil: 1
            }
        }

        func energy(at x: CGFloat, y: CGFloat, phase: ChargingEffectPhase? = nil, forceBattery: Bool = false) {
            if strip.usesSystemBattery || forceBattery {
                let tint = forceBattery ? palette.critical : energyInk
                if forceBattery || showsBatteryReadout {
                    text(number, x: x, y: y, size: min(12, 10 * accessoryScale), maxWidth: 29, tint: tint)
                }
                if forceBattery {
                    symbol("exclamationmark.triangle.fill", x: x + 22, y: y, size: 10.5, tint: tint)
                } else { power(at: x + 22, y: y + 0.7, phase: phase) }
            } else if !strip.airPodsLevels.isEmpty {
                let offset: CGFloat = strip.layout == .batteryWordmark ? 10 : 7
                airPodsReadout(at: x + offset, y: y, width: 42, fontSize: 9.5, symbolSize: 10)
            } else if let accessory = scene.outerRing?.accessory {
                switch accessory {
                case let .text(value):
                    text(value.text, x: x + 4, y: y, size: min(12, 9 * value.scale), maxWidth: 34, tint: color(value.color))
                case let .symbol(value):
                    sourceSymbol(value, x: x + 4, y: y, size: min(13, 10 * value.scale), tint: color(value.color))
                }
            }
        }

        func airPodsReadout(at x: CGFloat, y: CGFloat, width: CGFloat, fontSize: CGFloat, symbolSize: CGFloat) {
            let markerScale = min(1.2, max(0.9, strip.airPodsMarkerScale))
            let split = strip.airPodsLevels.count == 2
            let iconWidth = strip.showsAirPodsSymbol ? symbolSize * markerScale : 0
            let maxWidth = split ? (width - iconWidth - 4) / 2 : width - iconWidth - 4
            for (index, level) in strip.airPodsLevels.enumerated() {
                let offset = split ? (index == 0 ? -1 : 1) * (width - maxWidth) / 2 : -iconWidth / 2
                let role = segments.indices.contains(index) ? segments[index].color : .primary
                text(level.map { "\($0)%" } ?? "\u{2013}", x: x + offset, y: y,
                     size: fontSize * markerScale, maxWidth: maxWidth, tint: color(level == nil ? .primary : role))
            }
            if strip.showsAirPodsSymbol {
                let iconX = split ? x : x + width / 3
                symbol("airpods", x: iconX, y: y, size: iconWidth, tint: color(.bluetoothIcon), fallback: "headphones")
            }
        }

        func power(at x: CGFloat, y: CGFloat, phase: ChargingEffectPhase?, size: CGFloat = 11.4) {
            if case let .symbol(value) = scene.outerRing?.accessory {
                let pulses = scene.outerRing?.effect?.pulsesAccessory == true
                let pulse = pulses ? phase.map { 1 + 0.1 * sin(2 * .pi * Double($0.step) / Double(max(1, $0.stepsPerCycle))) } ?? 1 : 1
                let adjustment = min(1.2, max(0.8, value.scale / BatteryIconOptions.defaultTextScale))
                sourceSymbol(value, x: x, y: y, size: size * adjustment * pulse, tint: energyInk)
            } else if strip.lowBattery {
                symbol("exclamationmark.triangle.fill", x: x, y: y - 1.5, size: size * 0.86, tint: energyInk)
            }
        }

        func indicator(at x: CGFloat, y: CGFloat, width: CGFloat, symbolSize: CGFloat = 18,
                       verticalHeight: CGFloat = 13) {
            let name: String
            switch scene.bottomIndicatorSource {
            case .hidden: return
            case .wifi: name = "wifi"
            case .battery: name = "battery.75percent"
            case .metric:
                let tint = color(scene.footer?.colorRole ?? .primary)
                let value = scene.footer?.metricReading ?? "\u{2013}"
                let icon = strip.footerMetric.map { HardwareRingMapper.topMarkerSymbol(for: $0) } ?? "waveform.path"
                symbol(icon, x: x - 3, y: y, size: 12, tint: tint, fallback: "waveform.path")
                let readingX = x + 15
                if case let .arc(bar) = scene.footer, bar.isVertical {
                    text(value, x: readingX - 1, y: y, size: 9, maxWidth: 22, tint: ink)
                    footer(x: readingX + 7, centerY: y, width: width, verticalHeight: verticalHeight)
                } else {
                    text(value, x: readingX, y: y + 3.5, size: 9.5, maxWidth: 29, tint: ink)
                    footer(x: readingX - width / 2, centerY: y - 4, width: width, verticalHeight: verticalHeight)
                }
                return
            case .volume:
                name = if strip.muted { "speaker.slash.fill" }
                    else if strip.audio == .high { "speaker.wave.2.fill" }
                    else if strip.audio == .low { "speaker.wave.1.fill" }
                    else { "speaker.fill" }
            }
            symbol(name, x: x, y: y, size: symbolSize, tint: color(scene.footer?.colorRole ?? .primary),
                   weight: scene.bottomIndicatorSource == .volume ? .semibold : nil)
            footer(x: x + symbolSize / 2 + 2, centerY: y, width: width, verticalHeight: verticalHeight)
        }

        func center(at x: CGFloat, y: CGFloat, symbolSize: CGFloat = 15, maxWidth: CGFloat = 24) {
            if strip.showsOutageInCenter {
                symbol("wifi.slash", x: x, y: y, size: symbolSize + 1, tint: palette.critical)
                return
            }
            switch scene.center {
            case let .text(value):
                let scale = value.normalizedSizePercentage.map { 0.7 + 0.5 * ($0 - 1) } ?? value.scale
                text(value.text, x: x, y: y, size: min(symbolSize + 1.5, (symbolSize - 1.5) * scale),
                     maxWidth: maxWidth, tint: color(value.color))
            case let .symbol(value):
                let size = value.normalizedSizePercentage.map { symbolSize * (0.7 + 0.5 * ($0 - 1)) }
                    ?? symbolSize * value.scale
                sourceSymbol(value, x: x, y: y, size: min(maxWidth - 2, symbolSize + 4, size), tint: color(value.color))
            case nil: break
            }
        }

        func sourceSymbol(_ value: IconSymbolState, x: CGFloat, y: CGFloat, size: CGFloat, tint: CGColor) {
            switch value.source {
                case let .symbol(name, variable, fallback):
                    symbol(name, x: x, y: y, size: size, tint: tint, variable: variable, fallback: fallback)
                case let .image(url, fallback):
                    if let image = NSImage(contentsOf: url) { drawImage(image, x: x, y: y, size: size, tint: nil) }
                    else { symbol(fallback, x: x, y: y, size: size, tint: tint) }
                case let .primitive(kind):
                    let name: String
                    switch kind {
                    case .wiredPort: name = "network"
                    case .screenWedge: name = "display"
                    case .arrowWedge: name = "arrow.up.right"
                    case .plug: name = "powerplug.fill"
                    case .bolt:
                        context.saveGState()
                        context.translateBy(x: x, y: y)
                        context.scaleBy(x: 1, y: -1)
                        context.setFillColor(tint)
                        context.addPath(StatusIconGeometry.batteryChargingBolt(centeredAt: .zero, targetHeight: size))
                        context.fillPath()
                        context.restoreGState()
                        return
                    }
                    symbol(name, x: x, y: y, size: size, tint: tint)
            }
        }

        func primaryTrack(x: CGFloat, y: CGFloat, width: CGFloat, phase: ChargingEffectPhase?) {
            guard !segments.isEmpty else { return }
            let lane = (width - 2 * CGFloat(segments.count - 1)) / CGFloat(segments.count)
            for (index, segment) in segments.enumerated() {
                let origin = x + CGFloat(index) * (lane + 2)
                let tint = color(segment.color)
                let stroke = batteryStroke
                let isUnknownEar = strip.airPodsLevels.indices.contains(index) && strip.airPodsLevels[index] == nil
                let progress = isUnknownEar ? 0 : segment.progress
                if strip.layout == .gauge && segments.count == 1 {
                    let tick = (lane - 9) / 10
                    let lit = max(1, Int(ceil(progress * 10)))
                    let activeTick = phase.map { min(lit - 1, $0.step * lit / max(1, $0.stepsPerCycle)) }
                    for cell in 0..<10 {
                        meter(x: origin + CGFloat(cell) * (tick + 1), y: y, width: tick,
                              progress: min(1, max(0, progress * 10 - Double(cell))), tint: tint,
                              stroke: stroke, phase: cell == activeTick ? phase : nil)
                    }
                } else {
                    meter(x: origin, y: y, width: lane, progress: progress,
                          tint: tint, stroke: stroke, phase: phase)
                }
            }
        }

        func footer(x: CGFloat, centerY: CGFloat, width: CGFloat, verticalHeight: CGFloat) {
            switch scene.footer {
            case let .arc(value):
                if value.isVertical {
                    let tint = color(value.color)
                    let thickness = meterThickness(value.strokeScale) + 0.55
                    let track = CGRect(x: x + 5 - thickness / 2, y: centerY - verticalHeight / 2,
                                       width: thickness, height: verticalHeight)
                    var fill = track
                    fill.size.height *= value.progress
                    rounded(track, tint: faded(tint, 0.2), radius: thickness / 2)
                    rounded(fill, tint: tint, radius: thickness / 2)
                } else {
                    meter(x: x, y: centerY, width: width, progress: value.progress,
                          tint: color(value.color), stroke: value.strokeScale)
                }
            case let .dots(value):
                let count = min(10, value.count)
                guard count > 0 else { return }
                let step = width / CGFloat(count)
                let dot = step * min(0.87, max(0.36, 0.50 + (value.strokeScale - 1) * 0.76))
                for index in 0..<count {
                    rounded(CGRect(x: x + CGFloat(index) * step + (step - dot) / 2, y: centerY - dot / 2,
                                   width: dot, height: dot),
                            tint: index < value.activeCount ? color(value.color) : faded(color(value.inactiveColor), 0.65),
                            radius: dot / 3)
                }
            case nil: break
            }
        }

        func meter(x: CGFloat, y: CGFloat, width: CGFloat, progress: Double, tint: CGColor,
                   stroke: Double, phase: ChargingEffectPhase? = nil) {
            let thickness = meterThickness(stroke)
            let y = y - thickness / 2
            let active = width * progress
            rounded(CGRect(x: x, y: y, width: width, height: thickness), tint: faded(tint, 0.2), radius: thickness / 2)
            rounded(CGRect(x: x, y: y, width: active, height: thickness), tint: tint, radius: thickness / 2)
            if let phase, active >= 2 {
                let spot = min(4, active / 2)
                let travel = active - spot
                let offset = CGFloat(phase.step) / CGFloat(max(1, phase.stepsPerCycle)) * travel
                rounded(CGRect(x: x + min(travel, offset), y: y, width: spot, height: thickness),
                        tint: CGColor(gray: dark ? 1 : 0, alpha: 0.55), radius: thickness / 2)
            }
        }

        func meterThickness(_ stroke: Double) -> CGFloat { min(3.9, max(1, 1.4 + 4.4 * (stroke - 1))) }

        func pill(x: CGFloat, width: CGFloat, tint: CGColor) {
            rounded(CGRect(x: x, y: 1.75, width: width, height: 20.5), tint: faded(tint, dark ? 0.17 : 0.105), radius: 7)
        }

        func rule(at x: CGFloat) {
            rounded(CGRect(x: x, y: 6, width: 0.7, height: 12), tint: faded(ink, 0.25), radius: 0.35)
        }

        func faded(_ color: CGColor, _ opacity: CGFloat) -> CGColor { color.copy(alpha: color.alpha * opacity) ?? color }

        func rounded(_ rect: CGRect, tint: CGColor, radius: CGFloat) {
            guard rect.width > 0, rect.height > 0 else { return }
            context.setFillColor(tint)
            let radius = min(radius, rect.width / 2, rect.height / 2)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }

        func text(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, maxWidth: CGFloat, tint: CGColor) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): tint
            ]))
            let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            guard !bounds.isEmpty else { return }
            let scale = min(1, maxWidth / bounds.width)
            context.saveGState()
            context.translateBy(x: x, y: y)
            context.scaleBy(x: scale, y: scale)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
            CTLineDraw(line, context)
            context.restoreGState()
        }

        func symbol(_ name: String, x: CGFloat, y: CGFloat, size: CGFloat, tint: CGColor,
                    variable: Double? = nil, fallback: String? = nil, weight: NSFont.Weight? = nil) {
            let source = variable.flatMap { NSImage(systemSymbolName: name, variableValue: $0, accessibilityDescription: nil) }
                ?? NSImage(systemSymbolName: name, accessibilityDescription: nil)
                ?? fallback.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            guard let source else { return }
            let weighted = weight.flatMap { source.withSymbolConfiguration(.init(pointSize: 18, weight: $0)) }
            drawImage(weighted ?? source, x: x, y: y, size: size, tint: tint)
        }

        func drawImage(_ source: NSImage, x: CGFloat, y: CGFloat, size: CGFloat, tint: CGColor?) {
            guard let bitmap = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let scale = size / CGFloat(max(bitmap.width, bitmap.height))
            let width = CGFloat(bitmap.width) * scale
            let height = CGFloat(bitmap.height) * scale
            let box = CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)
            if let tint {
                context.saveGState()
                context.clip(to: box, mask: bitmap)
                context.setFillColor(tint)
                context.fill(box)
                context.restoreGState()
            } else { context.draw(bitmap, in: box) }
        }
    }
}
