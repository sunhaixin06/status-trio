import AppKit
import XCTest
@testable import StatusTrioCore

@MainActor
final class StatusStripTests: XCTestCase {
    private func snapshot(level: Int = 76, charging: Bool = true, connection: NetworkConnection = .wifi,
                          band: WiFiFrequencyBand = .fiveGHz, muted: Bool = false,
                          lowPower: Bool = false, connectedToPower: Bool? = nil) -> StatusSnapshot {
        StatusSnapshot(
            battery: BatteryStatus(rawPercentage: level, isPresent: true, isCharging: charging,
                                   isLowPowerMode: lowPower, isConnectedToPower: connectedToPower ?? charging),
            wifi: WiFiStatus(state: connection == .wifi ? .connected : .notAssociated, rssi: -53, band: band),
            connection: connection,
            volume: VolumeStatus(scalar: 0.6, isMuted: muted, deviceName: nil)
        )
    }

    private func scene(_ layout: StatusStripLayout, from status: StatusSnapshot) -> IconSceneState {
        var scene = IconPreviewScene.make(status: MenuBarStatus(snapshot: status), configuration: .standard)
        scene.statusStrip = StatusStrip(layout: layout, snapshot: status, threshold: 20)
        return scene
    }

    private func raster(_ scene: IconSceneState, dark: Bool, scale: CGFloat = 2, size: CGFloat = 24,
                        phase: ChargingEffectPhase? = nil) throws -> CGImage {
        let appearance = try XCTUnwrap(NSAppearance(named: dark ? .darkAqua : .aqua))
        let image = try XCTUnwrap(StatusStripRenderer.image(scene: scene, size: size, scale: scale,
                                                           appearance: appearance, phase: phase))
        return try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    private func data(_ image: CGImage) throws -> Data {
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    func testAllSevenLayoutsDrawDistinctMenuBarAndDockImages() throws {
        for dark in [false, true] {
            var menu = Set<Data>(), dock = Set<Data>()
            for layout in StatusStripLayout.allCases {
                let scene = scene(layout, from: snapshot())
                let strip = try XCTUnwrap(scene.statusStrip)
                for scale in [CGFloat(1), 2] {
                    let image = try raster(scene, dark: dark, scale: scale)
                    XCTAssertEqual(image.width, Int(StatusStripRenderer.width(strip) * scale))
                    XCTAssertEqual(image.height, Int(24 * scale))
                    let bytes = try XCTUnwrap(image.dataProvider?.data) as Data
                    XCTAssertTrue(bytes.contains { $0 != 0 }, "\(layout) must not be blank")
                    if scale == 2 { menu.insert(try data(image)) }
                }
                let tile = try XCTUnwrap(DockIconRenderer.tileImage(scene: scene, backgroundStyle: dark ? .dark : .light,
                                                                    pixelLength: 128))
                dock.insert(try data(tile))
            }
            XCTAssertEqual(menu.count, 7)
            XCTAssertEqual(dock.count, 7)
        }
    }

    func testAlertsExpandOnlyForKnownLowBatteryOrOffline() {
        let normal = StatusStrip(layout: .alerts, snapshot: snapshot(), threshold: 20)
        let unknown = StatusStrip(layout: .alerts, snapshot: .placeholder, threshold: 20)
        let low = StatusStrip(layout: .alerts, snapshot: snapshot(level: 20), threshold: 20)
        let offline = StatusStrip(layout: .alerts, snapshot: snapshot(connection: .offline), threshold: 20)
        XCTAssertFalse(normal.hasAlert)
        XCTAssertFalse(unknown.hasAlert)
        XCTAssertTrue(low.lowBattery)
        XCTAssertEqual(offline.link, .offline)
        XCTAssertEqual(StatusStripRenderer.width(normal), StatusStripRenderer.width(unknown))
        XCTAssertGreaterThan(StatusStripRenderer.width(low), StatusStripRenderer.width(normal))
        XCTAssertEqual(StatusStripRenderer.width(low), StatusStripRenderer.width(offline))
    }

    func testOnlyConnectionLayoutProjectsBand() {
        for layout in StatusStripLayout.allCases {
            let five = StatusStrip(layout: layout, snapshot: snapshot(), threshold: 20)
            let six = StatusStrip(layout: layout, snapshot: snapshot(band: .sixGHz), threshold: 20)
            if layout == .connection {
                XCTAssertEqual(five.link, .wifi("5G"))
                XCTAssertEqual(six.link, .wifi("6G"))
            } else { XCTAssertEqual(five, six) }
        }
    }

    func testOnlyTheDesignatedLayoutsDrawCapsuleBackgrounds() throws {
        for dark in [false, true] {
            for layout in StatusStripLayout.allCases {
                let normal = try PixelBuffer(image: raster(scene(layout, from: snapshot()), dark: dark))
                let warning = try PixelBuffer(image: raster(scene(layout, from: snapshot(level: 12, charging: false,
                                                                                         connection: .offline)), dark: dark))
                let x: Int = switch layout {
                case .capsule: 50
                case .connection: 79
                case .alerts: 12
                default: 16
                }
                let showsCapsule = layout == .capsule || layout == .unified || layout == .connection
                // Sample inside the top padding of each capsule, above the glyphs.
                XCTAssertEqual(normal.rgba(x: x * 2, y: 6).alpha > 16, showsCapsule, "\(layout) normal")
                XCTAssertEqual(warning.rgba(x: x * 2, y: 6).alpha > 16, showsCapsule || layout == .alerts,
                               "\(layout) alert")
                XCTAssertEqual(normal.rgba(x: 32, y: 6).alpha > 16, layout == .unified, "\(layout) outer frame")
            }
        }
    }

    func testReadableNetworkAndVolumeInkShareTheCenterlineWithoutTouching() throws {
        for (size, scale) in [(CGFloat(24), CGFloat(1)), (24, 2), (16, 2)] {
            for layout in StatusStripLayout.allCases where layout != .alerts {
                for link in [NetworkConnection.wifi, .offline] {
                    let scene = scene(layout, from: snapshot(connection: link))
                    let width = StatusStripRenderer.width(try XCTUnwrap(scene.statusStrip))
                    let networkX: CGFloat = switch layout {
                    case .unified: 70
                    case .connection: link == .wifi ? 66.5 : 79.5
                    default: 13
                    }
                    let pixels = try PixelBuffer(image: raster(scene, dark: true, scale: scale, size: size))
                    func ink(x: CGFloat, width: CGFloat) throws -> CGRect {
                        let bounds = try XCTUnwrap(pixels.alphaBounds(
                            inSVGRect: CGRect(x: x, y: 0, width: width, height: 24),
                            size: StatusIconGeometry.canvas.width, scale: scale * size / 24, minimumAlpha: 128
                        ), "\(layout), \(link), size \(size), scale \(scale)")
                        return CGRect(x: bounds.minX, y: bounds.minY,
                                      width: bounds.maxX - bounds.minX, height: bounds.maxY - bounds.minY)
                    }
                    let network = try ink(x: networkX - 10, width: 20)
                    let speaker = try ink(x: width - 42, width: 18)
                    let meter = try ink(x: width - 22, width: 18)
                    XCTAssertGreaterThanOrEqual(network.width, 10)
                    XCTAssertGreaterThanOrEqual(speaker.width, 9, "\(layout), \(link), \(size)@\(scale)")
                    XCTAssertEqual(network.midY, 12, accuracy: 1.5)
                    XCTAssertEqual(speaker.midY, meter.midY, accuracy: 1.5)
                    XCTAssertGreaterThanOrEqual(meter.minX - speaker.maxX, 3)
                    XCTAssertEqual(pixels.maximumAlphaOnEdges, 0)
                }
            }
        }
    }

    func testMuteChangesTheSpeakerWithoutChangingLayoutWidth() throws {
        for layout in StatusStripLayout.allCases where layout != .alerts {
            let playing = try raster(scene(layout, from: snapshot()), dark: false)
            let muted = try raster(scene(layout, from: snapshot(muted: true)), dark: false)
            XCTAssertEqual(playing.width, muted.width)
            let speaker = CGRect(x: playing.width - 84, y: 0, width: 36, height: playing.height)
            XCTAssertNotEqual(try data(XCTUnwrap(playing.cropping(to: speaker))),
                              try data(XCTUnwrap(muted.cropping(to: speaker))), "\(layout)")
        }
        let hidden = StatusStrip(layout: .divider, snapshot: snapshot(muted: true), threshold: 20, showsVolume: false)
        XCTAssertNil(hidden.audio)
        XCTAssertFalse(hidden.muted)
    }

    func testPlainSingleMetricAndFooterStillPaintWhenTheirValuesChange() throws {
        let strip = StatusStrip(layout: .unified, snapshot: snapshot(), threshold: 20, usesSystemBattery: false)
        func sample(_ primary: Double, footer: Double) -> IconSceneState {
            IconSceneState(outerRing: OuterRingState(segments: [.init(progress: primary, color: .primary)], gap: .closed),
                           footer: .arc(.init(progress: footer, color: .primary)),
                           bottomIndicatorSource: .metric, statusStrip: strip)
        }
        let base = try data(raster(sample(0.2, footer: 0.2), dark: false))
        XCTAssertNotEqual(base, try data(raster(sample(0.8, footer: 0.2), dark: false)))
        XCTAssertNotEqual(base, try data(raster(sample(0.2, footer: 0.8), dark: false)))
    }

    func testMetricReadoutChangesPixelsEvenWhenTheSameDotsStayFilled() throws {
        let strip = StatusStrip(layout: .unified, snapshot: snapshot(), threshold: 20, footerMetric: .cpuUsage)
        func scene(reading: String) -> IconSceneState {
            IconSceneState(footer: .dots(.init(count: 4, activeCount: 2, color: .primary, metricReading: reading)),
                           bottomIndicatorSource: .metric, statusStrip: strip)
        }
        let first = scene(reading: "41%")
        let second = scene(reading: "42%")
        XCTAssertNotEqual(try data(raster(first, dark: false)), try data(raster(second, dark: false)))
        let dockA = try XCTUnwrap(DockIconRenderer.tileImage(scene: first, backgroundStyle: .light, pixelLength: 128))
        let dockB = try XCTUnwrap(DockIconRenderer.tileImage(scene: second, backgroundStyle: .light, pixelLength: 128))
        XCTAssertNotEqual(try data(dockA), try data(dockB))
    }

    func testAnimationsRespectTheSurfaceSettingInAllLayouts() throws {
        let first = ChargingEffectPhase(step: 3, stepsPerCycle: 40, kind: .steady)
        let later = ChargingEffectPhase(step: 18, stepsPerCycle: 40, kind: .steady)
        for layout in StatusStripLayout.allCases {
            let scene = scene(layout, from: snapshot())
            XCTAssertNotEqual(try data(raster(scene, dark: false, phase: first)),
                              try data(raster(scene, dark: false, phase: later)), "\(layout)")
            let disabled = scene.withChargingEffectEnabled(false)
            XCTAssertEqual(try data(raster(disabled, dark: false, phase: first)),
                           try data(raster(disabled, dark: false, phase: later)), "\(layout)")
        }
    }

    func testChargingBoltGrowsWithTopMarkerScaleAndPulsesWithoutMovingReadout() throws {
        func chargingScene(_ scale: Double, heartbeat: Bool = true) -> IconSceneState {
            let configuration = IconPresentationConfiguration(
                battery: BatteryIconOptions(showsChargingBoltHeartbeat: heartbeat, textScale: scale * 1.8),
                connection: .standard, volume: .standard, bluetooth: .standard
            )
            var scene = IconPreviewScene.make(status: MenuBarStatus(snapshot: snapshot()), configuration: configuration)
            scene.statusStrip = StatusStrip(layout: .divider, snapshot: snapshot(), threshold: 20)
            return scene
        }

        let bolt = CGRect(x: 62, y: 0, width: 15, height: 17)
        let digits = CGRect(x: 33, y: 4, width: 28, height: 12)
        let peak = ChargingEffectPhase(step: 10, stepsPerCycle: 40, kind: .steady)
        let trough = ChargingEffectPhase(step: 30, stepsPerCycle: 40, kind: .steady)
        func pixels(_ scene: IconSceneState, phase: ChargingEffectPhase? = nil) throws -> PixelBuffer {
            try PixelBuffer(image: raster(scene, dark: false, phase: phase))
        }
        func ink(_ frame: PixelBuffer, in rect: CGRect) -> Int {
            frame.alphaSum(inSVGRect: rect, size: StatusIconGeometry.canvas.width, scale: 2)
        }
        let small = try pixels(chargingScene(0.9))
        let large = try pixels(chargingScene(1.2))
        XCTAssertGreaterThan(ink(large, in: bolt), ink(small, in: bolt) * 3 / 2)
        let expanded = try pixels(chargingScene(1.2), phase: peak)
        let contracted = try pixels(chargingScene(1.2), phase: trough)
        XCTAssertGreaterThan(ink(expanded, in: bolt), ink(contracted, in: bolt) * 6 / 5)
        XCTAssertEqual(ink(expanded, in: digits), ink(contracted, in: digits))
        XCTAssertEqual(expanded.maximumAlphaOnEdges, 0)
        let still = chargingScene(1.2, heartbeat: false)
        XCTAssertEqual(ink(try pixels(still, phase: peak), in: bolt), ink(try pixels(still, phase: trough), in: bolt))
    }

    func testAllVisibleMetersGetThickerAndStayInsideTheMenuBar() throws {
        for layout in StatusStripLayout.allCases where layout != .alerts {
            for style in VolumeDisplayStyle.allCases {
                for (size, scale) in [(CGFloat(16), CGFloat(1)), (16, 2), (24, 1), (24, 2)] {
                    var batteryInk = [Int](), audioInk = [Int]()
                    for stroke in RingStrokeStyle.allCases {
                        let scene = meterScene(layout, style: style, stroke: stroke)
                        let width = StatusStripRenderer.width(try XCTUnwrap(scene.statusStrip))
                        let image = try PixelBuffer(image: raster(scene, dark: false, scale: scale, size: size))
                        let expectedWidth = Int(ceil(width * size / 24 * scale))
                        XCTAssertEqual(image.width, expectedWidth, "\(layout), \(size)@\(scale)")
                        XCTAssertEqual(image.height, Int(size * scale), "\(layout), \(size)@\(scale)")
                        let trackX: CGFloat = layout == .connection ? 8 : layout == .unified ? 10 : 33
                        let batteryTrack = CGRect(x: trackX, y: 16.5, width: 24, height: 5.5)
                        let audioTrack = CGRect(x: width - 22, y: 4, width: 20, height: 16)
                        func ink(_ rect: CGRect) -> Int {
                            image.alphaSum(inSVGRect: rect, size: StatusIconGeometry.canvas.width, scale: size / 24 * scale)
                        }
                        batteryInk.append(ink(batteryTrack))
                        audioInk.append(ink(audioTrack))
                        XCTAssertEqual(image.maximumAlphaOnEdges, 0, "\(layout), \(style), \(stroke), \(size)@\(scale)")
                    }
                    for (meter, ink) in [("battery", batteryInk), ("audio", audioInk)] {
                        let label = "\(meter), \(layout), \(style), \(size)@\(scale), ink: \(ink)"
                        XCTAssertGreaterThan(ink[1], ink[0] * 11 / 10, label)
                        XCTAssertGreaterThan(ink[2], ink[1] * 11 / 10, label)
                    }
                }
            }
        }
    }

    func testVerticalVolumeFillsFromBottomAndMuteClearsIt() throws {
        let playing = meterScene(.divider, style: .verticalBar, stroke: .bold)
        let muted = meterScene(.divider, style: .verticalBar, stroke: .bold, muted: true)
        let horizontal = meterScene(.divider, style: .arc, stroke: .bold)
        let w = StatusStripRenderer.width(try XCTUnwrap(playing.statusStrip))
        func ink(_ scene: IconSceneState, y: CGFloat) throws -> Int {
            let image = try PixelBuffer(image: raster(scene, dark: false))
            return image.alphaSum(inSVGRect: CGRect(x: w - 22, y: y, width: 20, height: 3),
                                  size: StatusIconGeometry.canvas.width, scale: 2)
        }
        XCTAssertGreaterThan(try ink(playing, y: 15), try ink(playing, y: 6) * 2)
        XCTAssertGreaterThan(try ink(playing, y: 15), try ink(muted, y: 15) * 2)
        XCTAssertEqual(try ink(playing, y: 6), try ink(muted, y: 6))
        XCTAssertFalse(playing.isVolumeValueChange(from: horizontal))
    }

    private func meterScene(_ layout: StatusStripLayout, style: VolumeDisplayStyle, stroke: RingStrokeStyle,
                            muted: Bool = false) -> IconSceneState {
        let status = snapshot(charging: false, muted: muted)
        let configuration = IconPresentationConfiguration(
            battery: BatteryIconOptions(ringStrokeScale: stroke.scale), connection: .standard,
            volume: VolumeIconOptions(displayStyle: style, ringStrokeScale: stroke.scale), bluetooth: .standard
        )
        var scene = IconPreviewScene.make(status: MenuBarStatus(snapshot: status), configuration: configuration)
        scene.statusStrip = StatusStrip(layout: layout, snapshot: status, threshold: 20)
        return scene
    }

    func testWritesOptionalMeterSheet() throws {
        guard let path = ProcessInfo.processInfo.environment["STATUS_TRIO_METER_SHEET"] else {
            throw XCTSkip("Set STATUS_TRIO_METER_SHEET to write the meter sheet.")
        }
        let canvas = try SheetCanvas.makeContext(width: 780, height: 322, scale: 2)
        let title = SheetCanvas.font("PingFangSC-Semibold", 21)
        let label = SheetCanvas.font("PingFangSC-Regular", 14)
        canvas.setFillColor(SheetCanvas.color(0.96, 0.97, 0.98))
        canvas.fill(CGRect(x: 0, y: 0, width: 780, height: 322))
        SheetCanvas.draw("Status Trio DIY  /  音量量表", font: title, color: SheetCanvas.ink,
                         baseline: 280, x: 26, in: canvas)
        let localization = Localization()
        let styleKeys: [LocalizationKey] = [.settingsAudioIndicatorStyleDots, .settingsAudioIndicatorStyleArc,
                                            .settingsAudioIndicatorStyleVerticalBar]
        let strokeKeys: [LocalizationKey] = [.settingsRingStrokeStyleLight, .settingsRingStrokeStyleRegular,
                                             .settingsRingStrokeStyleBold]
        for (column, style) in VolumeDisplayStyle.allCases.enumerated() {
            let x = CGFloat(118 + 221 * column)
            let heading = localization.string(styleKeys[column], language: .simplifiedChinese)
            SheetCanvas.draw(heading, font: label, color: SheetCanvas.mutedInk, baseline: 242, x: x, in: canvas)
            for (row, stroke) in RingStrokeStyle.allCases.enumerated() {
                let y = CGFloat(168 - 70 * row)
                if column == 0 {
                    let text = localization.string(strokeKeys[row], language: .simplifiedChinese)
                    SheetCanvas.draw(text, font: label, color: SheetCanvas.ink, baseline: y + 24, x: 26, in: canvas)
                }
                let sample = meterScene(.unified, style: style, stroke: stroke)
                let image = try raster(sample, dark: true, size: 32)
                let panel = CGRect(x: x, y: y, width: 195, height: 58)
                canvas.setFillColor(CGColor(gray: 0.10, alpha: 1))
                canvas.addPath(SheetCanvas.roundedRect(panel, cornerRadius: 6))
                canvas.fillPath()
                let width = CGFloat(image.width) / 2
                canvas.draw(image, in: CGRect(x: panel.midX - width / 2, y: panel.midY - 16, width: width, height: 32))
            }
        }
        try SheetCanvas.pngData(canvas).write(to: URL(fileURLWithPath: path))
    }

    func testWritesOptionalLayoutSheet() throws {
        guard let path = ProcessInfo.processInfo.environment["STATUS_TRIO_LAYOUT_SHEET"] else {
            throw XCTSkip("Set STATUS_TRIO_LAYOUT_SHEET to write the layout sheet.")
        }
        let sheetWidth: CGFloat = 842
        let sampleWidth: CGFloat = 162
        let canvas = try SheetCanvas.makeContext(width: sheetWidth, height: 504, scale: 2)
        let localization = Localization()
        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 15, nil)
        let heading = CGColor(gray: 0.12, alpha: 1)
        canvas.setFillColor(CGColor(gray: 0.975, alpha: 1))
        canvas.fill(CGRect(x: 0, y: 0, width: sheetWidth, height: 504))
        for (i, layout) in StatusStripLayout.allCases.enumerated() {
            let y = CGFloat(404 - i * 62)
            let normal = scene(layout, from: snapshot())
            let warning = scene(layout, from: snapshot(level: 12, charging: false, connection: .offline))
            let muted = scene(layout, from: snapshot(muted: true))
            let title = localization.string(layout.titleKey, language: .simplifiedChinese)
            SheetCanvas.draw(title, font: font, color: heading, topLeft: CGPoint(x: 16, y: y + 33), in: canvas)
            for (j, sample) in [(normal, false), (normal, true), (warning, true), (muted, false)].enumerated() {
                let x = CGFloat(132 + j * 174)
                canvas.setFillColor(CGColor(gray: sample.1 ? 0.08 : 0.91, alpha: 1))
                canvas.fill(CGRect(x: x, y: y, width: sampleWidth, height: 44))
                let image = try raster(sample.0, dark: sample.1)
                let width = CGFloat(image.width) / 2
                canvas.draw(image, in: CGRect(x: x + (sampleWidth - width) / 2, y: y + 10, width: width, height: 24))
            }
        }
        for (x, title) in [(16, "Status Trio DIY"), (142, "Light"), (316, "Dark"), (490, "Low + offline"), (664, "Muted")] {
            SheetCanvas.draw(title, font: font, color: heading, topLeft: CGPoint(x: x, y: 477), in: canvas)
        }
        try SheetCanvas.pngData(canvas).write(to: URL(fileURLWithPath: path))
    }

    func testWritesOptionalBatteryColorsSheet() throws {
        guard let path = ProcessInfo.processInfo.environment["STATUS_TRIO_BATTERY_COLORS_SHEET"] else {
            throw XCTSkip("Set STATUS_TRIO_BATTERY_COLORS_SHEET to write the battery colors sheet.")
        }
        let samples: [(LocalizationKey, StatusSnapshot, IconColorRole)] = [
            (.settingsBatteryColorsDischarging, snapshot(charging: false), .discharging),
            (.settingsBatteryColorsCharging, snapshot(), .powered),
            (.settingsBatteryColorsLowPower, snapshot(level: 46, charging: false, lowPower: true), .lowPower),
            (.settingsBatteryColorsHighPower, snapshot(charging: false, connectedToPower: true), .highPower),
            (.settingsBatteryColorsCritical, snapshot(level: 12, charging: false), .critical)
        ]
        let canvas = try SheetCanvas.makeContext(width: 580, height: 366, scale: 2)
        let localization = Localization()
        let regular = SheetCanvas.font("PingFangSC-Regular", 14)
        let semibold = SheetCanvas.font("PingFangSC-Semibold", 14)
        canvas.setFillColor(SheetCanvas.color(0.97, 0.97, 0.98))
        canvas.fill(CGRect(x: 0, y: 0, width: 580, height: 366))
        SheetCanvas.draw("Status Trio DIY", font: SheetCanvas.font("HelveticaNeue-Medium", 24),
                         color: SheetCanvas.ink, baseline: 324, x: 24, in: canvas)
        for (key, x) in [(LocalizationKey.settingsBatteryTitle, 24), (.settingsPreviewLight, 202), (.settingsPreviewDark, 390)] {
            SheetCanvas.draw(localization.string(key, language: .simplifiedChinese), font: semibold,
                             color: SheetCanvas.mutedInk, baseline: 287, x: CGFloat(x), in: canvas)
        }
        for (i, sample) in samples.enumerated() {
            let (key, status, role) = sample
            let y = CGFloat(229 - i * 51)
            let label = localization.string(key, language: .simplifiedChinese)
            SheetCanvas.draw(label, font: regular, color: SheetCanvas.ink, baseline: y + 15, x: 24, in: canvas)
            var scene = IconPreviewScene.make(snapshot: status, configuration: .standard, isHighPowerMode: role == .highPower)
            scene.statusStrip = StatusStrip(layout: .capsule, snapshot: status, threshold: 20)
            XCTAssertEqual(scene.outerRing?.segments.first?.color, role)
            for (dark, x) in [(false, CGFloat(202)), (true, 390)] {
                let panel = CGRect(x: x, y: y, width: 166, height: 40)
                canvas.setFillColor(CGColor(gray: dark ? 0.14 : 0.91, alpha: 1))
                canvas.addPath(SheetCanvas.roundedRect(panel, cornerRadius: 6))
                canvas.fillPath()
                let image = try raster(scene, dark: dark)
                let width = CGFloat(image.width) / 2
                canvas.draw(image, in: CGRect(x: panel.midX - width / 2, y: y + 8, width: width, height: 24))
            }
        }
        try SheetCanvas.pngData(canvas).write(to: URL(fileURLWithPath: path))
    }
}
