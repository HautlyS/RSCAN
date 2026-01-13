import SwiftUI

struct ContentView: View {
    @StateObject private var scanVM = ScanViewModel()
    @State private var showScanner = false
    
    private let capability = DeviceCapabilityService.shared.capability
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if scanVM.scannedRooms.isEmpty && scanVM.pointCount == 0 {
                    StartScanView(scanVM: scanVM, showScanner: $showScanner, capability: capability)
                } else {
                    ScannedRoomsListView(scanVM: scanVM, showScanner: $showScanner)
                }
            }
            .navigationTitle("RSCAN")
            .toolbar {
                if !scanVM.scannedRooms.isEmpty || scanVM.pointCount > 0 {
                    Button("Export") { scanVM.exportStructure() }
                }
            }
            .sheet(isPresented: $scanVM.isScanning) {
                if capability.supportsRoomPlan {
                    RoomScanView(scanVM: scanVM)
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                UnifiedScanView()
            }
        }
    }
}

struct StartScanView: View {
    @ObservedObject var scanVM: ScanViewModel
    @Binding var showScanner: Bool
    let capability: ScanCapability
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Scan Your Building")
                .font(.title2)
            
            Text(capability.description)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Mode indicator
            HStack {
                Image(systemName: capability.icon)
                Text(capability.displayName)
            }
            .font(.caption)
            .padding(8)
            .background(capability.color.opacity(0.2))
            .cornerRadius(8)
            
            Button("Start Scanning") {
                if capability.supportsRoomPlan {
                    scanVM.startNewScan()
                } else {
                    showScanner = true
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

extension ScanCapability {
    var supportsRoomPlan: Bool {
        self == .lidar && DeviceCapabilityService.shared.supportsRoomPlan
    }
    
    var description: String {
        switch self {
        case .lidar: return "LiDAR detected! Full room scanning with RoomPlan available."
        case .arkit: return "Using photogrammetry mode. Move slowly around objects for best results."
        case .basic: return "Camera-only mode. Take photos from multiple angles."
        }
    }
    
    var icon: String {
        switch self {
        case .lidar: return "sensor.tag.radiowaves.forward"
        case .arkit: return "video.fill"
        case .basic: return "camera.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .lidar: return .green
        case .arkit: return .blue
        case .basic: return .orange
        }
    }
}

struct ScannedRoomsListView: View {
    @ObservedObject var scanVM: ScanViewModel
    @Binding var showScanner: Bool
    
    private let capability = DeviceCapabilityService.shared.capability
    
    var body: some View {
        List {
            if scanVM.pointCount > 0 {
                Section("Point Cloud") {
                    HStack {
                        Image(systemName: "cube.transparent")
                        VStack(alignment: .leading) {
                            Text("Captured Points")
                            Text("\(scanVM.pointCount.formatted()) points")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            if !scanVM.scannedRooms.isEmpty {
                Section("Rooms") {
                    ForEach(scanVM.scannedRooms) { room in
                        RoomRowView(room: room)
                    }
                }
            }
            
            Section {
                Button {
                    if capability.supportsRoomPlan {
                        scanVM.startNewScan()
                    } else {
                        showScanner = true
                    }
                } label: {
                    Label("Add Scan", systemImage: "plus.circle")
                }
            }
        }
    }
}

struct RoomRowView: View {
    let room: ScannedRoom
    
    var body: some View {
        HStack {
            Image(systemName: "cube.transparent")
            VStack(alignment: .leading) {
                Text(room.name)
                Text("\(room.wallCount) walls • \(room.doorCount) doors")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
