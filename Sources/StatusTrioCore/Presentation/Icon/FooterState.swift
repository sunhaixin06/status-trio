struct DotsState: Equatable, Hashable, Sendable {
    let count: Int
    let activeCount: Int
    let color: IconColorRole
    let strokeScale: Double
    let inactiveColor: IconColorRole
    let metricReading: String?

    init(count: Int, activeCount: Int, color: IconColorRole, strokeScale: Double = 1.25,
         inactiveColor: IconColorRole = .inactive, metricReading: String? = nil) {
        let normalizedCount = max(0, count)
        self.count = normalizedCount
        self.activeCount = min(normalizedCount, max(0, activeCount))
        self.color = color
        self.strokeScale = OuterRingState.normalizedStrokeScale(strokeScale)
        self.inactiveColor = inactiveColor
        self.metricReading = metricReading
    }
}

struct ArcState: Equatable, Hashable, Sendable {
    let progress: Double
    let color: IconColorRole
    let strokeScale: Double
    let inactiveColor: IconColorRole
    let isVertical: Bool
    let metricReading: String?

    init(progress: Double, color: IconColorRole, strokeScale: Double = 1.25,
         inactiveColor: IconColorRole = .inactive, isVertical: Bool = false, metricReading: String? = nil) {
        self.progress = RingSegmentState.normalizedProgress(progress)
        self.color = color
        self.strokeScale = OuterRingState.normalizedStrokeScale(strokeScale)
        self.inactiveColor = inactiveColor
        self.isVertical = isVertical
        self.metricReading = metricReading
    }
}

enum FooterState: Equatable, Hashable, Sendable {
    case dots(DotsState)
    case arc(ArcState)

    var metricReading: String? {
        switch self {
        case let .dots(value): value.metricReading
        case let .arc(value): value.metricReading
        }
    }
}
