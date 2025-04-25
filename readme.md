# EHE-Pilot

**EHE-Pilot** is an iOS application designed to continuously track and record the user's geographical location and calculate derived metrics like daily time outdoors. It stores these records locally using CoreData and provides useful daily statistics. The app runs in both foreground and background modes, optimizing for battery life while ensuring data capture. Key features include setting a home location, calculating time away/outdoors, exporting data to CSV, and securely uploading data to a backend FHIR server integrated with the JupyterHealth Exchange platform.

## Table of Contents
- [Overview](#overview)
- [Features](#features)
- [JupyterHealth Exchange Integration](#jupyterhealth-exchange-integration)
- [Project Structure](#project-structure)
- [Data Models](#data-models)
- [Core Functionalities](#core-functionalities)
- [Location Tracking Logic](#location-tracking-logic)
- [Background Mode Configuration](#background-mode-configuration)
- [UI Highlights](#ui-highlights)
- [CSV Export](#csv-export)
- [Customization](#customization)
- [Setup & Requirements](#setup--requirements)
- [License](#license)

## Overview
EHE-Pilot uses CoreLocation to track the user’s location throughout the day. It stores records (timestamp, latitude, longitude, accuracy, at-home status) in CoreData using `PersistenceController.swift`. The app differentiates between foreground and background modes to balance data granularity and battery life.

Users can define a "home" location, and the app calculates daily statistics, such as time spent away from home and time spent outdoors. In addition to local storage and CSV export, the app securely authenticates via OAuth 2.0 (`AuthManager.swift`) and uploads location and time interval data (representing time outdoors) to a FHIR-compliant backend server, facilitating its use within the JupyterHealth Exchange ecosystem.

## Features
- **Home Location Setup:** Set a home coordinate and radius via `SettingsView.swift` and `HomeLocationSelectorView.swift`.
- **Background Tracking:** Uses significant location changes and scheduled background tasks (`BackgroundRefreshManager.swift`) for battery-efficient background monitoring.
- **Daily Statistics:** `StatisticsView.swift` displays calculated metrics like time away, time outdoors, and location point counts.
- **Daily Location Records:** View a detailed list of location points for a selected day in `StatisticsView.swift`.
- **Data Upload:** Automatically (and manually via `SettingsView.swift`) uploads location (`omh:geoposition:1.0`) and time outdoors (`omh:time-interval:1.0`) data to a secure FHIR backend using `FHIRUploadService.swift`.
- **Authentication:** Secure user login and session management using OAuth 2.0 (`AuthManager.swift`).
- **CSV Export:** Export detailed location records, including calculated away/outdoor status and cumulative daily times, via `SettingsView.swift` using `CSVExporter.swift`.
- **Testing Utilities:** Includes views for testing OAuth flow, token management, FHIR uploads, and data generation (`FHIRTestTool.swift`, `TimeOutdoorsTestView.swift`, etc.).

## JupyterHealth Exchange Integration

This application is designed to integrate with health data platforms like the JupyterHealth Exchange by uploading collected sensor data to a secure, FHIR-compliant backend server.

- **Authentication:** Connection to the backend requires user authentication via OAuth 2.0, managed by `AuthManager.swift`. This ensures that data is linked to the correct user account and access is properly controlled.
- **Data Types Uploaded:**
    - **Geolocation Data:** Recorded latitude, longitude, timestamp, and accuracy are packaged using the `omh:geoposition:1.0` standard code.
    - **Time Outdoors:** Daily cumulative time spent outdoors is calculated locally (`TimeOutdoorsManager.swift`) and uploaded using the `omh:time-interval:1.0` standard code. The raw JSON payload for time interval data is embedded within the FHIR Observation's `valueAttachment`.
- **Upload Mechanism:**
    - The `FHIRUploadService.swift` class is responsible for orchestrating the data upload process.
    - It fetches unsynced data from CoreData (`LocationRecord`, `TimeOutdoorsRecord`).
    - Data is formatted into FHIR `Observation` resources.
    - Multiple observations are bundled into a FHIR `Bundle` resource with `type` set to `batch`.
    - The bundle is sent via an HTTP POST request to the configured FHIR server endpoint (e.g., `/fhir/r5/`).
    - Authentication is handled by including a Bearer token (obtained via `AuthManager.swift`) in the `Authorization` header.
- **Triggers:** Data upload occurs automatically in the background via scheduled tasks managed by `BackgroundRefreshManager.swift` and can also be manually triggered from the `Data Upload Settings` screen within `SettingsView.swift`.
- **Consent:** The server enforces data consent rules. Data types (like `omh:time-interval:1.0`) will only be accepted if the authenticated patient has consented to share that specific type of data within the relevant study context. Errors related to consent (e.g., `403 Forbidden`) are handled and logged.

## Project Structure
EHE-Pilot
├─ .DS_Store
├─ EHE-Pilot
│  ├─ Assets.xcassets
│  ├─ CoreData
│  │  └─ LocationTracker.xcdatamodeld
│  ├─ EHE_Pilot.entitlements
│  ├─ EHE_PilotApp.swift               # App Entry Point, ScenePhase, BGTask Registration
│  ├─ Extension
│  │  └─ Calendar+Extension.swift
│  ├─ Info.plist
│  ├─ Managers                       # Core logic and services
│  │  ├─ AuthManager.swift            # Handles OAuth 2.0 Authentication
│  │  ├─ BackgroundRefreshManager.swift # Manages background tasks
│  │  ├─ CSVExporter.swift            # Handles CSV data export
│  │  ├─ ClipboardLoginHelper.swift   # Helper for invitation link login
│  │  ├─ FHIRUploadService.swift        # Manages data upload to FHIR server
│  │  ├─ JHDataExchangeManager.swift    # Potential helper for FHIR/Data Exchange 
│  │  ├─ LocationManager.swift        # Core Location tracking logic
│  │  ├─ MotionManager.swift          # Detects user motion state
│  │  ├─ PersistenceController.swift  # CoreData stack setup
│  │  ├─ TimeOutdoorsManager.swift    # Calculates and manages Time Outdoors data
│  │  └─ TokenRefreshManager.swift    # Manages OAuth token refresh
│  ├─ Models
│  │  └─ LocationPin.swift            # Used for map annotations
│  ├─ Preview Content
│  │  └─ Preview Assets.xcassets
│  ├─ ViewModels
│  │  └─ MainViewModel.swift
│  └─ Views                            # UI Components
│     ├─ AppDelegate.swift              # App lifecycle delegate
│     ├─ ContentTabView.swift           # Main Tab Bar UI
│     ├─ DataTest                     # Views for testing/debugging
│     │  ├─ ConsentDebugTool.swift
│     │  ├─ FHIRTestTool.swift
│     │  ├─ LocationDataPreviewView.swift
│     │  ├─ LoginTestView.swift
│     │  ├─ OAuthLoginView.swift
│     │  ├─ SampleLocationGenerator.swift
│     │  ├─ TimeOutdoorsTestView.swift # View for testing Time Outdoors features
│     │  └─ UploadDebugTool.swift
│     ├─ KeyTest
│     │  └─ TokenTestView.swift
│     ├─ LocationPermissionView.swift   # Guides user through location permissions
│     ├─ MainView.swift                 # Initial view loading/permission check
│     ├─ MapContentView.swift           # Displays map with current location
│     ├─ Setting                      # Views related to settings
│     │  ├─ ConsentManagerView.swift
│     │  ├─ DataUploadView.swift       # Manual data upload trigger
│     │  ├─ HomeLocationSelectorView.swift
│     │  ├─ LocationUpdateFrequencyView.swift
│     │  └─ UserProfileView.swift
│     ├─ SettingsView.swift             # Main settings screen, CSV Export
│     └─ StatisticsView.swift           # Displays daily statistics and records
├─ EHE-Pilot.xcodeproj
│  ├─ project.pbxproj
│  └─ project.xcworkspace
└─ readme.md

## Data Models

### LocationRecord (CoreData Entity)
- `timestamp` (Date): When the location was recorded.
- `latitude` (Double): User's latitude.
- `longitude` (Double): User's longitude.
- `gpsAccuracy` (Double?): Horizontal accuracy in meters (optional).
- `isHome` (Bool): Whether the user was within the home radius at that time.
- `distanceFromHome` (Double): Distance to the home location.
- `ifUpdated` (Bool): Flag indicating if the record has been uploaded to the server.

### HomeLocation (CoreData Entity)
- `latitude` (Double)
- `longitude` (Double)
- `radius` (Double): Defines the home boundary in meters.
- `timestamp` (Date): Last time home was set or updated.

### TimeOutdoorsRecord (CoreData Entity)
- `date` (Date): The specific day the record applies to (normalized to start of day).
- `totalDurationMinutes` (Int64): Total minutes spent outdoors on that day.
- `isUploaded` (Bool): Flag indicating if this daily summary has been uploaded.
- `calculationTimestamp` (Date): When this record was calculated.

## Core Functionalities
- **CoreData Storage:** Stores `LocationRecord` points and calculated daily `TimeOutdoorsRecord` summaries.
- **At-Home Determination:** Calculates distance from the defined `HomeLocation` to determine `isHome` status for each `LocationRecord`.
- **Time Calculation:** Calculates total daily time spent away from home and outdoors using recorded timestamps and statuses (`StatisticsView.swift`, `TimeOutdoorsManager.swift`).
- **Data Upload:** Packages and uploads location and time interval data as FHIR Observations to a backend server (`FHIRUploadService.swift`).

## Location Tracking Logic
- **Foreground:** Uses `startUpdatingLocation()` and a timer for frequent updates (configurable).
- **Background:** Switches to `startMonitoringSignificantLocationChanges()` and periodic `BGAppRefreshTask` execution to conserve battery.
- **Motion Detection:** Uses `MotionManager.swift` to potentially adjust tracking frequency/accuracy based on whether the user is moving or stationary.

## Background Mode Configuration
- **Info.plist:** Configured with `location`, `fetch`, `processing` background modes and necessary location usage descriptions.
- **BGTaskScheduler:** Background tasks (`com.EHE-Pilot.LocationUpdate`, `com.EHE-Pilot.AuthRefresh`, `com.EHE-Pilot.TimeOutdoorsUpdate`) are registered in `AppDelegate.swift` via `BackgroundRefreshManager.swift` to handle periodic location fetching, token refreshes, and data processing/upload.

## CSV Export
The `CSVExporter.swift` class fetches all `LocationRecord` data from CoreData and generates a CSV file. The exported columns include:
- `Timestamp` (ISO 8601 UTC)
- `Latitude`
- `Longitude`
- `Accuracy` (meters, "N/A" if unavailable)
- `IsAwayFromHome` (1 if away, 0 if at home)
- `IsOutdoors` (1 if considered outdoors, 0 otherwise)
- `CumulativeTimeAwayHome(minutes)` (Running total minutes away for the day up to that point)
- `CumulativeTimeOutdoors(minutes)` (Running total minutes outdoors for the day up to that point)

## Setup & Requirements
- **Requirements:**
  - iOS 16+
  - Swift 5.7+
  - Xcode 14+
- **Setup Steps:**
  1. Clone the repository.
  2. Open `EHE-Pilot.xcodeproj` in Xcode.
  3. Configure Signing & Capabilities (Bundle ID, Team).
  4. Ensure Background Modes (Location Updates, Background Fetch, Background Processing) are enabled.
  5. Add necessary keys to `Info.plist` (Location Usage Descriptions, Background Task Identifiers).
  6. Configure OAuth 2.0 client ID, redirect URI, and issuer URL in `AuthManager.swift` or a configuration file.
  7. Run on a real iOS device for accurate location tracking and background task testing.

## License
This project is available under the MIT License. See the LICENSE file for details.
