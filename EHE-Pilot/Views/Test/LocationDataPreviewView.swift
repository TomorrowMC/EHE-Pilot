import SwiftUI
import CoreData

struct LocationDataPreviewView: View {
    @StateObject private var locationUploadManager = LocationUploadManager.shared
    @StateObject private var jhDataManager = JHDataExchangeManager.shared
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var records: [LocationRecord] = []
    @State private var showingGenerateOptions = false
    @State private var sampleCount = 5
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Uploadable Location Records")) {
                    if records.isEmpty {
                        Text("No pending location records to upload")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(records, id: \.objectID) { record in
                            locationRecordRow(record)
                        }
                    }
                }
                
                Section(header: Text("Preview FHIR Data")) {
                    if records.isEmpty {
                        Text("No data to preview")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Button(action: {
                                // Print original FHIR Bundle structure
                                let bundle = locationUploadManager.createFHIRBundle(from: Array(records.prefix(3)))
                                if let jsonData = try? JSONSerialization.data(withJSONObject: bundle, options: .prettyPrinted),
                                   let jsonString = String(data: jsonData, encoding: .utf8) {
                                    print("Original FHIR Bundle Preview:\n\(jsonString)")
                                }
                            }) {
                                Text("Print Original FHIR Bundle to Console")
                                    .font(.caption)
                            }
                            
                            Button(action: {
                                // Print JH Data Exchange format FHIR Bundle
                                let bundle = jhDataManager.createFHIRBundle(from: Array(records.prefix(3)))
                                if let jsonData = try? JSONSerialization.data(withJSONObject: bundle, options: .prettyPrinted),
                                   let jsonString = String(data: jsonData, encoding: .utf8) {
                                    print("JH Data Exchange FHIR Bundle Preview:\n\(jsonString)")
                                }
                            }) {
                                Text("Print JH Data Exchange FHIR Bundle to Console")
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                Section(header: Text("Test Tools")) {
                    Button(action: {
                        showingGenerateOptions = true
                    }) {
                        Label("Generate Sample Location Data", systemImage: "plus.circle")
                    }
                    
                    HStack {
                        Button(action: {
                            jhDataManager.generateSampleDataWithSimpleFormat(count: 2)
                            fetchUnuploadedRecords()
                        }) {
                            Label("NYC Data", systemImage: "building.2")
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            jhDataManager.generateSampleDataWithFullFormat(count: 2)
                            fetchUnuploadedRecords()
                        }) {
                            Label("SF Data", systemImage: "sun.max")
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("Delete All Location Records", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Location Data Preview")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        fetchUnuploadedRecords()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                fetchUnuploadedRecords()
            }
            .alert(isPresented: $showingDeleteConfirmation) {
                Alert(
                    title: Text("Confirm Deletion"),
                    message: Text("Are you sure you want to delete all location records? This cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        SampleLocationGenerator.shared.clearAllLocationRecords()
                        fetchUnuploadedRecords()
                    },
                    secondaryButton: .cancel()
                )
            }
            .sheet(isPresented: $showingGenerateOptions) {
                generateOptionsView
            }
        }
    }
    
    private var generateOptionsView: some View {
        NavigationView {
            Form {
                Section(header: Text("Generate Sample Location Data")) {
                    Stepper("Number of samples: \(sampleCount)", value: $sampleCount, in: 1...50)
                    
                    Button(action: {
                        SampleLocationGenerator.shared.generateSampleLocationRecords(count: sampleCount)
                        showingGenerateOptions = false
                        fetchUnuploadedRecords()
                    }) {
                        Text("Generate")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Generation Settings")
            .navigationBarItems(trailing: Button("Cancel") {
                showingGenerateOptions = false
            })
        }
    }
    
    private func locationRecordRow(_ record: LocationRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Coordinates: \(record.latitude, specifier: "%.5f"), \(record.longitude, specifier: "%.5f")")
                    .font(.caption)
                    .bold()
                
                Spacer()
                
                if let timestamp = record.timestamp {
                    Text(timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack {
                if record.isHome {
                    Label("Home", systemImage: "house.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("Away", systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                if let accuracy = record.gpsAccuracy {
                    Text("Accuracy: \(accuracy.doubleValue, specifier: "%.1f")m")
                        .font(.caption)
                        .foregroundColor(accuracy.doubleValue < 10 ? .green : .orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func fetchUnuploadedRecords() {
        records = locationUploadManager.fetchLocationRecords(limit: 20)
    }
}

struct LocationDataPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        LocationDataPreviewView()
            .environmentObject(AuthManager())
    }
}
