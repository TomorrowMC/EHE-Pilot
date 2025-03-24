//
//  BackgroundRefreshManager.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/3/19.
//


import Foundation
import BackgroundTasks
import UIKit

class BackgroundRefreshManager {
    static let shared = BackgroundRefreshManager()
    
    // 后台任务标识符
    private let authRefreshTaskId = "com.EHE-Pilot.AuthRefresh"
    private let locationUpdateTaskId = "com.EHE-Pilot.LocationUpdate"
    
    // 跟踪已注册的任务
    private var hasRegisteredAuthTask = false
    private var hasRegisteredLocationTask = false
    
    // 初始化时注册后台任务
    private init() {}
    
    // 注册所有后台任务
    func registerBackgroundTasks() {
        // 注册认证刷新任务
        if !hasRegisteredAuthTask {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: authRefreshTaskId, using: nil) { task in
                self.handleAuthRefreshTask(task: task as! BGAppRefreshTask)
            }
            hasRegisteredAuthTask = true
        }
        
        // 只在需要时注册位置更新任务
        if !hasRegisteredLocationTask {
            // 使用try-catch处理可能的注册异常
            do {
                BGTaskScheduler.shared.register(forTaskWithIdentifier: locationUpdateTaskId, using: nil) { task in
                    LocationManager.shared.handleBackgroundTask(task as! BGAppRefreshTask)
                }
                hasRegisteredLocationTask = true
            } catch {
                print("Location task may already be registered: \(error)")
            }
        }
    }
    
    // 修改handleAuthRefreshTask方法
    private func handleAuthRefreshTask(task: BGAppRefreshTask) {
        // 设置过期处理器
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
            print("Auth refresh task expired before completion")
        }
        
        // 先安排下一次任务，确保任务链不会中断
        scheduleAuthRefreshTask()
        
        // 获取AuthManager
        let authManager = AppDelegate.shared.authManager
        
        // 验证Token有效性
        authManager.verifyTokenValidity { isValid in
            if !isValid {
                // Token无效，尝试刷新
                authManager.refreshTokenWithStoredRefreshToken { success in
                    if success {
                        print("Successfully refreshed token in background")
                        // 令牌刷新成功，尝试上传位置数据
                        self.tryUploadLocationData(authManager: authManager)
                    } else {
                        print("Failed to refresh token in background")
                    }
                    task.setTaskCompleted(success: success)
                }
            } else {
                print("Token still valid, no refresh needed")
                // Token有效，直接尝试上传数据
                self.tryUploadLocationData(authManager: authManager)
                task.setTaskCompleted(success: true)
            }
        }
    }
    
    // 安排认证刷新任务
    func scheduleAuthRefreshTask() {
        let request = BGAppRefreshTaskRequest(identifier: authRefreshTaskId)
        // 设置为2小时后执行
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Auth refresh task scheduled for 2 hours from now")
        } catch {
            print("Failed to schedule auth refresh task: \(error)")
        }
    }
    
    // 安排位置更新任务
    func scheduleLocationUpdateTask() {
        // 与认证刷新交错执行，设为1小时
        let request = BGAppRefreshTaskRequest(identifier: locationUpdateTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1 * 60 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Location update task scheduled for 1 hour from now")
        } catch {
            print("Failed to schedule location update task: \(error)")
        }
    }
    
    // 应用进入前台时验证认证状态
    func verifyAuthenticationOnForeground() {
        let authManager = AppDelegate.shared.authManager
        
        // 如果认为已认证，但令牌不存在，重置状态
        if authManager.isAuthenticated && authManager.currentAccessToken() == nil {
            print("Invalid authentication state detected on foreground, resetting")
            authManager.signOut()
            return
        }
        
        // 如果已认证，验证令牌有效性
        if authManager.isAuthenticated {
            authManager.verifyTokenValidity { isValid in
                if !isValid {
                    print("Token invalid on foreground, attempting refresh")
                    authManager.refreshTokenIfNeeded { _ in
                        // 如果刷新后仍然没有认证，重置登录状态
                        if !authManager.isAuthenticated || authManager.currentAccessToken() == nil {
                            print("Could not restore authentication, signing out")
                            authManager.signOut()
                        }
                    }
                }
            }
        }
    }
    
    // 尝试上传位置数据
    private func tryUploadLocationData(authManager: AuthManager) {
        // 如果有未上传的数据，尝试上传
        FHIRUploadService.shared.uploadLocationRecords(authManager: authManager) { success, message in
            print("Background location upload attempt: \(success ? "Success" : "Failed") - \(message)")
        }
    }
    
    // 当应用切换到活跃状态时调用
    func applicationDidBecomeActive() {
        // 验证认证状态
        verifyAuthenticationOnForeground()
        
        // 安排后台任务
        scheduleAuthRefreshTask()
        scheduleLocationUpdateTask()
    }
    
    // 当应用进入后台时调用
    func applicationDidEnterBackground() {
        // 确保后台任务已安排
        scheduleAuthRefreshTask()
        scheduleLocationUpdateTask()
    }
    
    
}
