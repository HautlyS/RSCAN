# iOS Scanning Layer - ARKit, RoomPlan, LiDAR

## Overview

The iOS scanning layer captures 3D data using Apple's frameworks on LiDAR-equipped devices (iPhone 12 Pro+, iPad Pro 2020+).

## Core Frameworks

### 1. ARKit - World Tracking
```swift
import ARKit

class ARScanSession {
    let session = ARSession()
    
    func startTracking() {
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        session.run(config)
    }
}
```

### 2. RoomPlan API - Room Scanning
```swift
import RoomPlan

class RoomScanner: RoomCaptureSessionDelegate {
    let captureSession = RoomCaptureSession()
    
    func startScan() {
        captureSession.delegate = self
        let config = RoomCaptureSession.Configuration()
        captureSession.run(configuration: config)
    }
    
    func stopScan() {
        captureSession.stop(pauseARSession: false) // Keep AR for multi-room
    }
    
    // Delegate: receive captured room
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
        guard let finalRoom = try? CapturedRoom(from: data) else { return }
        exportRoom(finalRoom)
    }
    
    func exportRoom(_ room: CapturedRoom) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("room.usdz")
        try? room.export(to: url, exportOptions: .mesh)
    }
}
```

### 3. LiDAR Depth Capture
```swift
import ARKit

extension ARScanSession: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let depthMap = frame.sceneDepth?.depthMap else { return }
        let confidenceMap = frame.sceneDepth?.confidenceMap
        
        // Convert depth to point cloud
        let points = depthToPointCloud(
            depth: depthMap,
            camera: frame.camera,
            confidence: confidenceMap
        )
        appendToBuffer(points)
    }
    
    func depthToPointCloud(depth: CVPixelBuffer, camera: ARCamera, confidence: CVPixelBuffer?) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        let width = CVPixelBufferGetWidth(depth)
        let height = CVPixelBufferGetHeight(depth)
        
        CVPixelBufferLockBaseAddress(depth, .readOnly)
        let depthData = CVPixelBufferGetBaseAddress(depth)!.assumingMemoryBound(to: Float32.self)
        
        let intrinsics = camera.intrinsics
        let fx = intrinsics[0][0], fy = intrinsics[1][1]
        let cx = intrinsics[2][0], cy = intrinsics[2][1]
        
        for y in stride(from: 0, to: height, by: 4) { // Downsample
            for x in stride(from: 0, to: width, by: 4) {
                let z = depthData[y * width + x]
                guard z > 0 && z < 5.0 else { continue }
                
                let px = (Float(x) - cx) * z / fx
                let py = (Float(y) - cy) * z / fy
                
                let localPoint = SIMD4<Float>(px, -py, -z, 1)
                let worldPoint = camera.transform * localPoint
                points.append(SIMD3(worldPoint.x, worldPoint.y, worldPoint.z))
            }
        }
        CVPixelBufferUnlockBaseAddress(depth, .readOnly)
        return points
    }
}
```

## Multi-Room Scanning (CapturedStructure)

```swift
import RoomPlan

class StructureScanner {
    let structureBuilder = StructureBuilder(options: [.beautifyObjects])
    var capturedRooms: [CapturedRoom] = []
    
    func addRoom(_ room: CapturedRoom) {
        capturedRooms.append(room)
    }
    
    func buildStructure() async throws -> CapturedStructure {
        return try await structureBuilder.capturedStructure(from: capturedRooms)
    }
    
    func exportStructure(_ structure: CapturedStructure, to url: URL) throws {
        try structure.export(to: url, metadataURL: nil, modelProvider: nil, exportOptions: .mesh)
    }
}
```

## Export Formats

| Format | Use Case | Method |
|--------|----------|--------|
| USDZ | AR viewing, sharing | `room.export(to:exportOptions:.mesh)` |
| USD | Editing in DCC tools | Same with .usd extension |
| PLY | Point cloud processing | Custom export from depth buffer |

## Point Cloud Buffer for Export

```swift
class PointCloudBuffer {
    var points: [SIMD3<Float>] = []
    var colors: [SIMD3<UInt8>] = []
    
    func exportPLY(to url: URL) throws {
        var ply = "ply\nformat ascii 1.0\n"
        ply += "element vertex \(points.count)\n"
        ply += "property float x\nproperty float y\nproperty float z\n"
        ply += "property uchar red\nproperty uchar green\nproperty uchar blue\n"
        ply += "end_header\n"
        
        for (i, p) in points.enumerated() {
            let c = i < colors.count ? colors[i] : SIMD3<UInt8>(128, 128, 128)
            ply += "\(p.x) \(p.y) \(p.z) \(c.x) \(c.y) \(c.z)\n"
        }
        try ply.write(to: url, atomically: true, encoding: .utf8)
    }
}
```

## Device Requirements

- iPhone 12 Pro / Pro Max or newer
- iPad Pro (2020) or newer  
- iOS/iPadOS 16.0+ for RoomPlan
- iOS/iPadOS 17.0+ for CapturedStructure (multi-room)
