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
        locationManager.desiredAccuracy = kCLLocationAccuracyBest  // 始终使用最高精度
        locationManager.activityType = .fitness  // 更适合追踪运动状态
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.distanceFilter = 5  // 每5米更新一次位置
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
        // 当用户运动时，提高精度
        // 当用户静止时，降低精度或增加定位间隔
        
        if moving {
            currentAccuracy = kCLLocationAccuracyBest
            currentForegroundFrequency = 120  // 移动时30秒更新一次
            locationManager.distanceFilter = 20  // 移动时每5米更新
        } else {
            currentAccuracy = kCLLocationAccuracyNearestTenMeters  // 静止时稍微降低精度，但不要太低
            currentForegroundFrequency = 8 * 60  // 静止时5分钟更新一次
            locationManager.distanceFilter = 100  // 静止时每20米更新
        }
        
        locationManager.desiredAccuracy = currentAccuracy
        
        // 重启Timer
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
    
    // 增加位置过滤逻辑
    private func isValidLocation(_ location: CLLocation) -> Bool {
        // 检查水平精度是否在合理范围内
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 100 {
            return false
        }
        
        // 检查时间戳是否是最近的
        let timeThreshold = 10.0 // 10秒
        if abs(location.timestamp.timeIntervalSinceNow) > timeThreshold {
            return false
        }
        
        return true
    }
    
    // 在saveLocationRecord中设置ifUpdated = false
    private func saveLocationRecord(_ location: CLLocation) {
        if location.horizontalAccuracy <= 0 {
            // 如果精度无效，请求一次高精度更新
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.requestLocation()
            return
        }
        
        let record = LocationRecord(context: context)
        record.timestamp = location.timestamp
        record.latitude = location.coordinate.latitude
        record.longitude = location.coordinate.longitude
        record.gpsAccuracy = NSNumber(value: location.horizontalAccuracy)
        record.ifUpdated = false // 初始为false
        
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
    
    // 将地理位置JSON改为Open mHealth "Geoposition"格式
    func attemptUploadRecords() {
        let request: NSFetchRequest<LocationRecord> = LocationRecord.fetchRequest()
        request.predicate = NSPredicate(format: "ifUpdated == false OR ifUpdated = nil")
        // 根据需求，你可以改为 ascending 或 descending
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LocationRecord.timestamp, ascending: false)]
        request.fetchLimit = 30

        do {
            let notUpdatedRecords = try context.fetch(request)
            print("Found \(notUpdatedRecords.count) records to upload")
            guard !notUpdatedRecords.isEmpty else { return }
            
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.timeZone = TimeZone(secondsFromGMT: 0) // or userTimeZone if needed
            
            // 构建Open mHealth Geoposition数组
            let geopositionArray: [[String: Any]] = notUpdatedRecords.map { record in
                // latitude / longitude
                let latitudeObj: [String: Any] = [
                    "value": record.latitude,
                    "unit": "deg"
                ]
                let longitudeObj: [String: Any] = [
                    "value": record.longitude,
                    "unit": "deg"
                ]
                
                // effective_time_frame
                let timeStr = record.timestamp != nil
                    ? isoFormatter.string(from: record.timestamp!)
                    : "N/A"
                
                let effectiveTimeFrame: [String: Any] = [
                    "date_time": timeStr
                ]
                
                // (可选) accuracy视为extension字段
                // (可选) isHome也放在 extension
                var geoDict: [String: Any] = [
                    "latitude": latitudeObj,
                    "longitude": longitudeObj,
                    "effective_time_frame": effectiveTimeFrame
                ]
                
                // 如果想加一个自定义扩展, 例如 "omh_extension_accuracy"
                if let gpsAccNum = record.gpsAccuracy {
                    let gpsAccuracyVal = gpsAccNum.doubleValue
                    geoDict["omh_extension_accuracy"] = gpsAccuracyVal
                }
                
                // 如果想加 isHome
                geoDict["omh_extension_isHome"] = record.isHome
                
                return geoDict
            }
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: geopositionArray, options: [.prettyPrinted]) else {
                print("Failed to convert geoposition array to JSON data")
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

// MARK: - CLLocationManagerDelegate
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
        // 不在这里立即写入CoreData，因为前台timer或后台task已处理
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error)")
    }
    
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        saveLocationRecordFromVisit(visit)
    }
}
