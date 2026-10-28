import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads GPX files into fixes. Accepts both `<wpt>` (what Xcode's location
/// simulation uses) and `<trkpt>`. Reach's fixtures add an optional `<hacc>`
/// element for horizontal accuracy; without it, fixes get `defaultAccuracy`.
public enum GPX {
    public enum ParseError: Error, Equatable {
        case invalidXML(String)
    }

    public static func parse(_ data: Data, defaultAccuracy: Double = 5) throws -> [LocationSample] {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        let delegate = Delegate(defaultAccuracy: defaultAccuracy)
        parser.delegate = delegate
        guard parser.parse() else {
            throw ParseError.invalidXML(parser.parserError?.localizedDescription ?? "unknown error")
        }
        return delegate.samples
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let defaultAccuracy: Double
        var samples: [LocationSample] = []
        private var current: LocationSample?
        private var text = ""
        private let iso = ISO8601DateFormatter()
        private let isoFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f
        }()

        init(defaultAccuracy: Double) {
            self.defaultAccuracy = defaultAccuracy
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            text = ""
            guard elementName == "wpt" || elementName == "trkpt",
                  let lat = attributes["lat"].flatMap(Double.init),
                  let lon = attributes["lon"].flatMap(Double.init) else { return }
            current = LocationSample(timestamp: 0, latitude: lat, longitude: lon, horizontalAccuracy: defaultAccuracy)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "time":
                if let date = isoFractional.date(from: value) ?? iso.date(from: value) {
                    current?.timestamp = date.timeIntervalSince1970
                }
            case "hacc":
                if let v = Double(value) { current?.horizontalAccuracy = v }
            case "speed":
                if let v = Double(value) { current?.speed = v }
            case "wpt", "trkpt":
                if let current { samples.append(current) }
                current = nil
            default:
                break
            }
        }
    }
}
