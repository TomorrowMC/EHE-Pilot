import SwiftUI
import CoreData

struct StatisticsView: View {
    @FetchRequest(
        entity: LocationRecord.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \LocationRecord.timestamp, ascending: true)],
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
                if let last = lastHomeTime {
                    timeAway += location.timestamp.timeIntervalSince(last)
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
    
    var body: some View {
        List {
            Section(header: Text("Today's Statistics")) {
                HStack {
                    Text("Time Away")
                    Spacer()
                    Text(formatTimeInterval(totalTimeAway))
                }
                
                HStack {
                    Text("Location Points")
                    Spacer()
                    Text("\(todayLocations.count)")
                }
                
                if let lastLocation = todayLocations.last {
                    HStack {
                        Text("Current Status")
                        Spacer()
                        Text(lastLocation.isHome ? "At Home" : "Away")
                            .foregroundColor(lastLocation.isHome ? .green : .orange)
                    }
                }
            }
        }
        .navigationTitle("Statistics")
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) / 60 % 60
        return String(format: "%dh %dm", hours, minutes)
    }
}