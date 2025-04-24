//
//  Extension.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//

import Foundation

extension Calendar {
    
    func endOfDay(for date: Date) -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        let startOfDay = self.startOfDay(for: date)  // 直接使用系统的 startOfDay
        return self.date(byAdding: components, to: startOfDay) ?? date
    }
}
