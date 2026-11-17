use egui::{Color32, RichText, Ui};
use std::sync::mpsc::Receiver;
use crate::models::EnigmaBox;
use crate::services::{BoxStorage, DiscoveredBox, NetworkScanner, OpenWebifClient};
use crate::i18n::Language;

pub struct BoxManagerView {
    pub edit_name: String,
    pub edit_ip: String,
    pub edit_port: String,
    pub edit_user: String,
    pub edit_pass: String,
    pub selected_box_id: Option<String>,
    pub status_msg: Option<(String, bool)>, // (message, is_error)

    pub is_scanning: bool,
    pub scan_receiver: Option<Receiver<DiscoveredBox>>,
    pub discovered_boxes: Vec<DiscoveredBox>,
}

impl Default for BoxManagerView {
    fn default() -> Self {
        Self {
            edit_name: "Vu+ Duo 4K SE".to_string(),
            edit_ip: "192.168.68.79".to_string(),
            edit_port: "80".to_string(),
            edit_user: "root".to_string(),
            edit_pass: String::new(),
            selected_box_id: None,
            status_msg: None,
            is_scanning: false,
            scan_receiver: None,
            discovered_boxes: Vec::new(),
        }
    }
}

impl BoxManagerView {
    pub fn render(
        &mut self,
        ui: &mut Ui,
        boxes: &mut Vec<EnigmaBox>,
        active_box_id: &mut Option<String>,
        _lang: Language,
    ) {
        // Poll background network scanner
        if let Some(rx) = &self.scan_receiver {
            while let Ok(disc) = rx.try_recv() {
                if !self.discovered_boxes.iter().any(|b| b.ip == disc.ip) {
                    self.discovered_boxes.push(disc);
                }
            }
        }

        ui.heading("⚙ Enigma2-laitteiden hallinta");
        ui.label("Lisää, muokkaa ja testaa yhteyksiä kotiverkkosi Enigma2-digibokseihin.");
        ui.add_space(8.0);

        if let Some((msg, is_error)) = &self.status_msg {
            let color = if *is_error { Color32::RED } else { Color32::GREEN };
            ui.colored_label(color, msg);
            ui.add_space(4.0);
        }

        ui.columns(2, |cols| {
            // Left column: Boxes List & Discovery
            cols[0].group(|ui| {
                ui.strong("Tallennetut vastaanottimet:");
                ui.add_space(4.0);

                let mut to_delete = None;
                let mut to_select = None;

                for (idx, b) in boxes.iter().enumerate() {
                    let is_active = active_box_id.as_deref() == Some(&b.id);
                    let is_selected = self.selected_box_id.as_deref() == Some(&b.id);

                    ui.horizontal(|ui| {
                        let dot = if b.is_online { "🟢" } else { "⚪" };
                        let name_label = format!("{} {}", dot, b.name);
                        
                        if ui.selectable_label(is_selected, name_label).clicked() {
                            to_select = Some(b.id.clone());
                        }

                        if is_active {
                            ui.colored_label(Color32::from_rgb(59, 130, 246), "[Aktiivinen]");
                        } else if ui.small_button("Valitse").clicked() {
                            *active_box_id = Some(b.id.clone());
                            BoxStorage::save_prefs(active_box_id.as_deref(), crate::models::NavigationTab::BoxManager, _lang.code());
                        }

                        if ui.small_button("❌").clicked() {
                            to_delete = Some(idx);
                        }
                    });

                    ui.label(format!("  {} (Portti: {})", b.ip, b.port));
                    if let Some(model) = &b.model {
                        ui.label(format!("  Malli: {} | Distro: {}", model, b.distro.as_deref().unwrap_or("-")));
                    }
                    ui.separator();
                }

                if let Some(id) = to_select {
                    self.selected_box_id = Some(id.clone());
                    if let Some(b) = boxes.iter().find(|b| b.id == id) {
                        self.edit_name = b.name.clone();
                        self.edit_ip = b.ip.clone();
                        self.edit_port = b.port.to_string();
                        self.edit_user = b.username.clone();
                        self.edit_pass = b.password.clone();
                    }
                }

                if let Some(del_idx) = to_delete {
                    boxes.remove(del_idx);
                    BoxStorage::save_boxes(boxes);
                    self.status_msg = Some(("Boksi poistettu.".to_string(), false));
                }

                ui.add_space(10.0);
                ui.separator();
                ui.add_space(4.0);

                // Auto-Discovery Section
                ui.horizontal(|ui| {
                    let scan_btn_label = if self.is_scanning {
                        "⏳ Etsitään verkosta..."
                    } else {
                        "🔍 Etsi boksit verkosta"
                    };

                    if ui.button(scan_btn_label).clicked() && !self.is_scanning {
                        self.is_scanning = true;
                        self.discovered_boxes.clear();

                        let prefix = if let Some(dot_idx) = self.edit_ip.rfind('.') {
                            format!("{}.", &self.edit_ip[..dot_idx])
                        } else {
                            "192.168.68.".to_string()
                        };
                        self.scan_receiver = Some(NetworkScanner::start_scan(prefix));
                    }

                    if self.is_scanning && ui.small_button("Pysäytä").clicked() {
                        self.is_scanning = false;
                        self.scan_receiver = None;
                    }
                });

                if !self.discovered_boxes.is_empty() {
                    ui.add_space(6.0);
                    ui.strong("Löydetyt vastaanottimet lähiverkosta:");
                    let mut add_disc_idx = None;

                    for (d_idx, disc) in self.discovered_boxes.iter().enumerate() {
                        let already_added = boxes.iter().any(|b| b.ip == disc.ip);
                        ui.horizontal(|ui| {
                            let label = format!("• {} ({}) - {}", disc.model, disc.brand, disc.ip);
                            ui.label(label);
                            if already_added {
                                ui.colored_label(Color32::from_gray(140), "Tallennettu");
                            } else if ui.small_button("➕ Lisää").clicked() {
                                add_disc_idx = Some(d_idx);
                            }
                        });
                    }

                    if let Some(idx) = add_disc_idx {
                        let disc = &self.discovered_boxes[idx];
                        let mut nb = EnigmaBox::new(&format!("Vu+ {}", disc.model), &disc.ip);
                        nb.port = disc.port;
                        nb.model = Some(disc.model.clone());
                        nb.is_online = true;
                        let id = nb.id.clone();
                        boxes.push(nb);
                        BoxStorage::save_boxes(boxes);
                        *active_box_id = Some(id);
                        self.status_msg = Some((format!("Lisätty {} ({}) ja valittu aktiiviseksi!", disc.model, disc.ip), false));
                    }
                }
            });

            // Right column: Add / Edit Form
            cols[1].group(|ui| {
                ui.strong("Boksin tiedot / Muokkaus:");
                ui.add_space(4.0);

                ui.horizontal(|ui| {
                    ui.label("Nimi:        ");
                    ui.text_edit_singleline(&mut self.edit_name);
                });

                ui.horizontal(|ui| {
                    ui.label("IP-osoite:   ");
                    ui.text_edit_singleline(&mut self.edit_ip);
                });

                ui.horizontal(|ui| {
                    ui.label("Portti:      ");
                    ui.text_edit_singleline(&mut self.edit_port);
                });

                ui.horizontal(|ui| {
                    ui.label("Käyttäjänimi:");
                    ui.text_edit_singleline(&mut self.edit_user);
                });

                ui.horizontal(|ui| {
                    ui.label("Salasana:    ");
                    ui.add(egui::TextEdit::singleline(&mut self.edit_pass).password(true));
                });

                ui.add_space(8.0);

                ui.horizontal(|ui| {
                    if ui.button(RichText::new("➕ Lisää uutena").strong()).clicked() {
                        let port = self.edit_port.parse().unwrap_or(80);
                        let mut new_box = EnigmaBox::new(&self.edit_name, &self.edit_ip);
                        new_box.port = port;
                        new_box.username = self.edit_user.clone();
                        new_box.password = self.edit_pass.clone();
                        
                        let id = new_box.id.clone();
                        boxes.push(new_box);
                        BoxStorage::save_boxes(boxes);
                        *active_box_id = Some(id);
                        self.status_msg = Some(("Uusi boksi lisätty ja valittu aktiiviseksi!".to_string(), false));
                    }

                    if ui.button("💾 Tallenna muutokset").clicked() {
                        if let Some(id) = &self.selected_box_id {
                            if let Some(b) = boxes.iter_mut().find(|b| &b.id == id) {
                                b.name = self.edit_name.clone();
                                b.ip = self.edit_ip.clone();
                                b.port = self.edit_port.parse().unwrap_or(80);
                                b.username = self.edit_user.clone();
                                b.password = self.edit_pass.clone();
                                BoxStorage::save_boxes(boxes);
                                self.status_msg = Some(("Muutokset tallennettu!".to_string(), false));
                            }
                        }
                    }

                    if ui.button("🔍 Testaa yhteys").clicked() {
                        let port = self.edit_port.parse().unwrap_or(80);
                        let mut test_box = EnigmaBox::new(&self.edit_name, &self.edit_ip);
                        test_box.port = port;
                        test_box.username = self.edit_user.clone();
                        test_box.password = self.edit_pass.clone();

                        match OpenWebifClient::test_connection(&mut test_box) {
                            Ok(()) => {
                                let model = test_box.model.unwrap_or_else(|| "Tuntematon".to_string());
                                let distro = test_box.distro.unwrap_or_else(|| "Tuntematon".to_string());
                                self.status_msg = Some((format!("Yhteys toimii! Malli: {} | Ohjelmisto: {}", model, distro), false));
                                
                                // Update existing box if editing
                                if let Some(id) = &self.selected_box_id {
                                    if let Some(b) = boxes.iter_mut().find(|b| &b.id == id) {
                                        b.model = Some(model);
                                        b.distro = Some(distro);
                                        b.is_online = true;
                                        b.tuners = test_box.tuners;
                                        BoxStorage::save_boxes(boxes);
                                    }
                                }
                            }
                            Err(e) => {
                                self.status_msg = Some((format!("Yhteys epäonnistui: {}", e), true));
                            }
                        }
                    }
                });
            });
        });
    }
}
