import CoreLocation
import CoreData

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    private let locationManager = CLLocationManager()
    private let context = PersistenceController.shared.container.viewContext
    
    @Published var currentLocation: CLLocation?
    @Published var homeLocation: HomeLocation?
    @Published var isAuthorized = false
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.distanceFilter = 50 // 每50米更新一次
        
        // 加载家的位置
        loadHomeLocation()
    }
    
    func requestPermission() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func startMonitoring() {
        locationManager.startUpdatingLocation()
    }
    
    private func loadHomeLocation() {
        let request: NSFetchRequest<HomeLocation> = HomeLocation.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            homeLocation = results.first
        } catch {
            print("Error fetching home location: \(error)")
        }
    }
    
    func saveHomeLocation(latitude: Double, longitude: Double, radius: Double) {
        let home = HomeLocation(context: context)
        home.latitude = latitude
        home.longitude = longitude
        home.radius = radius
        home.timestamp = Date()
        
        do {
            try context.save()
            homeLocation = home
        } catch {
            print("Error saving home location: \(error)")
        }
    }
    
    func saveLocationRecord(_ location: CLLocation) {
        let record = LocationRecord(context: context)
        record.timestamp = Date()
        record.latitude = location.coordinate.latitude
        record.longitude = location.coordinate.longitude
        
        if let home = homeLocation {
            let homeCoordinate = CLLocation(latitude: home.latitude, longitude: home.longitude)
            let distance = location.distance(from: homeCoordinate)
            record.distanceFromHome = distance
            record.isHome = distance <= home.radius
        }
        
        do {
            try context.save()
        } catch {
            print("Error saving location record: \(error)")
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorized = true
            startMonitoring()
        default:
            isAuthorized = false
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        saveLocationRecord(location)
    }
}