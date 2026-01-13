import Foundation
import RoomPlan
import ARKit
import Combine

@MainActor
class ScanViewModel: ObservableObject {
    @Published var isScanning = false
    @Published var scannedRooms: [ScannedRoom] = []
    @Published var pointCount = 0
    
    private var capturedRooms: [CapturedRoom] = []
    private var pointBuffer: [SIMD3<Float>] = []
    private let structureBuilder = StructureBuilder(options: [.beautifyObjects])
    
    func startNewScan() {
        isScanning = true
    }
    
    func cancelScan() {
        isScanning = false
    }
    
    func finishScan() {
        isScanning = false
    }
    
    func processCapturedData(_ data: CapturedRoomData) {
        // Processing handled by RoomCaptureView delegate
    }
    
    func addRoom(_ room: CapturedRoom) {
        capturedRooms.append(room)
        scannedRooms.append(ScannedRoom(from: room, index: scannedRooms.count))
    }
    
    func processDepthFrame(_ depthMap: CVPixelBuffer, camera: ARCamera) {
        let points = depthToPoints(depthMap, camera: camera)
        pointBuffer.append(contentsOf: points)
        pointCount = pointBuffer.count
    }
    
    private func depthToPoints(_ depth: CVPixelBuffer, camera: ARCamera) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        let width = CVPixelBufferGetWidth(depth)
        let height = CVPixelBufferGetHeight(depth)
        
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depth) else { return [] }
        let depthData = baseAddress.assumingMemoryBound(to: Float32.self)
        
        let intrinsics = camera.intrinsics
        let fx = intrinsics[0][0], fy = intrinsics[1][1]
        let cx = intrinsics[2][0], cy = intrinsics[2][1]
        
        for y in stride(from: 0, to: height, by: 8) {
            for x in stride(from: 0, to: width, by: 8) {
                let z = depthData[y * width + x]
                guard z > 0.1 && z < 5.0 else { continue }
                
                let px = (Float(x) - cx) * z / fx
                let py = (Float(y) - cy) * z / fy
                
                let local = SIMD4<Float>(px, -py, -z, 1)
                let world = camera.transform * local
                points.append(SIMD3(world.x, world.y, world.z))
            }
        }
        return points
    }
    
    func savePointCloud() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scan.ply")
        exportPLY(points: pointBuffer, to: url)
    }
    
    func exportStructure() {
        Task {
            guard !capturedRooms.isEmpty else { return }
            
            do {
                let structure = try await structureBuilder.capturedStructure(from: capturedRooms)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("building.usdz")
                try structure.export(to: url, metadataURL: nil, modelProvider: nil, exportOptions: .mesh)
                
                // Share file
                await shareFile(url)
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
    
    private func shareFile(_ url: URL) async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else { return }
        
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        rootVC.present(activityVC, animated: true)
    }
    
    private func exportPLY(points: [SIMD3<Float>], to url: URL) {
        var ply = "ply\nformat ascii 1.0\n"
        ply += "element vertex \(points.count)\n"
        ply += "property float x\nproperty float y\nproperty float z\n"
        ply += "end_header\n"
        
        for p in points {
            ply += "\(p.x) \(p.y) \(p.z)\n"
        }
        
        try? ply.write(to: url, atomically: true, encoding: .utf8)
    }
}
