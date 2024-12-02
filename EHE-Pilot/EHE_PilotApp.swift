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
    init() {
        // 在这里进行任何必要的初始化
        _ = LocationManager.shared  // 确保LocationManager被初始化
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.yourdomain.locationUpdate", using: nil) { task in
            LocationManager.shared.handleBackgroundTask(task as! BGAppRefreshTask)
        }
    }
    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
