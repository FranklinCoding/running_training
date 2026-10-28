import MapKit
import SwiftUI

/// MKMapView wrapper. Uses UIKit's map rather than SwiftUI's `Map` because
/// tens of thousands of hexagons need a custom overlay renderer.
struct ExploredMapView: UIViewRepresentable {
    let overlay: HexOverlay
    let revision: Int

    static let newYork = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -73.9560),
                                            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3))

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = configuration
        map.showsUserLocation = true
        map.setRegion(Self.newYork, animated: false)
        map.addOverlay(overlay, level: .aboveRoads)

        let tracking = MKUserTrackingButton(mapView: map)
        tracking.translatesAutoresizingMaskIntoConstraints = false
        tracking.backgroundColor = .secondarySystemBackground
        tracking.layer.cornerRadius = 8
        map.addSubview(tracking)
        NSLayoutConstraint.activate([
            tracking.trailingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            tracking.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 12),
        ])
        context.coordinator.revision = revision
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        guard context.coordinator.revision != revision else { return }
        context.coordinator.revision = revision
        context.coordinator.renderer?.setNeedsDisplay()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var revision = 0
        var renderer: HexOverlayRenderer?

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard overlay is HexOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = HexOverlayRenderer(overlay: overlay)
            self.renderer = renderer
            return renderer
        }
    }
}
