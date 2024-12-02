# Location Tracker App

A SwiftUI-based iOS application that tracks user's location and calculates time spent away from home. The app uses CoreLocation for location tracking and CoreData for data persistence.

## Project Structure

```
LocationTracker/
├── App/
│   └── LocationTrackerApp.swift         # Main app entry point and CoreData setup
│
├── Models/
│   └── LocationPin.swift                # Model for map annotations
│
├── Views/
│   ├── MainView.swift                   # Root view controlling app flow
│   ├── LocationPermissionView.swift     # Handles location permission requests
│   ├── ContentTabView.swift            # Main tab bar controller
│   ├── MapContentView.swift            # Map view with location tracking
│   ├── StatisticsView.swift            # Statistics and time calculations
│   ├── SettingsView.swift              # App settings management
│   ├── HomeLocationSelectorView.swift   # Home location selection interface
│   └── LocationUpdateFrequencyView.swift # Location update frequency settings
│
├── ViewModels/
│   └── MainViewModel.swift              # Main view business logic
│
├── Managers/
│   ├── LocationManager.swift            # Core location handling and tracking
│   └── PersistenceController.swift      # CoreData stack management
│
└── Extensions/
    └── Calendar+Extension.swift         # Calendar utility extensions
```

## Core Components

### Data Models (CoreData)

#### LocationRecord Entity
- `timestamp`: Date
- `latitude`: Double
- `longitude`: Double
- `isHome`: Boolean
- `distanceFromHome`: Double

#### HomeLocation Entity
- `latitude`: Double
- `longitude`: Double
- `radius`: Double
- `timestamp`: Date

### Key Managers

#### LocationManager
Primary responsibilities:
- Location tracking and updates
- Permission management
- Home location calculations
- CoreData record creation
- Background location updates

Key methods:
- `requestPermission()`
- `startMonitoring()`
- `saveHomeLocation(latitude:longitude:radius:)`
- `updateCurrentLocationStatus(for:)`

#### PersistenceController
- Manages CoreData stack
- Handles persistent store setup
- Provides shared container access

### View Structure

#### Main Flow
1. MainView → Permission check
2. ContentTabView → Tab management
3. Individual feature views

#### Feature Views
- MapContentView: Real-time location display
- StatisticsView: Time calculations and statistics
- SettingsView: App configuration
- HomeLocationSelectorView: Home location setup

## Key Features

### Location Tracking
- Background location updates
- Configurable update frequency
- Distance-based updates (50m default)

### Home Location
- Custom radius setting
- Map-based selection
- Automatic status updates

### Statistics
- Time away calculation
- Daily location points
- Current status tracking

## Permission Requirements

Info.plist requirements:
```xml
NSLocationAlwaysAndWhenInUseUsageDescription
NSLocationWhenInUseUsageDescription
UIBackgroundModes (location)
```

## File Dependencies

### Critical Paths
1. LocationManager → PersistenceController
2. Views → LocationManager
3. CoreData Models → All tracking features

### State Management
- LocationManager: @Published properties
- Views: @StateObject and @FetchRequest
- ViewModels: @Published and ObservableObject

## Development Notes

### Adding New Features
1. Add models to CoreData if needed
2. Update LocationManager for new tracking features
3. Create new views in Views folder
4. Update README structure

### Maintenance
- Check LocationManager for memory leaks
- Monitor CoreData performance
- Review location update frequency
- Test background mode behavior

### Common Issues
- Location permission handling
- CoreData migration
- Background updates
- Battery optimization