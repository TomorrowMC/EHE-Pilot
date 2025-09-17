import SwiftUI
import CoreLocation

struct SettingsView: View {
    @StateObject private var locationManager = LocationManager.shared
    @EnvironmentObject var authManager: AuthManager
    
    @State private var showingHomeSelector = false
    @State private var showingResetAlert = false
    @State private var csvFileURL: URL? // 用于存储导出后的CSV文件路径
    @State private var showingUserProfile = false
    @State private var showingConsentManager = false
    @State private var isProcessingLogin: Bool = false
    
    var body: some View {
        NavigationStack{
            Form {
                // User Authentication Section
                Section(header: Text("User Account")) {
                    if authManager.isAuthenticated {
                        userInfoRow
                        
                        Button(action: {
                            showingUserProfile = true
                        }) {
                            HStack {
                                Text("View Profile")
                                Spacer()
                                Image(systemName: "person.crop.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Button(action: {
                            showingConsentManager = true
                        }) {
                            HStack {
                                Text("Manage Data Sharing")
                                Spacer()
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        
                        Button(action: {
                            authManager.signOut()
                        }) {
                            HStack {
                                Text("Sign Out")
                                Spacer()
                                Image(systemName: "arrow.backward.circle")
                                    .foregroundColor(.red)
                            }
                        }
                        .foregroundColor(.red)
                    } else {
                        // 登录选项
                        loginOptionsView
                    }
                }
                
                // Home Location Section
                Section(header: Text("Home Location")) {
                    if let home = locationManager.homeLocation {
                        HStack {
                            Text("Latitude")
                            Spacer()
                            Text(String(format: "%.4f", home.latitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Longitude")
                            Spacer()
                            Text(String(format: "%.4f", home.longitude))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Radius")
                            Spacer()
                            Text("\(Int(home.radius))m")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("No home location set")
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        showingHomeSelector = true
                    }) {
                        Text(locationManager.homeLocation == nil ? "Set Home Location" : "Update Home Location")
                    }
                }
                
                // App Settings
                Section(header: Text("App Settings")) {
                    NavigationLink(destination: LocationUpdateFrequencyView()) {
                        Text("Location Update Frequency")
                    }

                    NavigationLink(destination: DataUploadView()) {
                        Text("Data Upload Settings")
                    }

                    NavigationLink(destination: OuraReminderSettingsView()) {
                        HStack {
                            Text("Oura Sync Reminder")
                            Spacer()
                            Image(systemName: "bell.fill")
                                .foregroundColor(.blue)
                        }
                    }

                    Button(action: {
                        showingResetAlert = true
                    }) {
                        Text("Reset All Data")
                            .foregroundColor(.red)
                    }
                }
                
                // Export Data Section
                Section(header: Text("Export Data")) {
                    Button("Export CSV") {
                        exportDataToCSV()
                    }
                    
                    if let fileURL = csvFileURL {
                        ShareLink(item: fileURL, preview: SharePreview("Exported Data", image: Image(systemName: "doc"))) {
                            Text("Share Exported CSV")
                        }
                    }
                }
                
                // Testing & Debug Section
                Section(header: Text("Development")) {
                    NavigationLink(destination: LoginTestView()) {
                        Text("Test OAuth Flow")
                    }
                    NavigationLink(destination: TokenTestView()){
                        Text("Test Token")
                    }
                    NavigationLink("Time Outdoors Test") {
                        TimeOutdoorsTestView()
                    }

                    Button(action: {
                        OuraManager.shared.triggerTestReminder()
                    }) {
                        HStack {
                            Text("Test Oura Notification")
                            Spacer()
                            Image(systemName: "bell.badge")
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingHomeSelector) {
                HomeLocationSelectorView()
            }
            .sheet(isPresented: $showingUserProfile) {
                UserProfileView()
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showingConsentManager) {
                ConsentManagerView(patientId: authManager.getPatientIdFromProfile())
                    .environmentObject(authManager)
            }
            .alert("Reset Data", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    // Reset functionality
                }
            } message: {
                Text("Are you sure you want to reset all location data? This action cannot be undone.")
            }
            .overlay(
                ZStack {
                    if isProcessingLogin {
                        Color.black.opacity(0.4)
                            .edgesIgnoringSafeArea(.all)
                        
                        VStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            
                            Text("Signing in...")
                                .foregroundColor(.white)
                                .padding(.top, 20)
                        }
                        .padding(20)
                        .background(Color(UIColor.systemBackground).opacity(0.8))
                        .cornerRadius(10)
                        .shadow(radius: 10)
                    }
                }
            )
        }
    }
    
    // 登录选项视图
    private var loginOptionsView: some View {
        VStack(spacing: 16) {
            // 用户名密码登录按钮
            Button {
                authManager.signIn()
            } label: {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(.white)
                        .padding(.trailing, 8)
                    Text("Sign in with Username")
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle()) // 添加这一行
            
            // 邀请链接登录按钮
            Button {
                loginWithClipboard()
            } label: {
                HStack {
                    Image(systemName: "link")
                        .foregroundColor(.white)
                        .padding(.trailing, 8)
                    Text("Sign in with Invitation Link")
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.green)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle()) // 添加这一行
        }
        .padding(.vertical, 4)
    }
    
    private func loginWithClipboard() {
        if let _ = ClipboardLoginHelper.shared.getInvitationCodeFromClipboard() {
            isProcessingLogin = true
            
            ClipboardLoginHelper.shared.loginWithClipboardContent(authManager: authManager) { success in
                isProcessingLogin = false
                
                if success {
                    // Show success alert
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        ClipboardLoginHelper.shared.showLoginSuccessAlert()
                    }
                } else {
                    // Show error if login failed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        ClipboardLoginHelper.shared.showLoginFailedAlert()
                    }
                }
            }
        } else {
            // No invitation link in clipboard
            ClipboardLoginHelper.shared.showNoInvitationLinkAlert()
        }
    }
    
    // Extract user display information
    private var userInfoRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let profileData = authManager.profileData {
                    // Try to get name from patient or user
                    let name = extractUserName(from: profileData)
                    Text(name)
                        .fontWeight(.medium)
                    
                    // Try to get email
                    if let email = extractUserEmail(from: profileData) {
                        Text(email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Show patient ID
                    Text("Patient ID: \(authManager.getPatientIdFromProfile())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Loading profile...")
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "person.crop.circle.fill")
                .font(.title)
                .foregroundColor(.blue)
        }
    }
    
    private func exportDataToCSV() {
        let context = PersistenceController.shared.container.viewContext
        do {
            let data = try CSVExporter.exportAllRecords(context: context)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("location_export.csv")
            try data.write(to: tempURL)
            csvFileURL = tempURL
        } catch {
            print("Error exporting CSV: \(error)")
        }
    }
    
    // Helper methods to extract user info
    private func extractUserName(from profileData: [String: Any]) -> String {
        // Try to get name from patient
        if let patient = profileData["patient"] as? [String: Any] {
            if let name = patient["name"] as? [[String: Any]],
               let firstName = name.first {
                let family = firstName["family"] as? String ?? ""
                
                if let given = firstName["given"] as? [String],
                   let first = given.first {
                    return "\(first) \(family)"
                }
                
                return family
            }
        }
        
        // Fallback to user info
        if let firstName = profileData["firstName"] as? String,
           let lastName = profileData["lastName"] as? String {
            return "\(firstName) \(lastName)"
        }
        
        return "User"
    }
    
    private func extractUserEmail(from profileData: [String: Any]) -> String? {
        // Try to get email from patient
        if let patient = profileData["patient"] as? [String: Any],
           let telecom = patient["telecom"] as? [[String: Any]] {
            for contact in telecom {
                if let system = contact["system"] as? String,
                   system == "email",
                   let value = contact["value"] as? String {
                    return value
                }
            }
        }
        
        // Fallback to user email
        return profileData["email"] as? String
    }
}

// Data Upload View for managing upload settings
struct DataUploadView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var fhirUploadService = FHIRUploadService.shared
    @State private var showUploadConfirmation = false
    
    var body: some View {
        Form {
            Section(header: Text("Upload Status")) {
                HStack {
                    Text("Last Upload:")
                    Spacer()
                    if let lastUploadTime = fhirUploadService.lastUploadTime {
                        Text(lastUploadTime, style: .time)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never")
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text("Status:")
                    Spacer()
                    Text(fhirUploadService.lastUploadStatus)
                        .foregroundColor(
                            fhirUploadService.lastUploadStatus.contains("Successfully") ? .green : .secondary
                        )
                }
            }
            
            Section(header: Text("Manual Upload")) {
                Button(action: {
                    if authManager.isAuthenticated {
                        uploadLocationData()
                    } else {
                        showUploadConfirmation = true
                    }
                }) {
                    HStack {
                        if fhirUploadService.isUploading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding(.trailing, 8)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.white)
                        }
                        
                        Text(fhirUploadService.isUploading ? "Uploading..." : "Upload Location Data to Server")
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(authManager.isAuthenticated ? Color.blue : Color.gray)
                    .cornerRadius(10)
                }
                .disabled(fhirUploadService.isUploading || !authManager.isAuthenticated)
                
                if !authManager.isAuthenticated {
                    Text("You need to sign in to upload data")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            
            Section(header: Text("Automatic Uploads")) {
                // Could add toggles for auto-upload settings here
                Text("Location data is automatically uploaded in the background when new records are created.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Data Upload")
        .alert(isPresented: $showUploadConfirmation) {
            Alert(
                title: Text("Authentication Required"),
                message: Text("You need to sign in before uploading data."),
                primaryButton: .default(Text("Sign In"), action: {
                    authManager.signIn()
                }),
                secondaryButton: .cancel()
            )
        }
    }
    
    private func uploadLocationData() {
        fhirUploadService.uploadLocationRecords(authManager: authManager) { success, message in
            print("Upload result: \(success ? "Success" : "Failed") - \(message)")
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AuthManager())
    }
}
