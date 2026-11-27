enum StatusStripLayout: String, CaseIterable, Identifiable, Sendable {
    case inline, unified, connection

    var id: Self { self }

    /// Old values are accepted on read, but only the three current choices are written.
    init?(storedValue: String) {
        switch storedValue {
        case "divider", "batteryWordmark", "gauge": self = .inline
        case "capsule", "alerts": self = .unified
        default: self.init(rawValue: storedValue)
        }
    }

    var titleKey: LocalizationKey {
        switch self {
        case .inline: .statusStripInline
        case .unified: .statusStripUnified
        case .connection: .statusStripConnection
        }
    }
}

/// Only values that are visible in a preset, not SSIDs, device names or timestamps.
struct StatusStrip: Hashable, Sendable {
    static let defaultMetricTextScale = 1.0
    static let metricTextScaleRange = 0.85...1.20

    static func clampedMetricTextScale(_ scale: Double) -> Double {
        guard scale.isFinite else { return defaultMetricTextScale }
        return min(metricTextScaleRange.upperBound, max(metricTextScaleRange.lowerBound, scale))
    }

    enum Link: Hashable, Sendable {
        case wifi(String?), wired, other, offline, unknown
    }

    enum Energy: Hashable, Sendable {
        case battery, charging, plugged, absent
    }

    enum AudioLevel: Hashable, Sendable {
        case silent, low, high
    }

    let layout: StatusStripLayout
    let battery: Int?
    let energy: Energy
    let lowBattery: Bool
    let link: Link
    let audio: AudioLevel?
    let muted: Bool
    let usesSystemBattery: Bool
    let showsOutageInCenter: Bool
    let centerShowsNetwork: Bool
    let footerMetric: BottomIndicatorMetric?
    let footerMetricTextScale: Double
    /// An empty array means this slot isn't showing AirPods. In split mode an
    /// unknown ear stays nil, even when the legacy ring mirrors the other ear.
    let airPodsLevels: [Int?]
    let airPodsMarkerScale: Double
    let showsAirPodsSymbol: Bool

    init(layout: StatusStripLayout, snapshot: StatusSnapshot, threshold: Int, usesSystemBattery: Bool = true,
         prioritizesNetworkErrors: Bool = true, showsVolume: Bool = true, centerShowsNetwork: Bool = true,
         footerMetric: BottomIndicatorMetric? = nil, footerMetricTextScale: Double = Self.defaultMetricTextScale,
         airPodsLevels: [Int?] = [], airPodsMarkerScale: Double = 1,
         showsAirPodsSymbol: Bool = false) {
        self.layout = layout
        self.usesSystemBattery = usesSystemBattery
        self.centerShowsNetwork = centerShowsNetwork
        self.footerMetric = footerMetric
        // Ignore the custom scale in other modes so their render keys stay stable.
        self.footerMetricTextScale = footerMetric == nil ? Self.defaultMetricTextScale
            : Self.clampedMetricTextScale(footerMetricTextScale)
        self.airPodsLevels = airPodsLevels
        self.airPodsMarkerScale = airPodsLevels.isEmpty ? 1 : airPodsMarkerScale
        self.showsAirPodsSymbol = !airPodsLevels.isEmpty && showsAirPodsSymbol
        let power = snapshot.battery
        battery = power.isPresent && power.rawPercentage != nil ? power.percentage : nil
        lowBattery = battery.map { $0 <= threshold } ?? false
        energy = if !power.isPresent { .absent }
            else if power.isCharging && !power.isCharged { .charging }
            else if power.isConnectedToPower { .plugged }
            else { .battery }
        if snapshot.connection == .offline
            || (snapshot.connection == .wifi && StatusMappings.isNetworkOffline(wifi: snapshot.wifi, connection: .wifi))
            || (snapshot.connection == .unknown && snapshot.wifi.state == .noInternet) {
            link = .offline
        } else {
            switch snapshot.connection {
            case .ethernet: link = .wired
            case .other: link = .other
            case .wifi, .unknown:
                switch snapshot.wifi.state {
                case .connected:
                    let label: String? = switch layout == .connection && centerShowsNetwork ? snapshot.wifi.band : nil {
                    case .twoPointFourGHz: "2.4 GHz"
                    case .fiveGHz: "5 GHz"
                    case .sixGHz: "6 GHz"
                    case nil: nil
                    }
                    link = .wifi(label)
                case .hotspot, .temporary, .shared: link = .other
                default: link = .unknown
                }
            case .offline: link = .offline
            }
        }
        audio = showsVolume ? snapshot.volume.scalar.flatMap { value in
            guard value.isFinite else { return nil }
            let step = Int((min(1, max(0, value)) * 20).rounded())
            return step == 0 ? .silent : step <= 7 ? .low : .high
        } : nil
        muted = showsVolume && snapshot.volume.isMuted
        showsOutageInCenter = link == .offline && prioritizesNetworkErrors
    }

    init(layout: StatusStripLayout, previewScene: IconSceneState) {
        self.layout = layout
        usesSystemBattery = true
        showsOutageInCenter = false
        centerShowsNetwork = true
        footerMetric = nil
        footerMetricTextScale = Self.defaultMetricTextScale
        airPodsLevels = []
        airPodsMarkerScale = 1
        showsAirPodsSymbol = false
        let segment = previewScene.outerRing?.segments.first
        battery = segment.map { Int(($0.progress * 100).rounded()) }
        lowBattery = segment?.color == .critical
        energy = previewScene.outerRing?.effect != nil ? .charging : battery == nil ? .absent : .battery
        link = .unknown
        audio = nil
        muted = false
    }

    func hasSameNonAudioContent(as other: Self) -> Bool {
        layout == other.layout && battery == other.battery && energy == other.energy
            && lowBattery == other.lowBattery && link == other.link && usesSystemBattery == other.usesSystemBattery
            && showsOutageInCenter == other.showsOutageInCenter
            && centerShowsNetwork == other.centerShowsNetwork && footerMetric == other.footerMetric
            && footerMetricTextScale == other.footerMetricTextScale
            && airPodsLevels == other.airPodsLevels
            && airPodsMarkerScale == other.airPodsMarkerScale
            && showsAirPodsSymbol == other.showsAirPodsSymbol
    }
}
