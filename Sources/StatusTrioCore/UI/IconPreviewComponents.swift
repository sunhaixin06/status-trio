import AppKit
import SwiftUI

/// The single mapping entry point shared by settings and guide artwork.
@MainActor
enum IconPreviewScene {
    static func make(
        snapshot: StatusSnapshot,
        configuration: IconPresentationConfiguration,
        inputSource: InputSourceDescriptor? = nil,
        systemPower: SystemPowerSample? = nil,
        isHighPowerMode: Bool = false,
        bottomIndicatorSource: BottomIndicatorSource = .volume
    ) -> IconSceneState {
        var inputs = IconPresentationResourceResolver.inputs(
            snapshot: snapshot,
            inputSource: inputSource,
            systemPower: systemPower,
            isHighPowerMode: isHighPowerMode
        )
        inputs.bottomIndicatorSource = bottomIndicatorSource
        return IconPresentationMapper.scene(
            inputs: inputs,
            configuration: configuration
        )
    }

    static func make(
        status: MenuBarStatus,
        configuration: IconPresentationConfiguration,
        inputSource: InputSourceDescriptor? = nil,
        systemPower: SystemPowerSample? = nil,
        isHighPowerMode: Bool = false,
        bottomIndicatorSource: BottomIndicatorSource = .volume
    ) -> IconSceneState {
        make(
            snapshot: snapshot(from: status),
            configuration: configuration,
            inputSource: inputSource,
            systemPower: systemPower,
            isHighPowerMode: isHighPowerMode,
            bottomIndicatorSource: bottomIndicatorSource
        )
    }

    static func snapshot(from status: MenuBarStatus) -> StatusSnapshot {
        StatusSnapshot(
            battery: status.battery,
            wifi: status.wifi,
            connection: status.connection,
            volume: VolumeStatus(
                scalar: status.volume.scalar,
                isMuted: status.volume.isMuted,
                deviceName: status.volume.deviceName,
                currentDevice: status.volume.currentDevice
            )
        )
    }
}

/// Reusable menu bar simulation used by Settings and the icon guide.
struct MenuBarPreviewBar<TrailingAccessory: View>: View {
    let status: MenuBarStatus
    var iconSize: CGFloat = 24
    var batteryOptions: BatteryIconOptions = .standard
    var connectionOptions: ConnectionIconOptions = .standard
    var volumeOptions: VolumeIconOptions = .standard
    var bluetoothAudioOptions: BluetoothAudioIconOptions = .standard
    var isDarkBackground = true
    var phase: ChargingEffectPhase?
    var showsChargingEffect = true
    var highlightedPart: IconGuidePart?
    var highlightOpacity: Double = 1
    /// Live input source for previews that mirror the current centre-slot
    /// choice; static guide artwork leaves it `nil`.
    var inputSource: InputSourceDescriptor?
    /// The live High Power Mode state, so a preview can show its ring colour.
    var isHighPowerMode = false
    /// The bottom indicator source/style, so the settings preview reflects the
    /// chosen quantity (volume / Wi-Fi / battery / hardware metric) instead of
    /// always drawing the volume bar.
    var bottomIndicatorSource: BottomIndicatorSource = .volume
    var bottomIndicatorMetric: HardwareMonitorMetric = .cpuUsage
    var bottomIndicatorMetricColor: IconRGBA? = nil
    var bottomIndicatorStyle: VolumeDisplayStyle? = nil
    var layout: StatusStripLayout = .unified
    var wifiBand: WiFiFrequencyBand? = nil
    var resolvedScene: IconSceneState? = nil
    /// Rendered after `rightContext` inside the same `HStack`, so a caller's
    /// control takes part in the bar's standard 14 pt element spacing instead of
    /// needing a reserved trailing inset that its localized width cannot match.
    var trailingAccessory: () -> TrailingAccessory

    var scene: IconSceneState {
        if let resolvedScene { return resolvedScene }
        let base = IconPreviewScene.make(
            status: status,
            configuration: IconPresentationConfiguration(
                battery: batteryOptions,
                connection: connectionOptions,
                volume: VolumeIconOptions(
                    displayStyle: bottomIndicatorStyle ?? volumeOptions.displayStyle,
                    ringStrokeScale: volumeOptions.ringStrokeScale),
                bluetooth: bluetoothAudioOptions
            ),
            inputSource: inputSource,
            isHighPowerMode: isHighPowerMode,
            bottomIndicatorSource: bottomIndicatorSource
        )
        let resolved: IconSceneState
        if bottomIndicatorSource == .metric {
            // The legacy preview mapper has no hardware samples; draw the metric
            // bar from the representative helper over the same ring + centre.
            let style = bottomIndicatorStyle ?? volumeOptions.displayStyle
            resolved = IconSceneState(
                outerRing: base.outerRing,
                center: base.center,
                footer: BottomIndicatorMetricPreview.footerBar(
                    metric: bottomIndicatorMetric,
                    style: style,
                    strokeScale: volumeOptions.ringStrokeScale,
                    baseColor: bottomIndicatorMetricColor),
                statusColors: base.statusColors,
                bluetoothIconColor: base.bluetoothIconColor,
                bottomIndicatorSource: .metric
            )
        } else {
            resolved = base
        }
        var scene = resolved.withChargingEffectEnabled(showsChargingEffect)
        scene.statusStrip = StatusStrip(layout: layout, snapshot: status.stripSnapshot(band: wifiBand),
                                       threshold: batteryOptions.criticalThreshold,
                                       prioritizesNetworkErrors: connectionOptions.prioritizesNetworkErrors,
                                       showsVolume: scene.bottomIndicatorSource == .volume,
                                       footerMetric: scene.bottomIndicatorSource == .metric ? bottomIndicatorMetric : nil)
        return scene
    }

    init(
        status: MenuBarStatus,
        iconSize: CGFloat = 24,
        batteryOptions: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        isDarkBackground: Bool = true,
        highlightedPart: IconGuidePart? = nil,
        highlightOpacity: Double = 1,
        phase: ChargingEffectPhase? = nil,
        showsChargingEffect: Bool = true,
        inputSource: InputSourceDescriptor? = nil,
        isHighPowerMode: Bool = false,
        bottomIndicatorSource: BottomIndicatorSource = .volume,
        bottomIndicatorMetric: HardwareMonitorMetric = .cpuUsage,
        bottomIndicatorMetricColor: IconRGBA? = nil,
        bottomIndicatorStyle: VolumeDisplayStyle? = nil,
        layout: StatusStripLayout = .unified,
        wifiBand: WiFiFrequencyBand? = nil,
        resolvedScene: IconSceneState? = nil,
        @ViewBuilder trailingAccessory: @escaping () -> TrailingAccessory
    ) {
        self.status = status
        self.iconSize = iconSize
        self.batteryOptions = batteryOptions
        self.connectionOptions = connectionOptions
        self.volumeOptions = volumeOptions
        self.bluetoothAudioOptions = bluetoothAudioOptions
        self.isDarkBackground = isDarkBackground
        self.highlightedPart = highlightedPart
        self.highlightOpacity = highlightOpacity
        self.phase = phase
        self.showsChargingEffect = showsChargingEffect
        self.inputSource = inputSource
        self.isHighPowerMode = isHighPowerMode
        self.bottomIndicatorSource = bottomIndicatorSource
        self.bottomIndicatorMetric = bottomIndicatorMetric
        self.bottomIndicatorMetricColor = bottomIndicatorMetricColor
        self.bottomIndicatorStyle = bottomIndicatorStyle
        self.layout = layout
        self.wifiBand = wifiBand
        self.resolvedScene = resolvedScene
        self.trailingAccessory = trailingAccessory
    }

    var body: some View {
        ZStack {
            backdrop

            HStack(spacing: 14) {
                leftContext

                Spacer(minLength: 16)

                ZStack {
                    Image(nsImage: StatusIconPreviewCache.shared.stripImage(
                        scene: scene,
                        size: iconSize,
                        scale: NSScreen.main?.backingScaleFactor ?? 2,
                        appearance: NSAppearance(
                            named: isDarkBackground ? .darkAqua : .aqua
                        ),
                        phase: phase
                    ) ?? NSImage(size: NSSize(width: iconSize, height: iconSize)))

                    if let highlightedPart {
                        StatusIconPartHighlight(
                            part: highlightedPart,
                            lineWidth: max(2.5, iconSize * 0.075)
                        )
                        .frame(width: min(104, iconSize * 4), height: min(28, iconSize))
                        .opacity(highlightOpacity)
                    }
                }
                .accessibilityHidden(true)

                rightContext

                // The no-accessory initializer has to stay layout-neutral on
                // every supported macOS release, and a stack's spacing for
                // `EmptyView` is not a documented guarantee, so the `EmptyView`
                // specialization contributes no stack child at all.
                if TrailingAccessory.self != EmptyView.self {
                    trailingAccessory()
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 40)
    }

    private var backdrop: some View {
        MenuBarPreviewBackdrop(isDarkBackground: isDarkBackground, cornerRadius: 10)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isDarkBackground
                            ? Color.white.opacity(0.12)
                            : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    }

    private var leftContext: some View {
        HStack(spacing: 6) {
            Image(systemName: "apple.logo")
                .font(.system(size: 12, weight: .medium))
            Text(verbatim: "Finder")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(
            isDarkBackground
                ? Color.white.opacity(0.75)
                : Color.black.opacity(0.75)
        )
    }

    private var rightContext: some View {
        HStack(spacing: 6) {
            Image(systemName: "switch.2")
                .font(.system(size: 10))
            Text(verbatim: "9:41")
                .font(.system(size: 12, weight: .medium, design: .rounded))
        }
        .foregroundStyle(
            isDarkBackground
                ? Color.white.opacity(0.65)
                : Color.black.opacity(0.65)
        )
    }
}

/// A bar with no trailing accessory, for callers such as the icon guide that
/// only simulate the menu bar itself.
extension MenuBarPreviewBar where TrailingAccessory == EmptyView {
    init(
        status: MenuBarStatus,
        iconSize: CGFloat = 24,
        batteryOptions: BatteryIconOptions = .standard,
        connectionOptions: ConnectionIconOptions = .standard,
        volumeOptions: VolumeIconOptions = .standard,
        bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
        isDarkBackground: Bool = true,
        highlightedPart: IconGuidePart? = nil,
        highlightOpacity: Double = 1,
        phase: ChargingEffectPhase? = nil,
        showsChargingEffect: Bool = true,
        inputSource: InputSourceDescriptor? = nil
    ) {
        self.init(
            status: status,
            iconSize: iconSize,
            batteryOptions: batteryOptions,
            connectionOptions: connectionOptions,
            volumeOptions: volumeOptions,
            bluetoothAudioOptions: bluetoothAudioOptions,
            isDarkBackground: isDarkBackground,
            highlightedPart: highlightedPart,
            highlightOpacity: highlightOpacity,
            phase: phase,
            showsChargingEffect: showsChargingEffect,
            inputSource: inputSource,
            trailingAccessory: { EmptyView() }
        )
    }
}

/// Reusable Dock simulation with the real Dock icon artwork centered among
/// native macOS app icons.
struct DockPreviewBar: View {
    let status: MenuBarStatus
    var batteryOptions: BatteryIconOptions = .standard
    var connectionOptions: ConnectionIconOptions = .standard
    var volumeOptions: VolumeIconOptions = .standard
    var bluetoothAudioOptions: BluetoothAudioIconOptions = .standard
    var backgroundStyle: DockIconBackgroundStyle = .dark
    var isDarkBackground = true
    var statusIconSize: CGFloat = 56
    var highlightedPart: IconGuidePart?
    var highlightOpacity: Double = 1
    var inputSource: InputSourceDescriptor? = nil

    var body: some View {
        HStack(spacing: 12) {
            MacAppIcon(
                bundleIdentifier: "com.apple.finder",
                fallbackSymbol: "face.smiling.fill",
                size: statusIconSize * 0.64
            )
            MacAppIcon(
                bundleIdentifier: "com.apple.Safari",
                fallbackSymbol: "safari.fill",
                size: statusIconSize * 0.64
            )

            DockIconTile(
                status: status,
                batteryOptions: batteryOptions,
                connectionOptions: connectionOptions,
                volumeOptions: volumeOptions,
                backgroundStyle: backgroundStyle,
                size: statusIconSize,
                highlightedPart: highlightedPart,
                highlightOpacity: highlightOpacity,
                inputSource: inputSource
            )

            MacAppIcon(
                bundleIdentifier: "com.apple.MobileSMS",
                fallbackSymbol: "message.fill",
                size: statusIconSize * 0.64
            )
            MacAppIcon(
                bundleIdentifier: "com.apple.mail",
                fallbackSymbol: "envelope.fill",
                size: statusIconSize * 0.64
            )
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    isDarkBackground
                        ? Color.black.opacity(0.42)
                        : Color.white.opacity(0.62)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isDarkBackground
                        ? Color.white.opacity(0.16)
                        : Color.black.opacity(0.10),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 3)
    }
}

private struct MacAppIcon: View {
    let bundleIdentifier: String
    let fallbackSymbol: String
    let size: CGFloat

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: fallbackSymbol)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.18)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [
                                Color.accentColor,
                                Color.accentColor.opacity(0.62)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.18), radius: 2, x: 0, y: 1)
        .accessibilityHidden(true)
    }

    private var icon: NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Real Dock artwork at an arbitrary preview size.
struct DockIconTile: View {
    let status: MenuBarStatus
    var layout: StatusStripLayout = .unified
    var batteryOptions: BatteryIconOptions = .standard
    var connectionOptions: ConnectionIconOptions = .standard
    var volumeOptions: VolumeIconOptions = .standard
    var bluetoothAudioOptions: BluetoothAudioIconOptions = .standard
    var backgroundStyle: DockIconBackgroundStyle = .dark
    var size: CGFloat = 44
    var highlightedPart: IconGuidePart?
    var highlightOpacity: Double = 1
    /// Live input source for previews that mirror the current centre-slot
    /// choice; static guide artwork leaves it `nil`.
    var inputSource: InputSourceDescriptor? = nil
    /// Static power sample so the guide can illustrate the power centre slot.
    var systemPower: SystemPowerSample? = nil
    /// Injected by tests; the app shares one bounded cache.
    var previewCache: DockIconPreviewCache? = nil
    var wifiBand: WiFiFrequencyBand? = nil
    var resolvedScene: IconSceneState? = nil

    /// The raster length this tile's on-screen size needs, never the Dock's.
    var pixelLength: Int {
        DockIconPreviewMetrics.pixelLength(forPointSize: size)
    }

    /// What the tile draws, identified exactly like the Dock path identifies its
    /// own rasters. A body evaluation only looks this up.
    @MainActor
    var renderKey: DockIconRenderKey {
        DockIconRenderKey(
            scene: previewScene,
            backgroundStyle: backgroundStyle,
            pixelLength: pixelLength
        )
    }

    @MainActor
    private var previewScene: IconSceneState {
        if let resolvedScene { return resolvedScene }
        var scene = IconPreviewScene.make(
            status: status,
            configuration: IconPresentationConfiguration(
                battery: batteryOptions,
                connection: connectionOptions,
                volume: volumeOptions,
                bluetooth: bluetoothAudioOptions
            ),
            inputSource: inputSource,
            systemPower: systemPower
        )
        scene.statusStrip = StatusStrip(layout: layout, snapshot: status.stripSnapshot(band: wifiBand),
                                       threshold: batteryOptions.criticalThreshold,
                                       prioritizesNetworkErrors: connectionOptions.prioritizesNetworkErrors,
                                       showsVolume: scene.bottomIndicatorSource == .volume)
        return scene
    }

    /// The single place this tile resolves its bitmap.
    @MainActor
    var previewImage: NSImage? {
        let cache = previewCache ?? DockIconPreviewCache.shared
        return cache.image(for: renderKey) {
            DockIconRenderer.image(
                scene: previewScene,
                backgroundStyle: backgroundStyle,
                pixelLength: pixelLength
            )
        }
    }

    var body: some View {
        ZStack {
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
            }

            if let highlightedPart {
                let scale = DockIconRenderer.statusStripTileFraction
                StatusIconPartHighlight(
                    part: highlightedPart,
                    lineWidth: max(2, size * 0.045),
                    isDock: true
                )
                .frame(width: size * scale, height: size * scale)
                .opacity(highlightOpacity)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Production geometry overlaid at a larger optical weight for onboarding.
struct StatusIconPartHighlight: View {
    let part: IconGuidePart
    var lineWidth: CGFloat
    var isDock = false

    var body: some View {
        StatusIconPartShape(
            part: part,
            isDock: isDock
        )
        .stroke(
            Color.accentColor,
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
        .shadow(
            color: Color.accentColor.opacity(0.75),
            radius: lineWidth * 0.9
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct StatusIconPartShape: Shape {
    let part: IconGuidePart
    let isDock: Bool

    func path(in rect: CGRect) -> Path {
        if isDock {
            let cell: CGRect = switch part {
            case .battery: CGRect(x: 0.07, y: 0.13, width: 0.85, height: 0.44)
            case .network: CGRect(x: 0.09, y: 0.60, width: 0.40, height: 0.28)
            case .volume: CGRect(x: 0.55, y: 0.60, width: 0.37, height: 0.32)
            }
            return Path(roundedRect: CGRect(x: rect.minX + rect.width * cell.minX,
                                            y: rect.minY + rect.height * cell.minY,
                                            width: rect.width * cell.width, height: rect.height * cell.height),
                        cornerRadius: min(5, rect.height / 12))
        }
        let track = CGRect(x: rect.minX, y: rect.midY - rect.height * 0.26,
                           width: rect.width, height: rect.height * 0.52)
        let cell: (offset: CGFloat, width: CGFloat) = switch part {
        case .battery: (0.04, 0.36)
        case .network: (0.46, 0.22)
        case .volume: (0.72, 0.24)
        }
        return Path(roundedRect: CGRect(x: track.minX + track.width * cell.offset,
                                        y: track.minY, width: track.width * cell.width, height: track.height),
                    cornerRadius: min(5, track.height / 3))
    }
}
