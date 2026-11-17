use std::fs;
use std::process::Command;

pub struct MediaPlayer;

impl MediaPlayer {
    pub fn play_stream(stream_url: &str, title: &str) {
        // 1. Try launching VLC directly on macOS
        #[cfg(target_os = "macos")]
        {
            let user_app = dirs::home_dir().map(|h| h.join("Applications/VLC.app"));
            let vlc_installed = std::path::Path::new("/Applications/VLC.app").exists()
                || user_app.map(|p| p.exists()).unwrap_or(false);

            if vlc_installed {
                if Command::new("open")
                    .arg("-a")
                    .arg("VLC")
                    .arg(stream_url)
                    .spawn()
                    .is_ok()
                {
                    return;
                }
            }
        }

        // 2. Try launching VLC directly on Windows
        #[cfg(target_os = "windows")]
        {
            let candidates = [
                r"C:\Program Files\VideoLAN\VLC\vlc.exe",
                r"C:\Program Files (x86)\VideoLAN\VLC\vlc.exe",
            ];
            for path in candidates {
                if std::path::Path::new(path).exists() {
                    if Command::new(path).arg(stream_url).spawn().is_ok() {
                        return;
                    }
                }
            }
            if Command::new("vlc").arg(stream_url).spawn().is_ok() {
                return;
            }
        }

        // 3. Try launching vlc directly on Linux
        #[cfg(target_os = "linux")]
        {
            if Command::new("vlc").arg(stream_url).spawn().is_ok() {
                return;
            }
        }

        // 4. Universal Fallback: generate a temporary .m3u playlist file and open it.
        // Operating systems associate .m3u with media players (VLC, mpv, Windows Media Player)
        // instead of opening the web browser to download the file!
        let temp_dir = std::env::temp_dir();
        let m3u_path = temp_dir.join("enigmasuite_stream.m3u");
        let content = format!("#EXTM3U\n#EXTINF:-1,{}\n{}\n", title, stream_url);
        if fs::write(&m3u_path, content).is_ok() {
            let _ = open::that(&m3u_path);
        }
    }
}
