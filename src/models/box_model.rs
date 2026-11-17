use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum NavigationTab {
    BoxManager,
    Remote,
    Channels,
    TimersAndMovies,
    SettingsSync,
    Bootlogo,
    ImageManager,
    Support,
}

impl NavigationTab {
    pub fn icon(&self) -> &'static str {
        match self {
            NavigationTab::BoxManager => "🎛️",
            NavigationTab::Remote => "📱",
            NavigationTab::Channels => "📺",
            NavigationTab::TimersAndMovies => "⏱️",
            NavigationTab::SettingsSync => "🔄",
            NavigationTab::Bootlogo => "🎨",
            NavigationTab::ImageManager => "💾",
            NavigationTab::Support => "ℹ️",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TunerInfo {
    pub name: String,
    #[serde(rename = "type", default)]
    pub tuner_type: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnigmaBox {
    #[serde(default = "default_id")]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub ip: String,
    #[serde(default = "default_port")]
    pub port: u16,
    #[serde(default)]
    pub is_online: bool,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub distro: Option<String>,
    #[serde(default = "default_username")]
    pub username: String,
    #[serde(default)]
    pub password: String,
    #[serde(default)]
    pub tuners: Vec<TunerInfo>,
}

fn default_id() -> String {
    Uuid::new_v4().to_string()
}

fn default_port() -> u16 {
    80
}

fn default_username() -> String {
    "root".to_string()
}

impl Default for EnigmaBox {
    fn default() -> Self {
        Self {
            id: default_id(),
            name: "Uusi Enigma2-boksi".to_string(),
            ip: "192.168.1.100".to_string(),
            port: 80,
            is_online: false,
            model: None,
            distro: None,
            username: "root".to_string(),
            password: String::new(),
            tuners: Vec::new(),
        }
    }
}

impl EnigmaBox {
    pub fn new(name: &str, ip: &str) -> Self {
        Self {
            id: default_id(),
            name: name.to_string(),
            ip: ip.to_string(),
            port: 80,
            is_online: false,
            model: None,
            distro: None,
            username: "root".to_string(),
            password: String::new(),
            tuners: Vec::new(),
        }
    }

    pub fn base_url(&self) -> String {
        if self.port == 80 {
            format!("http://{}", self.ip)
        } else {
            format!("http://{}:{}", self.ip, self.port)
        }
    }

    pub fn stream_url(&self, s_ref: &str) -> String {
        format!("http://{}:8001/{}", self.ip, s_ref)
    }

    pub fn has_auth(&self) -> bool {
        !self.password.is_empty()
    }
}
