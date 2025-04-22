//
//  StatisticsView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//

import SwiftUI
import CoreData

struct StatisticsView: View {
    // --- StateObjects ---
    // locationManager 用于位置相关的状态和数据显示
    @StateObject private var locationManager = LocationManager.shared
    // timeOutdoorsManager 用于处理户外时间的计算、存储和上传状态
    @StateObject private var timeOutdoorsManager = TimeOutdoorsManager.shared // <--- 添加 TimeOutdoorsManager

    // --- State Variables ---
    @State private var selectedDate = Date()
    @State private var records: [LocationRecord] = []
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var uploadMessage: String? // 用于显示上传结果或状态

    // --- CoreData Context ---
    private let context = PersistenceController.shared.container.viewContext

    // --- Computed Properties (保持不变) ---
    var totalTimeAway: TimeInterval {
        var timeAway: TimeInterval = 0
        var lastHomeTime: Date?
        var hasHomeRecord = false

        let sortedRecords = records.sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
        let endTime = isToday(selectedDate) ? Date() : endOfDay(for: selectedDate)

        for location in sortedRecords {
            if location.isHome {
                hasHomeRecord = true
                if let last = lastHomeTime, let currentTimestamp = location.timestamp {
                    timeAway += currentTimestamp.timeIntervalSince(last)
                    lastHomeTime = nil
                }
            } else {
                if lastHomeTime == nil {
                    lastHomeTime = location.timestamp
                }
            }
        }

        if !hasHomeRecord, let firstRecord = sortedRecords.first, let firstTimestamp = firstRecord.timestamp {
            timeAway = endTime.timeIntervalSince(firstTimestamp)
            return timeAway
        }

        if let last = lastHomeTime {
            timeAway += endTime.timeIntervalSince(last)
        }

        return timeAway
    }

    // --- 计算户外时间 (仅用于显示，实际计算在 TimeOutdoorsManager) ---
    // Note: This calculation logic might slightly differ from TimeOutdoorsManager's
    // persistent calculation if rules change. Consider unifying if needed.
    var displayTotalTimeOutdoors: TimeInterval {
        var timeOutdoors: TimeInterval = 0
        var lastOutdoorsTime: Date?
        var hasIndoorRecord = false // Renamed for clarity, assuming 'indoor' means 'not outdoors'

        let sortedRecords = records.sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
        let endTime = isToday(selectedDate) ? Date() : endOfDay(for: selectedDate)

        // Use the same definition of 'outdoors' as in StatisticsCalculator for consistency
        // Let's assume outdoors = !isHome and good GPS accuracy (e.g., < 10m) or unknown
        for location in sortedRecords {
             let isConsideredOutdoors = !location.isHome && (location.gpsAccuracy == nil || (location.gpsAccuracy?.doubleValue ?? 100.0) < 10.0)

            if isConsideredOutdoors {
                if lastOutdoorsTime == nil, let ts = location.timestamp {
                    lastOutdoorsTime = ts // Start of an outdoor segment
                }
            } else { // Considered 'indoors' or 'at home'
                hasIndoorRecord = true // Mark that at least one non-outdoor record exists
                if let last = lastOutdoorsTime, let currentTimestamp = location.timestamp {
                    timeOutdoors += currentTimestamp.timeIntervalSince(last) // End the previous outdoor segment
                    lastOutdoorsTime = nil // Reset
                }
            }
        }

        // If the entire day was recorded as outdoors
        if !hasIndoorRecord, let firstRecord = sortedRecords.first, let firstTimestamp = firstRecord.timestamp {
            timeOutdoors = endTime.timeIntervalSince(firstTimestamp)
            return max(0, timeOutdoors) // Ensure non-negative
        }

        // If the last record was 'outdoors'
        if let last = lastOutdoorsTime {
            timeOutdoors += endTime.timeIntervalSince(last)
        }

        return max(0, timeOutdoors) // Ensure non-negative
    }

    // --- Formatters (保持不变) ---
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


    // ---分享 JSON 文件 (保持不变) ---
    private func shareJSONFile() {
        // Consider fetching a combined JSON or separate files if needed
        if let jsonString = LocationManager.shared.getLatestRecordsJSON() {
            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "location_records_\(Int(Date().timeIntervalSince1970)).json"
            let fileURL = tempDir.appendingPathComponent(fileName)

            do {
                try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
                shareURL = fileURL
                showShareSheet = true

                let generator = UIImpactFeedbackGenerator(style: .medium) // Use medium feedback
                generator.impactOccurred()
            } catch {
                print("Error creating JSON file: \(error)")
                uploadMessage = "Error creating export file." // Show error
            }
        } else {
             uploadMessage = "No location data to export."
        }
    }


    // --- Body ---
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 20) {

                        // Date Selector
                        HStack {
                            Button(action: { changeDate(by: -1) }) { // <--- 用 {} 包裹起来
                                Image(systemName: "chevron.left").font(.title2)
                            }
                            Spacer()
                            Text(displayDateFormatter.string(from: selectedDate))
                                .font(.headline)
                                .padding(.horizontal)
                            Spacer()
                            Button(action: { changeDate(by: 1) }) { // <--- 用 {} 包裹起来
                                Image(systemName: "chevron.right").font(.title2)
                            }
                            .disabled(!canChangeDate(by: 1)) // 保持禁用逻辑
                            .foregroundColor(canChangeDate(by: 1) ? .blue : .gray)

                        }
                        .padding(.top, 20)
                        .padding(.horizontal) // Add horizontal padding

                        // Statistics Header
                        VStack(spacing: 12) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.blue)
                            Text("Daily Summary") // Changed title slightly
                                .font(.title2)
                                .fontWeight(.semibold)
                        }

                        // Statistics Card
                        VStack(spacing: 12) {
                            statisticsRow(title: "Time Away From Home", value: formatTimeInterval(totalTimeAway))
                            Divider()
                            // Display the locally calculated outdoor time
                            statisticsRow(title: "Time Outdoors (Display)", value: formatTimeInterval(displayTotalTimeOutdoors))
                            Divider()
                            statisticsRow(title: "Location Points Recorded", value: "\(records.count)")
                            Divider()
                            statisticsRow(title: "Current Status",
                                        value: locationManager.currentLocationStatus ? "At Home" : "Away",
                                        valueColor: locationManager.currentLocationStatus ? .green : .orange)
                        }
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(12)
                        .padding(.horizontal)

                        // --- Upload Status Area ---
                        // Show status message from TimeOutdoorsManager or LocationManager
                        if timeOutdoorsManager.isProcessing || locationManager.isUploading {
                             ProgressView("Uploading...") // Show progress indicator
                                 .padding(.top, 5)
                        } else if let msg = uploadMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(msg.contains("Error") || msg.contains("Failed") ? .red : .green)
                                .padding(.top, 5)
                                .onAppear {
                                     // Clear message after a delay
                                     DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                                         uploadMessage = nil
                                     }
                                }
                        }
                        // --- End Upload Status Area ---


                        // Location Records List
                        VStack(alignment: .leading, spacing: 15) {
                            Text("\(displayDateFormatter.string(from: selectedDate))'s Location Records")
                                .font(.headline)
                                .padding(.horizontal)

                            if records.isEmpty {
                                Text("No records found for this day.")
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                    .frame(maxWidth: .infinity, alignment: .center) // Center message
                            } else {
                                let sortedByTimestamp = records.sorted { ($0.timestamp ?? Date.distantPast) > ($1.timestamp ?? Date.distantPast) }
                                ForEach(sortedByTimestamp, id: \.objectID) { record in
                                    locationRecordRow(record: record) // Extracted to function
                                        .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                    .padding(.top)
                    .padding(.bottom, 80) // Increased bottom padding for button overlap
                } // End ScrollView

                // --- Go to Today Button ---
                if !isToday(selectedDate) {
                    Button {
                        selectedDate = Date()
                        fetchRecords(for: selectedDate)
                        let generator = UIImpactFeedbackGenerator(style: .light) // Lighter feedback
                        generator.impactOccurred()
                    } label: {
                        Label("Go to Today", systemImage: "arrow.uturn.backward.circle.fill")
                            .font(.system(size: 14, weight: .medium))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color.blue.opacity(0.9)) // Slightly transparent
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.2), radius: 5, y: 2) // Adjusted shadow
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.easeInOut, value: isToday(selectedDate))
                }
                // --- End Go to Today Button ---

            } // End ZStack
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    uploadButton // Use the modified uploadButton
                }
            }
            .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
            .onAppear {
                fetchRecords(for: selectedDate)
                // Also trigger TimeOutdoors calculation on appear, but don't block UI
                 timeOutdoorsManager.processAndStorePastDaysOutdoorsTime { _ in } // Fire and forget
            }
            .sheet(isPresented: $showShareSheet) {
                 if let url = shareURL {
                     ShareSheet(activityItems: [url])
                 }
             }
        } // End NavigationView
        .navigationViewStyle(.stack) // Explicitly set style
    }

    // --- Modified Upload Button ---
    var uploadButton: some View {
        Button {
            // --- Trigger BOTH uploads ---
            print("Manual Upload Triggered")
            uploadMessage = "Starting upload..." // Initial message

            // 1. Trigger Location Upload (Assuming it updates its own status via @Published)
            // We might want a completion handler here too for better status coordination.
            // For now, we rely on observing locationManager.isUploading.
             // LocationManager.shared.attemptUploadRecords() // Or use FHIRUploadService if that's the primary uploader

            // Let's assume FHIRUploadService is used and has a completion handler
            FHIRUploadService.shared.uploadLocationRecords(authManager: AppDelegate.shared.authManager) { locSuccess, locMessage in
                 DispatchQueue.main.async {
                     if !locSuccess {
                         self.uploadMessage = "Location Upload: \(locMessage)"
                     } else {
                         // Optionally clear message or wait for TimeOutdoors upload
                         print("Location Upload: \(locMessage)")
                     }
                 }
             }
            // 2. Trigger Time Outdoors Calculation & Upload (Uses triggerUploadFromForeground)
            timeOutdoorsManager.triggerUploadFromForeground() // This updates its @Published vars

            // Give haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

        } label: {
            // Show progress view if either manager is processing
            if locationManager.isUploading || timeOutdoorsManager.isProcessing {
                 ProgressView()
                     .progressViewStyle(.circular)
                     .frame(width: 20, height: 20) // Smaller progress view
            } else {
                HStack {
                    Image(systemName: "arrow.up.circle.fill") // Changed icon slightly
                    Text("Upload Now") // Changed text slightly
                }
            }
        }
        .disabled(locationManager.isUploading || timeOutdoorsManager.isProcessing) // Disable while uploading
        .onLongPressGesture {
            shareJSONFile() // Keep long press for JSON export
        }
        // Observe TimeOutdoorsManager's message for final status update
        // This combines status reporting
        .onChange(of: timeOutdoorsManager.lastProcessingMessage) { newMessage in
            if !timeOutdoorsManager.isProcessing && !newMessage.isEmpty {
                 // Only update if TimeOutdoors just finished and had a message
                 // Prioritize TimeOutdoors message if both finish around the same time
                 self.uploadMessage = "Time Outdoors: \(newMessage)"
            }
        }
    }

    // --- Extracted ViewBuilder for statistics row ---
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
                .lineLimit(1) // Prevent wrapping
                .minimumScaleFactor(0.8) // Allow slight shrinking
        }
    }

    // --- Extracted ViewBuilder for location record row ---
    @ViewBuilder
    private func locationRecordRow(record: LocationRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Lat: \(record.latitude, specifier: "%.4f") | Lon: \(record.longitude, specifier: "%.4f")")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                // Upload status indicator
                if record.ifUpdated {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .help("Uploaded") // Accessibility hint
                } else {
                    Image(systemName: "icloud.slash.fill") // Different icon for not uploaded
                        .foregroundColor(.gray)
                        .help("Pending Upload") // Accessibility hint
                }
            }

            HStack(spacing: 10) { // Added spacing
                // Home/Away/Outdoor status label
                if record.isHome {
                    Label("At Home", systemImage: "house.fill")
                        .foregroundColor(.green)
                } else {
                     // Consistent definition of outdoors
                     let isConsideredOutdoors = record.gpsAccuracy == nil || (record.gpsAccuracy?.doubleValue ?? 100.0) < 10.0
                    Label(isConsideredOutdoors ? "Outdoors" : "Indoor (Away)",
                          systemImage: isConsideredOutdoors ? "sun.max.fill" : "building.2.fill")
                        .foregroundColor(isConsideredOutdoors ? .orange : .purple) // Changed indoor color
                }

                Spacer()

                // GPS Accuracy Text
                if let accuracy = record.gpsAccuracy {
                     Text("GPS: \(accuracy.doubleValue, specifier: "%.1f")m")
                          .foregroundColor(accuracy.doubleValue < 10.0 ? .green :
                                         accuracy.doubleValue < 30.0 ? .orange : .red) // Adjusted thresholds
                } else {
                     Text("GPS: n/a")
                          .foregroundColor(.secondary)
                }

                // Timestamp Text
                if let timestamp = record.timestamp {
                    Text(dateFormatter.string(from: timestamp))
                        .foregroundColor(.secondary)
                }
            }
            .font(.caption) // Apply caption font to the whole HStack
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
    }


    // --- Helper Functions (保持不变) ---
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated // "h", "m"
        // Handle zero interval explicitly
        return interval > 0 ? (formatter.string(from: interval) ?? "0m") : "0m"
    }

    private func fetchRecords(for date: Date) {
        let start = startOfDay(for: date)
        // Use end of day exclusive for fetch predicate to match calculation logic better
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
             print("Error calculating end date for fetch")
             self.records = []
             return
        }

        let request: NSFetchRequest<LocationRecord> = LocationRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LocationRecord.timestamp, ascending: true)]
        // Fetch records >= start AND < next day's start
        request.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", start as NSDate, end as NSDate)

        do {
            // Perform fetch on the correct context
             self.records = try context.fetch(request)
             print("Fetched \(self.records.count) records for \(date)")
        } catch {
            print("Error fetching records for date \(date): \(error)")
            self.records = []
        }
    }

    private func startOfDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    // Helper to calculate end of day (exclusive) for consistency
     private func endOfDayExclusive(for date: Date) -> Date? {
         let start = startOfDay(for: date)
         return Calendar.current.date(byAdding: .day, value: 1, to: start)
     }

     // Helper to calculate end of day (inclusive 23:59:59)
     private func endOfDay(for date: Date) -> Date {
         let start = startOfDay(for: date)
         return Calendar.current.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1)
     }


    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    // Helper function to check if date can be changed
    private func canChangeDate(by days: Int) -> Bool {
        guard let currentDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else {
            return false //无法计算目标日期
        }

        if days > 0 { // 如果是向未来移动
            let today = Calendar.current.startOfDay(for: Date())
            guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else {
                return false // 无法计算明天
            }
            // 目标日期必须早于明天（即不能是明天或之后）
            return currentDate < tomorrow
        }
        return true // 总是允许向过去移动
    }

     // Helper function to change date and fetch records
     private func changeDate(by days: Int) {
         if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
             if days > 0 && !canChangeDate(by: days) { return } // Don't change if invalid future date
             selectedDate = newDate
             fetchRecords(for: selectedDate)
             let generator = UIImpactFeedbackGenerator(style: .light)
             generator.impactOccurred()
         }
     }
}


// ShareSheet Struct (保持不变)
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


// --- Preview Provider (Optional, for canvas debugging) ---
struct StatisticsView_Previews: PreviewProvider {
    static var previews: some View {
        // Setup preview environment if needed (e.g., inject mock managers)
        StatisticsView()
           .environmentObject(LocationManager.shared) // Provide LocationManager
           .environmentObject(TimeOutdoorsManager.shared) // Provide TimeOutdoorsManager
    }
}
