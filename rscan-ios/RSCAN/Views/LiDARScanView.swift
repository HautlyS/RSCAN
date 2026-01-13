import SwiftUI
import ARKit

struct LiDARScanView: View {
    @ObservedObject var scanVM: ScanViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            ARViewRepresentable(scanVM: scanVM)
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Text("Points: \(scanVM.pointCount)")
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    Spacer()
                }
                .padding()
                
                Spacer()
                
                HStack(spacing: 20) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                    Button("Save") {
                        scanVM.savePointCloud()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
    }
}

struct ARViewRepresentable: UIViewRepresentable {
    @ObservedObject var scanVM: ScanViewModel
    
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session.delegate = context.coordinator
        
        let config = ARWorldTrackingConfiguration()
        config.sceneReconstruction = .meshWithClassification
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        view.session.run(config)
        
        return view
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(scanVM: scanVM)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        let scanVM: ScanViewModel
        
        init(scanVM: ScanViewModel) {
            self.scanVM = scanVM
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let depthMap = frame.sceneDepth?.depthMap else { return }
            scanVM.processDepthFrame(depthMap, camera: frame.camera)
        }
    }
}
