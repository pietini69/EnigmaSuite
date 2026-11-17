use std::path::Path;
use egui::{Color32, RichText, Ui, Vec2};
use crate::models::EnigmaBox;
use crate::i18n::Language;
use crate::services::{
    BootlogoService, BootlogoType, BootlogoResolution, ScalingMode, OpenWebifClient
};

pub struct BootlogoView {
    pub selected_type_idx: usize,
    pub selected_res_idx: usize,
    pub selected_scaling_idx: usize,
    pub remote_directory: String,
    pub restart_gui_after_upload: bool,
    pub selected_image_path: Option<String>,
    pub image_dimensions: Option<(u32, u32)>,
    pub status_msg: Option<String>,
    pub is_error: bool,
    pub preview_texture: Option<egui::TextureHandle>,
}

impl Default for BootlogoView {
    fn default() -> Self {
        Self {
            selected_type_idx: 0,
            selected_res_idx: 0, // 1080p FHD
            selected_scaling_idx: 0, // Fit & Pad
            remote_directory: "/usr/share/vuplus-bootlogo".to_string(),
            restart_gui_after_upload: true,
            selected_image_path: None,
            image_dimensions: None,
            status_msg: None,
            is_error: false,
            preview_texture: None,
        }
    }
}

impl BootlogoView {
    pub fn load_image_preview(&mut self, ctx: &egui::Context, path_str: &str) -> Result<(), String> {
        let path = Path::new(path_str);
        let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();

        let img_path = if ext == "mvi" {
            let temp_preview = std::env::temp_dir().join("enigma_mvi_preview.png");
            BootlogoService::convert_mvi_to_image(path, &temp_preview)?;
            temp_preview
        } else {
            path.to_path_buf()
        };

        let dyn_img = image::open(&img_path).map_err(|e| format!("Kuvan avaus epäonnistui: {}", e))?;
        let w = dyn_img.width();
        let h = dyn_img.height();
        let rgba = dyn_img.to_rgba8();
        let color_image = egui::ColorImage::from_rgba_unmultiplied([w as usize, h as usize], rgba.as_raw());

        self.preview_texture = Some(ctx.load_texture("bootlogo_preview", color_image, Default::default()));
        self.selected_image_path = Some(path_str.to_string());
        self.image_dimensions = Some((w, h));
        Ok(())
    }

    pub fn load_bytes_preview(&mut self, ctx: &egui::Context, bytes: &[u8], name: &str) -> Result<(), String> {
        let dyn_img = image::load_from_memory(bytes).map_err(|e| format!("Kuvan lukeminen muistista epäonnistui: {}", e))?;
        let w = dyn_img.width();
        let h = dyn_img.height();
        let rgba = dyn_img.to_rgba8();
        let color_image = egui::ColorImage::from_rgba_unmultiplied([w as usize, h as usize], rgba.as_raw());

        let temp_png = std::env::temp_dir().join(format!("enigma_{}.png", name));
        let _ = std::fs::write(&temp_png, bytes);

        self.preview_texture = Some(ctx.load_texture("bootlogo_preview", color_image, Default::default()));
        self.selected_image_path = Some(temp_png.to_string_lossy().to_string());
        self.image_dimensions = Some((w, h));
        Ok(())
    }

    pub fn render(&mut self, ui: &mut Ui, active_box: Option<&EnigmaBox>, _lang: Language) {
        ui.heading("🎨 Käynnistyskuvien hallinta (MVI Bootlogo Studio)");
        ui.label("Luo, muunna ja asenna kustomoituja käynnistys- ja taustakuvia (bootlogo.mvi) suoraan digiboksiin.");
        ui.add_space(8.0);

        let b = match active_box {
            Some(b) => b,
            None => {
                ui.colored_label(Color32::YELLOW, "Valitse aktiivinen boksi 'Boksin hallinta' -välilehdeltä käyttääksesi toimintoja.");
                return;
            }
        };

        // FFmpeg status check
        let ffmpeg_status = BootlogoService::find_ffmpeg();
        match &ffmpeg_status {
            Some(p) => {
                ui.label(RichText::new(format!("✓ FFmpeg-moottori käytettävissä: {}", p.display())).color(Color32::from_rgb(16, 185, 129)).small());
            }
            None => {
                ui.label(RichText::new("⚠ FFmpeg-työkalua ei löytynyt. Asenna FFmpeg (esim. 'brew install ffmpeg' tai Windowsissa ffmpeg.exe) jotta MVI-muunnos toimii.").color(Color32::from_rgb(234, 179, 8)).small());
            }
        }

        if let Some(msg) = &self.status_msg {
            ui.add_space(6.0);
            let color = if self.is_error {
                Color32::from_rgb(220, 38, 38)
            } else {
                Color32::from_rgb(16, 185, 129)
            };
            ui.label(RichText::new(msg).strong().color(color));
        }

        ui.add_space(8.0);

        ui.columns(2, |columns| {
            // LEFT COLUMN: Controls & Settings
            let ui = &mut columns[0];

            ui.group(|ui| {
                ui.strong("1. Kuvalähde:");
                ui.add_space(4.0);

                ui.horizontal(|ui| {
                    if ui.button("📁 Valitse tiedosto...").clicked() {
                        if let Some(path) = rfd::FileDialog::new()
                            .add_filter("Kuvat ja MVI", &["png", "jpg", "jpeg", "bmp", "mvi"])
                            .pick_file()
                        {
                            let p_str = path.to_string_lossy().to_string();
                            let ctx = ui.ctx().clone();
                            match self.load_image_preview(&ctx, &p_str) {
                                Ok(()) => {
                                    self.status_msg = Some(format!("Ladattu tiedosto: {}", path.file_name().unwrap_or_default().to_string_lossy()));
                                    self.is_error = false;
                                }
                                Err(e) => {
                                    self.status_msg = Some(e);
                                    self.is_error = true;
                                }
                            }
                        }
                    }

                    if ui.button("📸 Kaappaa TV-kuva").clicked() {
                        match OpenWebifClient::take_screenshot(b) {
                            Ok(bytes) => {
                                let ctx = ui.ctx().clone();
                                match self.load_bytes_preview(&ctx, &bytes, "tv_grab") {
                                    Ok(()) => {
                                        self.status_msg = Some("TV-ruutu kaapattu onnistuneesti esikatseluun!".to_string());
                                        self.is_error = false;
                                    }
                                    Err(e) => {
                                        self.status_msg = Some(e);
                                        self.is_error = true;
                                    }
                                }
                            }
                            Err(e) => {
                                self.status_msg = Some(format!("TV-kaappaus epäonnistui: {}", e));
                                self.is_error = true;
                            }
                        }
                    }

                    if ui.button("📥 Lataa boksista").clicked() {
                        let b_type = BootlogoType::all()[self.selected_type_idx];
                        let filename = b_type.filename();
                        let remote_path = format!("{}/{}", self.remote_directory.trim_end_matches('/'), filename);
                        let temp_local = std::env::temp_dir().join(format!("remote_{}", filename));

                        match BootlogoService::download_bootlogo_ftp(&b.ip, &b.username, &b.password, &remote_path, &temp_local) {
                            Ok(()) => {
                                let ctx = ui.ctx().clone();
                                match self.load_image_preview(&ctx, &temp_local.to_string_lossy()) {
                                    Ok(()) => {
                                        self.status_msg = Some(format!("Ladattu boksista nykyinen {}!", filename));
                                        self.is_error = false;
                                    }
                                    Err(e) => {
                                        self.status_msg = Some(format!("Kuvan esikatselu epäonnistui: {}", e));
                                        self.is_error = true;
                                    }
                                }
                            }
                            Err(e) => {
                                self.status_msg = Some(format!("Lataus boksista epäonnistui: {}", e));
                                self.is_error = true;
                            }
                        }
                    }
                });

                if let Some(src) = &self.selected_image_path {
                    ui.add_space(4.0);
                    let filename = Path::new(src).file_name().unwrap_or_default().to_string_lossy();
                    ui.label(format!("Valittu lähde: {}", filename));
                    if let Some((w, h)) = self.image_dimensions {
                        ui.label(format!("Alkuperäinen resoluutio: {} x {} px", w, h));
                    }
                }
            });

            ui.add_space(8.0);

            ui.group(|ui| {
                ui.strong("2. Asetukset & Muunnos:");
                ui.add_space(4.0);

                ui.horizontal(|ui| {
                    ui.label("Kuvatyyppi:");
                    let types = BootlogoType::all();
                    egui::ComboBox::from_id_salt("bootlogo_type_combo")
                        .selected_text(types[self.selected_type_idx].display_name())
                        .show_ui(ui, |ui| {
                            for (i, t) in types.iter().enumerate() {
                                if ui.selectable_label(self.selected_type_idx == i, t.display_name()).clicked() {
                                    self.selected_type_idx = i;
                                }
                            }
                        });
                });

                ui.horizontal(|ui| {
                    ui.label("Resoluutio:");
                    let res_options = [
                        BootlogoResolution::Fhd1080p.label(),
                        BootlogoResolution::Uhd4k.label(),
                        BootlogoResolution::Hd720p.label(),
                    ];
                    egui::ComboBox::from_id_salt("bootlogo_res_combo")
                        .selected_text(res_options[self.selected_res_idx])
                        .show_ui(ui, |ui| {
                            for (i, opt) in res_options.iter().enumerate() {
                                if ui.selectable_label(self.selected_res_idx == i, *opt).clicked() {
                                    self.selected_res_idx = i;
                                }
                            }
                        });
                });

                ui.horizontal(|ui| {
                    ui.label("Kuvasuhde / Rajaus:");
                    let scale_options = [
                        "Sovita & mustat reunat (Fit & Pad)",
                        "Rajaa ruutuun (Crop / Täytä ruutu)",
                        "Venytä kuvasuhteesta välittämättä (Stretch)",
                    ];
                    egui::ComboBox::from_id_salt("bootlogo_scale_combo")
                        .selected_text(scale_options[self.selected_scaling_idx])
                        .show_ui(ui, |ui| {
                            for (i, opt) in scale_options.iter().enumerate() {
                                if ui.selectable_label(self.selected_scaling_idx == i, *opt).clicked() {
                                    self.selected_scaling_idx = i;
                                }
                            }
                        });
                });

                ui.horizontal(|ui| {
                    ui.label("Kohdehakemisto boksissa:");
                    let dirs = [
                        "/usr/share/vuplus-bootlogo",
                        "/usr/share/enigma2",
                        "/etc/enigma2",
                    ];
                    egui::ComboBox::from_id_salt("bootlogo_dir_combo")
                        .selected_text(&self.remote_directory)
                        .show_ui(ui, |ui| {
                            for d in dirs {
                                if ui.selectable_label(self.remote_directory == d, d).clicked() {
                                    self.remote_directory = d.to_string();
                                }
                            }
                        });
                });

                ui.checkbox(&mut self.restart_gui_after_upload, "Käynnistä Enigma2 käyttöliittymä uudelleen asennuksen jälkeen");
            });

            ui.add_space(8.0);

            ui.group(|ui| {
                ui.strong("3. Toiminnot:");
                ui.add_space(4.0);

                ui.horizontal(|ui| {
                    if ui.button(RichText::new("⚡ Asenna valittu kuva boksiin").strong().color(Color32::from_rgb(37, 99, 235))).clicked() {
                        if let Some(src_str) = &self.selected_image_path {
                            let src_path = Path::new(src_str);
                            let b_type = BootlogoType::all()[self.selected_type_idx];
                            let filename = b_type.filename();
                            let remote_path = format!("{}/{}", self.remote_directory.trim_end_matches('/'), filename);
                            let ext = src_path.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();

                            let temp_mvi = std::env::temp_dir().join(filename);
                            let mvi_to_upload = if ext == "mvi" {
                                src_path.to_path_buf()
                            } else {
                                let res = match self.selected_res_idx {
                                    1 => BootlogoResolution::Uhd4k,
                                    2 => BootlogoResolution::Hd720p,
                                    _ => BootlogoResolution::Fhd1080p,
                                };
                                let mode = match self.selected_scaling_idx {
                                    1 => ScalingMode::Crop,
                                    2 => ScalingMode::Stretch,
                                    _ => ScalingMode::FitPad,
                                };

                                match BootlogoService::convert_image_to_mvi(src_path, &temp_mvi, res, mode) {
                                    Ok(()) => temp_mvi,
                                    Err(e) => {
                                        self.status_msg = Some(format!("MVI-muunnos epäonnistui: {}", e));
                                        self.is_error = true;
                                        return;
                                    }
                                }
                            };

                            match BootlogoService::upload_bootlogo_ftp(&b.ip, &b.username, &b.password, &mvi_to_upload, &remote_path) {
                                Ok(()) => {
                                    let mut msg = format!("✓ Käynnistyskuva {} asennettu onnistuneesti kansioon {}!", filename, self.remote_directory);
                                    if self.restart_gui_after_upload {
                                        let _ = OpenWebifClient::set_powerstate(b, 3);
                                        msg.push_str(" Enigma2 GUI käynnistetään uudelleen...");
                                    }
                                    self.status_msg = Some(msg);
                                    self.is_error = false;
                                }
                                Err(e) => {
                                    self.status_msg = Some(format!("Asennus boksiin epäonnistui: {}", e));
                                    self.is_error = true;
                                }
                            }
                        } else {
                            self.status_msg = Some("Valitse ensin kuva koneelta tai kaappaa se televisiosta!".to_string());
                            self.is_error = true;
                        }
                    }

                    if ui.button("💾 Tallenna .mvi koneelle...").clicked() {
                        if let Some(src_str) = &self.selected_image_path {
                            let src_path = Path::new(src_str);
                            let b_type = BootlogoType::all()[self.selected_type_idx];
                            let default_name = b_type.filename();

                            if let Some(dest_path) = rfd::FileDialog::new()
                                .set_file_name(default_name)
                                .add_filter("MVI Käynnistyskuva", &["mvi"])
                                .save_file()
                            {
                                let res = match self.selected_res_idx {
                                    1 => BootlogoResolution::Uhd4k,
                                    2 => BootlogoResolution::Hd720p,
                                    _ => BootlogoResolution::Fhd1080p,
                                };
                                let mode = match self.selected_scaling_idx {
                                    1 => ScalingMode::Crop,
                                    2 => ScalingMode::Stretch,
                                    _ => ScalingMode::FitPad,
                                };

                                let ext = src_path.extension().and_then(|e| e.to_str()).unwrap_or("").to_lowercase();
                                let res_result = if ext == "mvi" {
                                    std::fs::copy(src_path, &dest_path).map(|_| ()).map_err(|e| e.to_string())
                                } else {
                                    BootlogoService::convert_image_to_mvi(src_path, &dest_path, res, mode)
                                };

                                match res_result {
                                    Ok(()) => {
                                        self.status_msg = Some(format!("Tallennettu onnistuneesti kohteeseen: {}", dest_path.display()));
                                        self.is_error = false;
                                    }
                                    Err(e) => {
                                        self.status_msg = Some(format!("Tallennus epäonnistui: {}", e));
                                        self.is_error = true;
                                    }
                                }
                            }
                        } else {
                            self.status_msg = Some("Valitse ensin kuva koneelta tai kaappaa se televisiosta!".to_string());
                            self.is_error = true;
                        }
                    }
                });

                ui.add_space(4.0);
                if ui.button("📦 Varmuuskopioi kaikki boksin käynnistyskuvat").clicked() {
                    if let Some(folder) = rfd::FileDialog::new().pick_folder() {
                        let mut count = 0;
                        let mut errors = 0;
                        for t in BootlogoType::all() {
                            let fn_name = t.filename();
                            let remote_p = format!("{}/{}", self.remote_directory.trim_end_matches('/'), fn_name);
                            let local_p = folder.join(fn_name);
                            if BootlogoService::download_bootlogo_ftp(&b.ip, &b.username, &b.password, &remote_p, &local_p).is_ok() {
                                count += 1;
                            } else {
                                errors += 1;
                            }
                        }
                        if count > 0 {
                            self.status_msg = Some(format!("Varmuuskopioitu {} kuvaa kansioon {} (virheitä {})", count, folder.display(), errors));
                            self.is_error = false;
                        } else {
                            self.status_msg = Some("Yhtäkään käynnistyskuvaa ei voitu ladata boksista.".to_string());
                            self.is_error = true;
                        }
                    }
                }
            });

            // RIGHT COLUMN: Live Image Preview
            let ui = &mut columns[1];
            ui.group(|ui| {
                ui.strong("Esikatselu:");
                ui.add_space(4.0);

                if let Some(tex) = &self.preview_texture {
                    let aspect = tex.size()[0] as f32 / tex.size()[1].max(1) as f32;
                    let avail_w = ui.available_width().min(500.0);
                    let h = avail_w / aspect;
                    ui.image((tex.id(), Vec2::new(avail_w, h)));

                    ui.add_space(4.0);
                    if let Some((w, h)) = self.image_dimensions {
                        ui.label(format!("Mitat: {} x {} px", w, h));
                    }
                } else {
                    ui.vertical_centered(|ui| {
                        ui.add_space(40.0);
                        ui.label(RichText::new("Ei valittua kuvaa").italics().color(Color32::GRAY));
                        ui.label("Valitse kuva tiedostosta, kaappaa TV-lähetyksestä tai lataa boksin nykyinen kuva esikatseluun.");
                        ui.add_space(40.0);
                    });
                }
            });
        });
    }
}
