//
//  TokenTestView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/3/24.
//


import SwiftUI

struct TokenTestView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var refreshResult: String = ""
    @State private var showTokenDetails = false
    
    var body: some View {
        Form {
            Section(header: Text("Authentication Status")) {
                HStack {
                    Text("Logged In:")
                    Spacer()
                    Text(authManager.isAuthenticated ? "Yes" : "No")
                        .foregroundColor(authManager.isAuthenticated ? .green : .red)
                }
                
                if authManager.isAuthenticated {
                    Button("Show/Hide Token Details") {
                        showTokenDetails.toggle()
                    }
                    
                    if showTokenDetails, let tokenResponse = authManager.tokenResponse {
                        VStack(alignment: .leading, spacing: 8) {
                            if let accessToken = tokenResponse["access_token"] as? String {
                                Text("Access Token:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(accessToken.prefix(20) + "..."))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let refreshToken = tokenResponse["refresh_token"] as? String {
                                Text("Refresh Token:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(refreshToken.prefix(20) + "..."))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let expiryDate = authManager.getTokenExpiry() {
                                Text("Expires at:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(expiryDate, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(expiryDate, style: .time)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                // 添加过期状态
                                let isExpired = Date() > expiryDate
                                HStack {
                                    Text("Status:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(isExpired ? "Expired" : "Valid")
                                        .font(.caption)
                                        .foregroundColor(isExpired ? .red : .green)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            
            Section(header: Text("Token Tests")) {
                Button("Verify Token") {
                    authManager.verifyTokenValidity { isValid in
                        refreshResult = isValid ? "Token is valid" : "Token is invalid or expired"
                    }
                }
                
                Button("Force Refresh Token") {
                    authManager.refreshTokenWithStoredRefreshToken { success in
                        refreshResult = success ? "Token refreshed successfully" : "Token refresh failed"
                    }
                }
                
                Button("Load Tokens from Storage") {
                    let success = authManager.loadTokensFromStorage()
                    refreshResult = success ? "Loaded tokens from storage" : "Failed to load tokens"
                }
                
                Button("Clear Stored Tokens") {
                    authManager.clearStoredTokens()
                    refreshResult = "Tokens cleared from storage"
                }
                
                Button("Sync Current Tokens to KeyChain") {
                    let success = authManager.syncCurrentTokensToKeyChain()
                    refreshResult = success ? "Successfully synced tokens to KeyChain" : "Failed to sync tokens"
                }
                
                if !refreshResult.isEmpty {
                    Text(refreshResult)
                        .foregroundColor(refreshResult.contains("success") || refreshResult.contains("valid") || refreshResult.contains("Loaded") ? .green : .secondary)
                        .padding(.top, 4)
                }
            }
            
            Section(header: Text("Auto Login Test")) {
                Button("Test Auto Login") {
                    if authManager.isAuthenticated {
                        authManager.signOut()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            AppDelegate.shared.attemptAutoLogin()
                            refreshResult = "Auto login test initiated"
                        }
                    } else {
                        AppDelegate.shared.attemptAutoLogin()
                        refreshResult = "Auto login test initiated"
                    }
                }
            }
        }
        .navigationTitle("Token Test")
    }
}
