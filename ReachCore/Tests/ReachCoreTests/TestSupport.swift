import Foundation
import XCTest
@testable import ReachCore

enum Fixture {
    static func samples(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> [LocationSample] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "gpx", subdirectory: "Fixtures"),
                                "Missing fixture \(name).gpx", file: file, line: line)
        return try GPX.parse(Data(contentsOf: url))
    }
}

let barclays = GeoCoordinate(latitude: 40.6826, longitude: -73.9754)

func sample(_ t: Double, _ c: GeoCoordinate, accuracy: Double = 5) -> LocationSample {
    LocationSample(timestamp: t, latitude: c.latitude, longitude: c.longitude, horizontalAccuracy: accuracy)
}

/// A point `north`/`east` metres away from `c`.
func offset(_ c: GeoCoordinate, north: Double = 0, east: Double = 0) -> GeoCoordinate {
    GeoCoordinate(latitude: c.latitude + north / 111_320,
                  longitude: c.longitude + east / (111_320 * cos(c.latitude * .pi / 180)))
}
