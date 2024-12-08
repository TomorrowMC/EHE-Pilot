//
//  StatisticsView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//

import SwiftUI
import CoreData

struct StatisticsView: View {
    @StateObject private var locationManager = LocationManager.shared
    @FetchRequest(
        entity: LocationRecord.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \LocationRecord.timestamp, ascending: false)],
        predicate: NSPredicate(format: "timestamp >= %@ AND timestamp <= %@",
                               Calendar.current.startOfDay(for: Date()) as NSDate,
                               Calendar.current.endOfDay(for: Date()) as NSDate)
    ) private var todayLocations: FetchedResults<LocationRecord>

    
    var totalTimeAway: TimeInterval {
        var timeAway: TimeInterval = 0
        var lastHomeTime: Date?
        
        for location in todayLocations {
            if !location.isHome {
                if lastHomeTime == nil {
                    lastHomeTime = location.timestamp
                }
            } else {
                if let last = lastHomeTime, let currentTimestamp = location.timestamp {
                    timeAway += currentTimestamp.timeIntervalSince(last)
                    lastHomeTime = nil
                }
            }
        }
        
        // If still away, calculate time until now
        if let last = lastHomeTime {
            timeAway += Date().timeIntervalSince(last)
        }
        
        return timeAway
    }
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return df
    }()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Custom header for statistics
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Today's Statistics")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .padding(.top, 20)
                    
                    // Statistics card
                    VStack(spacing: 12) {
                        statisticsRow(title: "Time Away", value: formatTimeInterval(totalTimeAway))
                        Divider()
                        statisticsRow(title: "Location Points", value: "\(todayLocations.count)")
                        Divider()
                        statisticsRow(title: "Current Status",
                                      value: locationManager.currentLocationStatus ? "At Home" : "Away",
                                      valueColor: locationManager.currentLocationStatus ? .green : .orange)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Today's location records section
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Today's Location Records")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        if todayLocations.isEmpty {
                            Text("No records for today.")
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        } else {
                            ForEach(todayLocations, id: \.objectID) { record in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Lat: \(record.latitude, specifier: "%.4f") | Lon: \(record.longitude, specifier: "%.4f")")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }
                                    
                                    HStack {
                                        if record.isHome {
                                            Label("At Home", systemImage: "house.fill")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                        } else {
                                            Label("Away", systemImage: "figure.walk")
                                                .foregroundColor(.orange)
                                                .font(.caption)
                                        }
                                        Spacer()
                                        if let timestamp = record.timestamp {
                                            Text(dateFormatter.string(from: timestamp))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding()
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                                .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .padding(.top)
            }
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        }
    }
    
    @ViewBuilder
    private func statisticsRow(title: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
        }
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) / 60 % 60
        return String(format: "%dh %dm", hours, minutes)
    }
}
