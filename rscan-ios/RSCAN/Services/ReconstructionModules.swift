import Vision
import CoreImage
import Accelerate

// MARK: - Feature Extraction (ORB/SIFT-like via Vision)

class FeatureExtractionModule: ReconstructionModule {
    let name = "Feature Extraction"
    private let fast: Bool
    private let maxKeypoints: Int
    
    init(fast: Bool = false) {
        self.fast = fast
        self.maxKeypoints = fast ? 500 : 2000
    }
    
    func process(_ input: ReconstructionData) async throws -> ReconstructionData {
        var output = input
        output.features = []
        
        for (index, url) in input.frameURLs.enumerated() {
            let features = try await extractFeatures(from: url, frameIndex: index)
            output.features.append(features)
        }
        
        return output
    }
    
    private func extractFeatures(from url: URL, frameIndex: Int) async throws -> FrameFeatures {
        guard let image = CIImage(contentsOf: url) else {
            throw ReconstructionError.invalidImage
        }
        
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try handler.perform([request])
        
        // Use corner detection for keypoints
        let keypoints = try await detectCorners(in: image)
        
        // Get feature print as descriptor
        let descriptor = request.results?.first?.data ?? Data()
        
        return FrameFeatures(
            frameIndex: frameIndex,
            keypoints: Array(keypoints.prefix(maxKeypoints)),
            descriptors: descriptor
        )
    }
    
    private func detectCorners(in image: CIImage) async throws -> [SIMD2<Float>] {
        var keypoints: [SIMD2<Float>] = []
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            return keypoints
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Convert to grayscale
        var grayscale = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: &grayscale,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return keypoints }
        
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Simple Harris corner detection
        let step = fast ? 8 : 4
        for y in stride(from: step, to: height - step, by: step) {
            for x in stride(from: step, to: width - step, by: step) {
                let response = harrisResponse(grayscale, x: x, y: y, width: width)
                if response > 0.01 {
                    keypoints.append(SIMD2(Float(x), Float(y)))
                }
            }
        }
        
        return keypoints
    }
    
    private func harrisResponse(_ img: [UInt8], x: Int, y: Int, width: Int) -> Float {
        var ix2: Float = 0, iy2: Float = 0, ixy: Float = 0
        
        for dy in -1...1 {
            for dx in -1...1 {
                let idx = (y + dy) * width + (x + dx)
                let idxR = (y + dy) * width + (x + dx + 1)
                let idxD = (y + dy + 1) * width + (x + dx)
                
                guard idx >= 0, idxR < img.count, idxD < img.count else { continue }
                
                let gx = Float(img[idxR]) - Float(img[idx])
                let gy = Float(img[idxD]) - Float(img[idx])
                
                ix2 += gx * gx
                iy2 += gy * gy
                ixy += gx * gy
            }
        }
        
        let det = ix2 * iy2 - ixy * ixy
        let trace = ix2 + iy2
        return det - 0.04 * trace * trace
    }
}

// MARK: - Feature Matching

class FeatureMatchingModule: ReconstructionModule {
    let name = "Feature Matching"
    
    func process(_ input: ReconstructionData) async throws -> ReconstructionData {
        var output = input
        output.matches = []
        
        // Match consecutive frames + some skip frames
        for i in 0..<input.features.count {
            for j in (i+1)..<min(i+5, input.features.count) {
                let match = matchFeatures(input.features[i], input.features[j])
                if match.matches.count > 20 {
                    output.matches.append(match)
                }
            }
        }
        
        return output
    }
    
    private func matchFeatures(_ a: FrameFeatures, _ b: FrameFeatures) -> FeatureMatch {
        var matches: [(Int, Int)] = []
        
        // Simple nearest neighbor matching based on position (for demo)
        // Real implementation would use descriptor matching
        for (i, kpA) in a.keypoints.enumerated() {
            var bestDist: Float = .infinity
            var bestJ = -1
            
            for (j, kpB) in b.keypoints.enumerated() {
                let dist = simd_distance(kpA, kpB)
                if dist < bestDist && dist < 50 {
                    bestDist = dist
                    bestJ = j
                }
            }
            
            if bestJ >= 0 {
                matches.append((i, bestJ))
            }
        }
        
        return FeatureMatch(frameA: a.frameIndex, frameB: b.frameIndex, matches: matches)
    }
}

// MARK: - Structure from Motion

class SfMModule: ReconstructionModule {
    let name = "Structure from Motion"
    
    func process(_ input: ReconstructionData) async throws -> ReconstructionData {
        var output = input
        
        // Initialize with first two frames
        guard input.matches.count > 0 else {
            throw ReconstructionError.insufficientMatches
        }
        
        // Use ARKit poses if available
        if let firstFrame = input.frames.first, firstFrame.pose != nil {
            output.cameraPoses = input.frames.compactMap { $0.pose }
            output.pointCloud = triangulateWithPoses(input)
        } else {
            // Estimate poses from matches (simplified)
            let (poses, points) = estimatePosesAndPoints(input)
            output.cameraPoses = poses
            output.pointCloud = points
        }
        
        return output
    }
    
    private func triangulateWithPoses(_ input: ReconstructionData) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        
        // Triangulate matched points using known poses
        for match in input.matches {
            guard match.frameA < input.frames.count,
                  match.frameB < input.frames.count,
                  let poseA = input.frames[match.frameA].pose,
                  let poseB = input.frames[match.frameB].pose else { continue }
            
            let featuresA = input.features[match.frameA]
            let featuresB = input.features[match.frameB]
            
            for (idxA, idxB) in match.matches.prefix(100) {
                guard idxA < featuresA.keypoints.count,
                      idxB < featuresB.keypoints.count else { continue }
                
                let ptA = featuresA.keypoints[idxA]
                let ptB = featuresB.keypoints[idxB]
                
                if let point3D = triangulate(ptA, ptB, poseA, poseB) {
                    points.append(point3D)
                }
            }
        }
        
        return points
    }
    
    private func triangulate(_ p1: SIMD2<Float>, _ p2: SIMD2<Float>,
                            _ pose1: simd_float4x4, _ pose2: simd_float4x4) -> SIMD3<Float>? {
        // Simplified mid-point triangulation
        let dir1 = simd_normalize(SIMD3<Float>(p1.x / 1000, p1.y / 1000, 1))
        let dir2 = simd_normalize(SIMD3<Float>(p2.x / 1000, p2.y / 1000, 1))
        
        let origin1 = SIMD3<Float>(pose1.columns.3.x, pose1.columns.3.y, pose1.columns.3.z)
        let origin2 = SIMD3<Float>(pose2.columns.3.x, pose2.columns.3.y, pose2.columns.3.z)
        
        // Transform directions to world space
        let rot1 = simd_float3x3(
            SIMD3(pose1.columns.0.x, pose1.columns.0.y, pose1.columns.0.z),
            SIMD3(pose1.columns.1.x, pose1.columns.1.y, pose1.columns.1.z),
            SIMD3(pose1.columns.2.x, pose1.columns.2.y, pose1.columns.2.z)
        )
        let worldDir1 = rot1 * dir1
        
        // Simple depth estimate
        let depth: Float = 2.0
        return origin1 + worldDir1 * depth
    }
    
    private func estimatePosesAndPoints(_ input: ReconstructionData) -> ([simd_float4x4], [SIMD3<Float>]) {
        // Simplified: assume forward motion
        var poses: [simd_float4x4] = []
        var points: [SIMD3<Float>] = []
        
        for i in 0..<input.features.count {
            var pose = matrix_identity_float4x4
            pose.columns.3.z = Float(i) * -0.1 // Move forward
            poses.append(pose)
        }
        
        // Generate sparse point cloud from features
        for (i, features) in input.features.enumerated() {
            for kp in features.keypoints.prefix(50) {
                let x = (kp.x - 500) / 500.0
                let y = (kp.y - 500) / 500.0
                let z = Float(i) * -0.1 - 1.0
                points.append(SIMD3(x, y, z))
            }
        }
        
        return (poses, points)
    }
}

// MARK: - Dense Reconstruction

class DenseReconstructionModule: ReconstructionModule {
    let name = "Dense Reconstruction"
    
    func process(_ input: ReconstructionData) async throws -> ReconstructionData {
        var output = input
        
        // Densify point cloud using multi-view stereo concepts
        // This is a simplified version - real MVS is much more complex
        
        var densePoints: [SIMD3<Float>] = input.pointCloud
        var colors: [SIMD3<UInt8>] = []
        
        // Add interpolated points
        for i in 0..<input.pointCloud.count - 1 {
            let p1 = input.pointCloud[i]
            let p2 = input.pointCloud[min(i + 1, input.pointCloud.count - 1)]
            
            // Interpolate
            for t in stride(from: 0.0, to: 1.0, by: 0.5) {
                let interp = p1 * Float(1 - t) + p2 * Float(t)
                densePoints.append(interp)
                colors.append(SIMD3(128, 128, 128))
            }
        }
        
        output.pointCloud = densePoints
        output.colors = colors
        
        return output
    }
}

// MARK: - Mesh Reconstruction

class MeshReconstructionModule: ReconstructionModule {
    let name = "Mesh Generation"
    
    func process(_ input: ReconstructionData) async throws -> ReconstructionData {
        var output = input
        
        guard input.pointCloud.count > 10 else {
            return output
        }
        
        // Simple mesh from point cloud using ball pivoting concept
        let mesh = generateMesh(from: input.pointCloud)
        output.mesh = mesh
        
        return output
    }
    
    private func generateMesh(from points: [SIMD3<Float>]) -> MeshData {
        var vertices = points
        var normals: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        
        // Estimate normals
        for p in points {
            normals.append(SIMD3(0, 1, 0)) // Simplified upward normal
        }
        
        // Create triangles from nearby points (simplified Delaunay-like)
        for i in 0..<min(points.count - 2, 1000) {
            indices.append(UInt32(i))
            indices.append(UInt32(i + 1))
            indices.append(UInt32(i + 2))
        }
        
        return MeshData(vertices: vertices, normals: normals, indices: indices)
    }
}

// MARK: - Errors

enum ReconstructionError: Error {
    case invalidImage
    case insufficientMatches
    case reconstructionFailed
}
