//
//  LocationManager.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//


import CoreLocation
import CoreData
import Combine
import BackgroundTasks
class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    // MARK: - Published Properties
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isAuthorized = false
    @Published var homeLocation: HomeLocation?
    @Published var currentLocationStatus: Bool = false
    
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
        locationManager.showsBackgroundLocationIndicator = true  // 添加这行
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.distanceFilter = 50
        
        authorizationStatus = locationManager.authorizationStatus
        updateAuthorizationStatus(locationManager.authorizationStatus)
        // 设置显著位置变化监测，这是后台定位的关键
        locationManager.startMonitoringSignificantLocationChanges()
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.locationManager.requestAlwaysAuthorization()
        }
    }
    
    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.yourdomain.locationUpdate", using: nil) { task in
            self.handleBackgroundTask(task as! BGAppRefreshTask)
        }
    }
    
    private func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: "com.yourdomain.locationUpdate")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60) // 5 minutes
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule background task: \(error)")
        }
    }
    
    func handleBackgroundTask(_ task: BGAppRefreshTask) {
        // 创建一个任务完成的标记
        let taskCompletionHandler = { [weak self] in
            task.setTaskCompleted(success: true)
            self?.scheduleBackgroundTask() // 安排下一次任务
        }
        
        // 设置任务超时处理
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        // 请求一次位置更新
        locationManager.requestLocation()
        
        // 5秒后完成任务
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            taskCompletionHandler()
        }
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
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = HomeLocation.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        do {
            try context.execute(deleteRequest)
            
            let home = HomeLocation(context: context)
            home.latitude = latitude
            home.longitude = longitude
            home.radius = radius
            home.timestamp = Date()
            
            try context.save()
            
            DispatchQueue.main.async {
                self.homeLocation = home
                // 更新当前位置状态
                if let currentLocation = self.currentLocation {
                    self.updateCurrentLocationStatus(for: currentLocation)
                }
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

    private func updateCurrentLocationStatus(for location: CLLocation) {
        guard let home = homeLocation else {
            currentLocationStatus = false
            return
        }
        
        let homeCoordinate = CLLocation(latitude: home.latitude, longitude: home.longitude)
        let distance = location.distance(from: homeCoordinate)
        
        DispatchQueue.main.async {
            self.currentLocationStatus = distance <= home.radius
        }
    }
    

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.currentLocation = location
            self.updateCurrentLocationStatus(for: location)
        }
        
        saveLocationRecord(location)
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationStatus(manager.authorizationStatus)
        if manager.authorizationStatus == .authorizedAlways {
            locationManager.startMonitoringSignificantLocationChanges()
            scheduleBackgroundTask()
        }
    }
    
}
