# EHE-Pilot

**EHE-Pilot** is an iOS application designed to continuously track and record the user's geographical location, store these records in CoreData, and provide useful daily statistics. The app can run in both foreground and background modes, allowing you to monitor how much time you spend away from your "home" location without draining too much battery. It supports exporting all location data as a CSV file.

## Table of Contents
- [Overview](#overview)
- [Features](#features)
- [Project Structure](#project-structure)
- [Core Functionalities](#core-functionalities)
- [Location Tracking Logic](#location-tracking-logic)
- [Background Mode Configuration](#background-mode-configuration)
- [UI Highlights](#ui-highlights)
- [CSV Export](#csv-export)
- [Customization](#customization)
- [Setup & Requirements](#setup--requirements)
- [License](#license)

## Overview
EHE-Pilot leverages CoreLocation to track the user’s location throughout the day. It stores records (timestamp, latitude, longitude, at-home status) in CoreData. The app differentiates between foreground and background modes:
- In the **foreground**, it updates the user’s location every minute.
- In the **background**, it relies on significant location changes and background tasks to minimize power consumption while still capturing location data over time.

The app also allows you to set a "home" location and calculates daily statistics, such as total time spent away. You can view a neatly formatted list of today's location records, including timestamp, latitude, longitude, and whether you were at home.

## Features
- **Home Location Setup:** Set a home coordinate and radius, used to determine whether you’re "at home" or "away."
- **Foreground Tracking:** While the app is active, it records location data every minute.
- **Background Tracking:** When the app moves to the background, it switches to significant location changes and scheduled background tasks to conserve battery.
- **Daily Statistics:** View how long you spent away from home, the total number of location points recorded, and your current status.
- **Daily Location Records:** A visually enhanced list of all the day’s recorded points, sorted by newest first.
- **CSV Export:** Export all recorded location data as a CSV file via the Settings menu.

## Project Structure
```
LocationTracker/
├── App/
│   └── EHE_PilotApp.swift              # Main app entry, BGTask registration
│
├── Models/
│   └── LocationPin.swift               # Model for map annotations (UI)
│
├── Views/
│   ├── MainView.swift                  # Handles app start and permission checks
│   ├── LocationPermissionView.swift    # Handles location permission requests
│   ├── ContentTabView.swift            # Main tab bar navigation
│   ├── MapContentView.swift            # Shows user’s location on a map
│   ├── StatisticsView.swift            # Displays daily stats & location records
│   ├── SettingsView.swift              # App settings, CSV export button
│   ├── HomeLocationSelectorView.swift  # Select/update home location
│   └── LocationUpdateFrequencyView.swift # (Optional) Frequency setting UI
│
├── ViewModels/
│   └── MainViewModel.swift             # Business logic for main view
│
├── Managers/
│   ├── LocationManager.swift           # Core location logic, background tasks
│   ├── PersistenceController.swift     # CoreData stack management
│   └── CSVExporter.swift               # Generates CSV from CoreData records
│
└── Extensions/
    └── Calendar+Extension.swift        # Utility extensions for date/time calculations
```
## Data Models

### LocationRecord (CoreData Entity)
- **timestamp (Date):** When the location was recorded.
- **latitude (Double):** User's latitude.
- **longitude (Double):** User's longitude.
- **isHome (Bool):** Whether the user was within the home radius at that time.
- **distanceFromHome (Double):** Distance to the home location.

### HomeLocation (CoreData Entity)
- **latitude (Double)**
- **longitude (Double)**
- **radius (Double)**: Defines the home boundary.
- **timestamp (Date)**: Last time home was set or updated.
- ** gpsAccuracy (Double)** : GPS strength of the current recording point for determining whether the user is in a building or not

## Core Functionalities
- **CoreData Storage:** Every recorded location is stored along with timestamp, latitude, longitude, and a Boolean indicating if user was at home.
- **At-Home Determination:** The app calculates the user’s distance from the home location radius to determine status.
- **Time Calculation:** Calculates total time spent away from home using recorded timestamps.

## Location Tracking Logic
- **Foreground:**  
  When the app is active (`scenePhase == .active`), it uses `startUpdatingLocation()` and a timer to request new locations every 60 seconds.
  
- **Background:**  
  When moving to the background, the app stops continuous updates and relies on:
  - `startMonitoringSignificantLocationChanges()` to get notified of major location shifts.
  - Periodic `BGAppRefreshTask` to request a single location update occasionally.
  
  This approach reduces battery usage significantly while still capturing meaningful data points throughout the day.

## Background Mode Configuration
- **Info.plist:**  
  Configured with:
  - `UIBackgroundModes` including `location`, `fetch`, `processing`
  - `BGTaskSchedulerPermittedIdentifiers` with `com.EHE-Pilot.LocationUpdate`
  - `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationWhenInUseUsageDescription`
  
- **BGTaskScheduler:**  
  Registered in `EHE_PilotApp.init()`. The background task triggers `LocationManager.handleBackgroundTask(_:)` to request one-time location updates at intervals.

## UI Highlights
- **StatisticsView:**  
  Displays daily away time, number of recorded points, current home/away status, and a list of recorded points (newest first) in a visually appealing layout with material backgrounds and icons.
  
- **SettingsView:**  
  Offers a CSV export button. Generates a CSV file of all recorded data and allows sharing via `ShareLink`.
  
- **Permission Views:**  
  Custom permission prompts guide the user to grant "Always" location permission to enable background tracking.

## CSV Export
The `CSVExporter` fetches all `LocationRecord`s and creates a CSV file including:
- Timestamp (ISO 8601)
- Latitude
- Longitude
- isHome (1 for at home, 0 for away)

Users can easily export and share this file for external analysis.

## Customization
- **Update Interval in Foreground:**  
  Currently set to 1 minute when foregrounded. You can adjust this interval in `LocationManager.startForegroundUpdates()`.
  
- **Background Task Interval:**  
  Adjust `request.earliestBeginDate` in `scheduleBackgroundTask()` to change how frequently background tasks run.
  
- **UI Styling:**  
  Modify colors, fonts, and materials to match your brand or visual preferences.

## Setup & Requirements
- **Requirements:**
  - iOS 16+
  - Swift 5.7+
  - Xcode 14+
  
- **Setup Steps:**
  1. Clone the repository:
     ```bash
     git clone https://github.com/yourusername/EHE-Pilot.git
     ```
  2. Open `LocationTracker.xcodeproj` in Xcode.
  3. Configure Signing & Capabilities:
     - Enable Background Modes: Location Updates, Background Fetch
  4. Run on a real iOS device for proper location testing.

## License
This project is available under the MIT License. See the [LICENSE](LICENSE) file for details.

```
EHE-Pilot
├─ .DS_Store
├─ EHE-Pilot
│  ├─ Assets.xcassets
│  │  ├─ AccentColor.colorset
│  │  │  └─ Contents.json
│  │  ├─ AppIcon.appiconset
│  │  │  ├─ Contents.json
│  │  │  └─ Untitled design.png
│  │  └─ Contents.json
│  ├─ CoreData
│  │  └─ LocationTracker.xcdatamodeld
│  │     └─ LocationTracker.xcdatamodel
│  │        └─ contents
│  ├─ EHE_Pilot.entitlements
│  ├─ EHE_PilotApp.swift
│  ├─ Extension
│  │  └─ Calendar+Extension.swift
│  ├─ Info.plist
│  ├─ Managers
│  │  ├─ AuthManager.swift
│  │  ├─ BackgroundRefreshManager.swift
│  │  ├─ CSVExporter.swift
│  │  ├─ ClipboardLoginHelper.swift
│  │  ├─ FHIRUploadService.swift
│  │  ├─ JHDataExchangeManager.swift
│  │  ├─ LocationManager.swift
│  │  ├─ LocationUploadManager.swift
│  │  ├─ MotionManager.swift
│  │  ├─ PersistenceController.swift
│  │  └─ TokenRefreshManager.swift
│  ├─ Models
│  │  └─ LocationPin.swift
│  ├─ Preview Content
│  │  └─ Preview Assets.xcassets
│  │     └─ Contents.json
│  ├─ ViewModels
│  │  └─ MainViewModel.swift
│  └─ Views
│     ├─ AppDelegate.swift
│     ├─ ContentTabView.swift
│     ├─ DataTest
│     │  ├─ ConsentDebugTool.swift
│     │  ├─ FHIRTestTool.swift
│     │  ├─ LocationDataPreviewView.swift
│     │  ├─ LoginTestView.swift
│     │  ├─ OAuthLoginView.swift
│     │  ├─ SampleLocationGenerator.swift
│     │  └─ UploadDebugTool.swift
│     ├─ KeyTest
│     │  └─ TokenTestView.swift
│     ├─ LocationPermissionView.swift
│     ├─ MainView.swift
│     ├─ MapContentView.swift
│     ├─ Setting
│     │  ├─ ConsentManagerView.swift
│     │  ├─ HomeLocationSelectorView.swift
│     │  ├─ LocationUpdateFrequencyView.swift
│     │  └─ UserProfileView.swift
│     ├─ SettingsView.swift
│     └─ StatisticsView.swift
├─ EHE-Pilot.xcodeproj
│  ├─ project.pbxproj
│  ├─ project.xcworkspace
│  │  ├─ contents.xcworkspacedata
│  │  ├─ xcshareddata
│  │  │  └─ swiftpm
│  │  │     ├─ Package.resolved
│  │  │     └─ configuration
│  │  └─ xcuserdata
│  │     └─ yifei.hu.xcuserdatad
│  │        └─ UserInterfaceState.xcuserstate
│  └─ xcuserdata
│     └─ yifei.hu.xcuserdatad
│        └─ xcschemes
│           └─ xcschememanagement.plist
└─ readme.md

```