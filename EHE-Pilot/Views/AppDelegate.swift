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
        
        // 自动发现OAuth配置
        authManager.discoverConfiguration { success in
            if success {
                // 尝试自动登录
                self.attemptAutoLogin()
            }
        }
        
        return true
    }
    
    // 自动登录方法
    func attemptAutoLogin() {
        authManager.attemptAutoLogin { success in
            if success {
                print("Auto login successful")
                // 登录成功后可以执行其他初始化操作，如启动位置服务
                LocationManager.shared.startForegroundUpdates()
            } else {
                print("Auto login failed, manual login required")
            }
        }
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
        
        // 验证Token有效性
        if authManager.isAuthenticated {
            authManager.verifyTokenValidity { isValid in
                if !isValid {
                    // Token无效或过期，尝试使用刷新Token
                    self.authManager.refreshTokenWithStoredRefreshToken { success in
                        if success {
                            print("Successfully refreshed token when app became active")
                            // 刷新成功后可以触发数据上传
                            self.triggerDataUploadIfNeeded()
                        } else {
                            print("Failed to refresh token when app became active")
                        }
                    }
                } else {
                    // Token有效，可以触发数据上传
                    self.triggerDataUploadIfNeeded()
                }
            }
        }
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // 应用进入后台时安排任务
        BackgroundRefreshManager.shared.applicationDidEnterBackground()
    }
    
    // 根据需要触发数据上传
    private func triggerDataUploadIfNeeded() {
            // 有未上传数据，触发上传
            FHIRUploadService.shared.uploadLocationRecords(authManager: authManager) { success, message in
                print("Auto data upload attempt: \(success ? "Success" : "Failed") - \(message)")
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
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        // 场景激活时验证认证状态
        BackgroundRefreshManager.shared.applicationDidBecomeActive()
        
        // 验证Token有效性
        let authManager = AppDelegate.shared.authManager
        if authManager.isAuthenticated {
            authManager.verifyTokenValidity { isValid in
                if !isValid {
                    authManager.refreshTokenWithStoredRefreshToken { _ in }
                }
            }
        } else {
            // 如果未认证，尝试自动登录
            AppDelegate.shared.attemptAutoLogin()
        }
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        // 场景进入后台时安排任务
        BackgroundRefreshManager.shared.applicationDidEnterBackground()
    }
}
