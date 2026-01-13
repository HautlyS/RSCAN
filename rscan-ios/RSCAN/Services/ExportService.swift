import Foundation
import RoomPlan

class ExportService {
    static let shared = ExportService()
    
    private init() {}
    
    func exportRoom(_ room: CapturedRoom, format: ExportFormat) async throws -> URL {
        let filename = "room_\(UUID().uuidString.prefix(8)).\(format.ext)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        
        switch format {
        case .usdz:
            try room.export(to: url, exportOptions: .mesh)
        case .ply:
            // Would need mesh data extraction - RoomPlan exports USD natively
            try room.export(to: url, exportOptions: .mesh)
        }
        
        return url
    }
    
    func exportStructure(_ structure: CapturedStructure) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("building.usdz")
        try structure.export(to: url, metadataURL: nil, modelProvider: nil, exportOptions: .mesh)
        return url
    }
    
    func exportPointCloud(_ points: [SIMD3<Float>], colors: [SIMD3<UInt8>]? = nil) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pointcloud.ply")
        
        var ply = "ply\nformat ascii 1.0\n"
        ply += "element vertex \(points.count)\n"
        ply += "property float x\nproperty float y\nproperty float z\n"
        
        if colors != nil {
            ply += "property uchar red\nproperty uchar green\nproperty uchar blue\n"
        }
        ply += "end_header\n"
        
        for (i, p) in points.enumerated() {
            if let colors = colors, i < colors.count {
                let c = colors[i]
                ply += "\(p.x) \(p.y) \(p.z) \(c.x) \(c.y) \(c.z)\n"
            } else {
                ply += "\(p.x) \(p.y) \(p.z)\n"
            }
        }
        
        try ply.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    enum ExportFormat {
        case usdz, ply
        
        var ext: String {
            switch self {
            case .usdz: return "usdz"
            case .ply: return "ply"
            }
        }
    }
}
