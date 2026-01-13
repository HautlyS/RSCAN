use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Clone, Serialize, Deserialize)]
pub struct PointCloud {
    pub points: Vec<[f32; 3]>,
    pub colors: Vec<[u8; 3]>,
    pub normals: Vec<[f32; 3]>,
}

impl PointCloud {
    pub fn new() -> Self {
        Self {
            points: vec![],
            colors: vec![],
            normals: vec![],
        }
    }

    pub fn from_ply(path: &std::path::Path) -> Result<Self, String> {
        use std::io::{BufRead, BufReader};
        let file = std::fs::File::open(path).map_err(|e| e.to_string())?;
        let mut reader = BufReader::new(file);
        let mut line = String::new();
        let mut vertex_count = 0;
        let mut has_color = false;

        // Parse header
        loop {
            line.clear();
            reader.read_line(&mut line).map_err(|e| e.to_string())?;
            if line.starts_with("element vertex") {
                vertex_count = line.split_whitespace().nth(2).unwrap().parse().unwrap();
            }
            if line.contains("red") {
                has_color = true;
            }
            if line.trim() == "end_header" {
                break;
            }
        }

        let mut cloud = PointCloud::new();
        for _ in 0..vertex_count {
            line.clear();
            reader.read_line(&mut line).map_err(|e| e.to_string())?;
            let vals: Vec<&str> = line.split_whitespace().collect();

            cloud.points.push([
                vals[0].parse().unwrap(),
                vals[1].parse().unwrap(),
                vals[2].parse().unwrap(),
            ]);

            if has_color && vals.len() >= 6 {
                cloud.colors.push([
                    vals[3].parse().unwrap(),
                    vals[4].parse().unwrap(),
                    vals[5].parse().unwrap(),
                ]);
            }
        }
        Ok(cloud)
    }

    pub fn voxel_downsample(&mut self, voxel_size: f32) {
        let mut voxels: HashMap<(i32, i32, i32), (usize, [f32; 3])> = HashMap::new();

        for (i, p) in self.points.iter().enumerate() {
            let key = (
                (p[0] / voxel_size).floor() as i32,
                (p[1] / voxel_size).floor() as i32,
                (p[2] / voxel_size).floor() as i32,
            );
            voxels.entry(key).or_insert((i, *p));
        }

        let indices: Vec<usize> = voxels.values().map(|(i, _)| *i).collect();
        self.points = indices.iter().map(|&i| self.points[i]).collect();
        if !self.colors.is_empty() {
            self.colors = indices.iter().map(|&i| self.colors[i]).collect();
        }
    }

    pub fn remove_outliers(&mut self, k: usize, std_ratio: f32) {
        // Simplified: remove points far from mean
        if self.points.len() < k {
            return;
        }

        let mean: [f32; 3] = [
            self.points.iter().map(|p| p[0]).sum::<f32>() / self.points.len() as f32,
            self.points.iter().map(|p| p[1]).sum::<f32>() / self.points.len() as f32,
            self.points.iter().map(|p| p[2]).sum::<f32>() / self.points.len() as f32,
        ];

        let distances: Vec<f32> = self
            .points
            .iter()
            .map(|p| {
                ((p[0] - mean[0]).powi(2) + (p[1] - mean[1]).powi(2) + (p[2] - mean[2]).powi(2))
                    .sqrt()
            })
            .collect();

        let mean_dist = distances.iter().sum::<f32>() / distances.len() as f32;
        let std = (distances
            .iter()
            .map(|d| (d - mean_dist).powi(2))
            .sum::<f32>()
            / distances.len() as f32)
            .sqrt();
        let threshold = mean_dist + std_ratio * std;

        let mask: Vec<bool> = distances.iter().map(|d| *d < threshold).collect();
        self.points = self
            .points
            .iter()
            .zip(&mask)
            .filter(|(_, &m)| m)
            .map(|(p, _)| *p)
            .collect();
        if !self.colors.is_empty() {
            self.colors = self
                .colors
                .iter()
                .zip(&mask)
                .filter(|(_, &m)| m)
                .map(|(c, _)| *c)
                .collect();
        }
    }
}
