use egui::{Color32, RichText, ScrollArea, Ui};
use crate::models::{AutoTimerRule, EnigmaBox, MovieItem, TimerItem};
use crate::services::OpenWebifClient;
use crate::i18n::Language;

pub struct TimersView {
    pub timers: Vec<TimerItem>,
    pub autotimers: Vec<AutoTimerRule>,
    pub movies: Vec<MovieItem>,
    pub active_subtab: usize, // 0 = Timers, 1 = AutoTimers, 2 = Movies
    pub status_msg: Option<String>,
    pub movie_search: String,
    
    pub new_autotimer_name: String,
    pub new_autotimer_match: String,
    pub show_add_autotimer: bool,

    has_loaded_timers: bool,
    has_loaded_autotimers: bool,
    has_loaded_movies: bool,
}

impl Default for TimersView {
    fn default() -> Self {
        Self {
            timers: Vec::new(),
            autotimers: Vec::new(),
            movies: Vec::new(),
            active_subtab: 0,
            status_msg: None,
            movie_search: String::new(),
            new_autotimer_name: String::new(),
            new_autotimer_match: String::new(),
            show_add_autotimer: false,
            has_loaded_timers: false,
            has_loaded_autotimers: false,
            has_loaded_movies: false,
        }
    }
}

impl TimersView {
    pub fn load_timers(&mut self, b: &EnigmaBox) {
        match OpenWebifClient::fetch_timers(b) {
            Ok(list) => {
                self.timers = list;
                self.has_loaded_timers = true;
            }
            Err(e) => self.status_msg = Some(format!("Ajastusten haku epäonnistui: {}", e)),
        }
    }

    pub fn load_autotimers(&mut self, b: &EnigmaBox) {
        match OpenWebifClient::fetch_autotimers(b) {
            Ok(list) => {
                self.autotimers = list;
                self.has_loaded_autotimers = true;
            }
            Err(e) => self.status_msg = Some(format!("Automaattiajastusten haku epäonnistui: {}", e)),
        }
    }

    pub fn load_movies(&mut self, b: &EnigmaBox) {
        match OpenWebifClient::fetch_movies(b) {
            Ok(list) => {
                self.movies = list;
                self.has_loaded_movies = true;
            }
            Err(e) => self.status_msg = Some(format!("Tallenteiden haku epäonnistui: {}", e)),
        }
    }

    pub fn render(&mut self, ui: &mut Ui, active_box: Option<&EnigmaBox>, _lang: Language) {
        ui.heading("⏱ Ajastukset, Automaattiajastukset & Tallenteet");

        let b = match active_box {
            Some(b) => b,
            None => {
                ui.colored_label(Color32::YELLOW, "Valitse aktiivinen boksi 'Boksin hallinta' -välilehdeltä.");
                return;
            }
        };

        ui.add_space(4.0);

        // Subtabs
        ui.horizontal(|ui| {
            if ui.selectable_label(self.active_subtab == 0, format!("⏱ Tavalliset ajastukset ({})", self.timers.len())).clicked() {
                self.active_subtab = 0;
                self.load_timers(b);
            }
            if ui.selectable_label(self.active_subtab == 1, format!("⚡ Automaattiajastukset ({})", self.autotimers.len())).clicked() {
                self.active_subtab = 1;
                self.load_autotimers(b);
            }
            if ui.selectable_label(self.active_subtab == 2, format!("🎬 Tallenteet ({})", self.movies.len())).clicked() {
                self.active_subtab = 2;
                self.load_movies(b);
            }

            if ui.button("🔄 Päivitä").clicked() {
                match self.active_subtab {
                    0 => self.load_timers(b),
                    1 => self.load_autotimers(b),
                    _ => self.load_movies(b),
                }
            }
        });

        if let Some(msg) = &self.status_msg {
            ui.label(RichText::new(msg).color(Color32::from_rgb(220, 38, 38)));
            ui.add_space(4.0);
        }

        ui.add_space(6.0);

        match self.active_subtab {
            0 => {
                // Tab 0: Regular Timers
                if !self.has_loaded_timers {
                    self.load_timers(b);
                }

                ScrollArea::vertical().id_salt("timers_scroll").max_height(520.0).show(ui, |ui| {
                    if self.timers.is_empty() {
                        ui.label("Ei aktiivisia ajastuksia boksissa.");
                    } else {
                        let mut to_delete = None;
                        for t in &self.timers {
                            ui.group(|ui| {
                                ui.horizontal(|ui| {
                                    ui.label(RichText::new(&t.name).strong().color(Color32::from_rgb(37, 99, 235)));
                                    ui.label(format!("Kanava: {}", t.service_name));
                                    
                                    if ui.small_button("❌ Poista").clicked() {
                                        to_delete = Some((t.service_ref.clone(), t.begin, t.end));
                                    }
                                });
                                if !t.description.is_empty() {
                                    ui.label(&t.description);
                                }
                            });
                            ui.add_space(3.0);
                        }

                        if let Some((sref, begin, end)) = to_delete {
                            let _ = OpenWebifClient::delete_timer(b, &sref, begin, end);
                            self.load_timers(b);
                        }
                    }
                });
            }

            1 => {
                // Tab 1: AutoTimers (Automaattiajastukset)
                if !self.has_loaded_autotimers {
                    self.load_autotimers(b);
                }

                ui.horizontal(|ui| {
                    if ui.button(if self.show_add_autotimer { "Sulje lisäyslomake" } else { "➕ Lisää uusi automaattiajastus" }).clicked() {
                        self.show_add_autotimer = !self.show_add_autotimer;
                    }
                });

                if self.show_add_autotimer {
                    ui.group(|ui| {
                        ui.strong("Uusi automaattiajastussääntö:");
                        ui.horizontal(|ui| {
                            ui.label("Otsikko/Nimi:");
                            ui.text_edit_singleline(&mut self.new_autotimer_name);
                        });
                        ui.horizontal(|ui| {
                            ui.label("Hakusana (Match):");
                            ui.text_edit_singleline(&mut self.new_autotimer_match);
                        });
                        if ui.button("💾 Tallenna automaattiajastus").clicked() {
                            if !self.new_autotimer_name.is_empty() && !self.new_autotimer_match.is_empty() {
                                if let Ok(()) = OpenWebifClient::add_autotimer(b, &self.new_autotimer_name, &self.new_autotimer_match, None) {
                                    self.new_autotimer_name.clear();
                                    self.new_autotimer_match.clear();
                                    self.show_add_autotimer = false;
                                    self.load_autotimers(b);
                                    self.status_msg = Some("Uusi automaattiajastus lisätty!".to_string());
                                }
                            }
                        }
                    });
                    ui.add_space(6.0);
                }

                ScrollArea::vertical().id_salt("autotimers_scroll").max_height(520.0).show(ui, |ui| {
                    if self.autotimers.is_empty() {
                        ui.label("Ei automaattiajastussääntöjä boksissa tai AutoTimer-lisäosa ei ole asennettu.");
                    } else {
                        let mut to_delete = None;
                        for at in &self.autotimers {
                            ui.group(|ui| {
                                ui.horizontal(|ui| {
                                    ui.label(RichText::new(&at.name).strong().color(Color32::from_rgb(16, 185, 129)));
                                    ui.label(format!("Hakusana: \"{}\"", at.match_pattern));
                                    if !at.service_name.is_empty() {
                                        ui.label(format!("| Kanava: {}", at.service_name));
                                    }
                                    let status_badge = if at.enabled { "Käytössä" } else { "Pois päältä" };
                                    ui.colored_label(if at.enabled { Color32::GREEN } else { Color32::GRAY }, status_badge);

                                    if ui.small_button("❌ Poista").clicked() {
                                        to_delete = Some(at.id.clone());
                                    }
                                });
                            });
                            ui.add_space(3.0);
                        }

                        if let Some(id) = to_delete {
                            let _ = OpenWebifClient::delete_autotimer(b, &id);
                            self.load_autotimers(b);
                        }
                    }
                });
            }

            _ => {
                // Tab 2: Movies / Recordings
                if !self.has_loaded_movies {
                    self.load_movies(b);
                }

                ui.horizontal(|ui| {
                    ui.label("🔍 Etsi tallenteista:");
                    ui.text_edit_singleline(&mut self.movie_search);
                    if !self.movie_search.is_empty() && ui.small_button("Tyhjennä").clicked() {
                        self.movie_search.clear();
                    }
                });

                ui.add_space(4.0);

                let filtered_indices: Vec<usize> = self.movies
                    .iter()
                    .enumerate()
                    .filter_map(|(idx, m)| {
                        if self.movie_search.is_empty() {
                            Some(idx)
                        } else {
                            let q = self.movie_search.to_lowercase();
                            if m.name.to_lowercase().contains(&q)
                                || m.service_name.to_lowercase().contains(&q)
                                || m.description.to_lowercase().contains(&q)
                            {
                                Some(idx)
                            } else {
                                None
                            }
                        }
                    })
                    .collect();

                ui.strong(format!("Boksin kiintolevyn tallenteet (Näytetään {} / {})", filtered_indices.len(), self.movies.len()));
                
                let mut to_delete_sref = None;
                ScrollArea::vertical().id_salt("movies_scroll").max_height(480.0).show(ui, |ui| {
                    for &idx in &filtered_indices {
                        if let Some(m) = self.movies.get(idx) {
                            ui.group(|ui| {
                                ui.horizontal(|ui| {
                                    ui.label(RichText::new(&m.name).strong().color(Color32::from_rgb(16, 185, 129)));
                                    if !m.service_name.is_empty() {
                                        ui.label(format!("Kanava: {}", m.service_name));
                                    }
                                    if !m.filesize_readable.is_empty() {
                                        ui.label(format!("| Koko: {}", m.filesize_readable));
                                    }
                                    if !m.length.is_empty() {
                                        ui.label(format!("| Kesto: {}", m.length));
                                    }

                                    if ui.small_button("▶ Toista (VLC)").clicked() {
                                        let stream_url = b.stream_url(&m.service_ref);
                                        crate::services::MediaPlayer::play_stream(&stream_url, &m.name);
                                    }
                                    if ui.small_button("❌ Poista").clicked() {
                                        to_delete_sref = Some(m.service_ref.clone());
                                    }
                                });
                                if !m.description.is_empty() {
                                    ui.label(&m.description);
                                }
                            });
                            ui.add_space(3.0);
                        }
                    }
                });

                if let Some(sref) = to_delete_sref {
                    let _ = OpenWebifClient::delete_movie(b, &sref);
                    self.load_movies(b);
                }
            }
        }
    }
}
