use std::collections::BTreeMap;
use crate::models::EnigmaBox;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SettingDiff {
    pub key: String,
    pub source_val: Option<String>,
    pub target_val: Option<String>,
    pub is_different: bool,
    pub selected: bool,
}

pub struct SettingsSyncService;

impl SettingsSyncService {
    /// Parses Enigma2 /etc/enigma2/settings text into a sorted map
    pub fn parse_settings(content: &str) -> BTreeMap<String, String> {
        let mut map = BTreeMap::new();
        for line in content.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some((k, v)) = line.split_once('=') {
                map.insert(k.trim().to_string(), v.trim().to_string());
            }
        }
        map
    }

    /// Compares two parsed settings maps
    pub fn compare(source: &BTreeMap<String, String>, target: &BTreeMap<String, String>) -> Vec<SettingDiff> {
        let mut diffs = Vec::new();
        let mut all_keys: std::collections::BTreeSet<&String> = source.keys().collect();
        all_keys.extend(target.keys());

        for key in all_keys {
            let s_val = source.get(key).cloned();
            let t_val = target.get(key).cloned();
            let is_diff = s_val != t_val;

            diffs.push(SettingDiff {
                key: key.clone(),
                source_val: s_val,
                target_val: t_val,
                is_different: is_diff,
                selected: is_diff, // Select differences by default
            });
        }

        diffs
    }

    /// Fetches settings text via OpenWebif /file?file=/etc/enigma2/settings
    pub fn fetch_box_settings(b: &EnigmaBox) -> Result<String, String> {
        let path = "/file?file=/etc/enigma2/settings";
        let url = format!("{}{}", b.base_url(), path);
        let resp = ureq::get(&url)
            .timeout(std::time::Duration::from_secs(6))
            .call()
            .map_err(|e| format!("Virhe ladattaessa asetuksia: {}", e))?;

        resp.into_string().map_err(|e| e.to_string())
    }
}
