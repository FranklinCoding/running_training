import Foundation

/// Packs fixes into a compact little-endian blob, so a day of 1 Hz walking
/// is a handful of database rows instead of tens of thousands.
///
/// Layout: version (UInt8), count (UInt32), then per fix:
/// timestamp, latitude, longitude (Float64); accuracy, speed, course (Float32).
public enum PointCodec {
    public static let version: UInt8 = 1
    static let headerSize = 5
    static let recordSize = 36

    public enum DecodeError: Error, Equatable {
        case unsupportedVersion(UInt8)
        case truncated
    }

    public static func encode(_ samples: [LocationSample]) -> Data {
        var data = Data(capacity: headerSize + samples.count * recordSize)
        data.append(version)
        append(UInt32(samples.count), to: &data)
        for s in samples {
            append(s.timestamp.bitPattern, to: &data)
            append(s.latitude.bitPattern, to: &data)
            append(s.longitude.bitPattern, to: &data)
            append(Float(s.horizontalAccuracy).bitPattern, to: &data)
            append(Float(s.speed).bitPattern, to: &data)
            append(Float(s.course).bitPattern, to: &data)
        }
        return data
    }

    public static func decode(_ data: Data) throws -> [LocationSample] {
        try data.withUnsafeBytes { raw -> [LocationSample] in
            guard raw.count >= headerSize else { throw DecodeError.truncated }
            let v = raw[0]
            guard v == version else { throw DecodeError.unsupportedVersion(v) }
            let count = Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 1, as: UInt32.self)))
            guard raw.count >= headerSize + count * recordSize else { throw DecodeError.truncated }

            func f64(_ offset: Int) -> Double {
                Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)))
            }
            func f32(_ offset: Int) -> Double {
                Double(Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))))
            }

            var samples: [LocationSample] = []
            samples.reserveCapacity(count)
            for i in 0..<count {
                let o = headerSize + i * recordSize
                samples.append(LocationSample(timestamp: f64(o), latitude: f64(o + 8), longitude: f64(o + 16),
                                              horizontalAccuracy: f32(o + 24), speed: f32(o + 28), course: f32(o + 32)))
            }
            return samples
        }
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
