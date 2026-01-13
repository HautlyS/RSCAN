import AVFoundation
import UIKit
import ARKit
import Combine

struct CapturedFrame {
    let image: CGImage
    let timestamp: TimeInterval
    let pose: simd_float4x4?
    let intrinsics: simd_float3x3?
}

actor PhotogrammetryCaptureService {
    private var frames: [CapturedFrame] = []
    private var isCapturing = false
    private var lastCaptureTime: TimeInterval = 0
    private let minFrameInterval: TimeInterval = 0.3 // ~3 FPS for quality
    private let maxFrames = 200
    
    var frameCount: Int { frames.count }
    
    func startCapture() {
        frames.removeAll()
        isCapturing = true
        lastCaptureTime = 0
    }
    
    func stopCapture() -> [CapturedFrame] {
        isCapturing = false
        return frames
    }
    
    func processARFrame(_ frame: ARFrame) {
        guard isCapturing else { return }
        guard frame.timestamp - lastCaptureTime >= minFrameInterval else { return }
        guard frames.count < maxFrames else { return }
        
        // Check motion blur via tracking state
        guard frame.camera.trackingState == .normal else { return }
        
        let pixelBuffer = frame.capturedImage
        guard let cgImage = pixelBufferToCGImage(pixelBuffer) else { return }
        
        let captured = CapturedFrame(
            image: cgImage,
            timestamp: frame.timestamp,
            pose: frame.camera.transform,
            intrinsics: frame.camera.intrinsics
        )
        
        frames.append(captured)
        lastCaptureTime = frame.timestamp
    }
    
    func processCameraFrame(_ sampleBuffer: CMSampleBuffer, timestamp: TimeInterval) {
        guard isCapturing else { return }
        guard timestamp - lastCaptureTime >= minFrameInterval else { return }
        guard frames.count < maxFrames else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let cgImage = pixelBufferToCGImage(pixelBuffer) else { return }
        
        let captured = CapturedFrame(
            image: cgImage,
            timestamp: timestamp,
            pose: nil,
            intrinsics: nil
        )
        
        frames.append(captured)
        lastCaptureTime = timestamp
    }
    
    private func pixelBufferToCGImage(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
    
    func exportFrames(to directory: URL) async throws -> [URL] {
        var urls: [URL] = []
        
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        for (index, frame) in frames.enumerated() {
            let url = directory.appendingPathComponent("frame_\(String(format: "%04d", index)).jpg")
            let uiImage = UIImage(cgImage: frame.image)
            
            if let data = uiImage.jpegData(compressionQuality: 0.9) {
                try data.write(to: url)
                urls.append(url)
            }
            
            // Export pose if available
            if let pose = frame.pose {
                let poseURL = directory.appendingPathComponent("frame_\(String(format: "%04d", index)).json")
                let poseData = try JSONEncoder().encode(PoseData(transform: pose, intrinsics: frame.intrinsics))
                try poseData.write(to: poseURL)
            }
        }
        
        return urls
    }
}

struct PoseData: Codable {
    let transform: [[Float]]
    let intrinsics: [[Float]]?
    
    init(transform: simd_float4x4, intrinsics: simd_float3x3?) {
        self.transform = [
            [transform.columns.0.x, transform.columns.0.y, transform.columns.0.z, transform.columns.0.w],
            [transform.columns.1.x, transform.columns.1.y, transform.columns.1.z, transform.columns.1.w],
            [transform.columns.2.x, transform.columns.2.y, transform.columns.2.z, transform.columns.2.w],
            [transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, transform.columns.3.w]
        ]
        
        if let i = intrinsics {
            self.intrinsics = [
                [i.columns.0.x, i.columns.0.y, i.columns.0.z],
                [i.columns.1.x, i.columns.1.y, i.columns.1.z],
                [i.columns.2.x, i.columns.2.y, i.columns.2.z]
            ]
        } else {
            self.intrinsics = nil
        }
    }
}
