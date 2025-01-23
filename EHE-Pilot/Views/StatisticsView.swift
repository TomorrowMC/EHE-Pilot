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
    
    @State private var selectedDate = Date()
    @State private var records: [LocationRecord] = []
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    
    private let context = PersistenceController.shared.container.viewContext
    
    var totalTimeAway: TimeInterval {
        var timeAway: TimeInterval = 0
        var lastHomeTime: Date?
        
        let sortedRecords = records.sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
        for location in sortedRecords {
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
        
        if let last = lastHomeTime {
            let endTime = isToday(selectedDate) ? Date() : endOfDay(for: selectedDate)
            timeAway += endTime.timeIntervalSince(last)
        }
        
        return timeAway
    }
    
    // 添加一个计算户外时间的计算属性
    var totalTimeOutdoors: TimeInterval {
        var timeOutdoors: TimeInterval = 0
        var lastOutdoorsTime: Date?
        
        let sortedRecords = records.sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
        
        for location in sortedRecords {
            let isOutdoors = !location.isHome && (location.gpsAccuracy == nil || location.gpsAccuracy?.doubleValue ?? 0 < 4.0)
            
            if isOutdoors {
                if lastOutdoorsTime == nil {
                    lastOutdoorsTime = location.timestamp
                }
            } else {
                if let last = lastOutdoorsTime, let currentTimestamp = location.timestamp {
                    timeOutdoors += currentTimestamp.timeIntervalSince(last)
                    lastOutdoorsTime = nil
                }
            }
        }
        
        // 如果最后一段还在户外，计算到当前时间
        if let last = lastOutdoorsTime {
            let endTime = isToday(selectedDate) ? Date() : endOfDay(for: selectedDate)
            timeOutdoors += endTime.timeIntervalSince(last)
        }
        
        return timeOutdoors
    }
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .none
        df.timeStyle = .short
        return df
    }()
    
    private let displayDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
    
    
    // 添加分享文件的方法
    private func shareJSONFile() {
        if let jsonString = LocationManager.shared.getLatestRecordsJSON() {
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "location_records_\(Int(Date().timeIntervalSince1970)).json"
            let fileURL = tempDir.appendingPathComponent(fileName)
            
            do {
                try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
                shareURL = fileURL
                showShareSheet = true
                
                // 触觉反馈
                let generator = UIImpactFeedbackGenerator(style: .heavy)
                generator.impactOccurred()
            } catch {
                print("Error creating JSON file: \(error)")
            }
        }
    }
    
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // 日期选择区域
                    HStack {
                        Button(action: {
                            selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
                            fetchRecords(for: selectedDate)
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                        }
                        
                        Text(displayDateFormatter.string(from: selectedDate))
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Button(action: {
                            selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
                            fetchRecords(for: selectedDate)
                        }) {
                            Image(systemName: "chevron.right")
                                .font(.title2)
                        }
                    }
                    .padding(.top, 20)
                    
                    // Custom header for statistics
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Statistics")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    
                    // Statistics card
                    VStack(spacing: 12) {
                        statisticsRow(title: "Time Away", value: formatTimeInterval(totalTimeAway))
                        Divider()
                        statisticsRow(title: "Time Outdoors",
                                    value: formatTimeInterval(totalTimeOutdoors))
                        Divider()
                        statisticsRow(title: "Location Points", value: "\(records.count)")
                        Divider()
                        statisticsRow(title: "Current Status",
                                    value: locationManager.currentLocationStatus ? "At Home" : "Away",
                                    valueColor: locationManager.currentLocationStatus ? .green : .orange)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // Location records section for selected date
                    VStack(alignment: .leading, spacing: 15) {
                        Text("\(displayDateFormatter.string(from: selectedDate))'s Location Records")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        if records.isEmpty {
                            Text("No records for this day.")
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                        } else {
                            let sortedByTimestamp = records.sorted { ($0.timestamp ?? Date.distantPast) > ($1.timestamp ?? Date.distantPast) }
                            ForEach(sortedByTimestamp, id: \.objectID) { record in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Lat: \(record.latitude, specifier: "%.4f") | Lon: \(record.longitude, specifier: "%.4f")")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        // 根据ifUpdated显示标识
                                        if record.ifUpdated {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        } else {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                        }
                                    }
                                    
                                    HStack {
                                        if record.isHome {
                                            Label("At Home", systemImage: "house.fill")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                        } else {
                                            let isOutdoors = record.gpsAccuracy == nil || record.gpsAccuracy?.doubleValue ?? 0 < 4.0
                                            Label(isOutdoors ? "Outdoors" : "Indoor",
                                                  systemImage: isOutdoors ? "sun.max.fill" : "building.2.fill")
                                                .foregroundColor(isOutdoors ? .orange : .blue)
                                                .font(.caption)
                                        }
                                        Spacer()
                                        if let accuracy = record.gpsAccuracy {
                                            Text("GPS: \(accuracy.doubleValue, specifier: "%.1f")m")
                                                .font(.caption2)
                                                .foregroundColor(accuracy.doubleValue < 4.0 ? .green :
                                                               accuracy.doubleValue < 10.0 ? .orange : .red)
                                        } else {
                                            Text("GPS: N/A")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
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
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    uploadButton
                }
            }
            .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
            .onAppear {
                fetchRecords(for: selectedDate)
            }
        }
    }
    
    var uploadButton: some View {
        Button {
            // 修改为调用LocationManager的上传方法
            LocationManager.shared.attemptUploadRecords()
        } label: {
            HStack {
                Image(systemName: "arrow.up.circle")
                Text("Upload")
            }
        }
        .onLongPressGesture {
            shareJSONFile()
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
    
    private func fetchRecords(for date: Date) {
        let start = startOfDay(for: date)
        let end = endOfDay(for: date)
        
        let request: NSFetchRequest<LocationRecord> = LocationRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LocationRecord.timestamp, ascending: true)]
        request.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp <= %@", start as NSDate, end as NSDate)
        
        do {
            let result = try context.fetch(request)
            self.records = result
        } catch {
            print("Error fetching records for date \(date): \(error)")
            self.records = []
        }
    }
    
    private func startOfDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
    
    private func endOfDay(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return Calendar.current.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1)
    }
    
    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}


// 添加ShareSheet结构体
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities)
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
