import SwiftUI
import Foundation

struct UploadDebugTool: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.presentationMode) var presentationMode
    @State private var debugLogs: [DebugLogEntry] = []
    @State private var isPerformingTest = false
    @State private var selectedEndpoint = 0
    
    // Test endpoint options
    private let endpointOptions = [
        "FHIR API: /fhir/r5/",
        "User Profile: /api/v1/users/profile",
        "OIDC Config: /.well-known/openid-configuration"
    ]
    
    // Custom request parameters
    @State private var customHeaders: [String: String] = [
        "Authorization": "Bearer {token}" // Will be replaced with actual token
    ]
    @State private var customPatientID = "40001"
    @State private var showAdvancedOptions = false
    
    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Authentication Status")) {
                        HStack {
                            Image(systemName: authManager.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(authManager.isAuthenticated ? .green : .red)
                            Text(authManager.isAuthenticated ? "Authenticated" : "Not authenticated")
                        }
                        
                        if let token = authManager.currentAccessToken() {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Token (first 15 chars):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(token.prefix(15)) + "...")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                    
                    Section(header: Text("Connection Test")) {
                        Picker("Test Endpoint", selection: $selectedEndpoint) {
                            ForEach(0..<endpointOptions.count, id: \.self) { index in
                                Text(endpointOptions[index])
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        
                        DisclosureGroup("Advanced Options", isExpanded: $showAdvancedOptions) {
                            TextField("Patient ID", text: $customPatientID)
                                .keyboardType(.numberPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.vertical, 5)
                            
                            ForEach(customHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                HStack {
                                    Text(key)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(value)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        
                        Button(action: {
                            performConnectionTest()
                        }) {
                            HStack {
                                if isPerformingTest {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .padding(.trailing, 10)
                                }
                                Text("Run Connection Test")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(authManager.isAuthenticated ? Color.blue : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(!authManager.isAuthenticated || isPerformingTest)
                    }
                    
                    Section(header: Text("Debug Logs")) {
                        if debugLogs.isEmpty {
                            Text("No logs yet. Run a test to see results.")
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
                                            .lineLimit(3)
                                            .padding(.leading, 8)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            
                            Button("Clear Logs") {
                                debugLogs.removeAll()
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Upload Debug Tool")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    private func performConnectionTest() {
        guard authManager.isAuthenticated,
              let accessToken = authManager.currentAccessToken() else {
            addLog(message: "No access token available", type: .error)
            return
        }
        
        isPerformingTest = true
        
        // Construct the request URL based on the selected endpoint
        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        var endpointPath = ""
        
        switch selectedEndpoint {
        case 0:
            endpointPath = "/fhir/r5/"
        case 1:
            endpointPath = "/api/v1/users/profile"
        case 2:
            endpointPath = "/o/.well-known/openid-configuration"
        default:
            endpointPath = "/fhir/r5/"
        }
        
        guard let url = URL(string: baseURLString + endpointPath) else {
            addLog(message: "Invalid URL: \(baseURLString + endpointPath)", type: .error)
            isPerformingTest = false
            return
        }
        
        // Create the request
        var request = URLRequest(url: url)
        
        // IMPORTANT: Use POST for FHIR endpoint, GET for others
        if selectedEndpoint == 0 {
            request.httpMethod = "POST"
            // Add empty body for POST request to avoid "empty body" errors
            request.httpBody = "{}".data(using: .utf8)
            addLog(message: "Using POST method for FHIR endpoint", type: .info)
        } else {
            request.httpMethod = "GET"
        }
        
        // Add authorization header
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        addLog(message: "Sending request to \(url.absoluteString)", type: .info)
        
        // Make the request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isPerformingTest = false
                
                if let error = error {
                    self.addLog(message: "Network error", type: .error, details: error.localizedDescription)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.addLog(message: "Invalid response type", type: .error)
                    return
                }
                
                // Log status code
                let statusMessage = "Response status: \(httpResponse.statusCode)"
                let logType: LogType = (200...299).contains(httpResponse.statusCode) ? .success : .error
                self.addLog(message: statusMessage, type: logType)
                
                // Log headers
                var headerDetails = "Response Headers:\n"
                httpResponse.allHeaderFields.forEach { key, value in
                    headerDetails += "• \(key): \(value)\n"
                }
                self.addLog(message: "Response headers received", type: .info, details: headerDetails)
                
                // Log data if available
                if let data = data, let dataString = String(data: data, encoding: .utf8) {
                    let trimmedString = dataString.count > 500 ? String(dataString.prefix(500)) + "..." : dataString
                    self.addLog(message: "Response body received", type: .info, details: trimmedString)
                } else if data != nil {
                    self.addLog(message: "Response body received (binary data)", type: .info)
                } else {
                    self.addLog(message: "No response body", type: .warning)
                }
                
                // Test FHIR upload with a single record if on FHIR endpoint
                if selectedEndpoint == 0 {
                    self.testFHIRUpload(accessToken: accessToken, url: url)
                }
            }
        }
        
        task.resume()
    }
    
    private func testFHIRUpload(accessToken: String, url: URL) {
        addLog(message: "Testing FHIR upload...", type: .info)
        
        // Create a simple location data point
        let locationData: [String: Any] = [
            "latitude": [
                "value": 40.7128,
                "unit": "deg"
            ],
            "longitude": [
                "value": -74.0060,
                "unit": "deg"
            ],
            "positioningSystem": "GPS",
            "effective_time_frame": [
                "date_time": ISO8601DateFormatter().string(from: Date())
            ]
        ]
        
        // Create data for upload
        do {
            let jsonLocationData = try JSONSerialization.data(withJSONObject: locationData)
            let base64String = jsonLocationData.base64EncodedString()
            
            // Create a FHIR bundle
            let bundle: [String: Any] = [
                "resourceType": "Bundle",
                "type": "batch",
                "entry": [
                    [
                        "resource": [
                            "resourceType": "Observation",
                            "status": "final",
                            "subject": [
                                "reference": "Patient/\(customPatientID)"
                            ],
                            "device": [
                                "reference": "Device/70001"
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
                ]
            ]
            
            let bundleData = try JSONSerialization.data(withJSONObject: bundle)
            
            // Log the bundle
            if let bundleString = String(data: bundleData, encoding: .utf8) {
                addLog(message: "Prepared FHIR bundle", type: .info, details: bundleString)
            }
            
            // Create the request
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = bundleData
            
            // Send the test upload
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.addLog(message: "FHIR upload error", type: .error, details: error.localizedDescription)
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        self.addLog(message: "Invalid FHIR response", type: .error)
                        return
                    }
                    
                    // Log response details
                    let statusMessage = "FHIR upload status: \(httpResponse.statusCode)"
                    let logType: LogType = (200...299).contains(httpResponse.statusCode) ? .success : .error
                    self.addLog(message: statusMessage, type: logType)
                    
                    // Log data if available
                    if let data = data, let dataString = String(data: data, encoding: .utf8) {
                        self.addLog(message: "FHIR response body", type: .info, details: dataString)
                    }
                }
            }
            
            task.resume()
            
        } catch {
            addLog(message: "Failed to create FHIR bundle", type: .error, details: error.localizedDescription)
        }
    }
    
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

// Log entry model
struct DebugLogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let message: String
    let type: LogType
    let details: String
}

enum LogType {
    case info
    case success
    case warning
    case error
}

struct UploadDebugTool_Previews: PreviewProvider {
    static var previews: some View {
        UploadDebugTool()
            .environmentObject(AuthManager())
    }
}
