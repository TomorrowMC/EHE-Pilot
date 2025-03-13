import Foundation
import CoreData
import SwiftUI

class LocationUploadManager: ObservableObject {
    // 单例实例
    static let shared = LocationUploadManager()
    
    // Published properties for UI updates
    @Published var isUploading = false
    @Published var lastUploadStatus: String = "Not uploaded"
    @Published var lastUploadTime: Date?
    
    // Fixed Patient ID and Device ID
    private let patientId = "40001"  // This is the default Patient ID
    private let deviceId = "70001"   // This is the default Device ID
    private let stellaParkPatientId = "40001" // Based on the example in the image, might be Stella Park's ID
    
    // 初始化
    private init() {}
    
    // 从CoreData获取位置记录
    func fetchLocationRecords(limit: Int = 10) -> [LocationRecord] {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<LocationRecord> = LocationRecord.fetchRequest()
        
        // 只获取未上传过的记录
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
    
    // 将位置记录转换为FHIR格式的Bundle
    func createFHIRBundle(from records: [LocationRecord]) -> [String: Any] {
        var entries: [[String: Any]] = []
        
        for record in records {
            // 创建内部JSON数据
            let geoPositionData = createGeoPositionData(from: record)
            
            // Base64编码位置数据
            if let jsonData = try? JSONSerialization.data(withJSONObject: geoPositionData),
               let base64String = jsonData.base64EncodedString().data(using: .utf8)?.base64EncodedString() {
                
                // 创建Entry对象
                let entry: [String: Any] = [
                    "resource": [
                        "resourceType": "Observation",
                        "status": "final",
                        "subject": [
                            "reference": "Patient/\(patientId)"
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
    
    // 创建GeoPosition数据
    private func createGeoPositionData(from record: LocationRecord) -> [String: Any] {
        var data: [String: Any] = [:]
        
        // 经度信息
        data["latitude"] = [
            "value": record.latitude,
            "unit": "deg"
        ]
        
        // 纬度信息
        data["longitude"] = [
            "value": record.longitude,
            "unit": "deg"
        ]
        
        // 定位系统
        data["positioning_system"] = "GPS"
        
        // 信号强度（如果有）
        if let accuracy = record.gpsAccuracy?.doubleValue {
            // 将GPS精度转换为卫星信号强度估计值（简化处理）
            let signalStrength = max(5, 30 - Int(accuracy * 2)) // 简单计算，精度越高，信号越强
            data["satellite_signal_strengths"] = [
                [
                    "value": signalStrength,
                    "unit": "dB"
                ]
            ]
        }
        
        // 时间信息
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
        // 确保已经登录
        guard authManager.isAuthenticated,
              let accessToken = authManager.currentAccessToken() else {
            DispatchQueue.main.async {
                self.lastUploadStatus = "未授权，请先登录"
                completion(false, "未授权，请先登录")
            }
            return
        }
        
        // 获取位置记录
        let records = fetchLocationRecords(limit: 5) // 每次上传5条记录
        
        if records.isEmpty {
            DispatchQueue.main.async {
                self.lastUploadStatus = "没有新的位置记录需要上传"
                completion(false, "没有新的位置记录需要上传")
            }
            return
        }
        
        // 创建FHIR Bundle
        let bundle = createFHIRBundle(from: records)
        
        // 准备API请求
        // 使用基础URL，去掉路径中的 "/o"
        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        guard let fhirURL = URL(string: "\(baseURLString)/fhir/r5/") else {
            DispatchQueue.main.async {
                self.lastUploadStatus = "无效的FHIR端点URL"
                completion(false, "无效的FHIR端点URL")
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
            
            print("Uploading FHIR Bundle: \(String(data: jsonData, encoding: .utf8) ?? "")")
            
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
                            // 成功上传，标记记录为已上传
                            self.markRecordsAsUploaded(records)
                            self.lastUploadStatus = "成功上传 \(records.count) 条记录"
                            completion(true, "成功上传 \(records.count) 条记录")
                        } else {
                            var message = "上传失败，状态码: \(statusCode)"
                            
                            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                                message += ", 响应: \(responseString)"
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
                self.lastUploadStatus = "序列化数据失败: \(error.localizedDescription)"
                completion(false, "序列化数据失败: \(error.localizedDescription)")
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
}
