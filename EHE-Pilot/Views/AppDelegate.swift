//
//  AppDelegate.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/3/13.
//


import UIKit
import BackgroundTasks
import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    // Shared instance for global access
    static let shared = AppDelegate()
    
    // Shared AuthManager instance
    let authManager = AuthManager()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Register background tasks
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.EHE-Pilot.LocationUpdate", using: nil) { task in
            self.handleLocationUpdateTask(task: task as! BGAppRefreshTask)
        }
        
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Handle OAuth callback
        if url.scheme == "ehepilot" && url.host == "oauth" {
            return authManager.handleRedirectURL(url)
        }
        return false
    }
    
    func handleLocationUpdateTask(task: BGAppRefreshTask) {
        // Schedule next task before this one expires
        scheduleLocationUpdateTask()
        
        let taskIdentifier = task.identifier
        print("Background task started: \(taskIdentifier)")
        
        // Create a task completion handler
        let taskCompletionHandler = { (success: Bool) in
            task.setTaskCompleted(success: success)
            print("Background task completed: \(success)")
        }
        
        // Set expiration handler
        task.expirationHandler = {
            taskCompletionHandler(false)
        }
        
        // Perform location update
        LocationManager.shared.handleBackgroundTask(task)
    }
    
    func scheduleLocationUpdateTask() {
        let request = BGAppRefreshTaskRequest(identifier: "com.EHE-Pilot.LocationUpdate")
        // Schedule for 15 minutes later
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background task scheduled")
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }
}

// MARK: - Scene Delegate
class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Handle OAuth callback URLs
        guard let url = URLContexts.first?.url else { return }
        
        if url.scheme == "ehepilot" && url.host == "oauth" {
            AppDelegate.shared.authManager.handleRedirectURL(url)
        }
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        // Schedule background tasks when app enters background
        AppDelegate.shared.scheduleLocationUpdateTask()
    }
}
