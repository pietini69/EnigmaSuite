#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod i18n;
mod models;
mod services;
mod ui;

use ui::EnigmaSuiteApp;

fn main() -> eframe::Result<()> {
    env_logger::init();

    let icon_bytes = include_bytes!("../assets/icon.png");
    let icon_data = eframe::icon_data::from_png_bytes(icon_bytes).ok();

    let mut viewport = eframe::egui::ViewportBuilder::default()
        .with_title("EnigmaSuite V2")
        .with_inner_size([1120.0, 750.0])
        .with_min_inner_size([880.0, 550.0]);

    if let Some(icon) = icon_data {
        viewport = viewport.with_icon(icon);
    }

    let native_options = eframe::NativeOptions {
        viewport,
        ..Default::default()
    };

    eframe::run_native(
        "EnigmaSuite",
        native_options,
        Box::new(|_cc| Ok(Box::new(EnigmaSuiteApp::default()))),
    )
}
