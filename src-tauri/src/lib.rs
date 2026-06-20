pub mod commands;
pub mod detdoc;

pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            commands::ping,
            commands::project_status,
            commands::detdoc_init,
            commands::docs_list,
            commands::docs_read,
            commands::docs_write,
            commands::runs_list,
            commands::run_start_fake,
            commands::apply_saved_run_command,
            commands::pi_health_check,
        ])
        .run(tauri::generate_context!())
        .expect("failed to run DetDoc Tauri app");
}
