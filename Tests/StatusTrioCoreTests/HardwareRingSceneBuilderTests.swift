import XCTest
@testable import StatusTrioCore

final class HardwareRingSceneBuilderTests: XCTestCase {
    func testRegularProgressFillsFromLeadingEdge() {
        XCTAssertEqual(HardwareMetricTrackGeometry.fill(progress: 0.5, split: false), 0..<0.5)
    }

    func testSplitProgressFillsBothDirectionsAndClampsExtremes() {
        XCTAssertEqual(HardwareMetricTrackGeometry.fill(progress: 0.5, split: true), 0.25..<0.75)
        XCTAssertEqual(HardwareMetricTrackGeometry.fill(progress: -1, split: true), 0.5..<0.5)
        XCTAssertEqual(HardwareMetricTrackGeometry.fill(progress: 2, split: true), 0..<1)
    }
}
