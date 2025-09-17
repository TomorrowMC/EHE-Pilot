//
//  OuraReminderSettingsView.swift
//  EHE-Pilot
//
//  Created by Assistant on 9/17/25.
//

import SwiftUI

struct OuraReminderSettingsView: View {
    @StateObject private var ouraManager = OuraManager.shared
    @State private var showingPermissionAlert = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Daily Reminder Settings")) {
                    Toggle("Enable Daily Reminder", isOn: $ouraManager.isReminderEnabled)
                        .onChange(of: ouraManager.isReminderEnabled) { isEnabled in
                            if isEnabled {
                                ouraManager.requestNotificationPermission()
                            }
                        }

                    if ouraManager.isReminderEnabled {
                        HStack {
                            Text("Reminder Time")
                            Spacer()
                            DatePicker("", selection: $ouraManager.reminderTime, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                }

                Section(header: Text("How it Works")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Image(systemName: "bell.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                                .padding(.top, 2)
                            Text("Daily notifications at your chosen time")
                                .font(.subheadline)
                        }

                        HStack(alignment: .top) {
                            Image(systemName: "app.badge")
                                .foregroundColor(.green)
                                .font(.caption)
                                .padding(.top, 2)
                            Text("Daily reminder popup on first app open")
                                .font(.subheadline)
                        }

                        HStack(alignment: .top) {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundColor(.orange)
                                .font(.caption)
                                .padding(.top, 2)
                            Text("Quick access to open Oura app")
                                .font(.subheadline)
                        }
                    }
                    .foregroundColor(.secondary)
                }

                Section(header: Text("About Oura")) {
                    Text("Oura is a health tracking ring that monitors your sleep, activity, and recovery. Regular data syncing helps ensure your health metrics are up to date.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Oura Sync Reminder")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct OuraReminderSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        OuraReminderSettingsView()
    }
}