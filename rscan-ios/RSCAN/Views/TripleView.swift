import SwiftUI
import SceneKit

struct TripleView: View {
    @ObservedObject var viewModel: TripleViewModel
    @State private var selectedTab = 0
    
    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                // Landscape: side by side
                HStack(spacing: 1) {
                    PointCloudPanel(viewModel: viewModel)
                    MeshPanel(viewModel: viewModel)
                    FloorPlanPanel(viewModel: viewModel)
                }
            } else {
                // Portrait: tabbed
                VStack(spacing: 0) {
                    Picker("View", selection: $selectedTab) {
                        Text("Points").tag(0)
                        Text("Mesh").tag(1)
                        Text("Floor").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(8)
                    
                    TabView(selection: $selectedTab) {
                        PointCloudPanel(viewModel: viewModel).tag(0)
                        MeshPanel(viewModel: viewModel).tag(1)
                        FloorPlanPanel(viewModel: viewModel).tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
        }
        .background(Color.black)
    }
}

// MARK: - Point Cloud Panel

struct PointCloudPanel: View {
    @ObservedObject var viewModel: TripleViewModel
    
    var body: some View {
        ZStack {
            SceneKitPointCloudView(points: viewModel.points, colors: viewModel.colors)
            
            VStack {
                PanelHeader(title: "Point Cloud", count: "\(viewModel.points.count) pts")
                Spacer()
            }
        }
    }
}

// MARK: - Mesh Panel

struct MeshPanel: View {
    @ObservedObject var viewModel: TripleViewModel
    
    var body: some View {
        ZStack {
            SceneKitMeshView(mesh: viewModel.mesh)
            
            VStack {
                PanelHeader(title: "3D Mesh", count: viewModel.mesh != nil ? "\(viewModel.mesh!.indices.count / 3) tris" : "—")
                Spacer()
            }
        }
    }
}

// MARK: - Floor Plan Panel

struct FloorPlanPanel: View {
    @ObservedObject var viewModel: TripleViewModel
    
    var body: some View {
        ZStack {
            Canvas { context, size in
                let scale = min(size.width, size.height) / (viewModel.floorPlanBounds + 1)
                let offset = CGPoint(x: size.width / 2, y: size.height / 2)
                
                // Draw walls
                for wall in viewModel.walls {
                    var path = Path()
                    path.move(to: CGPoint(
                        x: offset.x + CGFloat(wall.start.x) * scale,
                        y: offset.y + CGFloat(wall.start.y) * scale
                    ))
                    path.addLine(to: CGPoint(
                        x: offset.x + CGFloat(wall.end.x) * scale,
                        y: offset.y + CGFloat(wall.end.y) * scale
                    ))
                    context.stroke(path, with: .color(.white), lineWidth: 3)
                }
                
                // Draw doors
                for door in viewModel.doors {
                    let rect = CGRect(
                        x: offset.x + CGFloat(door.x) * scale - 5,
                        y: offset.y + CGFloat(door.y) * scale - 5,
                        width: 10, height: 10
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(.blue))
                }
                
                // Draw rooms
                for (i, room) in viewModel.roomCenters.enumerated() {
                    let pt = CGPoint(
                        x: offset.x + CGFloat(room.x) * scale,
                        y: offset.y + CGFloat(room.y) * scale
                    )
                    context.draw(Text("R\(i+1)").font(.caption).foregroundColor(.green), at: pt)
                }
            }
            
            VStack {
                PanelHeader(title: "Floor Plan", count: "\(viewModel.walls.count) walls")
                Spacer()
            }
        }
    }
}

// MARK: - Panel Header

struct PanelHeader: View {
    let title: String
    let count: String
    
    var body: some View {
        HStack {
            Text(title).font(.caption.bold())
            Spacer()
            Text(count).font(.caption2)
        }
        .padding(6)
        .background(.black.opacity(0.6))
        .foregroundColor(.white)
    }
}

// MARK: - SceneKit Views

struct SceneKitPointCloudView: UIViewRepresentable {
    let points: [SIMD3<Float>]
    let colors: [SIMD3<UInt8>]
    
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene()
        view.backgroundColor = .black
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        return view
    }
    
    func updateUIView(_ view: SCNView, context: Context) {
        view.scene?.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        
        guard !points.isEmpty else { return }
        
        let vertices = points.map { SCNVector3($0.x, $0.y, $0.z) }
        let source = SCNGeometrySource(vertices: vertices)
        
        let indices = Array(0..<Int32(points.count))
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        element.pointSize = 2
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 5
        
        let geometry = SCNGeometry(sources: [source], elements: [element])
        geometry.firstMaterial?.diffuse.contents = UIColor.cyan
        
        let node = SCNNode(geometry: geometry)
        view.scene?.rootNode.addChildNode(node)
        
        // Camera
        let camera = SCNCamera()
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 5, 10)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        view.scene?.rootNode.addChildNode(cameraNode)
    }
}

struct SceneKitMeshView: UIViewRepresentable {
    let mesh: MeshData?
    
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = SCNScene()
        view.backgroundColor = .black
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        return view
    }
    
    func updateUIView(_ view: SCNView, context: Context) {
        view.scene?.rootNode.childNodes.forEach { $0.removeFromParentNode() }
        
        guard let mesh = mesh, !mesh.vertices.isEmpty else { return }
        
        let vertices = mesh.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
        let normals = mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) }
        
        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: mesh.indices.map { Int32($0) }, primitiveType: .triangles)
        
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        geometry.firstMaterial?.diffuse.contents = UIColor.gray
        geometry.firstMaterial?.isDoubleSided = true
        
        let node = SCNNode(geometry: geometry)
        view.scene?.rootNode.addChildNode(node)
        
        let camera = SCNCamera()
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 5, 10)
        cameraNode.look(at: SCNVector3(0, 0, 0))
        view.scene?.rootNode.addChildNode(cameraNode)
    }
}

// MARK: - ViewModel

class TripleViewModel: ObservableObject {
    @Published var points: [SIMD3<Float>] = []
    @Published var colors: [SIMD3<UInt8>] = []
    @Published var mesh: MeshData?
    @Published var walls: [Wall2D] = []
    @Published var doors: [SIMD2<Float>] = []
    @Published var roomCenters: [SIMD2<Float>] = []
    @Published var floorPlanBounds: CGFloat = 10
    
    func load(from data: ReconstructionData) {
        points = data.pointCloud
        colors = data.colors
        mesh = data.mesh
        generateFloorPlan()
    }
    
    private func generateFloorPlan() {
        guard !points.isEmpty else { return }
        
        // Project points to XZ plane, detect walls
        let floorPoints = points.map { SIMD2($0.x, $0.z) }
        
        // Simple wall detection from point clusters
        walls = detectWalls(from: floorPoints)
        
        // Bounds
        let maxCoord = floorPoints.map { max(abs($0.x), abs($0.y)) }.max() ?? 10
        floorPlanBounds = CGFloat(maxCoord)
    }
    
    private func detectWalls(from points: [SIMD2<Float>]) -> [Wall2D] {
        // Simplified: create walls from point pairs at similar Y
        var walls: [Wall2D] = []
        let sorted = points.sorted { $0.y < $1.y }
        
        var i = 0
        while i < sorted.count - 1 {
            let start = sorted[i]
            var end = start
            
            // Find points on same "line"
            for j in (i+1)..<min(i+20, sorted.count) {
                if abs(sorted[j].y - start.y) < 0.3 {
                    end = sorted[j]
                }
            }
            
            if simd_distance(start, end) > 0.5 {
                walls.append(Wall2D(start: start, end: end))
            }
            i += 10
        }
        
        return walls
    }
}

struct Wall2D {
    let start: SIMD2<Float>
    let end: SIMD2<Float>
}
