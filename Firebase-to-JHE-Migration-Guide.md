# Firebase to JupyterHealth Exchange (JHE) Migration Guide

> **Migration Guide for Spezi-based Applications**  
> *From Firebase Backend to JupyterHealth Exchange Integration*  
> *Based on EHE-Pilot Implementation by Yifei Hu*

## Table of Contents

1. [Overview](#overview)
2. [Architecture Comparison](#architecture-comparison)
3. [Authentication Migration](#authentication-migration)
4. [Data Format Transformation](#data-format-transformation)
5. [Upload Mechanism Changes](#upload-mechanism-changes)
6. [Implementation Guide](#implementation-guide)
7. [Code Examples](#code-examples)
8. [Testing and Deployment](#testing-and-deployment)
9. [Troubleshooting](#troubleshooting)

---

## Overview

This guide provides a comprehensive migration path from Firebase/Firestore backend to JupyterHealth Exchange (JHE) for Spezi-based iOS applications. The migration involves three major components:

1. **Authentication**: OAuth 2.0/OIDC replacing Firebase Auth
2. **Data Format**: Open mHealth (OMH) schemas with FHIR R5 compliance
3. **Upload Mechanism**: RESTful API with FHIR bundles replacing Firestore collections

### Key Benefits of JHE Migration

- **Standards Compliance**: Open mHealth and FHIR standards
- **Research Grade**: Purpose-built for clinical research data
- **Data Portability**: Standardized export formats
- **Advanced Analytics**: Jupyter-based analysis platform

---

## Architecture Comparison

### Current LifeSpace Architecture (Firebase)
```
iOS App → Firebase Auth → Firestore Collections
         ↓
    Real-time Sync → Direct Document Writes
```

### Target Architecture (JHE)
```
iOS App → OAuth 2.0/OIDC → JHE FHIR R5 API
         ↓
    Batch Uploads → OMH + FHIR Bundles → Base64 Encoding
```

### Data Storage Comparison

| Aspect | Firebase (Current) | JHE (Target) |
|--------|-------------------|--------------|
| Auth | Firebase Auth | OAuth 2.0/OIDC |
| Data Format | Custom JSON | OMH + FHIR |
| Storage | Firestore Collections | FHIR Observations |
| Upload | Real-time Documents | Batch FHIR Bundles |
| Encoding | Native JSON | Base64 + JSON |

---

## Authentication Migration

### 1. Dependencies Update

**Remove Firebase Dependencies:**
```swift
// Remove from Package.swift or Xcode
.package(url: "https://github.com/firebase/firebase-ios-sdk", from: "10.0.0")
```

**Add OAuth Dependencies:**
```swift
// Add to Package.swift
.package(url: "https://github.com/openid/AppAuth-iOS", from: "1.6.0")
```

### 2. OAuth 2.0 Configuration

**AuthManager Implementation:**
```swift
import AppAuth

class AuthManager: ObservableObject {
    // OAuth Configuration
    private let issuerURL = URL(string: "https://ehepilot.com/o")!
    private let clientID = "nChhwTBZ4SZJEg0QJftkWDkulGqIkIAsMLqXagFo"
    private let redirectURI = URL(string: "ehepilot://oauth/callback")!
    
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    
    private var authState: OIDAuthState?
    private var serviceConfiguration: OIDServiceConfiguration?
    
    // OIDC Discovery
    func discoverConfiguration(completion: @escaping (Bool) -> Void) {
        let discoveryURL = issuerURL.appendingPathComponent("/.well-known/openid-configuration")
        
        OIDAuthorizationService.discoverConfiguration(forIssuer: issuerURL) { [weak self] configuration, error in
            DispatchQueue.main.async {
                if let config = configuration {
                    self?.serviceConfiguration = config
                    completion(true)
                } else {
                    print("OIDC Discovery failed: \(error?.localizedDescription ?? "Unknown error")")
                    completion(false)
                }
            }
        }
    }
    
    // OAuth Authentication Flow
    func authenticate(completion: @escaping (Bool) -> Void) {
        guard let serviceConfig = serviceConfiguration else {
            completion(false)
            return
        }
        
        // Create authorization request with PKCE
        let request = OIDAuthorizationRequest(
            configuration: serviceConfig,
            clientId: clientID,
            clientSecret: nil,
            scopes: ["openid"],
            redirectURL: redirectURI,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )
        
        // Present authorization flow
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            
            OIDAuthState.authState(
                byPresenting: request,
                presenting: window.rootViewController!
            ) { [weak self] authState, error in
                DispatchQueue.main.async {
                    if let authState = authState {
                        self?.authState = authState
                        self?.accessToken = authState.lastTokenResponse?.accessToken
                        self?.isAuthenticated = true
                        self?.saveTokenToKeychain()
                        completion(true)
                    } else {
                        print("Authorization failed: \(error?.localizedDescription ?? "Unknown error")")
                        completion(false)
                    }
                }
            }
        }
    }
    
    // Secure Token Storage
    private func saveTokenToKeychain() {
        guard let accessToken = accessToken,
              let refreshToken = authState?.refreshToken else { return }
        
        saveToKeychain(token: accessToken, key: "access_token")
        saveToKeychain(token: refreshToken, key: "refresh_token")
    }
    
    private func saveToKeychain(token: String, key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: token.data(using: .utf8)!
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
}
```

### 3. Token Refresh Management

**TokenRefreshManager Implementation:**
```swift
import Foundation
import AppAuth

class TokenRefreshManager {
    private var authManager: AuthManager
    private var refreshTimer: Timer?
    
    init(authManager: AuthManager) {
        self.authManager = authManager
        startTokenRefreshTimer()
    }
    
    private func startTokenRefreshTimer() {
        // Refresh every 6 hours
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task {
                await self.refreshTokenIfNeeded()
            }
        }
    }
    
    private func refreshTokenIfNeeded() async {
        guard let authState = authManager.authState,
              let tokenRequest = authState.lastTokenResponse?.tokenRefreshRequest() else {
            return
        }
        
        return await withCheckedContinuation { continuation in
            OIDAuthorizationService.perform(tokenRequest) { [weak self] tokenResponse, error in
                DispatchQueue.main.async {
                    if let tokenResponse = tokenResponse {
                        self?.authState.update(with: tokenResponse, error: nil)
                        self?.authManager.accessToken = tokenResponse.accessToken
                        self?.authManager.saveTokenToKeychain()
                    }
                    continuation.resume()
                }
            }
        }
    }
}
```

---

## Data Format Transformation

### 1. From Firebase Documents to OMH Schemas

**Firebase LocationDataPoint (Current):**
```swift
struct LocationDataPoint: Codable {
    var currentDate: Date
    var time: TimeInterval
    var latitude: CLLocationDegrees
    var longitude: CLLocationDegrees
    var studyID: String
    var UpdatedBy: String
}
```

**OMH Geoposition Schema (Target):**
```swift
func createOMHGeoposition(from location: CLLocationCoordinate2D, timestamp: Date) -> [String: Any] {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    
    return [
        "latitude": [
            "value": location.latitude,
            "unit": "deg"
        ],
        "longitude": [
            "value": location.longitude,
            "unit": "deg"
        ],
        "positioning_system": "GPS",
        "effective_time_frame": [
            "date_time": isoFormatter.string(from: timestamp)
        ]
    ]
}
```

### 2. OMH Schema Implementations

**Supported OMH Schemas:**

```swift
enum OMHSchema: String {
    case geoposition = "omh:geoposition:1.0"
    case timeInterval = "omh:time-interval:1.0"
    case bloodGlucose = "omh:blood-glucose:4.0"
    case heartRate = "omh:heart-rate:4.0"
    case stepCount = "omh:step-count:4.0"
    case sleepDuration = "omh:sleep-duration:4.0"
    case bloodPressure = "omh:blood-pressure:4.0"
}
```

**Time Interval Schema Example:**
```swift
func createOMHTimeInterval(duration: Int64, endDate: Date) -> [String: Any] {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    isoFormatter.timeZone = TimeZone(secondsFromGMT: 0)
    
    return [
        "end_date_time": isoFormatter.string(from: endDate),
        "duration": [
            "value": duration,
            "unit": "min"
        ]
    ]
}
```

---

## Upload Mechanism Changes

### 1. From Firestore to FHIR Bundles

**Current Firestore Upload:**
```swift
// Firebase approach - direct document write
try await configuration.userDocumentReference
    .collection(Constants.locationDataCollectionName)
    .document(UUID().uuidString)
    .setData(from: dataPoint)
```

**New FHIR Bundle Upload:**
```swift
// JHE approach - FHIR bundle with Base64 encoding
func uploadFHIRBundle(entries: [[String: Any]], completion: @escaping (Bool, String) -> Void) {
    let bundle: [String: Any] = [
        "resourceType": "Bundle",
        "type": "batch",
        "entry": entries
    ]
    
    guard let jsonData = try? JSONSerialization.data(withJSONObject: bundle),
          let fhirURL = URL(string: "\(baseURL)/fhir/r5/") else {
        completion(false, "Invalid bundle or URL")
        return
    }
    
    var request = URLRequest(url: fhirURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = jsonData
    
    URLSession.shared.dataTask(with: request) { data, response, error in
        // Handle response
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 200 {
            completion(true, "Upload successful")
        } else {
            completion(false, "Upload failed")
        }
    }.resume()
}
```

### 2. FHIR Entry Creation

**Location FHIR Observation:**
```swift
func createLocationFHIREntry(location: CLLocationCoordinate2D, timestamp: Date) -> [String: Any] {
    // Create OMH data
    let omhData = createOMHGeoposition(from: location, timestamp: timestamp)
    
    // Base64 encode
    guard let jsonData = try? JSONSerialization.data(withJSONObject: omhData),
          let base64String = jsonData.base64EncodedString() as String? else {
        return [:]
    }
    
    // Create FHIR observation entry
    return [
        "resource": [
            "resourceType": "Observation",
            "status": "final",
            "category": [
                [
                    "coding": [
                        [
                            "system": "http://terminology.hl7.org/CodeSystem/observation-category",
                            "code": "survey",
                            "display": "Survey"
                        ]
                    ]
                ]
            ],
            "code": [
                "coding": [
                    [
                        "system": "https://w3id.org/openmhealth",
                        "code": "omh:geoposition:1.0",
                        "display": "Geoposition"
                    ]
                ]
            ],
            "subject": [
                "reference": "Patient/40001"
            ],
            "device": [
                "reference": "Device/70001"
            ],
            "effectiveDateTime": ISO8601DateFormatter().string(from: timestamp),
            "valueAttachment": [
                "contentType": "application/json",
                "data": base64String
            ],
            "identifier": [
                [
                    "value": UUID().uuidString,
                    "system": "https://ehr.example.com"
                ]
            ]
        ],
        "request": [
            "method": "POST",
            "url": "Observation"
        ]
    ]
}
```

---

## Implementation Guide

### Step 1: Update Dependencies

**Package.swift Changes:**
```swift
// Remove Firebase
// .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "10.0.0")

// Add OAuth
.package(url: "https://github.com/openid/AppAuth-iOS", from: "1.6.0")
```

### Step 2: Create New Service Layer

**FHIRUploadService.swift:**
```swift
import Foundation
import AppAuth

class FHIRUploadService: ObservableObject {
    private let authManager: AuthManager
    private let baseURL: String
    
    // Configuration
    private let patientId = "40001"
    private let deviceId = "70001"
    private let organizationId = "20012"
    private let studyId = "30001"
    
    init(authManager: AuthManager, baseURL: String = "https://ehepilot.com") {
        self.authManager = authManager
        self.baseURL = baseURL
    }
    
    func uploadLocationData(_ locations: [CLLocationCoordinate2D], completion: @escaping (Bool, String) -> Void) {
        guard authManager.isAuthenticated,
              let accessToken = authManager.accessToken else {
            completion(false, "Not authenticated")
            return
        }
        
        let entries = locations.map { location in
            createLocationFHIREntry(location: location, timestamp: Date())
        }
        
        uploadFHIRBundle(entries: entries, accessToken: accessToken, completion: completion)
    }
    
    // Additional upload methods for surveys, health data, etc.
}
```

### Step 3: Update LifeSpaceStandard

**Modified LifeSpaceStandard.swift:**
```swift
// Replace Firebase dependencies
class LifeSpaceStandard: Standard, LifeSpaceStandardProtocol, ObservableObject {
    private let authManager: AuthManager
    private let fhirService: FHIRUploadService
    
    init() {
        self.authManager = AuthManager()
        self.fhirService = FHIRUploadService(authManager: authManager)
    }
    
    // Updated location upload
    func add(location: CLLocationCoordinate2D) async throws {
        return await withCheckedContinuation { continuation in
            fhirService.uploadLocationData([location]) { success, message in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: LifeSpaceStandardError.uploadFailed(message))
                }
            }
        }
    }
    
    // Similar updates for surveys and health data
}
```

### Step 4: Update App Configuration

**Info.plist Updates:**
```xml
<!-- Add OAuth redirect scheme -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>OAuth Callback</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>lifespace</string>
        </array>
    </dict>
</array>

<!-- Background processing capabilities -->
<key>UIBackgroundModes</key>
<array>
    <string>background-processing</string>
    <string>background-fetch</string>
</array>
```

---

## Testing and Deployment

### 1. Testing Strategy

**Unit Tests for Data Transformation:**
```swift
import XCTest

class OMHDataTransformTests: XCTestCase {
    func testGeopositionCreation() {
        let location = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let timestamp = Date()
        
        let omhData = createOMHGeoposition(from: location, timestamp: timestamp)
        
        XCTAssertEqual(omhData["positioning_system"] as? String, "GPS")
        XCTAssertNotNil(omhData["latitude"])
        XCTAssertNotNil(omhData["longitude"])
    }
    
    func testFHIRBundleCreation() {
        let entries = [createLocationFHIREntry(location: testLocation, timestamp: Date())]
        let bundle = createFHIRBundle(entries: entries)
        
        XCTAssertEqual(bundle["resourceType"] as? String, "Bundle")
        XCTAssertEqual(bundle["type"] as? String, "batch")
    }
}
```

### 2. Migration Testing

**Test with Both Backends:**
```swift
class MigrationTestManager {
    private let firebaseStandard: LifeSpaceStandardFirebase
    private let jheStandard: LifeSpaceStandardJHE
    
    func testDataConsistency() async {
        let testLocation = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        
        // Upload to both systems
        try await firebaseStandard.add(location: testLocation)
        try await jheStandard.add(location: testLocation)
        
        // Verify data integrity
        // Compare timestamps, coordinate precision, etc.
    }
}
```

---

## Troubleshooting

### Common Issues and Solutions

**1. OAuth Authentication Failures**
```swift
// Debug OIDC discovery
func debugOIDCConfiguration() {
    OIDAuthorizationService.discoverConfiguration(forIssuer: issuerURL) { config, error in
        if let error = error {
            print("OIDC Discovery Error: \(error)")
        } else {
            print("Authorization Endpoint: \(config?.authorizationEndpoint)")
            print("Token Endpoint: \(config?.tokenEndpoint)")
        }
    }
}
```

**2. Base64 Encoding Issues**
```swift
// Verify Base64 encoding
func verifyBase64Encoding(data: [String: Any]) -> Bool {
    guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
          let base64String = jsonData.base64EncodedString() as String?,
          let decodedData = Data(base64Encoded: base64String),
          let decodedJSON = try? JSONSerialization.jsonObject(with: decodedData) else {
        return false
    }
    
    print("Original: \(data)")
    print("Decoded: \(decodedJSON)")
    return true
}
```

**3. FHIR Bundle Validation**
```swift
// Validate FHIR bundle structure
func validateFHIRBundle(_ bundle: [String: Any]) -> [String] {
    var errors: [String] = []
    
    if bundle["resourceType"] as? String != "Bundle" {
        errors.append("Missing or invalid resourceType")
    }
    
    if bundle["type"] as? String != "batch" {
        errors.append("Bundle type must be 'batch'")
    }
    
    guard let entries = bundle["entry"] as? [[String: Any]] else {
        errors.append("Missing entries array")
        return errors
    }
    
    for (index, entry) in entries.enumerated() {
        if let resource = entry["resource"] as? [String: Any] {
            if resource["resourceType"] as? String != "Observation" {
                errors.append("Entry \(index): Invalid resourceType")
            }
        }
    }
    
    return errors
}
```

### Performance Optimization

**Batch Upload Strategy:**
```swift
class BatchUploadManager {
    private var pendingUploads: [FHIREntry] = []
    private let batchSize = 10
    private let uploadInterval: TimeInterval = 30
    
    func queueUpload(_ entry: FHIREntry) {
        pendingUploads.append(entry)
        
        if pendingUploads.count >= batchSize {
            processBatch()
        }
    }
    
    private func processBatch() {
        let batch = Array(pendingUploads.prefix(batchSize))
        pendingUploads.removeFirst(batch.count)
        
        // Upload batch to JHE
        fhirService.uploadBatch(batch) { success, error in
            if !success {
                // Handle retry logic
                self.handleUploadFailure(batch, error: error)
            }
        }
    }
}
```

---

## Configuration Reference

### JHE Endpoints
- **OAuth Issuer**: `https://ehepilot.com/o`
- **FHIR R5 API**: `https://ehepilot.com/fhir/r5/`
- **OIDC Discovery**: `https://ehepilot.com/o/.well-known/openid-configuration`

### Default Entity IDs
- **Patient ID**: 40001 (Stella Park)
- **Device ID**: 70001
- **Organization ID**: 20012 (JH Data Exchange)
- **Study ID**: 30001 (Spezi)

### OAuth Configuration
- **Client ID**: `nChhwTBZ4SZJEg0QJftkWDkulGqIkIAsMLqXagFo`
- **Redirect URI**: `lifespace://oauth/callback`
- **Scopes**: `openid`
- **Response Type**: `code`
- **PKCE**: Required

---

## Conclusion

This migration guide provides a complete roadmap for transitioning from Firebase to JupyterHealth Exchange. The key benefits include:

- **Standards Compliance**: Full OMH and FHIR compatibility
- **Research Integration**: Direct integration with Jupyter analytics
- **Enterprise Security**: OAuth 2.0/OIDC with secure token management
- **Data Portability**: Standardized export formats

For additional support or questions about specific implementation details, please refer to the EHE-Pilot project source code or contact the development team.

### Next Steps

1. Review the complete EHE-Pilot source code at `/Users/yifei.hu/NoUpdate/Swift_Project/EHE-Pilot`
2. Test authentication flow with JHE development environment
3. Implement data transformation layer
4. Validate OMH schema compliance
5. Deploy and monitor upload success rates

---
*Guide prepared by: Yifei Hu*  
*Last updated: September 2024*  
*Version: 1.0*