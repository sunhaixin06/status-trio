import AppKit
import SwiftUI
import XCTest
@testable import StatusTrioCore

@MainActor
final class MenuBarAppearanceSettingsTests: XCTestCase {
    private func withStore(_ test: (SettingsStore, UserDefaults) throws -> Void) rethrows {
        let name = "MenuBarAppearanceSettingsTests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try test(SettingsStore(defaults: defaults, systemChargeLimit: { nil }), defaults)
    }

    func testSamplesKeepTheirLayoutAndDoNotMutateTheLiveSelection() throws {
        try withStore { store, _ in
            store.statusStripLayout = .inline
            store.bottomIndicatorSource = .volume
            for layout in StatusStripLayout.allCases {
                let charging = MenuBarAppearancePreview.scene(layout: layout, scenario: .charging, store: store)
                let offline = MenuBarAppearancePreview.scene(layout: layout, scenario: .lowAndOffline, store: store)
                let muted = MenuBarAppearancePreview.scene(layout: layout, scenario: .muted, store: store)
                XCTAssertEqual(charging.statusStrip?.layout, layout)
                XCTAssertEqual(charging.statusStrip?.energy, .charging)
                XCTAssertEqual(offline.statusStrip?.link, .offline)
                XCTAssertEqual(offline.statusStrip?.battery, 12)
                XCTAssertEqual(muted.statusStrip?.muted, true)
                for appearanceName: NSAppearance.Name in [.aqua, .darkAqua] {
                    let appearance = try XCTUnwrap(NSAppearance(named: appearanceName))
                    let image = try XCTUnwrap(StatusStripRenderer.image(
                        scene: charging, size: 17, scale: 2, appearance: appearance
                    ))
                    XCTAssertLessThanOrEqual(image.size.width, 110)
                }
            }
            XCTAssertEqual(store.statusStripLayout, .inline)
            XCTAssertEqual(store.bottomIndicatorSource, .volume)
        }
    }

    func testFooterControlsUseIndependentStylesAndSharedStroke() {
        withStore { store, _ in
            store.bottomIndicatorSource = .volume
            store.setBottomIndicatorStyle(.dots)
            store.bottomIndicatorSource = .battery
            store.setBottomIndicatorStyle(.arc)
            store.bottomIndicatorSource = .metric
            store.bottomIndicatorMetric = .cpuUsage
            store.setBottomIndicatorStyle(.verticalBar)
            store.ringStrokeStyle = .bold
            store.footerMetricTextScale = 1.2
            let custom = MenuBarAppearancePreview.scene(layout: .connection, scenario: .normal, store: store)
            XCTAssertEqual(custom.statusStrip?.footerMetric, .cpuUsage)
            XCTAssertEqual(custom.statusStrip?.footerMetricTextScale, 1.2)
            XCTAssertNotNil(custom.footer?.metricReading)
            if case let .arc(bar) = custom.footer {
                XCTAssertTrue(bar.isVertical)
                XCTAssertEqual(bar.strokeScale, RingStrokeStyle.bold.scale)
            } else {
                XCTFail("Expected the selected vertical metric gauge")
            }
            XCTAssertEqual(store.bottomIndicatorStyle(for: .volume), .dots)
            XCTAssertEqual(store.bottomIndicatorStyle(for: .battery), .arc)
            store.bottomIndicatorSource = .hidden
            let hidden = MenuBarAppearancePreview.scene(layout: .connection, scenario: .normal, store: store)
            XCTAssertNil(hidden.footer)
            XCTAssertNil(hidden.statusStrip?.footerMetric)
        }
    }

    func testWorkbenchHostsAtDefaultAndMinimumPaneWidthsWithoutAWindow() {
        withStore { store, defaults in
            store.bottomIndicatorSource = .metric
            store.bottomIndicatorMetric = .cpuUsage
            for language in ["zh-Hans", "en", "de", "ar"] {
                let localization = Localization(defaults: defaults, preferredLanguages: [language])
                for windowWidth in [SettingsView.minimumWidth, SettingsView.width] {
                    let width = windowWidth - SettingsView.sidebarWidth - 2 * SettingsMetrics.pageMargin
                    let view = MenuBarAppearanceSettings(store: store)
                        .environmentObject(localization)
                        .frame(width: width)
                    let hosting = NSHostingView(rootView: view)
                    hosting.frame = NSRect(x: 0, y: 0, width: width, height: 650)
                    hosting.layoutSubtreeIfNeeded()
                    XCTAssertEqual(hosting.fittingSize.width, width, accuracy: 1, language)
                    XCTAssertGreaterThan(hosting.fittingSize.height, 180, language)
                }
            }
        }
    }
}
