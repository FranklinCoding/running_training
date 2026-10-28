import CH3

public typealias H3Cell = UInt64

/// Thin Swift wrapper over the vendored H3 C library.
public enum H3 {
    /// The resolution Reach uses for coverage: hexagons ~43 m across, ~2,150 m².
    public static let coverageResolution = 11

    public static func cell(at coordinate: GeoCoordinate, resolution: Int = coverageResolution) -> H3Cell? {
        var point = LatLng(lat: degsToRads(coordinate.latitude), lng: degsToRads(coordinate.longitude))
        var out: H3Index = 0
        guard CH3.latLngToCell(&point, Int32(resolution), &out) == 0 else { return nil }
        return out
    }

    public static func center(of cell: H3Cell) -> GeoCoordinate? {
        var point = LatLng()
        guard CH3.cellToLatLng(cell, &point) == 0 else { return nil }
        return GeoCoordinate(latitude: radsToDegs(point.lat), longitude: radsToDegs(point.lng))
    }

    /// Corner points of the cell, counter-clockwise. Empty for an invalid cell.
    public static func boundary(of cell: H3Cell) -> [GeoCoordinate] {
        var boundary = CellBoundary()
        guard CH3.cellToBoundary(cell, &boundary) == 0 else { return [] }
        let count = Int(boundary.numVerts)
        return withUnsafeBytes(of: boundary.verts) { raw in
            let verts = raw.bindMemory(to: LatLng.self)
            return (0..<count).map {
                GeoCoordinate(latitude: radsToDegs(verts[$0].lat), longitude: radsToDegs(verts[$0].lng))
            }
        }
    }

    public static func isValid(_ cell: H3Cell) -> Bool {
        CH3.isValidCell(cell) != 0
    }

    public static func resolution(of cell: H3Cell) -> Int {
        Int(CH3.getResolution(cell))
    }

    public static func areNeighbors(_ a: H3Cell, _ b: H3Cell) -> Bool {
        var out: Int32 = 0
        guard CH3.areNeighborCells(a, b, &out) == 0 else { return false }
        return out != 0
    }

    /// Average hexagon area at a resolution, in square metres.
    public static func averageArea(resolution: Int = coverageResolution) -> Double {
        var out: Double = 0
        _ = CH3.getHexagonAreaAvgM2(Int32(resolution), &out)
        return out
    }
}
