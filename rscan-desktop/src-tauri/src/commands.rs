use crate::point_cloud::PointCloud;
use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use tauri::State;

pub struct AppState {
    pub cloud: Mutex<Option<PointCloud>>,
    pub status: Mutex<ProcessingStatus>,
}

#[derive(Clone, Serialize, Deserialize, Default)]
pub struct ProcessingStatus {
    pub stage: String,
    pub progress: f32,
    pub point_count: usize,
}

#[derive(Serialize)]
pub struct LoadResult {
    pub point_count: usize,
    pub has_colors: bool,
    pub bounds: [[f32; 3]; 2],
}

#[tauri::command]
pub async fn load_point_cloud(path: String, state: State<'_, AppState>) -> Result<LoadResult, String> {
    let cloud = PointCloud::from_ply(std::path::Path::new(&path))?;
    
    let bounds = if cloud.points.is_empty() {
        [[0.0; 3], [0.0; 3]]
    } else {
        let mut min = cloud.points[0];
        let mut max = cloud.points[0];
        for p in &cloud.points {
            for i in 0..3 {
                min[i] = min[i].min(p[i]);
                max[i] = max[i].max(p[i]);
            }
        }
        [min, max]
    };
    
    let result = LoadResult {
        point_count: cloud.points.len(),
        has_colors: !cloud.colors.is_empty(),
        bounds,
    };
    
    *state.cloud.lock().unwrap() = Some(cloud);
    Ok(result)
}

#[derive(Deserialize)]
pub struct ProcessOptions {
    pub voxel_size: Option<f32>,
    pub remove_outliers: bool,
    pub outlier_k: Option<usize>,
    pub outlier_std: Option<f32>,
}

#[tauri::command]
pub async fn process_point_cloud(options: ProcessOptions, state: State<'_, AppState>) -> Result<usize, String> {
    let mut cloud_guard = state.cloud.lock().unwrap();
    let cloud = cloud_guard.as_mut().ok_or("No point cloud loaded")?;
    
    {
        let mut status = state.status.lock().unwrap();
        status.stage = "Processing".into();
        status.progress = 0.0;
    }
    
    if let Some(voxel_size) = options.voxel_size {
        cloud.voxel_downsample(voxel_size);
    }
    
    if options.remove_outliers {
        let k = options.outlier_k.unwrap_or(20);
        let std = options.outlier_std.unwrap_or(2.0);
        cloud.remove_outliers(k, std);
    }
    
    {
        let mut status = state.status.lock().unwrap();
        status.stage = "Complete".into();
        status.progress = 1.0;
        status.point_count = cloud.points.len();
    }
    
    Ok(cloud.points.len())
}

#[tauri::command]
pub fn get_processing_status(state: State<'_, AppState>) -> ProcessingStatus {
    state.status.lock().unwrap().clone()
}
