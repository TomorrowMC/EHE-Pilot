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
        // 初始化并注册后台刷新管理器
        BackgroundRefreshManager.shared.registerBackgroundTasks()
        
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Handle OAuth callback
        if url.scheme == "ehepilot" && url.host == "oauth" {
            return authManager.handleRedirectURL(url)
        }
        return false
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // 应用激活时验证认证状态并安排任务
        BackgroundRefreshManager.shared.applicationDidBecomeActive()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // 应用进入后台时安排任务
        BackgroundRefreshManager.shared.applicationDidEnterBackground()
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
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        // 场景激活时验证认证状态
        BackgroundRefreshManager.shared.applicationDidBecomeActive()
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        // 场景进入后台时安排任务
        BackgroundRefreshManager.shared.applicationDidEnterBackground()
    }
}
