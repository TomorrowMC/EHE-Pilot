//
//  SampleLocationGenerator.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2025/3/13.
//


import Foundation
import CoreData

class SampleLocationGenerator {
    static let shared = SampleLocationGenerator()
    
    private init() {}
    
    // 生成随机位置记录
    func generateSampleLocationRecords(count: Int = 10) {
        let context = PersistenceController.shared.container.viewContext
        
        // 北京附近的经纬度范围
        let latitudeRange = (39.8...40.1)
        let longitudeRange = (116.2...116.5)
        
        // 开始时间
        let startTime = Date().addingTimeInterval(-3600 * 24) // 从一天前开始
        
        for i in 0..<count {
            let record = LocationRecord(context: context)
            
            // 设置随机经纬度
            record.latitude = Double.random(in: latitudeRange)
            record.longitude = Double.random(in: longitudeRange)
            
            // GPS精度 (1-15米)
            record.gpsAccuracy = NSNumber(value: Double.random(in: 1...15))
            
            // 随机时间戳 (过去24小时内)
            let timeOffset = TimeInterval(-3600 * 24) + TimeInterval(i) * (3600 * 24 / TimeInterval(count))
            record.timestamp = Date().addingTimeInterval(timeOffset)
            
            // 是否在家 (大约50%的几率)
            record.isHome = Bool.random()
            
            // 未上传状态
            record.ifUpdated = false
        }
        
        // 保存上下文
        do {
            try context.save()
            print("成功生成 \(count) 条示例位置记录")
        } catch {
            print("生成示例位置记录时出错: \(error)")
        }
    }
    
    // 清除所有位置记录
    func clearAllLocationRecords() {
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = LocationRecord.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        do {
            try context.execute(deleteRequest)
            try context.save()
            print("成功清除所有位置记录")
        } catch {
            print("清除位置记录时出错: \(error)")
        }
    }
}