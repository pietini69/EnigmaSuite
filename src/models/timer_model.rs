use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimerItem {
    #[serde(default)]
    pub name: String,
    #[serde(default, rename = "servicename")]
    pub service_name: String,
    #[serde(default, rename = "servicereference", alias = "sRef", alias = "serviceref")]
    pub service_ref: String,
    #[serde(default, rename = "description")]
    pub description: String,
    #[serde(default)]
    pub begin: i64,
    #[serde(default)]
    pub end: i64,
    #[serde(default)]
    pub duration: i64,
    #[serde(default)]
    pub state: i32,
    #[serde(default)]
    pub disabled: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AutoTimerRule {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub match_pattern: String,
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub service_name: String,
    #[serde(default)]
    pub service_ref: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MovieItem {
    #[serde(default, rename = "eventname", alias = "title", alias = "name")]
    pub name: String,
    #[serde(default, rename = "servicename")]
    pub service_name: String,
    #[serde(default, rename = "serviceref", alias = "servicereference", alias = "sRef", alias = "fullname")]
    pub service_ref: String,
    #[serde(default, rename = "description", alias = "descriptionExtended")]
    pub description: String,
    #[serde(default, rename = "filename", alias = "filename_stripped")]
    pub filename: String,
    #[serde(default, rename = "filesize")]
    pub filesize: i64,
    #[serde(default, rename = "filesize_readable")]
    pub filesize_readable: String,
    #[serde(default, rename = "recordingtime")]
    pub recording_time: i64,
    #[serde(default, rename = "length")]
    pub length: String,
}
