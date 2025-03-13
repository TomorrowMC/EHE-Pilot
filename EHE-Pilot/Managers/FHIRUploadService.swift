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
    // Singleton instance
    static let shared = FHIRUploadService()
    
    // Published properties for UI updates
    @Published var isUploading = false
    @Published var lastUploadStatus: String = "Not uploaded"
    @Published var lastUploadTime: Date?
    @Published var lastUploadResult: (success: Bool, message: String)?
    
    // Private initialization
    private init() {}
    
    // MARK: - LocationRecord Upload Methods
    
    /// Uploads location records using the blood-glucose type (as per requirements)
    func uploadLocationRecords(authManager: AuthManager, limit: Int = 5, completion: @escaping (Bool, String) -> Void) {
        // Ensure authenticated
        guard authManager.isAuthenticated,
              let accessToken = authManager.currentAccessToken() else {
            DispatchQueue.main.async {
                self.lastUploadStatus = "Not authorized, please login first"
                self.lastUploadResult = (false, "Not authorized, please login first")
                completion(false, "Not authorized, please login first")
            }
            return
        }
        
        // Get patient ID from profile, default to 40010
        let patientId = authManager.getPatientIdFromProfile()
        let deviceId = "70001" // Fixed device ID
        
        // Get location records to upload
        let records = fetchLocationRecords(limit: limit)
        
        if records.isEmpty {
            DispatchQueue.main.async {
                self.lastUploadStatus = "No new location records to upload"
                self.lastUploadResult = (false, "No new location records to upload")
                completion(false, "No new location records to upload")
            }
            return
        }
        
        // Create FHIR Bundle for blood-glucose type
        let bundle = createBloodGlucoseFHIRBundle(from: records, patientId: patientId, deviceId: deviceId)
        
        // Prepare API request
        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        guard let fhirURL = URL(string: "\(baseURLString)/fhir/r5/") else {
            DispatchQueue.main.async {
                self.lastUploadStatus = "Invalid FHIR endpoint URL"
                self.lastUploadResult = (false, "Invalid FHIR endpoint URL")
                completion(false, "Invalid FHIR endpoint URL")
            }
            return
        }
        
        // Create request
        var request = URLRequest(url: fhirURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Serialize request body
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: bundle, options: [])
            request.httpBody = jsonData
            
            // Print request data for debugging
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("Uploading FHIR Bundle:")
                print(jsonString)
            }
            
            DispatchQueue.main.async {
                self.isUploading = true
                self.lastUploadStatus = "Uploading..."
            }
            
            // Send request
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
                        
                        // Check the response body for batch response status
                        var individualSuccess = true
                        var individualMessage = ""
                        
                        if let data = data {
                            // Try to parse the batch response to check individual entry statuses
                            individualSuccess = self.checkBatchResponseSuccess(data, statusMessage: &individualMessage)
                        }
                        
                        if (200...299).contains(statusCode) && individualSuccess {
                            // Successfully uploaded, mark records as uploaded
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
                                // Don't include the full response in the UI message
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
    
    // MARK: - Data Preparation
    
    /// Fetch location records that haven't been uploaded yet
    private func fetchLocationRecords(limit: Int = 10) -> [LocationRecord] {
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
    
    // 修复的 createBloodGlucoseFHIRBundle 方法

    private func createBloodGlucoseFHIRBundle(from records: [LocationRecord], patientId: String, deviceId: String) -> [String: Any] {
        var entries: [[String: Any]] = []
        
        for record in records {
            // Create location data disguised as blood glucose data
            let locationData = createLocationDataAsBloodGlucose(from: record)
            
            // Base64 encode the data - 修复的部分
            if let jsonData = try? JSONSerialization.data(withJSONObject: locationData) {
                let base64String = jsonData.base64EncodedString()
                
                // Create Entry object
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
        
        // Create Bundle
        return [
            "resourceType": "Bundle",
            "type": "batch",
            "entry": entries
        ]
    }
    /// Create location data in a format accepted by the server
    private func createLocationDataAsBloodGlucose(from record: LocationRecord) -> [String: Any] {
        var data: [String: Any] = [:]
        
        // Location information in full format
        data["latitude"] = [
            "value": record.latitude,
            "unit": "deg"
        ]
        
        data["longitude"] = [
            "value": record.longitude,
            "unit": "deg"
        ]
        
        // Add a fake blood glucose value to match the type
        // This is necessary since we're using blood-glucose type but storing location data
        data["blood_glucose"] = [
            "value": Int.random(in: 80...150),  // Random value in normal range
            "unit": "mg/dL"
        ]
        
        // Add positioning system
        data["positioning_system"] = "GPS"
        
        // Add satellite signal strength if available
        if let accuracy = record.gpsAccuracy?.doubleValue {
            data["satellite_signal_strengths"] = [
                [
                    "value": Int(accuracy),
                    "unit": "dB"
                ]
            ]
        }
        
        // Add timestamp
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
    
    // MARK: - Helper Methods
    
    /// Mark records as uploaded
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
    
    /// Check batch response for individual entry success
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
                            // Not a success status
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
