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
}