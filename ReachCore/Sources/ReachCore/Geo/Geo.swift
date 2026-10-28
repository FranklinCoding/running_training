import Foundation

/// A latitude/longitude pair in degrees. ReachCore's stand-in for
/// `CLLocationCoordinate2D`, so this package doesn't depend on CoreLocation.
public struct GeoCoordinate: Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// One location fix, as recorded. Times are seconds since 1970.
public struct LocationSample: Equatable, Codable, Sendable {
    public var timestamp: Double
    public var latitude: Double
    public var longitude: Double
    /// Radius of uncertainty in metres. Negative means the fix is invalid.
    public var horizontalAccuracy: Double
    /// Metres per second. Negative means unknown.
    public var speed: Double
    /// Degrees clockwise from true north. Negative means unknown.
    public var course: Double

    public init(timestamp: Double, latitude: Double, longitude: Double,
                horizontalAccuracy: Double, speed: Double = -1, course: Double = -1) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.course = course
    }

    public var coordinate: GeoCoordinate {
        GeoCoordinate(latitude: latitude, longitude: longitude)
    }
}

public enum Geo {
    /// Mean Earth radius (IUGG), metres.
    public static let earthRadius = 6_371_008.8

    /// Great-circle distance in metres.
    public static func distance(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Straight-line interpolation in degrees. Accurate enough over the
    /// few hundred metres between consecutive fixes.
    public static func interpolate(_ a: GeoCoordinate, _ b: GeoCoordinate, fraction t: Double) -> GeoCoordinate {
        GeoCoordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                      longitude: a.longitude + (b.longitude - a.longitude) * t)
    }
}
