import MapKit
import CoreLocation

class MainViewModel: ObservableObject {
    @Published var isInitialized = false
    @Published var initialRegion: MKCoordinateRegion
    let locationManager = LocationManager.shared
    
    init() {
        initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        setupLocationTracking()
    }
    
    private func setupLocationTracking() {
        locationManager.requestPermission()
        
        if let location = locationManager.currentLocation {
            initialRegion = MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            isInitialized = true
        }
    }
}