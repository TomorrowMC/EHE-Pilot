//
//  LocationPermissionView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//


import SwiftUI

struct LocationPermissionView: View {
    @StateObject private var locationManager = LocationManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.circle")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("Location Permission Required")
                .font(.title2)
                .fontWeight(.bold)
            
            switch locationManager.authorizationStatus {
            case .notDetermined:
                initialRequestContent
            case .authorizedWhenInUse:
                requestAlwaysContent
            case .denied, .restricted:
                openSettingsContent
            default:
                EmptyView()
            }
        }
        .padding()
    }
    
    private var initialRequestContent: some View {
        VStack(spacing: 20) {
            Text("We need location access to track your activity range")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
            
            Button(action: {
                locationManager.requestPermission()
            }) {
                Text("Grant Permission")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(width: 200, height: 50)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
    }
    
    private var requestAlwaysContent: some View {
        VStack(spacing: 20) {
            Text("To track your location in background, we need 'Always' permission")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
            
            Button(action: {
                locationManager.requestPermission()
            }) {
                Text("Allow Background Location")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(width: 200, height: 50)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
    }
    
    private var openSettingsContent: some View {
        VStack(spacing: 20) {
            Text("Please enable location access in Settings")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
            
            Button(action: {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }) {
                Text("Open Settings")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(width: 200, height: 50)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
    }
}
