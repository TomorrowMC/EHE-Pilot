//
//  CSVExporter.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//

import Foundation
import CoreData

class CSVExporter {
    static func exportAllRecords(context: NSManagedObjectContext) throws -> Data {
        let fetchRequest: NSFetchRequest<LocationRecord> = LocationRecord.fetchRequest()
        let records = try context.fetch(fetchRequest)
        
        // CSV Header
        var csvString = "timestamp,latitude,longitude,isHome\n"
        
        let dateFormatter = ISO8601DateFormatter()
        
        for record in records {
            let timestamp = record.timestamp != nil ? dateFormatter.string(from: record.timestamp!) : ""
            let lat = record.latitude
            let lon = record.longitude
            let isHomeVal = record.isHome ? "1" : "0"
            csvString += "\(timestamp),\(lat),\(lon),\(isHomeVal)\n"
        }
        
        // 转换为UTF8数据
        guard let data = csvString.data(using: .utf8) else {
            throw NSError(domain: "CSVExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode CSV data"])
        }
        
        return data
    }
}
