import AppKit
import SwiftUI

/// Layout and indicator controls share the same settings as the live menu bar and Dock.
struct MenuBarAppearanceSettings: View {
    @ObservedObject var store: SettingsStore
    @EnvironmentObject private var localization: Localization
    @Environment(\.displayScale) private var displayScale
    @State private var scenario: MenuBarAppearanceScenario = .normal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localization.string(.settingsMenuBarTitle), systemImage: "menubar.rectangle")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    comparison.frame(minWidth: 246)
                    controls.padding(.leading, 12).frame(width: 182)
                        .overlay(alignment: .leading) { Divider().accessibilityHidden(true) }
                }
                VStack(alignment: .leading, spacing: 12) {
                    comparison
                    Divider()
                    controls
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor).opacity(0.55)) }
        }
        .accessibilityIdentifier("appIcon.appearanceWorkbench")
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.string(.statusStripLayout)).font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            field(.iconDesignerPreviewScenario) {
                Picker(selection: $scenario) {
                    ForEach(MenuBarAppearanceScenario.allCases) { scenario in
                        Text(localization.string(scenario.titleKey)).tag(scenario)
                    }
                } label: {
                    Text(localization.string(.iconDesignerPreviewScenario))
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityIdentifier("appIcon.layoutPreviewScenario")
            }

            HStack(spacing: 5) {
                themeHeading(.settingsPreviewLight)
                themeHeading(.settingsPreviewDark)
            }
            .accessibilityHidden(true)

            ForEach(StatusStripLayout.allCases) { layout in
                layoutRow(layout)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("appIcon.statusStripLayout")
    }

    private func themeHeading(_ title: LocalizationKey) -> some View {
        Text(localization.string(title))
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }

    private func layoutRow(_ layout: StatusStripLayout) -> some View {
        let selected = store.statusStripLayout == layout
        let title = localization.string(layout.titleKey)
        let scene = MenuBarAppearancePreview.scene(layout: layout, scenario: scenario, store: store)
        return Button {
            store.statusStripLayout = layout
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(selected ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .opacity(selected ? 1 : 0)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(selected ? Color.accentColor : .primary)

                HStack(spacing: 5) {
                    thumbnail(scene, dark: false)
                    thumbnail(scene, dark: true)
                }
            }
            .padding(5)
            .background(Color.accentColor.opacity(selected ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.60) : Color(nsColor: .separatorColor).opacity(0.48))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("appIcon.statusStripLayout.\(layout.rawValue)")
    }

    private func thumbnail(_ scene: IconSceneState, dark: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(dark ? Color(white: 0.16) : Color(red: 0.92, green: 0.93, blue: 0.94))
            if let image = StatusIconPreviewCache.shared.stripImage(
                scene: scene, size: 17, scale: displayScale,
                appearance: MenuBarPreviewBackdrop.appearance(isDarkBackground: dark)
            ) {
                Image(nsImage: image).interpolation(.high)
            }
        }
        .frame(minWidth: 110, maxWidth: .infinity, minHeight: 25, maxHeight: 25)
        .accessibilityHidden(true)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(localization.string(.settingsBottomIndicatorTitle)).font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            field(.settingsBottomIndicatorSource) {
                Picker(selection: $store.bottomIndicatorSource) {
                    ForEach(BottomIndicatorSource.allCases) { source in
                        Text(localization.string(source.settingsTitleKey)).tag(source)
                    }
                } label: {
                    Text(localization.string(.settingsBottomIndicatorSource))
                }
                .labelsHidden()
                .accessibilityIdentifier("appIcon.appearanceFooterSource")
            }
            if store.bottomIndicatorSource == .metric {
                field(.settingsBottomIndicatorMetric) {
                    Picker(selection: $store.bottomIndicatorMetric) {
                        ForEach(FooterMetricChoices.groups(
                            showsTemperatures: store.hardwareTemperatureMonitoringEnabled, localization: localization
                        ), id: \.title) { group in
                            Section(group.title) {
                                ForEach(group.options) { metric in
                                    Text(localization.string(metric.titleKey)).tag(metric)
                                }
                            }
                        }
                    } label: {
                        Text(localization.string(.settingsBottomIndicatorMetric))
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("appIcon.appearanceFooterMetric")
                }
            }
            if store.bottomIndicatorSource.showsStyleOptions {
                field(.settingsAudioIndicatorStyle) {
                    choice(.settingsAudioIndicatorStyle, selection: Binding(
                        get: { store.effectiveBottomIndicatorStyle },
                        set: { store.setBottomIndicatorStyle($0) }
                    ), options: VolumeDisplayStyle.allCases, title: \.settingsTitleKey)
                    .accessibilityIdentifier("appIcon.appearanceFooterGauge")
                }
            }
            field(.settingsRingStrokeStyle) {
                choice(.settingsRingStrokeStyle, selection: $store.ringStrokeStyle,
                       options: RingStrokeStyle.allCases) { style in
                    switch style {
                    case .light: .settingsRingStrokeStyleLight
                    case .regular: .settingsRingStrokeStyleRegular
                    case .bold: .settingsRingStrokeStyleBold
                    }
                }
                .accessibilityIdentifier("appIcon.appearanceGaugeWeight")
            }
            if store.bottomIndicatorSource == .metric, store.bottomIndicatorMetric != .memoryPressure {
                readingSlider
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field<Content: View>(_ title: LocalizationKey, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(localization.string(title)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            content()
        }
    }

    private func choice<Option: Hashable & Identifiable>(
        _ label: LocalizationKey, selection: Binding<Option>, options: [Option],
        title: @escaping (Option) -> LocalizationKey
    ) -> some View {
        let picker = Picker(selection: selection) {
            ForEach(options) { option in Text(localization.string(title(option))).tag(option) }
        } label: {
            Text(localization.string(label))
        }
        .labelsHidden()
        return ViewThatFits(in: .horizontal) {
            picker.pickerStyle(.segmented).fixedSize(horizontal: true, vertical: false)
            picker.pickerStyle(.menu)
        }
    }

    private var readingSlider: some View {
        let title = localization.string(.settingsFooterMetricTextSize)
        let percent = store.footerMetricTextScale.formatted(.percent.precision(.fractionLength(0)))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text(percent).monospacedDigit().foregroundStyle(Color.accentColor)
            }
            .font(.caption.weight(.medium))
            .accessibilityHidden(true)
            Slider(value: Binding(
                get: { store.footerMetricTextScale },
                set: { store.setFooterMetricTextScaleFromSlider($0) }
            ), in: StatusStrip.metricTextScaleRange)
            .accessibilityLabel(title)
            .accessibilityValue(percent)
            .accessibilityIdentifier("appIcon.appearanceFooterMetricTextSize")
        }
    }
}

enum MenuBarAppearanceScenario: String, CaseIterable, Identifiable {
    case normal, charging, muted, lowAndOffline

    var id: Self { self }

    var titleKey: LocalizationKey {
        switch self {
        case .normal: .iconPreviewScenarioNetworkHealthy
        case .charging: .iconPreviewScenarioBatteryCharging
        case .muted: .iconPreviewScenarioVolumeMuted
        case .lowAndOffline: .statusStripPreviewLowAndOffline
        }
    }

    var snapshot: StatusSnapshot {
        let alert = self == .lowAndOffline
        return StatusSnapshot(
            battery: BatteryStatus(rawPercentage: alert ? 12 : 76, isPresent: true, isCharging: self == .charging,
                                   isLowPowerMode: false, isConnectedToPower: self == .charging),
            wifi: WiFiStatus(state: alert ? .notAssociated : .connected, rssi: alert ? nil : -54,
                             band: alert ? nil : .fiveGHz),
            connection: alert ? .offline : .wifi,
            volume: VolumeStatus(scalar: 0.72, isMuted: self == .muted, deviceName: nil)
        )
    }
}

/// Fixed examples isolate layout and appearance choices from hardware availability.
@MainActor
enum MenuBarAppearancePreview {
    static func scene(layout: StatusStripLayout, scenario: MenuBarAppearanceScenario, store: SettingsStore) -> IconSceneState {
        let snapshot = scenario.snapshot
        let source = store.bottomIndicatorSource
        let metric = source == .metric ? store.bottomIndicatorMetric : nil
        let style = store.effectiveBottomIndicatorStyle
        let stroke = store.ringStrokeStyle.scale
        // Compare the reference network glyph consistently; the pinned preview retains the live center source.
        let connection = ConnectionIconOptions(wifiScale: store.connectionIconOptions.wifiScale)
        let scene = IconPreviewScene.make(
            snapshot: snapshot,
            configuration: .init(battery: store.batteryIconOptions, connection: connection,
                                 volume: .init(displayStyle: style, ringStrokeScale: stroke),
                                 bluetooth: store.bluetoothVolumePreviewOptions),
            bottomIndicatorSource: source
        )
        let footer = if let metric {
            BottomIndicatorMetricPreview.footerBar(
                metric: metric, style: style, strokeScale: stroke,
                baseColor: metric.hardwareMetric.map { store.hardwareColor(for: $0) }
            )
        } else {
            scene.footer
        }
        return IconSceneState(
            outerRing: scene.outerRing, center: scene.center, footer: footer,
            statusColors: scene.statusColors, bluetoothIconColor: scene.bluetoothIconColor,
            bottomIndicatorSource: source,
            statusStrip: StatusStrip(
                layout: layout, snapshot: snapshot, threshold: Int(store.batteryCriticalThreshold.rounded()),
                showsVolume: source == .volume, footerMetric: metric, footerMetricTextScale: store.footerMetricTextScale
            )
        )
    }
}

enum FooterMetricChoices {
    @MainActor
    static func groups(showsTemperatures: Bool, localization: Localization) -> [(title: String, options: [BottomIndicatorMetric])] {
        [
            ("CPU", showsTemperatures ? [.cpuUsage, .cpuTemperature] : [.cpuUsage]),
            ("GPU", showsTemperatures ? [.gpuUsage, .gpuTemperature] : [.gpuUsage]),
            (localization.string(.hardwareDetailTitleMemory), [.memoryUsage, .memoryPressure]),
            (localization.string(.settingsHardwareRingGroupOther), [.batteryTemperature, .fan, .downloadSpeed, .uploadSpeed]),
        ]
    }
}

extension BottomIndicatorSource {
    var settingsTitleKey: LocalizationKey {
        switch self {
        case .volume: .settingsBottomIndicatorSourceVolume
        case .wifi: .settingsBottomIndicatorSourceWiFi
        case .battery: .settingsBottomIndicatorSourceBattery
        case .metric: .settingsBottomIndicatorSourceMetric
        case .hidden: .settingsBottomIndicatorSourceHidden
        }
    }
}

extension VolumeDisplayStyle {
    var settingsTitleKey: LocalizationKey {
        switch self {
        case .dots: .settingsAudioIndicatorStyleDots
        case .arc: .settingsAudioIndicatorStyleArc
        case .verticalBar: .settingsAudioIndicatorStyleVerticalBar
        }
    }
}
