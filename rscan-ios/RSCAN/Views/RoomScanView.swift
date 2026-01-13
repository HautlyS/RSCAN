import SwiftUI
import RoomPlan

struct RoomScanView: View {
    @ObservedObject var scanVM: ScanViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            RoomCaptureViewRepresentable(scanVM: scanVM)
                .ignoresSafeArea()
            
            VStack {
                Spacer()
                HStack(spacing: 20) {
                    Button("Cancel") {
                        scanVM.cancelScan()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Done") {
                        scanVM.finishScan()
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

struct RoomCaptureViewRepresentable: UIViewRepresentable {
    @ObservedObject var scanVM: ScanViewModel
    
    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView()
        view.captureSession.delegate = context.coordinator
        view.delegate = context.coordinator
        return view
    }
    
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(scanVM: scanVM)
    }
    
    class Coordinator: NSObject, RoomCaptureSessionDelegate, RoomCaptureViewDelegate {
        let scanVM: ScanViewModel
        var capturedRoomData: CapturedRoomData?
        
        init(scanVM: ScanViewModel) {
            self.scanVM = scanVM
            super.init()
        }
        
        func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
            capturedRoomData = data
            if let data = capturedRoomData {
                scanVM.processCapturedData(data)
            }
        }
        
        func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: Error?) -> Bool {
            true
        }
        
        func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
            scanVM.addRoom(processedResult)
        }
    }
}
