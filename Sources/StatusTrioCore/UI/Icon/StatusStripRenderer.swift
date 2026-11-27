import AppKit
import CoreText

@MainActor
enum StatusStripRenderer {
    private static let height: CGFloat = 24

    nonisolated static func width(_ strip: StatusStrip) -> CGFloat {
        switch strip.layout {
        case .inline: 114
        case .unified: 122
        case .connection: 150
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
        let strip = scene.statusStrip ?? StatusStrip(layout: .inline, previewScene: scene)
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return bitmap(size: CGSize(width: 43, height: height), scale: scale) { context in
            painter(scene: scene, strip: strip, in: context, dark: dark, appearance: appearance)
                .indicator(at: 11, y: height / 2, width: 18, metricLane: 3...40)
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
        var batteryStroke: Double { scene.outerRing?.strokeScale ?? RingStrokeStyle.regular.scale }
        var connectionTint: CGColor { strip.link == .offline ? palette.critical : ink }

        func draw(phase: ChargingEffectPhase?) {
            let w = StatusStripRenderer.width(strip)
            switch strip.layout {
            case .inline:
                center(at: 59, y: 12, maxWidth: 22)
            case .unified:
                pill(x: 2, width: w - 4, tint: ink)
                rule(at: 49)
                center(at: 62, y: 12, maxWidth: 21)
                rule(at: 74)
            case .connection:
                pill(x: 2, width: 46, tint: ink)
                pill(x: 52, width: w - 54, tint: connectionTint)
                connectionCenter(at: 77, leadingX: 64, detailX: 88, y: 12,
                                 symbolSize: 15, detailWidth: 30)
            }
            energy(at: 18, y: 14, phase: phase)
            primaryTrack(x: 5, y: 5.25, width: strip.layout == .inline ? 33 : 40, phase: phase)
            indicator(at: w - 33, y: 12, width: 18, metricLane: (w - 42)...(w - 5))
        }

        func drawDock(phase: ChargingEffectPhase?) {
            switch strip.layout {
            case .inline: break
            case .unified:
                rounded(CGRect(x: 4, y: 9, width: 88, height: 77), tint: faded(ink, 0.11), radius: 12)
                rounded(CGRect(x: 43, y: 16, width: 1, height: 18), tint: faded(ink, 0.25), radius: 0.5)
                rounded(CGRect(x: 12, y: 38, width: 72, height: 1), tint: faded(ink, 0.25), radius: 0.5)
            case .connection:
                rounded(CGRect(x: 4, y: 41, width: 88, height: 45), tint: faded(ink, 0.13), radius: 10)
                rounded(CGRect(x: 4, y: 9, width: 88, height: 28), tint: faded(connectionTint, 0.16), radius: 8)
            }

            if strip.usesSystemBattery {
                if showsBatteryReadout {
                    text(number, x: 43, y: 64, size: min(30, 23 * accessoryScale), maxWidth: 59, tint: energyInk)
                }
                power(at: 81, y: 65, phase: phase, size: 17)
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

            if strip.layout == .connection {
                connectionCenter(at: 26, leadingX: 15, detailX: 37, y: 24,
                                 symbolSize: 17, detailWidth: 24)
            } else {
                center(at: 23, y: 24, symbolSize: 21)
            }
            let connectedLayout = strip.layout == .connection
            indicator(at: connectedLayout ? 64 : 59, y: 24,
                      width: connectedLayout ? 14 : 19,
                      metricLane: (connectedLayout ? 52 : 48)...89, verticalHeight: 16)
        }

        func color(_ role: IconColorRole) -> CGColor {
            StatusIconRenderer.sceneColor(for: role, foreground: ink, statusPalette: palette)
        }

        func connectionCenter(at x: CGFloat, leadingX: CGFloat, detailX: CGFloat, y: CGFloat,
                              symbolSize: CGFloat, detailWidth: CGFloat) {
            let label: String? = switch strip.centerShowsNetwork ? strip.link : .unknown {
            case let .wifi(band): band
            case .wired: "LAN"
            default: nil
            }
            let sideWarning = strip.link == .offline && !strip.showsOutageInCenter
            center(at: label != nil || sideWarning ? leadingX : x, y: y, symbolSize: symbolSize, maxWidth: 21)
            if let label { text(label, x: detailX, y: y, size: 9, maxWidth: detailWidth, tint: ink) }
            if sideWarning { symbol("wifi.slash", x: detailX, y: y, size: 14, tint: palette.critical) }
        }

        var accessoryScale: Double {
            switch scene.outerRing?.accessory {
            case let .text(value): value.scale
            case let .symbol(value): value.scale
            case nil: 1
            }
        }

        func energy(at x: CGFloat, y: CGFloat, phase: ChargingEffectPhase?) {
            if strip.usesSystemBattery {
                if showsBatteryReadout {
                    text(number, x: x, y: y, size: min(12, 10 * accessoryScale), maxWidth: 29, tint: energyInk)
                }
                power(at: x + 22, y: y + 0.7, phase: phase)
            } else if !strip.airPodsLevels.isEmpty {
                airPodsReadout(at: x + 7, y: y, width: 42, fontSize: 9.5, symbolSize: 10)
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

        func indicator(at x: CGFloat, y: CGFloat, width: CGFloat, metricLane: ClosedRange<CGFloat>,
                       symbolSize: CGFloat = 18, verticalHeight: CGFloat = 13) {
            let name: String
            switch scene.bottomIndicatorSource {
            case .hidden: return
            case .wifi: name = "wifi"
            case .battery: name = "battery.75percent"
            case .metric:
                metricIndicator(in: metricLane, y: y, width: width, verticalHeight: verticalHeight)
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

        func metricIndicator(in lane: ClosedRange<CGFloat>, y: CGFloat, width: CGFloat, verticalHeight: CGFloat) {
            let midX = (lane.lowerBound + lane.upperBound) / 2
            let isVertical = if case let .arc(bar) = scene.footer { bar.isVertical } else { false }
            // Memory pressure reports a discrete level through the gauge, not a numeric reading.
            if strip.footerMetric == .memoryPressure, MemoryPressureFooterMapper.title(for: scene.footer) != nil {
                footer(x: midX - (isVertical ? 5 : width / 2), centerY: y, width: width, verticalHeight: verticalHeight)
                return
            }
            let value = scene.footer?.metricReading ?? "\u{2013}"
            // Fit the largest setting first so long units retain the slider's full range.
            let maxScale = StatusStrip.metricTextScaleRange.upperBound
            let fontSize: CGFloat = 9.5 * maxScale
            let relativeScale = strip.footerMetricTextScale / maxScale
            if isVertical {
                let barX = lane.upperBound - 3
                // Reserve room for the thickest bar and its gap at every reading size.
                let readingWidth = barX - 5 - lane.lowerBound
                text(value, x: lane.lowerBound + readingWidth / 2, y: y, size: fontSize,
                     maxWidth: readingWidth, tint: ink, relativeScale: relativeScale)
                footer(x: barX - 5, centerY: y, width: width, verticalHeight: verticalHeight)
            } else {
                text(value, x: midX, y: y + 4.5, size: fontSize, maxWidth: lane.upperBound - lane.lowerBound,
                     tint: ink, relativeScale: relativeScale)
                footer(x: midX - width / 2, centerY: y - 4.5, width: width, verticalHeight: verticalHeight)
            }
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
                meter(x: origin, y: y, width: lane, progress: progress, tint: tint, stroke: stroke, phase: phase)
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

        func text(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, maxWidth: CGFloat, tint: CGColor,
                  relativeScale: CGFloat = 1) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): tint
            ]))
            let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            guard !bounds.isEmpty else { return }
            let scale = min(1, maxWidth / bounds.width) * relativeScale
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
