use egui::{Color32, RichText, Ui, Vec2};
use crate::models::{CurrentPlaybackInfo, EnigmaBox};
use crate::services::OpenWebifClient;
use crate::i18n::Language;

pub struct RemoteView {
    pub playback_info: Option<CurrentPlaybackInfo>,
    pub status_msg: Option<String>,
    pub screenshot_texture: Option<egui::TextureHandle>,
}

impl Default for RemoteView {
    fn default() -> Self {
        Self {
            playback_info: None,
            status_msg: None,
            screenshot_texture: None,
        }
    }
}

impl RemoteView {
    pub fn refresh_playback(&mut self, b: &EnigmaBox) {
        match OpenWebifClient::get_current_playback(b) {
            Ok(info) => self.playback_info = Some(info),
            Err(e) => self.status_msg = Some(format!("Toistotietojen haku epäonnistui: {}", e)),
        }
    }

    pub fn render(&mut self, ui: &mut Ui, active_box: Option<&EnigmaBox>, _lang: Language) {
        ui.heading("📱 Virtuaalinen Kaukosäädin");

        let b = match active_box {
            Some(b) => b,
            None => {
                ui.colored_label(Color32::YELLOW, "Valitse aktiivinen boksi 'Boksin hallinta' -välilehdeltä.");
                return;
            }
        };

        if self.playback_info.is_none() {
            self.refresh_playback(b);
        }

        // Top Banner: Now playing
        ui.group(|ui| {
            ui.horizontal(|ui| {
                ui.strong("Nyt katsotaan:");
                if ui.small_button("🔄 Päivitä").clicked() {
                    self.refresh_playback(b);
                }
            });

            if let Some(info) = &self.playback_info {
                ui.label(RichText::new(&info.channel_name).size(16.0).strong().color(Color32::from_rgb(59, 130, 246)));
                ui.label(RichText::new(&info.event_title).strong());
                if !info.event_description.is_empty() {
                    ui.label(&info.event_description);
                }

                if info.duration_sec > 0 {
                    ui.add_space(4.0);
                    let progress = info.progress_percent;
                    ui.add(egui::ProgressBar::new(progress).show_percentage());
                }
            } else {
                ui.label("Ei toistotietoja saatavilla.");
            }
        });

        ui.add_space(8.0);

        if let Some(msg) = &self.status_msg {
            ui.label(msg);
            ui.add_space(4.0);
        }

        ui.columns(2, |cols| {
            // Left column: Remote Control keypad
            cols[0].group(|ui| {
                ui.set_max_width(320.0);
                let btn_size = Vec2::new(75.0, 32.0);

                // Row 1: Power, Mute, TV
                ui.horizontal(|ui| {
                    if ui.add_sized(btn_size, egui::Button::new(RichText::new("⏻ Virta").color(Color32::RED))).clicked() {
                        let _ = OpenWebifClient::send_remote_key(b, "KEY_POWER");
                    }
                    if ui.add_sized(btn_size, egui::Button::new("🔇 Mykistys")).clicked() {
                        let _ = OpenWebifClient::send_remote_key(b, "KEY_MUTE");
                    }
                    if ui.add_sized(btn_size, egui::Button::new("📺 TV/Radio")).clicked() {
                        let _ = OpenWebifClient::send_remote_key(b, "KEY_TV");
                    }
                });

                ui.add_space(6.0);

                // Numbers: 1, 2, 3
                ui.horizontal(|ui| {
                    if ui.add_sized(btn_size, egui::Button::new("1")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_1"); }
                    if ui.add_sized(btn_size, egui::Button::new("2")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_2"); }
                    if ui.add_sized(btn_size, egui::Button::new("3")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_3"); }
                });

                // Numbers: 4, 5, 6
                ui.horizontal(|ui| {
                    if ui.add_sized(btn_size, egui::Button::new("4")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_4"); }
                    if ui.add_sized(btn_size, egui::Button::new("5")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_5"); }
                    if ui.add_sized(btn_size, egui::Button::new("6")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_6"); }
                });

                // Numbers: 7, 8, 9
                ui.horizontal(|ui| {
                    if ui.add_sized(btn_size, egui::Button::new("7")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_7"); }
                    if ui.add_sized(btn_size, egui::Button::new("8")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_8"); }
                    if ui.add_sized(btn_size, egui::Button::new("9")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_9"); }
                });

                // Numbers: <, 0, >
                ui.horizontal(|ui| {
                    if ui.add_sized(btn_size, egui::Button::new("⏮")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_PREVIOUS"); }
                    if ui.add_sized(btn_size, egui::Button::new("0")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_0"); }
                    if ui.add_sized(btn_size, egui::Button::new("⏭")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_NEXT"); }
                });

                ui.add_space(8.0);

                // Vol / Ch controls
                ui.horizontal(|ui| {
                    if ui.add_sized(btn_size, egui::Button::new("VOL +")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_VOLUMEUP"); }
                    ui.add_sized(btn_size, egui::Label::new(""));
                    if ui.add_sized(btn_size, egui::Button::new("CH +")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_CHANNELUP"); }
                });
                ui.horizontal(|ui| {
                    if ui.add_sized(btn_size, egui::Button::new("VOL -")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_VOLUMEDOWN"); }
                    ui.add_sized(btn_size, egui::Label::new(""));
                    if ui.add_sized(btn_size, egui::Button::new("CH -")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_CHANNELDOWN"); }
                });

                ui.add_space(8.0);

                // D-Pad navigation
                ui.horizontal(|ui| {
                    ui.add_sized(btn_size, egui::Label::new(""));
                    if ui.add_sized(btn_size, egui::Button::new("▲")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_UP"); }
                    ui.add_sized(btn_size, egui::Label::new(""));
                });
                ui.horizontal(|ui| {
                    if ui.add_sized(btn_size, egui::Button::new("◀")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_LEFT"); }
                    if ui.add_sized(btn_size, egui::Button::new(RichText::new("OK").strong())).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_OK"); }
                    if ui.add_sized(btn_size, egui::Button::new("▶")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_RIGHT"); }
                });
                ui.horizontal(|ui| {
                    ui.add_sized(btn_size, egui::Label::new(""));
                    if ui.add_sized(btn_size, egui::Button::new("▼")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_DOWN"); }
                    ui.add_sized(btn_size, egui::Label::new(""));
                });

                ui.add_space(8.0);

                // Menu, Exit, Info, EPG
                ui.horizontal(|ui| {
                    if ui.add_sized(btn_size, egui::Button::new("Valikko")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_MENU"); }
                    if ui.add_sized(btn_size, egui::Button::new("Poistu")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_EXIT"); }
                    if ui.add_sized(btn_size, egui::Button::new("EPG")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_EPG"); }
                });

                ui.add_space(6.0);

                // Color row
                ui.horizontal(|ui| {
                    let col_btn = Vec2::new(55.0, 24.0);
                    if ui.add_sized(col_btn, egui::Button::new(RichText::new("Pun").color(Color32::WHITE)).fill(Color32::from_rgb(220, 38, 38))).clicked() {
                        let _ = OpenWebifClient::send_remote_key(b, "KEY_RED");
                    }
                    if ui.add_sized(col_btn, egui::Button::new(RichText::new("Vihr").color(Color32::WHITE)).fill(Color32::from_rgb(22, 163, 74))).clicked() {
                        let _ = OpenWebifClient::send_remote_key(b, "KEY_GREEN");
                    }
                    if ui.add_sized(col_btn, egui::Button::new(RichText::new("Kelt").color(Color32::BLACK)).fill(Color32::from_rgb(234, 179, 8))).clicked() {
                        let _ = OpenWebifClient::send_remote_key(b, "KEY_YELLOW");
                    }
                    if ui.add_sized(col_btn, egui::Button::new(RichText::new("Sin").color(Color32::WHITE)).fill(Color32::from_rgb(37, 99, 235))).clicked() {
                        let _ = OpenWebifClient::send_remote_key(b, "KEY_BLUE");
                    }
                });

                ui.add_space(6.0);

                // Playback
                ui.horizontal(|ui| {
                    let med_btn = Vec2::new(38.0, 26.0);
                    if ui.add_sized(med_btn, egui::Button::new("⏪")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_REWIND"); }
                    if ui.add_sized(med_btn, egui::Button::new("▶")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_PLAY"); }
                    if ui.add_sized(med_btn, egui::Button::new("⏸")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_PAUSE"); }
                    if ui.add_sized(med_btn, egui::Button::new("⏩")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_FASTFORWARD"); }
                    if ui.add_sized(med_btn, egui::Button::new("⏹")).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_STOP"); }
                    if ui.add_sized(med_btn, egui::Button::new(RichText::new("⏺").color(Color32::RED))).clicked() { let _ = OpenWebifClient::send_remote_key(b, "KEY_RECORD"); }
                });
            });

            // Right column: TV Screenshot
            cols[1].group(|ui| {
                ui.strong("TV-ruutukaappaus:");
                if ui.button("📸 Ota ruutukaappaus televisiosta").clicked() {
                    match OpenWebifClient::take_screenshot(b) {
                        Ok(bytes) => {
                            if let Ok(img) = image::load_from_memory(&bytes) {
                                let size = [img.width() as _, img.height() as _];
                                let rgba = img.to_rgba8();
                                let color_image = egui::ColorImage::from_rgba_unmultiplied(size, rgba.as_raw());
                                self.screenshot_texture = Some(ui.ctx().load_texture("screenshot", color_image, Default::default()));
                                self.status_msg = Some("Ruutukaappaus ladattu!".to_string());
                            }
                        }
                        Err(e) => {
                            self.status_msg = Some(format!("Kaappaus epäonnistui: {}", e));
                        }
                    }
                }

                if let Some(tex) = &self.screenshot_texture {
                    ui.add_space(8.0);
                    let aspect = tex.size()[0] as f32 / tex.size()[1] as f32;
                    let width = 360.0;
                    let height = width / aspect;
                    ui.image((tex.id(), Vec2::new(width, height)));
                }
            });
        });
    }
}
