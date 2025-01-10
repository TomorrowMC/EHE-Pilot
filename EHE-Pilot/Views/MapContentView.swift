//
//  MapContentView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//


import SwiftUI
import MapKit
import CoreData


struct MapContentView: View {
    @StateObject private var locationManager = LocationManager.shared
    @Environment(\.managedObjectContext) private var viewContext
    
    @State private var selectedDate = Date()
    
    // 使用计算属性动态创建FetchRequest
    private var locationRecords: [LocationRecord] {
        let startOfDay = Calendar.current.startOfDay(for: selectedDate)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let request = NSFetchRequest<LocationRecord>(entityName: "LocationRecord")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LocationRecord.timestamp, ascending: true)]
        request.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp <= %@",
                                      startOfDay as NSDate,
                                      endOfDay as NSDate)
        
        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching records: \(error)")
            return []
        }
    }
    
    @State private var region: MKCoordinateRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    
    private let displayDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
    
    var body: some View {
        NavigationView {
            ZStack {
                Map(coordinateRegion: $region,
                    showsUserLocation: true,
                    annotationItems: locationRecords) { location in
                    MapPin(coordinate: CLLocationCoordinate2D(
                        latitude: location.latitude,
                        longitude: location.longitude),
                           tint: getPinColor(for: location))
                }
                .edgesIgnoringSafeArea(.top)
                
                VStack {
                    // 日期选择器
                    VStack(spacing: 8) {
                        HStack {
                            Button(action: {
                                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.title2)
                            }
                            
                            Text(displayDateFormatter.string(from: selectedDate))
                                .font(.headline)
                                .padding(.horizontal)
                            
                            Button(action: {
                                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.title2)
                            }
                        }
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(15)
                        
                        // 记录数量显示
                        Text("\(locationRecords.count) location points")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                    
                    Spacer()
                    
                    HStack {
                        // 图例
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 10, height: 10)
                                Text("At Home")
                                    .font(.caption)
                            }
                            HStack {
                                Circle()
                                    .fill(Color.orange)
                                    .frame(width: 10, height: 10)
                                Text("Outdoors")
                                    .font(.caption)
                            }
                            HStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 10, height: 10)
                                Text("Indoor")
                                    .font(.caption)
                            }
                        }
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(10)
                        
                        Spacer()
                        
                        // 定位按钮
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            if let location = locationManager.currentLocation {
                region.center = location.coordinate
            }
        }
    }
    
    // 根据位置状态返回不同的颜色
    private func getPinColor(for location: LocationRecord) -> Color {
        if location.isHome {
            return .green
        } else {
            let isOutdoors = location.gpsAccuracy == nil || location.gpsAccuracy?.doubleValue ?? 0 < 4.0
            return isOutdoors ? .orange : .blue
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
