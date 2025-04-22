//
//  CSVExporter.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/7.
// Updated on 2025/04/22 for cumulative daily times.
//

import Foundation
import CoreData
import CoreLocation

class CSVExporter {

    /// Exports all LocationRecord data, including cumulative daily Time Away and Time Outdoors.
    static func exportAllRecords(context: NSManagedObjectContext) throws -> Data {

        // 1. Fetch all LocationRecord data, sorted by timestamp ascending
        let fetchRequest: NSFetchRequest<LocationRecord> = LocationRecord.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \LocationRecord.timestamp, ascending: true)]

        let allRecords: [LocationRecord]
        do {
            allRecords = try context.fetch(fetchRequest)
            print("Fetched \(allRecords.count) total records for CSV export.")
            if allRecords.isEmpty {
                 print("No records to export.")
                 // Return data for an empty CSV with just the header
                 let emptyHeader = "Timestamp,Latitude,Longitude,Accuracy,IsAwayFromHome,IsOutdoors,CumulativeTimeAwayHome(minutes),CumulativeTimeOutdoors(minutes)\n"
                 return emptyHeader.data(using: .utf8) ?? Data()
            }
        } catch {
            print("Error fetching records for CSV export: \(error)")
            throw error
        }

        // 2. Group records by day (Start of Day)
        let groupedByDay = Dictionary(grouping: allRecords) { record -> Date in
            guard let timestamp = record.timestamp else {
                // Handle records with nil timestamp if necessary, maybe group them separately
                // For simplicity, we'll use a far past date as the key
                return Date.distantPast
            }
            return Calendar.current.startOfDay(for: timestamp)
        }
        print("Grouped records into \(groupedByDay.count) days.")


        // 3. Define CSV Header
        var csvString = "Timestamp,Latitude,Longitude,Accuracy,IsAwayFromHome,IsOutdoors,CumulativeTimeAwayHome(minutes),CumulativeTimeOutdoors(minutes)\n"

        // 4. Prepare Date Formatter
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC 'Z'

        // 5. Process records day by day
        // Sort the days chronologically
        let sortedDays = groupedByDay.keys.sorted()

        for dayStartDate in sortedDays {
            guard let recordsForDay = groupedByDay[dayStartDate], !recordsForDay.isEmpty else { continue }
             print("Processing \(recordsForDay.count) records for day starting \(dayStartDate)...")

            // Initialize cumulative times for the day
            var cumulativeTimeAway: TimeInterval = 0
            var cumulativeTimeOutdoors: TimeInterval = 0

            // Iterate through records within the day
            for (index, currentRecord) in recordsForDay.enumerated() {

                var intervalDuration: TimeInterval = 0
                var previousIsHome: Bool = false // Default to 'at home' at start of day / interval
                var previousIsOutdoors: Bool = false // Default to 'not outdoors' at start of day / interval

                // Determine the start of the interval and the state during the previous interval
                if index == 0 {
                    // For the first record, the interval starts from the beginning of the day
                    // The 'previous' state doesn't really apply for accumulation *before* this record.
                    // We calculate status *for* this record, and accumulation starts *after* it.
                    // So, cumulative times for the *first* record's row will be 0.
                     intervalDuration = 0 // No duration *before* the first point to accumulate

                } else {
                    // For subsequent records, calculate interval from the previous record
                    let previousRecord = recordsForDay[index - 1]
                    if let currentTimestamp = currentRecord.timestamp, let previousTimestamp = previousRecord.timestamp {
                        intervalDuration = currentTimestamp.timeIntervalSince(previousTimestamp)
                        if intervalDuration < 0 { intervalDuration = 0 } // Avoid negative duration

                        // Determine the state *during* the interval (based on the previous record)
                        previousIsHome = previousRecord.isHome
                        let prevAccuracy = previousRecord.gpsAccuracy?.doubleValue ?? 100.0
                        previousIsOutdoors = !previousIsHome && (previousRecord.gpsAccuracy == nil || prevAccuracy < 10.0) // Same logic as below

                    } else {
                         intervalDuration = 0 // Cannot calculate duration if timestamps are missing
                    }
                }

                // Accumulate time based on the *previous* interval's state
                if !previousIsHome { // If was away during the previous interval
                    cumulativeTimeAway += intervalDuration
                }
                if previousIsOutdoors { // If was outdoors during the previous interval
                    cumulativeTimeOutdoors += intervalDuration
                }


                // --- Format data for the *current* record ---

                let timestamp = currentRecord.timestamp != nil ? dateFormatter.string(from: currentRecord.timestamp!) : "N/A"
                let lat = String(currentRecord.latitude)
                let lon = String(currentRecord.longitude)

                let accuracy: String
                if let acc = currentRecord.gpsAccuracy?.doubleValue {
                    accuracy = String(format: "%.1f", acc)
                } else {
                    accuracy = "N/A"
                }

                // Status for the current record
                let currentIsAway = !currentRecord.isHome ? "1" : "0"
                let currentAccuracyValue = currentRecord.gpsAccuracy?.doubleValue ?? 100.0
                let currentIsOutdoorsCondition = !currentRecord.isHome && (currentRecord.gpsAccuracy == nil || currentAccuracyValue < 10.0)
                let currentIsOutdoors = currentIsOutdoorsCondition ? "1" : "0"

                // Cumulative times *up to this point* (in minutes, rounded)
                let cumulativeAwayMinutes = Int(round(cumulativeTimeAway / 60.0))
                let cumulativeOutdoorsMinutes = Int(round(cumulativeTimeOutdoors / 60.0))

                // Append row to CSV
                csvString += "\(timestamp),\(lat),\(lon),\(accuracy),\(currentIsAway),\(currentIsOutdoors),\(cumulativeAwayMinutes),\(cumulativeOutdoorsMinutes)\n"

            } // End loop through records for the day
        } // End loop through days

        // 6. Convert final CSV string to UTF-8 Data
        guard let data = csvString.data(using: .utf8) else {
            print("Error: Failed to encode final CSV string to UTF-8 data.")
            throw NSError(domain: "CSVExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode CSV string to UTF-8 data"])
        }

        print("CSV data successfully generated with cumulative times.")
        return data
    }
}
