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
        let records = fetchLocationRecords(limit: 20) // Upload 20 records at a time
        
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
    
    // In JHDataExchangeManager.swift


    /// 上传 Time Outdoors 数据，但将其伪装成 Blood Glucose Observation
    /// (Uploads Time Outdoors data, but disguises it as Blood Glucose Observation)
    /// - Parameters:
    ///   - payloads: 包含 "end_date_time" 和 "duration" 的 JSON 对象数组 (Array of JSON objects containing "end_date_time" and "duration")
    ///   - authManager: 用于认证的 AuthManager 实例 (AuthManager instance for authentication)
    ///   - completion: 完成回调 (Completion handler)
    func uploadTimeOutdoorsDisguisedAsBloodGlucose(
        payloads: [[String: Any]],
        authManager: AuthManager,
        completion: @escaping (Bool, String) -> Void
    ) {
        // 1. --- 认证检查 (Authentication Check) ---
        guard authManager.isAuthenticated, let accessToken = authManager.currentAccessToken() else {
            completion(false, "Not authorized")
            return
        }

        if payloads.isEmpty {
            completion(true, "No Time Outdoors payloads to upload.")
            return
        }

        // 2. --- 准备 FHIR Bundle Entries ---
        var entries: [[String: Any]] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = TimeZone(secondsFromGMT: 0) // Ensure UTC

        // --- 使用 Blood Glucose 的 Code ---
        let bloodGlucoseCode: [String: Any] = [
            "system": "https://w3id.org/openmhealth",
            "code": "omh:blood-glucose:4.0" // Hardcode Blood Glucose code
        ]
        // --- ---

        for payload in payloads {
            // 确保 payload 包含所需键
            guard let endDateTimeString = payload["end_date_time"] as? String,
                  let effectiveDate = isoFormatter.date(from: endDateTimeString) else {
                print("Warning: Could not parse end_date_time from payload, skipping entry.")
                continue
            }

            do {
                // Base64 编码原始的 duration payload
                let jsonData = try JSONSerialization.data(withJSONObject: payload) // Encode the original payload
                let base64String = jsonData.base64EncodedString()

                // 创建 FHIR Observation Entry，使用 Blood Glucose Code
                let entry: [String: Any] = [
                    "resource": [
                        "resourceType": "Observation",
                        "status": "final",
                        "subject": [ "reference": "Patient/\(stellaPatientId)" ], // Use class property
                        "device": [ "reference": "Device/\(deviceId)" ],         // Use class property
                        "code": [ "coding": [ bloodGlucoseCode ] ],               // *** 使用血糖 Code ***
                        "effectiveDateTime": isoFormatter.string(from: effectiveDate), // 使用 payload 的时间
                        "valueAttachment": [                                         // *** 将原始 payload 放入 ***
                            "contentType": "application/json",
                            "data": base64String                                     // *** Base64 编码后的 duration payload ***
                        ],
                        "identifier": [ // Unique identifier for the Observation
                            [
                                "value": UUID().uuidString,
                                "system": "urn:ietf:rfc:3986" // Example system
                            ]
                        ]
                        // 注意：这里没有添加 category，因为血糖通常不需要
                    ],
                    "request": [
                        "method": "POST",
                        "url": "Observation" // Target the Observation endpoint
                    ]
                ]
                entries.append(entry)

            } catch {
                print("Error serializing payload: \(error). Skipping entry.")
                continue
            }
        } // End loop through payloads

        if entries.isEmpty {
            completion(false, "Failed to prepare any valid entries for upload.")
            return
        }

        // 3. --- 创建 FHIR Bundle ---
        let bundle: [String: Any] = [
            "resourceType": "Bundle",
            "type": "batch", // Use "batch" for multiple independent entries
            "entry": entries
        ]

        // 4. --- 准备并发送网络请求 (复用之前的逻辑) ---
        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        guard let fhirURL = URL(string: "\(baseURLString)/fhir/r5/") else { // Ensure correct endpoint
             completion(false, "Invalid FHIR endpoint URL")
             return
        }

        var request = URLRequest(url: fhirURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: bundle)
            request.httpBody = jsonData

            // --- 发送请求 (URLSession Task) ---
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                // --- 处理响应 (Handle Response) ---
                if let error = error {
                    completion(false, "Network error: \(error.localizedDescription)")
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    completion(false, "Invalid response from server.")
                    return
                }

                let success = (200...299).contains(httpResponse.statusCode)
                var message = "Upload status: \(httpResponse.statusCode)"
                if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                     message += "\nResponse Body:\n\(responseBody)"
                     // Optionally parse the response bundle for individual entry statuses here if needed
                }

                completion(success, message) // Call completion with result
            }
            task.resume() // Start the network request

        } catch {
             completion(false, "Failed to serialize bundle: \(error.localizedDescription)")
        }
    } // End of function uploadTimeOutdoorsDisguisedAsBloodGlucose

    
    
    /// 上传 Time Outdoors 数据，使用官方 Time Interval OMH Code
    /// (Uploads Time Outdoors data using the official Time Interval OMH Code)
    /// Note: Function name kept as requested, but now uses omh:time-interval:1.0 code.
    /// - Parameters:
    ///   - payloads: 包含 "end_date_time" 和 "duration" 的 JSON 对象数组
    ///   - authManager: 用于认证的 AuthManager 实例
    ///   - completion: 完成回调
    

//    func uploadTimeOutdoorsDisguisedAsBloodGlucose( // <-- Function name NOT changed as requested
//        payloads: [[String: Any]],
//        authManager: AuthManager,
//        completion: @escaping (Bool, String) -> Void
//    ) {
//        // 1. --- 认证检查 (Authentication Check) ---
//        guard authManager.isAuthenticated, let accessToken = authManager.currentAccessToken() else {
//            completion(false, "Not authorized")
//            return
//        }
//
//        if payloads.isEmpty {
//            completion(true, "No Time Outdoors payloads to upload.")
//            return
//        }
//
//        // 2. --- 准备 FHIR Bundle Entries ---
//        var entries: [[String: Any]] = []
//        let isoFormatter = ISO8601DateFormatter()
//        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
//        isoFormatter.timeZone = TimeZone(secondsFromGMT: 0) // Ensure UTC
//
//        // --- *** 使用 Time Interval 的 OMH Code *** ---
//        let timeIntervalCode: [String: Any] = [
//            "system": "https://w3id.org/openmhealth",
//            "code": "omh:time-interval:1.0" // *** Use the official Time Interval code ***
//        ]
//        // --- *** ---
//
//        for payload in payloads {
//            // 确保 payload 包含所需键
//            guard let endDateTimeString = payload["end_date_time"] as? String,
//                  let effectiveDate = isoFormatter.date(from: endDateTimeString) else {
//                print("Warning: Could not parse end_date_time from payload, skipping entry.")
//                continue
//            }
//
//            do {
//                // Base64 编码原始的 duration payload
//                let jsonData = try JSONSerialization.data(withJSONObject: payload)
//                let base64String = jsonData.base64EncodedString() // Single Base64 encoding
//
//                // 创建 FHIR Observation Entry，使用 Time Interval Code
//                let entry: [String: Any] = [
//                    "resource": [
//                        "resourceType": "Observation",
//                        "status": "final",
//                        "subject": [ "reference": "Patient/\(stellaPatientId)" ], // Use class property
//                        "device": [ "reference": "Device/\(deviceId)" ],         // Use class property
//                        "code": [ "coding": [ timeIntervalCode ] ],               // *** 使用 Time Interval Code ***
//                        "effectiveDateTime": isoFormatter.string(from: effectiveDate), // Use payload's time
//                        "valueAttachment": [                                         // Contains original duration payload
//                            "contentType": "application/json",
//                            "data": base64String
//                        ],
//                        "identifier": [ // Unique identifier for the Observation
//                            [
//                                "value": UUID().uuidString,
//                                "system": "urn:ietf:rfc:3986" // Example system
//                            ]
//                        ]
//                        // No category needed for time-interval generally
//                    ],
//                    "request": [
//                        "method": "POST",
//                        "url": "Observation" // Target the Observation endpoint
//                    ]
//                ]
//                entries.append(entry)
//
//            } catch {
//                print("Error serializing payload: \(error). Skipping entry.")
//                continue
//            }
//        } // End loop through payloads
//
//        if entries.isEmpty {
//            completion(false, "Failed to prepare any valid entries for upload.")
//            return
//        }
//
//        // 3. --- 创建 FHIR Bundle ---
//        let bundle: [String: Any] = [
//            "resourceType": "Bundle",
//            "type": "batch", // Use "batch" for multiple independent entries
//            "entry": entries
//        ]
//
//        // 4. --- 准备并发送网络请求 (Reuse previous logic) ---
//        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
//        guard let fhirURL = URL(string: "\(baseURLString)/fhir/r5/") else { // Ensure correct endpoint
//             completion(false, "Invalid FHIR endpoint URL")
//             return
//        }
//
//        var request = URLRequest(url: fhirURL)
//        request.httpMethod = "POST"
//        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
//        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
//
//        do {
//            let jsonData = try JSONSerialization.data(withJSONObject: bundle)
//            request.httpBody = jsonData
//
//            // --- 发送请求 (URLSession Task) ---
//            let task = URLSession.shared.dataTask(with: request) { data, response, error in
//                // --- 处理响应 (Handle Response) ---
//                if let error = error {
//                    completion(false, "Network error: \(error.localizedDescription)")
//                    return
//                }
//                guard let httpResponse = response as? HTTPURLResponse else {
//                    completion(false, "Invalid response from server.")
//                    return
//                }
//
//                let success = (200...299).contains(httpResponse.statusCode)
//                var message = "Upload status: \(httpResponse.statusCode)"
//                if let data = data, let responseBody = String(data: data, encoding: .utf8) {
//                     message += "\nResponse Body:\n\(responseBody)"
//                     // TODO: Optionally parse the response bundle for individual entry statuses
//                     // if the overall status is 200 but contains errors inside.
//                }
//
//                completion(success, message) // Call completion with result
//            }
//            task.resume() // Start the network request
//
//        } catch {
//             completion(false, "Failed to serialize bundle: \(error.localizedDescription)")
//        }
//    } // End of function

    // 新方法：上传通用的 Observation 数据
    func uploadGenericObservations(payloads: [[String: Any]],
                                   observationCode: [String: String], // 例如: ["system": "...", "code": "...", "display": "..."]
                                   authManager: AuthManager,
                                   completion: @escaping (Bool, String) -> Void) {

        guard authManager.isAuthenticated, let accessToken = authManager.currentAccessToken() else {
            completion(false, "Not authorized")
            return
        }

        if payloads.isEmpty {
            completion(true, "No payloads to upload.")
            return
        }

        var entries: [[String: Any]] = []
        let isoFormatter = ISO8601DateFormatter() // For effectiveDateTime
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]


        for payload in payloads {
            // 从 payload 中提取 end_date_time 作为 effectiveDateTime
            guard let endDateTimeString = payload["end_date_time"] as? String,
                  let effectiveDate = isoFormatter.date(from: endDateTimeString) else {
                print("Warning: Could not parse end_date_time from payload, skipping entry.")
                continue // 跳过这个 payload
            }

            do {
                let jsonData = try JSONSerialization.data(withJSONObject: payload)
                let base64String = jsonData.base64EncodedString()


                let entry: [String: Any] = [
                    "resource": [
                        "resourceType": "Observation",
                        "status": "final",
                        "subject": [ "reference": "Patient/\(stellaPatientId)" ], // 使用类内部定义的 patientId
                        "device": [ "reference": "Device/\(deviceId)" ],         // 使用类内部定义的 deviceId
                        "code": [ "coding": [ observationCode ] ],               // 使用传入的 code
                        "effectiveDateTime": isoFormatter.string(from: effectiveDate), // 使用 payload 的时间
                        "valueAttachment": [
                            "contentType": "application/json",
                            "data": base64String
                        ],
                         "identifier": [ // 可选，但建议有唯一标识符
                             [
                                 "value": UUID().uuidString,
                                 "system": "urn:ietf:rfc:3986" // 或其他合适的 system
                             ]
                         ]
                    ],
                    "request": [
                        "method": "POST",
                        "url": "Observation"
                    ]
                ]
                entries.append(entry)

            } catch {
                print("Error serializing payload: \(error). Skipping entry.")
                continue
            }
        }

         if entries.isEmpty {
             completion(false, "Failed to prepare any valid entries for upload.")
             return
         }

        // 创建 Bundle
        let bundle: [String: Any] = [
            "resourceType": "Bundle",
            "type": "batch",
            "entry": entries
        ]

        // --- 复用或调整现有的上传网络请求逻辑 ---
         // 使用与 uploadLocationData 相同的 endpoint 和认证头
         let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
         guard let fhirURL = URL(string: "\(baseURLString)/fhir/r5/") else { // 确保是正确的 FHIR endpoint
              DispatchQueue.main.async {
                   completion(false, "Invalid FHIR endpoint URL")
              }
              return
         }

         var request = URLRequest(url: fhirURL)
         request.httpMethod = "POST"
         request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
         request.setValue("application/json", forHTTPHeaderField: "Content-Type")

         do {
             let jsonData = try JSONSerialization.data(withJSONObject: bundle)
             request.httpBody = jsonData
             // ... (发送请求，处理响应，调用 completion 的逻辑，类似 uploadLocationData) ...
             // ... 在请求成功的回调中，调用 completion(true, "...") ...
             // ... 在请求失败的回调中，调用 completion(false, "...") ...

              // 示例 URLSession Task (需要完整实现错误处理和状态码检查)
              let task = URLSession.shared.dataTask(with: request) { data, response, error in
                   // ... 处理响应 ...
                   if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                        completion(true, "Successfully uploaded \(entries.count) generic observations.")
                   } else {
                        // 解析错误信息
                        var errorMsg = "Upload failed."
                        if let error = error { errorMsg += " Error: \(error.localizedDescription)" }
                        if let resp = response as? HTTPURLResponse { errorMsg += " Status: \(resp.statusCode)." }
                        if let data = data, let responseBody = String(data: data, encoding: .utf8) { errorMsg += " Body: \(responseBody)" }
                        completion(false, errorMsg)
                   }
              }
              task.resume()

         } catch {
              completion(false, "Failed to serialize bundle: \(error.localizedDescription)")
         }
    }

    // ... 其他 JHDataExchangeManager 代码 ...
}
