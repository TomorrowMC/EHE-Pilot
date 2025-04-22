//
//  TimeOutdoorsManager.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/4/21. // 修改日期以反映更新
//

import Foundation
import CoreData
import Combine // If state publishing is needed

class TimeOutdoorsManager: ObservableObject {
    // 单例实例 (Singleton instance)
    static let shared = TimeOutdoorsManager() // Ensure class name matches if changed
    private let context = PersistenceController.shared.container.viewContext
    private var cancellables = Set<AnyCancellable>() // If observing AuthManager

    // Published properties for UI updates
    @Published var isProcessing: Bool = false
    @Published var lastProcessingMessage: String = ""

    private init() {
        // Can observe login status changes here if needed for auto-upload trigger
        // AppDelegate.shared.authManager.$isAuthenticated.sink { ... }.store(in: &cancellables)
    }

    // --- 修改后的核心方法：添加 completion handler ---
    /// 计算并存储过去 N 天的户外时间，并通过回调通知完成状态。
    /// (Calculates and stores outdoor time for the past N days, notifies completion status via callback.)
    /// - Parameters:
    ///   - days: 要处理的天数 (Number of days to process).
    ///   - completion: 操作完成后的回调，参数为 Bool 表示是否成功 (Callback after operation finishes, Bool parameter indicates success).
    func processAndStorePastDaysOutdoorsTime(days: Int = 5, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else {
                completion(false) // self is nil, fail early
                return
            }

            DispatchQueue.main.async {
                self.isProcessing = true
                self.lastProcessingMessage = "Calculating past outdoor times..."
            }

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            var overallSuccess = true // Track if any step fails

            for i in 1...days {
                guard let targetDate = calendar.date(byAdding: .day, value: -i, to: today) else {
                    print("Error calculating target date for day \(i). Skipping.")
                    continue // Skip this day but continue the loop
                }

                // Check if a record for this date already exists in the database
                if self.fetchTimeOutdoorsRecord(for: targetDate) != nil {
                    print("TimeOutdoorsRecord for \(targetDate) already exists. Skipping.")
                    continue
                }

                // Calculate outdoor time
                let timeOutdoorsInterval = StatisticsCalculator.calculateTimeOutdoors(for: targetDate, using: self.context)
                let totalMinutes = Int64(round(timeOutdoorsInterval / 60.0)) // Round to nearest minute

                // If outdoor time is significant, create and save the record
                if totalMinutes > 0 {
                     // Use performAndWait to ensure Core Data operations complete before proceeding
                     // and handle potential errors within the block.
                     var saveError: Error? = nil
                     self.context.performAndWait {
                        let newRecord = TimeOutdoorsRecord(context: self.context)
                        newRecord.date = targetDate // Store normalized date
                        newRecord.totalDurationMinutes = totalMinutes
                        newRecord.isUploaded = false
                        newRecord.calculationTimestamp = Date() // Record calculation time

                        do {
                            // Only save if changes were actually made
                            if self.context.hasChanges {
                                try self.context.save()
                                print("Saved TimeOutdoorsRecord for \(targetDate): \(totalMinutes) minutes")
                            }
                        } catch {
                            saveError = error // Capture the error
                            print("Error saving TimeOutdoorsRecord for \(targetDate): \(error)")
                            self.context.rollback() // Rollback changes on error
                        }
                    }
                     // If an error occurred during save, mark the overall process as failed
                     if saveError != nil {
                         overallSuccess = false
                     }

                } else {
                     print("No significant outdoor time calculated for \(targetDate). Not saving.")
                     // Optional: You could create an isUploaded=true record here
                     // if you want to explicitly mark that the day was processed with zero time.
                }
            } // End of loop

            // --- 调用完成回调 ---
            DispatchQueue.main.async { // Switch back to main thread for UI updates if needed
                self.isProcessing = false // Update processing status
                self.lastProcessingMessage = overallSuccess ? "Finished calculating past outdoor times." : "Finished calculating with errors."
                print("processAndStorePastDaysOutdoorsTime completed with success: \(overallSuccess)")
                completion(overallSuccess) // Call the completion handler
            }
        } // End of background dispatch
    }


    /// 触发后台上传未发送的户外时间数据。
    /// (Triggers background upload for unsent outdoor time data.)
    /// - Parameter completion: 上传完成后的回调 (Callback after upload finishes). (Bool: success, String: status message)
    func triggerUploadInBackground(completion: @escaping (Bool, String) -> Void) {
        print("Attempting to trigger background upload for outdoor time...")
        // Check login status first
        // 直接获取 authManager 实例，因为它不是可选的
        let authManager = AppDelegate.shared.authManager

        // 使用 guard 检查 isAuthenticated 这个 Bool 属性
        guard authManager.isAuthenticated else {
            // --- 在这里处理未认证的情况 ---
            let message = "User not authenticated. Cannot upload outdoor time."
            print(message)
            DispatchQueue.main.async {
                // self.lastProcessingMessage = "User not logged in. Upload skipped." // 如果需要更新 UI
            }
            completion(false, message) // 调用回调，告知后台任务失败原因
            return // 从当前函数返回
            // --- 处理结束 ---
        }

        // Update UI status if needed (though less relevant for pure background tasks)
         DispatchQueue.main.async {
             self.lastProcessingMessage = "Starting outdoor time upload..."
             self.isProcessing = true // Reuse the processing flag or add a dedicated one
         }

        // Call the actual upload function, passing the completion handler along
        uploadUnsentTimeOutdoorsData(authManager: authManager) { success, message in
             // This block is already the completion handler for the upload process
             DispatchQueue.main.async { // Ensure UI updates happen on main thread
                 self.isProcessing = false // Update status
                 self.lastProcessingMessage = message // Update message
             }
             print("Background outdoor time upload finished. Success: \(success), Message: \(message)")
             // Directly pass the result to the background task's completion handler
             completion(success, message)
        }
    }

    // --- 保持不变的方法 ---

    // 辅助函数：获取指定日期的记录 (Helper function: fetch record for a specific date)
    private func fetchTimeOutdoorsRecord(for date: Date) -> TimeOutdoorsRecord? {
        let request: NSFetchRequest<TimeOutdoorsRecord> = TimeOutdoorsRecord.fetchRequest()
        let startOfDay = Calendar.current.startOfDay(for: date)
        // Precise date matching
        request.predicate = NSPredicate(format: "date == %@", startOfDay as NSDate)
        request.fetchLimit = 1

        var result: TimeOutdoorsRecord? = nil
        // Use performAndWait to ensure fetch completes before returning
        context.performAndWait {
            do {
                let results = try context.fetch(request)
                result = results.first
            } catch {
                print("Error fetching TimeOutdoorsRecord for date \(date): \(error)")
            }
        }
        return result
    }

    // 上传未发送的数据 (Upload unsent data) - 已包含 completion handler
     private func uploadUnsentTimeOutdoorsData(authManager: AuthManager, completion: @escaping (Bool, String) -> Void) {
          let fetchRequest: NSFetchRequest<TimeOutdoorsRecord> = TimeOutdoorsRecord.fetchRequest()
          fetchRequest.predicate = NSPredicate(format: "isUploaded == NO") // Fetch records where isUploaded is false
          fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \TimeOutdoorsRecord.date, ascending: true)] // Sort by date ascending

          var recordsToUpload: [TimeOutdoorsRecord] = []
          context.performAndWait { // Ensure fetch completes
               do {
                    recordsToUpload = try context.fetch(fetchRequest)
               } catch {
                    // If fetch fails, call completion immediately
                    completion(false, "Error fetching unsent outdoor records: \(error)")
                    return // Exit early from performAndWait block if possible, or let it finish
               }
          }

          // If fetch failed outside performAndWait (which it shouldn't here), completion would have been called.
          // If fetch succeeded but returned error inside, completion called.
          // Now check if recordsToUpload is populated.

          if recordsToUpload.isEmpty {
               completion(true, "No new outdoor time records to upload.")
               return
          }

          print("Found \(recordsToUpload.count) outdoor time records to upload.")

          // --- Prepare data for upload ---
          var payloads: [[String: Any]] = []
          var recordsSuccessfullyPrepared: [TimeOutdoorsRecord] = [] // Track successfully converted records

          for record in recordsToUpload {
               guard let recordDate = record.date else {
                   print("Warning: Skipping record with missing date.")
                   continue
               }

               // Calculate end time: 23:59:59 of the day
               // Use startOfDay for consistency and add almost a full day
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

               // Create JSON Payload according to your requirements
               let durationPayload: [String: Any] = [
                    "value": record.totalDurationMinutes,
                    "unit": "min" // Use minute unit (min)
               ]
               let finalPayload: [String: Any] = [
                    "end_date_time": endDateTimeString,
                    "duration": durationPayload
               ]
               payloads.append(finalPayload)
               recordsSuccessfullyPrepared.append(record) // Record this one as prepared
          }

          if payloads.isEmpty {
               // This could happen if all records had issues (e.g., missing dates)
               completion(false, "Failed to prepare any outdoor records for upload.")
               return
          }
         print("Attempting to upload \(payloads.count) prepared payloads (disguised as Blood Glucose)...")
         JHDataExchangeManager.shared.uploadTimeOutdoorsDisguisedAsBloodGlucose( // <--- 调用新函数
             payloads: payloads,
             authManager: authManager
         ) { success, message in
             if success {
                 // 上传成功，标记记录为已上传 (这一步保持不变)
                 print("Upload successful (as Blood Glucose). Marking records...")
                 self.markRecordsAsUploaded(recordsSuccessfullyPrepared)
                 completion(true, "Successfully uploaded \(recordsSuccessfullyPrepared.count) outdoor time records (as Blood Glucose).")
             } else {
                 // 上传失败
                 print("Upload failed (as Blood Glucose): \(message)")
                 completion(false, "Outdoor time upload failed (as BG): \(message)")
             }
         }
     }
         // --- Call the upload service ---
         // Assuming JHDataExchangeManager has the uploadGenericObservations method as discussed
//          print("Attempting to upload \(payloads.count) prepared payloads.")
//          JHDataExchangeManager.shared.uploadGenericObservations(
//               payloads: payloads,
//               // Define a code for this data type. Make sure this matches server expectations.
//               observationCode: ["system": "http://loinc.org", // Example system, use appropriate one
//                                 "code": "83401-9",        // Example LOINC code for "Time outdoors"
//                                 "display": "Time outdoors"],
//               authManager: authManager
//          ) { success, message in
//               if success {
//                    // Upload successful, mark these records as uploaded
//                    print("Upload successful via JHDataExchangeManager. Marking records...")
//                    self.markRecordsAsUploaded(recordsSuccessfullyPrepared)
//                    completion(true, "Successfully uploaded \(recordsSuccessfullyPrepared.count) outdoor time records.")
//               } else {
//                    // Upload failed
//                    print("Upload failed via JHDataExchangeManager: \(message)")
//                    completion(false, "Outdoor time upload failed: \(message)")
//               }
//          }
//     }

     // 标记记录为已上传 (Mark records as uploaded)
     private func markRecordsAsUploaded(_ records: [TimeOutdoorsRecord]) {
          // Ensure this runs on the correct context and handles potential errors
          context.performAndWait { // Use performAndWait to ensure it completes synchronously relative to caller
              guard !records.isEmpty else { return } // No records to mark

              print("Marking \(records.count) records as uploaded...")
              for record in records {
                   // Check if the record still exists in the context before modifying
                  if context.object(with: record.objectID) == record {
                      record.isUploaded = true
                  } else {
                      print("Warning: Record \(record.objectID) not found in context during marking.")
                  }
              }

              // Only save if changes were actually made
              if context.hasChanges {
                  do {
                      try context.save()
                      print("Successfully marked and saved \(records.count) outdoor records as uploaded.")
                  } catch {
                      print("Error saving context after marking outdoor records as uploaded: \(error)")
                      context.rollback() // Rollback on error
                  }
              } else {
                 print("No changes detected after marking records, skipping save.")
              }
          }
     }

     // --- 前台触发方法（可选，如果UI需要直接调用） ---
     // This method remains largely the same as your original `triggerUpload`
     // It's intended for foreground triggers (e.g., button press)
     // and updates the UI via @Published properties.
     func triggerUploadFromForeground() {
         // 直接获取 authManager 实例，因为它不是可选的
         let authManager = AppDelegate.shared.authManager

         // 使用 guard 检查 isAuthenticated 这个 Bool 属性
         guard authManager.isAuthenticated else {
             // --- 在这里处理未认证的情况 ---
             let message = "User not authenticated. Cannot upload outdoor time."
             print(message)
             DispatchQueue.main.async {
                 // self.lastProcessingMessage = "User not logged in. Upload skipped." // 如果需要更新 UI
             }
             return // 从当前函数返回
             // --- 处理结束 ---
         }
          DispatchQueue.main.async {
              self.lastProcessingMessage = "Starting outdoor time upload..."
              self.isProcessing = true // Update UI state
          }

         // Call the upload function which now has a completion handler
         uploadUnsentTimeOutdoorsData(authManager: authManager) { success, message in
             DispatchQueue.main.async { // Ensure UI updates are on main thread
                 self.isProcessing = false
                 self.lastProcessingMessage = message
                 print("Foreground outdoor time upload result: \(success) - \(message)")
                 // Optionally show an alert or further UI feedback here
             }
         }
     }

} // End of class TimeOutdoorsManager
