//
//  LocationPin.swift
//  EHE-Pilot
//
//  Created by 胡逸飞 on 2024/12/1.
//


import CoreLocation

struct LocationPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}