import XCTest
@testable import ReachCore

final class PointFilterTests: XCTestCase {
    func testRejectsVagueFixes() {
        var filter = PointFilter()
        XCTAssertFalse(filter.accept(sample(0, barclays, accuracy: 120)))
        XCTAssertFalse(filter.accept(sample(1, barclays, accuracy: -1)))
        XCTAssertTrue(filter.accept(sample(2, barclays, accuracy: 10)))
    }

    func testRejectsTeleportsButNotLongGaps() {
        var filter = PointFilter()
        XCTAssertTrue(filter.accept(sample(0, barclays)))
        // 2 km in 5 s is a glitch.
        XCTAssertFalse(filter.accept(sample(5, offset(barclays, north: 2000))))
        // 5 km after 15 minutes underground is fine.
        XCTAssertTrue(filter.accept(sample(900, offset(barclays, north: 5000))))
    }

    func testRejectsDuplicateAndOutOfOrderFixes() {
        var filter = PointFilter()
        XCTAssertTrue(filter.accept(sample(10, barclays)))
        XCTAssertFalse(filter.accept(sample(10.2, barclays)))
        XCTAssertFalse(filter.accept(sample(5, barclays)))
        XCTAssertTrue(filter.accept(sample(11, offset(barclays, north: 1.4))))
    }
}

final class PointCodecTests: XCTestCase {
    func testRoundTrip() throws {
        let samples = [
            LocationSample(timestamp: 1_790_859_601.25, latitude: 40.6826895, longitude: -73.9753894,
                           horizontalAccuracy: 4.5, speed: 1.4, course: 152),
            LocationSample(timestamp: 1_790_859_602.5, latitude: 40.68265, longitude: -73.97535,
                           horizontalAccuracy: 12, speed: -1, course: -1),
        ]
        let decoded = try PointCodec.decode(PointCodec.encode(samples))
        XCTAssertEqual(decoded, samples)
    }

    func testEmptyAndCorrupt() throws {
        XCTAssertEqual(try PointCodec.decode(PointCodec.encode([])), [])
        XCTAssertThrowsError(try PointCodec.decode(Data([1, 5, 0, 0, 0, 1, 2]))) {
            XCTAssertEqual($0 as? PointCodec.DecodeError, .truncated)
        }
        XCTAssertThrowsError(try PointCodec.decode(Data([9, 0, 0, 0, 0]))) {
            XCTAssertEqual($0 as? PointCodec.DecodeError, .unsupportedVersion(9))
        }
    }

    func testDecodesSlicedData() throws {
        let samples = [sample(1, barclays)]
        let padded = Data([0xFF, 0xFF]) + PointCodec.encode(samples)
        XCTAssertEqual(try PointCodec.decode(padded.dropFirst(2)), samples)
    }
}

final class MotionKindTests: XCTestCase {
    func testMostSpecificMovementWins() {
        XCTAssertEqual(MotionKind.classify(stationary: true, walking: false, running: false, cycling: false, automotive: true), .automotive)
        XCTAssertEqual(MotionKind.classify(stationary: false, walking: true, running: true, cycling: false, automotive: false), .running)
        XCTAssertEqual(MotionKind.classify(stationary: true, walking: false, running: false, cycling: false, automotive: false), .stationary)
        XCTAssertEqual(MotionKind.classify(stationary: false, walking: false, running: false, cycling: false, automotive: false), .unknown)
        XCTAssertFalse(MotionKind.stationary.isMoving)
        XCTAssertTrue(MotionKind.cycling.isMoving)
    }
}

final class GPXTests: XCTestCase {
    func testParsesWaypointsWithTimeAndAccuracy() throws {
        let xml = """
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <wpt lat="40.68265" lon="-73.97539"><time>2026-10-01T13:00:00Z</time><hacc>12</hacc></wpt>
          <trk><trkseg><trkpt lat="40.6827" lon="-73.9754"><time>2026-10-01T13:00:01.500Z</time></trkpt></trkseg></trk>
        </gpx>
        """
        let samples = try GPX.parse(Data(xml.utf8))
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].latitude, 40.68265)
        XCTAssertEqual(samples[0].horizontalAccuracy, 12)
        XCTAssertEqual(samples[1].timestamp - samples[0].timestamp, 1.5, accuracy: 0.001)
        XCTAssertEqual(samples[1].horizontalAccuracy, 5)
    }

    func testFixturesLoad() throws {
        for name in ["WalkBarclaysToGrandArmyPlaza", "WalkDwellWalk", "WalkSubwayGapWalk"] {
            let samples = try Fixture.samples(name)
            XCTAssertGreaterThan(samples.count, 500, name)
            XCTAssertEqual(samples, samples.sorted { $0.timestamp < $1.timestamp }, name)
        }
    }
}
