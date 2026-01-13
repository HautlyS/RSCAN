import Foundation
import Combine

// MARK: - Pipeline Protocol

protocol ReconstructionModule {
    var name: String { get }
    func process(_ input: ReconstructionData) async throws -> ReconstructionData
}

// MARK: - Data Types

struct ReconstructionData {
    var frames: [CapturedFrame]
    var frameURLs: [URL]
    var features: [FrameFeatures]
    var matches: [FeatureMatch]
    var pointCloud: [SIMD3<Float>]
    var colors: [SIMD3<UInt8>]
    var cameraPoses: [simd_float4x4]
    var mesh: MeshData?
    var progress: Float
    var stage: String
}

struct FrameFeatures {
    let frameIndex: Int
    let keypoints: [SIMD2<Float>]
    let descriptors: Data
}

struct FeatureMatch {
    let frameA: Int
    let frameB: Int
    let matches: [(Int, Int)]
}

struct MeshData {
    var vertices: [SIMD3<Float>]
    var normals: [SIMD3<Float>]
    var indices: [UInt32]
}

// MARK: - Async Pipeline

actor ReconstructionPipeline {
    private var modules: [ReconstructionModule] = []
    private var progressSubject = PassthroughSubject<(Float, String), Never>()
    
    var progressPublisher: AnyPublisher<(Float, String), Never> {
        progressSubject.eraseToAnyPublisher()
    }
    
    func addModule(_ module: ReconstructionModule) {
        modules.append(module)
    }
    
    func process(frames: [CapturedFrame], frameURLs: [URL]) async throws -> ReconstructionData {
        var data = ReconstructionData(
            frames: frames,
            frameURLs: frameURLs,
            features: [],
            matches: [],
            pointCloud: [],
            colors: [],
            cameraPoses: [],
            mesh: nil,
            progress: 0,
            stage: "Starting"
        )
        
        let totalModules = Float(modules.count)
        
        for (index, module) in modules.enumerated() {
            data.stage = module.name
            data.progress = Float(index) / totalModules
            progressSubject.send((data.progress, data.stage))
            
            data = try await module.process(data)
        }
        
        data.progress = 1.0
        data.stage = "Complete"
        progressSubject.send((1.0, "Complete"))
        
        return data
    }
}

// MARK: - Default Pipeline Factory

class ReconstructionPipelineFactory {
    static func createDefaultPipeline() -> ReconstructionPipeline {
        let pipeline = ReconstructionPipeline()
        
        Task {
            await pipeline.addModule(FeatureExtractionModule())
            await pipeline.addModule(FeatureMatchingModule())
            await pipeline.addModule(SfMModule())
            await pipeline.addModule(DenseReconstructionModule())
            await pipeline.addModule(MeshReconstructionModule())
        }
        
        return pipeline
    }
    
    static func createFastPipeline() -> ReconstructionPipeline {
        let pipeline = ReconstructionPipeline()
        
        Task {
            await pipeline.addModule(FeatureExtractionModule(fast: true))
            await pipeline.addModule(FeatureMatchingModule())
            await pipeline.addModule(SfMModule())
        }
        
        return pipeline
    }
}
