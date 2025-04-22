//
//  StatisticsCalculator.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 4/21/25.
//


// StatisticsCalculator.swift
import Foundation
import CoreData

class StatisticsCalculator {

    // 计算指定日期的户外时间 (Calculate Time Outdoors for a specific date)
    static func calculateTimeOutdoors(for date: Date, using context: NSManagedObjectContext) -> TimeInterval {
        let start = Calendar.current.startOfDay(for: date)
        // 注意：结束时间应为第二天的开始，以便查询包含整天的数据
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else {
            print("Error calculating end of day for \(date)")
            return 0
        }

        // 获取当天的 LocationRecord 数据
        let request: NSFetchRequest<LocationRecord> = LocationRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \LocationRecord.timestamp, ascending: true)]
        // 查询条件应为 >= start AND < end，覆盖整天24小时
        request.predicate = NSPredicate(format: "timestamp >= %@ AND timestamp < %@", start as NSDate, end as NSDate)

        var records: [LocationRecord] = []
        do {
            records = try context.fetch(request)
        } catch {
            print("Error fetching records for date \(date): \(error)")
            return 0
        }

        // --- 复用 StatisticsView 中的计算逻辑 ---
        var timeOutdoors: TimeInterval = 0
        var lastOutdoorsTime: Date?
        var hasIndoorRecord = false // 用于处理全天在户外或没有室内记录的情况

        let calculationEndTime = end // 使用当天的结束时间作为计算终点

        // 如果当天没有记录，则户外时间为0
        guard !records.isEmpty else { return 0 }

        for location in records {
             // 判断是否为户外: 不在家且GPS精度良好或未知 (认为未知时可能在户外)
            // 注意：这里的逻辑要和你 StatisticsView 中的保持一致
            let isOutdoors = !location.isHome && (location.gpsAccuracy == nil || location.gpsAccuracy!.doubleValue < 4.0) // 假设小于4米算户外

            if isOutdoors {
                if lastOutdoorsTime == nil, let currentTimestamp = location.timestamp {
                    lastOutdoorsTime = currentTimestamp // 标记户外时段开始
                }
            } else {
                // 如果当前是室内或其他非户外状态
                hasIndoorRecord = true // 标记当天至少有一次非户外记录
                if let last = lastOutdoorsTime, let currentTimestamp = location.timestamp {
                    // 结算上一个户外时段
                    timeOutdoors += currentTimestamp.timeIntervalSince(last)
                    lastOutdoorsTime = nil // 重置户外开始时间
                }
            }
        }

        // 处理最后一段记录是 Outdoors 的情况
        if let last = lastOutdoorsTime {
            timeOutdoors += calculationEndTime.timeIntervalSince(last)
        }

        // 处理全天都在户外的情况 (没有 indoor/home 记录)
        // 如果没有任何非户外记录，且有记录存在，则认为从第一条记录开始到当天结束都在户外
        if !hasIndoorRecord, let firstRecord = records.first, let firstTimestamp = firstRecord.timestamp {
             timeOutdoors = calculationEndTime.timeIntervalSince(firstTimestamp)
        }
        // --- 计算逻辑结束 ---

        return max(0, timeOutdoors) // 确保时间不为负
    }
}