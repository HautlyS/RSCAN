# Room Segmentation

## Overview

Room segmentation divides a building scan into individual rooms for organized navigation and per-room processing.

## Approaches

### 1. RoomPlan Native (iOS)
Apple's RoomPlan already provides room-level segmentation via `CapturedStructure`:

```swift
// Each room is a separate CapturedRoom in the structure
let structure: CapturedStructure = try await structureBuilder.capturedStructure(from: rooms)

for room in structure.rooms {
    print("Room: \(room.identifier)")
    print("Walls: \(room.walls.count)")
    print("Doors: \(room.doors.count)")
    print("Windows: \(room.windows.count)")
}
```

### 2. Graph-Based Segmentation (Point Cloud)

For raw point clouds without RoomPlan metadata:

```rust
use petgraph::graph::UnGraph;
use std::collections::HashMap;

pub struct Room {
    pub id: usize,
    pub points: Vec<usize>,  // Indices into point cloud
    pub boundary: Vec<Point3<f32>>,
    pub doors: Vec<DoorOpening>,
}

pub struct DoorOpening {
    pub position: Point3<f32>,
    pub width: f32,
    pub height: f32,
    pub connects: [usize; 2],  // Room IDs
}

/// Segment rooms by detecting walls and openings
pub fn segment_rooms(cloud: &PointCloud, floor_height: f32) -> Vec<Room> {
    // 1. Extract floor slice (horizontal cross-section)
    let floor_slice = extract_slice(cloud, floor_height, floor_height + 0.3);
    
    // 2. Create 2D occupancy grid
    let grid = OccupancyGrid::from_points(&floor_slice, 0.05);
    
    // 3. Detect walls (occupied cells)
    let walls = grid.find_walls(min_thickness: 0.1);
    
    // 4. Find openings in walls (doors)
    let openings = detect_openings(&walls, min_width: 0.6, max_width: 1.2);
    
    // 5. Flood fill to find rooms
    let room_labels = flood_fill_rooms(&grid, &walls, &openings);
    
    // 6. Build room structures
    build_rooms(cloud, &room_labels, &openings)
}
```

### 3. Occupancy Grid + Flood Fill

```rust
pub struct OccupancyGrid {
    cells: Vec<Vec<CellState>>,
    resolution: f32,
    origin: Point2<f32>,
}

#[derive(Clone, Copy, PartialEq)]
pub enum CellState {
    Empty,
    Occupied,
    Wall,
    Opening,
}

impl OccupancyGrid {
    pub fn flood_fill_rooms(&self) -> Vec<Vec<(usize, usize)>> {
        let mut visited = vec![vec![false; self.cells[0].len()]; self.cells.len()];
        let mut rooms = Vec::new();
        
        for y in 0..self.cells.len() {
            for x in 0..self.cells[0].len() {
                if self.cells[y][x] == CellState::Empty && !visited[y][x] {
                    let room = self.flood_fill(x, y, &mut visited);
                    if room.len() > 100 { // Min room size
                        rooms.push(room);
                    }
                }
            }
        }
        rooms
    }
    
    fn flood_fill(&self, start_x: usize, start_y: usize, visited: &mut Vec<Vec<bool>>) -> Vec<(usize, usize)> {
        let mut stack = vec![(start_x, start_y)];
        let mut region = Vec::new();
        
        while let Some((x, y)) = stack.pop() {
            if visited[y][x] { continue; }
            if self.cells[y][x] == CellState::Wall { continue; }
            
            visited[y][x] = true;
            region.push((x, y));
            
            // 4-connected neighbors
            if x > 0 { stack.push((x - 1, y)); }
            if x < self.cells[0].len() - 1 { stack.push((x + 1, y)); }
            if y > 0 { stack.push((x, y - 1)); }
            if y < self.cells.len() - 1 { stack.push((x, y + 1)); }
        }
        region
    }
}
```

### 4. Door/Opening Detection

```rust
pub fn detect_openings(walls: &[WallSegment], cloud: &PointCloud) -> Vec<DoorOpening> {
    let mut openings = Vec::new();
    
    for wall in walls {
        // Sample points along wall
        let wall_points = cloud.points_near_line(&wall.start, &wall.end, 0.2);
        
        // Find vertical gaps (doors/windows)
        let height_profile = compute_height_profile(&wall_points, wall);
        let gaps = find_gaps_in_profile(&height_profile, min_gap: 0.6);
        
        for gap in gaps {
            if gap.height > 1.8 && gap.height < 2.5 && gap.bottom < 0.1 {
                // Door
                openings.push(DoorOpening {
                    position: gap.center,
                    width: gap.width,
                    height: gap.height,
                    connects: [0, 0], // Filled later
                });
            }
        }
    }
    openings
}
```

### 5. Semantic Segmentation (Neural)

For complex scenes, use PointNet++ or similar:

```rust
pub struct RoomSegmentationNet {
    session: ort::Session,
}

impl RoomSegmentationNet {
    /// Returns per-point room labels
    pub fn segment(&self, points: &[Point3<f32>]) -> Vec<usize> {
        let input = points_to_tensor(points);
        let outputs = self.session.run(ort::inputs![input].unwrap()).unwrap();
        
        // Output: [N, num_rooms] probabilities
        let probs: ndarray::ArrayView2<f32> = outputs[0].extract_tensor().unwrap();
        
        probs.rows().into_iter()
            .map(|row| row.iter().enumerate().max_by(|a, b| a.1.partial_cmp(b.1).unwrap()).unwrap().0)
            .collect()
    }
}
```

## Room Data Structure

```rust
pub struct SegmentedBuilding {
    pub rooms: Vec<Room>,
    pub connections: Vec<RoomConnection>,
    pub exterior: ExteriorScan,
}

pub struct RoomConnection {
    pub room_a: usize,
    pub room_b: usize,
    pub connection_type: ConnectionType,
    pub opening: DoorOpening,
}

pub enum ConnectionType {
    Door,
    Archway,
    Open,
}

impl SegmentedBuilding {
    pub fn room_graph(&self) -> UnGraph<usize, ConnectionType> {
        let mut graph = UnGraph::new_undirected();
        let nodes: Vec<_> = self.rooms.iter().map(|r| graph.add_node(r.id)).collect();
        
        for conn in &self.connections {
            graph.add_edge(nodes[conn.room_a], nodes[conn.room_b], conn.connection_type.clone());
        }
        graph
    }
    
    pub fn export_per_room(&self, base_path: &Path) -> std::io::Result<()> {
        for room in &self.rooms {
            let path = base_path.join(format!("room_{}.ply", room.id));
            room.export_ply(&path)?;
        }
        Ok(())
    }
}
```

## Integration with RoomPlan

```swift
// Convert RoomPlan CapturedRoom to exportable format
extension CapturedRoom {
    func toSegmentedRoom() -> SegmentedRoom {
        SegmentedRoom(
            id: identifier.uuidString,
            walls: walls.map { $0.dimensions },
            doors: doors.map { door in
                DoorInfo(
                    position: door.transform.position,
                    dimensions: door.dimensions
                )
            },
            windows: windows.map { $0.dimensions },
            objects: objects.map { $0.category.rawValue }
        )
    }
}
```

## Algorithm Comparison

| Method | Accuracy | Speed | Requirements |
|--------|----------|-------|--------------|
| RoomPlan Native | High | Real-time | iOS 16+, LiDAR |
| Flood Fill | Medium | Fast | Clean floor plan |
| Graph-Based | High | Medium | Wall detection |
| Neural (PointNet++) | High | Slow | Training data |
