use egui::{Color32, RichText, ScrollArea, Ui};
use crate::models::{EnigmaBox, MovieItem, TimerItem};
use crate::services::OpenWebifClient;
use crate::i18n::Language;

pub struct TimersView {
    pub timers: Vec<TimerItem>,
    pub movies: Vec<MovieItem>,
    pub active_subtab: usize, // 0 = Timers, 1 = Movies
    pub status_msg: Option<String>,
}

impl Default for TimersView {
    fn default() -> Self {
        Self {
            timers: Vec::new(),
            movies: Vec::new(),
            active_subtab: 0,
            status_msg: None,
        }
    }
}

impl TimersView {
    pub fn load_timers(&mut self, b: &EnigmaBox) {
        match OpenWebifClient::fetch_timers(b) {
            Ok(list) => self.timers = list,
            Err(e) => self.status_msg = Some(format!("Ajastusten haku epäonnistui: {}", e)),
        }
    }

    pub fn load_movies(&mut self, b: &EnigmaBox) {
        match OpenWebifClient::fetch_movies(b) {
            Ok(list) => self.movies = list,
            Err(e) => self.status_msg = Some(format!("Tallenteiden haku epäonnistui: {}", e)),
        }
    }

    pub fn render(&mut self, ui: &mut Ui, active_box: Option<&EnigmaBox>, _lang: Language) {
        ui.heading("⏱ Ajastukset & Tallenteet");

        let b = match active_box {
            Some(b) => b,
            None => {
                ui.colored_label(Color32::YELLOW, "Valitse aktiivinen boksi 'Boksin hallinta' -välilehdeltä.");
                return;
            }
        };

        ui.horizontal(|ui| {
            if ui.selectable_label(self.active_subtab == 0, "⏱ Ajastukset").clicked() {
                self.active_subtab = 0;
                self.load_timers(b);
            }
            if ui.selectable_label(self.active_subtab == 1, "🎬 Tallenteet").clicked() {
                self.active_subtab = 1;
                self.load_movies(b);
            }

            if ui.button("🔄 Päivitä lista").clicked() {
                if self.active_subtab == 0 {
                    self.load_timers(b);
                } else {
                    self.load_movies(b);
                }
            }
        });

        if let Some(msg) = &self.status_msg {
            ui.label(RichText::new(msg).color(Color32::RED));
            ui.add_space(4.0);
        }

        ui.add_space(6.0);

        if self.active_subtab == 0 {
            // Timers
            if self.timers.is_empty() {
                self.load_timers(b);
            }

            ui.strong(format!("Aktiiviset ajastukset ({})", self.timers.len()));
            ScrollArea::vertical().id_salt("timers_scroll").max_height(500.0).show(ui, |ui| {
                let mut to_delete = None;
                for t in &self.timers {
                    ui.group(|ui| {
                        ui.horizontal(|ui| {
                            ui.label(RichText::new(&t.name).strong().color(Color32::from_rgb(59, 130, 246)));
                            ui.label(format!("Kanava: {}", t.service_name));
                            if ui.small_button("❌ Poista").clicked() {
                                to_delete = Some((t.service_ref.clone(), t.begin, t.end));
                            }
                        });
                        if !t.description.is_empty() {
                            ui.label(&t.description);
                        }
                    });
                }

                if let Some((sref, begin, end)) = to_delete {
                    let _ = OpenWebifClient::delete_timer(b, &sref, begin, end);
                    self.load_timers(b);
                }
            });
        } else {
            // Movies
            if self.movies.is_empty() {
                self.load_movies(b);
            }

            ui.strong(format!("Boksin kiintolevyn tallenteet ({})", self.movies.len()));
            ScrollArea::vertical().id_salt("movies_scroll").max_height(500.0).show(ui, |ui| {
                let mut to_delete = None;
                for m in &self.movies {
                    ui.group(|ui| {
                        ui.horizontal(|ui| {
                            ui.label(RichText::new(&m.name).strong().color(Color32::from_rgb(16, 185, 129)));
                            ui.label(format!("Kanava: {} | Koko: {} | Kesto: {}", m.service_name, m.filesize_readable, m.length));
                            
                            if ui.small_button("▶ Toista (VLC)").clicked() {
                                let stream_url = b.stream_url(&m.service_ref);
                                crate::services::MediaPlayer::play_stream(&stream_url, &m.name);
                            }
                            if ui.small_button("❌ Poista").clicked() {
                                to_delete = Some(m.service_ref.clone());
                            }
                        });
                        if !m.description.is_empty() {
                            ui.label(&m.description);
                        }
                    });
                }

                if let Some(sref) = to_delete {
                    let _ = OpenWebifClient::delete_movie(b, &sref);
                    self.load_movies(b);
                }
            });
        }
    }
}
