import XCTest
@testable import ReachCore

final class GeoAndH3Tests: XCTestCase {
    func testDistanceMatchesKnownValue() {
        // Barclays Center to Grand Army Plaza is about 1 km.
        let gap = GeoCoordinate(latitude: 40.6745, longitude: -73.9704)
        XCTAssertEqual(Geo.distance(barclays, gap), 990, accuracy: 30)
        XCTAssertEqual(Geo.distance(barclays, offset(barclays, north: 100)), 100, accuracy: 0.5)
    }

    func testCellForBarclaysMatchesReferenceImplementation() throws {
        // Value from the H3 C library and h3-py for (40.6826, -73.9754) at resolution 11.
        let cell = try XCTUnwrap(H3.cell(at: barclays))
        XCTAssertEqual(cell, 0x8b2a100da772fff)
        XCTAssertTrue(H3.isValid(cell))
        XCTAssertEqual(H3.resolution(of: cell), 11)
    }

    func testCenterAndBoundary() throws {
        let cell = try XCTUnwrap(H3.cell(at: barclays))
        let center = try XCTUnwrap(H3.center(of: cell))
        XCTAssertLessThan(Geo.distance(center, barclays), 30)
        let boundary = H3.boundary(of: cell)
        XCTAssertEqual(boundary.count, 6)
        for corner in boundary {
            // Res-11 hexagons in New York have corners ~28-30 m from the centre.
            XCTAssertEqual(Geo.distance(corner, center), 29, accuracy: 4)
        }
    }

    func testNeighbours() throws {
        let a = try XCTUnwrap(H3.cell(at: barclays))
        let near = try XCTUnwrap(H3.cell(at: offset(barclays, east: 45)))
        let far = try XCTUnwrap(H3.cell(at: offset(barclays, east: 400)))
        XCTAssertNotEqual(a, near)
        XCTAssertTrue(H3.areNeighbors(a, near))
        XCTAssertFalse(H3.areNeighbors(a, far))
    }

    func testAverageArea() {
        XCTAssertEqual(H3.averageArea(), 2150, accuracy: 10)
    }
}
