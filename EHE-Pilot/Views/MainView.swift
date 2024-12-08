//
//  MainView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//


import SwiftUI

struct MainView: View {
    @StateObject private var locationManager = LocationManager.shared
    
    var body: some View {
        Group {
            if !locationManager.isAuthorized {
                LocationPermissionView()
            } else {
                ContentTabView()
            }
        }
        // 如果需要在APP刚启动时就获取位置，可以在此加一段，判断当前scenePhase，如果为active则直接启动:
        .onAppear {
                LocationManager.shared.startForegroundUpdates()
        }
        .onChange(of: locationManager.isAuthorized) { newValue in
            if newValue {
                print("Location permission granted, starting location tracking")
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
