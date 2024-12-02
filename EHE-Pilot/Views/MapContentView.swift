//
//  MapContentView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//


import SwiftUI
import MapKit


struct MapContentView: View {
    @StateObject private var locationManager = LocationManager.shared
    @Environment(\.managedObjectContext) private var viewContext
    
    @FetchRequest(
        entity: LocationRecord.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \LocationRecord.timestamp, ascending: true)],
        predicate: NSPredicate(format: "timestamp >= %@ AND timestamp <= %@",
                             Calendar.current.startOfDay(for: Date()) as NSDate,
                             Calendar.current.endOfDay(for: Date()) as NSDate)
    ) private var todayLocations: FetchedResults<LocationRecord>
    
    @State private var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    var body: some View {
        ZStack {
            Map(coordinateRegion: $region,
                showsUserLocation: true,
                annotationItems: Array(todayLocations)) { location in
                MapPin(coordinate: CLLocationCoordinate2D(
                    latitude: location.latitude,
                    longitude: location.longitude),
                       tint: location.isHome ? .green : .red)
            }
            .edgesIgnoringSafeArea(.top)
            
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
                    .padding(.trailing, 16) // 添加右边距
                    .padding(.bottom, 16) // 添加底部边距，避免与标签栏重叠
                }
            }
        }
        .onAppear {
            if let location = locationManager.currentLocation {
                region.center = location.coordinate
            }
        }
    }
}

struct MapContentView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MapContentView()
        }
    }
}
