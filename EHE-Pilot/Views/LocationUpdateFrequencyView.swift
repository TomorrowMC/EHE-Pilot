//
//  LocationUpdateFrequencyView.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//


import SwiftUI

struct LocationUpdateFrequencyView: View {
    @AppStorage("locationUpdateFrequency") private var updateFrequency: TimeInterval = 600 // Default 10 minutes
    
    let frequencies: [(String, TimeInterval)] = [
        ("5 minutes", 300),
        ("10 minutes", 600),
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("1 hour", 3600)
    ]
    
    var body: some View {
        Form {
            Section(header: Text("Update Frequency")) {
                ForEach(frequencies, id: \.1) { frequency in
                    HStack {
                        Text(frequency.0)
                        Spacer()
                        if updateFrequency == frequency.1 {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        updateFrequency = frequency.1
                        NotificationCenter.default.post(
                            name: NSNotification.Name("LocationUpdateFrequencyChanged"),
                            object: nil,
                            userInfo: ["frequency": frequency.1]
                        )
                    }
                }
            }
            
            Section(footer: Text("More frequent updates will use more battery power")) {
                EmptyView()
            }
        }
        .navigationTitle("Update Frequency")
    }
}