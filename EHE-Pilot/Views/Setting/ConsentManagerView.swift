//
//  ConsentManagerView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/3/13.
//


import SwiftUI

struct ConsentManagerView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.presentationMode) var presentationMode
    
    var patientId: String
    private let studyId = "30001"  // Fixed study ID as per requirements
    
    // Consent data
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var consentedScopes: [ScopeItem] = []
    @State private var pendingScopes: [ScopeItem] = []
    @State private var patientInfo: [String: Any]?
    
    // Progress tracking
    @State private var isProcessingConsent = false
    @State private var processingScope: String?
    
    var body: some View {
        NavigationView {
            ZStack {
                // Main content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Patient info section
                        patientInfoSection
                        
                        // Consented scopes section
                        consentedScopesSection
                        
                        // Pending scopes section
                        pendingScopesSection
                        
                        // Error message
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                }
                
                // Loading overlay
                if isLoading {
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.all)
                    
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading consent data...")
                            .foregroundColor(.white)
                            .shadow(radius: 1)
                    }
                    .padding()
                    .background(Color(.systemGray3))
                    .cornerRadius(10)
                }
            }
            .navigationTitle("Data Sharing Consents")
            .navigationBarItems(trailing: Button("Close") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                fetchConsentStatus()
            }
        }
    }
    
    private var patientInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Patient & Study Information")
                .font(.headline)
                .padding(.bottom, 4)
            
            HStack {
                Text("Patient ID:")
                    .fontWeight(.medium)
                Spacer()
                Text(patientId)
            }
            
            HStack {
                Text("Study ID:")
                    .fontWeight(.medium)
                Spacer()
                Text(studyId)
            }
            
            if let patientInfo = patientInfo {
                if let name = extractPatientName() {
                    HStack {
                        Text("Name:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(name)
                    }
                }
                
                // Add more patient info as needed
            }
            
            Button(action: {
                fetchConsentStatus()
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Consent Status")
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private var consentedScopesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Consents")
                .font(.headline)
                .padding(.bottom, 4)
            
            if consentedScopes.isEmpty {
                Text("No active data sharing consents found.")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            } else {
                ForEach(consentedScopes) { scope in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading) {
                            Text(scope.displayName)
                                .fontWeight(.medium)
                            Text(scope.code)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            revokeConsent(for: scope)
                        }) {
                            if isProcessingConsent && processingScope == scope.code {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.red)
                            }
                        }
                        .disabled(isProcessingConsent)
                    }
                    .padding()
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private var pendingScopesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pending Consents")
                .font(.headline)
                .padding(.bottom, 4)
            
            if pendingScopes.isEmpty {
                Text("No pending data sharing requests.")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            } else {
                ForEach(pendingScopes) { scope in
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading) {
                            Text(scope.displayName)
                                .fontWeight(.medium)
                            Text(scope.code)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            grantConsent(for: scope)
                        }) {
                            if isProcessingConsent && processingScope == scope.code {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Text("Consent")
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .cornerRadius(6)
                            }
                        }
                        .disabled(isProcessingConsent)
                    }
                    .padding()
                    .background(Color(.systemGray5))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    // MARK: - API Methods
    
    private func fetchConsentStatus() {
        guard authManager.isAuthenticated,
              let accessToken = authManager.currentAccessToken() else {
            self.errorMessage = "Not authenticated"
            return
        }
        
        isLoading = true
        
        // Construct the URL
        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        let endpointPath = "/api/v1/patients/\(patientId)/consents"
        
        guard let url = URL(string: baseURLString + endpointPath) else {
            isLoading = false
            errorMessage = "Invalid URL for consent data"
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = "Invalid response"
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    self.errorMessage = "Server error: \(httpResponse.statusCode)"
                    if let data = data, let errorText = String(data: data, encoding: .utf8) {
                        print("Error response: \(errorText)")
                    }
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No data received"
                    return
                }
                
                self.parseConsentResponse(data)
            }
        }.resume()
    }
    
    private func parseConsentResponse(_ data: Data) {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Print the response for debugging
                if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    print("Consent Response:")
                    print(jsonStr)
                }
                
                // Extract patient info
                self.patientInfo = json["patient"] as? [String: Any]
                
                // Extract consented scopes
                var consented: [ScopeItem] = []
                if let consolidatedScopes = json["consolidatedConsentedScopes"] as? [[String: Any]] {
                    for scope in consolidatedScopes {
                        if let code = scope["codingCode"] as? String,
                           let system = scope["codingSystem"] as? String,
                           let text = scope["text"] as? String {
                            let scopeItem = ScopeItem(
                                id: scope["id"] as? Int ?? 0,
                                code: code,
                                system: system,
                                displayName: text
                            )
                            consented.append(scopeItem)
                        }
                    }
                }
                self.consentedScopes = consented
                
                // Extract pending scopes
                var pending: [ScopeItem] = []
                if let pendingStudies = json["studiesPendingConsent"] as? [[String: Any]] {
                    for study in pendingStudies {
                        if let studyIdNum = study["id"] as? Int,
                           String(studyIdNum) == self.studyId,
                           let pendingScopeConsents = study["pendingScopeConsents"] as? [[String: Any]] {
                            
                            for pendingScope in pendingScopeConsents {
                                if let codeInfo = pendingScope["code"] as? [String: Any],
                                   let code = codeInfo["codingCode"] as? String,
                                   let system = codeInfo["codingSystem"] as? String,
                                   let text = codeInfo["text"] as? String {
                                    let scopeItem = ScopeItem(
                                        id: codeInfo["id"] as? Int ?? 0,
                                        code: code,
                                        system: system,
                                        displayName: text
                                    )
                                    pending.append(scopeItem)
                                }
                            }
                        }
                    }
                }
                self.pendingScopes = pending
                
                // Clear any error message on success
                self.errorMessage = nil
            } else {
                self.errorMessage = "Invalid response format"
            }
        } catch {
            self.errorMessage = "JSON parsing error: \(error.localizedDescription)"
        }
    }
    
    private func grantConsent(for scope: ScopeItem) {
        isProcessingConsent = true
        processingScope = scope.code
        
        guard authManager.isAuthenticated,
              let accessToken = authManager.currentAccessToken() else {
            self.errorMessage = "Not authenticated"
            isProcessingConsent = false
            processingScope = nil
            return
        }
        
        // Construct the URL
        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        let endpointPath = "/api/v1/patients/\(patientId)/consents"
        
        guard let url = URL(string: baseURLString + endpointPath) else {
            errorMessage = "Invalid URL for consent"
            isProcessingConsent = false
            processingScope = nil
            return
        }
        
        // Create the request body
        let requestBody: [String: Any] = [
            "studyScopeConsents": [
                [
                    "studyId": Int(studyId) ?? 30001,
                    "scopeConsents": [
                        [
                            "codingSystem": scope.system,
                            "codingCode": scope.code,
                            "consented": true
                        ]
                    ]
                ]
            ]
        ]
        
        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Serialize and set the request body
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            // Print the request for debugging
            if let requestString = String(data: jsonData, encoding: .utf8) {
                print("Consent Request: \(requestString)")
            }
        } catch {
            self.errorMessage = "Failed to serialize request: \(error.localizedDescription)"
            isProcessingConsent = false
            processingScope = nil
            return
        }
        
        // Make the request
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isProcessingConsent = false
                self.processingScope = nil
                
                if let error = error {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = "Invalid response"
                    return
                }
                
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    // Success - refresh the consents
                    self.fetchConsentStatus()
                } else {
                    self.errorMessage = "Failed to update consent: Status \(httpResponse.statusCode)"
                    
                    // Print error response for debugging
                    if let data = data, let errorText = String(data: data, encoding: .utf8) {
                        print("Error response: \(errorText)")
                    }
                }
            }
        }.resume()
    }
    
    private func revokeConsent(for scope: ScopeItem) {
        isProcessingConsent = true
        processingScope = scope.code
        
        guard authManager.isAuthenticated,
              let accessToken = authManager.currentAccessToken() else {
            self.errorMessage = "Not authenticated"
            isProcessingConsent = false
            processingScope = nil
            return
        }
        
        // Construct the URL
        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        let endpointPath = "/api/v1/patients/\(patientId)/consents"
        
        guard let url = URL(string: baseURLString + endpointPath) else {
            errorMessage = "Invalid URL for consent"
            isProcessingConsent = false
            processingScope = nil
            return
        }
        
        // Create the request body for revocation
        let requestBody: [String: Any] = [
            "studyScopeConsents": [
                [
                    "studyId": Int(studyId) ?? 30001,
                    "scopeConsents": [
                        [
                            "codingSystem": scope.system,
                            "codingCode": scope.code,
                            "consented": false
                        ]
                    ]
                ]
            ]
        ]
        
        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"  // Use PATCH to update existing consent
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Serialize and set the request body
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
        } catch {
            self.errorMessage = "Failed to serialize request: \(error.localizedDescription)"
            isProcessingConsent = false
            processingScope = nil
            return
        }
        
        // Make the request
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isProcessingConsent = false
                self.processingScope = nil
                
                if let error = error {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    self.errorMessage = "Invalid response"
                    return
                }
                
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    // Success - refresh the consents
                    self.fetchConsentStatus()
                } else {
                    self.errorMessage = "Failed to revoke consent: Status \(httpResponse.statusCode)"
                    
                    // Print error response for debugging
                    if let data = data, let errorText = String(data: data, encoding: .utf8) {
                        print("Error response: \(errorText)")
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - Helper Methods
    
    private func extractPatientName() -> String? {
        if let patientInfo = self.patientInfo {
            // Try to extract from 'name' array
            if let name = patientInfo["name"] as? [[String: Any]],
               let firstName = name.first {
                let family = firstName["family"] as? String ?? ""
                
                if let given = firstName["given"] as? [String],
                   let first = given.first {
                    return "\(first) \(family)"
                }
                
                return family
            }
        }
        return nil
    }
}

// MARK: - Models

struct ScopeItem: Identifiable {
    let id: Int
    let code: String
    let system: String
    let displayName: String
}

struct ConsentManagerView_Previews: PreviewProvider {
    static var previews: some View {
        ConsentManagerView(patientId: "40010")
            .environmentObject(AuthManager())
    }
}