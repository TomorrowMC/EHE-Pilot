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