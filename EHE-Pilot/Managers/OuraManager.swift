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
            DispatchQueue.main.async {
                if let error = error {
                    print("Notification permission error: \(error)")
                    return
                }

                if granted {
                    print("Notification permission granted")
                } else {
                    print("Notification permission denied")
                    // If permission was denied, disable the reminder
                    self.isReminderEnabled = false
                }
            }
        }
    }

    private func scheduleNotification() {
        cancelNotification() // Cancel existing notification first

        // Check if we have permission before scheduling
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                guard settings.authorizationStatus == .authorized else {
                    print("Cannot schedule notification: permission not granted")
                    self.isReminderEnabled = false
                    return
                }

                let content = UNMutableNotificationContent()
                content.title = "Oura Data Sync Reminder"
                content.body = "Don't forget to sync your Oura ring data today!"
                content.sound = .default

                let calendar = Calendar.current
                let components = calendar.dateComponents([.hour, .minute], from: self.reminderTime)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

                let request = UNNotificationRequest(identifier: self.notificationIdentifier, content: content, trigger: trigger)

                UNUserNotificationCenter.current().add(request) { error in
                    if let error = error {
                        print("Error scheduling notification: \(error)")
                        DispatchQueue.main.async {
                            self.isReminderEnabled = false
                        }
                    } else {
                        print("Notification scheduled successfully for \(String(describing: components.hour)):\(String(describing: components.minute))")
                    }
                }
            }
        }
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }

    // MARK: - Deep Link to Oura App
    func openOuraApp() {
        print("openOuraApp called")
        // Try to open Oura app with URL scheme
        if let url = URL(string: "oura://") {
            print("Checking if Oura app can be opened with URL: \(url)")
            if UIApplication.shared.canOpenURL(url) {
                print("Oura app detected, opening...")
                UIApplication.shared.open(url, options: [:]) { success in
                    print("Opening Oura app result: \(success)")
                }
            } else {
                print("Oura app not installed, opening App Store...")
                // If Oura app is not installed, open App Store
                openOuraInAppStore()
            }
        } else {
            print("Failed to create Oura URL")
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

    func sendTestNotification() {
        // First check permission status
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("Notification Settings:")
            print("Authorization Status: \(settings.authorizationStatus.rawValue)")
            print("Alert Setting: \(settings.alertSetting.rawValue)")
            print("Badge Setting: \(settings.badgeSetting.rawValue)")
            print("Sound Setting: \(settings.soundSetting.rawValue)")

            switch settings.authorizationStatus {
            case .notDetermined:
                print("Notification permission not determined, requesting...")
                self.requestNotificationPermission()
                return
            case .denied:
                print("Notification permission denied by user")
                return
            case .authorized, .provisional:
                print("Notification permission granted, scheduling test notification...")
            case .ephemeral:
                print("Notification permission is ephemeral")
            @unknown default:
                print("Unknown notification permission status")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Test Notification"
            content.body = "This is a test notification for Oura sync reminder. If you see this, notifications are working!"
            content.sound = .default
            content.badge = 1

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            let request = UNNotificationRequest(identifier: "oura_test_notification_\(Date().timeIntervalSince1970)", content: content, trigger: trigger)

            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error sending test notification: \(error)")
                    print("Error details: \(error.localizedDescription)")
                } else {
                    print("Test notification scheduled successfully - should appear in 2 seconds")
                }
            }
        }
    }

    func checkNotificationPermission(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .authorized)
            }
        }
    }
}