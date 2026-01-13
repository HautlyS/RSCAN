# Point Cloud Processing & Mesh Reconstruction

## Overview

Processing pipeline for converting raw LiDAR point clouds into clean, watertight meshes.

## Pipeline Stages

```
Raw Points → Filter → Downsample → Normal Estimation → Surface Reconstruction → Mesh
```

## 1. Point Cloud Filtering (Rust)

```rust
use nalgebra::{Point3, Vector3};

pub struct PointCloud {
    pub points: Vec<Point3<f32>>,
    pub normals: Vec<Vector3<f32>>,
    pub colors: Vec<[u8; 3]>,
}

impl PointCloud {
    /// Statistical Outlier Removal
    pub fn remove_outliers(&mut self, k: usize, std_ratio: f32) {
        let kdtree = self.build_kdtree();
        let mut distances: Vec<f32> = Vec::with_capacity(self.points.len());
        
        for p in &self.points {
            let neighbors = kdtree.nearest(p, k + 1);
            let mean_dist: f32 = neighbors.iter().skip(1).map(|(d, _)| *d).sum::<f32>() / k as f32;
            distances.push(mean_dist);
        }
        
        let mean = distances.iter().sum::<f32>() / distances.len() as f32;
        let std = (distances.iter().map(|d| (d - mean).powi(2)).sum::<f32>() / distances.len() as f32).sqrt();
        let threshold = mean + std_ratio * std;
        
        let mask: Vec<bool> = distances.iter().map(|d| *d < threshold).collect();
        self.filter_by_mask(&mask);
    }
    
    /// Voxel Downsampling
    pub fn voxel_downsample(&mut self, voxel_size: f32) {
        use std::collections::HashMap;
        let mut voxels: HashMap<(i32, i32, i32), (Point3<f32>, usize)> = HashMap::new();
        
        for p in &self.points {
            let key = (
                (p.x / voxel_size).floor() as i32,
                (p.y / voxel_size).floor() as i32,
                (p.z / voxel_size).floor() as i32,
            );
            voxels.entry(key)
                .and_modify(|(sum, count)| { *sum += p.coords; *count += 1; })
                .or_insert((p.clone(), 1));
        }
        
        self.points = voxels.values()
            .map(|(sum, count)| Point3::from(sum.coords / *count as f32))
            .collect();
    }
}
```

## 2. Normal Estimation

```rust
impl PointCloud {
    /// Estimate normals using PCA on k-nearest neighbors
    pub fn estimate_normals(&mut self, k: usize) {
        let kdtree = self.build_kdtree();
        self.normals = Vec::with_capacity(self.points.len());
        
        for p in &self.points {
            let neighbors = kdtree.nearest(p, k);
            let centroid = neighbors.iter()
                .map(|(_, idx)| &self.points[*idx])
                .fold(Vector3::zeros(), |acc, p| acc + p.coords) / k as f32;
            
            // Covariance matrix
            let mut cov = nalgebra::Matrix3::zeros();
            for (_, idx) in &neighbors {
                let d = self.points[*idx].coords - centroid;
                cov += d * d.transpose();
            }
            
            // Smallest eigenvector = normal
            let eigen = cov.symmetric_eigen();
            let min_idx = eigen.eigenvalues.imin();
            let normal = eigen.eigenvectors.column(min_idx).normalize();
            self.normals.push(normal.into());
        }
    }
}
```

## 3. Surface Reconstruction Algorithms

### Poisson Surface Reconstruction
Best for watertight meshes from dense, oriented point clouds.

```rust
pub struct PoissonReconstructor {
    pub depth: u32,      // Octree depth (8-12 typical)
    pub scale: f32,      // Bounding box scale
}

impl PoissonReconstructor {
    pub fn reconstruct(&self, cloud: &PointCloud) -> Mesh {
        // 1. Build octree from points
        let octree = Octree::from_points(&cloud.points, self.depth);
        
        // 2. Compute vector field from normals
        let vector_field = self.compute_vector_field(&octree, cloud);
        
        // 3. Solve Poisson equation: ∇²χ = ∇·V
        let indicator = self.solve_poisson(&octree, &vector_field);
        
        // 4. Extract isosurface using Marching Cubes
        marching_cubes(&indicator, 0.0)
    }
}
```

### Ball Pivoting Algorithm
Better for preserving sharp features.

```rust
pub fn ball_pivoting(cloud: &PointCloud, radii: &[f32]) -> Mesh {
    let mut mesh = Mesh::new();
    let kdtree = cloud.build_kdtree();
    
    for radius in radii {
        let mut front = find_seed_triangle(cloud, &kdtree, *radius);
        
        while let Some(edge) = front.pop_active_edge() {
            if let Some(point) = find_pivot_point(&edge, cloud, &kdtree, *radius) {
                let triangle = Triangle::new(edge.v1, edge.v2, point);
                mesh.add_triangle(triangle);
                front.update_edges(&triangle);
            }
        }
    }
    mesh
}
```

## 4. Mesh Data Structure

```rust
pub struct Mesh {
    pub vertices: Vec<Point3<f32>>,
    pub normals: Vec<Vector3<f32>>,
    pub indices: Vec<[u32; 3]>,  // Triangle indices
    pub uvs: Vec<[f32; 2]>,
}

impl Mesh {
    pub fn compute_vertex_normals(&mut self) {
        self.normals = vec![Vector3::zeros(); self.vertices.len()];
        
        for tri in &self.indices {
            let v0 = &self.vertices[tri[0] as usize];
            let v1 = &self.vertices[tri[1] as usize];
            let v2 = &self.vertices[tri[2] as usize];
            
            let normal = (v1 - v0).cross(&(v2 - v0));
            for &idx in tri {
                self.normals[idx as usize] += normal;
            }
        }
        
        for n in &mut self.normals {
            *n = n.normalize();
        }
    }
    
    pub fn export_obj(&self, path: &std::path::Path) -> std::io::Result<()> {
        use std::io::Write;
        let mut file = std::fs::File::create(path)?;
        
        for v in &self.vertices {
            writeln!(file, "v {} {} {}", v.x, v.y, v.z)?;
        }
        for n in &self.normals {
            writeln!(file, "vn {} {} {}", n.x, n.y, n.z)?;
        }
        for tri in &self.indices {
            writeln!(file, "f {}//{} {}//{} {}//{}",
                tri[0]+1, tri[0]+1, tri[1]+1, tri[1]+1, tri[2]+1, tri[2]+1)?;
        }
        Ok(())
    }
}
```

## 5. PLY Parser (Rust)

```rust
use std::io::{BufRead, BufReader};

pub fn parse_ply(path: &std::path::Path) -> Result<PointCloud, Box<dyn std::error::Error>> {
    let file = std::fs::File::open(path)?;
    let mut reader = BufReader::new(file);
    let mut line = String::new();
    let mut vertex_count = 0;
    
    // Parse header
    loop {
        line.clear();
        reader.read_line(&mut line)?;
        if line.starts_with("element vertex") {
            vertex_count = line.split_whitespace().nth(2).unwrap().parse()?;
        }
        if line.trim() == "end_header" { break; }
    }
    
    // Parse vertices
    let mut points = Vec::with_capacity(vertex_count);
    for _ in 0..vertex_count {
        line.clear();
        reader.read_line(&mut line)?;
        let vals: Vec<f32> = line.split_whitespace()
            .take(3)
            .map(|s| s.parse().unwrap())
            .collect();
        points.push(Point3::new(vals[0], vals[1], vals[2]));
    }
    
    Ok(PointCloud { points, normals: vec![], colors: vec![] })
}
```

## Algorithm Comparison

| Algorithm | Watertight | Sharp Features | Speed | Memory |
|-----------|------------|----------------|-------|--------|
| Poisson | ✅ Yes | ❌ Smoothed | Medium | High |
| Ball Pivoting | ❌ No | ✅ Preserved | Fast | Low |
| Marching Cubes | ✅ Yes | ❌ Smoothed | Fast | Medium |
| Alpha Shapes | ❌ No | ✅ Preserved | Fast | Low |

## Rust Crates

```toml
[dependencies]
nalgebra = "0.32"
rayon = "1.8"           # Parallel processing
kiddo = "4.2"           # KD-tree
ply-rs = "0.1"          # PLY parsing
```
