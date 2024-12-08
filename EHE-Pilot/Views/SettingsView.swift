//
//  SettingsView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//

import SwiftUI
import CoreLocation

struct SettingsView: View {
    @StateObject private var locationManager = LocationManager.shared
    @State private var showingHomeSelector = false
    @State private var showingResetAlert = false
    
    @State private var csvFileURL: URL? // 用于存储导出后的CSV文件路径
    
    var body: some View {
        Form {
            Section(header: Text("Home Location")) {
                if let home = locationManager.homeLocation {
                    HStack {
                        Text("Latitude")
                        Spacer()
                        Text(String(format: "%.4f", home.latitude))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Longitude")
                        Spacer()
                        Text(String(format: "%.4f", home.longitude))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Radius")
                        Spacer()
                        Text("\(Int(home.radius))m")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("No home location set")
                        .foregroundColor(.secondary)
                }
                
                Button(action: {
                    showingHomeSelector = true
                }) {
                    Text(locationManager.homeLocation == nil ? "Set Home Location" : "Update Home Location")
                }
            }
            
            Section(header: Text("App Settings")) {
                NavigationLink(destination: LocationUpdateFrequencyView()) {
                    Text("Location Update Frequency")
                }
                
                Button(action: {
                    showingResetAlert = true
                }) {
                    Text("Reset All Data")
                        .foregroundColor(.red)
                }
            }
            
            // 新增导出数据的Section
            Section(header: Text("Export Data")) {
                Button("Export CSV") {
                    exportDataToCSV()
                }
                
                // 当csvFileURL有值时，显示分享按钮
                if let fileURL = csvFileURL {
                    ShareLink(item: fileURL, preview: SharePreview("Exported Data", image: Image(systemName: "doc"))) {
                        Text("Share Exported CSV")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingHomeSelector) {
            HomeLocationSelectorView()
        }
        .alert("Reset Data", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                // Add reset functionality here
            }
        } message: {
            Text("Are you sure you want to reset all location data? This action cannot be undone.")
        }
    }
    
    private func exportDataToCSV() {
        let context = PersistenceController.shared.container.viewContext
        do {
            let data = try CSVExporter.exportAllRecords(context: context)
            // 将CSV数据写入临时目录
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("export.csv")
            try data.write(to: tempURL)
            csvFileURL = tempURL
        } catch {
            print("Error exporting CSV: \(error)")
        }
    }
}
