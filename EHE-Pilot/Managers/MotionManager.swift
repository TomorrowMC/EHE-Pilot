//
//  MotionManager.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//

import Foundation
import CoreMotion
import Combine

class MotionManager: ObservableObject {
    static let shared = MotionManager()
    
    private let activityManager = CMMotionActivityManager()
    @Published var isUserMoving = false // 简化逻辑：true表示用户在移动，false表示用户静止
    
    private init() {
        startMonitoring()
    }
    
    private func startMonitoring() {
        guard CMMotionActivityManager.isActivityAvailable() else {
            print("Motion Activity not available on this device.")
            return
        }
        
        activityManager.startActivityUpdates(to: OperationQueue.main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            
            // 简化判断逻辑：如果用户在走路、跑步、骑行或驾车就算moving；否则静止
            let moving = activity.walking || activity.running || activity.cycling || activity.automotive
            
            DispatchQueue.main.async {
                self.isUserMoving = moving
            }
        }
    }
}