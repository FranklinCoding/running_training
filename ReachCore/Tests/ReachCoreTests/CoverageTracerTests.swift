import XCTest
@testable import ReachCore

final class CoverageTracerTests: XCTestCase {
    func testStraightWalkMarksAContinuousChainOfCells() throws {
        var tracer = CoverageTracer()
        var touches: [CoverageTracer.Touch] = []
        // 500 m east, one fix every 25 m: sparser than the cells themselves.
        for i in 0...20 {
            touches += tracer.add(sample(Double(i) * 18, offset(barclays, east: Double(i) * 25)))
        }
        XCTAssertGreaterThanOrEqual(Set(touches.map(\.cell)).count, 10)
        for (a, b) in zip(touches, touches.dropFirst()) {
            XCTAssertTrue(H3.areNeighbors(a.cell, b.cell), "gap between consecutive cells")
            XCTAssertLessThanOrEqual(a.timestamp, b.timestamp)
        }
    }

    func testStandingStillReportsTheCellOnce() {
        var tracer = CoverageTracer()
        var touches: [CoverageTracer.Touch] = []
        for i in 0..<30 { touches += tracer.add(sample(Double(i), barclays)) }
        XCTAssertEqual(touches.count, 1)
    }

    func testIgnoresVagueFixes() {
        var tracer = CoverageTracer()
        XCTAssertEqual(tracer.add(sample(0, barclays, accuracy: 45)), [])
    }

    func testDoesNotBridgeLongGapsOrJumps() throws {
        var tracer = CoverageTracer()
        _ = tracer.add(sample(0, barclays))
        // 300 s later, 200 m away: too long a gap to join.
        let afterGap = tracer.add(sample(300, offset(barclays, north: 200)))
        XCTAssertEqual(afterGap.count, 1)
        // 10 s later, 800 m away: too far to join.
        let afterJump = tracer.add(sample(310, offset(barclays, north: 1000)))
        XCTAssertEqual(afterJump.count, 1)
    }

    func testBreakTraceStartsFresh() {
        var tracer = CoverageTracer()
        _ = tracer.add(sample(0, barclays))
        tracer.breakTrace()
        // Same spot again after a break is reported again, and nothing is interpolated.
        XCTAssertEqual(tracer.add(sample(10, barclays)).count, 1)
    }

    func testSubwayGapFixtureIsNotDrawnAcross() throws {
        let samples = try Fixture.samples("WalkSubwayGapWalk")
        var tracer = CoverageTracer()
        var touches: [CoverageTracer.Touch] = []
        for s in samples { touches += tracer.add(s) }
        let jumps = zip(touches, touches.dropFirst()).filter { !H3.areNeighbors($0.cell, $1.cell) }
        // Exactly one discontinuity: Barclays to Union Square, with nothing marked in between.
        XCTAssertEqual(jumps.count, 1)
        let union = GeoCoordinate(latitude: 40.7356, longitude: -73.9905)
        let midway = GeoCoordinate(latitude: 40.709, longitude: -73.983)
        let centers = touches.compactMap { H3.center(of: $0.cell) }
        XCTAssertTrue(centers.contains { Geo.distance($0, union) < 60 })
        XCTAssertFalse(centers.contains { Geo.distance($0, midway) < 2000 })
    }

    func testVisitRule() {
        XCTAssertTrue(CellVisitRule.countsAsNewPass(lastVisit: nil, now: 0))
        XCTAssertFalse(CellVisitRule.countsAsNewPass(lastVisit: 0, now: 600))
        XCTAssertTrue(CellVisitRule.countsAsNewPass(lastVisit: 0, now: 1800))
    }
}
