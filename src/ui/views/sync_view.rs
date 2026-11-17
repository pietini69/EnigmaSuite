use egui::{Color32, RichText, ScrollArea, Ui};
use crate::models::EnigmaBox;
use crate::services::{SettingDiff, SettingsSyncService};
use crate::i18n::Language;

pub struct SettingsSyncView {
    pub source_box_id: Option<String>,
    pub target_box_id: Option<String>,
    pub diffs: Vec<SettingDiff>,
    pub search_query: String,
    pub status_msg: Option<String>,
}

impl Default for SettingsSyncView {
    fn default() -> Self {
        Self {
            source_box_id: None,
            target_box_id: None,
            diffs: Vec::new(),
            search_query: String::new(),
            status_msg: None,
        }
    }
}

impl SettingsSyncView {
    pub fn render(&mut self, ui: &mut Ui, boxes: &[EnigmaBox], _lang: Language) {
        ui.heading("🔄 Asetusten synkronointi kahden boksin välillä");
        ui.label("Vertaile ja synkronoi asetukset (kanavahaut, kieli, laajennukset, aikavyöhyke) kahden Enigma2-laitteen välillä.");
        ui.add_space(8.0);

        if boxes.len() < 2 {
            ui.colored_label(Color32::YELLOW, "Synkronointi vaatii vähintään kaksi tallennettua boksia 'Boksin hallinta' -välilehdellä.");
            return;
        }

        ui.horizontal(|ui| {
            ui.strong("Lähdeboksi (Kopioidaan tästä):");
            let source_name = boxes.iter().find(|b| Some(&b.id) == self.source_box_id.as_ref()).map(|b| b.name.as_str()).unwrap_or("Valitse");
            egui::ComboBox::from_id_salt("source_box_combo").selected_text(source_name).show_ui(ui, |ui| {
                for b in boxes {
                    if ui.selectable_label(Some(&b.id) == self.source_box_id.as_ref(), &b.name).clicked() {
                        self.source_box_id = Some(b.id.clone());
                    }
                }
            });

            ui.add_space(20.0);

            ui.strong("Kohdeboksi (Päivitetään tähän):");
            let target_name = boxes.iter().find(|b| Some(&b.id) == self.target_box_id.as_ref()).map(|b| b.name.as_str()).unwrap_or("Valitse");
            egui::ComboBox::from_id_salt("target_box_combo").selected_text(target_name).show_ui(ui, |ui| {
                for b in boxes {
                    if ui.selectable_label(Some(&b.id) == self.target_box_id.as_ref(), &b.name).clicked() {
                        self.target_box_id = Some(b.id.clone());
                    }
                }
            });

            if ui.button("🔍 Vertaa asetuksia").clicked() {
                if let (Some(s_id), Some(t_id)) = (&self.source_box_id, &self.target_box_id) {
                    if let (Some(sb), Some(tb)) = (boxes.iter().find(|b| &b.id == s_id), boxes.iter().find(|b| &b.id == t_id)) {
                        match (SettingsSyncService::fetch_box_settings(sb), SettingsSyncService::fetch_box_settings(tb)) {
                            (Ok(s_txt), Ok(t_txt)) => {
                                let s_map = SettingsSyncService::parse_settings(&s_txt);
                                let t_map = SettingsSyncService::parse_settings(&t_txt);
                                self.diffs = SettingsSyncService::compare(&s_map, &t_map);
                                self.status_msg = Some(format!("Vertailu valmis: {} asetusta tarkistettu.", self.diffs.len()));
                            }
                            _ => {
                                self.status_msg = Some("Asetusten haku toisesta tai molemmista bokseista epäonnistui.".to_string());
                            }
                        }
                    }
                }
            }
        });

        if let Some(msg) = &self.status_msg {
            ui.add_space(4.0);
            ui.label(RichText::new(msg).color(Color32::from_rgb(59, 130, 246)));
        }

        ui.add_space(8.0);

        if !self.diffs.is_empty() {
            ui.horizontal(|ui| {
                ui.label("Etsi asetusta:");
                ui.text_edit_singleline(&mut self.search_query);

                if ui.button("Valitse kaikki erot").clicked() {
                    for d in &mut self.diffs {
                        if d.is_different { d.selected = true; }
                    }
                }
                if ui.button("Poista valinnat").clicked() {
                    for d in &mut self.diffs { d.selected = false; }
                }
            });

            ui.add_space(4.0);

            ScrollArea::vertical().id_salt("sync_diff_scroll").max_height(450.0).show(ui, |ui| {
                let q = self.search_query.to_lowercase();
                for d in &mut self.diffs {
                    if !q.is_empty() && !d.key.to_lowercase().contains(&q) {
                        continue;
                    }

                    ui.horizontal(|ui| {
                        ui.checkbox(&mut d.selected, "");
                        let color = if d.is_different { Color32::from_rgb(234, 179, 8) } else { Color32::GRAY };
                        ui.label(RichText::new(&d.key).color(color));

                        ui.label(format!("Lähde: '{}'", d.source_val.as_deref().unwrap_or("-")));
                        ui.label(format!("Kohde: '{}'", d.target_val.as_deref().unwrap_or("-")));
                    });
                }
            });
        }
    }
}
