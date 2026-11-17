use std::path::{Path, PathBuf};
use std::process::Command;
use std::fs;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BootlogoType {
    Bootlogo,      // bootlogo.mvi
    BootlogoWait,  // bootlogo_wait.mvi
    Backdrop,      // backdrop.mvi
    Reboot,        // reboot.mvi
    Shutdown,      // shutdown.mvi
}

impl BootlogoType {
    pub fn all() -> &'static [BootlogoType] {
        &[
            BootlogoType::Bootlogo,
            BootlogoType::BootlogoWait,
            BootlogoType::Backdrop,
            BootlogoType::Reboot,
            BootlogoType::Shutdown,
        ]
    }

    pub fn filename(&self) -> &'static str {
        match self {
            BootlogoType::Bootlogo => "bootlogo.mvi",
            BootlogoType::BootlogoWait => "bootlogo_wait.mvi",
            BootlogoType::Backdrop => "backdrop.mvi",
            BootlogoType::Reboot => "reboot.mvi",
            BootlogoType::Shutdown => "shutdown.mvi",
        }
    }

    pub fn display_name(&self) -> &'static str {
        match self {
            BootlogoType::Bootlogo => "bootlogo.mvi (Pääkäynnistyskuva)",
            BootlogoType::BootlogoWait => "bootlogo_wait.mvi (Odotus-/Latauskuva)",
            BootlogoType::Backdrop => "backdrop.mvi (Taustakuva)",
            BootlogoType::Reboot => "reboot.mvi (Uudelleenkäynnistyskuva)",
            BootlogoType::Shutdown => "shutdown.mvi (Sammutuskuva)",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ScalingMode {
    FitPad,  // Keep aspect ratio, pad with black
    Crop,    // Keep aspect ratio, crop excess
    Stretch, // Stretch to exact resolution
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BootlogoResolution {
    Fhd1080p, // 1920x1080
    Uhd4k,    // 3840x2160
    Hd720p,   // 1280x720
}

impl BootlogoResolution {
    pub fn dimensions(&self) -> (u32, u32) {
        match self {
            BootlogoResolution::Fhd1080p => (1920, 1080),
            BootlogoResolution::Uhd4k => (3840, 2160),
            BootlogoResolution::Hd720p => (1280, 720),
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            BootlogoResolution::Fhd1080p => "1080p Full HD (1920x1080)",
            BootlogoResolution::Uhd4k => "4K UHD (3840x2160)",
            BootlogoResolution::Hd720p => "720p HD (1280x720)",
        }
    }
}

pub struct BootlogoService;

impl BootlogoService {
    /// Discovers ffmpeg executable path across macOS and Windows
    pub fn find_ffmpeg() -> Option<PathBuf> {
        let candidates = [
            "ffmpeg",
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg",
            "ffmpeg.exe",
            "Resources/ffmpeg.exe",
            "C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe",
        ];

        for c in &candidates {
            if let Ok(out) = Command::new(c).arg("-version").output() {
                if out.status.success() {
                    return Some(PathBuf::from(c));
                }
            }
        }

        // Check relative to current exe
        if let Ok(current_exe) = std::env::current_exe() {
            if let Some(parent) = current_exe.parent() {
                let win_ffmpeg = parent.join("ffmpeg.exe");
                if win_ffmpeg.exists() {
                    return Some(win_ffmpeg);
                }
            }
        }

        None
    }

    /// Converts standard image (PNG, JPG, BMP) to Enigma2 MVI MPEG-2 format
    pub fn convert_image_to_mvi(
        source_image: &Path,
        output_mvi: &Path,
        res: BootlogoResolution,
        mode: ScalingMode,
    ) -> Result<(), String> {
        let ffmpeg = Self::find_ffmpeg().ok_or_else(|| "FFmpeg-työkalua ei löydy järjestelmästä.".to_string())?;
        let (w, h) = res.dimensions();

        let vf = match mode {
            ScalingMode::FitPad => format!("scale={}:{}:force_original_aspect_ratio=decrease,pad={}:{}:(ow-iw)/2:(oh-ih)/2:black", w, h, w, h),
            ScalingMode::Crop => format!("scale={}:{}:force_original_aspect_ratio=increase,crop={}:{}", w, h, w, h),
            ScalingMode::Stretch => format!("scale={}:{}", w, h),
        };

        let status = Command::new(ffmpeg)
            .args([
                "-y",
                "-loop", "1",
                "-i", &source_image.to_string_lossy(),
                "-vf", &vf,
                "-c:v", "mpeg2video",
                "-b:v", "15000k",
                "-minrate", "15000k",
                "-maxrate", "15000k",
                "-bufsize", "1000k",
                "-q:v", "1",
                "-g", "1",
                "-vframes", "1",
                "-f", "mpeg2video",
                &output_mvi.to_string_lossy(),
            ])
            .status()
            .map_err(|e| format!("FFmpeg-suoritusvirhe: {}", e))?;

        if status.success() && output_mvi.exists() {
            Ok(())
        } else {
            Err("MVI-muunnos epäonnistui FFmpegillä.".to_string())
        }
    }

    /// Extracts first frame of an MVI file to a standard PNG/JPG for preview
    pub fn convert_mvi_to_image(mvi_path: &Path, output_image: &Path) -> Result<(), String> {
        let ffmpeg = Self::find_ffmpeg().ok_or_else(|| "FFmpeg-työkalua ei löydy järjestelmästä.".to_string())?;

        let status = Command::new(ffmpeg)
            .args([
                "-y",
                "-f", "mpegvideo",
                "-i", &mvi_path.to_string_lossy(),
                "-vframes", "1",
                "-update", "1",
                "-f", "image2",
                &output_image.to_string_lossy(),
            ])
            .status()
            .map_err(|e| format!("FFmpeg-suoritusvirhe: {}", e))?;

        if status.success() && output_image.exists() {
            Ok(())
        } else {
            Err("MVI-esikatselukuvan muodostus epäonnistui.".to_string())
        }
    }

    /// Downloads a bootlogo directly from Enigma2 box via FTP
    pub fn download_bootlogo_ftp(ip: &str, user: &str, pass: &str, remote_path: &str, local_file: &Path) -> Result<(), String> {
        let user_pass = format!("{}:{}", user, pass);
        let ftp_url = format!("ftp://{}/{}", ip, remote_path.trim_start_matches('/'));

        let out = Command::new("curl")
            .args([
                "-s",
                "-m", "8",
                "--user", &user_pass,
                &ftp_url,
                "-o", &local_file.to_string_lossy(),
            ])
            .output()
            .map_err(|e| format!("Curl-virhe: {}", e))?;

        if out.status.success() && local_file.exists() && fs::metadata(local_file).map(|m| m.len() > 0).unwrap_or(false) {
            Ok(())
        } else {
            Err(format!("Lataus epäonnistui osoitteesta {}", ftp_url))
        }
    }

    /// Uploads an MVI bootlogo to Enigma2 box via FTP
    pub fn upload_bootlogo_ftp(ip: &str, user: &str, pass: &str, local_file: &Path, remote_path: &str) -> Result<(), String> {
        let user_pass = format!("{}:{}", user, pass);
        let ftp_url = format!("ftp://{}/{}", ip, remote_path.trim_start_matches('/'));

        let out = Command::new("curl")
            .args([
                "-s",
                "-m", "10",
                "--user", &user_pass,
                "-T", &local_file.to_string_lossy(),
                &ftp_url,
            ])
            .output()
            .map_err(|e| format!("Curl-virhe: {}", e))?;

        if out.status.success() {
            Ok(())
        } else {
            Err(format!("Lähetys epäonnistui osoitteeseen {}", ftp_url))
        }
    }
}
