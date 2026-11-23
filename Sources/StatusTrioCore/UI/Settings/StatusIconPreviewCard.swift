import AppKit
import SwiftUI

private struct SettingsIconPresentationKey: EnvironmentKey {
    static let defaultValue: IconPresentationViewModel? = nil
}

extension EnvironmentValues {
    var settingsIconPresentation: IconPresentationViewModel? {
        get { self[SettingsIconPresentationKey.self] }
        set { self[SettingsIconPresentationKey.self] = newValue }
    }
}

private struct IconPresentationPreview<Content: View>: View {
    @ObservedObject var model: IconPresentationViewModel
    @ViewBuilder let content: (IconPresentationOutput) -> Content

    var body: some View { content(model.output) }
}

struct LiveIconSettingsStatus: View {
    @Environment(\.settingsIconPresentation) private var iconPresentation
    let text: (IconPresentationOutput) -> String?

    var body: some View {
        if let iconPresentation {
            IconPresentationPreview(model: iconPresentation) { output in
                if let message = text(output) {
                    SettingsHintRow(text: message)
                }
            }
        }
    }
}

/// Live status icon preview shown at the top of the icon-related settings panes.
///
/// The card renders the real menu bar artwork through `StatusIconRenderer`, so
/// every option that feeds the icon — battery, connection, volume — updates it
/// immediately.
struct StatusIconPreviewCard: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    /// The live source the centre slot draws. The card re-renders when
    /// the controller publishes; `nil` in previews with no live controller.
    var inputSourceController: InputSourceController? = nil
    @Binding var isDarkBackground: Bool
    @EnvironmentObject private var localization: Localization
    @EnvironmentObject private var chargingEffectClock: ChargingEffectClock
    @Environment(\.settingsIconPresentation) private var iconPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previewPlayback = ChargingEffectPreviewPlayback()
    /// Identifies this card's claim on the shared clock, so a Dock-only menu bar
    /// still animates the preview while it is visible.
    @State private var clockConsumerToken = UUID()
    /// Mirrors the live High Power Mode state so the preview shows its ring colour.
    @State private var isHighPowerMode = false

    var body: some View {
        InputSourceLivePreview(controller: inputSourceController) {
            if let iconPresentation {
                IconPresentationPreview(model: iconPresentation) { output in
                    card(scene: output.menuBarTestScene ?? output.scene)
                }
            } else {
                card(scene: nil)
            }
        }
    }

    private func card(scene: IconSceneState?) -> some View {
        VStack(spacing: 8) {
            menuBarPreview(scene: scene)

            Text(localization.string(.settingsPreviewHint))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            isHighPowerMode = statusStore.highPowerMode.isHighPowerMode
            setClockClaim(enabled: store.showsMenuBarChargingEffect)
        }
        .onReceive(statusStore.highPowerMode.$isHighPowerMode) { isHighPowerMode = $0 }
        .onChange(of: store.showsMenuBarChargingEffect) { isEnabled in
            setClockClaim(enabled: isEnabled)
            if isEnabled {
                startPreviewIfAllowed()
            } else {
                previewPlayback.stop()
            }
        }
        .onChange(of: isLiveChargingActive) { isActive in
            if isActive { previewPlayback.stop() }
        }
        .onChange(of: reduceMotion) { isEnabled in
            if isEnabled {
                previewPlayback.stop()
            }
        }
        .onDisappear {
            chargingEffectClock.endAnimationPreview(clockConsumerToken)
            previewPlayback.stop()
        }
        .task(id: previewPlayback.startedAt) {
            guard let startedAt = previewPlayback.startedAt else { return }
            let elapsed = Date().timeIntervalSince(startedAt)
            let remaining = max(0, ChargingEffectPreviewPlayback.duration - elapsed)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            guard !Task.isCancelled else { return }
            previewPlayback.stop()
        }
    }

    @ViewBuilder
    private func menuBarPreview(scene: IconSceneState?) -> some View {
        if let phase = liveChargingPhase {
            previewBar(status: currentStatus, phase: phase, scene: scene)
        } else if previewPlayback.isPlaying && !store.isNoBatterySimulationActive {
            TimelineView(.animation(
                minimumInterval: 1 / Double(ChargingEffectTimeline.framesPerSecond),
                paused: false
            )) { timeline in
                let phase = previewPlayback.phase(at: timeline.date)
                previewBar(
                    status: phase == nil ? currentStatus : chargingPreviewStatus,
                    phase: phase,
                    scene: phase == nil ? scene : nil
                )
            }
        } else {
            previewBar(status: currentStatus, phase: nil, scene: scene)
        }
    }

    /// The snapshot the preview draws. A development build's no-battery
    /// simulation swaps the battery out so the menu-bar preview shows the
    /// battery-less layout (a full closed ring plus the decorative marker).
    private var displaySnapshot: StatusSnapshot {
        store.isNoBatterySimulationActive
            ? statusStore.snapshot.replacingBattery(
                .absent(lowPowerMode: statusStore.snapshot.battery.isLowPowerMode))
            : statusStore.snapshot
    }

    private var currentStatus: MenuBarStatus {
        ChargingEffectTestMode.status(
            MenuBarStatus(snapshot: displaySnapshot),
            enabled: store.testsChargingEffect
        )
    }

    private var liveChargingPhase: ChargingEffectPhase? {
        Self.livePhase(
            battery: ChargingEffectTestMode.battery(
                displaySnapshot.battery,
                enabled: store.testsChargingEffect
            ),
            enabled: store.showsMenuBarChargingEffect,
            reduceMotion: reduceMotion,
            phase: chargingEffectClock.phase
        )
    }

    private var isLiveChargingActive: Bool {
        liveChargingPhase != nil
    }

    static func livePhase(
        battery: BatteryStatus,
        enabled: Bool,
        reduceMotion: Bool,
        phase: ChargingEffectPhase?
    ) -> ChargingEffectPhase? {
        guard battery.isCharging, enabled, !reduceMotion else { return nil }
        return phase
    }

    private var chargingPreviewStatus: MenuBarStatus {
        let current = statusStore.snapshot
        let battery = BatteryStatus(
            rawPercentage: 62,
            isPresent: true,
            isCharging: true,
            isLowPowerMode: current.battery.isLowPowerMode,
            isConnectedToPower: true
        )
        return MenuBarStatus(snapshot: StatusSnapshot(
            battery: battery,
            wifi: current.wifi,
            connection: current.connection,
            volume: current.volume
        ))
    }

    private func previewBar(
        status: MenuBarStatus,
        phase: ChargingEffectPhase?,
        scene: IconSceneState?
    ) -> some View {
        MenuBarPreviewBar(
            status: status,
            iconSize: store.iconSize,
            batteryOptions: store.batteryIconOptions,
            connectionOptions: store.connectionIconOptions,
            volumeOptions: store.volumeIconOptions,
            bluetoothAudioOptions: store.bluetoothAudioIconOptions,
            isDarkBackground: isDarkBackground,
            phase: phase,
            showsChargingEffect: store.showsMenuBarChargingEffect,
            inputSource: inputSourceController?.state.iconDescriptor(
                markerStyle: store.inputSourceMarkerStyle
            ),
            isHighPowerMode: isHighPowerMode,
            bottomIndicatorSource: store.bottomIndicatorSource,
            bottomIndicatorMetric: store.bottomIndicatorMetric,
            bottomIndicatorMetricColor: store.hardwareColor(for: store.bottomIndicatorMetric),
            bottomIndicatorStyle: store.effectiveBottomIndicatorStyle,
            layout: store.statusStripLayout,
            wifiBand: displaySnapshot.wifi.band,
            resolvedScene: scene?.withChargingEffectEnabled(store.showsMenuBarChargingEffect)
        ) {
            appearanceToggle
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.iconSize)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.batteryIconOptions)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.connectionIconOptions)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.volumeIconOptions)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.bluetoothAudioIconOptions)
    }

    private func startPreviewIfAllowed() {
        guard store.showsMenuBarChargingEffect,
              !reduceMotion,
              !isLiveChargingActive
        else { return }
        previewPlayback.start(at: Date())
    }

    private func setClockClaim(enabled: Bool) {
        if enabled {
            chargingEffectClock.beginAnimationPreview(clockConsumerToken)
        } else {
            chargingEffectClock.endAnimationPreview(clockConsumerToken)
        }
    }

    private var appearanceToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isDarkBackground.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isDarkBackground ? "moon.fill" : "sun.max.fill")
                    .font(.system(size: 10))
                Text(localization.string(isDarkBackground ? .settingsPreviewDark : .settingsPreviewLight))
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(isDarkBackground ? Color.white.opacity(0.85) : Color.black.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isDarkBackground ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .help(localization.string(.settingsPreviewToggleHelp))
    }
}

/// Small Dock tile preview that mirrors the live Dock icon.
struct DockIconPreviewTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsIconPresentation) private var iconPresentation
    @ObservedObject var store: SettingsStore
    @ObservedObject var statusStore: SystemStatusStore
    var inputSourceController: InputSourceController? = nil
    var size: CGFloat = 44
    var overrideStyle: DockIconBackgroundStyle? = nil
    var previewCache: DockIconPreviewCache? = nil

    var body: some View {
        InputSourceLivePreview(controller: inputSourceController) {
            Group {
                if let iconPresentation {
                    IconPresentationPreview(model: iconPresentation) { output in
                        tile(scene: output.scene)
                    }
                } else { tile(scene: nil) }
            }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.batteryIconOptions)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.connectionIconOptions)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.volumeIconOptions)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: store.bluetoothAudioIconOptions)
                .accessibilityHidden(true)
        }
    }

    @MainActor
    var renderKey: DockIconRenderKey { tile(scene: nil).renderKey }

    @MainActor
    var previewImage: NSImage? { tile(scene: nil).previewImage }

    /// The tile the body renders, so a test reads exactly the key the body uses.
    private func tile(scene: IconSceneState?) -> DockIconTile {
        DockIconTile(
            status: MenuBarStatus(snapshot: statusStore.snapshot),
            layout: store.statusStripLayout,
            batteryOptions: store.batteryIconOptions,
            connectionOptions: store.connectionIconOptions,
            volumeOptions: store.volumeIconOptions,
            bluetoothAudioOptions: store.bluetoothAudioIconOptions,
            backgroundStyle: resolvedBackgroundStyle,
            size: size,
            inputSource: inputSourceController?.state.iconDescriptor(
                markerStyle: store.inputSourceMarkerStyle
            ),
            previewCache: previewCache,
            wifiBand: statusStore.snapshot.wifi.band,
            resolvedScene: scene
        )
    }

    private var resolvedBackgroundStyle: DockIconBackgroundStyle {
        if let overrideStyle {
            return overrideStyle
        }
        return DockIconBackgroundResolver.style(
            for: store.dockIconBackgroundPreference,
            theme: SystemIconAppearanceReader.current(),
            isDarkAppearance: NSApplication.shared.effectiveAppearance
                .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        )
    }
}
