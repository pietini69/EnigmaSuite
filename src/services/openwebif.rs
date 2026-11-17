use crate::models::{AutoTimerRule, Bouquet, Channel, CurrentPlaybackInfo, EnigmaBox, EpgEvent, MovieItem, TimerItem, TunerInfo};
use base64::Engine;
use serde_json::Value;
use std::time::Duration;

#[allow(dead_code)]
pub struct OpenWebifClient;

#[allow(dead_code)]
impl OpenWebifClient {
    fn build_get(b: &EnigmaBox, path: &str) -> ureq::Request {
        let url = if path.starts_with('/') {
            format!("{}{}", b.base_url(), path)
        } else {
            format!("{}/{}", b.base_url(), path)
        };
        let mut req = ureq::get(&url).timeout(Duration::from_secs(6));
        if b.has_auth() {
            let cred = format!("{}:{}", b.username, b.password);
            let encoded = base64::engine::general_purpose::STANDARD.encode(cred);
            req = req.set("Authorization", &format!("Basic {}", encoded));
        }
        req
    }

    /// Fetches receiver info from /api/about
    pub fn test_connection(b: &mut EnigmaBox) -> Result<(), String> {
        let resp = Self::build_get(b, "/api/about")
            .call()
            .map_err(|e| format!("Yhteysvirhe: {}", e))?;

        let val: Value = resp.into_json().map_err(|e| format!("JSON-virhe: {}", e))?;
        let info = val.get("info").unwrap_or(&val);

        if let Some(model) = info.get("model").and_then(|v| v.as_str()) {
            b.model = Some(model.to_string());
        }
        if let Some(distro) = info.get("imagedistro")
            .or_else(|| info.get("friendlyimagedistro"))
            .or_else(|| info.get("distro"))
            .and_then(|v| v.as_str())
        {
            b.distro = Some(distro.to_string());
        }

        // Tuners
        if let Some(tuners_arr) = info.get("tuners").and_then(|v| v.as_array()) {
            let mut list = Vec::new();
            for t in tuners_arr {
                if let Some(name) = t.get("name").and_then(|v| v.as_str()) {
                    let type_name = t.get("type").and_then(|v| v.as_str()).unwrap_or("");
                    list.push(TunerInfo {
                        name: name.to_string(),
                        tuner_type: type_name.to_string(),
                    });
                }
            }
            b.tuners = list;
        }

        b.is_online = true;
        Ok(())
    }

    /// Fetches current playback info from /api/getcurrent
    pub fn get_current_playback(b: &EnigmaBox) -> Result<CurrentPlaybackInfo, String> {
        let resp = Self::build_get(b, "/api/getcurrent")
            .call()
            .map_err(|e| e.to_string())?;

        let val: Value = resp.into_json().map_err(|e| e.to_string())?;
        let mut info = CurrentPlaybackInfo::default();

        let obj = val.get("info").unwrap_or(&val);
        if let Some(ch) = obj.get("name").and_then(|v| v.as_str()) {
            info.channel_name = ch.to_string();
        }
        if let Some(sref) = obj.get("ref").or_else(|| obj.get("sRef")).and_then(|v| v.as_str()) {
            info.service_ref = sref.to_string();
        }
        if let Some(title) = obj.get("title").and_then(|v| v.as_str()) {
            info.event_title = title.to_string();
        }
        if let Some(desc) = obj.get("description").or_else(|| obj.get("desc")).and_then(|v| v.as_str()) {
            info.event_description = desc.to_string();
        }
        if let Some(dur) = obj.get("duration").and_then(|v| v.as_i64()) {
            info.duration_sec = dur;
        }
        if let Some(rem) = obj.get("remaining").and_then(|v| v.as_i64()) {
            info.remaining_sec = rem;
        }

        if info.duration_sec > 0 {
            let elapsed = info.duration_sec - info.remaining_sec;
            info.progress_percent = (elapsed as f32 / info.duration_sec as f32).clamp(0.0, 1.0);
        }

        Ok(info)
    }

    /// Sends a remote control key code to /api/remotecontrol?type=0&key={code}
    pub fn send_remote_key(b: &EnigmaBox, key_name: &str) -> Result<(), String> {
        let code = match key_name {
            "KEY_POWER" => 116,
            "KEY_MUTE" => 113,
            "KEY_TV" => 377,
            "KEY_MODE" => 385,
            "KEY_1" => 2,
            "KEY_2" => 3,
            "KEY_3" => 4,
            "KEY_4" => 5,
            "KEY_5" => 6,
            "KEY_6" => 7,
            "KEY_7" => 8,
            "KEY_8" => 9,
            "KEY_9" => 10,
            "KEY_0" => 11,
            "KEY_PREVIOUS" => 412,
            "KEY_NEXT" => 407,
            "KEY_VOLUMEUP" => 115,
            "KEY_VOLUMEDOWN" => 114,
            "KEY_UP" => 103,
            "KEY_DOWN" => 108,
            "KEY_LEFT" => 105,
            "KEY_RIGHT" => 106,
            "KEY_OK" => 352,
            "KEY_CHANNELUP" => 402,
            "KEY_CHANNELDOWN" => 403,
            "KEY_MENU" => 139,
            "KEY_EXIT" => 174,
            "KEY_INFO" => 358,
            "KEY_EPG" => 365,
            "KEY_AUDIO" => 392,
            "KEY_SUBTITLE" => 370,
            "KEY_RED" => 398,
            "KEY_GREEN" => 399,
            "KEY_YELLOW" => 400,
            "KEY_BLUE" => 401,
            "KEY_REWIND" => 168,
            "KEY_PLAY" => 207,
            "KEY_PAUSE" => 119,
            "KEY_FASTFORWARD" => 159,
            "KEY_STOP" => 128,
            "KEY_RECORD" => 167,
            _ => return Err(format!("Tuntematon kaukosäädinnäppäin: {}", key_name)),
        };

        let path = format!("/api/remotecontrol?type=0&key={}", code);
        let _ = Self::build_get(b, &path).call().map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Sets volume (0-100)
    pub fn set_volume(b: &EnigmaBox, vol: u8) -> Result<(), String> {
        let path = format!("/api/vol?set=set{}", vol);
        let _ = Self::build_get(b, &path).call().map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Toggles audio mute
    pub fn toggle_mute(b: &EnigmaBox) -> Result<(), String> {
        let path = "/api/vol?set=mute";
        let _ = Self::build_get(b, path).call().map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Sets power state: 0=Toggle Standby, 1=Deep Standby, 2=Reboot Box, 3=Restart GUI
    pub fn set_powerstate(b: &EnigmaBox, state: i32) -> Result<(), String> {
        let path = format!("/api/powerstate?newstate={}", state);
        let _ = Self::build_get(b, &path).call().map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Zaps to a channel sRef
    pub fn zap(b: &EnigmaBox, s_ref: &str) -> Result<(), String> {
        let path = format!("/api/zap?sRef={}", urlencoding::encode(s_ref));
        let _ = Self::build_get(b, &path).call().map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Fetches list of bouquets (TV or Radio)
    pub fn fetch_bouquets(b: &EnigmaBox, is_radio: bool) -> Result<Vec<Bouquet>, String> {
        let path = if is_radio { "/api/bouquets?stype=radio" } else { "/api/bouquets" };
        let resp = Self::build_get(b, path).call().map_err(|e| e.to_string())?;
        let val: Value = resp.into_json().map_err(|e| e.to_string())?;

        let mut list = Vec::new();
        if let Some(bouquets) = val.get("bouquets").and_then(|v| v.as_array()) {
            for b_val in bouquets {
                if let Some(arr) = b_val.as_array() {
                    if arr.len() >= 2 {
                        let sref = arr[0].as_str().unwrap_or("").to_string();
                        let name = arr[1].as_str().unwrap_or("").to_string();
                        if !name.is_empty() {
                            list.push(Bouquet { name, s_ref: sref });
                        }
                    }
                }
            }
        }
        Ok(list)
    }

    /// Fetches channels in a bouquet
    pub fn fetch_channels_in_bouquet(b: &EnigmaBox, bouquet_ref: &str) -> Result<Vec<Channel>, String> {
        let path = format!("/api/getservices?sRef={}", urlencoding::encode(bouquet_ref));
        let resp = Self::build_get(b, &path).call().map_err(|e| e.to_string())?;
        let val: Value = resp.into_json().map_err(|e| e.to_string())?;

        let mut list = Vec::new();
        if let Some(services) = val.get("services").and_then(|v| v.as_array()) {
            for s in services {
                let sref = s.get("servicereference").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let name = s.get("servicename").and_then(|v| v.as_str()).unwrap_or("").to_string();
                if !name.is_empty() && !sref.is_empty() {
                    list.push(Channel {
                        name,
                        s_ref: sref,
                        now_title: None,
                        now_desc: None,
                        next_title: None,
                    });
                }
            }
        }
        Ok(list)
    }

    /// Fetches EPG events for a channel
    pub fn fetch_epg(b: &EnigmaBox, s_ref: &str) -> Result<Vec<EpgEvent>, String> {
        let path = format!("/api/epgservice?sRef={}", urlencoding::encode(s_ref));
        let resp = Self::build_get(b, &path).call().map_err(|e| e.to_string())?;
        let val: Value = resp.into_json().map_err(|e| e.to_string())?;

        let mut list = Vec::new();
        if let Some(events) = val.get("events").and_then(|v| v.as_array()) {
            for ev in events {
                let id = ev.get("id").and_then(|v| v.as_i64()).unwrap_or(0);
                let title = ev.get("title").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let desc = ev.get("description").or_else(|| ev.get("longdesc")).and_then(|v| v.as_str()).unwrap_or("").to_string();
                let begin = ev.get("begin_timestamp").and_then(|v| v.as_i64()).unwrap_or(0);
                let duration = ev.get("duration_sec").and_then(|v| v.as_i64()).unwrap_or(0);

                list.push(EpgEvent {
                    id,
                    title,
                    description: desc,
                    begin_timestamp: begin,
                    duration_sec: duration,
                });
            }
        }
        Ok(list)
    }

    /// Fetches all scheduled timers
    pub fn fetch_timers(b: &EnigmaBox) -> Result<Vec<TimerItem>, String> {
        let resp = Self::build_get(b, "/api/timerlist").call().map_err(|e| e.to_string())?;
        let val: Value = resp.into_json().map_err(|e| e.to_string())?;

        let mut list = Vec::new();
        if let Some(timers) = val.get("timers").and_then(|v| v.as_array()) {
            for t in timers {
                if let Ok(item) = serde_json::from_value::<TimerItem>(t.clone()) {
                    list.push(item);
                }
            }
        }
        Ok(list)
    }

    /// Deletes a timer
    pub fn delete_timer(b: &EnigmaBox, s_ref: &str, begin: i64, end: i64) -> Result<(), String> {
        let path = format!("/api/timerdelete?sRef={}&begin={}&end={}", urlencoding::encode(s_ref), begin, end);
        let _ = Self::build_get(b, &path).call().map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Adds a timer by event ID (User Rule: sRef NOT encoded, eventid required)
    pub fn add_timer_by_event_id(b: &EnigmaBox, s_ref: &str, event_id: i64) -> Result<(), String> {
        let path = format!("/api/timeraddbyeventid?sRef={}&eventid={}", s_ref, event_id);
        let _ = Self::build_get(b, &path).call().map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Fetches recorded movies / media
    pub fn fetch_movies(b: &EnigmaBox) -> Result<Vec<MovieItem>, String> {
        let resp = Self::build_get(b, "/api/movielist").call().map_err(|e| e.to_string())?;
        let val: Value = resp.into_json().map_err(|e| e.to_string())?;

        let mut list = Vec::new();
        if let Some(movies) = val.get("movies").and_then(|v| v.as_array()) {
            for m in movies {
                let name = m.get("eventname")
                    .or_else(|| m.get("title"))
                    .or_else(|| m.get("name"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                let s_ref = m.get("serviceref")
                    .or_else(|| m.get("servicereference"))
                    .or_else(|| m.get("sRef"))
                    .or_else(|| m.get("fullname"))
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string();

                let service_name = m.get("servicename").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let desc = m.get("description").or_else(|| m.get("descriptionExtended")).and_then(|v| v.as_str()).unwrap_or("").to_string();
                let filename = m.get("filename").or_else(|| m.get("filename_stripped")).and_then(|v| v.as_str()).unwrap_or("").to_string();
                let filesize = m.get("filesize").and_then(|v| v.as_i64()).unwrap_or(0);
                let filesize_readable = m.get("filesize_readable").and_then(|v| v.as_str()).unwrap_or("").to_string();
                let recording_time = m.get("recordingtime").and_then(|v| v.as_i64()).unwrap_or(0);
                let length = m.get("length").and_then(|v| v.as_str()).unwrap_or("").to_string();

                if !name.is_empty() || !s_ref.is_empty() {
                    list.push(MovieItem {
                        name,
                        service_name,
                        service_ref: s_ref,
                        description: desc,
                        filename,
                        filesize,
                        filesize_readable,
                        recording_time,
                        length,
                    });
                }
            }
        }

        // Sort descending by recording time (newest first)
        list.sort_by(|a, b| b.recording_time.cmp(&a.recording_time));
        Ok(list)
    }

    /// Fetches autotimer rules from /autotimer
    pub fn fetch_autotimers(b: &EnigmaBox) -> Result<Vec<AutoTimerRule>, String> {
        let resp = Self::build_get(b, "/autotimer").call().map_err(|e| e.to_string())?;
        let text = resp.into_string().map_err(|e| e.to_string())?;

        let mut list = Vec::new();
        for block in text.split("<timer ").skip(1) {
            let header = block.split('>').next().unwrap_or("");
            let body = block.split("</timer>").next().unwrap_or("");

            let extract_attr = |attr: &str| -> String {
                let token = format!("{}=\"", attr);
                if let Some(idx) = header.find(&token) {
                    let rest = &header[idx + token.len()..];
                    if let Some(end) = rest.find('"') {
                        return rest[..end].to_string();
                    }
                }
                String::new()
            };

            let id = extract_attr("id");
            let mut name = extract_attr("name");
            let match_pattern = extract_attr("match");
            let enabled_str = extract_attr("enabled");
            let enabled = enabled_str == "yes" || enabled_str == "1" || enabled_str == "true";

            if name.is_empty() {
                name = match_pattern.clone();
            }

            let extract_tag = |tag: &str| -> String {
                let open = format!("<{}>", tag);
                let close = format!("</{}>", tag);
                if let Some(s) = body.find(&open) {
                    let rest = &body[s + open.len()..];
                    if let Some(e) = rest.find(&close) {
                        return rest[..e].to_string();
                    }
                }
                String::new()
            };

            let service_name = extract_tag("e2servicename");
            let service_ref = extract_tag("e2servicereference");

            if !id.is_empty() || !name.is_empty() {
                list.push(AutoTimerRule {
                    id,
                    name,
                    match_pattern,
                    enabled,
                    service_name,
                    service_ref,
                });
            }
        }

        Ok(list)
    }

    /// Deletes an autotimer rule
    pub fn delete_autotimer(b: &EnigmaBox, id: &str) -> Result<(), String> {
        let path = format!("/autotimer/remove?id={}", urlencoding::encode(id));
        let _ = Self::build_get(b, &path).call().map_err(|e| e.to_string())?;
        let _ = Self::build_get(b, "/api/autotimer/reload").call();
        Ok(())
    }

    /// Adds a new autotimer rule
    pub fn add_autotimer(b: &EnigmaBox, name: &str, match_str: &str, sref: Option<&str>) -> Result<(), String> {
        let mut path = format!("/autotimer/add?name={}&match={}&enabled=1", urlencoding::encode(name), urlencoding::encode(match_str));
        if let Some(s) = sref {
            path.push_str(&format!("&services={}", urlencoding::encode(s)));
        }
        let _ = Self::build_get(b, &path).call().map_err(|e| e.to_string())?;
        let _ = Self::build_get(b, "/api/autotimer/reload").call();
        Ok(())
    }

    /// Deletes a recorded movie
    pub fn delete_movie(b: &EnigmaBox, s_ref: &str) -> Result<(), String> {
        let path = format!("/api/moviedelete?sRef={}", urlencoding::encode(s_ref));
        let _ = Self::build_get(b, &path).call().map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Captures screenshot PNG
    pub fn take_screenshot(b: &EnigmaBox) -> Result<Vec<u8>, String> {
        let mut buf = Vec::new();
        let resp = Self::build_get(b, "/grab?format=png&mode=all")
            .call()
            .map_err(|e| e.to_string())?;

        use std::io::Read;
        resp.into_reader().read_to_end(&mut buf).map_err(|e| e.to_string())?;
        Ok(buf)
    }

    /// Sends an on-screen message
    pub fn send_message(b: &EnigmaBox, text: &str, msg_type: u8, timeout_sec: u32) -> Result<(), String> {
        let path = format!("/api/message?text={}&type={}&timeout={}", urlencoding::encode(text), msg_type, timeout_sec);
        let _ = Self::build_get(b, &path).call().map_err(|e| e.to_string())?;
        Ok(())
    }
}
