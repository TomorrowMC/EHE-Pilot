//
//  ConsentDebugTool.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/3/13.
//


import SwiftUI
import Foundation

struct ConsentDebugTool: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.presentationMode) var presentationMode
    
    // Patient and study parameters
    @State private var patientId = "40001"
    @State private var studyId = "30001"
    @State private var isLoading = false
    @State private var debugLogs: [DebugLogEntry] = []
    
    // Available scopes
    @State private var selectedScopeIndex = 0
    private let availableScopes = [
        "omh:blood-glucose:4.0",
        "omh:blood-pressure:4.0",
        "omh:geoposition:1.0",
        "omh:step-count:1.0",
        "omh:heart-rate:1.0",
        "omh:sleep-duration:1.0",
        "omh:time-interval:1.0"
    ]
    
    // Consent status
    @State private var patientInfo: [String: Any]?
    @State private var consentedScopes: [String] = []
    @State private var pendingScopes: [String] = []
    @State private var hasLoadedConsents = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Patient & Study")) {
                    TextField("Patient ID", text: $patientId)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    TextField("Study ID", text: $studyId)
                        .keyboardType(.numberPad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button(action: {
                        fetchPatientConsents()
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .padding(.trailing, 10)
                                Text("Loading...")
                            } else {
                                Text("Check Consent Status")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(!authManager.isAuthenticated || isLoading)
                }
                
                if hasLoadedConsents {
                    Section(header: Text("Patient Information")) {
                        if let info = patientInfo, let name = info["name"] as? [String: Any] {
                            let familyName = (name["family"] as? String) ?? "Unknown"
                            let givenName = (name["given"] as? [String])?.first ?? "Unknown"
                            
                            HStack {
                                Text("Name:")
                                    .bold()
                                Spacer()
                                Text("\(givenName) \(familyName)")
                            }
                            
                            if let email = (info["telecom"] as? [[String: Any]])?.first(where: { ($0["system"] as? String) == "email" })?["value"] as? String {
                                HStack {
                                    Text("Email:")
                                        .bold()
                                    Spacer()
                                    Text(email)
                                }
                            }
                        } else {
                            Text("Failed to load patient details")
                                .foregroundColor(.red)
                        }
                    }
                    
                    Section(header: Text("Consented Scopes")) {
                        if consentedScopes.isEmpty {
                            Text("No consented scopes found")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ForEach(consentedScopes, id: \.self) { scope in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text(scope)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }
                    }
                    
                    Section(header: Text("Pending Scopes")) {
                        if pendingScopes.isEmpty {
                            Text("No pending scopes found")
                                .foregroundColor(.secondary)
                                .italic()
                        } else {
                            ForEach(pendingScopes, id: \.self) { scope in
                                HStack {
                                    Image(systemName: "clock.fill")
                                        .foregroundColor(.orange)
                                    Text(scope)
                                        .font(.system(.body, design: .monospaced))
                                }
                            }
                        }
                    }
                    
                    Section(header: Text("Add Consent")) {
                        Picker("Data Type:", selection: $selectedScopeIndex) {
                            ForEach(0..<availableScopes.count, id: \.self) { index in
                                Text(availableScopes[index])
                                    .tag(index)
                            }
                        }
                        
                        Button(action: {
                            addConsent(for: availableScopes[selectedScopeIndex])
                        }) {
                            Text("Grant Consent")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(isLoading)
                    }
                }
                
                Section(header: Text("Debug Logs")) {
                    if debugLogs.isEmpty {
                        Text("No logs yet. Run a check to see results.")
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
            .navigationTitle("Consent Manager")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - API Methods
    
    private func fetchPatientConsents() {
        guard authManager.isAuthenticated, 
              let accessToken = authManager.currentAccessToken() else {
            addLog(message: "No access token available", type: .error)
            return
        }
        
        isLoading = true
        
        // 1. Build the URL
        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        let endpointPath = "/api/v1/patients/\(patientId)/consents"
        
        guard let url = URL(string: baseURLString + endpointPath) else {
            addLog(message: "Invalid URL: \(baseURLString + endpointPath)", type: .error)
            isLoading = false
            return
        }
        
        // 2. Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // 3. Make the request
        addLog(message: "Fetching consent data for Patient \(patientId)", type: .info)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                self.hasLoadedConsents = true
                
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
                
                guard (200...299).contains(httpResponse.statusCode), let data = data else {
                    if let data = data, let errorString = String(data: data, encoding: .utf8) {
                        self.addLog(message: "API error", type: .error, details: errorString)
                    }
                    return
                }
                
                // Parse the response
                self.parseConsentResponse(data)
            }
        }
        
        task.resume()
    }
    
    private func parseConsentResponse(_ data: Data) {
        do {
            // Parse the JSON response
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Print the complete response for debugging
                if let responseString = String(data: data, encoding: .utf8) {
                    addLog(message: "Consent response received", type: .info, details: responseString)
                }
                
                // Extract patient info
                if let patient = json["patient"] as? [String: Any] {
                    self.patientInfo = patient
                    addLog(message: "Patient information loaded", type: .success)
                }
                
                // Extract consented scopes
                var consented: [String] = []
                if let consolidatedScopes = json["consolidatedConsentedScopes"] as? [[String: Any]] {
                    for scope in consolidatedScopes {
                        if let code = scope["codingCode"] as? String {
                            consented.append(code)
                        }
                    }
                    addLog(message: "Found \(consented.count) consented scopes", type: .success)
                }
                self.consentedScopes = consented
                
                // Extract pending scopes
                var pending: [String] = []
                if let pendingStudies = json["studiesPendingConsent"] as? [[String: Any]] {
                    for study in pendingStudies {
                        if let studyId = study["id"] as? Int, 
                           String(studyId) == self.studyId,
                           let pendingScopeConsents = study["pendingScopeConsents"] as? [[String: Any]] {
                            
                            for pendingScope in pendingScopeConsents {
                                if let codeInfo = pendingScope["code"] as? [String: Any],
                                   let code = codeInfo["codingCode"] as? String {
                                    pending.append(code)
                                }
                            }
                        }
                    }
                    addLog(message: "Found \(pending.count) pending scopes", type: .info)
                }
                self.pendingScopes = pending
                
            } else {
                addLog(message: "Invalid response format", type: .error)
            }
        } catch {
            addLog(message: "Failed to parse response", type: .error, details: error.localizedDescription)
        }
    }
    
    private func addConsent(for scope: String) {
        guard authManager.isAuthenticated, 
              let accessToken = authManager.currentAccessToken() else {
            addLog(message: "No access token available", type: .error)
            return
        }
        
        isLoading = true
        
        // 1. Build the URL
        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        let endpointPath = "/api/v1/patients/\(patientId)/consents"
        
        guard let url = URL(string: baseURLString + endpointPath) else {
            addLog(message: "Invalid URL: \(baseURLString + endpointPath)", type: .error)
            isLoading = false
            return
        }
        
        // 2. Create the request body
        let requestBody: [String: Any] = [
            "studyScopeConsents": [
                [
                    "studyId": Int(studyId) ?? 30001,
                    "scopeConsents": [
                        [
                            "codingSystem": "https://w3id.org/openmhealth",
                            "codingCode": scope,
                            "consented": true
                        ]
                    ]
                ]
            ]
        ]
        
        // 3. Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"  // Use POST to create new consent
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Serialize the request body
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            if let requestString = String(data: jsonData, encoding: .utf8) {
                addLog(message: "Sending consent request", type: .info, details: requestString)
            }
        } catch {
            addLog(message: "Failed to serialize request", type: .error, details: error.localizedDescription)
            isLoading = false
            return
        }
        
        // 4. Make the request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
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
                
                if (200...299).contains(httpResponse.statusCode) {
                    self.addLog(message: "Consent successfully added for \(scope)", type: .success)
                    // Refresh consent data
                    self.fetchPatientConsents()
                } else if let data = data, let errorString = String(data: data, encoding: .utf8) {
                    self.addLog(message: "Failed to add consent", type: .error, details: errorString)
                }
            }
        }
        
        task.resume()
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

struct ConsentDebugTool_Previews: PreviewProvider {
    static var previews: some View {
        ConsentDebugTool()
            .environmentObject(AuthManager())
    }
}
