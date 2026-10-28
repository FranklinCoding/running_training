import MapKit
import ReachCore

/// One MapKit overlay holding every explored H3 cell. MapKit draws overlay
/// tiles on background threads, so the cell geometry sits behind a lock and
/// is bucketed spatially so each tile only looks at nearby cells.
final class HexOverlay: NSObject, MKOverlay, @unchecked Sendable {
    struct Hex {
        let cell: H3Cell
        let points: [MKMapPoint]
        let bounds: MKMapRect
    }

    private struct BucketKey: Hashable {
        let x: Int
        let y: Int
    }

    let coordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -73.9560)
    let boundingMapRect = MKMapRect.world

    /// ~2 km buckets at New York's latitude.
    private static let bucketSize = MKMapPointsPerMeterAtLatitude(40.7) * 2000
    /// A hexagon's corners are ~30 m from its centre; pad lookups by more than that.
    private static let lookupPadding = MKMapPointsPerMeterAtLatitude(40.7) * 60

    private let lock = NSLock()
    private var buckets: [BucketKey: [Hex]] = [:]
    private var known: Set<H3Cell> = []

    /// Adds cells and returns the area that needs redrawing.
    @discardableResult
    func add(_ cells: [H3Cell]) -> MKMapRect {
        let hexes: [Hex] = cells.compactMap { cell in
            let points = H3.boundary(of: cell).map {
                MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
            }
            guard points.count >= 3 else { return nil }
            let xs = points.map(\.x), ys = points.map(\.y)
            let bounds = MKMapRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            return Hex(cell: cell, points: points, bounds: bounds)
        }
        return lock.withLock {
            var dirty = MKMapRect.null
            for hex in hexes where known.insert(hex.cell).inserted {
                buckets[Self.bucket(for: MKMapPoint(x: hex.bounds.midX, y: hex.bounds.midY)), default: []].append(hex)
                dirty = dirty.union(hex.bounds)
            }
            return dirty
        }
    }

    func hexes(in rect: MKMapRect) -> [Hex] {
        let padded = rect.insetBy(dx: -Self.lookupPadding, dy: -Self.lookupPadding)
        let low = Self.bucket(for: MKMapPoint(x: padded.minX, y: padded.minY))
        let high = Self.bucket(for: MKMapPoint(x: padded.maxX, y: padded.maxY))
        return lock.withLock {
            var result: [Hex] = []
            for x in low.x...high.x {
                for y in low.y...high.y {
                    guard let bucket = buckets[BucketKey(x: x, y: y)] else { continue }
                    result += bucket.filter { $0.bounds.intersects(rect) }
                }
            }
            return result
        }
    }

    private static func bucket(for point: MKMapPoint) -> BucketKey {
        BucketKey(x: Int((point.x / bucketSize).rounded(.down)), y: Int((point.y / bucketSize).rounded(.down)))
    }
}

final class HexOverlayRenderer: MKOverlayRenderer {
    /// Same amber as the app icon; fixed rather than dynamic because tiles
    /// render off the main thread, and it reads well on light and dark maps.
    private static let fill = UIColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 0.55).cgColor
    private static let edge = UIColor(red: 0.91, green: 0.56, blue: 0.14, alpha: 0.8).cgColor

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? HexOverlay else { return }
        let hexes = overlay.hexes(in: mapRect)
        guard !hexes.isEmpty else { return }

        let path = CGMutablePath()
        for hex in hexes {
            path.addLines(between: hex.points.map { point(for: $0) })
            path.closeSubpath()
        }
        context.addPath(path)
        context.setFillColor(Self.fill)
        context.fillPath()

        // Outline individual cells only when zoomed in far enough to see them.
        let metresPerScreenPoint = 1 / (Double(zoomScale) * MKMapPointsPerMeterAtLatitude(40.7))
        if metresPerScreenPoint < 2 {
            context.addPath(path)
            context.setStrokeColor(Self.edge)
            context.setLineWidth(1 / zoomScale)
            context.strokePath()
        }
    }
}
