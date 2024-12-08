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

    init() {
        _ = LocationManager.shared
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.EHE-Pilot.LocationUpdate", using: nil) { task in
            guard let bgTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            LocationManager.shared.handleBackgroundTask(bgTask)
        }
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
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
}
