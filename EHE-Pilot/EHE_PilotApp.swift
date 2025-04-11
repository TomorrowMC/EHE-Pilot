//
//  EHE_PilotApp.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//

import SwiftUI
import BackgroundTasks

@main
struct EHE_PilotApp: App {
    let persistenceController = PersistenceController.shared
    @Environment(\.scenePhase) var scenePhase
    
    // 使用AppDelegate单例
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // 环境对象
    @StateObject private var locationManager = LocationManager.shared

    init() {
        // 初始化LocationManager单例
        _ = LocationManager.shared
        
        // BGTaskScheduler注册会在AppDelegate中进行，避免重复注册
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(AppDelegate.shared.authManager)
                .environmentObject(locationManager)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onOpenURL { url in
                    // 处理OAuth回调
                    if AppDelegate.shared.authManager.handleRedirectURL(url) {
                        print("Handled OAuth callback.")
                    }
                }
                .onAppear {
                    // 启动时设置位置服务
                    setupLocationServices()
                    
                    // 尝试自动登录（如果尚未登录）
                    if !AppDelegate.shared.authManager.isAuthenticated {
                        AppDelegate.shared.attemptAutoLogin()
                    }
                }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                // 应用进入前台时启动前台定位更新
                LocationManager.shared.startForegroundUpdates()
                
                // 验证认证状态 - 更改为更可靠的方法
                if AppDelegate.shared.authManager.isAuthenticated {
                    // 只检查，不进行会导致登出的API调用
                    if let expiryDate = AppDelegate.shared.authManager.getTokenExpiry(),
                       expiryDate > Date() {
                        // Token未过期，保持登录状态
                        print("Token still valid until \(expiryDate)")
                    } else {
                        // Token已过期，尝试刷新
                        AppDelegate.shared.authManager.refreshTokenWithStoredRefreshToken { success in
                            if success {
                                print("Token refreshed automatically")
                            } else {
                                print("Token refresh failed, but not logging out")
                            }
                        }
                    }
                } else if AppDelegate.shared.authManager.loadTokensFromStorage() {
                    // 如果未认证但有存储的tokens，尝试恢复会话
                    AppDelegate.shared.attemptAutoLogin()
                }
                // 安排后台任务
                BackgroundRefreshManager.shared.applicationDidBecomeActive()
                
            case .background:
                // 安排后台任务
                BackgroundRefreshManager.shared.applicationDidEnterBackground()
                
                // 停止前台定位
                LocationManager.shared.stopForegroundUpdates()
                
            case .inactive:
                // 非活跃状态不做特殊处理
                break
                
            @unknown default:
                break
            }
        }
    }
    
    private func setupLocationServices() {
        // 如果尚未授权，请求位置权限
        if !locationManager.isAuthorized {
            locationManager.requestPermission()
        }
        
        // 启动位置更新
        locationManager.startForegroundUpdates()
    }
}
