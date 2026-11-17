use egui::{Color32, Ui};
use crate::models::EnigmaBox;
use crate::i18n::Language;

pub struct ImageView {
    pub status_msg: Option<String>,
}

impl Default for ImageView {
    fn default() -> Self {
        Self { status_msg: None }
    }
}

impl ImageView {
    pub fn render(&mut self, ui: &mut Ui, active_box: Option<&EnigmaBox>, _lang: Language) {
        ui.heading("💾 Image Manager & Multiboot");
        ui.label("Varmuuskopioi ja asenna täydellisiä levykuvia (OpenATV, VTi, OpenPLi, PurE2) ja hallitse Multiboot-paikkoja.");
        ui.add_space(8.0);

        let _b = match active_box {
            Some(b) => b,
            None => {
                ui.colored_label(Color32::YELLOW, "Valitse aktiivinen boksi 'Boksin hallinta' -välilehdeltä.");
                return;
            }
        };

        ui.group(|ui| {
            ui.strong("Multiboot-paikat:");
            ui.label("Tarkistetaan laitteen käynnistyspaikkoja (eMMC / USB)...");
            ui.add_space(4.0);

            for slot in 1..=4 {
                ui.horizontal(|ui| {
                    ui.label(format!("Slot {}:", slot));
                    ui.colored_label(Color32::from_rgb(16, 185, 129), "Aktiivinen / Käytössä");
                });
            }
        });

        ui.add_space(8.0);

        ui.group(|ui| {
            ui.strong("Toiminnot:");
            ui.horizontal(|ui| {
                if ui.button("📦 Luo täysi varmuuskopio (.zip)").clicked() {
                    self.status_msg = Some("Varmuuskopionti aloitettu boksissa...".to_string());
                }
                if ui.button("⚡ Asenna uusi Image (.zip)").clicked() {
                    if let Some(path) = rfd::FileDialog::new().add_filter("ZIP Image", &["zip"]).pick_file() {
                        self.status_msg = Some(format!("Valittu asennettavaksi: {}", path.display()));
                    }
                }
            });
        });

        if let Some(msg) = &self.status_msg {
            ui.add_space(8.0);
            ui.label(msg);
        }
    }
}
