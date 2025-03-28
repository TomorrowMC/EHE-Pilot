//
//  FHIRTestTool.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/3/13.
//

import SwiftUI
import Foundation

struct FHIRTestTool: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var debugLogs: [DebugLogEntry] = []
    @State private var isUploading = false
    
    // FHIR resource data
    @State private var patientId = "40001"
    @State private var deviceId = "70001"
    @State private var selectedScope = "geoposition"
    @State private var generateTestData = true
    @State private var useFullFormat = true
    
    // Predefined scopes
    private let availableScopes = [
        "geoposition",
        "blood-glucose",
        "blood-pressure",
        "step-count",
        "heart-rate",
        "sleep-duration"
    ]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("FHIR Upload Configuration")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Patient ID:")
                            .foregroundColor(.secondary)
                        TextField("Patient ID", text: $patientId)
                            .keyboardType(.numberPad)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Device ID:")
                            .foregroundColor(.secondary)
                        TextField("Device ID", text: $deviceId)
                            .keyboardType(.numberPad)
                    }
                    
                    Picker("Data Type:", selection: $selectedScope) {
                        ForEach(availableScopes, id: \.self) { scope in
                            Text(scope).tag(scope)
                        }
                    }
                    
                    Toggle("Generate Test Data", isOn: $generateTestData)
                    
                    if generateTestData {
                        Toggle("Use Full Data Format", isOn: $useFullFormat)
                    }
                }
                
                Section {
                    Button(action: performFHIRUpload) {
                        HStack {
                            if isUploading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .padding(.trailing, 5)
                                Text("Uploading...")
                            } else {
                                Text("Upload FHIR Data")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(authManager.isAuthenticated ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(!authManager.isAuthenticated || isUploading)
                }
                
                Section(header: Text("Debug Logs")) {
                    if debugLogs.isEmpty {
                        Text("No logs yet")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(debugLogs) { log in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(log.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Text(log.message)
                                    .font(.caption)
                                    .foregroundColor(colorForLogType(log.type))
                                
                                if !log.details.isEmpty {
                                    Text(log.details)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(5)
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle()) // 确保整个区域可点击
                            .onTapGesture {
                                copyLogToClipboard(log)
                            }
                        }
                        
                        Button("Clear Logs") {
                            debugLogs.removeAll()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("FHIR Data Tester")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - FHIR Upload Methods
    
    private func performFHIRUpload() {
        guard authManager.isAuthenticated,
              let accessToken = authManager.currentAccessToken() else {
            addLog(message: "No access token available", type: .error)
            return
        }
        
        isUploading = true
        
        // 1. Create test data
        let testData = generateTestData ? createTestData() : [String: Any]()
        
        // 2. Prepare the FHIR Bundle
        let bundle = createFHIRBundle(with: testData)
        
        // 3. Upload to FHIR endpoint
        uploadFHIRBundle(bundle, with: accessToken)
    }
    
    private func createTestData() -> [String: Any] {
        var data: [String: Any] = [:]
        
        if selectedScope == "geoposition" {
            // Generate random coordinates for geoposition
            let latitude = Double.random(in: 37.75...40.75)
            let longitude = Double.random(in: -122.45...(-73.95))
            
            if useFullFormat {
                // Full geoposition format (matching FHIRUploadService format)
                data = [
                    "latitude": [
                        "value": latitude,
                        "unit": "deg"
                    ],
                    "longitude": [
                        "value": longitude,
                        "unit": "deg"
                    ],
                    "positioning_system": "GPS",
                    "satellite_signal_strengths": [
                        [
                            "value": Int.random(in: 5...25),
                            "unit": "dB"
                        ]
                    ],
                    "effective_time_frame": [
                        "date_time": ISO8601DateFormatter().string(from: Date())
                    ]
                ]
            } else {
                // Simple format
                data = [
                    "latitude": latitude,
                    "longitude": longitude,
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ]
            }
        } else if selectedScope == "blood-glucose" {
            if useFullFormat {
                data = [
                    "blood_glucose": [
                        "value": Int.random(in: 70...180),
                        "unit": "mg/dL"
                    ],
                    "effective_time_frame": [
                        "date_time": ISO8601DateFormatter().string(from: Date())
                    ]
                ]
            } else {
                data = [
                    "glucose": Int.random(in: 70...180),
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ]
            }
        } else if selectedScope == "blood-pressure" {
            if useFullFormat {
                data = [
                    "systolic_blood_pressure": [
                        "value": Int.random(in: 110...140),
                        "unit": "mmHg"
                    ],
                    "diastolic_blood_pressure": [
                        "value": Int.random(in: 70...90),
                        "unit": "mmHg"
                    ],
                    "effective_time_frame": [
                        "date_time": ISO8601DateFormatter().string(from: Date())
                    ]
                ]
            } else {
                data = [
                    "systolic": Int.random(in: 110...140),
                    "diastolic": Int.random(in: 70...90),
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ]
            }
        } else if selectedScope == "heart-rate" {
            if useFullFormat {
                data = [
                    "heart_rate": [
                        "value": Int.random(in: 60...100),
                        "unit": "bpm"
                    ],
                    "effective_time_frame": [
                        "date_time": ISO8601DateFormatter().string(from: Date())
                    ]
                ]
            } else {
                data = [
                    "rate": Int.random(in: 60...100),
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ]
            }
        } else if selectedScope == "step-count" {
            if useFullFormat {
                data = [
                    "step_count": [
                        "value": Int.random(in: 1000...10000)
                    ],
                    "effective_time_frame": [
                        "date_time": ISO8601DateFormatter().string(from: Date())
                    ]
                ]
            } else {
                data = [
                    "steps": Int.random(in: 1000...10000),
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ]
            }
        } else if selectedScope == "sleep-duration" {
            let hours = Double.random(in: 5...9)
            if useFullFormat {
                data = [
                    "sleep_duration": [
                        "value": hours,
                        "unit": "h"
                    ],
                    "effective_time_frame": [
                        "date_time": ISO8601DateFormatter().string(from: Date())
                    ]
                ]
            } else {
                data = [
                    "duration": hours,
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ]
            }
        }
        
        return data
    }
    
    private func createFHIRBundle(with data: [String: Any]) -> [String: Any] {
        // Convert data to JSON
        var jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: data)
        } catch {
            addLog(message: "Failed to serialize data", type: .error, details: error.localizedDescription)
            return [:]
        }
        
        // Base64 encode the data
        let base64String = jsonData.base64EncodedString()
        
        // Generate UUID for observation
        let uuid = UUID().uuidString
        
        // Map scope to OMH code
        var scope = ""
        var version = "1.0"
        
        // Use correct code formats based on scope
        if selectedScope == "geoposition" {
            scope = "omh:geoposition:1.0"
        } else {
            version = "4.0"
            scope = "omh:\(selectedScope):\(version)"
        }
        
        // Format date time string for effectiveDateTime
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        let effectiveDateTime = iso8601Formatter.string(from: Date())
        
        // Create the FHIR bundle with category for specific types
        var observationResource: [String: Any] = [
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
                        "code": scope
                    ]
                ]
            ],
            "valueAttachment": [
                "contentType": "application/json",
                "data": base64String
            ],
            "identifier": [
                [
                    "value": uuid,
                    "system": "https://ehr.example.com"
                ]
            ],
            "effectiveDateTime": effectiveDateTime
        ]
        
        // Add category for certain types like geoposition
        if selectedScope == "geoposition" {
            observationResource["category"] = [
                [
                    "coding": [
                        [
                            "system": "http://terminology.hl7.org/CodeSystem/observation-category",
                            "code": "survey",
                            "display": "Survey"
                        ]
                    ]
                ]
            ]
        }
        
        let bundle: [String: Any] = [
            "resourceType": "Bundle",
            "type": "batch",
            "entry": [
                [
                    "resource": observationResource,
                    "request": [
                        "method": "POST",
                        "url": "Observation"
                    ]
                ]
            ]
        ]
        
        // Log the bundle
        do {
            let bundleData = try JSONSerialization.data(withJSONObject: bundle, options: .prettyPrinted)
            if let bundleString = String(data: bundleData, encoding: .utf8) {
                addLog(message: "Created FHIR Bundle:", type: .info, details: bundleString)
            }
        } catch {
            addLog(message: "Failed to convert bundle to string", type: .error)
        }
        
        return bundle
    }
    
    private func uploadFHIRBundle(_ bundle: [String: Any], with accessToken: String) {
        // 1. Create the URL
        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        let fhirEndpoint = "/fhir/r5/"
        
        guard let url = URL(string: baseURLString + fhirEndpoint) else {
            isUploading = false
            addLog(message: "Invalid FHIR endpoint URL", type: .error)
            return
        }
        
        // 2. Prepare the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        // 3. Serialize the bundle
        do {
            let bundleData = try JSONSerialization.data(withJSONObject: bundle)
            request.httpBody = bundleData
        } catch {
            isUploading = false
            addLog(message: "Failed to serialize bundle", type: .error, details: error.localizedDescription)
            return
        }
        
        // 4. Make the request
        addLog(message: "Sending FHIR data to endpoint: \(url.absoluteString)", type: .info)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isUploading = false
                
                if let error = error {
                    self.addLog(message: "Network error", type: .error, details: error.localizedDescription)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.addLog(message: "Invalid response", type: .error)
                    return
                }
                
                // 5. Log response
                self.addLog(
                    message: "Response status: \(httpResponse.statusCode)",
                    type: (200...299).contains(httpResponse.statusCode) ? .success : .error
                )
                
                // 6. Check and log response body
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    if (200...299).contains(httpResponse.statusCode) {
                        self.addLog(message: "Upload successful", type: .success, details: responseString)
                    } else {
                        self.addLog(message: "Upload failed", type: .error, details: responseString)
                    }
                    
                    // 7. Check for batch-response statuses in the FHIR Bundle response
                    self.checkBatchResponseStatus(data)
                }
            }
        }
        
        task.resume()
    }
    
    private func checkBatchResponseStatus(_ responseData: Data?) {
        // Parse the FHIR Bundle response to check for individual entry statuses
        guard let data = responseData else { return }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["resourceType"] as? String == "Bundle",
               json["type"] as? String == "batch-response",
               let entries = json["entry"] as? [[String: Any]] {
                
                for (index, entry) in entries.enumerated() {
                    if let response = entry["response"] as? [String: Any],
                       let status = response["status"] as? String {
                        
                        // Check if the entry has an error
                        let isSuccess = status.hasPrefix("2")
                        let logType: LogType = isSuccess ? .success : .error
                        let message = "Entry \(index + 1) status: \(status)"
                        
                        // Log outcome details if present
                        if let outcome = response["outcome"] as? [String: Any],
                           let issueContainer = outcome["issue"] as? [[String: Any]],
                           !issueContainer.isEmpty {
                            
                            for issue in issueContainer {
                                let severity = issue["severity"] as? String ?? "unknown"
                                let code = issue["code"] as? String ?? "unknown"
                                let details = (issue["details"] as? [String: Any])?["text"] as? String ?? "No details"
                                
                                self.addLog(
                                    message: "Issue: \(severity) - \(code)",
                                    type: .error,
                                    details: details
                                )
                            }
                        } else {
                            self.addLog(message: message, type: logType)
                        }
                    }
                }
            }
        } catch {
            addLog(message: "Failed to parse batch response", type: .error, details: error.localizedDescription)
        }
    }
    
    // MARK: - Helper Methods
    
    private func addLog(message: String, type: LogType, details: String = "") {
        let newLog = DebugLogEntry(
            id: UUID(),
            timestamp: Date(),
            message: message,
            type: type,
            details: details
        )
        
        debugLogs.insert(newLog, at: 0)
        
        // Keep only the last 30 logs
        if debugLogs.count > 30 {
            debugLogs.removeLast()
        }
    }
    
    private func copyLogToClipboard(_ log: DebugLogEntry) {
        // 创建要复制的日志文本
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .medium
        
        var logText = "[\(dateFormatter.string(from: log.timestamp))] [\(log.type)] \(log.message)"
        if !log.details.isEmpty {
            logText += "\n\nDetails:\n\(log.details)"
        }
        
        // 复制到剪贴板
        UIPasteboard.general.string = logText
        
        // 添加一个反馈日志，显示复制成功
        addLog(message: "Log Copied", type: .info)
    }
    
    private func colorForLogType(_ type: LogType) -> Color {
        switch type {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

struct FHIRTestTool_Previews: PreviewProvider {
    static var previews: some View {
        FHIRTestTool()
            .environmentObject(AuthManager())
    }
}
