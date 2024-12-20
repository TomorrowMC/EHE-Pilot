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
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isAuthorized = false
    @Published var homeLocation: HomeLocation?
    @Published var currentLocationStatus: Bool = false
    
    private let locationManager = CLLocationManager()
    private let context = PersistenceController.shared.container.viewContext
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    override init() {
        super.init()
        setupLocationManager()
        loadHomeLocation()
    }
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.distanceFilter = kCLDistanceFilterNone // 尝试无距离过滤，持续更新
        authorizationStatus = locationManager.authorizationStatus
        updateAuthorizationStatus(locationManager.authorizationStatus)
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.locationManager.requestAlwaysAuthorization()
        }
    }
    
    func handleBackgroundTask(_ task: BGAppRefreshTask) {
        let taskCompletionHandler = { [weak self] in
            task.setTaskCompleted(success: true)
            self?.scheduleBackgroundTask()
        }
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        locationManager.requestLocation()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            taskCompletionHandler()
        }
    }
    
    func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: "com.EHE-Pilot.LocationUpdate")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule background task: \(error)")
        }
    }

    // 在前台时每30秒无论位置是否更新都写入CoreData
    func startForegroundUpdates() {
        stopForegroundUpdates() // 先清理可能存在的timer
        locationManager.startUpdatingLocation()
        
        let frequency: TimeInterval = 30
        updateTimer = Timer.scheduledTimer(withTimeInterval: frequency, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // 无论location是否变化，都使用currentLocation写入CoreData
            if let loc = self.currentLocation {
                self.saveLocationRecord(loc)
            } else {
                // 如果还没有currentLocation（可能刚启动还没拿到位置）
                // 可以尝试requestLocation()获取一次最新位置
                self.locationManager.requestLocation()
            }
        }
        updateTimer?.tolerance = frequency * 0.1
    }
    
    func stopForegroundUpdates() {
        locationManager.stopUpdatingLocation()
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
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
                if let currentLocation = self.currentLocation {
                    self.updateCurrentLocationStatus(for: currentLocation)
                }
            }
        } catch {
            print("Error saving home location: \(error)")
        }
    }
    
    private func saveLocationRecord(_ location: CLLocation) {
        let record = LocationRecord(context: context)
        record.timestamp = location.timestamp
        record.latitude = location.coordinate.latitude
        record.longitude = location.coordinate.longitude
        
        record.gpsAccuracy = NSNumber(value: location.horizontalAccuracy)


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

    
    private func updateAuthorizationStatus(_ status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
            self.isAuthorized = (status == .authorizedAlways || status == .authorizedWhenInUse)
            
            if status == .authorizedAlways {
                self.locationManager.startMonitoringSignificantLocationChanges()
                self.scheduleBackgroundTask()
            } else {
                self.locationManager.stopMonitoringSignificantLocationChanges()
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
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationStatus(manager.authorizationStatus)
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = location
            self.updateCurrentLocationStatus(for: location)
        }
        // 不在这里立即写入CoreData，因为定时器会定期写入，无论位置变化与否
        // 如需立即写入，也可在这里调用saveLocationRecord(location)多次记录
        // 但为了与定时机制统一，可以保持在timer中定期写入。
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error)")
    }
}
