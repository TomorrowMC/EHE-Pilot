//
//  TimeOutdoorsTestViewModel.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 4/21/25.
//


import SwiftUI
import CoreData

// MARK: - ViewModel for Test View Logic
class TimeOutdoorsTestViewModel: ObservableObject {
    @Published var records: [TimeOutdoorsRecord] = []
    @Published var logs: [String] = []
    @Published var selectedDate: Date = Date()
    @Published var inputMinutes: String = ""
    @Published var isUploading: Bool = false
    @Published var isProcessing: Bool = false // For generation/deletion

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
        log("Test View Initialized. Fetching records...")
        fetchRecords()
    }

    // --- Logging ---
    func log(_ message: String) {
        DispatchQueue.main.async {
            // Prepend new logs to the top
            self.logs.insert("[\(Date().formatted(date: .omitted, time: .standard))] \(message)", at: 0)
            // Limit log history if needed
            if self.logs.count > 100 {
                self.logs.removeLast()
            }
        }
    }

    // --- Core Data Operations ---
    func fetchRecords() {
        log("Fetching all TimeOutdoors records...")
        let request: NSFetchRequest<TimeOutdoorsRecord> = TimeOutdoorsRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TimeOutdoorsRecord.date, ascending: false)] // Newest date first

        context.perform { // Perform fetch on the context's queue
            do {
                let fetchedRecords = try self.context.fetch(request)
                DispatchQueue.main.async { // Update published property on main thread
                    self.records = fetchedRecords
                    self.log("Fetched \(fetchedRecords.count) records.")
                }
            } catch {
                self.log("Error fetching records: \(error.localizedDescription)")
                 DispatchQueue.main.async {
                     self.records = [] // Clear records on error
                 }
            }
        }
    }

    func createOrUpdateRecord() {
        guard let minutes = Int64(inputMinutes), minutes >= 0 else {
            log("Invalid input: Please enter a non-negative integer for minutes.")
            return
        }

        let targetDate = Calendar.current.startOfDay(for: selectedDate)
        log("Attempting to create/update record for \(targetDate) with \(minutes) minutes.")
        isProcessing = true

        context.perform { // Perform Core Data operations on the correct queue
             // Fetch existing record for the specific date
             let request: NSFetchRequest<TimeOutdoorsRecord> = TimeOutdoorsRecord.fetchRequest()
             request.predicate = NSPredicate(format: "date == %@", targetDate as NSDate)
             request.fetchLimit = 1

             do {
                 let results = try self.context.fetch(request)
                 let recordToUpdate: TimeOutdoorsRecord

                 if let existingRecord = results.first {
                     // Update existing record (Overwrite)
                     recordToUpdate = existingRecord
                     recordToUpdate.totalDurationMinutes = minutes
                     recordToUpdate.isUploaded = false // Reset upload status on update if needed (optional)
                     recordToUpdate.calculationTimestamp = Date()
                     self.log("Record found. Updating minutes to \(minutes).")
                 } else {
                     // Create new record
                     recordToUpdate = TimeOutdoorsRecord(context: self.context)
                     recordToUpdate.date = targetDate
                     recordToUpdate.totalDurationMinutes = minutes
                     recordToUpdate.isUploaded = false
                     recordToUpdate.calculationTimestamp = Date()
                     self.log("No record found. Creating new record.")
                 }

                 // Save changes
                 if self.context.hasChanges {
                     try self.context.save()
                     self.log("Successfully saved record for \(targetDate).")
                 } else {
                     self.log("No changes detected, save skipped.")
                 }

                 // Refresh the list after save
                 self.fetchRecords() // Fetch on the same background queue

             } catch {
                 self.log("Error creating/updating record: \(error.localizedDescription)")
                 self.context.rollback() // Rollback on error
             }
            DispatchQueue.main.async {
                self.isProcessing = false
                 self.inputMinutes = "" // Clear input field
            }
        }
    }

    func deleteRecordForSelectedDate() {
        let targetDate = Calendar.current.startOfDay(for: selectedDate)
        log("Attempting to delete record for \(targetDate).")
        isProcessing = true

        context.perform {
            let request: NSFetchRequest<TimeOutdoorsRecord> = TimeOutdoorsRecord.fetchRequest()
            request.predicate = NSPredicate(format: "date == %@", targetDate as NSDate)
            request.fetchLimit = 1

            do {
                let results = try self.context.fetch(request)
                if let recordToDelete = results.first {
                    self.context.delete(recordToDelete)
                    if self.context.hasChanges {
                         try self.context.save()
                         self.log("Successfully deleted record for \(targetDate).")
                    } else {
                         self.log("Record found but no changes after delete? (Should not happen)")
                    }
                    self.fetchRecords() // Refresh list
                } else {
                    self.log("No record found to delete for \(targetDate).")
                }
            } catch {
                self.log("Error deleting record: \(error.localizedDescription)")
                self.context.rollback()
            }
            DispatchQueue.main.async {
                 self.isProcessing = false
            }
        }
    }

    func deleteAllRecords() {
        log("Attempting to delete ALL TimeOutdoors records...")
        isProcessing = true
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = TimeOutdoorsRecord.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs // Get IDs of deleted objects

        context.perform {
            do {
                let result = try self.context.execute(deleteRequest) as? NSBatchDeleteResult
                let deletedObjectIDs = result?.result as? [NSManagedObjectID] ?? []
                self.log("Successfully deleted \(deletedObjectIDs.count) records via batch delete.")

                // Important: Merge changes if the context needs to be aware of the deletion
                if !deletedObjectIDs.isEmpty {
                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: [NSDeletedObjectsKey: deletedObjectIDs],
                        into: [self.context]
                    )
                }
                // Refresh the list
                self.fetchRecords()

            } catch {
                self.log("Error performing batch delete: \(error.localizedDescription)")
                // Batch delete doesn't use rollback in the same way
            }
             DispatchQueue.main.async {
                 self.isProcessing = false
            }
        }
    }

    func generateSampleData(days: Int = 3) {
            log("Generating sample data for the last \(days) days (excluding today)...")
            isProcessing = true
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())

            // Use a dispatch group to know when all updates are done
            let group = DispatchGroup()

            for i in 1...days {
                guard let targetDate = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
                let randomMinutes = Int64.random(in: 30...360) // Random minutes between 30 and 360

                log("Generating for \(targetDate): \(randomMinutes) min")
                group.enter() // Enter group before starting async operation
                context.perform { // Perform each update on the context's queue
                     // Fetch or create logic
                     let request: NSFetchRequest<TimeOutdoorsRecord> = TimeOutdoorsRecord.fetchRequest()
                     request.predicate = NSPredicate(format: "date == %@", targetDate as NSDate)
                     request.fetchLimit = 1
                     var record: TimeOutdoorsRecord

                     do {
                         let results = try self.context.fetch(request)
                         if let existing = results.first {
                             record = existing
                             // Don't log excessively inside the loop if not needed
                             // self.log("Updating existing record for \(targetDate.formatted(date: .short, time: .omitted))")
                         } else {
                             record = TimeOutdoorsRecord(context: self.context)
                             record.date = targetDate
                             // self.log("Creating new record for \(targetDate.formatted(date: .short, time: .omitted))")
                         }
                         record.totalDurationMinutes = randomMinutes
                         record.isUploaded = Bool.random() // Randomly set upload status
                         record.calculationTimestamp = Date()

                     } catch {
                         // Log errors if fetch fails
                         self.log("Error fetching during generation for \(targetDate): \(error)")
                     }
                    group.leave() // Leave group when this date's operation is done
                } // End context.perform
            } // End for loop

            // Notify when all generation operations are complete
            // --- 修正这里的队列 ---
            group.notify(queue: .global()) { // Notify on a global queue (or .main if prefered)
                // --- 在 notify 闭包内部，使用 context.perform 来保存 ---
                self.context.perform { // Ensure save happens on the context's queue
                    do {
                        if self.context.hasChanges {
                            try self.context.save()
                            self.log("Successfully saved generated sample data.")
                            // Refresh the list after saving all changes
                            // Ensure fetchRecords also handles threading correctly or call appropriately
                            self.fetchRecords()
                        } else {
                            self.log("No changes detected after generation.")
                        }
                    } catch {
                        self.log("Error saving generated sample data: \(error)")
                        self.context.rollback()
                    }
                    // Update UI state back on the main thread
                    DispatchQueue.main.async {
                        self.isProcessing = false
                    }
                } // End context.perform for saving
            } // End group.notify
        } // End generateSampleData
    
    // --- Force Upload ---
    func forceUploadAllRecords() {
        log("Starting FORCE upload of ALL records...")
        isUploading = true

        // 1. Check Authentication
        let authManager = AppDelegate.shared.authManager
        guard authManager.isAuthenticated else {
            log("Upload failed: User not authenticated.")
            DispatchQueue.main.async { self.isUploading = false }
            return
        }

        // 2. Fetch ALL records (ignoring isUploaded flag)
        let request: NSFetchRequest<TimeOutdoorsRecord> = TimeOutdoorsRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TimeOutdoorsRecord.date, ascending: true)]

        var allRecords: [TimeOutdoorsRecord] = []
        context.performAndWait { // Fetch synchronously within the context's queue
            do {
                allRecords = try context.fetch(request)
            } catch {
                log("Upload failed: Error fetching records: \(error.localizedDescription)")
            }
        }

        if allRecords.isEmpty {
            log("No records found to upload.")
             DispatchQueue.main.async { self.isUploading = false }
            return
        }

        log("Found \(allRecords.count) records to force upload.")

        // 3. Prepare Payloads (same logic as TimeOutdoorsManager)
        var payloads: [[String: Any]] = []
        for record in allRecords { // Iterate through ALL fetched records
            guard let recordDate = record.date else {
                 log("Warning: Skipping record with missing date during upload prep.")
                 continue
            }
            let startOfDay = Calendar.current.startOfDay(for: recordDate)
            guard let startOfNextDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay),
                  let desiredEndTime = Calendar.current.date(byAdding: .hour, value: -5, to: startOfNextDay) else {
                // 如果计算失败，记录警告并跳过此记录
                print("Warning: Could not calculate desired end time (start of next day - 4 hours) for \(recordDate). Skipping record.")
                continue
            }

            // 格式化日期为 ISO 8601 UTC (格式化部分保持不变)
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            isoFormatter.timeZone = TimeZone(secondsFromGMT: 0) // Explicitly set UTC
            let endDateTimeString = isoFormatter.string(from: desiredEndTime) // 使用调整后的时间
            // --- 新的代码结束 ---

            let durationPayload: [String: Any] = ["value": record.totalDurationMinutes, "unit": "min"]
            let finalPayload: [String: Any] = ["end_date_time": endDateTimeString, "duration": durationPayload]
            payloads.append(finalPayload)
        }
        if payloads.isEmpty {
            log("Upload failed: Failed to prepare any payloads.")
             DispatchQueue.main.async { self.isUploading = false }
            return
        }

        // 4. 调用修改后的/新的上传函数
        log("Uploading \(payloads.count) payloads (disguised as Blood Glucose)...")
        JHDataExchangeManager.shared.uploadTimeOutdoorsDisguisedAsBloodGlucose( // <--- 调用新函数
            payloads: payloads,
            authManager: authManager
        ) { success, message in
            // 5. Handle Completion
            self.log("Force Upload Result (as BG): \(success ? "Success" : "Failed") - \(message)")
            DispatchQueue.main.async {
                self.isUploading = false
                // Still DO NOT mark records as uploaded here
            }
        }
    }
//        if payloads.isEmpty {
//            log("Upload failed: Failed to prepare any payloads.")
//             DispatchQueue.main.async { self.isUploading = false }
//            return
//        }
//
//        // 4. Call Upload Service
//        log("Uploading \(payloads.count) payloads...")
//        JHDataExchangeManager.shared.uploadGenericObservations(
//            payloads: payloads,
//            observationCode: ["system": "http://loinc.org", "code": "83401-9", "display": "Time outdoors"], // Use consistent code
//            authManager: authManager
//        ) { success, message in
//            // 5. Handle Completion
//            self.log("Force Upload Result: \(success ? "Success" : "Failed") - \(message)")
//            DispatchQueue.main.async {
//                self.isUploading = false
//                // DO NOT mark records as uploaded here - it's a force upload test
//                // self.fetchRecords() // Optionally refresh if needed, but data hasn't changed
//            }
//        }
//    }
}


// MARK: - Test View UI
struct TimeOutdoorsTestView: View {
    // Use @StateObject to keep the ViewModel alive
    @StateObject private var viewModel = TimeOutdoorsTestViewModel()
     // Access CoreData context if needed directly (though ViewModel handles most)
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        NavigationView {
            VStack(spacing: 0) { // Use spacing 0 for tighter control

                // --- Controls Section ---
                Form {
                    Section("Create / Update Record") {
                        DatePicker("Select Date", selection: $viewModel.selectedDate, displayedComponents: .date)
                        HStack {
                            Text("Outdoor Minutes:")
                            TextField("e.g., 120", text: $viewModel.inputMinutes)
                                .keyboardType(.numberPad)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        Button("Save Record for Selected Date") {
                            viewModel.createOrUpdateRecord()
                        }
                        .disabled(viewModel.isProcessing || viewModel.isUploading)
                    }

                    Section("Actions") {
                        Button("Generate Sample Data (Last 3 Days)") {
                            viewModel.generateSampleData()
                        }
                        .disabled(viewModel.isProcessing || viewModel.isUploading)

                        Button("Force Upload All Records") {
                            viewModel.forceUploadAllRecords()
                        }
                        .disabled(viewModel.isProcessing || viewModel.isUploading)
                         // Display progress during upload
                         if viewModel.isUploading {
                             ProgressView("Uploading...")
                         }


                        Button("Delete Record for Selected Date", role: .destructive) {
                            viewModel.deleteRecordForSelectedDate()
                        }
                        .disabled(viewModel.isProcessing || viewModel.isUploading)

                        Button("Delete ALL Records", role: .destructive) {
                             // Add confirmation later if needed
                            viewModel.deleteAllRecords()
                        }
                        .disabled(viewModel.isProcessing || viewModel.isUploading)
                    }
                }
                 .frame(maxHeight: 380) // Limit height of the Form
                 .disabled(viewModel.isProcessing) // Disable form while processing deletions/generations


                Divider()

                // --- Data Display Section ---
                 Text("Stored Records").font(.headline).padding(.top)
                List {
                    if viewModel.records.isEmpty {
                         Text("No TimeOutdoors records found.").foregroundColor(.secondary)
                     } else {
                         ForEach(viewModel.records) { record in
                            HStack {
                                Text(record.date ?? Date(), style: .date)
                                Spacer()
                                Text("\(record.totalDurationMinutes) min")
                                Spacer()
                                Image(systemName: record.isUploaded ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundColor(record.isUploaded ? .green : .gray)
                            }
                        }
                     }
                }
                .listStyle(PlainListStyle()) // Use plain style for tighter look
                .frame(maxHeight: .infinity) // Allow list to take remaining space


                Divider()

                // --- Log Display Section ---
                Text("Logs").font(.headline).padding(.top)
                TextEditor(text: .constant(viewModel.logs.joined(separator: "\n")))
                     .font(.system(.caption, design: .monospaced)) // Monospaced font for logs
                     .frame(height: 150) // Fixed height for log view
                     .border(Color.gray.opacity(0.5)) // Add border for visibility
                     .padding(.horizontal)
                     .padding(.bottom)


            } // End VStack
            .navigationTitle("Time Outdoors Test")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Re-fetch when the view appears in case data changed elsewhere
                 viewModel.fetchRecords()
            }
        } // End NavigationView
    }


}


// MARK: - Preview
struct TimeOutdoorsTestView_Previews: PreviewProvider {
    static var previews: some View {
        TimeOutdoorsTestView()
            // Provide the preview context for the preview to work
    }
}
