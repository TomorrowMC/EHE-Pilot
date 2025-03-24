//
//  HomeLocationSelectorView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//


import SwiftUI
import MapKit

struct HomeLocationSelectorView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var locationManager = LocationManager.shared
    
    @State private var region: MKCoordinateRegion
    @State private var selectedRadius: Double = 100
    @State private var selectedLocation: CLLocationCoordinate2D?
    @State private var showingSaveConfirmation = false
    
    init() {
        // Default to current location if available, otherwise use a default location
        if let currentLocation = LocationManager.shared.currentLocation {
            _region = State(initialValue: MKCoordinateRegion(
                center: currentLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        } else {
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack {
                    Map(coordinateRegion: $region,
                        interactionModes: .all,
                        showsUserLocation: true,
                        annotationItems: selectedLocation.map { [LocationPin(coordinate: $0)] } ?? []) { pin in
                        MapPin(coordinate: pin.coordinate, tint: .red)
                    }
                    
                    // Center indicator
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                    
                    // Current location button
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                if let location = locationManager.currentLocation {
                                    region.center = location.coordinate
                                }
                            }) {
                                Image(systemName: "location.circle.fill")
                                    .font(.title)
                                    .padding()
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(radius: 4)
                            }
                            .padding()
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set Home Range Radius")
                        .font(.headline)
                    
                    Slider(value: $selectedRadius, in: 50...500, step: 50) {
                        Text("Radius")
                    } minimumValueLabel: {
                        Text("50m")
                    } maximumValueLabel: {
                        Text("500m")
                    }
                    
                    Text("Current radius: \(Int(selectedRadius))m")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .navigationTitle("Select Home Location")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    selectedLocation = region.center
                    showingSaveConfirmation = true
                }
            )
            .alert("Confirm Location", isPresented: $showingSaveConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    locationManager.saveHomeLocation(
                        latitude: region.center.latitude,
                        longitude: region.center.longitude,
                        radius: selectedRadius
                    )
                    presentationMode.wrappedValue.dismiss()
                }
            } message: {
                Text("Set this location as your home?")
            }
        }
    }
}