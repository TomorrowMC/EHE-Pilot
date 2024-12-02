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