use std::fs;
use std::path::PathBuf;
use std::collections::HashMap;
use crate::models::{EnigmaBox, NavigationTab};

pub struct BoxStorage;

impl BoxStorage {
    pub fn config_dir() -> PathBuf {
        let base = dirs::config_dir().unwrap_or_else(|| PathBuf::from("."));
        let dir = base.join("EnigmaSuite");
        if !dir.exists() {
            let _ = fs::create_dir_all(&dir);
        }
        dir
    }

    pub fn boxes_file() -> PathBuf {
        Self::config_dir().join("boxes.json")
    }

    pub fn prefs_file() -> PathBuf {
        Self::config_dir().join("prefs.json")
    }

    pub fn load_boxes() -> Vec<EnigmaBox> {
        let path = Self::boxes_file();
        if path.exists() {
            if let Ok(content) = fs::read_to_string(&path) {
                if let Ok(boxes) = serde_json::from_str::<Vec<EnigmaBox>>(&content) {
                    let valid: Vec<EnigmaBox> = boxes
                        .into_iter()
                        .filter(|b| !(b.name == "Enigma2" && b.model.as_deref() == Some("Enigma2") && b.tuners.is_empty()))
                        .collect();
                    if !valid.is_empty() {
                        return valid;
                    }
                }
            }
        }

        // Default initial boxes if none exist
        vec![
            EnigmaBox::new("Vu+ Duo 4K SE", "192.168.68.79"),
            EnigmaBox::new("Vu+ Duo4kLite", "192.168.68.84"),
        ]
    }

    pub fn save_boxes(boxes: &[EnigmaBox]) {
        let path = Self::boxes_file();
        if let Ok(json) = serde_json::to_string_pretty(boxes) {
            let _ = fs::write(path, json);
        }
    }

    pub fn load_prefs() -> (Option<String>, NavigationTab, String) {
        let path = Self::prefs_file();
        let mut active_id = None;
        let mut tab = NavigationTab::BoxManager;
        let mut lang = "fi".to_string();

        if path.exists() {
            if let Ok(content) = fs::read_to_string(&path) {
                if let Ok(dict) = serde_json::from_str::<HashMap<String, String>>(&content) {
                    if let Some(id) = dict.get("activeBoxId") {
                        if !id.is_empty() {
                            active_id = Some(id.clone());
                        }
                    }
                    if let Some(t) = dict.get("selectedTab") {
                        tab = match t.as_str() {
                            "Remote" => NavigationTab::Remote,
                            "TimersAndMovies" => NavigationTab::TimersAndMovies,
                            "Channels" => NavigationTab::Channels,
                            "SettingsSync" => NavigationTab::SettingsSync,
                            "Bootlogo" => NavigationTab::Bootlogo,
                            "ImageManager" => NavigationTab::ImageManager,
                            "Support" => NavigationTab::Support,
                            _ => NavigationTab::BoxManager,
                        };
                    }
                    if let Some(l) = dict.get("language") {
                        if l == "en" || l == "fi" {
                            lang = l.clone();
                        }
                    }
                }
            }
        }

        (active_id, tab, lang)
    }

    pub fn save_prefs(active_id: Option<&str>, tab: NavigationTab, lang: &str) {
        let path = Self::prefs_file();
        let mut dict = HashMap::new();
        if path.exists() {
            if let Ok(content) = fs::read_to_string(&path) {
                if let Ok(existing) = serde_json::from_str::<HashMap<String, String>>(&content) {
                    dict = existing;
                }
            }
        }

        if let Some(id) = active_id {
            dict.insert("activeBoxId".to_string(), id.to_string());
        } else {
            dict.remove("activeBoxId");
        }

        let tab_str = match tab {
            NavigationTab::Remote => "Remote",
            NavigationTab::TimersAndMovies => "TimersAndMovies",
            NavigationTab::Channels => "Channels",
            NavigationTab::SettingsSync => "SettingsSync",
            NavigationTab::Bootlogo => "Bootlogo",
            NavigationTab::ImageManager => "ImageManager",
            NavigationTab::Support => "Support",
            NavigationTab::BoxManager => "BoxManager",
        };
        dict.insert("selectedTab".to_string(), tab_str.to_string());
        dict.insert("language".to_string(), lang.to_string());

        if let Ok(json) = serde_json::to_string_pretty(&dict) {
            let _ = fs::write(path, json);
        }
    }
}
