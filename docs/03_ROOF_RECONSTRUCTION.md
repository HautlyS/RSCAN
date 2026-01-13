# Roof Reconstruction with Missing Piece Completion

## Overview

Roof reconstruction from aerial/ground scans is challenging due to:
- Occlusions from trees, neighboring buildings
- Sparse data from limited drone coverage
- Complex roof geometries (dormers, chimneys, valleys)

## Approach: Hybrid Primitive Fitting + Neural Completion

```
Sparse Points → Plane Detection → Primitive Fitting → Gap Detection → Neural Completion → Final Mesh
```

## 1. RANSAC Plane Detection

```rust
use nalgebra::{Point3, Vector3};
use rand::seq::SliceRandom;

pub struct Plane {
    pub normal: Vector3<f32>,
    pub d: f32,
    pub inliers: Vec<usize>,
}

pub fn ransac_planes(points: &[Point3<f32>], threshold: f32, iterations: usize) -> Vec<Plane> {
    let mut planes = Vec::new();
    let mut remaining: Vec<usize> = (0..points.len()).collect();
    let mut rng = rand::thread_rng();
    
    while remaining.len() > 100 {
        let mut best_plane: Option<Plane> = None;
        let mut best_count = 0;
        
        for _ in 0..iterations {
            // Sample 3 random points
            let sample: Vec<_> = remaining.choose_multiple(&mut rng, 3).copied().collect();
            let p0 = &points[sample[0]];
            let p1 = &points[sample[1]];
            let p2 = &points[sample[2]];
            
            let v1 = p1 - p0;
            let v2 = p2 - p0;
            let normal = v1.cross(&v2).normalize();
            let d = -normal.dot(&p0.coords);
            
            // Count inliers
            let inliers: Vec<usize> = remaining.iter()
                .filter(|&&i| (normal.dot(&points[i].coords) + d).abs() < threshold)
                .copied()
                .collect();
            
            if inliers.len() > best_count {
                best_count = inliers.len();
                best_plane = Some(Plane { normal, d, inliers });
            }
        }
        
        if let Some(plane) = best_plane {
            if plane.inliers.len() < 50 { break; }
            remaining.retain(|i| !plane.inliers.contains(i));
            planes.push(plane);
        } else { break; }
    }
    planes
}
```

## 2. Roof Primitive Types

```rust
pub enum RoofPrimitive {
    Flat { height: f32, boundary: Vec<Point3<f32>> },
    Gable { ridge: Line3, slope: f32, boundary: Vec<Point3<f32>> },
    Hip { apex: Point3<f32>, slopes: Vec<f32>, boundary: Vec<Point3<f32>> },
    Shed { direction: Vector3<f32>, slope: f32, boundary: Vec<Point3<f32>> },
}

pub struct Line3 {
    pub start: Point3<f32>,
    pub end: Point3<f32>,
}

impl RoofPrimitive {
    pub fn fit_to_planes(planes: &[Plane], footprint: &[Point3<f32>]) -> Self {
        if planes.len() == 1 {
            let slope = planes[0].normal.dot(&Vector3::z()).acos();
            if slope < 0.1 {
                return RoofPrimitive::Flat { 
                    height: -planes[0].d / planes[0].normal.z,
                    boundary: footprint.to_vec(),
                };
            }
            return RoofPrimitive::Shed {
                direction: Vector3::new(planes[0].normal.x, planes[0].normal.y, 0.0).normalize(),
                slope,
                boundary: footprint.to_vec(),
            };
        }
        
        if planes.len() == 2 {
            // Find ridge line (intersection of two planes)
            let ridge = plane_intersection(&planes[0], &planes[1]);
            let slope = (planes[0].normal.dot(&Vector3::z()).acos() 
                       + planes[1].normal.dot(&Vector3::z()).acos()) / 2.0;
            return RoofPrimitive::Gable { ridge, slope, boundary: footprint.to_vec() };
        }
        
        // 4+ planes = hip roof
        let apex = find_apex(&planes);
        let slopes = planes.iter().map(|p| p.normal.dot(&Vector3::z()).acos()).collect();
        RoofPrimitive::Hip { apex, slopes, boundary: footprint.to_vec() }
    }
}
```

## 3. Gap Detection

```rust
pub struct RoofGap {
    pub boundary: Vec<Point3<f32>>,
    pub area: f32,
    pub adjacent_planes: Vec<usize>,
}

pub fn detect_gaps(planes: &[Plane], footprint: &[Point3<f32>], grid_size: f32) -> Vec<RoofGap> {
    let bounds = compute_bounds(footprint);
    let mut coverage = Grid2D::new(bounds, grid_size);
    
    // Mark covered cells
    for plane in planes {
        for &idx in &plane.inliers {
            coverage.mark_covered(idx);
        }
    }
    
    // Find connected uncovered regions
    let uncovered_regions = coverage.find_connected_uncovered();
    
    uncovered_regions.into_iter()
        .filter(|region| region.area() > 0.5) // Min 0.5 m²
        .map(|region| RoofGap {
            boundary: region.boundary(),
            area: region.area(),
            adjacent_planes: find_adjacent_planes(&region, planes),
        })
        .collect()
}
```

## 4. Neural Completion (Point Cloud)

Using a PCN-style (Point Completion Network) approach:

```rust
// Inference wrapper for ONNX model
pub struct PointCompletionNet {
    session: ort::Session,
}

impl PointCompletionNet {
    pub fn load(model_path: &str) -> Result<Self, ort::Error> {
        let session = ort::Session::builder()?
            .with_model_from_file(model_path)?;
        Ok(Self { session })
    }
    
    pub fn complete(&self, partial: &[Point3<f32>], num_output: usize) -> Vec<Point3<f32>> {
        // Normalize input to unit sphere
        let (normalized, centroid, scale) = normalize_points(partial);
        
        // Run inference
        let input = ndarray::Array2::from_shape_vec(
            (partial.len(), 3),
            normalized.iter().flat_map(|p| [p.x, p.y, p.z]).collect()
        ).unwrap();
        
        let outputs = self.session.run(ort::inputs![input].unwrap()).unwrap();
        let completed: ndarray::ArrayView2<f32> = outputs[0].extract_tensor().unwrap();
        
        // Denormalize output
        completed.rows().into_iter()
            .map(|row| Point3::new(
                row[0] * scale + centroid.x,
                row[1] * scale + centroid.y,
                row[2] * scale + centroid.z,
            ))
            .collect()
    }
}
```

## 5. Geometric Completion (Fallback)

When neural completion isn't available, use geometric interpolation:

```rust
pub fn geometric_fill_gap(gap: &RoofGap, planes: &[Plane]) -> Vec<Point3<f32>> {
    let mut filled = Vec::new();
    
    // Interpolate height from adjacent planes
    for point in sample_grid(&gap.boundary, 0.1) {
        let mut weighted_height = 0.0;
        let mut total_weight = 0.0;
        
        for &plane_idx in &gap.adjacent_planes {
            let plane = &planes[plane_idx];
            let dist = distance_to_plane_boundary(&point, plane);
            let weight = 1.0 / (dist + 0.01);
            let height = -(plane.normal.x * point.x + plane.normal.y * point.y + plane.d) / plane.normal.z;
            
            weighted_height += height * weight;
            total_weight += weight;
        }
        
        filled.push(Point3::new(point.x, point.y, weighted_height / total_weight));
    }
    filled
}
```

## 6. RoofDiffusion Approach (State-of-Art)

Based on the 2024 paper, diffusion models can handle extreme sparsity:

```rust
// Conceptual - actual implementation requires PyTorch/ONNX
pub struct RoofDiffusion {
    denoiser: DiffusionModel,
    footprint_encoder: FootprintEncoder,
}

impl RoofDiffusion {
    /// Handles up to 99% point sparsity and 80% area occlusion
    pub fn complete_roof(&self, 
        sparse_points: &[Point3<f32>], 
        footprint: &[Point3<f32>],
        num_steps: usize
    ) -> HeightMap {
        // Encode footprint as conditioning
        let footprint_embedding = self.footprint_encoder.encode(footprint);
        
        // Initialize with sparse height map
        let mut height_map = HeightMap::from_sparse(sparse_points, footprint);
        
        // Iterative denoising
        for t in (0..num_steps).rev() {
            let noise_pred = self.denoiser.predict(&height_map, t, &footprint_embedding);
            height_map = height_map.denoise_step(noise_pred, t);
        }
        
        height_map
    }
}
```

## Pipeline Integration

```rust
pub fn reconstruct_roof(
    points: &[Point3<f32>],
    footprint: &[Point3<f32>],
    completion_model: Option<&PointCompletionNet>,
) -> Mesh {
    // 1. Detect roof planes
    let planes = ransac_planes(points, 0.05, 1000);
    
    // 2. Fit primitives
    let primitive = RoofPrimitive::fit_to_planes(&planes, footprint);
    
    // 3. Detect gaps
    let gaps = detect_gaps(&planes, footprint, 0.1);
    
    // 4. Fill gaps
    let mut all_points = points.to_vec();
    for gap in &gaps {
        let filled = match completion_model {
            Some(model) => model.complete(&extract_gap_context(&gap, points), 2048),
            None => geometric_fill_gap(gap, &planes),
        };
        all_points.extend(filled);
    }
    
    // 5. Final mesh reconstruction
    poisson_reconstruct(&all_points)
}
```

## References

- [RoofDiffusion](https://arxiv.org/abs/2404.09290) - Diffusion for roof completion
- [PCN](https://arxiv.org/abs/1808.00671) - Point Completion Network
- [Building Reconstruction from LiDAR](https://www.mdpi.com/2072-4292/14/9/2254)
