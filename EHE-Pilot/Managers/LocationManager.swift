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
import UIKit
import SwiftUI

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isAuthorized = false
    @Published var homeLocation: HomeLocation?
    @Published var currentLocationStatus: Bool = false
    
    // 状态追踪属性
    @Published var isUploading = false
    @Published var lastUploadStatus: (success: Bool, message: String)?
    
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
    //
    // Modified attemptUploadRecords method for LocationManager class
    // Replace the existing method with this implementation
    //

    func attemptUploadRecords() {
        // 首先，检查是否通过AuthManager进行了身份验证
        if let authManager = getAuthManager(), authManager.isAuthenticated {
            // 使用FHIRUploadService上传为geoposition类型
            FHIRUploadService.shared.uploadLocationRecords(authManager: authManager) { success, message in
                print("Location upload result: \(success ? "Success" : "Failed") - \(message)")
            }
        } else {
            // 如果未经身份验证，则回退到原始方法
            attemptUploadRecordsLegacy()
        }
    }

    // Keep the original method as a fallback
    private func attemptUploadRecordsLegacy() {
        let request: NSFetchRequest<LocationRecord> = LocationRecord.fetchRequest()
        request.predicate = NSPredicate(format: "ifUpdated == false OR ifUpdated = nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LocationRecord.timestamp, ascending: false)]
        request.fetchLimit = 10
        
        do {
            let notUpdatedRecords = try context.fetch(request)
            print("Found \(notUpdatedRecords.count) records to upload")
            guard !notUpdatedRecords.isEmpty else { return }
            
            // 构建FHIR Bundle
            var bundleEntries: [[String: Any]] = []
            
            for record in notUpdatedRecords {
                // 构建位置数据 - 保留复杂数据结构
                var locationData: [String: Any] = [
                    "latitude": [
                        "value": record.latitude,
                        "unit": "deg"
                    ],
                    "longitude": [
                        "value": record.longitude,
                        "unit": "deg"
                    ],
                    "positioning_system": "GPS",
                    "effective_time_frame": [
                        "date_time": ISO8601DateFormatter().string(from: record.timestamp ?? Date())
                    ]
                ]
                
                // 如果有GPS精度数据，添加卫星信号强度
                if let accuracy = record.gpsAccuracy?.doubleValue {
                    locationData["satellite_signal_strengths"] = [
                        ["value": Int(accuracy), "unit": "dB"]
                    ]
                }
                
                // 编码数据
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: locationData)
                    let base64String = jsonData.base64EncodedString()
                    
                    // 格式化日期时间
                    let effectiveDateTime = ISO8601DateFormatter().string(from: record.timestamp ?? Date())
                    
                    // 构建FHIR Observation资源 - 使用geoposition类型
                    let observationEntry: [String: Any] = [
                        "resource": [
                            "resourceType": "Observation",
                            "status": "final",
                            "category": [
                                [
                                    "coding": [
                                        [
                                            "system": "http://terminology.hl7.org/CodeSystem/observation-category",
                                            "code": "survey",
                                            "display": "Survey"
                                        ]
                                    ]
                                ]
                            ],
                            "code": [
                                "coding": [
                                    [
                                        "system": "https://w3id.org/openmhealth",
                                        "code": "omh:geoposition:1.0",
                                        "display": "Geoposition"
                                    ]
                                ]
                            ],
                            "subject": [
                                "reference": "Patient/40001"
                            ],
                            "device": [
                                "reference": "Device/70001"
                            ],
                            "effectiveDateTime": effectiveDateTime,
                            "valueAttachment": [
                                "contentType": "application/json",
                                "data": base64String
                            ]
                        ],
                        "request": [
                            "method": "POST",
                            "url": "Observation"
                        ]
                    ]
                    
                    bundleEntries.append(observationEntry)
                    
                } catch {
                    print("Error serializing location data: \(error)")
                    continue
                }
            }
            
            // 构建完整的FHIR Bundle
            let bundle: [String: Any] = [
                "resourceType": "Bundle",
                "type": "batch",
                "entry": bundleEntries
            ]
            
            // 发送请求
            guard let jsonData = try? JSONSerialization.data(withJSONObject: bundle) else {
                print("Failed to serialize bundle")
                return
            }
            
            var request = URLRequest(url: URL(string: "https://httpbin.org/post")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData
            
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
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
                
                // 标记记录为已更新
                self.context.perform {
                    for record in notUpdatedRecords {
                        record.ifUpdated = true
                    }
                    
                    do {
                        try self.context.save()
                        print("Successfully marked records as updated")
                    } catch {
                        print("Error updating records after upload: \(error)")
                    }
                }
            }
            
            task.resume()
            
        } catch {
            print("Fetch error: \(error)")
        }
    }
    
    // Helper method to get AuthManager instance
    private func getAuthManager() -> AuthManager? {
        // Find AuthManager in SwiftUI environment
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController,
           let hostingController = rootViewController as? UIHostingController<AnyView> {
            
            // Try to extract AuthManager from environment
            // This is a bit hacky, but works for accessing the singleton
            return AppDelegate.shared.authManager
        }
        
        // Fall back to creating a new instance if needed
        return AppDelegate.shared.authManager
    }
    // 在LocationManager类中添加

    

    func getLatestRecordsJSON() -> String? {
        let request: NSFetchRequest<LocationRecord> = LocationRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LocationRecord.timestamp, ascending: false)]
        request.fetchLimit = 20
        
        do {
            let records = try context.fetch(request)
            guard !records.isEmpty else { return nil }
            
            var bundleEntries: [[String: Any]] = []
            
            for record in records {
                var locationData: [String: Any] = [
                    "latitude": [
                        "value": record.latitude,
                        "unit": "deg"
                    ],
                    "longitude": [
                        "value": record.longitude,
                        "unit": "deg"
                    ],
                    "positioning_system": "GPS",
                    "effective_time_frame": [
                        "date_time": ISO8601DateFormatter().string(from: record.timestamp ?? Date())
                    ]
                ]
                
                if let accuracy = record.gpsAccuracy?.doubleValue {
                    locationData["satellite_signal_strengths"] = [
                        ["value": Int(accuracy), "unit": "dB"]
                    ]
                }
                
                // 修改这部分的错误处理方式
                do {
                    let jsonData = try JSONSerialization.data(withJSONObject: locationData)
                    let base64String = jsonData.base64EncodedString()
                    
                    let observationEntry: [String: Any] = [
                        "resource": [
                            "resourceType": "Observation",
                            "status": "final",
                            "code": [
                                "coding": [
                                    [
                                        "system": "https://w3id.org/openmhealth",
                                        "code": "omh:geoposition:1.0"
                                    ]
                                ]
                            ],
                            "subject": [
                                "reference": "Patient/40001"
                            ],
                            "device": [
                                "reference": "Device/70001"
                            ],
                            "valueAttachment": [
                                "contentType": "application/json",
                                "data": base64String
                            ]
                        ],
                        "request": [
                            "method": "POST",
                            "url": "Observation"
                        ]
                    ]
                    
                    bundleEntries.append(observationEntry)
                    
                } catch {
                    print("Error serializing location data: \(error)")
                    continue
                }
            }
            
            let bundle: [String: Any] = [
                "resourceType": "Bundle",
                "type": "batch",
                "entry": bundleEntries
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: bundle, options: .prettyPrinted)
            return String(data: jsonData, encoding: .utf8)
            
        } catch {
            print("Fetch error: \(error)")
            return nil
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
