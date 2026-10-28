import XCTest
@testable import ReachCore

final class TrackingPolicyTests: XCTestCase {
    func testStartsMovingAndClearsStaleGeofence() {
        var policy = TrackingPolicy()
        XCTAssertEqual(policy.handle(.start(at: 0)), [.clearGeofence, .startContinuousUpdates(.onFoot)])
        XCTAssertEqual(policy.mode, .moving)
        XCTAssertEqual(policy.handle(.start(at: 1)), [], "starting twice does nothing")
    }

    func testGoesStationaryAfterThreeMinutesInOnePlace() {
        var policy = TrackingPolicy()
        _ = policy.handle(.start(at: 0))
        for t in stride(from: 0.0, through: 175, by: 5) {
            XCTAssertEqual(policy.handle(.location(sample(t, offset(barclays, north: t.truncatingRemainder(dividingBy: 10))))), [])
        }
        let actions = policy.handle(.location(sample(180, barclays)))
        XCTAssertEqual(actions, [.stopContinuousUpdates, .breakTrace, .setGeofence(center: barclays, radius: 150)])
        XCTAssertEqual(policy.mode, .stationary(anchor: barclays))
    }

    func testTickNoticesDwellWhenDistanceFilterSuppressesFixes() {
        var policy = TrackingPolicy()
        _ = policy.handle(.start(at: 0))
        _ = policy.handle(.location(sample(10, barclays)))
        XCTAssertEqual(policy.handle(.tick(at: 120)), [])
        XCTAssertEqual(policy.handle(.tick(at: 190)).first, .stopContinuousUpdates)
    }

    func testWalkingKeepsGPSOn() {
        var policy = TrackingPolicy()
        _ = policy.handle(.start(at: 0))
        for t in stride(from: 0.0, through: 600, by: 1) {
            XCTAssertEqual(policy.handle(.location(sample(t, offset(barclays, east: t * 1.4)))), [])
        }
        XCTAssertEqual(policy.mode, .moving)
    }

    func testMotionVetoesStationaryInTraffic() {
        var policy = TrackingPolicy()
        _ = policy.handle(.start(at: 0))
        _ = policy.handle(.location(sample(0, barclays)))
        _ = policy.handle(.motion(.automotive, confident: true, at: 170))
        XCTAssertEqual(policy.handle(.tick(at: 200)), [], "still in a car 30 s ago")
        XCTAssertEqual(policy.handle(.tick(at: 235)).first, .stopContinuousUpdates)
    }

    func testMotionSwitchesProfile() {
        var policy = TrackingPolicy()
        _ = policy.handle(.start(at: 0))
        XCTAssertEqual(policy.handle(.motion(.automotive, confident: true, at: 5)), [.startContinuousUpdates(.vehicle)])
        XCTAssertEqual(policy.handle(.motion(.automotive, confident: true, at: 6)), [])
        XCTAssertEqual(policy.handle(.motion(.walking, confident: false, at: 7)), [], "low confidence is ignored")
        XCTAssertEqual(policy.handle(.motion(.walking, confident: true, at: 8)), [.startContinuousUpdates(.onFoot)])
        XCTAssertEqual(policy.handle(.motion(.stationary, confident: true, at: 9)), [])
    }

    func testWakesFromStationary() {
        func stationaryPolicy() -> TrackingPolicy {
            var policy = TrackingPolicy()
            _ = policy.handle(.start(at: 0))
            _ = policy.handle(.location(sample(0, barclays)))
            _ = policy.handle(.tick(at: 200))
            return policy
        }
        let wake: [TrackingAction] = [.clearGeofence, .startContinuousUpdates(.onFoot)]

        var a = stationaryPolicy()
        XCTAssertEqual(a.handle(.geofenceExit(at: 500)), wake)
        XCTAssertEqual(a.mode, .moving)

        var b = stationaryPolicy()
        XCTAssertEqual(b.handle(.visitDeparture(at: 500)), wake)

        var c = stationaryPolicy()
        XCTAssertEqual(c.handle(.significantChange(sample(500, offset(barclays, north: 100)))), [], "too close to be real")
        XCTAssertEqual(c.handle(.significantChange(sample(600, offset(barclays, north: 900)))), wake)

        var d = stationaryPolicy()
        XCTAssertEqual(d.handle(.motion(.stationary, confident: true, at: 500)), [])
        XCTAssertEqual(d.handle(.motion(.cycling, confident: true, at: 510)), wake)
    }

    func testGivesUpWhenNoFixEverArrives() {
        var policy = TrackingPolicy()
        _ = policy.handle(.start(at: 0))
        XCTAssertEqual(policy.handle(.tick(at: 300)), [])
        XCTAssertEqual(policy.handle(.tick(at: 360)), [.stopContinuousUpdates, .breakTrace])
        XCTAssertEqual(policy.mode, .stationary(anchor: nil))
        // With no anchor, any significant change wakes us.
        XCTAssertEqual(policy.handle(.significantChange(sample(400, barclays))).last, .startContinuousUpdates(.onFoot))
    }

    func testStopTurnsEverythingOff() {
        var policy = TrackingPolicy()
        _ = policy.handle(.start(at: 0))
        XCTAssertEqual(policy.handle(.stop), [.stopContinuousUpdates, .clearGeofence, .breakTrace])
        XCTAssertEqual(policy.mode, .off)
        XCTAssertEqual(policy.handle(.geofenceExit(at: 10)), [])
    }

    /// Replays the walk–dwell–walk GPX: exactly one stop, about three minutes
    /// after standing still, then GPS comes back when the geofence is left.
    func testWalkDwellWalkFixture() throws {
        let samples = try Fixture.samples("WalkDwellWalk")
        let t0 = try XCTUnwrap(samples.first).timestamp
        var policy = TrackingPolicy()
        _ = policy.handle(.start(at: t0))
        var stops: [Double] = []
        var anchor: GeoCoordinate?
        for s in samples {
            if case .stationary(let a) = policy.mode, let a {
                // Simulate CLMonitor: report leaving the geofence.
                if Geo.distance(a, s.coordinate) > 150 { _ = policy.handle(.geofenceExit(at: s.timestamp)) }
                continue
            }
            let actions = policy.handle(.location(s))
            if actions.contains(.stopContinuousUpdates) {
                stops.append(s.timestamp - t0)
                if case .stationary(let a) = policy.mode { anchor = a }
            }
        }
        XCTAssertEqual(stops.count, 1)
        // Walking ends ~600 s in; the stop should come ~180 s later.
        XCTAssertEqual(try XCTUnwrap(stops.first), 780, accuracy: 15)
        let atlanticAveEast = GeoCoordinate(latitude: 40.6811, longitude: -73.9655)
        XCTAssertLessThan(Geo.distance(try XCTUnwrap(anchor), atlanticAveEast), 30)
        XCTAssertEqual(policy.mode, .moving, "walked away, so GPS is back on")
    }
}
