//
//  ContentTabView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//


import SwiftUI

struct ContentTabView: View {
    var body: some View {
        TabView {
            MapContentView()
                .tabItem {
                    Label("Map", systemImage: "map")
                }
            
            StatisticsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}