import SwiftUI
import ARKit
import Combine

struct UnifiedScanView: View {
    @StateObject private var viewModel = UnifiedScanViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Camera/AR View
            if viewModel.capability == .lidar || viewModel.capability == .arkit {
                ARScanViewRepresentable(viewModel: viewModel)
                    .ignoresSafeArea()
            } else {
                CameraScanViewRepresentable(viewModel: viewModel)
                    .ignoresSafeArea()
            }
            
            // Overlay UI
            VStack {
                // Status bar
                HStack {
                    VStack(alignment: .leading) {
                        Text(viewModel.capability.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(viewModel.frameCount) frames")
                            .font(.headline)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                    
                    Spacer()
                    
                    if viewModel.isRecording {
                        RecordingIndicator()
                    }
                }
                .padding()
                
                Spacer()
                
                // Progress during processing
                if viewModel.isProcessing {
                    ProcessingOverlay(progress: viewModel.progress, stage: viewModel.stage)
                }
                
                // Controls
                HStack(spacing: 30) {
                    Button("Cancel") {
                        viewModel.cancel()
                        dismiss()
                    }
                    .buttonStyle(ScanButtonStyle(isPrimary: false))
                    
                    Button(viewModel.isRecording ? "Stop" : "Record") {
                        viewModel.toggleRecording()
                    }
                    .buttonStyle(ScanButtonStyle(isPrimary: true, isRecording: viewModel.isRecording))
                    
                    Button("Done") {
                        Task {
                            await viewModel.processAndExport()
                            dismiss()
                        }
                    }
                    .buttonStyle(ScanButtonStyle(isPrimary: false))
                    .disabled(viewModel.frameCount < 10)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .onAppear { viewModel.setup() }
    }
}

// MARK: - AR Scan View (LiDAR + ARKit)

struct ARScanViewRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: UnifiedScanViewModel
    
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session.delegate = context.coordinator
        
        var config: ARConfiguration
        if DeviceCapabilityService.shared.hasLiDAR {
            let worldConfig = ARWorldTrackingConfiguration()
            worldConfig.sceneReconstruction = .meshWithClassification
            worldConfig.frameSemantics = [.sceneDepth]
            config = worldConfig
        } else {
            config = ARWorldTrackingConfiguration()
        }
        
        view.session.run(config)
        return view
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        let viewModel: UnifiedScanViewModel
        
        init(viewModel: UnifiedScanViewModel) {
            self.viewModel = viewModel
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            Task { await viewModel.processARFrame(frame) }
        }
    }
}

// MARK: - Camera Scan View (Basic devices)

struct CameraScanViewRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: UnifiedScanViewModel
    
    func makeUIView(context: Context) -> UIView {
        let view = CameraPreviewView()
        view.delegate = context.coordinator
        view.startSession()
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    class Coordinator: NSObject, CameraPreviewDelegate {
        let viewModel: UnifiedScanViewModel
        
        init(viewModel: UnifiedScanViewModel) {
            self.viewModel = viewModel
        }
        
        func didCapture(_ sampleBuffer: CMSampleBuffer) {
            Task { await viewModel.processCameraFrame(sampleBuffer) }
        }
    }
}

// MARK: - Camera Preview

protocol CameraPreviewDelegate: AnyObject {
    func didCapture(_ sampleBuffer: CMSampleBuffer)
}

class CameraPreviewView: UIView, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var delegate: CameraPreviewDelegate?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    func startSession() {
        session.sessionPreset = .high
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        
        session.addInput(input)
        
        let output = AVCaptureVideoDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera"))
        session.addOutput(output)
        
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer?.videoGravity = .resizeAspectFill
        previewLayer?.frame = bounds
        layer.addSublayer(previewLayer!)
        
        DispatchQueue.global().async { self.session.startRunning() }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.didCapture(sampleBuffer)
    }
}

// MARK: - ViewModel

@MainActor
class UnifiedScanViewModel: ObservableObject {
    @Published var isRecording = false
    @Published var isProcessing = false
    @Published var frameCount = 0
    @Published var progress: Float = 0
    @Published var stage = ""
    
    let capability = DeviceCapabilityService.shared.capability
    
    private let captureService = PhotogrammetryCaptureService()
    private let pipeline = ReconstructionPipelineFactory.createDefaultPipeline()
    private var cancellables = Set<AnyCancellable>()
    
    var onComplete: ((ReconstructionData) -> Void)?
    
    func setup() {
        Task {
            for await (prog, stg) in await pipeline.progressPublisher.values {
                self.progress = prog
                self.stage = stg
            }
        }
    }
    
    func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            Task { await captureService.startCapture() }
        }
    }
    
    func cancel() {
        isRecording = false
        Task { _ = await captureService.stopCapture() }
    }
    
    func processARFrame(_ frame: ARFrame) async {
        guard isRecording else { return }
        await captureService.processARFrame(frame)
        frameCount = await captureService.frameCount
    }
    
    func processCameraFrame(_ buffer: CMSampleBuffer) async {
        guard isRecording else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        await captureService.processCameraFrame(buffer, timestamp: timestamp)
        frameCount = await captureService.frameCount
    }
    
    func processAndExport() async {
        isRecording = false
        isProcessing = true
        
        let frames = await captureService.stopCapture()
        
        // Export frames to disk
        let exportDir = FileManager.default.temporaryDirectory.appendingPathComponent("rscan_\(UUID().uuidString)")
        
        do {
            let urls = try await captureService.exportFrames(to: exportDir)
            let result = try await pipeline.process(frames: frames, frameURLs: urls)
            onComplete?(result)
        } catch {
            print("Processing failed: \(error)")
        }
        
        isProcessing = false
    }
}

// MARK: - UI Components

struct RecordingIndicator: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack {
            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
                .opacity(isAnimating ? 0.3 : 1)
            Text("REC")
                .font(.caption.bold())
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever()) {
                isAnimating = true
            }
        }
    }
}

struct ProcessingOverlay: View {
    let progress: Float
    let stage: String
    
    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Text(stage)
                .font(.caption)
            Text("\(Int(progress * 100))%")
                .font(.headline)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding()
    }
}

struct ScanButtonStyle: ButtonStyle {
    let isPrimary: Bool
    var isRecording: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(isPrimary ? (isRecording ? .red : .blue) : .gray.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(25)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

// MARK: - Capability Extension

extension ScanCapability {
    var displayName: String {
        switch self {
        case .lidar: return "LiDAR Mode"
        case .arkit: return "Photogrammetry Mode"
        case .basic: return "Camera Mode"
        }
    }
}
