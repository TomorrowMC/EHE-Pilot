import SwiftUI

struct LoginTestView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var locationUploadManager = LocationUploadManager.shared
    @StateObject private var jhDataManager = JHDataExchangeManager.shared
    
    @State private var manualAuthCode: String = ""
    @State private var customIssuerURL: String = "https://ehepilot.com/o"
    @State private var customRedirectURI: String = "ehepilot://oauth/callback"
    @State private var showingProfile: Bool = false
    @State private var showingConfigAlert: Bool = false
    @State private var configAlertMessage: String = ""
    @State private var showingUploadAlert: Bool = false
    @State private var uploadAlertMessage: String = ""
    @State private var showingLocationPreview: Bool = false
    @State private var showingDebugTool: Bool = false
    @State private var showingConsentTool: Bool = false
    @State private var showingFHIRTool: Bool = false
    
    var body: some View {
        Form {
            // Status Section
            Section(header: Text("Status")) {
                HStack {
                    Image(systemName: authManager.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(authManager.isAuthenticated ? .green : .red)
                    Text(authManager.statusMessage)
                }
            }
            
            // Authentication Section
            Section(header: Text("OAuth Flow")) {
                Button(action: {
                    authManager.discoverConfiguration { _ in }
                }) {
                    HStack {
                        Image(systemName: "network")
                        Text("Discover OIDC Configuration")
                    }
                }
                
                Button(action: {
                    authManager.signIn()
                }) {
                    HStack {
                        Image(systemName: "person.fill")
                        Text("Sign In with OAuth")
                    }
                }
                
                if authManager.isAuthenticated {
                    Button(action: {
                        authManager.fetchUserProfile { _ in
                            showingProfile = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "person.crop.circle")
                            Text("Test Profile API")
                        }
                    }
                    
                    Button(action: {
                        authManager.refreshTokenIfNeeded { _ in }
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh Token")
                        }
                    }
                    
                    Button(action: {
                        authManager.signOut()
                    }) {
                        HStack {
                            Image(systemName: "escape")
                            Text("Sign Out")
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            
            // Manual Code Exchange Section
            Section(header: Text("Manual Code Exchange")) {
                TextField("Enter authorization code", text: $manualAuthCode)
                
                Button(action: {
                    guard !manualAuthCode.isEmpty else { return }
                    authManager.swapCodeForToken(code: manualAuthCode) { _ in
                        manualAuthCode = ""
                    }
                }) {
                    Text("Exchange Code for Token")
                }
                .disabled(manualAuthCode.isEmpty)
            }
            
            // Custom Configuration Section
            Section(header: Text("Custom Configuration")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Issuer URL:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Enter issuer URL", text: $customIssuerURL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled(true)
                        .font(.system(.body, design: .monospaced))
                    
                    Text("Redirect URI:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    
                    TextField("Enter redirect URI", text: $customRedirectURI)
                        .autocapitalization(.none)
                        .autocorrectionDisabled(true)
                        .font(.system(.body, design: .monospaced))
                }
                
                Button(action: {
                    applyCustomConfiguration()
                }) {
                    HStack {
                        Image(systemName: "arrow.up.doc.fill")
                        Text("Apply Custom Configuration")
                    }
                }
            }
            
            // Token Information Section
            if authManager.isAuthenticated {
                Section(header: Text("Token Information")) {
                    if let accessToken = authManager.currentAccessToken() {
                        VStack(alignment: .leading) {
                            Text("Access Token")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(accessToken)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(3)
                        }
                    }
                    
                    if let refreshToken = authManager.tokenResponse?["refresh_token"] as? String {
                        VStack(alignment: .leading) {
                            Text("Refresh Token")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(refreshToken)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(2)
                        }
                    }
                }
            }
            
            // JH Data Exchange upload section
            if authManager.isAuthenticated {
                Section(header: Text("JH Data Exchange Upload")) {
                    // Upload status display
                    HStack {
                        Text("Status:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(jhDataManager.lastUploadStatus)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(jhDataManager.lastUploadStatus.contains("Successfully") ? .green : .primary)
                    }
                    
                    // Last upload time
                    if let lastUploadTime = jhDataManager.lastUploadTime {
                        HStack {
                            Text("Last upload:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(lastUploadTime, style: .time)
                                .font(.caption)
                        }
                    }
                    
                    // JH Data Exchange upload button
                    Button(action: {
                        uploadToJHDataExchange()
                    }) {
                        HStack {
                            if jhDataManager.isUploading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .padding(.trailing, 8)
                            } else {
                                Image(systemName: "bolt.horizontal.fill")
                                    .foregroundColor(.white)
                            }
                            Text(jhDataManager.isUploading ? "Uploading..." : "Upload to JH Data Exchange")
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .cornerRadius(10)
                    }
                    .disabled(jhDataManager.isUploading)
                    
                    // Generate sample data buttons
                    HStack {
                        Button(action: {
                            jhDataManager.generateSampleDataWithSimpleFormat(count: 2)
                        }) {
                            Label("NYC Data", systemImage: "waveform.path.ecg")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            jhDataManager.generateSampleDataWithFullFormat(count: 2)
                        }) {
                            Label("SF Data", systemImage: "waveform.path.ecg.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // View location data button
                    Button(action: {
                        showingLocationPreview = true
                    }) {
                        Label("View/Manage Location Data", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 5)
                    
                    // Debug Tools Section
                    Section(header: Text("Debug Tools")) {
                        Button(action: {
                            showingDebugTool = true
                        }) {
                            Label("Upload Debug Tool", systemImage: "wrench.and.screwdriver.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .foregroundColor(.purple)
                        
                        Button(action: {
                            showingConsentTool = true
                        }) {
                            Label("Consent Manager", systemImage: "lock.shield.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .foregroundColor(.orange)
                        
                        Button(action: {
                            showingFHIRTool = true
                        }) {
                            Label("FHIR Test Tool", systemImage: "server.rack")
                                .frame(maxWidth: .infinity)
                        }
                        .foregroundColor(.green)
                    }
                }
                
                // Original location data upload section
                Section(header: Text("Location Data Upload")) {
                    // Upload status display
                    HStack {
                        Text("Status:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(locationUploadManager.lastUploadStatus)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(locationUploadManager.lastUploadStatus.contains("Successfully") ? .green : .primary)
                    }
                    
                    // Last upload time
                    if let lastUploadTime = locationUploadManager.lastUploadTime {
                        HStack {
                            Text("Last upload:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(lastUploadTime, style: .time)
                                .font(.caption)
                        }
                    }
                    
                    // Original upload button
                    Button(action: {
                        uploadLocationData()
                    }) {
                        HStack {
                            if locationUploadManager.isUploading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .padding(.trailing, 8)
                            } else {
                                Image(systemName: "location.fill.viewfinder")
                                    .foregroundColor(.white)
                            }
                            Text(locationUploadManager.isUploading ? "Uploading..." : "Upload Location Data")
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    .disabled(locationUploadManager.isUploading)
                }
            }
        }
        .navigationTitle("OAuth Test")
        .sheet(isPresented: $showingProfile) {
            UserProfileView()
                .environmentObject(authManager)
        }
        .alert(isPresented: $showingConfigAlert) {
            Alert(
                title: Text("Configuration Update"),
                message: Text(configAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(isPresented: $showingUploadAlert) {
            Alert(
                title: Text("Location Data Upload"),
                message: Text(uploadAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showingLocationPreview) {
            LocationDataPreviewView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showingDebugTool) {
            UploadDebugTool()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showingConsentTool) {
            ConsentDebugTool()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showingFHIRTool) {
            FHIRTestTool()
                .environmentObject(authManager)
        }
    }
    
    // 上传位置数据到原系统
    private func uploadLocationData() {
        locationUploadManager.uploadLocationData(authManager: authManager) { success, message in
            uploadAlertMessage = message
            showingUploadAlert = true
            
            // 触发触觉反馈
            let generator = UINotificationFeedbackGenerator()
            if success {
                generator.notificationOccurred(.success)
            } else {
                generator.notificationOccurred(.error)
            }
        }
    }
    
    // 上传位置数据到JH Data Exchange
    private func uploadToJHDataExchange() {
        jhDataManager.uploadLocationData(authManager: authManager) { success, message in
            uploadAlertMessage = message
            showingUploadAlert = true
            
            // 触发触觉反馈
            let generator = UINotificationFeedbackGenerator()
            if success {
                generator.notificationOccurred(.success)
            } else {
                generator.notificationOccurred(.error)
            }
        }
    }
    
    func applyCustomConfiguration() {
        guard let issuerURL = URL(string: customIssuerURL),
              let redirectURI = URL(string: customRedirectURI) else {
            configAlertMessage = "Invalid URL format. Please check your inputs."
            showingConfigAlert = true
            return
        }
        
        // 调用 AuthManager 的方法来更新配置
        let success = authManager.updateConfiguration(
            issuerURL: issuerURL,
            redirectURI: redirectURI
        )
        
        if success {
            configAlertMessage = "Configuration updated successfully!\nIssuer: \(issuerURL.absoluteString)\nRedirect: \(redirectURI.absoluteString)"
        } else {
            configAlertMessage = "Failed to update configuration."
        }
        
        showingConfigAlert = true
    }
}

struct UserProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                if let profileData = authManager.profileData {
                    ForEach(Array(profileData.keys.sorted()), id: \.self) { key in
                        if let value = profileData[key] {
                            Section(header: Text(key.capitalized)) {
                                ProfileValueView(value: value)
                            }
                        }
                    }
                } else {
                    Section {
                        Text("No profile data available")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("User Profile")
            .navigationBarItems(trailing: Button("Close") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

struct ProfileValueView: View {
    let value: Any
    
    var body: some View {
        Group {
            if let stringValue = value as? String {
                Text(stringValue)
            } else if let intValue = value as? Int {
                Text("\(intValue)")
            } else if let dictValue = value as? [String: Any] {
                ForEach(Array(dictValue.keys.sorted()), id: \.self) { key in
                    if let subValue = dictValue[key] {
                        VStack(alignment: .leading) {
                            Text(key.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ProfileValueView(value: subValue)
                        }
                        .padding(.leading)
                    }
                }
            } else if let arrayValue = value as? [Any] {
                ForEach(0..<arrayValue.count, id: \.self) { index in
                    VStack(alignment: .leading) {
                        Text("Item \(index + 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ProfileValueView(value: arrayValue[index])
                    }
                    .padding(.leading)
                }
            } else {
                Text(String(describing: value))
            }
        }
    }
}

struct LoginTestView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LoginTestView()
                .environmentObject(AuthManager())
        }
    }
}
