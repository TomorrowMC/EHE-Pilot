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
        
        // 不再在这里注册背景任务，而是统一在AppDelegate中注册
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(AppDelegate.shared.authManager) // 使用AppDelegate中的单例
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
                }
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .active:
                // 应用进入前台时启动前台定位更新
                LocationManager.shared.startForegroundUpdates()
            case .background, .inactive:
                // 背景或非活跃时停止前台定位
                LocationManager.shared.stopForegroundUpdates()
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
