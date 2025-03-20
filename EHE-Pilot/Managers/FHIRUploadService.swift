//
//  FHIRUploadService.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/3/13.
//

import Foundation
import CoreData
import SwiftUI

class FHIRUploadService: ObservableObject {
    // 单例实例
    static let shared = FHIRUploadService()
    
    // 发布属性用于UI更新
    @Published var isUploading = false
    @Published var lastUploadStatus: String = "Not uploaded"
    @Published var lastUploadTime: Date?
    @Published var lastUploadResult: (success: Bool, message: String)?
    
    // 私有初始化
    private init() {}
    
    // MARK: - 位置记录上传方法
    
    /// 上传位置记录使用geoposition类型
    func uploadLocationRecords(authManager: AuthManager, limit: Int = 5, completion: @escaping (Bool, String) -> Void) {
        // 确保已认证
        guard authManager.isAuthenticated,
              let accessToken = authManager.currentAccessToken() else {
            DispatchQueue.main.async {
                self.lastUploadStatus = "Not authorized, please login first"
                self.lastUploadResult = (false, "Not authorized, please login first")
                completion(false, "Not authorized, please login first")
            }
            return
        }
        
        // 从配置文件获取patientId，默认为40010
        let patientId = authManager.getPatientIdFromProfile()
        let deviceId = "70001" // 固定设备ID
        
        // 获取要上传的位置记录
        let records = fetchLocationRecords(limit: limit)
        
        if records.isEmpty {
            DispatchQueue.main.async {
                self.lastUploadStatus = "No new location records to upload"
                self.lastUploadResult = (false, "No new location records to upload")
                completion(false, "No new location records to upload")
            }
            return
        }
        
        // 创建FHIR Bundle，使用Geoposition类型
        let bundle = createGeopositionFHIRBundle(from: records, patientId: patientId, deviceId: deviceId)
        
        // 准备API请求
        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        guard let fhirURL = URL(string: "\(baseURLString)/fhir/r5/") else {
            DispatchQueue.main.async {
                self.lastUploadStatus = "Invalid FHIR endpoint URL"
                self.lastUploadResult = (false, "Invalid FHIR endpoint URL")
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
            
            // 打印请求数据用于调试
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("Uploading FHIR Bundle:")
                print(jsonString)
            }
            
            DispatchQueue.main.async {
                self.isUploading = true
                self.lastUploadStatus = "Uploading..."
            }
            
            // 发送请求
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.lastUploadTime = Date()
                    
                    if let error = error {
                        let message = "Upload failed: \(error.localizedDescription)"
                        self.lastUploadStatus = message
                        self.lastUploadResult = (false, message)
                        completion(false, message)
                        return
                    }
                    
                    if let httpResponse = response as? HTTPURLResponse {
                        let statusCode = httpResponse.statusCode
                        
                        // 检查响应体中的批处理响应状态
                        var individualSuccess = true
                        var individualMessage = ""
                        
                        if let data = data {
                            // 尝试解析批处理响应以检查单个条目状态
                            individualSuccess = self.checkBatchResponseSuccess(data, statusMessage: &individualMessage)
                        }
                        
                        if (200...299).contains(statusCode) && individualSuccess {
                            // 成功上传，标记记录为已上传
                            self.markRecordsAsUploaded(records)
                            let message = "Successfully uploaded \(records.count) records"
                            self.lastUploadStatus = message
                            self.lastUploadResult = (true, message)
                            completion(true, message)
                        } else {
                            var message = "Upload failed, status code: \(statusCode)"
                            if !individualMessage.isEmpty {
                                message += ", \(individualMessage)"
                            }
                            
                            if let data = data, let responseString = String(data: data, encoding: .utf8) {
                                print("Server response: \(responseString)")
                                // 不在UI消息中包含完整响应
                            }
                            
                            self.lastUploadStatus = message
                            self.lastUploadResult = (false, message)
                            completion(false, message)
                        }
                    }
                }
            }
            
            task.resume()
            
        } catch {
            DispatchQueue.main.async {
                self.isUploading = false
                let message = "Failed to serialize data: \(error.localizedDescription)"
                self.lastUploadStatus = message
                self.lastUploadResult = (false, message)
                completion(false, message)
            }
        }
    }
    
    // MARK: - 数据准备
    
    /// 获取尚未上传的位置记录
    private func fetchLocationRecords(limit: Int = 10) -> [LocationRecord] {
        let context = PersistenceController.shared.container.viewContext
        let request: NSFetchRequest<LocationRecord> = LocationRecord.fetchRequest()
        
        // 仅获取尚未上传的记录
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
    
    /// 创建一个使用geoposition类型的FHIR Bundle，保留复杂数据结构
    private func createGeopositionFHIRBundle(from records: [LocationRecord], patientId: String, deviceId: String) -> [String: Any] {
        var entries: [[String: Any]] = []
        
        for record in records {
            // 创建位置数据 - 保留复杂数据结构
            let locationData = createGeopositionData(from: record)
            
            // Base64编码数据
            if let jsonData = try? JSONSerialization.data(withJSONObject: locationData) {
                let base64String = jsonData.base64EncodedString()
                
                // 格式化日期时间字符串用于effectiveDateTime
                let iso8601Formatter = ISO8601DateFormatter()
                iso8601Formatter.formatOptions = [.withInternetDateTime]
                let effectiveDateTime = iso8601Formatter.string(from: record.timestamp ?? Date())
                
                // 创建Entry对象
                let entry: [String: Any] = [
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
                            "reference": "Patient/\(patientId)"
                        ],
                        "device": [
                            "reference": "Device/\(deviceId)"
                        ],
                        "effectiveDateTime": effectiveDateTime,
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
    
    /// 创建位置数据 - 保留复杂数据结构
    private func createGeopositionData(from record: LocationRecord) -> [String: Any] {
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
    
    // MARK: - 辅助方法
    
    /// 标记记录为已上传
    private func markRecordsAsUploaded(_ records: [LocationRecord]) {
        let context = PersistenceController.shared.container.viewContext
        
        for record in records {
            record.ifUpdated = true
        }
        
        do {
            try context.save()
            print("Successfully marked \(records.count) records as uploaded")
        } catch {
            print("Error saving context after marking records as uploaded: \(error)")
        }
    }
    
    /// 检查批处理响应中的单个条目是否成功
    private func checkBatchResponseSuccess(_ responseData: Data, statusMessage: inout String) -> Bool {
        do {
            if let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               json["resourceType"] as? String == "Bundle",
               json["type"] as? String == "batch-response",
               let entries = json["entry"] as? [[String: Any]] {
                
                for entry in entries {
                    if let response = entry["response"] as? [String: Any],
                       let status = response["status"] as? String {
                        
                        if !status.hasPrefix("2") {
                            // 不是成功状态
                            if let outcome = response["outcome"] as? [String: Any],
                               let issue = (outcome["issue"] as? [[String: Any]])?.first,
                               let details = issue["details"] as? [String: Any],
                               let text = details["text"] as? String {
                                statusMessage = text
                                return false
                            } else {
                                statusMessage = "Entry status: \(status)"
                                return false
                            }
                        }
                    }
                }
                
                return true
            }
        } catch {
            print("Error parsing batch response: \(error)")
            statusMessage = "Failed to parse response"
            return false
        }
        
        return true
    }
}
