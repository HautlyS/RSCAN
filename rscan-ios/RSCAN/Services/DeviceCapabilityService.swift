import ARKit
import RoomPlan

enum ScanCapability {
    case lidar       // Full RoomPlan + depth
    case arkit       // ARKit only (photogrammetry)
    case basic       // Camera only (no AR)
}

class DeviceCapabilityService {
    static let shared = DeviceCapabilityService()
    
    private init() {}
    
    var capability: ScanCapability {
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            return .lidar
        } else if ARWorldTrackingConfiguration.isSupported {
            return .arkit
        }
        return .basic
    }
    
    var hasLiDAR: Bool { capability == .lidar }
    var supportsRoomPlan: Bool { hasLiDAR && isRoomPlanSupported }
    
    private var isRoomPlanSupported: Bool {
        if #available(iOS 16.0, *) {
            return RoomCaptureSession.isSupported
        }
        return false
    }
    
    var recommendedMode: String {
        switch capability {
        case .lidar: return "LiDAR + RoomPlan"
        case .arkit: return "Photogrammetry (Video)"
        case .basic: return "Photo Capture"
        }
    }
}
