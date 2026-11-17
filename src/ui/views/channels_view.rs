use egui::{Color32, RichText, ScrollArea, Ui};
use crate::models::{Bouquet, Channel, EnigmaBox, EpgEvent};
use crate::services::OpenWebifClient;
use crate::i18n::Language;

pub struct ChannelsView {
    pub bouquets: Vec<Bouquet>,
    pub channels: Vec<Channel>,
    pub epg_events: Vec<EpgEvent>,
    pub selected_bouquet_ref: Option<String>,
    pub selected_channel_ref: Option<String>,
    pub search_query: String,
    pub is_radio: bool,
    pub status_msg: Option<String>,
}

impl Default for ChannelsView {
    fn default() -> Self {
        Self {
            bouquets: Vec::new(),
            channels: Vec::new(),
            epg_events: Vec::new(),
            selected_bouquet_ref: None,
            selected_channel_ref: None,
            search_query: String::new(),
            is_radio: false,
            status_msg: None,
        }
    }
}

impl ChannelsView {
    pub fn load_bouquets(&mut self, b: &EnigmaBox) {
        match OpenWebifClient::fetch_bouquets(b, self.is_radio) {
            Ok(list) => {
                self.bouquets = list;
                if let Some(first) = self.bouquets.first() {
                    let ref_str = first.s_ref.clone();
                    self.load_channels(b, &ref_str);
                    self.selected_bouquet_ref = Some(ref_str);
                }
            }
            Err(e) => self.status_msg = Some(format!("Suosikkilistojen haku epäonnistui: {}", e)),
        }
    }

    pub fn load_channels(&mut self, b: &EnigmaBox, b_ref: &str) {
        match OpenWebifClient::fetch_channels_in_bouquet(b, b_ref) {
            Ok(list) => self.channels = list,
            Err(e) => self.status_msg = Some(format!("Kanavien haku epäonnistui: {}", e)),
        }
    }

    pub fn load_epg(&mut self, b: &EnigmaBox, s_ref: &str) {
        match OpenWebifClient::fetch_epg(b, s_ref) {
            Ok(list) => self.epg_events = list,
            Err(e) => self.status_msg = Some(format!("EPG:n haku epäonnistui: {}", e)),
        }
    }

    pub fn render(&mut self, ui: &mut Ui, active_box: Option<&EnigmaBox>, _lang: Language) {
        ui.heading("📺 Kanavat & Ohjelmaopas (EPG)");

        let b = match active_box {
            Some(b) => b,
            None => {
                ui.colored_label(Color32::YELLOW, "Valitse aktiivinen boksi 'Boksin hallinta' -välilehdeltä.");
                return;
            }
        };

        if self.bouquets.is_empty() {
            self.load_bouquets(b);
        }

        ui.horizontal(|ui| {
            if ui.selectable_label(!self.is_radio, "📺 TV-kanavat").clicked() {
                self.is_radio = false;
                self.load_bouquets(b);
            }
            if ui.selectable_label(self.is_radio, "📻 Radiokanavat").clicked() {
                self.is_radio = true;
                self.load_bouquets(b);
            }
            if ui.button("🔄 Päivitä kanavat").clicked() {
                self.load_bouquets(b);
            }

            ui.add_space(20.0);
            ui.label("Hae kanavaa:");
            ui.text_edit_singleline(&mut self.search_query);
        });

        if let Some(msg) = &self.status_msg {
            ui.label(RichText::new(msg).color(Color32::RED));
        }

        ui.add_space(4.0);

        ui.columns(3, |cols| {
            // Column 1: Bouquets
            cols[0].group(|ui| {
                ui.strong("Suosikkilistat (Bouquets):");
                ScrollArea::vertical().id_salt("bouquets_scroll").max_height(480.0).show(ui, |ui| {
                    let mut chosen_b = None;
                    for bq in &self.bouquets {
                        let is_sel = self.selected_bouquet_ref.as_deref() == Some(&bq.s_ref);
                        if ui.selectable_label(is_sel, &bq.name).clicked() {
                            chosen_b = Some(bq.s_ref.clone());
                        }
                    }
                    if let Some(sref) = chosen_b {
                        self.selected_bouquet_ref = Some(sref.clone());
                        self.load_channels(b, &sref);
                    }
                });
            });

            // Column 2: Channels in Bouquet
            cols[1].group(|ui| {
                ui.strong("Kanavalista:");
                ScrollArea::vertical().id_salt("channels_scroll").max_height(480.0).show(ui, |ui| {
                    let q = self.search_query.to_lowercase();
                    let mut zap_target = None;
                    let mut stream_target = None;
                    let mut chosen_channel = None;

                    for ch in &self.channels {
                        if !q.is_empty() && !ch.name.to_lowercase().contains(&q) {
                            continue;
                        }

                        let is_sel = self.selected_channel_ref.as_deref() == Some(&ch.s_ref);
                        ui.horizontal(|ui| {
                            if ui.selectable_label(is_sel, &ch.name).clicked() {
                                chosen_channel = Some(ch.s_ref.clone());
                            }
                            if ui.small_button("⚡ Zap").on_hover_text("Vaihda kanavalle televisiossa").clicked() {
                                zap_target = Some(ch.s_ref.clone());
                            }
                            if ui.small_button("▶ VLC").on_hover_text("Suoratoista kanavaa tietokoneella").clicked() {
                                stream_target = Some(ch.s_ref.clone());
                            }
                        });
                    }

                    if let Some(sref) = chosen_channel {
                        self.selected_channel_ref = Some(sref.clone());
                        self.load_epg(b, &sref);
                    }
                    if let Some(sref) = zap_target {
                        let _ = OpenWebifClient::zap(b, &sref);
                    }
                    if let Some(sref) = stream_target {
                        let stream_url = b.stream_url(&sref);
                        let _ = open::that(&stream_url);
                    }
                });
            });

            // Column 3: EPG Events for selected channel
            cols[2].group(|ui| {
                ui.strong("Ohjelmatiedot (EPG):");
                ScrollArea::vertical().id_salt("epg_scroll").max_height(480.0).show(ui, |ui| {
                    if self.epg_events.is_empty() {
                        ui.label("Valitse kanava nähdäksesi ohjelmatiedot.");
                    } else {
                        for ev in &self.epg_events {
                            ui.group(|ui| {
                                ui.strong(&ev.title);
                                if !ev.description.is_empty() {
                                    ui.label(&ev.description);
                                }
                                if ui.small_button("⏱ Lisää ajastus").clicked() {
                                    let _ = OpenWebifClient::add_timer_by_event_id(b, self.selected_channel_ref.as_deref().unwrap_or(""), ev.id);
                                }
                            });
                        }
                    }
                });
            });
        });
    }
}
