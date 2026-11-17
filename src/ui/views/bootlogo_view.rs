use egui::{Color32, RichText, Ui, Vec2};
use crate::models::EnigmaBox;
use crate::i18n::Language;

pub struct BootlogoView {
    pub selected_type: usize, // 0 = bootlogo, 1 = bootlogo_wait, 2 = backdrop, 3 = reboot
    pub selected_image_path: Option<String>,
    pub status_msg: Option<String>,
    pub preview_texture: Option<egui::TextureHandle>,
}

impl Default for BootlogoView {
    fn default() -> Self {
        Self {
            selected_type: 0,
            selected_image_path: None,
            status_msg: None,
            preview_texture: None,
        }
    }
}

impl BootlogoView {
    pub fn render(&mut self, ui: &mut Ui, active_box: Option<&EnigmaBox>, _lang: Language) {
        ui.heading("🎨 Käynnistyskuvien hallinta (MVI Bootlogo)");
        ui.label("Luo ja asenna kustomoituja käynnistys- ja taustakuvia suoraan digiboksiin.");
        ui.add_space(8.0);

        let _b = match active_box {
            Some(b) => b,
            None => {
                ui.colored_label(Color32::YELLOW, "Valitse aktiivinen boksi 'Boksin hallinta' -välilehdeltä.");
                return;
            }
        };

        ui.horizontal(|ui| {
            ui.strong("Kuvatyyppi:");
            let types = ["bootlogo.mvi (Käynnistyskuva)", "bootlogo_wait.mvi (Latauskuva)", "backdrop.mvi (Tausta)", "reboot.mvi (Sammutuskuva)"];
            egui::ComboBox::from_id_salt("bootlogo_type_combo").selected_text(types[self.selected_type]).show_ui(ui, |ui| {
                for (i, t) in types.iter().enumerate() {
                    if ui.selectable_label(self.selected_type == i, *t).clicked() {
                        self.selected_type = i;
                    }
                }
            });

            if ui.button("📁 Valitse kuva koneelta...").clicked() {
                if let Some(path) = rfd::FileDialog::new().add_filter("Kuvat", &["png", "jpg", "jpeg", "mvi"]).pick_file() {
                    let path_str = path.to_string_lossy().to_string();
                    if let Ok(img) = image::open(&path) {
                        let size = [img.width() as _, img.height() as _];
                        let rgba = img.to_rgba8();
                        let color_image = egui::ColorImage::from_rgba_unmultiplied(size, rgba.as_raw());
                        self.preview_texture = Some(ui.ctx().load_texture("bootlogo_preview", color_image, Default::default()));
                    }
                    self.selected_image_path = Some(path_str);
                    self.status_msg = Some("Kuva valittu!".to_string());
                }
            }
        });

        if let Some(msg) = &self.status_msg {
            ui.add_space(4.0);
            ui.label(RichText::new(msg).color(Color32::from_rgb(59, 130, 246)));
        }

        ui.add_space(8.0);

        if let Some(tex) = &self.preview_texture {
            ui.group(|ui| {
                ui.strong("Esikatselu:");
                let aspect = tex.size()[0] as f32 / tex.size()[1] as f32;
                let width = 420.0;
                let height = width / aspect;
                ui.image((tex.id(), Vec2::new(width, height)));
            });
        }
    }
}
