//
//  ClipboardLoginHelper.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 4/11/25.
//


// ClipboardLoginHelper.swift
import SwiftUI
import UIKit

class ClipboardLoginHelper {
    static let shared = ClipboardLoginHelper()
    private init() {}
    
    // Parse invitation link from clipboard
    func getInvitationCodeFromClipboard() -> String? {
        guard let content = UIPasteboard.general.string else { return nil }
        
        // Check if content looks like an invitation link
        let invitationPattern = "cloud_sharing_code="
        if content.contains(invitationPattern) {
            return content
        }
        
        return nil
    }
    
    // Login with clipboard content
    func loginWithClipboardContent(authManager: AuthManager, completion: @escaping (Bool) -> Void) {
        guard let clipboardContent = getInvitationCodeFromClipboard() else {
            completion(false)
            return
        }
        
        // Check if we can extract authorization code
        if let authCode = authManager.parseInvitationLink(url: clipboardContent) {
            // Use authorization code to login
            authManager.loginWithAuthorizationCode(code: authCode) { success in
                completion(success)
            }
        } else {
            completion(false)
        }
    }
    
    // Show different types of alerts
    func showAlert(title: String, message: String) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        // Get the current window scene
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }
    
    // Show login success alert
    func showLoginSuccessAlert() {
        showAlert(
            title: "Login Successful",
            message: "You have been successfully signed in."
        )
    }
    
    // Show login failed alert
    func showLoginFailedAlert() {
        showAlert(
            title: "Login Failed",
            message: "We couldn't sign you in with the provided invitation link. The link may have expired or is invalid."
        )
    }
    
    // Show invalid link alert
    func showInvalidLinkAlert() {
        showAlert(
            title: "Invalid Invitation Link",
            message: "We couldn't process the invitation link. Please make sure you have copied the correct link."
        )
    }
    
    // Show no invitation link alert
    func showNoInvitationLinkAlert() {
        showAlert(
            title: "No Invitation Link",
            message: "We couldn't find an invitation link in your clipboard. Please copy the invitation link first."
        )
    }
}