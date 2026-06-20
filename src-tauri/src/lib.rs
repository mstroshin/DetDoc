pub mod commands;
pub mod detdoc;

pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![commands::ping])
        .run(tauri::generate_context!())
        .expect("failed to run DetDoc Tauri app");
}
