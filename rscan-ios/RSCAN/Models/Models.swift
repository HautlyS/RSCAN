import Foundation
import RoomPlan

struct ScannedRoom: Identifiable {
    let id = UUID()
    let name: String
    let wallCount: Int
    let doorCount: Int
    let windowCount: Int
    let area: Float
    
    init(from room: CapturedRoom, index: Int) {
        self.name = "Room \(index + 1)"
        self.wallCount = room.walls.count
        self.doorCount = room.doors.count
        self.windowCount = room.windows.count
        
        // Estimate area from walls
        var totalArea: Float = 0
        for wall in room.walls {
            totalArea += wall.dimensions.x * wall.dimensions.y
        }
        self.area = totalArea / 4 // Rough floor area estimate
    }
}

struct PointCloudData {
    var points: [SIMD3<Float>]
    var colors: [SIMD3<UInt8>]
    
    init() {
        points = []
        colors = []
    }
    
    mutating func append(_ point: SIMD3<Float>, color: SIMD3<UInt8> = SIMD3(128, 128, 128)) {
        points.append(point)
        colors.append(color)
    }
}

struct BuildingScan {
    var rooms: [ScannedRoom]
    var exterior: PointCloudData
    var roof: PointCloudData
    
    var totalRooms: Int { rooms.count }
}
