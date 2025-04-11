//
//  MainView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//

import SwiftUI
import UIKit


struct MainView: View {
    @StateObject private var locationManager = LocationManager.shared
    @EnvironmentObject var authManager: AuthManager
    @State private var showInvitationAlert: Bool = false
    @State private var isProcessingLogin: Bool = false
    
    var body: some View {
        Group {
            if !locationManager.isAuthorized {
                LocationPermissionView()
            } else {
                ContentTabView()
            }
        }
        // Start location updates when app appears
        .onAppear {
            LocationManager.shared.startForegroundUpdates()
            
            // Check clipboard for invitation link if not authenticated, with 2-second delay
            if !authManager.isAuthenticated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    checkClipboardForInvitationLink()
                }
            }
        }
        .onChange(of: locationManager.isAuthorized) { newValue in
            if newValue {
                print("Location permission granted, starting location tracking")
            }
        }
        .alert(isPresented: $showInvitationAlert) {
            Alert(
                title: Text("Invitation Link Detected"),
                message: Text("We detected an invitation link in your clipboard. Would you like to use it to sign in?"),
                primaryButton: .default(Text("Yes"), action: {
                    processClipboardLogin()
                }),
                secondaryButton: .cancel(Text("No"))
            )
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
    
    private func checkClipboardForInvitationLink() {
        if ClipboardLoginHelper.shared.getInvitationCodeFromClipboard() != nil {
            showInvitationAlert = true
        }
    }
    
    private func processClipboardLogin() {
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
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
