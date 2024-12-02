import CoreLocation
import CoreData
import Combine

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    // MARK: - Published Properties
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isAuthorized = false
    @Published var homeLocation: HomeLocation?
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private let context = PersistenceController.shared.container.viewContext
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupLocationManager()
        loadHomeLocation()
        setupUpdateFrequencyObserver()
    }
    
    // MARK: - Setup Methods
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.distanceFilter = 50 // Update every 50 meters
        
        // Get initial authorization status
        authorizationStatus = locationManager.authorizationStatus
        updateAuthorizationStatus(locationManager.authorizationStatus)
    }
    
    private func setupUpdateFrequencyObserver() {
        NotificationCenter.default.publisher(for: NSNotification.Name("LocationUpdateFrequencyChanged"))
            .sink { [weak self] notification in
                if let frequency = notification.userInfo?["frequency"] as? TimeInterval {
                    self?.updateLocationUpdateFrequency(frequency)
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    func requestPermission() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func startMonitoring() {
        locationManager.startUpdatingLocation()
        startUpdateTimer()
    }
    
    func stopMonitoring() {
        locationManager.stopUpdatingLocation()
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    // MARK: - Location Update Timer
    private func startUpdateTimer() {
        let frequency = UserDefaults.standard.double(forKey: "locationUpdateFrequency")
        updateLocationUpdateFrequency(frequency > 0 ? frequency : 600) // Default to 10 minutes
    }
    
    private func updateLocationUpdateFrequency(_ frequency: TimeInterval) {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: frequency, repeats: true) { [weak self] _ in
            self?.locationManager.requestLocation()
        }
        updateTimer?.tolerance = frequency * 0.1 // 10% tolerance
    }
    
    // MARK: - Home Location Management
    private func loadHomeLocation() {
        let request: NSFetchRequest<HomeLocation> = HomeLocation.fetchRequest()
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            DispatchQueue.main.async {
                self.homeLocation = results.first
            }
        } catch {
            print("Error fetching home location: \(error)")
        }
    }
    
    func saveHomeLocation(latitude: Double, longitude: Double, radius: Double) {
        // Delete existing home locations
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = HomeLocation.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        do {
            try context.execute(deleteRequest)
            
            // Create new home location
            let home = HomeLocation(context: context)
            home.latitude = latitude
            home.longitude = longitude
            home.radius = radius
            home.timestamp = Date()
            
            try context.save()
            
            DispatchQueue.main.async {
                self.homeLocation = home
            }
        } catch {
            print("Error saving home location: \(error)")
        }
    }
    
    // MARK: - Location Record Management
    private func saveLocationRecord(_ location: CLLocation) {
        let record = LocationRecord(context: context)
        record.timestamp = location.timestamp
        record.latitude = location.coordinate.latitude
        record.longitude = location.coordinate.longitude
        
        if let home = homeLocation {
            let homeCoordinate = CLLocation(latitude: home.latitude, longitude: home.longitude)
            let distance = location.distance(from: homeCoordinate)
            record.distanceFromHome = distance
            record.isHome = distance <= home.radius
        } else {
            record.distanceFromHome = 0
            record.isHome = false
        }
        
        do {
            try context.save()
        } catch {
            print("Error saving location record: \(error)")
        }
    }
    
    // MARK: - Authorization Status Management
    private func updateAuthorizationStatus(_ status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
            self.isAuthorized = (status == .authorizedAlways || status == .authorizedWhenInUse)
            
            if self.isAuthorized {
                self.startMonitoring()
            } else {
                self.stopMonitoring()
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationStatus(manager.authorizationStatus)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.currentLocation = location
        }
        
        saveLocationRecord(location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error)")
    }
}