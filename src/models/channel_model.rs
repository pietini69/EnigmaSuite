use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Bouquet {
    pub name: String,
    #[serde(rename = "servicereference", alias = "sRef", alias = "ref")]
    pub s_ref: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Channel {
    pub name: String,
    #[serde(rename = "servicereference", alias = "sRef", alias = "ref")]
    pub s_ref: String,
    #[serde(default)]
    pub now_title: Option<String>,
    #[serde(default)]
    pub now_desc: Option<String>,
    #[serde(default)]
    pub next_title: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EpgEvent {
    #[serde(default)]
    pub id: i64,
    #[serde(default)]
    pub title: String,
    #[serde(default, rename = "longdesc", alias = "description")]
    pub description: String,
    #[serde(default, rename = "begin_timestamp", alias = "begin")]
    pub begin_timestamp: i64,
    #[serde(default, rename = "duration_sec", alias = "duration")]
    pub duration_sec: i64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct CurrentPlaybackInfo {
    #[serde(default)]
    pub channel_name: String,
    #[serde(default)]
    pub service_ref: String,
    #[serde(default)]
    pub event_title: String,
    #[serde(default)]
    pub event_description: String,
    #[serde(default)]
    pub duration_sec: i64,
    #[serde(default)]
    pub remaining_sec: i64,
    #[serde(default)]
    pub progress_percent: f32,
    #[serde(default)]
    pub volume: u8,
    #[serde(default)]
    pub is_muted: bool,
    #[serde(default)]
    pub is_standby: bool,
}
