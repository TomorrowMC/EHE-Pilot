//
//  OuraManager.swift
//  EHE-Pilot
//
//  Created by Assistant on 9/17/25.
//

import SwiftUI
import UserNotifications
import UIKit

class OuraManager: ObservableObject {
    static let shared = OuraManager()

    @Published var isReminderEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isReminderEnabled, forKey: "ouraReminderEnabled")
            if isReminderEnabled {
                scheduleNotification()
            } else {
                cancelNotification()
            }
        }
    }

    @Published var reminderTime: Date {
        didSet {
            UserDefaults.standard.set(reminderTime, forKey: "ouraReminderTime")
            if isReminderEnabled {
                scheduleNotification()
            }
        }
    }

    @Published var shouldShowDailyReminder: Bool = false

    private let notificationIdentifier = "oura_daily_reminder"
    private let lastOpenDateKey = "lastAppOpenDate"

    private init() {
        self.isReminderEnabled = UserDefaults.standard.bool(forKey: "ouraReminderEnabled")

        // Default reminder time is 9:00 AM
        if let savedTime = UserDefaults.standard.object(forKey: "ouraReminderTime") as? Date {
            self.reminderTime = savedTime
        } else {
            let calendar = Calendar.current
            let components = DateComponents(hour: 9, minute: 0)
            self.reminderTime = calendar.date(from: components) ?? Date()
        }
    }

    // MARK: - Daily First Open Detection
    func checkDailyFirstOpen() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastOpenDate = UserDefaults.standard.object(forKey: lastOpenDateKey) as? Date

        var shouldShow = false

        if let lastOpen = lastOpenDate {
            let lastOpenDay = Calendar.current.startOfDay(for: lastOpen)
            // If it's a new day and reminder is enabled
            shouldShow = (today > lastOpenDay) && isReminderEnabled
        } else {
            // First time opening the app
            shouldShow = isReminderEnabled
        }

        UserDefaults.standard.set(Date(), forKey: lastOpenDateKey)

        if shouldShow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.shouldShowDailyReminder = true
            }
        }
    }

    // MARK: - Notification Management
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }

    private func scheduleNotification() {
        cancelNotification() // Cancel existing notification first

        let content = UNMutableNotificationContent()
        content.title = "Oura Data Sync Reminder"
        content.body = "Don't forget to sync your Oura ring data today!"
        content.sound = .default

        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: reminderTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }

    // MARK: - Deep Link to Oura App
    func openOuraApp() {
        // Try to open Oura app with URL scheme
        if let url = URL(string: "oura://") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            } else {
                // If Oura app is not installed, open App Store
                openOuraInAppStore()
            }
        }
    }

    private func openOuraInAppStore() {
        if let url = URL(string: "https://apps.apple.com/app/id1043837948") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    // MARK: - Test Functions
    func triggerTestReminder() {
        shouldShowDailyReminder = true
    }
}