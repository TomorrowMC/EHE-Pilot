import Foundation
import CoreData
import SwiftUI

class JHDataExchangeManager: ObservableObject {
    // 单例实例
    static let shared = JHDataExchangeManager()
    
    // Published properties for UI updates
    @Published var isUploading = false
    @Published var lastUploadStatus: String = "Not uploaded"
    @Published var lastUploadTime: Date?
    
    // Server configuration
    private let stellaPatientId = "40001"  // Stella Park's PatientID (updated)
    private let deviceId = "70001"         // Device ID
    private let organizationId = "20012"   // JH Data Exchange's OrganizationID (updated)
    private let studyId = "30001"          // Spezi's StudyID
    
    // Initialize
    private init() {}
    
    // 从CoreData获取位置记录
    func fetchLocationRecords(limit: Int = 10) -> [LocationRecord] {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<LocationRecord> = LocationRecord.fetchRequest()
        
        // Only get records that haven't been uploaded
        request.predicate = NSPredicate(format: "ifUpdated == %@", NSNumber(value: false))
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LocationRecord.timestamp, ascending: false)]
        request.fetchLimit = limit
        
        do {
            return try context.fetch(request)
        } catch {
            print("Error fetching location records: \(error)")
            return []
        }
    }
    
    // 创建血糖记录FHIR Bundle (但实际上放地理位置数据)
    func createFHIRBundle(from records: [LocationRecord]) -> [String: Any] {
        var entries: [[String: Any]] = []
        
        for record in records {
            // 创建内部JSON数据 - 使用与示例匹配的格式
            let geoPositionData = createGeoPositionData(from: record)
            
            // Base64编码位置数据
            if let jsonData = try? JSONSerialization.data(withJSONObject: geoPositionData),
               let base64String = jsonData.base64EncodedString().data(using: .utf8)?.base64EncodedString() {
                
            // Create Entry object
            let entry: [String: Any] = [
                "resource": [
                    "resourceType": "Observation",
                    "status": "final",
                    "subject": [
                        "reference": "Patient/\(stellaPatientId)"
                    ],
                    "device": [
                        "reference": "Device/\(deviceId)"
                    ],
                    "code": [
                        "coding": [
                            [
                                "system": "https://w3id.org/openmhealth",
                                "code": "omh:blood-glucose:4.0"
                            ]
                        ]
                    ],
                    "valueAttachment": [
                        "contentType": "application/json",
                        "data": base64String
                    ],
                    "identifier": [
                        [
                            "value": UUID().uuidString,
                            "system": "https://ehr.example.com"
                        ]
                    ]
                ],
                "request": [
                    "method": "POST",
                    "url": "Observation"
                ]
            ]
                
                entries.append(entry)
            }
        }
        
        // 创建Bundle
        return [
            "resourceType": "Bundle",
            "type": "batch",
            "entry": entries
        ]
    }
    
    // 创建GeoPosition数据 - 使用与服务器示例匹配的格式
    private func createGeoPositionData(from record: LocationRecord) -> [String: Any] {
        var data: [String: Any] = [:]
        
        // 第一种格式(完整格式)
        data["latitude"] = [
            "value": record.latitude,
            "unit": "deg"
        ]
        
        data["longitude"] = [
            "value": record.longitude,
            "unit": "deg"
        ]
        
        // 定位系统
        data["positioningSystem"] = "GPS"
        
        // 添加时间戳信息 (如果服务器需要)
        if let timestamp = record.timestamp {
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime]
            let dateTimeString = iso8601Formatter.string(from: timestamp)
            
            data["effective_time_frame"] = [
                "date_time": dateTimeString
            ]
        }
        
        return data
    }
    
    // 上传数据到服务器
    func uploadLocationData(authManager: AuthManager, completion: @escaping (Bool, String) -> Void) {
        // Ensure authenticated
        guard authManager.isAuthenticated,
              let accessToken = authManager.currentAccessToken() else {
            DispatchQueue.main.async {
                self.lastUploadStatus = "Not authorized, please login first"
                completion(false, "Not authorized, please login first")
            }
            return
        }
        
        // Get location records
        let records = fetchLocationRecords(limit: 5) // Upload 5 records at a time
        
        if records.isEmpty {
            DispatchQueue.main.async {
                self.lastUploadStatus = "No new location records to upload"
                completion(false, "No new location records to upload")
            }
            return
        }
        
        // 创建FHIR Bundle
        let bundle = createFHIRBundle(from: records)
        
        // Prepare API request
        // Use base URL, remove "/o" from path
        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        guard let fhirURL = URL(string: "\(baseURLString)/fhir/r5/") else {
            DispatchQueue.main.async {
                self.lastUploadStatus = "Invalid FHIR endpoint URL"
                completion(false, "Invalid FHIR endpoint URL")
            }
            return
        }
        
        // 创建请求
        var request = URLRequest(url: fhirURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 序列化请求体
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: bundle, options: [])
            request.httpBody = jsonData
            
            // Print request data for debugging
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("Upload data details:")
                print(jsonString)
            }
            
            DispatchQueue.main.async {
                self.isUploading = true
            }
            
            // 发送请求
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.lastUploadTime = Date()
                    
                    if let error = error {
                        self.lastUploadStatus = "上传失败: \(error.localizedDescription)"
                        completion(false, "上传失败: \(error.localizedDescription)")
                        return
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        let statusCode = httpResponse.statusCode
                        
                        if (200...299).contains(statusCode) {
                            // Successfully uploaded, mark records as uploaded
                            self.markRecordsAsUploaded(records)
                            self.lastUploadStatus = "Successfully uploaded \(records.count) records"
                            completion(true, "Successfully uploaded \(records.count) records")
                        } else {
                            var message = "Upload failed, status code: \(statusCode)"
                            
                            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                                print("Server response: \(responseString)")
                                message += ", response: \(responseString)"
                            }
                            
                            self.lastUploadStatus = message
                            completion(false, message)
                        }
                    }
                }
            }
            
            task.resume()
            
        } catch {
            DispatchQueue.main.async {
                self.isUploading = false
                self.lastUploadStatus = "Failed to serialize data: \(error.localizedDescription)"
                completion(false, "Failed to serialize data: \(error.localizedDescription)")
            }
        }
    }
    
    // 标记记录为已上传
    private func markRecordsAsUploaded(_ records: [LocationRecord]) {
        let context = PersistenceController.shared.container.viewContext
        
        for record in records {
            record.ifUpdated = true
        }
        
        do {
            try context.save()
        } catch {
            print("Error saving context after marking records as uploaded: \(error)")
        }
    }
    
    // 生成简单的示例数据
    func generateSampleDataWithSimpleFormat(count: Int = 3) {
        let context = PersistenceController.shared.container.viewContext
        
        // 纽约坐标附近范围
        let latitudeRange = (40.70...40.75)
        let longitudeRange = (71.01...73.95)
        
        for i in 0..<count {
            let record = LocationRecord(context: context)
            
            record.latitude = Double.random(in: latitudeRange)
            record.longitude = Double.random(in: longitudeRange)
            record.timestamp = Date().addingTimeInterval(-Double(i) * 3600) // 每小时一条
            record.isHome = false
            record.gpsAccuracy = NSNumber(value: Double.random(in: 2...10))
            record.ifUpdated = false
        }
        
        // Generate New York coordinates sample data
        do {
            try context.save()
            print("Successfully generated \(count) NYC sample data points")
        } catch {
            print("Error generating sample location records: \(error)")
        }
    }
    
    // 生成旧金山样例数据
    func generateSampleDataWithFullFormat(count: Int = 2) {
        let context = PersistenceController.shared.container.viewContext
        
        // 旧金山坐标附近范围
        let latitudeRange = (37.75...37.78)
        let longitudeRange = (121.43...122.40)
        
        for i in 0..<count {
            let record = LocationRecord(context: context)
            
            record.latitude = Double.random(in: latitudeRange)
            record.longitude = Double.random(in: longitudeRange)
            record.timestamp = Date().addingTimeInterval(-Double(i) * 7200) // 每2小时一条
            record.isHome = false
            record.gpsAccuracy = NSNumber(value: Double.random(in: 2...10))
            record.ifUpdated = false
        }
        
        // Generate San Francisco coordinates sample data
        do {
            try context.save()
            print("Successfully generated \(count) San Francisco sample data points")
        } catch {
            print("Error generating sample location records: \(error)")
        }
    }
}
