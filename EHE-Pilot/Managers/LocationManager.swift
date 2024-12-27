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
    
    // 新增属性用于动态调整前台频率
    private var currentForegroundFrequency: TimeInterval = 30
    private var currentAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters
    
    override init() {
        super.init()
        setupLocationManager()
        loadHomeLocation()
        observeMotionChanges()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = currentAccuracy
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.distanceFilter = kCLDistanceFilterNone
        authorizationStatus = locationManager.authorizationStatus
        updateAuthorizationStatus(locationManager.authorizationStatus)
    }
    
    private func observeMotionChanges() {
        // 当MotionManager状态变化时，动态调整定位策略
        MotionManager.shared.$isUserMoving
            .sink { [weak self] moving in
                guard let self = self else { return }
                self.adjustLocationPolicy(forMoving: moving)
            }
            .store(in: &cancellables)
    }
    
    private func adjustLocationPolicy(forMoving moving: Bool) {
        // 当用户运动时，提高精度，不降低频率（保持30秒）
        // 当用户静止时，降低精度或增加定位间隔，比如改为60秒一次。
        
        if moving {
            // 用户在运动：高精度、更新间隔不变
            currentAccuracy = kCLLocationAccuracyBest
            currentForegroundFrequency = 2*60
        } else {
            // 用户静止：降低精度（百米级别即可），减少更新频率
            currentAccuracy = kCLLocationAccuracyHundredMeters
            currentForegroundFrequency = 10*60
        }
        
        // 应用新的策略
        locationManager.desiredAccuracy = currentAccuracy
        
        // 如果正在前台更新，需要重启Timer
        if updateTimer != nil {
            stopForegroundUpdates()
            startForegroundUpdates()
        }
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
        request.earliestBeginDate = Date(timeIntervalSinceNow: 10 * 60) // 10分钟后尝试唤醒
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule background task: \(error)")
        }
    }

    func startForegroundUpdates() {
        stopForegroundUpdates()
        locationManager.startUpdatingLocation()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: currentForegroundFrequency, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let loc = self.currentLocation {
                self.saveLocationRecord(loc)
            } else {
                self.locationManager.requestLocation()
            }
        }
        updateTimer?.tolerance = currentForegroundFrequency * 0.1
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
    
    // 在saveLocationRecord中设置ifUpdated = false
    private func saveLocationRecord(_ location: CLLocation) {
        let record = LocationRecord(context: context)
        record.timestamp = location.timestamp
        record.latitude = location.coordinate.latitude
        record.longitude = location.coordinate.longitude
        record.gpsAccuracy = NSNumber(value: location.horizontalAccuracy)
        record.ifUpdated = false // 新增这一行，初始为false
        
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
        
        // 保存后尝试上传数据
        attemptUploadRecords()
    }
    
    func attemptUploadRecords() {
        let request: NSFetchRequest<LocationRecord> = LocationRecord.fetchRequest()
        request.predicate = NSPredicate(format: "ifUpdated == false OR ifUpdated = nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LocationRecord.timestamp, ascending: false)]
        request.fetchLimit = 30

        do {
            let notUpdatedRecords = try context.fetch(request)
            print("Found \(notUpdatedRecords.count) records to upload") // 新增打印
            guard !notUpdatedRecords.isEmpty else { return }
            
            // 构建JSON数据
            let formatter = ISO8601DateFormatter()
            
            let dataArray: [[String: Any]] = notUpdatedRecords.map { record in
                let lat = record.latitude
                let lon = record.longitude
                let gpsVal = record.gpsAccuracy != nil ? "\(record.gpsAccuracy!.doubleValue)" : "N/A"
                let isHomeVal = record.isHome ? 1 : 0
                let timeStr = record.timestamp != nil ? formatter.string(from: record.timestamp!) : "N/A"
                
                return [
                    "latitude": lat,
                    "longitude": lon,
                    "gpsAccuracy": gpsVal,
                    "isHome": isHomeVal,
                    "timestamp": timeStr
                ]
            }
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dataArray, options: []) else {
                return
            }
            
            // 构建请求
            var requestURL = URLRequest(url: URL(string: "https://httpbin.org/post")!)
            requestURL.httpMethod = "POST"
            requestURL.setValue("application/json", forHTTPHeaderField: "Content-Type")
            requestURL.httpBody = jsonData
            
            let task = URLSession.shared.dataTask(with: requestURL) { [weak self] data, response, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Upload error: \(error)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("Upload failed, non-200 status code")
                    return
                }
                
                // 上传成功，将notUpdatedRecords的ifUpdated设为true
                self.context.perform {
                    for rec in notUpdatedRecords {
                        rec.ifUpdated = true
                    }
                    
                    do {
                        try self.context.save()
                        print("Successfully updated records as ifUpdated = true")
                    } catch {
                        print("Error updating records after upload: \(error)")
                    }
                }
            }
            
            task.resume()
        } catch {
            print("Fetch not updated records error: \(error)")
        }
    }

    private func saveLocationRecordFromVisit(_ visit: CLVisit) {
        let coordinate = visit.coordinate
        let timestamp = visit.arrivalDate == Date.distantPast ? Date() : visit.arrivalDate
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        let record = LocationRecord(context: context)
        record.timestamp = timestamp
        record.latitude = coordinate.latitude
        record.longitude = coordinate.longitude
        record.gpsAccuracy = nil
        
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
            print("Error saving location record from visit: \(error)")
        }
    }
    
    private func updateAuthorizationStatus(_ status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
            self.isAuthorized = (status == .authorizedAlways || status == .authorizedWhenInUse)
            
            if status == .authorizedAlways {
                self.locationManager.startMonitoringVisits()
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
        // 后台任务或前台timer定期写入，无需在此立即写入
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        saveLocationRecordFromVisit(visit)
    }
}
