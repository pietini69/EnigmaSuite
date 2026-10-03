import Foundation
import AppKit

final class FFmpegService {
    static let shared = FFmpegService()
    
    private(set) var ffmpegPath: String?
    private(set) var lastErrorMessage: String?
    
    init() {
        findFFmpegPath()
    }
    
    func findFFmpegPath() {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                ffmpegPath = path
                return
            }
        }
        
        // Kokeillaan löytää 'which ffmpeg' kautta
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ffmpeg"]
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty,
               FileManager.default.isExecutableFile(atPath: output) {
                ffmpegPath = output
            }
        } catch {
            ffmpegPath = nil
        }
    }
    
    var isAvailable: Bool {
        return ffmpegPath != nil
    }
    
    // MARK: - MVI -> JPG Esikatseluun
    /// Muuntaa Enigma2 .mvi (MPEG-2 I-frame stream) tiedoston kuvaksi (JPG/NSImage).
    func convertMviToImage(mviData: Data) async -> NSImage? {
        if ffmpegPath == nil { findFFmpegPath() }
        guard let ffmpeg = ffmpegPath else {
            lastErrorMessage = "FFmpeg-binääriä ei löydy"
            return nil
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempMvi = tempDir.appendingPathComponent("mvi_preview_\(UUID().uuidString).mvi")
        let tempJpg = tempDir.appendingPathComponent("mvi_preview_\(UUID().uuidString).jpg")
        
        defer {
            try? FileManager.default.removeItem(at: tempMvi)
            try? FileManager.default.removeItem(at: tempJpg)
        }
        
        do {
            try mviData.write(to: tempMvi)
        } catch {
            lastErrorMessage = "Väliaikaistiedoston kirjoitus epäonnistui: \(error.localizedDescription)"
            return nil
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-y",
            "-f", "mpegvideo",
            "-i", tempMvi.path,
            "-vframes", "1",
            "-f", "image2",
            "-update", "1",
            tempJpg.path
        ]
        
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0,
               let imgData = try? Data(contentsOf: tempJpg) {
                lastErrorMessage = nil
                return NSImage(data: imgData)
            } else {
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                lastErrorMessage = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
        
        return nil
    }
    
    // MARK: - Kuva -> MVI (Boksille)
    /// Muuntaa valitun kuvatiedoston (JPG/PNG/HEIC/jne.) Enigma2-yhteensopivaksi .mvi tiedostoksi.
    func convertImageToMvi(
        sourceURL: URL,
        resolution: ResolutionOption = .fhd1080,
        scaling: ScalingMode = .pad
    ) async -> Data? {
        if ffmpegPath == nil { findFFmpegPath() }
        guard let ffmpeg = ffmpegPath else {
            lastErrorMessage = "FFmpeg-binääriä ei löydy"
            return nil
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let tempMvi = tempDir.appendingPathComponent("mvi_out_\(UUID().uuidString).mvi")
        
        defer {
            try? FileManager.default.removeItem(at: tempMvi)
        }
        
        let filter = scaling.ffmpegFilter(width: resolution.width, height: resolution.height)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-y",
            "-loop", "1",
            "-i", sourceURL.path,
            "-vf", filter,
            "-c:v", "mpeg2video",
            "-pix_fmt", "yuv420p",
            "-b:v", "15000k",
            "-minrate", "15000k",
            "-maxrate", "15000k",
            "-bufsize", "1000k",
            "-q:v", "1",
            "-g", "1",
            "-vframes", "1",
            "-f", "mpeg2video",
            tempMvi.path
        ]
        
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0,
               let data = try? Data(contentsOf: tempMvi) {
                lastErrorMessage = nil
                return data
            } else {
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                lastErrorMessage = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
        
        return nil
    }
}
