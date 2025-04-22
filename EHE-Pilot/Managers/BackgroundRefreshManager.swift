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
    private let timeOutdoorsUpdateTaskId = "com.EHE-Pilot.TimeOutdoorsUpdate"

    // 跟踪已注册的任务
    private var hasRegisteredAuthTask = false
    private var hasRegisteredLocationTask = false
    private var hasRegisteredTimeOutdoorsTask = false // 添加跟踪变量
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
        
        // 注册 Time Outdoors 更新任务
        if !hasRegisteredTimeOutdoorsTask {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: timeOutdoorsUpdateTaskId, using: nil) { task in
                // 调用新的处理函数
                self.handleTimeOutdoorsTask(task: task as! BGAppRefreshTask)
            }
            hasRegisteredTimeOutdoorsTask = true
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
    
    private func handleTimeOutdoorsTask(task: BGAppRefreshTask) {
        // 1. 先安排下一次任务 (重要！)
        scheduleTimeOutdoorsUpdateTask() // 你需要创建这个 schedule 方法

        // 2. 设置过期处理
        task.expirationHandler = {
            // 如果任务超时，需要在这里处理，例如取消网络请求
            task.setTaskCompleted(success: false)
            print("Time Outdoors background task expired.")
        }

        // 3. 执行你的 Time Outdoors 计算和上传逻辑
        print("Starting Time Outdoors background task...")
        // 使用 Dispatch Group 确保异步操作完成后再结束任务
        let group = DispatchGroup()
        var success = true // 跟踪任务是否成功

        group.enter() // 进入 Dispatch Group
        TimeOutdoorsManager.shared.processAndStorePastDaysOutdoorsTime { processSuccess in
             if !processSuccess {
                 print("Time Outdoors processing failed in background.")
                 success = false
             }
             // 不论成功失败，处理完成后离开 group
             group.leave()

             // 处理完成后，在这里触发上传 (上传也应该是异步的)
             // 注意：TimeOutdoorsManager 内部的上传逻辑也需要回调来通知完成
             if processSuccess { // 只有处理成功才尝试上传
                group.enter()
                TimeOutdoorsManager.shared.triggerUploadInBackground { uploadSuccess, message in
                     if !uploadSuccess {
                         print("Time Outdoors upload failed in background: \(message)")
                         // 根据需求决定上传失败是否算作整个任务失败
                         // success = false // 如果上传失败算任务失败，取消这行注释
                     }
                     group.leave()
                }
             }
        }


        // 4. 等待所有异步操作完成
         group.notify(queue: .global()) { // 使用全局队列等待
             // 5. 结束后台任务
             print("Time Outdoors background task finished with success: \(success)")
             task.setTaskCompleted(success: success)
        }

        // --- 为了防止任务因为主线程阻塞而无法及时完成，
        // --- 确保 TimeOutdoorsManager 中的方法是异步执行且有完成回调 ---
        // --- 你可能需要修改 TimeOutdoorsManager 的方法签名以接受 completion handler ---

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
    
    func scheduleTimeOutdoorsUpdateTask() {
        let request = BGAppRefreshTaskRequest(identifier: timeOutdoorsUpdateTaskId)
        // 设置执行频率，例如每 4 小时一次，并与其他任务错开
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("Time Outdoors update task scheduled.")
        } catch {
            print("Failed to schedule Time Outdoors update task: \(error)")
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
        scheduleTimeOutdoorsUpdateTask()
    }
    
    // 当应用进入后台时调用
    func applicationDidEnterBackground() {
        // 确保后台任务已安排
        scheduleAuthRefreshTask()
        scheduleLocationUpdateTask()
        scheduleTimeOutdoorsUpdateTask()
    }
    
    
}
