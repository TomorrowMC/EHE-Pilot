//
//  TokenRefreshManager.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/3/25.
//

import SwiftUICore


// 新增TokenRefreshManager类
class TokenRefreshManager {
    static let shared = TokenRefreshManager()
    
    private var refreshTimer: Timer?
    private let authManager: AuthManager
    
    private init() {
        self.authManager = AppDelegate.shared.authManager
    }
    
    func startAutoRefresh() {
        // 每隔6小时刷新一次，确保Token总是有效
        stopAutoRefresh()
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.performRefresh()
        }
    }
    
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func performRefresh() {
        // 只有在已认证时才执行刷新
        if authManager.isAuthenticated {
            print("执行定期Token刷新")
            authManager.refreshTokenWithStoredRefreshToken { success in
                if success {
                    print("定期Token刷新成功")
                } else {
                    print("定期Token刷新失败")
                }
            }
        }
    }
    
    // 在应用生命周期中调用
    func applicationDidBecomeActive() {
        startAutoRefresh()
        
        // 立即执行一次刷新确保会话有效
        if authManager.isAuthenticated {
            performRefresh()
        }
    }
    
    func applicationDidEnterBackground() {
        // 后台模式保持定时器运行
    }
}
