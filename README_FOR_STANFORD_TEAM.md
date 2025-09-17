# Guide: Integrating a Spezi App with JupyterHealth Exchange (JHE)

Hi Vishnu and Sylvie,

It's great to connect with you! I'm excited to help your team with the JHE integration for the upcoming hackathon. Based on the work I did for the EHE-Pilot app, I've created this guide to walk you through the process of connecting your Spezi-based app to the JHE backend.

The core workflow can be broken down into three main parts:
1.  **Authentication**: Authenticating with the JHE server to get access tokens.
2.  **Data Formatting**: Encoding your app's data into the required format.
3.  **Data Upload**: Uploading the formatted data to the JHE's FHIR endpoint.

I'll provide Swift code examples for each step that you can adapt for your `LifeSpace` project.

---

## Part 1: Authentication

JHE uses OAuth 2.0 for authentication. While a full web-based login is possible, the most straightforward approach for your use case (and for the hackathon) is to use a pre-generated **Authorization Code**. This code can be shared via a link or QR code and used directly in the app to get tokens.

### 1.1. Key Configuration

First, you'll need to configure the connection details.

```swift
// Configuration for JHE Authentication
let issuerURL = URL(string: "https://ehepilot.com/o")!
let clientID = "nChhwTBZ4SZJEg0QJftkWDkulGqIkIAsMLqXagFo" // This is a public client ID
let redirectURI = "ehepilot://oauth/callback" // This might be needed even for code exchange
```

### 1.2. Exchanging the Authorization Code for Tokens

Here is a function that takes an authorization code and exchanges it for an access token and a refresh token. The server response will contain the tokens which you need to save securely.

```swift
import Foundation

/// Exchanges an authorization code for access and refresh tokens.
///
/// - Parameters:
///   - code: The authorization code obtained from an invitation link or QR code.
///   - completion: A closure that returns true on success, false on failure.
func exchangeCodeForToken(code: String, completion: @escaping (Bool) -> Void) {
    let tokenEndpoint = issuerURL.appendingPathComponent("token") // Usually discovered, but can be hardcoded
    
    // The "code_verifier" is part of the PKCE security protocol.
    // For this simplified flow, a static one is used.
    let staticCodeVerifier = "f28984eaebcf41d881223399fc8eab27eaa374a9a8134eb3a900a3b7c0e6feab5b427479f3284ebe9c15b698849b0de2"

    let parameters: [String: String] = [
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": redirectURI,
        "client_id": clientID,
        "code_verifier": staticCodeVerifier
    ]

    var request = URLRequest(url: tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    
    let formString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
    request.httpBody = formString.data(using: .utf8)

    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        guard let data = data,
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("Error: Failed to exchange code for token.")
            completion(false)
            return
        }

        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? TimeInterval else {
            print("Error: Token response is missing required fields.")
            completion(false)
            return
        }

        // IMPORTANT: Save the tokens securely!
        print("Successfully received tokens. Saving to Keychain...")
        saveTokensToKeychain(accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
        
        DispatchQueue.main.async {
            completion(true)
        }
    }
    task.resume()
}
```

### 1.3. Secure Token Storage & Refresh

You **must** store these tokens securely. The iOS Keychain is the standard place for this. You also need to handle token expiration and refreshing.

```swift
import Security

// --- Token Storage (Example using Keychain) ---

func saveTokensToKeychain(accessToken: String, refreshToken: String, expiresIn: TimeInterval) {
    // Save tokens to Keychain (see AuthManager.swift for a full implementation)
    // For simplicity, here's a conceptual overview:
    // 1. Save accessToken using a unique key (e.g., "com.lifespace.accessToken")
    // 2. Save refreshToken using a unique key (e.g., "com.lifespace.refreshToken")
    
    // Also save the expiration date to UserDefaults or Keychain
    let expiryDate = Date().addingTimeInterval(expiresIn)
    UserDefaults.standard.set(expiryDate.timeIntervalSince1970, forKey: "com.lifespace.tokenExpiry")
    
    print("Tokens saved. Expiry date: \(expiryDate)")
}

func getAccessToken() -> String? {
    // Implement logic to load the access token from Keychain
    // return loadedToken
    return nil // Placeholder
}

// --- Token Refresh ---

func refreshToken(completion: @escaping (Bool) -> Void) {
    // Implement logic to use the stored refresh token to get a new access token.
    // This is very similar to `exchangeCodeForToken` but uses "grant_type": "refresh_token".
    // See `refreshTokenWithStoredRefreshToken` in AuthManager.swift for a complete example.
    print("Token refresh needed. Implement refresh logic.")
    completion(false) // Placeholder
}
```

---

## Part 2: Data Formatting (Open mHealth within a FHIR Bundle)

This is the most important concept. JHE doesn't ingest raw Open mHealth JSON directly. Instead, it expects a **FHIR `Bundle`** where each data point is a **FHIR `Observation`**. The OMH data itself is Base64-encoded and placed inside the `Observation`.

### 2.1. The OMH-like JSON Structure

First, create a standard Swift dictionary or struct that represents your data point. For location data, it looks like this:

```swift
/// Creates the JSON structure for a geoposition data point.
func createGeoPositionPayload(latitude: Double, longitude: Double, timestamp: Date) -> [String: Any] {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    let payload: [String: Any] = [
        "latitude": [
            "value": latitude,
            "unit": "deg"
        ],
        "longitude": [
            "value": longitude,
            "unit": "deg"
        ],
        "positioning_system": "GPS", // Or whatever system you use
        "effective_time_frame": [
            "date_time": isoFormatter.string(from: timestamp)
        ]
    ]
    return payload
}
```

### 2.2. The FHIR Observation Wrapper

Next, you wrap this payload inside a FHIR `Observation`. The key steps are:
1.  Define the data type using `code.coding`. For location, you can use the `omh:geoposition:1.0` code.
2.  Serialize the payload from step 2.1 into JSON.
3.  **Base64 encode** the JSON data.
4.  Put the Base64 string into the `valueAttachment.data` field.

Here is a generic function to create a FHIR `Observation` entry for any data payload.

```swift
/// Creates a FHIR Observation entry for a given data payload.
///
/// - Parameters:
///   - payload: The OMH-like data dictionary.
///   - observationCode: A dictionary defining the OMH code (e.g., for geoposition).
///   - patientId: The ID of the patient.
/// - Returns: A dictionary representing a FHIR Bundle entry, or nil on failure.
func createObservationEntry(payload: [String: Any], observationCode: [String: String], patientId: String) -> [String: Any]? {
    do {
        // 1. Serialize the payload to JSON data
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        // 2. Base64 encode the JSON data
        let base64String = jsonData.base64EncodedString()

        // 3. Create the FHIR Observation resource
        let resource: [String: Any] = [
            "resourceType": "Observation",
            "status": "final",
            "subject": ["reference": "Patient/\(patientId)"],
            "code": [
                "coding": [observationCode]
            ],
            "valueAttachment": [
                "contentType": "application/json",
                "data": base64String // 4. The Base64 string goes here
            ],
            "effectiveDateTime": payload["effective_time_frame"]?["date_time"] ?? ISO8601DateFormatter().string(from: Date())
        ]

        // 4. Wrap it in a Bundle entry structure
        let entry: [String: Any] = [
            "resource": resource,
            "request": [
                "method": "POST",
                "url": "Observation"
            ]
        ]
        return entry

    } catch {
        print("Error creating observation entry: \(error)")
        return nil
    }
}
```

---

## Part 3: Data Upload

Finally, you collect all your `Observation` entries into a single FHIR `Bundle` and `POST` it to the server.

### 3.1. The Generic Upload Function

This function takes a list of payloads, formats them using the helper from Part 2, and uploads them.

```swift
/// A generic function to upload any type of data to JHE.
///
/// - Parameters:
///   - payloads: An array of OMH-like data dictionaries.
///   - observationCode: The OMH code for this data type.
///   - authManager: Your authentication manager to get the access token.
///   - completion: A closure with the result of the upload.
func uploadData(
    payloads: [[String: Any]],
    observationCode: [String: String],
    patientId: String,
    completion: @escaping (Bool, String) -> Void
) {
    // --- 1. Get Access Token ---
    guard let accessToken = getAccessToken() else { // Assumes you have a function to get the token
        completion(false, "Not authenticated.")
        return
    }

    // --- 2. Create FHIR Bundle Entries ---
    let entries = payloads.compactMap {
        createObservationEntry(payload: $0, observationCode: observationCode, patientId: patientId)
    }

    if entries.isEmpty {
        completion(false, "No valid data to upload.")
        return
    }

    // --- 3. Create the main FHIR Bundle ---
    let bundle: [String: Any] = [
        "resourceType": "Bundle",
        "type": "batch", // "batch" means the server processes each entry independently
        "entry": entries
    ]

    // --- 4. Prepare and Send the Request ---
    let baseURLString = issuerURL.absoluteString.replacingOccurrences(of: "/o", with: "")
    guard let fhirURL = URL(string: "\(baseURLString)/fhir/r5/") else {
        completion(false, "Invalid FHIR endpoint URL.")
        return
    }

    var request = URLRequest(url: fhirURL)
    request.httpMethod = "POST"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    do {
        request.httpBody = try JSONSerialization.data(withJSONObject: bundle)
    } catch {
        completion(false, "Failed to serialize FHIR Bundle: \(error)")
        return
    }

    // --- 5. Execute the Upload ---
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        guard let httpResponse = response as? HTTPURLResponse, error == nil else {
            completion(false, "Network error: \(error?.localizedDescription ?? "Unknown error")")
            return
        }

        let statusMessage = "Upload finished with status: \(httpResponse.statusCode)."
        if (200...299).contains(httpResponse.statusCode) {
            print("Successfully uploaded \(entries.count) data points.")
            completion(true, statusMessage)
        } else {
            print("Error: Upload failed. \(statusMessage)")
            if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                print("Server response: \(responseBody)")
            }
            completion(false, statusMessage)
        }
    }
    task.resume()
}
```

### 3.2. Putting It All Together: Example Usage

Here’s how you would use these functions to upload location and weather data.

```swift
func uploadHackathonData() {
    let patientId = "40010" // Replace with the actual patient ID

    // --- 1. Upload Location Data ---
    let locationPayload = createGeoPositionPayload(latitude: 37.422, longitude: -122.084, timestamp: Date())
    let geoCode = [
        "system": "https://w3id.org/openmhealth/schema/omh", // Example system
        "code": "geoposition:1.0",
        "display": "Geoposition"
    ]
    
    uploadData(payloads: [locationPayload], observationCode: geoCode, patientId: patientId) { success, message in
        print("Location upload result: \(success) - \(message)")
    }

    // --- 2. Upload Weather Data (Example) ---
    let weatherPayload: [String: Any] = [
        "temperature": ["value": 68, "unit": "F"],
        "condition": "Sunny",
        "effective_time_frame": ["date_time": ISO8601DateFormatter().string(from: Date())]
    ]
    let weatherCode = [
        "system": "http://example.com/weather", // A custom system for weather
        "code": "weather:1.0",
        "display": "Weather"
    ]

    uploadData(payloads: [weatherPayload], observationCode: weatherCode, patientId: patientId) { success, message in
        print("Weather upload result: \(success) - \(message)")
    }
}
```

---

## Conclusion

This guide covers the essential steps for connecting your app to JHE. The key is to wrap your Base64-encoded OMH-like data inside a FHIR `Observation` and upload it as part of a `Bundle`.

I recommend you create a dedicated `JHEManager.swift` class in your project to encapsulate all this logic. Please feel free to reach out if you have any questions. Good luck with the hackathon!

Best,
Yifei
