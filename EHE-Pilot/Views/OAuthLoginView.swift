//
//  OAuthLoginView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/2/25.
//


import SwiftUI

struct OAuthLoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var manualAuthCode: String = ""
    @State private var showingProfile: Bool = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Text("EHE-Pilot OAuth Sign In")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.bottom, 8)
                    
                    // Status message
                    StatusBannerView(message: authManager.statusMessage, 
                                    isAuthenticated: authManager.isAuthenticated)
                    
                    // Authentication controls
                    authenticationControlsSection
                    
                    // Manual code exchange
                    manualCodeExchangeSection
                    
                    // Token information section
                    if authManager.isAuthenticated {
                        tokenInfoSection
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationBarItems(trailing: 
                Group {
                    if authManager.isAuthenticated {
                        Button("Sign Out") {
                            authManager.signOut()
                        }
                    }
                }
            )
            .sheet(isPresented: $showingProfile) {
                ProfileView()
                    .environmentObject(authManager)
            }
        }
    }
    
    // MARK: - Section Views
    
    private var authenticationControlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authentication")
                .font(.headline)
            
            // Discovery button
            Button(action: {
                authManager.discoverConfiguration { _ in }
            }) {
                HStack {
                    Image(systemName: "network")
                    Text("Discover OIDC Configuration")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(authManager.isAuthenticated)
            
            // Sign in button
            Button(action: {
                authManager.signIn()
            }) {
                HStack {
                    Image(systemName: "person.fill")
                    Text("Sign In with OAuth")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(authManager.isAuthenticated)
            
            // Profile test button
            Button(action: {
                if authManager.isAuthenticated {
                    authManager.fetchUserProfile { _ in
                        showingProfile = true
                    }
                }
            }) {
                HStack {
                    Image(systemName: "person.crop.circle")
                    Text("Test Profile API")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(authManager.isAuthenticated ? Color.purple : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(!authManager.isAuthenticated)
            
            // Refresh button
            Button(action: {
                authManager.refreshTokenIfNeeded { _ in }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh Token")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(authManager.isAuthenticated ? Color.orange : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(!authManager.isAuthenticated)
        }
    }
    
    private var manualCodeExchangeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manual Code Exchange")
                .font(.headline)
            
            VStack(alignment: .leading) {
                Text("Authorization Code:")
                    .font(.subheadline)
                
                HStack {
                    TextField("Enter authorization code", text: $manualAuthCode)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
                    Button(action: {
                        guard !manualAuthCode.isEmpty else { return }
                        authManager.swapCodeForToken(code: manualAuthCode) { _ in
                            manualAuthCode = ""
                        }
                    }) {
                        Text("Submit")
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }
    
    private var tokenInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Token Information")
                .font(.headline)
            
            if let accessToken = authManager.currentAccessToken() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Access Token:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(accessToken)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .lineLimit(3)
                }
            }
            
            if let refreshToken = authManager.tokenResponse?["refresh_token"] as? String {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Refresh Token:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(refreshToken)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct StatusBannerView: View {
    let message: String
    let isAuthenticated: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isAuthenticated ? "checkmark.circle.fill" : "info.circle")
                .foregroundColor(isAuthenticated ? .green : .blue)
            
            Text(message)
                .fontWeight(.medium)
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isAuthenticated ? Color.green.opacity(0.2) : Color.blue.opacity(0.2))
        )
    }
}

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("User Profile")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    if let profileData = authManager.profileData {
                        ForEach(profileData.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            profileRow(key: key, value: String(describing: value))
                        }
                    } else {
                        Text("No profile data available")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationBarItems(trailing: Button("Close") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
    
    private func profileRow(key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key.capitalized)
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
    }
}

struct OAuthLoginView_Previews: PreviewProvider {
    static var previews: some View {
        OAuthLoginView()
            .environmentObject(AuthManager())
    }
}