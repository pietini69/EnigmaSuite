import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Asennuspaketin tiedot
struct ExtractedPackageInfo: Identifiable, Hashable {
    var id: String { fileURL.path }
    let fileURL: URL
    let settingsContent: String
    let hostname: String?
    let imageVersion: String?
    let boxModel: String?
    let settings: [String: String]
    let tuners: [TunerInfo]
    
    var friendlyBoxName: String {
        let model = boxModel ?? hostname ?? fileURL.deletingLastPathComponent().lastPathComponent
        return "📦 rootfs.tar.bz2 (\(model))"
    }
}

// MARK: - Rootfs & Asennuspakettien purkupalvelu
final class RootfsPackageService {
    static let shared = RootfsPackageService()
    
    private var cache: [String: ExtractedPackageInfo] = [:]
    
    // MARK: - Asetusten purku tiedostosta tai arkistosta
    func extractSettings(from inputURL: URL) async -> (info: ExtractedPackageInfo?, error: String?) {
        let url: URL
        if !inputURL.isFileURL, inputURL.scheme == "enigmasuite",
           let comps = URLComponents(url: inputURL, resolvingAgainstBaseURL: false),
           let p = comps.queryItems?.first(where: { $0.name == "path" })?.value {
            url = URL(fileURLWithPath: p)
        } else {
            url = inputURL
        }
        let path = url.path
        if let cached = cache[path] {
            return (cached, nil)
        }
        
        let task = Task.detached(priority: .userInitiated) { [weak self] () -> (info: ExtractedPackageInfo?, error: String?) in
            guard let self = self else { return (nil, "Palveluvirhe") }
            
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
                return (nil, "Tiedostoa ei löytynyt polusta: \(path)")
            }
            
            var targetTarURL: URL?
            var directSettingsContent: String?
            var tempFolderToClean: URL?
            
            defer {
                if let temp = tempFolderToClean {
                    try? fm.removeItem(at: temp)
                }
            }
            
            if isDir.boolValue {
                // 1. Kansio: Tarkista suora etc/enigma2/settings
                let localSettings = url.appendingPathComponent("etc/enigma2/settings")
                if fm.fileExists(atPath: localSettings.path),
                   let s = try? String(contentsOf: localSettings, encoding: .utf8),
                   s.contains("config.") {
                    directSettingsContent = s
                } else {
                    // Etsi rootfs.tar.bz2 kansion sisältä
                    if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                        for case let file as URL in enumerator {
                            let name = file.lastPathComponent.lowercased()
                            if name.contains("rootfs") && (name.hasSuffix(".tar.bz2") || name.hasSuffix(".tar.gz") || name.hasSuffix(".tar")) {
                                targetTarURL = file
                                break
                            }
                        }
                    }
                }
            } else if url.pathExtension.lowercased() == "zip" {
                // 2. Zip-paketti: tarkistetaan suora settings-tiedosto tai puretaan sisäinen rootfs.tar.* väliaikaishakemistoon
                let tempDir = fm.temporaryDirectory.appendingPathComponent("enigma_pkg_\(UUID().uuidString)")
                try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
                tempFolderToClean = tempDir
                
                // Tarkistetaan zipin sisältö
                let listProc = Process()
                listProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                listProc.arguments = ["-l", path]
                let listPipe = Pipe()
                listProc.standardOutput = listPipe
                listProc.standardError = Pipe()
                
                var directSettingsEntry: String?
                var rootfsEntryName: String?
                
                if (try? listProc.run()) != nil {
                    let listData = listPipe.fileHandleForReading.readDataToEndOfFile()
                    listProc.waitUntilExit()
                    if let listStr = String(data: listData, encoding: .utf8) {
                        for line in listStr.components(separatedBy: .newlines) {
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                            if let entryPath = parts.last {
                                let lower = entryPath.lowercased()
                                if lower.hasSuffix("etc/enigma2/settings") || lower == "settings" {
                                    directSettingsEntry = entryPath
                                    break
                                } else if rootfsEntryName == nil && lower.contains("rootfs") && (lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tar") || lower.hasSuffix(".tar.xz")) {
                                    rootfsEntryName = entryPath
                                }
                            }
                        }
                    }
                }
                
                if let directEntry = directSettingsEntry {
                    // Puretaan settings-tiedosto suoraan zipistä
                    let unzipProc = Process()
                    unzipProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    unzipProc.arguments = ["-p", path, directEntry]
                    let pipe = Pipe()
                    unzipProc.standardOutput = pipe
                    unzipProc.standardError = Pipe()
                    
                    if (try? unzipProc.run()) != nil {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        unzipProc.waitUntilExit()
                        if unzipProc.terminationStatus == 0,
                           let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                           content.contains("config.") {
                            directSettingsContent = content
                        }
                    }
                }
                
                if directSettingsContent == nil {
                    if let entry = rootfsEntryName {
                        let ext = (entry as NSString).pathExtension.lowercased()
                        let tarName = ext.isEmpty ? "rootfs.tar.bz2" : "rootfs.\(ext)"
                        let tempTar = tempDir.appendingPathComponent(tarName)
                        let unzipProc = Process()
                        unzipProc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                        unzipProc.arguments = ["-p", path, entry]
                        let pipe = Pipe()
                        unzipProc.standardOutput = pipe
                        unzipProc.standardError = Pipe()
                        
                        do {
                            try unzipProc.run()
                            let data = pipe.fileHandleForReading.readDataToEndOfFile()
                            unzipProc.waitUntilExit()
                            if unzipProc.terminationStatus == 0 && !data.isEmpty {
                                try data.write(to: tempTar)
                                targetTarURL = tempTar
                            }
                        } catch {
                            return (nil, "Zip-tiedoston purku epäonnistui: \(error.localizedDescription)")
                        }
                    } else {
                        return (nil, "Zip-paketista ei löytynyt 'settings' tai 'rootfs' -tiedostoa.")
                    }
                }
            } else if url.lastPathComponent.lowercased().contains("rootfs") || ["bz2", "gz", "tar", "xz"].contains(url.pathExtension.lowercased()) {
                // 3. Suora tar-arkisto (kuten rootfs.tar.bz2)
                targetTarURL = url
            } else {
                // 4. Mahdollisesti tavallinen settings-tekstitiedosto
                if let content = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)),
                   content.contains("config.") {
                    directSettingsContent = content
                }
            }
            
            // Jos meillä on suora settings-sisältö
            if let content = directSettingsContent {
                let parsed = SettingsParser.shared.parse(content: content)
                let tuners = SettingsParser.shared.deduceTuners(from: parsed)
                let info = ExtractedPackageInfo(
                    fileURL: url,
                    settingsContent: content,
                    hostname: nil,
                    imageVersion: nil,
                    boxModel: nil,
                    settings: parsed,
                    tuners: tuners
                )
                self.cache[path] = info
                return (info, nil)
            }
            
            // Puretaan tar-arkistosta
            guard let tarURL = targetTarURL else {
                return (nil, "Valittu tiedosto ei ole tunnistettava Enigma2-asennuspaketti tai asetustiedosto.")
            }
            
            // Suoritetaan tar-purku settings-tiedostolle
            let settingsProc = Process()
            settingsProc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            settingsProc.arguments = ["--include", "*etc/enigma2/settings", "-xf", tarURL.path, "-O"]
            let settingsPipe = Pipe()
            settingsProc.standardOutput = settingsPipe
            settingsProc.standardError = Pipe()
            
            do {
                try settingsProc.run()
            } catch {
                return (nil, "tar-komennon suoritus epäonnistui: \(error.localizedDescription)")
            }
            
            let settingsData = settingsPipe.fileHandleForReading.readDataToEndOfFile()
            settingsProc.waitUntilExit()
            
            var settingsStr = String(data: settingsData, encoding: .utf8) ?? String(data: settingsData, encoding: .isoLatin1) ?? ""
            
            // Jos etc/enigma2/settings ei löytynyt suoraan (esim. puhdas tehdasasennusimage)
            if !settingsStr.contains("config.") {
                let defProc = Process()
                defProc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                defProc.arguments = ["--include", "*usr/share/enigma2/defaults/*settings*", "-xf", tarURL.path, "-O"]
                let defPipe = Pipe()
                defProc.standardOutput = defPipe
                defProc.standardError = Pipe()
                if (try? defProc.run()) != nil {
                    let defData = defPipe.fileHandleForReading.readDataToEndOfFile()
                    defProc.waitUntilExit()
                    let defStr = String(data: defData, encoding: .utf8) ?? ""
                    if defStr.contains("config.") {
                        settingsStr = defStr
                    }
                }
            }
            
            guard settingsStr.contains("config.") else {
                return (nil, "Tiedostosta rootfs.tar.bz2 ei löytynyt asetustiedostoa (etc/enigma2/settings).\n\nHuomaa: Tyhjissä tehdasimageissa asetukset luodaan vasta ensimmäisellä käyttökerralla ohjatussa asennuksessa (First Run Wizard). Varmuuskopio-imageissa (Image Backup) asetukset ovat valmiina mukana.")
            }
            
            // Haetaan hostname boksin mallin tunnistamiseksi
            var hostname: String?
            let hostProc = Process()
            hostProc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            hostProc.arguments = ["--include", "*etc/hostname", "-xf", tarURL.path, "-O"]
            let hostPipe = Pipe()
            hostProc.standardOutput = hostPipe
            hostProc.standardError = Pipe()
            if (try? hostProc.run()) != nil {
                let hostData = hostPipe.fileHandleForReading.readDataToEndOfFile()
                hostProc.waitUntilExit()
                if let str = String(data: hostData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                    hostname = str
                }
            }
            
            // Haetaan image-version
            var imageVersion: String?
            let verProc = Process()
            verProc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            verProc.arguments = ["--include", "*etc/image-version", "-xf", tarURL.path, "-O"]
            let verPipe = Pipe()
            verProc.standardOutput = verPipe
            verProc.standardError = Pipe()
            if (try? verProc.run()) != nil {
                let verData = verPipe.fileHandleForReading.readDataToEndOfFile()
                verProc.waitUntilExit()
                if let str = String(data: verData, encoding: .utf8), !str.isEmpty {
                    var distroParts: [String] = []
                    for line in str.components(separatedBy: .newlines) {
                        if line.hasPrefix("creator=") {
                            let c = line.replacingOccurrences(of: "creator=", with: "")
                                .components(separatedBy: "<").first?.trimmingCharacters(in: .whitespaces) ?? ""
                            if !c.isEmpty { distroParts.append(c) }
                        } else if line.hasPrefix("version=") {
                            let v = line.replacingOccurrences(of: "version=", with: "").trimmingCharacters(in: .whitespaces)
                            if !v.isEmpty { distroParts.append(v) }
                        }
                    }
                    if !distroParts.isEmpty {
                        imageVersion = distroParts.joined(separator: " ")
                    }
                }
            }
            
            // Päätellään boksin malli
            let boxModel = self.friendlyModelName(from: hostname ?? tarURL.path)
            
            // Parsitaan asetukset ja virittimet
            let parsed = SettingsParser.shared.parse(content: settingsStr)
            let tuners = SettingsParser.shared.deduceTuners(from: parsed)
            
            let info = ExtractedPackageInfo(
                fileURL: url,
                settingsContent: settingsStr,
                hostname: hostname,
                imageVersion: imageVersion,
                boxModel: boxModel,
                settings: parsed,
                tuners: tuners
            )
            
            self.cache[path] = info
            return (info, nil)
        }
        
        let result = await task.value
        return result
    }
    
    // MARK: - Luodaan EnigmaBox-ilmentymä asennuspaketista
    func createBox(from info: ExtractedPackageInfo) -> EnigmaBox {
        let modelName = info.boxModel ?? friendlyModelName(from: info.hostname ?? info.fileURL.path)
        let distroName = info.imageVersion ?? "rootfs.tar.bz2"
        let displayName = "📦 rootfs.tar.bz2 (\(modelName))"
        
        return EnigmaBox(
            id: UUID(),
            name: displayName,
            ip: "package://\(info.fileURL.path)",
            port: 0,
            isOnline: true,
            model: modelName,
            distro: distroName,
            tuners: info.tuners
        )
    }
    
    // MARK: - Mallinimen siistiminen
    func friendlyModelName(from text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("duo4kse") || lower.contains("duo 4k se") {
            return "Vu+ Duo 4K SE"
        } else if lower.contains("duo4klite") || lower.contains("duo 4k lite") {
            return "Vu+ Duo 4K Lite"
        } else if lower.contains("duo4k") || lower.contains("duo 4k") {
            return "Vu+ Duo 4K"
        } else if lower.contains("uno4kse") || lower.contains("uno 4k se") {
            return "Vu+ Uno 4K SE"
        } else if lower.contains("ultimo4k") || lower.contains("ultimo 4k") {
            return "Vu+ Ultimo 4K"
        } else if lower.contains("zero4k") || lower.contains("zero 4k") {
            return "Vu+ Zero 4K"
        } else if lower.contains("solo4k") || lower.contains("solo 4k") {
            return "Vu+ Solo 4K"
        } else if lower.contains("sf4008") {
            return "Octagon SF4008"
        } else if lower.contains("hd51") {
            return "Mutant HD51"
        }
        return text
    }
}
