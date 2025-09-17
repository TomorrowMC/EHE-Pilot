//
//  OuraDailyReminderView.swift
//  EHE-Pilot
//
//  Created by Assistant on 9/17/25.
//

import SwiftUI

struct OuraDailyReminderView: View {
    @Binding var isPresented: Bool
    let onOpenOura: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    onIgnore()
                }

            VStack(spacing: 20) {
                // Header with icon
                VStack(spacing: 12) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)

                    Text("Oura Data Sync Reminder")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                }

                // Body text
                VStack(spacing: 8) {
                    Text("Don't forget to sync your Oura ring data today!")
                        .font(.body)
                        .multilineTextAlignment(.center)

                    Text("Regular syncing helps keep your health metrics up to date.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Action buttons
                VStack(spacing: 12) {
                    // Open Oura App button
                    Button(action: {
                        onOpenOura()
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "arrow.up.right.square.fill")
                                .font(.system(size: 16))
                            Text("Open Oura App")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }

                    // Ignore button
                    Button(action: {
                        onIgnore()
                        isPresented = false
                    }) {
                        Text("Ignore for Now")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(UIColor.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                    }
                }
            }
            .padding(24)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
            .padding(.horizontal, 32)
        }
    }
}

struct OuraDailyReminderView_Previews: PreviewProvider {
    static var previews: some View {
        OuraDailyReminderView(
            isPresented: .constant(true),
            onOpenOura: {},
            onIgnore: {}
        )
    }
}