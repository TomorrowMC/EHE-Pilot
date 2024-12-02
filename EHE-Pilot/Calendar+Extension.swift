//
//  Extension.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//

import Foundation

extension Calendar {
    // 移除这个方法，因为 Calendar 已经有了 startOfDay 方法
    // 我们不需要重新实现它
    
    func endOfDay(for date: Date) -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        let startOfDay = self.startOfDay(for: date)  // 直接使用系统的 startOfDay
        return self.date(byAdding: components, to: startOfDay) ?? date
    }
}
