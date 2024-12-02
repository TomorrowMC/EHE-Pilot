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
                permissionRequestContent
            case .restricted, .denied:
                openSettingsContent
            default:
                EmptyView()
            }
        }
        .padding()
    }
    
    private var permissionRequestContent: some View {
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