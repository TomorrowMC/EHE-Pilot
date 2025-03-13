//
//  UserProfileView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/3/13.
//


import SwiftUI

struct UserProfileViewInSettings: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var profileData: [String: Any]?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingConsentManager = false
    
    var body: some View {
        VStack(spacing: 20) {
            if authManager.isAuthenticated {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                } else if let profileData = profileData {
                    userInfoSection(profileData: profileData)
                    
                    // Consent Manager button
                    Button(action: {
                        showingConsentManager = true
                    }) {
                        HStack {
                            Image(systemName: "lock.shield.fill")
                                .font(.title3)
                            Text("Manage Data Sharing Consents")
                                .fontWeight(.medium)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    
                    // Log out button
                    Button(action: {
                        authManager.signOut()
                        self.profileData = nil
                    }) {
                        Text("Sign Out")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.red.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)
                } else if let errorMessage = errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                            .padding()
                        
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .padding()
                        
                        Button(action: {
                            fetchUserProfile()
                        }) {
                            Text("Try Again")
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                }
            } else {
                notSignedInView()
            }
        }
        .padding()
        .navigationTitle("Profile")
        .onAppear {
            if authManager.isAuthenticated && profileData == nil {
                fetchUserProfile()
            }
        }
        .sheet(isPresented: $showingConsentManager) {
            // Use the PatientID from the profile data
            let patientId = extractPatientId()
            ConsentManagerView(patientId: patientId)
                .environmentObject(authManager)
        }
    }
    
    private func userInfoSection(profileData: [String: Any]) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            // Patient info
            if let patient = profileData["patient"] as? [String: Any] {
                patientInfoView(patient: patient)
            } else {
                userBasicInfoView(profileData: profileData)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // User info if separate from patient
            if profileData["patient"] != nil {
                userBasicInfoView(profileData: profileData)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
    }
    
    private func patientInfoView(patient: [String: Any]) -> some View {
        VStack(spacing: 10) {
            Text("Patient Information")
                .font(.headline)
                .padding(.bottom, 4)
            
            if let id = patient["id"] as? Int {
                infoRow(title: "Patient ID:", value: "\(id)")
            }
            
            if let familyName = extractFamilyName(from: patient),
               let givenName = extractGivenName(from: patient) {
                infoRow(title: "Name:", value: "\(givenName) \(familyName)")
            }
            
            if let email = extractEmail(from: patient) {
                infoRow(title: "Email:", value: email)
            }
            
            if let phone = extractPhone(from: patient) {
                infoRow(title: "Phone:", value: phone)
            }
            
            if let birthDate = patient["birthDate"] as? String {
                infoRow(title: "Birth Date:", value: birthDate)
            }
        }
    }
    
    private func userBasicInfoView(profileData: [String: Any]) -> some View {
        VStack(spacing: 10) {
            if profileData["patient"] != nil {
                Text("User Information")
                    .font(.headline)
                    .padding(.bottom, 4)
            }
            
            if let id = profileData["id"] as? Int {
                infoRow(title: "User ID:", value: "\(id)")
            }
            
            if let email = profileData["email"] as? String {
                infoRow(title: "Email:", value: email)
            }
            
            if let firstName = profileData["firstName"] as? String,
               let lastName = profileData["lastName"] as? String {
                infoRow(title: "Name:", value: "\(firstName) \(lastName)")
            }
        }
    }
    
    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func notSignedInView() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Not Signed In")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Sign in to access your profile and manage data sharing consents.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Button(action: {
                authManager.signIn()
            }) {
                Text("Sign In")
                    .fontWeight(.semibold)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.top, 10)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
        .padding()
    }
    
    private func fetchUserProfile() {
        guard authManager.isAuthenticated,
              let accessToken = authManager.currentAccessToken() else {
            errorMessage = "Not authenticated"
            return
        }
        
        isLoading = true
        
        // Construct the URL
        let baseURLString = authManager.issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
        guard let profileURL = URL(string: "\(baseURLString)/api/v1/users/profile") else {
            isLoading = false
            errorMessage = "Invalid profile URL"
            return
        }
        
        var request = URLRequest(url: profileURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
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
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No data received"
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self.profileData = json
                        self.errorMessage = nil
                        
                        // Print the profile data for debugging
                        print("Fetched profile data:")
                        if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
                           let jsonStr = String(data: jsonData, encoding: .utf8) {
                            print(jsonStr)
                        }
                    } else {
                        self.errorMessage = "Could not parse profile data"
                    }
                } catch {
                    self.errorMessage = "JSON parsing error: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    // Helper functions to extract data from profile
    private func extractPatientId() -> String {
        if let profileData = self.profileData,
           let patient = profileData["patient"] as? [String: Any],
           let id = patient["id"] as? Int {
            return "\(id)"
        }
        return "40010"  // Default Patient ID
    }
    
    private func extractFamilyName(from patient: [String: Any]) -> String? {
        if let name = patient["name"] as? [[String: Any]],
           let firstName = name.first,
           let family = firstName["family"] as? String {
            return family
        }
        return nil
    }
    
    private func extractGivenName(from patient: [String: Any]) -> String? {
        if let name = patient["name"] as? [[String: Any]],
           let firstName = name.first,
           let given = firstName["given"] as? [String],
           let first = given.first {
            return first
        }
        return nil
    }
    
    private func extractEmail(from patient: [String: Any]) -> String? {
        if let telecom = patient["telecom"] as? [[String: Any]] {
            for contact in telecom {
                if let system = contact["system"] as? String,
                   system == "email",
                   let value = contact["value"] as? String {
                    return value
                }
            }
        }
        return nil
    }
    
    private func extractPhone(from patient: [String: Any]) -> String? {
        if let telecom = patient["telecom"] as? [[String: Any]] {
            for contact in telecom {
                if let system = contact["system"] as? String,
                   system == "phone",
                   let value = contact["value"] as? String {
                    return value
                }
            }
        }
        return nil
    }
}

struct UserProfileView_Previews: PreviewProvider {
    static var previews: some View {
        UserProfileView()
            .environmentObject(AuthManager())
    }
}
