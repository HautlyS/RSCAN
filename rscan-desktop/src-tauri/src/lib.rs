mod point_cloud;
mod commands;

use commands::AppState;
use std::sync::Mutex;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .manage(AppState {
            cloud: Mutex::new(None),
            status: Mutex::new(Default::default()),
        })
        .invoke_handler(tauri::generate_handler![
            commands::load_point_cloud,
            commands::process_point_cloud,
            commands::get_processing_status,
        ])
        .run(tauri::generate_context!())
        .expect("error running tauri application");
}
