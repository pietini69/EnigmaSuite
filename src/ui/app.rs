use eframe::egui::{self, Color32, RichText, TopBottomPanel, SidePanel, CentralPanel};
use crate::models::{EnigmaBox, NavigationTab};
use crate::services::{BoxStorage, OpenWebifClient};
use crate::i18n::Language;
use crate::ui::views::{
    BootlogoView, BoxManagerView, ChannelsView, ImageView, RemoteView, SettingsSyncView, SupportView, TimersView,
};

pub struct EnigmaSuiteApp {
    pub boxes: Vec<EnigmaBox>,
    pub active_box_id: Option<String>,
    pub selected_tab: NavigationTab,
    pub language: Language,

    // Views
    pub box_manager_view: BoxManagerView,
    pub remote_view: RemoteView,
    pub channels_view: ChannelsView,
    pub timers_view: TimersView,
    pub sync_view: SettingsSyncView,
    pub bootlogo_view: BootlogoView,
    pub image_view: ImageView,
    pub support_view: SupportView,
}

impl Default for EnigmaSuiteApp {
    fn default() -> Self {
        let boxes = BoxStorage::load_boxes();
        let (active_id, tab, lang_code) = BoxStorage::load_prefs();
        let language = Language::from_code(&lang_code);

        let active_box_id = if let Some(id) = active_id {
            if boxes.iter().any(|b| b.id == id) {
                Some(id)
            } else {
                boxes.first().map(|b| b.id.clone())
            }
        } else {
            boxes.first().map(|b| b.id.clone())
        };

        Self {
            boxes,
            active_box_id,
            selected_tab: tab,
            language,
            box_manager_view: BoxManagerView::default(),
            remote_view: RemoteView::default(),
            channels_view: ChannelsView::default(),
            timers_view: TimersView::default(),
            sync_view: SettingsSyncView::default(),
            bootlogo_view: BootlogoView::default(),
            image_view: ImageView::default(),
            support_view: SupportView::default(),
        }
    }
}

impl EnigmaSuiteApp {
    pub fn active_box(&self) -> Option<&EnigmaBox> {
        let id = self.active_box_id.as_ref()?;
        self.boxes.iter().find(|b| &b.id == id)
    }

    pub fn active_box_mut(&mut self) -> Option<&mut EnigmaBox> {
        let id = self.active_box_id.as_ref()?;
        self.boxes.iter_mut().find(|b| &b.id == id)
    }

    pub fn refresh_active_box(&mut self) {
        if let Some(b) = self.active_box_mut() {
            let _ = OpenWebifClient::test_connection(b);
        }
        BoxStorage::save_boxes(&self.boxes);
    }
}

impl eframe::App for EnigmaSuiteApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Top Bar
        TopBottomPanel::top("top_panel").show(ctx, |ui| {
            ui.add_space(4.0);
            ui.horizontal(|ui| {
                ui.heading(RichText::new("EnigmaSuite").color(Color32::from_rgb(59, 130, 246)).strong());
                ui.label(RichText::new("v2.0").small().color(Color32::GRAY));

                ui.separator();

                // Active Box Selector
                ui.label(self.language.active_box_label());
                let current_name = self.active_box().map(|b| b.name.as_str()).unwrap_or("Ei valittu");
                let is_online = self.active_box().map(|b| b.is_online).unwrap_or(false);

                let dot = if is_online { "🟢" } else { "⚪" };
                let combo_label = format!("{} {}", dot, current_name);

                let mut changed_box = None;
                egui::ComboBox::from_id_salt("top_active_box_combo").selected_text(combo_label).show_ui(ui, |ui| {
                    for b in &self.boxes {
                        let dot = if b.is_online { "🟢" } else { "⚪" };
                        let label = format!("{} {}", dot, b.name);
                        let is_sel = self.active_box_id.as_deref() == Some(&b.id);
                        if ui.selectable_label(is_sel, label).clicked() {
                            changed_box = Some(b.id.clone());
                        }
                    }
                });

                if let Some(new_id) = changed_box {
                    self.active_box_id = Some(new_id);
                    BoxStorage::save_prefs(self.active_box_id.as_deref(), self.selected_tab, self.language.code());
                    self.refresh_active_box();
                }

                if ui.button("🔄").on_hover_text(self.language.refresh_btn()).clicked() {
                    self.refresh_active_box();
                }

                // Quick Power actions
                if let Some(b) = self.active_box() {
                    if ui.button("⏻").on_hover_text("Vaihda valmiustilaa (Standby)").clicked() {
                        let _ = OpenWebifClient::set_powerstate(b, 0);
                    }
                }

                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    // Language switcher
                    if ui.selectable_label(self.language == Language::English, "🇬🇧 EN").clicked() {
                        self.language = Language::English;
                        BoxStorage::save_prefs(self.active_box_id.as_deref(), self.selected_tab, self.language.code());
                    }
                    if ui.selectable_label(self.language == Language::Finnish, "🇫🇮 FI").clicked() {
                        self.language = Language::Finnish;
                        BoxStorage::save_prefs(self.active_box_id.as_deref(), self.selected_tab, self.language.code());
                    }
                });
            });
            ui.add_space(4.0);
        });

        // Left Navigation Sidebar
        SidePanel::left("left_nav_panel").min_width(200.0).max_width(220.0).show(ctx, |ui| {
            ui.add_space(8.0);
            let tabs = [
                NavigationTab::BoxManager,
                NavigationTab::Remote,
                NavigationTab::Channels,
                NavigationTab::TimersAndMovies,
                NavigationTab::SettingsSync,
                NavigationTab::Bootlogo,
                NavigationTab::ImageManager,
                NavigationTab::Support,
            ];

            for tab in tabs {
                let is_sel = self.selected_tab == tab;
                let text = format!("{} {}", tab.icon(), self.language.tab_title(tab));
                
                let btn = ui.add_sized(
                    egui::Vec2::new(ui.available_width(), 34.0),
                    egui::SelectableLabel::new(is_sel, RichText::new(text).size(13.0)),
                );

                if btn.clicked() {
                    self.selected_tab = tab;
                    BoxStorage::save_prefs(self.active_box_id.as_deref(), self.selected_tab, self.language.code());
                }
                ui.add_space(2.0);
            }
        });

        // Main Content Area
        CentralPanel::default().show(ctx, |ui| {
            let active_box = self.active_box().cloned();
            match self.selected_tab {
                NavigationTab::BoxManager => {
                    self.box_manager_view.render(ui, &mut self.boxes, &mut self.active_box_id, self.language);
                }
                NavigationTab::Remote => {
                    self.remote_view.render(ui, active_box.as_ref(), self.language);
                }
                NavigationTab::Channels => {
                    self.channels_view.render(ui, active_box.as_ref(), self.language);
                }
                NavigationTab::TimersAndMovies => {
                    self.timers_view.render(ui, active_box.as_ref(), self.language);
                }
                NavigationTab::SettingsSync => {
                    self.sync_view.render(ui, &self.boxes, self.language);
                }
                NavigationTab::Bootlogo => {
                    self.bootlogo_view.render(ui, active_box.as_ref(), self.language);
                }
                NavigationTab::ImageManager => {
                    self.image_view.render(ui, active_box.as_ref(), self.language);
                }
                NavigationTab::Support => {
                    self.support_view.render(ui, active_box.as_ref(), self.language);
                }
            }
        });
    }
}
