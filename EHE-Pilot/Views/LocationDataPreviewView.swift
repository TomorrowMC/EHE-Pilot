import SwiftUI
import CoreData

struct LocationDataPreviewView: View {
    @StateObject private var locationUploadManager = LocationUploadManager.shared
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var records: [LocationRecord] = []
    @State private var showingGenerateOptions = false
    @State private var sampleCount = 5
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("可上传位置记录")) {
                    if records.isEmpty {
                        Text("没有未上传的位置记录")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(records, id: \.objectID) { record in
                            locationRecordRow(record)
                        }
                    }
                }
                
                Section(header: Text("预览FHIR数据")) {
                    if records.isEmpty {
                        Text("没有数据可预览")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        Button(action: {
                            // 打印FHIR Bundle结构
                            let bundle = locationUploadManager.createFHIRBundle(from: Array(records.prefix(3)))
                            if let jsonData = try? JSONSerialization.data(withJSONObject: bundle, options: .prettyPrinted),
                               let jsonString = String(data: jsonData, encoding: .utf8) {
                                print("FHIR Bundle预览:\n\(jsonString)")
                            }
                        }) {
                            Text("控制台打印FHIR Bundle预览")
                                .font(.caption)
                        }
                    }
                }
                
                Section(header: Text("测试工具")) {
                    Button(action: {
                        showingGenerateOptions = true
                    }) {
                        Label("生成示例位置数据", systemImage: "plus.circle")
                    }
                    
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        Label("删除所有位置记录", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("位置数据预览")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("刷新") {
                        fetchUnuploadedRecords()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .onAppear {
                fetchUnuploadedRecords()
            }
            .alert(isPresented: $showingDeleteConfirmation) {
                Alert(
                    title: Text("确认删除"),
                    message: Text("确定要删除所有位置记录吗？此操作不可撤销。"),
                    primaryButton: .destructive(Text("删除")) {
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
                Section(header: Text("生成示例位置数据")) {
                    Stepper("生成数量: \(sampleCount)", value: $sampleCount, in: 1...50)
                    
                    Button(action: {
                        SampleLocationGenerator.shared.generateSampleLocationRecords(count: sampleCount)
                        showingGenerateOptions = false
                        fetchUnuploadedRecords()
                    }) {
                        Text("生成")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("生成设置")
            .navigationBarItems(trailing: Button("取消") {
                showingGenerateOptions = false
            })
        }
    }
    
    private func locationRecordRow(_ record: LocationRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("坐标: \(record.latitude, specifier: "%.5f"), \(record.longitude, specifier: "%.5f")")
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
                    Label("家", systemImage: "house.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Label("外出", systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                if let accuracy = record.gpsAccuracy {
                    Text("精度: \(accuracy.doubleValue, specifier: "%.1f")m")
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