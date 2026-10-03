import Foundation
import Network
import AppKit

final class EnigmaBoxService {
    static let shared = EnigmaBoxService()
    
    // MARK: - Apurit URL:lle ja todennukselle
    func formatURL(ip: String, port: Int = 80, path: String) -> URL? {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let urlString: String
        if port == 80 {
            urlString = "http://\(ip)/\(cleanPath)"
        } else {
            urlString = "http://\(ip):\(port)/\(cleanPath)"
        }
        return URL(string: urlString)
    }
    
    func resolveCredentials(for ip: String?, username: inout String?, password: inout String?) async {
        guard let ip = ip, !ip.isEmpty else { return }
        if (username == nil || username?.isEmpty == true) && (password == nil || password?.isEmpty == true) {
            let foundBox = await MainActor.run {
                EnigmaSuiteState.shared?.boxes.first(where: { $0.ip.caseInsensitiveCompare(ip) == .orderedSame })
            }
            if let box = foundBox, box.hasAuth {
                username = box.username
                password = box.password
            }
        }
    }
    
    func ftpCredentials(ip: String, username: String? = nil, password: String? = nil) async -> String {
        var u = username
        var p = password
        await resolveCredentials(for: ip, username: &u, password: &p)
        let resolvedUser = (u?.isEmpty == false) ? u! : "root"
        let resolvedPass = p ?? ""
        if !resolvedPass.isEmpty {
            let safeUser = resolvedUser.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? resolvedUser
            let safePass = resolvedPass.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? resolvedPass
            return "\(safeUser):\(safePass)"
        }
        return "\(resolvedUser):"
    }

    // MARK: - Universaali verkkopyyntö (URLSession + /usr/bin/curl fallback)
    func performRequest(
        url: URL,
        timeout: Double = 3.0,
        postData: Data? = nil,
        username: String? = nil,
        password: String? = nil
    ) async -> (data: Data?, statusCode: Int) {
        var user = username
        var pass = password
        if user == nil && pass == nil, let host = url.host {
            await resolveCredentials(for: host, username: &user, password: &pass)
        }
        
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        if let postData = postData {
            req.httpMethod = "POST"
            req.httpBody = postData
        }
        
        let u = user ?? ""
        let p = pass ?? ""
        if !u.isEmpty || !p.isEmpty {
            let authStr = "\(u):\(p)"
            if let authData = authStr.data(using: .utf8) {
                req.setValue("Basic \(authData.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        }
        
        // 1. Kokeillaan ensin URLSessionia
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                return (data, http.statusCode)
            }
        } catch {}
        
        // 2. Varatie: /usr/bin/curl ohittaa macOS Local Network Privacy -rajoitukset
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var args = [
            "-s",
            "--connect-timeout", "\(timeout)",
            "--max-time", "\(timeout + 2.0)",
            "-w", "%{stderr}%{http_code}"
        ]
        if !u.isEmpty || !p.isEmpty {
            args.append(contentsOf: ["-u", "\(u):\(p)"])
        }
        if let postData = postData, let str = String(data: postData, encoding: .utf8) {
            args.append(contentsOf: ["-X", "POST", "-d", str])
        }
        args.append(url.absoluteString)
        proc.arguments = args
        
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
            let bodyData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                let statusStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let code = Int(statusStr) ?? 200
                return (bodyData, code)
            }
        } catch {}
        
        return (nil, 0)
    }

    // MARK: - Boksin tilan ja laitetietojen haku
    func queryBoxInfo(
        ip: String,
        port: Int = 80,
        username: String? = nil,
        password: String? = nil
    ) async -> (
        isOnline: Bool,
        model: String?,
        distro: String?,
        tuners: [TunerInfo],
        diskFree: String?,
        uptime: String?
    ) {
        guard let url = formatURL(ip: ip, port: port, path: "api/about") else {
            return (false, nil, nil, [], nil, nil)
        }
        
        let (dataOpt, status) = await performRequest(url: url, timeout: 2.5, username: username, password: password)
        if status == 200, let data = dataOpt,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let info = json["info"] as? [String: Any] {
            
            let model = info["model"] as? String ?? info["boxtype"] as? String
            let distro = info["friendlyimagedistro"] as? String ?? info["imagedistro"] as? String ?? "VTi"
            let ver = info["imagever"] as? String ?? ""
            let fullDistro = ver.isEmpty ? distro : "\(distro) \(ver)"
            let uptime = info["uptime"] as? String
            
            var diskFree: String? = nil
            if let hdd = info["hdd"] as? [[String: Any]], let firstHdd = hdd.first {
                let free = firstHdd["free"] as? String ?? ""
                let cap = firstHdd["capacity"] as? String ?? ""
                if !free.isEmpty {
                    diskFree = "\(free) vapaana (yht. \(cap))"
                }
            }
            
            var parsedTuners: [TunerInfo] = []
            if let rawTuners = info["tuners"] as? [[String: Any]] {
                for (idx, tDict) in rawTuners.enumerated() {
                    let name = tDict["name"] as? String ?? "Viritin \(idx)"
                    let type = tDict["type"] as? String ?? ""
                    let upper = type.uppercased()
                    let family: TunerFamily = upper.contains("DVB-C") ? .cable :
                                             upper.contains("DVB-S") ? .satellite :
                                             upper.contains("DVB-T") ? .terrestrial : .unknown
                    parsedTuners.append(TunerInfo(index: idx, name: name, type: type, family: family))
                }
            }
            
            return (true, model, fullDistro, parsedTuners, diskFree, uptime)
        }
        
        // Kokeillaan FTP-porttia varayhteytenä
        let cred = await ftpCredentials(ip: ip, username: username, password: password)
        let ftpProcess = Process()
        ftpProcess.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        ftpProcess.arguments = ["-s", "--connect-timeout", "2", "--max-time", "3", "-I", "ftp://\(cred)@\(ip)/etc/enigma2/"]
        do {
            try ftpProcess.run()
            ftpProcess.waitUntilExit()
            if ftpProcess.terminationStatus == 0 {
                return (true, "Enigma2", "VTi", [], nil, nil)
            }
        } catch {}
        
        return (false, nil, nil, [], nil, nil)
    }
    
    // MARK: - Automaattinen verkkohaku (Subnet Discovery)
    private func logDiscovery(_ message: String) {
        print("[Discovery] \(message)")
        let line = "\(Date()): \(message)\n"
        if let data = line.data(using: .utf8) {
            let logFile = URL(fileURLWithPath: "/tmp/enigma_discovery.log")
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? line.write(toFile: "/tmp/enigma_discovery.log", atomically: true, encoding: .utf8)
            }
        }
    }
    
    func getActiveNetworkIPs() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        p.arguments = ["-an"]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        
        var ips: [String] = []
        for line in text.components(separatedBy: "\n") {
            guard !line.contains("incomplete") && line.contains("(") else { continue }
            let parts = line.components(separatedBy: "(")
            if parts.count >= 2, let ip = parts[1].components(separatedBy: ")").first {
                let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.starts(with: "192.168.") || trimmed.starts(with: "10.") {
                    ips.append(trimmed)
                }
            }
        }
        return Array(Set(ips)).sorted()
    }
    
    func getLocalSubnetPrefixes() -> [String] {
        var prefixes = Set<String>()
        
        // 1. Host.current().addresses
        for addr in Host.current().addresses {
            if !addr.contains(":") && addr != "127.0.0.1" {
                let parts = addr.components(separatedBy: ".")
                if parts.count == 4 {
                    prefixes.insert("\(parts[0]).\(parts[1]).\(parts[2]).")
                }
            }
        }
        
        // 2. getifaddrs
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr {
            defer { freeifaddrs(ifaddr) }
            var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
            while let p = ptr {
                let flags = Int32(p.pointee.ifa_flags)
                let isLoopback = (flags & IFF_LOOPBACK) != 0
                let isUp = (flags & IFF_UP) != 0
                if isUp && !isLoopback, let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: host)
                        let parts = ip.components(separatedBy: ".")
                        if parts.count == 4 && ip != "127.0.0.1" {
                            prefixes.insert("\(parts[0]).\(parts[1]).\(parts[2]).")
                        }
                    }
                }
                ptr = p.pointee.ifa_next
            }
        }
        
        if prefixes.isEmpty {
            return ["192.168.68.", "192.168.1.", "192.168.0."]
        }
        return Array(prefixes)
    }
    
    func discoverNetworkBoxes() async -> [EnigmaBox] {
        let prefixes = getLocalSubnetPrefixes()
        logDiscovery("Starting discovery on prefixes: \(prefixes)")
        
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.0
        config.timeoutIntervalForResource = 1.0
        let session = URLSession(configuration: config)
        
        var candidateIPs: [String] = []
        for prefix in prefixes {
            for i in 1...254 {
                candidateIPs.append("\(prefix)\(i)")
            }
        }
        
        var discovered: [EnigmaBox] = []
        
        await withTaskGroup(of: EnigmaBox?.self) { group in
            for ip in candidateIPs {
                group.addTask {
                    guard let url = URL(string: "http://\(ip)/api/about") else { return nil }
                    do {
                        let (data, resp) = try await session.data(from: url)
                        guard (resp as? HTTPURLResponse)?.statusCode == 200,
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let info = json["info"] as? [String: Any] else { return nil }
                        
                        let model = info["model"] as? String ?? info["boxtype"] as? String ?? "Enigma2"
                        let distro = info["friendlyimagedistro"] as? String ?? info["imagedistro"] as? String ?? "VTi"
                        let ver = info["imagever"] as? String ?? ""
                        let fullDistro = ver.isEmpty ? distro : "\(distro) \(ver)"
                        
                        var parsedTuners: [TunerInfo] = []
                        if let rawTuners = info["tuners"] as? [[String: Any]] {
                            for (idx, tDict) in rawTuners.enumerated() {
                                let name = tDict["name"] as? String ?? "Viritin \(idx)"
                                let type = tDict["type"] as? String ?? ""
                                let upper = type.uppercased()
                                let family: TunerFamily = upper.contains("DVB-C") ? .cable :
                                                         upper.contains("DVB-S") ? .satellite :
                                                         upper.contains("DVB-T") ? .terrestrial : .unknown
                                parsedTuners.append(TunerInfo(index: idx, name: name, type: type, family: family))
                            }
                        }
                        
                        let displayName = model.lowercased().contains("vu+") ? model : "Vu+ \(model)"
                        self.logDiscovery("Found Enigma2 box at \(ip): \(displayName)")
                        return EnigmaBox(
                            name: displayName,
                            ip: ip,
                            port: 80,
                            isOnline: true,
                            model: model,
                            distro: fullDistro,
                            tuners: parsedTuners
                        )
                    } catch {
                        return nil
                    }
                }
            }
            
            for await box in group {
                if let box = box {
                    discovered.append(box)
                }
            }
        }
        
        logDiscovery("Discovery complete. Total boxes found: \(discovered.count)")
        return discovered.sorted(by: { $0.ip < $1.ip })
    }
    
    // MARK: - Asetusten nouto (/etc/enigma2/settings)
    func fetchSettings(ip: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> (content: String, error: String?) {
        // Asennuspaketti (rootfs.tar.bz2 tai vastaava)
        if ip.hasPrefix("package://") {
            let path = String(ip.dropFirst("package://".count))
            let url = URL(fileURLWithPath: path)
            let res = await RootfsPackageService.shared.extractSettings(from: url)
            if let info = res.info {
                return (info.settingsContent, nil)
            } else {
                return ("", res.error ?? "Asetusten purku epäonnistui")
            }
        }
        
        // Paikallinen tiedosto tai arkisto
        if ip.hasPrefix("file://"), let url = URL(string: ip) {
            let pathExt = url.pathExtension.lowercased()
            if ["bz2", "gz", "tar", "zip"].contains(pathExt) || url.lastPathComponent.lowercased().contains("rootfs") {
                let res = await RootfsPackageService.shared.extractSettings(from: url)
                if let info = res.info {
                    return (info.settingsContent, nil)
                } else {
                    return ("", res.error ?? "Asetusten purku epäonnistui")
                }
            }
            if let content = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) {
                return (content, nil)
            }
        } else if ip.hasPrefix("/") {
            let url = URL(fileURLWithPath: ip)
            let pathExt = url.pathExtension.lowercased()
            if ["bz2", "gz", "tar", "zip"].contains(pathExt) || url.lastPathComponent.lowercased().contains("rootfs") {
                let res = await RootfsPackageService.shared.extractSettings(from: url)
                if let info = res.info {
                    return (info.settingsContent, nil)
                } else {
                    return ("", res.error ?? "Asetusten purku epäonnistui")
                }
            }
            if let content = (try? String(contentsOfFile: ip, encoding: .utf8)) ?? (try? String(contentsOfFile: ip, encoding: .isoLatin1)) {
                return (content, nil)
            }
        }
        
        // 1. Kokeillaan OpenWebifin natiivia /file?file=/etc/enigma2/settings
        if let webURL = formatURL(ip: ip, port: port, path: "file?file=/etc/enigma2/settings") {
            let (dataOpt, status) = await performRequest(url: webURL, timeout: 4.0, username: username, password: password)
            if status == 200, let data = dataOpt,
               let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
               !str.contains("<!DOCTYPE") && str.contains("config.") {
                return (str, nil)
            }
        }
        
        // 2. Kokeillaan FTP:tä
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("dl_settings_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        let cred = await ftpCredentials(ip: ip, username: username, password: password)
        let ftpURL = "ftp://\(cred)@\(ip)/etc/enigma2/settings"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-s", "--connect-timeout", "3", "--max-time", "5", ftpURL, "-o", tempFile.path]
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0,
               let data = try? Data(contentsOf: tempFile),
               let str = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
               !str.isEmpty {
                return (str, nil)
            }
        } catch {}
        
        return ("", "Yhteysvirhe: Ei voitu noutaa asetuksia osoitteesta \(ip) (laite ei vastaa).")
    }
    
    // MARK: - Asetusten siirto boksille
    func checkFTPConnection(ip: String, username: String? = nil, password: String? = nil) async -> Bool {
        let cred = await ftpCredentials(ip: ip, username: username, password: password)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-s", "-I", "--connect-timeout", "2", "--max-time", "3", "ftp://\(cred)@\(ip)/etc/enigma2/settings"]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    func uploadSettings(ip: String, content: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> (success: Bool, error: String?) {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("upload_settings_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        do {
            try content.write(to: tempFile, atomically: true, encoding: .utf8)
        } catch {
            return (false, "Tiedoston luominen epäonnistui: \(error.localizedDescription)")
        }
        
        let cred = await ftpCredentials(ip: ip, username: username, password: password)
        let ftpURL = "ftp://\(cred)@\(ip)/etc/enigma2/settings"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-sS", "--connect-timeout", "6", "-T", tempFile.path, ftpURL]
        
        let errPipe = Pipe()
        process.standardError = errPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return (true, nil)
            } else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrStr = (String(data: errData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                
                let code = process.terminationStatus
                let reason: String
                switch code {
                case 7:
                    reason = "Yhteys kohdeboksiin osoitteessa \(ip) epäonnistui (koodi 7: laite on sammutettu tai FTP-portti 21 ei vastaa)."
                case 9:
                    reason = "Pääsy evätty boksille (koodi 9: tiedosto-oikeusvirhe polulle /etc/enigma2/settings)."
                case 28:
                    reason = "FTP-aikakatkaisu (koodi 28: kohdeboksi ei vastannut pyyntöön ajoissa)."
                case 67:
                    reason = "FTP-kirjautumisvirhe (koodi 67: tarkista käyttäjätunnus ja salasana)."
                default:
                    if !stderrStr.isEmpty {
                        reason = "FTP-virhe (koodi \(code)): \(stderrStr)"
                    } else {
                        reason = "FTP-siirto epäonnistui (koodi \(code))."
                    }
                }
                return (false, reason)
            }
        } catch {
            return (false, "FTP-virhe: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Kaukosäädin (OpenWebif Keycodes)
    private static let keycodeMap: [String: Int] = [
        "KEY_POWER": 116,
        "POWER": 116,
        "KEY_1": 2,
        "KEY_2": 3,
        "KEY_3": 4,
        "KEY_4": 5,
        "KEY_5": 6,
        "KEY_6": 7,
        "KEY_7": 8,
        "KEY_8": 9,
        "KEY_9": 10,
        "KEY_0": 11,
        "KEY_MUTE": 113,
        "KEY_VOLUMEUP": 115,
        "KEY_VOLUMEDOWN": 114,
        "KEY_CHANNELUP": 402,
        "KEY_CHANNELDOWN": 403,
        "KEY_UP": 103,
        "KEY_DOWN": 108,
        "KEY_LEFT": 105,
        "KEY_RIGHT": 106,
        "KEY_OK": 352,
        "KEY_MENU": 139,
        "KEY_EXIT": 174,
        "KEY_INFO": 358,
        "KEY_EPG": 365,
        "KEY_AUDIO": 392,
        "KEY_SUBTITLE": 370,
        "KEY_TV": 377,
        "KEY_RADIO": 385,
        "KEY_MODE": 373,
        "KEY_PREVIOUS": 412,
        "KEY_NEXT": 407,
        "KEY_RED": 398,
        "KEY_GREEN": 399,
        "KEY_YELLOW": 400,
        "KEY_BLUE": 401,
        "KEY_REWIND": 168,
        "KEY_PLAY": 207,
        "KEY_PAUSE": 119,
        "KEY_FASTFORWARD": 159,
        "KEY_RECORD": 167,
        "KEY_STOP": 128
    ]
    
    func sendRemoteKey(ip: String, key: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> Bool {
        let commandCode: Int
        if let num = Int(key) {
            commandCode = num
        } else if let mapped = Self.keycodeMap[key.uppercased()] {
            commandCode = mapped
        } else {
            commandCode = 116
        }
        
        guard let url = formatURL(ip: ip, port: port, path: "api/remotecontrol?command=\(commandCode)") else { return false }
        let (dataOpt, code) = await performRequest(url: url, timeout: 2.5, username: username, password: password)
        if code == 200, let data = dataOpt,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let result = json["result"] as? Bool {
                return result
            }
        }
        
        // Fallback virtanapille: jos command=116 ei vastaa, käytetään /api/powerstate?newstate=0
        if commandCode == 116 {
            return await setPowerState(ip: ip, state: 0, port: port, username: username, password: password)
        }
        
        return code == 200
    }
    
    // MARK: - Viestin lähetys televisioon
    func sendMessage(ip: String, text: String, timeout: Int = 8, port: Int = 80, username: String? = nil, password: String? = nil) async -> Bool {
        let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        guard let url = formatURL(ip: ip, port: port, path: "api/message?text=\(encodedText)&type=1&timeout=\(timeout)") else { return false }
        let (_, code) = await performRequest(url: url, timeout: 3.5, username: username, password: password)
        return code == 200
    }
    
    // MARK: - Kuvakaappaus televisiosta (Live Screenshot)
    func grabScreenshot(ip: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> NSImage? {
        guard let url = formatURL(ip: ip, port: port, path: "grab?format=jpg&r=1280&mode=all") ?? formatURL(ip: ip, port: port, path: "grab?mode=all&r=720") else { return nil }
        let (dataOpt, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        if code == 200, let data = dataOpt {
            return NSImage(data: data)
        }
        return nil
    }
    
    // MARK: - Kanavan vaihto (Zap)
    func zap(ip: String, sRef: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> Bool {
        let encodedRef = sRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sRef
        guard let url = formatURL(ip: ip, port: port, path: "api/zap?sRef=\(encodedRef)") else { return false }
        let (_, code) = await performRequest(url: url, timeout: 3.0, username: username, password: password)
        return code == 200
    }
    
    // MARK: - Kanavalistan uudelleenlataus (Servicelist reload)
    func reloadServiceList(ip: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> Bool {
        guard let url = formatURL(ip: ip, port: port, path: "api/servicelistreload?mode=0") ?? formatURL(ip: ip, port: port, path: "web/servicelistreload?mode=0") else { return false }
        let (_, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        return code == 200
    }
    
    // MARK: - Virtatilan asetus
    /// 0 = Standby (vaihto), 1 = Deep standby, 2 = Reboot, 3 = Restart GUI
    func setPowerState(ip: String, state: Int, port: Int = 80, username: String? = nil, password: String? = nil) async -> Bool {
        guard let url = formatURL(ip: ip, port: port, path: "api/powerstate?newstate=\(state)") else { return false }
        let (_, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        return code == 200
    }
    
    // MARK: - Suosikkilistat (Bouquets)
    func fetchBouquets(ip: String, isRadio: Bool = false, port: Int = 80, username: String? = nil, password: String? = nil) async -> [Bouquet] {
        let path = isRadio ? "api/bouquets?stype=radio" : "api/bouquets"
        guard let url = formatURL(ip: ip, port: port, path: path) else { return [] }
        let (dataOpt, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        guard code == 200, let data = dataOpt else { return [] }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let bouquetList = json["bouquets"] as? [[Any]] {
            return bouquetList.compactMap { item -> Bouquet? in
                guard item.count >= 2,
                      let sRef = item[0] as? String,
                      let name = item[1] as? String else { return nil }
                return Bouquet(id: sRef, name: name, isRadio: isRadio)
            }
        }
        return []
    }
    
    // MARK: - Kanavat suosikkilistasta
    func fetchChannels(ip: String, bouquetRef: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> [Channel] {
        let encodedRef = bouquetRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bouquetRef
        guard let url = formatURL(ip: ip, port: port, path: "api/getservices?sRef=\(encodedRef)") else { return [] }
        let (dataOpt, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        guard code == 200, let data = dataOpt else { return [] }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let services = json["services"] as? [[String: Any]] {
            return services.compactMap { item -> Channel? in
                guard let sRef = item["servicereference"] as? String,
                      let name = item["servicename"] as? String else { return nil }
                return Channel(id: sRef, name: name)
            }
        }
        return []
    }
    
    // MARK: - Suosikkilistan ja kanavien muokkaus (Bouquet Editor)
    func addBouquet(ip: String, name: String, isRadio: Bool = false, port: Int = 80, username: String? = nil, password: String? = nil) async -> (success: Bool, message: String) {
        let safeName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        let type = isRadio ? "radio" : "tv"
        guard let url = formatURL(ip: ip, port: port, path: "bouqueteditor/api/addbouquet?name=\(safeName)&type=\(type)") else {
            return (false, "Virheellinen osoite")
        }
        let (dataOpt, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        _ = await reloadServiceList(ip: ip, port: port, username: username, password: password)
        if code == 200, let data = dataOpt,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let resultArr = json["Result"] as? [Any], resultArr.count >= 2 {
            let ok = resultArr[0] as? Bool ?? false
            let msg = resultArr[1] as? String ?? ""
            return (ok, msg)
        }
        return (code == 200, "")
    }

    func deleteBouquet(ip: String, bouquetRef: String, isRadio: Bool = false, port: Int = 80, username: String? = nil, password: String? = nil) async -> (success: Bool, message: String) {
        let encodedRef = bouquetRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bouquetRef
        guard let url = formatURL(ip: ip, port: port, path: "bouqueteditor/api/removebouquet?sBouquetRef=\(encodedRef)") else {
            return (false, "Virheellinen osoite")
        }
        let (dataOpt, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        _ = await reloadServiceList(ip: ip, port: port, username: username, password: password)
        if code == 200, let data = dataOpt,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let resultArr = json["Result"] as? [Any], resultArr.count >= 2 {
            let ok = resultArr[0] as? Bool ?? false
            let msg = resultArr[1] as? String ?? ""
            return (ok, msg)
        }
        return (code == 200, "")
    }

    func deleteChannelFromBouquet(ip: String, bouquetRef: String, channelRef: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> (success: Bool, message: String) {
        let encBq = bouquetRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bouquetRef
        let encCh = channelRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? channelRef
        guard let url = formatURL(ip: ip, port: port, path: "bouqueteditor/api/removeservice?sBouquetRef=\(encBq)&sRef=\(encCh)") else {
            return (false, "Virheellinen osoite")
        }
        let (dataOpt, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        _ = await reloadServiceList(ip: ip, port: port, username: username, password: password)
        if code == 200, let data = dataOpt,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let resultArr = json["Result"] as? [Any], resultArr.count >= 2 {
            let ok = resultArr[0] as? Bool ?? false
            let msg = resultArr[1] as? String ?? ""
            return (ok, msg)
        }
        return (code == 200, "")
    }
    
    func deleteMultipleChannelsFromBouquet(ip: String, bouquetRef: String, channelRefs: [String], port: Int = 80, username: String? = nil, password: String? = nil) async -> (success: Bool, count: Int) {
        let encBq = bouquetRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bouquetRef
        var successCount = 0
        for ch in channelRefs {
            let encCh = ch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ch
            if let url = formatURL(ip: ip, port: port, path: "bouqueteditor/api/removeservice?sBouquetRef=\(encBq)&sRef=\(encCh)") {
                let (_, code) = await performRequest(url: url, timeout: 3.0, username: username, password: password)
                if code == 200 { successCount += 1 }
            }
        }
        _ = await reloadServiceList(ip: ip, port: port, username: username, password: password)
        return (successCount > 0, successCount)
    }

    func addChannelToBouquet(ip: String, bouquetRef: String, channelRef: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> (success: Bool, message: String) {
        let encBq = bouquetRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bouquetRef
        let encCh = channelRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? channelRef
        guard let url = formatURL(ip: ip, port: port, path: "bouqueteditor/api/addservicetobouquet?sBouquetRef=\(encBq)&sRef=\(encCh)") else {
            return (false, "Virheellinen osoite")
        }
        let (dataOpt, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        _ = await reloadServiceList(ip: ip, port: port, username: username, password: password)
        if code == 200, let data = dataOpt,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let resultArr = json["Result"] as? [Any], resultArr.count >= 2 {
            let ok = resultArr[0] as? Bool ?? false
            let msg = resultArr[1] as? String ?? ""
            return (ok, msg)
        }
        return (code == 200, "")
    }

    func moveChannel(ip: String, bouquetRef: String, channelRef: String, position: Int, port: Int = 80, username: String? = nil, password: String? = nil) async -> (success: Bool, message: String) {
        let encBq = bouquetRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? bouquetRef
        let encCh = channelRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? channelRef
        guard let url = formatURL(ip: ip, port: port, path: "bouqueteditor/api/moveservice?sBouquetRef=\(encBq)&sRef=\(encCh)&position=\(position)") else {
            return (false, "Virheellinen osoite")
        }
        let (dataOpt, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        _ = await reloadServiceList(ip: ip, port: port, username: username, password: password)
        if code == 200, let data = dataOpt,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let resultArr = json["Result"] as? [Any], resultArr.count >= 2 {
            let ok = resultArr[0] as? Bool ?? false
            let msg = resultArr[1] as? String ?? ""
            return (ok, msg)
        }
        return (code == 200, "")
    }

    // MARK: - Kaikki kanavat (Hardware / Lamedb)
    func fetchAllChannels(ip: String, isRadio: Bool = false, port: Int = 80, username: String? = nil, password: String? = nil) async -> [Channel] {
        let sRef = isRadio
            ? "1:7:2:0:0:0:0:0:0:0:(type == 2) || (type == 10)"
            : "1:7:1:0:0:0:0:0:0:0:(type == 1) || (type == 17) || (type == 22) || (type == 25) || (type == 31) || (type == 134) || (type == 195) || (type == 211)"
        let encodedRef = sRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sRef
        guard let url = formatURL(ip: ip, port: port, path: "api/getservices?sRef=\(encodedRef)") else { return [] }
        let (dataOpt, code) = await performRequest(url: url, timeout: 5.0, username: username, password: password)
        guard code == 200, let data = dataOpt else { return [] }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let services = json["services"] as? [[String: Any]] {
            return services.compactMap { item -> Channel? in
                guard let sRef = item["servicereference"] as? String,
                      let name = item["servicename"] as? String else { return nil }
                return Channel(id: sRef, name: name)
            }
        }
        return []
    }
    
    // MARK: - Globaali kanavien poistaminen boksista (lamedb + init 4/3)
    func deleteChannelsGloballyFromLamedb(
        ip: String,
        channelRefs: [String],
        port: Int = 80,
        username: String? = nil,
        password: String? = nil,
        onProgress: @escaping @Sendable (String) -> Void
    ) async -> (success: Bool, count: Int, message: String) {
        var prefixList: [String] = []
        for sRef in channelRefs {
            let parts = sRef.components(separatedBy: ":")
            if parts.count >= 8,
               let typeVal = Int(parts[2], radix: 16),
               let tsidVal = Int(parts[4], radix: 16),
               let onidVal = Int(parts[5], radix: 16) {
                let sidVal = Int(parts[3], radix: 16) ?? 0
                let sidHex = String(format: "%04x", sidVal)
                let namespace = parts[6].lowercased()
                let tsidHex = String(format: "%04x", tsidVal)
                let onidHex = String(format: "%04x", onidVal)
                prefixList.append("\(sidHex):\(namespace):\(tsidHex):\(onidHex):\(typeVal):")
            }
        }
        
        guard !prefixList.isEmpty else {
            return (false, 0, "Ei kelvollisia kanavaviitteitä poistettavaksi.")
        }
        
        onProgress("Asetetaan digiboksi valmiustilaan ja pysäytetään toisto")
        _ = await setPowerState(ip: ip, state: 0, port: port, username: username, password: password)
        try? await Task.sleep(nanoseconds: 500_000_000)
        
        onProgress("Pysäytetään digiboksin käyttöliittymä (init 4)")
        let stopped = await runTelnetCommand(ip: ip, command: "init 4 && killall -9 enigma2", username: username, password: password)
        if !stopped {
            return (false, 0, "Telnet-komento 'init 4' epäonnistui. Tarkista yhteys boksiin.")
        }
        
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        onProgress("Ladataan kanavatietokantaa (lamedb) boksista")
        let cred = await ftpCredentials(ip: ip, username: username, password: password)
        let ftpURL = "ftp://\(cred)@\(ip)/etc/enigma2/lamedb"
        guard let url = URL(string: ftpURL) else {
            _ = await runTelnetCommand(ip: ip, command: "init 3", username: username, password: password)
            return (false, 0, "Virheellinen FTP-osoite.")
        }
        
        let lamedbContent: String
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let utf8 = String(data: data, encoding: .utf8) {
                lamedbContent = utf8
            } else if let latin1 = String(data: data, encoding: .isoLatin1) {
                lamedbContent = latin1
            } else {
                _ = await runTelnetCommand(ip: ip, command: "init 3", username: username, password: password)
                return (false, 0, "Tietokannan merkistökoodausvirhe.")
            }
        } catch {
            _ = await runTelnetCommand(ip: ip, command: "init 3", username: username, password: password)
            return (false, 0, "FTP-lataus epäonnistui: \(error.localizedDescription)")
        }
        
        onProgress("Käsitellään kanavatietokantaa (poistetaan \(prefixList.count) kanavaa)")
        let (updatedContent, removedCount) = removeServicesFromLamedb(content: lamedbContent, prefixes: prefixList)
        guard removedCount > 0 else {
            _ = await runTelnetCommand(ip: ip, command: "init 3", username: username, password: password)
            return (false, 0, "Valittuja kanavia ei löytynyt lamedb-tietokannasta.")
        }
        
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let tempFileURL = tempDir.appendingPathComponent("lamedb_\(UUID().uuidString)")
        do {
            try updatedContent.write(to: tempFileURL, atomically: true, encoding: .utf8)
        } catch {
            _ = await runTelnetCommand(ip: ip, command: "init 3", username: username, password: password)
            return (false, 0, "Väliaikaistiedoston luominen epäonnistui: \(error.localizedDescription)")
        }
        
        // Nollataan viimeksi toistettu kanava jotta boksi ei viritä poistettua kanavaa käynnistyessään ja luo sitä uudelleen
        _ = await runTelnetCommand(
            ip: ip,
            command: "sed -i '/config\\.tv\\.lastservice/d' /etc/enigma2/settings && sed -i '/config\\.servicelist\\.lastservice/d' /etc/enigma2/settings",
            username: username,
            password: password
        )
        
        onProgress("Siirretään muokattu lamedb boksiin (FTP)")
        let uploadProcess = Process()
        uploadProcess.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        uploadProcess.arguments = [
            "-s", "--connect-timeout", "6", "--max-time", "12",
            "-T", tempFileURL.path,
            "ftp://\(cred)@\(ip)/etc/enigma2/lamedb"
        ]
        var uploadSuccess = false
        do {
            try uploadProcess.run()
            uploadProcess.waitUntilExit()
            uploadSuccess = (uploadProcess.terminationStatus == 0)
        } catch {
            uploadSuccess = false
        }
        try? FileManager.default.removeItem(at: tempFileURL)
        
        if !uploadSuccess {
            _ = await runTelnetCommand(ip: ip, command: "init 3", username: username, password: password)
            return (false, 0, "Muokatun lamedb:n siirto boksiin epäonnistui.")
        }
        
        onProgress("Käynnistetään digiboksin käyttöliittymä uudelleen (init 3)")
        let started = await runTelnetCommand(ip: ip, command: "init 3", username: username, password: password)
        if !started {
            return (false, removedCount, "Lamedb päivitettiin, mutta 'init 3' ei vastannut. Käynnistä boksi manuaalisesti.")
        }
        
        onProgress("Odotetaan käyttöliittymän käynnistymistä (n. 7 sekuntia)")
        try? await Task.sleep(nanoseconds: 7_000_000_000)
        
        _ = await reloadServiceList(ip: ip, port: port, username: username, password: password)
        return (true, removedCount, "Poistettu \(removedCount) kanavaa pysyvästi lamedb-tietokannasta!")
    }
    
    // MARK: - Kaikkien kanavien tyhjennys boksista pysyvästi (lamedb + settings)
    func clearAllChannelsGloballyFromLamedb(
        ip: String,
        port: Int = 80,
        username: String? = nil,
        password: String? = nil,
        onProgress: @escaping @Sendable (String) -> Void
    ) async -> (success: Bool, count: Int, message: String) {
        let cred = await ftpCredentials(ip: ip, username: username, password: password)
        onProgress("Asetetaan digiboksi valmiustilaan ja pysäytetään toisto")
        _ = await setPowerState(ip: ip, state: 0, port: port, username: username, password: password)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        onProgress("Pysäytetään digiboksin käyttöliittymä (init 4)")
        let stopped = await runTelnetCommand(ip: ip, command: "init 4 && killall -9 enigma2", username: username, password: password)
        if !stopped {
            return (false, 0, "Telnet-komento 'init 4' epäonnistui. Tarkista yhteys boksiin.")
        }
        
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        onProgress("Ladataan kanavatietokanta (lamedb) boksista")
        let curlDownload = Process()
        curlDownload.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        curlDownload.arguments = ["-s", "--connect-timeout", "6", "--max-time", "12", "ftp://\(cred)@\(ip)/etc/enigma2/lamedb"]
        let dlPipe = Pipe()
        curlDownload.standardOutput = dlPipe
        var lamedbData: Data? = nil
        do {
            try curlDownload.run()
            let d = dlPipe.fileHandleForReading.readDataToEndOfFile()
            curlDownload.waitUntilExit()
            if curlDownload.terminationStatus == 0 && !d.isEmpty {
                lamedbData = d
            }
        } catch {}
        
        guard let data = lamedbData,
              let lamedbContent = (String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)) else {
            _ = await runTelnetCommand(ip: ip, command: "init 3", username: username, password: password)
            return (false, 0, "Kanavatietokannan (lamedb) lataus epäonnistui.")
        }
        
        onProgress("Tyhjennetään kanavat tietokannasta")
        let (clearedLamedb, removedCount) = purgeAllServicesFromLamedb(content: lamedbContent)
        
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let tempFileURL = tempDir.appendingPathComponent("lamedb_empty_\(UUID().uuidString)")
        do {
            try clearedLamedb.write(to: tempFileURL, atomically: true, encoding: .utf8)
        } catch {
            _ = await runTelnetCommand(ip: ip, command: "init 3", username: username, password: password)
            return (false, 0, "Väliaikaistiedoston luominen epäonnistui: \(error.localizedDescription)")
        }
        
        onProgress("Nollataan toistettu kanava ja palvelumuisti")
        _ = await runTelnetCommand(
            ip: ip,
            command: "sed -i '/config\\.tv\\.lastservice/d' /etc/enigma2/settings && sed -i '/config\\.servicelist\\.lastservice/d' /etc/enigma2/settings && sed -i '/config\\.tv\\.lastroot/d' /etc/enigma2/settings",
            username: username,
            password: password
        )
        
        onProgress("Siirretään tyhjennetty lamedb boksiin (FTP)")
        let uploadProcess = Process()
        uploadProcess.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        uploadProcess.arguments = [
            "-s", "--connect-timeout", "6", "--max-time", "12",
            "-T", tempFileURL.path,
            "ftp://\(cred)@\(ip)/etc/enigma2/lamedb"
        ]
        var uploadSuccess = false
        do {
            try uploadProcess.run()
            uploadProcess.waitUntilExit()
            uploadSuccess = (uploadProcess.terminationStatus == 0)
        } catch {
            uploadSuccess = false
        }
        try? FileManager.default.removeItem(at: tempFileURL)
        
        if !uploadSuccess {
            _ = await runTelnetCommand(ip: ip, command: "init 3", username: username, password: password)
            return (false, 0, "Tyhjennetyn lamedb:n siirto boksiin epäonnistui.")
        }
        
        onProgress("Käynnistetään digiboksin käyttöliittymä uudelleen (init 3)")
        let started = await runTelnetCommand(ip: ip, command: "init 3", username: username, password: password)
        if !started {
            return (false, removedCount, "Lamedb tyhjennettiin, mutta 'init 3' ei vastannut. Käynnistä boksi manuaalisesti.")
        }
        
        onProgress("Odotetaan käyttöliittymän käynnistymistä (n. 7 sekuntia)")
        try? await Task.sleep(nanoseconds: 7_000_000_000)
        
        _ = await reloadServiceList(ip: ip, port: port, username: username, password: password)
        return (true, removedCount, "Kaikki kanavat (\(removedCount) kpl) poistettu onnistuneesti boksista!")
    }
    
    private func purgeAllServicesFromLamedb(content: String) -> (updatedContent: String, count: Int) {
        let lines = content.components(separatedBy: .newlines)
        var updatedLines: [String] = []
        var inServices = false
        var serviceCount = 0
        var foundServicesTag = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "services" {
                inServices = true
                foundServicesTag = true
                updatedLines.append("services")
                continue
            }
            if inServices {
                if trimmed == "end" {
                    inServices = false
                    updatedLines.append("end")
                    continue
                }
                let parts = trimmed.components(separatedBy: ":")
                if parts.count >= 5 {
                    if let _ = Int(parts[0], radix: 16),
                       let _ = Int(parts[1], radix: 16),
                       let _ = Int(parts[2], radix: 16),
                       let _ = Int(parts[3], radix: 16),
                       let _ = Int(parts[4]) {
                        serviceCount += 1
                    }
                }
            } else {
                updatedLines.append(line)
            }
        }
        
        if !foundServicesTag {
            updatedLines.append("services")
            updatedLines.append("end")
            updatedLines.append("Have a lot of bugs!")
        }
        
        return (updatedLines.joined(separator: "\n"), serviceCount)
    }
    
    private func removeServicesFromLamedb(content: String, prefixes: [String]) -> (updatedContent: String, count: Int) {
        let lines = content.components(separatedBy: .newlines)
        var updatedLines: [String] = []
        var i = 0
        var inServices = false
        let searchPrefixSet = Set(prefixes.map { $0.lowercased() })
        var matchCount = 0
        
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if line == "services" {
                inServices = true
                updatedLines.append(lines[i])
                i += 1
                continue
            }
            if inServices && line == "end" {
                inServices = false
                updatedLines.append(lines[i])
                i += 1
                continue
            }
            
            if inServices {
                var matched = false
                let parts = line.lowercased().components(separatedBy: ":")
                if parts.count >= 5 {
                    let key = "\(parts[0]):\(parts[1]):\(parts[2]):\(parts[3]):\(parts[4]):"
                    if searchPrefixSet.contains(key) {
                        matched = true
                    }
                }
                
                if matched {
                    // Skipataan service-tietueen 3 riviä:
                    // 1. sid:namespace:tsid:onid:type:service_number
                    // 2. Kanavan nimi
                    // 3. Liput / provider / CA
                    i += 3
                    matchCount += 1
                } else {
                    updatedLines.append(lines[i])
                    i += 1
                }
            } else {
                updatedLines.append(lines[i])
                i += 1
            }
        }
        return (updatedLines.joined(separator: "\n"), matchCount)
    }
    
    // MARK: - EPG Ohjelmatiedot
    func fetchEPG(ip: String, sRef: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> [EPGEvent] {
        let encodedRef = sRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sRef
        guard let url = formatURL(ip: ip, port: port, path: "api/epgservice?sRef=\(encodedRef)") else { return [] }
        let (dataOpt, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        guard code == 200, let data = dataOpt else { return [] }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let eventsList = json["events"] as? [[String: Any]] {
            return eventsList.compactMap { item -> EPGEvent? in
                let id = (item["id"] as? Int) ?? (item["eventid"] as? Int) ?? 0
                let title = (item["title"] as? String) ?? "Ei otsikkoa"
                let desc = (item["shortdescription"] as? String) ?? (item["shortdesc"] as? String) ?? ""
                let longDesc = (item["longdescription"] as? String) ?? (item["longdesc"] as? String) ?? ""
                let start = (item["begin_timestamp"] as? Double) ?? 0.0
                let dur = (item["duration"] as? Int) ?? 0
                let eventSRef = (item["servicereference"] as? String) ?? sRef
                return EPGEvent(id: id, title: title, description: desc, longDescription: longDesc, beginTimestamp: start, duration: dur, sRef: eventSRef)
            }.sorted(by: { $0.beginTimestamp < $1.beginTimestamp })
        }
        return []
    }
    
    // MARK: - Nyt toistettava ohjelma (Now Playing)
    func fetchNowPlaying(ip: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> (channel: String, eventTitle: String, desc: String, start: Double, duration: Int)? {
        // 1. Tarkistetaan onko boksi valmiustilassa
        if let pURL = formatURL(ip: ip, port: port, path: "api/powerstate") {
            let (pDataOpt, pCode) = await performRequest(url: pURL, timeout: 2.5, username: username, password: password)
            if pCode == 200, let pData = pDataOpt,
               let pJson = try? JSONSerialization.jsonObject(with: pData) as? [String: Any] {
                var inStandby = false
                if let b = pJson["instandby"] as? Bool {
                    inStandby = b
                } else if let s = pJson["instandby"] as? String {
                    inStandby = s.lowercased() == "true" || s == "1"
                } else if let i = pJson["instandby"] as? Int {
                    inStandby = (i != 0)
                }
                if inStandby {
                    return (L10n("Remote_StandbyTitle"), L10n("Remote_StandbySubtitle"), L10n("Remote_StandbyHint"), 0, 0)
                }
            }
        }
        
        // 2. Haetaan nykyiset tiedot /api/getcurrent
        guard let url = formatURL(ip: ip, port: port, path: "api/getcurrent") else { return nil }
        let (dataOpt, code) = await performRequest(url: url, timeout: 3.0, username: username, password: password)
        guard code == 200, let data = dataOpt else { return nil }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let info = json["info"] as? [String: Any] ?? [:]
            let now = json["now"] as? [String: Any] ?? [:]
            
            let rawCh = (now["sname"] as? String) ?? (info["name"] as? String) ?? ""
            let rawTitle = (now["title"] as? String) ?? (info["eventtitle"] as? String) ?? (info["title"] as? String) ?? ""
            let rawDesc = (now["shortdesc"] as? String) ?? (info["eventdescription"] as? String) ?? ""
            let start = (now["begin_timestamp"] as? Double) ?? (info["eventstart"] as? Double) ?? 0
            let dur = (now["duration_sec"] as? Int) ?? (info["eventduration"] as? Int) ?? 0
            
            func cleanText(_ str: String) -> String {
                return str
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&#39;", with: "'")
                    .replacingOccurrences(of: "&apos;", with: "'")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            func isNA(_ str: String) -> Bool {
                let cleaned = cleanText(str)
                if cleaned.isEmpty { return true }
                let lower = cleaned.lowercased()
                return lower == "n/a" || lower == "<n/a>" || lower == "none" || lower == "null"
            }
            
            let ch = isNA(rawCh) ? "" : cleanText(rawCh)
            let title = isNA(rawTitle) ? "" : cleanText(rawTitle)
            let desc = isNA(rawDesc) ? "" : cleanText(rawDesc)
            
            if ch.isEmpty && title.isEmpty {
                return ("Ei aktiivista kanavaa", "Ei toistettavaa lähetystä", "Boksi on päällä, mutta TV-kanavaa ei ole viritetty tai toisto on pysäytetty.", 0, 0)
            }
            
            return (ch.isEmpty ? "Ei kanavatietoa" : ch,
                    title.isEmpty ? "Ei ohjelmatietoja" : title,
                    desc, start, dur)
        }
        return nil
    }
    
    // MARK: - Ajastukset (Timers)
    func fetchTimers(ip: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> [EnigmaTimer] {
        guard let url = formatURL(ip: ip, port: port, path: "api/timerlist") else { return [] }
        let (dataOpt, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        guard code == 200, let data = dataOpt else { return [] }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let list = json["timers"] as? [[String: Any]] {
            return list.compactMap { item -> EnigmaTimer? in
                let eventId = (item["eventid"] as? Int) ?? 0
                let sRef = (item["serviceref"] as? String) ?? (item["servicereference"] as? String) ?? ""
                let name = (item["name"] as? String) ?? ""
                let desc = (item["description"] as? String) ?? ""
                let begin = (item["begin"] as? Double) ?? 0.0
                let end = (item["end"] as? Double) ?? 0.0
                let state = (item["state"] as? Int) ?? 0
                return EnigmaTimer(eventId: eventId, sRef: sRef, name: name, description: desc, begin: begin, end: end, state: state)
            }
        }
        return []
    }
    
    /// TÄRKEÄ SÄÄNTÖ: Enigma2 timeraddbyeventid vaatii:
    /// - sRef EI saa olla URL-enkoodattu!
    /// - eventid on pakollinen parametri!
    func addTimerByEventId(ip: String, sRef: String, eventId: Int, port: Int = 80, username: String? = nil, password: String? = nil) async -> Bool {
        let path = "api/timeraddbyeventid?sRef=\(sRef)&eventid=\(eventId)"
        guard let url = formatURL(ip: ip, port: port, path: path) else { return false }
        let (dataOpt, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        if code == 200, let data = dataOpt {
            let str = String(data: data, encoding: .utf8) ?? ""
            return str.contains("\"result\": true") || str.contains("<e2state>True</e2state>")
        }
        return false
    }
    
    func deleteTimer(ip: String, sRef: String, begin: Double, end: Double, port: Int = 80, username: String? = nil, password: String? = nil) async -> Bool {
        let encodedRef = sRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sRef
        let path = "api/timerdelete?sRef=\(encodedRef)&begin=\(Int(begin))&end=\(Int(end))"
        guard let url = formatURL(ip: ip, port: port, path: path) else { return false }
        let (_, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        return code == 200
    }
    
    // MARK: - Automaattiajastukset (AutoTimers)
    func fetchAutoTimers(ip: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> [AutoTimerRule] {
        guard let url = formatURL(ip: ip, port: port, path: "autotimer") else { return [] }
        let (dataOpt, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        guard code == 200, let data = dataOpt else { return [] }
        let xmlString = String(data: data, encoding: .utf8) ?? ""
        guard let regex = try? NSRegularExpression(pattern: "<timer [^>]*name=\"([^\"]+)\" [^>]*match=\"([^\"]+)\" [^>]*id=\"(\\d+)\"") else { return [] }
        let matches = regex.matches(in: xmlString, range: NSRange(xmlString.startIndex..., in: xmlString))
        var rules: [AutoTimerRule] = []
        for match in matches {
            if let nameRange = Range(match.range(at: 1), in: xmlString),
               let matchRange = Range(match.range(at: 2), in: xmlString),
               let idRange = Range(match.range(at: 3), in: xmlString) {
                rules.append(AutoTimerRule(
                    ruleId: String(xmlString[idRange]),
                    name: String(xmlString[nameRange]),
                    match: String(xmlString[matchRange])
                ))
            }
        }
        return rules
    }
    
    func deleteAutoTimer(ip: String, ruleId: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> Bool {
        guard let url = formatURL(ip: ip, port: port, path: "autotimer/remove?id=\(ruleId)") else { return false }
        let (_, code) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
        if let reloadURL = formatURL(ip: ip, port: port, path: "api/autotimer/reload") {
            let _ = await performRequest(url: reloadURL, timeout: 2.0, username: username, password: password)
        }
        return code == 200
    }
    
    // MARK: - Tallenteet (Movies)
    func fetchMovies(ip: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> [EnigmaMovie] {
        guard let url = formatURL(ip: ip, port: port, path: "api/movielist") else { return [] }
        let (dataOpt, code) = await performRequest(url: url, timeout: 5.0, username: username, password: password)
        guard code == 200, let data = dataOpt else { return [] }
        do {
            let response = try JSONDecoder().decode(MovieResponse.self, from: data)
            return response.movies.sorted(by: { $0.time > $1.time })
        } catch {
            return []
        }
    }
    
    func deleteMovie(ip: String, sRef: String, port: Int = 80, username: String? = nil, password: String? = nil) async -> Bool {
        let encodedSRef = sRef.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sRef
        guard let url = formatURL(ip: ip, port: port, path: "api/moviedelete?sRef=\(encodedSRef)") else { return false }
        let (_, code) = await performRequest(url: url, timeout: 5.0, username: username, password: password)
        return code == 200
    }
    
    // MARK: - Käynnistyskuvan siirto boksille (Bootlogo upload)
    func uploadBootlogo(
        ip: String,
        mviData: Data,
        targetFileName: String,
        distro: EnigmaImageDistro = .auto,
        box: EnigmaBox? = nil,
        username: String? = nil,
        password: String? = nil
    ) async -> (success: Bool, error: String?) {
        var resolvedBox = box
        if resolvedBox?.distro == nil {
            let port = box?.port ?? 80
            let info = await queryBoxInfo(ip: ip, port: port, username: username, password: password)
            if let d = info.distro {
                if resolvedBox != nil {
                    resolvedBox?.distro = d
                } else {
                    resolvedBox = EnigmaBox(name: "Box", ip: ip, port: port, distro: d)
                }
            }
        }
        
        let cred = await ftpCredentials(ip: ip, username: username, password: password)
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("bootlogo_\(UUID().uuidString).mvi")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        
        do {
            try mviData.write(to: tempFile)
        } catch {
            return (false, "Väliaikaistiedoston kirjoitus epäonnistui: \(error.localizedDescription)")
        }
        
        let targetDir = distro.resolvedBootlogoPath(for: resolvedBox)
        let cleanDir = targetDir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let ftpURL = "ftp://\(cred)@\(ip)//\(cleanDir)/\(targetFileName)"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-s", "--connect-timeout", "6", "--ftp-create-dirs", "-T", tempFile.path, ftpURL]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return (true, nil)
            } else {
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let code = process.terminationStatus
                if code == 67 || errStr.contains("530") || errStr.lowercased().contains("login incorrect") {
                    return (false, "FTP-kirjautumisvirhe (koodi 67: tarkista boksille asetettu salasana). Huom: OpenViX ja uudet Enigma2-jakelut vaativat salasanan asettamisen boksille ennen FTP-yhteyttä (Menu -> Asetukset -> Järjestelmä -> Verkko -> Salasana).")
                } else if code == 7 {
                    return (false, "Yhteys kohdeboksiin osoitteessa \(ip) epäonnistui (FTP-portti 21 ei vastaa).")
                } else {
                    let detail = errStr.isEmpty ? "koodi \(code)" : errStr
                    return (false, "FTP-siirto epäonnistui: \(detail)")
                }
            }
        } catch {
            return (false, "Siirtovirhe: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Käynnistyskuvan lataus boksista (Bootlogo download)
    func downloadBootlogo(
        ip: String,
        port: Int = 80,
        fileName: String,
        distro: EnigmaImageDistro = .auto,
        box: EnigmaBox? = nil,
        username: String? = nil,
        password: String? = nil
    ) async -> (data: Data?, error: String?) {
        var resolvedBox = box
        if resolvedBox?.distro == nil {
            let info = await queryBoxInfo(ip: ip, port: port, username: username, password: password)
            if let d = info.distro {
                if resolvedBox != nil {
                    resolvedBox?.distro = d
                } else {
                    resolvedBox = EnigmaBox(name: "Box", ip: ip, port: port, distro: d)
                }
            }
        }
        
        let primaryPath = distro.resolvedBootlogoPath(for: resolvedBox)
        var candidatePaths = [primaryPath]
        let allFallbacks = ["/usr/share", "/usr/share/vuplus-bootlogo", "/usr/share/enigma2", "/boot"]
        for fb in allFallbacks where !candidatePaths.contains(fb) {
            candidatePaths.append(fb)
        }
        
        // 1. Kokeillaan ensin OpenWebif HTTP -rajapintaa (/file?file=...)
        // Tämä on erittäin nopea ja toimii ilman FTP-palvelimen salasanarajoituksia
        for dir in candidatePaths {
            let fullPath = "\(dir)/\(fileName)"
            if let url = formatURL(ip: ip, port: port, path: "file?file=\(fullPath)") {
                let (dataOpt, status) = await performRequest(url: url, timeout: 4.0, username: username, password: password)
                if status == 200, let data = dataOpt, data.count > 100 {
                    let preview = String(data: data.prefix(100), encoding: .utf8) ?? ""
                    if !preview.lowercased().contains("not found") {
                        return (data, nil)
                    }
                }
            }
        }
        
        // 2. Jos HTTP ei tuottanut tulosta, kokeillaan FTP-yhteyttä
        let cred = await ftpCredentials(ip: ip, username: username, password: password)
        var hadAuthError = false
        
        for dir in candidatePaths {
            let cleanDir = dir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let ftpURL = "ftp://\(cred)@\(ip)//\(cleanDir)/\(fileName)"
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = ["-s", "--connect-timeout", "4", "--max-time", "8", ftpURL]
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0 && data.count > 100 {
                    return (data, nil)
                } else if process.terminationStatus == 67 {
                    hadAuthError = true
                }
            } catch {}
        }
        
        if hadAuthError {
            return (nil, "FTP-kirjautumisvirhe (koodi 67). Tarkista boksille asetettu salasana (OpenViX vaatii salasanan asettamisen boksille).")
        }
        
        return (nil, "Tiedostoa '\(fileName)' ei löytynyt boksista tai FTP-yhteys epäonnistui.")
    }
    
    // MARK: - Telnet-komennon suoritus tulosteen palautuksella
    func executeTelnetCommand(
        ip: String,
        command: String,
        port: Int = 23,
        timeout: TimeInterval = 6.0,
        username: String? = nil,
        password: String? = nil
    ) async -> (success: Bool, output: String) {
        var u = username
        var p = password
        await resolveCredentials(for: ip, username: &u, password: &p)
        let user = (u?.isEmpty == false) ? u! : "root"
        let pass = p ?? ""
        let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) ?? NWEndpoint.Port(rawValue: 23)!
        let host = NWEndpoint.Host(ip)
        let connection = NWConnection(host: host, port: nwPort, using: .tcp)
        
        enum TelnetState: Equatable, Sendable {
            case connecting
            case waitingForLogin
            case waitingForPassword
            case waitingForPrompt
            case waitingForCommandResult
            case done
        }
        
        // Tuloste rajataan merkeillä. Kaiku ja kehotteet sammutetaan, jotta tulosteessa on vain
        // komennon oma tuloste (pääte toistaisi muuten jokaisen rivin, esim. "echo OK" -tarkistukset).
        // Lainausmerkit pitävät alkumerkin poissa kaiusta, ja merkit ovat omilla riveillään,
        // jotta myös heredoc-komennot toimivat.
        let wrappedCommand = "stty -echo 2>/dev/null; PS1=''; PS2=''; echo __ES_\"\"BEGIN__\n\(command)\necho \"__ES_END_$?__\"\n"

        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "enigmasuite.telnet.exec")
            var isResumed = false
            var buffer = ""
            var commandOutput = ""
            var state: TelnetState = .connecting
            
            func finish(success: Bool) {
                if !isResumed {
                    isResumed = true
                    connection.cancel()
                    let clean = Self.extractMarkedOutput(commandOutput)
                    continuation.resume(returning: (success, clean.isEmpty && success ? "(Komento suoritettu)" : clean))
                }
            }
            
            queue.asyncAfter(deadline: .now() + timeout) {
                finish(success: state == .waitingForCommandResult || state == .done)
            }
            
            func send(_ text: String) {
                guard let data = text.data(using: .utf8) else { return }
                connection.send(content: data, completion: .contentProcessed { error in
                    if error != nil { finish(success: false) }
                })
            }
            
            func readLoop() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                    if error != nil {
                        finish(success: false)
                        return
                    }
                    
                    if let data = data {
                        // Suodatetaan Telnet IAC (0xFF) ohjaustavut
                        var filteredData = Data()
                        var i = 0
                        let bytes = [UInt8](data)
                        while i < bytes.count {
                            if bytes[i] == 0xFF {
                                if i + 2 < bytes.count { i += 3 } else { i += 1 }
                            } else {
                                filteredData.append(bytes[i])
                                i += 1
                            }
                        }
                        
                        let text = String(data: filteredData, encoding: .utf8) ?? String(data: filteredData, encoding: .ascii) ?? ""
                        buffer += text
                        let lower = buffer.lowercased()
                        
                        switch state {
                        case .connecting, .waitingForLogin:
                            if lower.contains("login:") {
                                state = pass.isEmpty ? .waitingForPrompt : .waitingForPassword
                                buffer = ""
                                send("\(user)\n")
                            } else if lower.contains("password:") {
                                state = .waitingForPrompt
                                buffer = ""
                                send("\(pass)\n")
                            } else if Self.looksLikePrompt(buffer) {
                                state = .waitingForCommandResult
                                buffer = ""
                                commandOutput = ""
                                send(wrappedCommand)
                            }
                        case .waitingForPassword:
                            if lower.contains("password:") {
                                state = .waitingForPrompt
                                buffer = ""
                                send("\(pass)\n")
                            } else if Self.looksLikePrompt(buffer) {
                                state = .waitingForCommandResult
                                buffer = ""
                                commandOutput = ""
                                send(wrappedCommand)
                            }
                        case .waitingForPrompt:
                            if Self.looksLikePrompt(buffer) {
                                state = .waitingForCommandResult
                                buffer = ""
                                commandOutput = ""
                                send(wrappedCommand)
                            }
                        case .waitingForCommandResult:
                            // Valmis vasta kun loppumerkki näkyy: bannerit tai tulosteen "$ "/"# " eivät päätä komentoa
                            commandOutput += text
                            if Self.containsEndMarker(commandOutput) {
                                state = .done
                                finish(success: true)
                                return
                            }
                        case .done:
                            finish(success: true)
                            return
                        }
                    }
                    
                    if isComplete {
                        finish(success: state == .waitingForCommandResult || state == .done)
                    } else {
                        readLoop()
                    }
                }
            }
            
            connection.stateUpdateHandler = { newState in
                if case .ready = newState {
                    state = .waitingForLogin
                    readLoop()
                } else if case .failed = newState {
                    finish(success: false)
                }
            }
            
            connection.start(queue: queue)
        }
    }
    
    /// Kehote tunnistetaan vain puskurin viimeiseltä riviltä (esim. "root@box:~# ").
    /// Bannerien ASCII-taiteessa (esim. VTi:n "$$") on muuten "$ "-merkkejä keskellä tekstiä.
    nonisolated static func looksLikePrompt(_ buffer: String) -> Bool {
        let lastLine = buffer.components(separatedBy: "\n").last?.replacingOccurrences(of: "\r", with: "") ?? ""
        return lastLine.hasSuffix("# ") || lastLine.hasSuffix("$ ") || lastLine.hasSuffix("#") || lastLine.hasSuffix("$")
    }

    nonisolated static func containsEndMarker(_ output: String) -> Bool {
        output.range(of: "__ES_END_[0-9]+__", options: .regularExpression) != nil
    }

    /// Palauttaa vain alku- ja loppumerkin välisen tulosteen (ilman komennon kaikua ja kehotteita).
    nonisolated static func extractMarkedOutput(_ raw: String) -> String {
        let lines = raw
            .replacingOccurrences(of: "\r\r\n", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n")
        guard let begin = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "__ES_BEGIN__" }) else {
            return ""
        }
        var body: [String] = []
        for line in lines[(begin + 1)...] {
            if line.range(of: "^__ES_END_[0-9]+__$", options: .regularExpression) != nil { break }
            body.append(line)
        }
        return body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Telnet-komento tilakoneella (Bool palautus)
    func runTelnetCommand(ip: String, command: String, port: Int = 23, timeout: TimeInterval = 12.0, username: String? = nil, password: String? = nil) async -> Bool {
        let (ok, _) = await executeTelnetCommand(ip: ip, command: command, port: port, timeout: timeout, username: username, password: password)
        return ok
    }
    
    // MARK: - Varmuuskopiot
    func backupDirectory(for boxName: String) -> URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
        let safeName = boxName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let dir = pictures.appendingPathComponent("EnigmaSuiteBackups/\(safeName)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    func saveBackup(box: EnigmaBox, content: String) -> URL? {
        let dir = backupDirectory(for: box.name)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        
        let fileURL = dir.appendingPathComponent("settings_\(timestamp).settings")
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }
    
    func listBackups(for box: EnigmaBox) -> [BackupRecord] {
        let dir = backupDirectory(for: box.name)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: .skipsHiddenFiles) else {
            return []
        }
        
        var list: [BackupRecord] = []
        for file in files where file.pathExtension.lowercased() == "settings" {
            let res = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            let date = res?.contentModificationDate ?? Date()
            let linesCount = (try? String(contentsOf: file, encoding: .utf8))?.components(separatedBy: .newlines).count ?? 0
            
            list.append(BackupRecord(
                boxName: box.name,
                boxIP: box.ip,
                date: date,
                fileURL: file,
                entryCount: linesCount
            ))
        }
        
        return list.sorted(by: { $0.date > $1.date })
    }
    
    // MARK: - Image & Varmuuskopiot (Full Backup & Remote Flash)
    
    /// Varmistaa että FTP toimii myös tyhjällä salasanalla (lisää 'nullok' vsftpd PAM -asetuksiin tarvittaessa)
    func ensureFTPAllowed(box: EnigmaBox) async {
        let cmd = "grep -q 'nullok' /etc/pam.d/vsftpd 2>/dev/null || (sed -i 's/pam_unix.so shadow$/pam_unix.so shadow nullok/' /etc/pam.d/vsftpd 2>/dev/null && echo 'OK')"
        _ = await executeTelnetCommand(ip: box.ip, command: cmd, timeout: 4.0, username: box.username, password: box.password)
    }
    
    /// Hakee boksiin liitetyt tallennuslaitteet (USB, HDD jne.)
    func fetchBoxStorageDevices(box: EnigmaBox) async -> [BoxStorageDevice] {
        // -P: yksi rivi per levy (BusyBox rivittää muuten pitkät laitenimet omalle rivilleen).
        // Ilman polkuja df ei herätä autofs-/verkkolevyjä, jotka voisivat jumittaa komennon.
        let (success, output) = await executeTelnetCommand(
            ip: box.ip,
            command: "df -Pk 2>/dev/null",
            timeout: 8.0,
            username: box.username,
            password: box.password
        )
        guard success else { return [] }
        return Self.parseStorageDevices(dfOutput: output)
    }

    static func parseStorageDevices(dfOutput: String) -> [BoxStorageDevice] {
        var devices: [BoxStorageDevice] = []
        var seenDevices = Set<String>()
        var pending: String?

        for rawLine in dfOutput.components(separatedBy: .newlines) {
            var parts = rawLine.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            // Varmuuden vuoksi: rivitetty laitenimi yhdistetään seuraavaan riviin
            if parts.count == 1 { pending = parts[0]; continue }
            if let fs = pending, parts.count == 5 { parts.insert(fs, at: 0) }
            pending = nil
            guard parts.count >= 6 else { continue }

            let fs = parts[0]
            let mount = parts[5...].joined(separator: " ")
            guard mount.hasPrefix("/media/") else { continue }
            guard !["tmpfs", "devtmpfs", "autofs", "none", "udev", "overlay"].contains(fs) else { continue }
            guard let totalKb = Int64(parts[1]), let availKb = Int64(parts[3]), totalKb > 0 else { continue }

            // Sama levy voi olla liitettynä kahteen kohtaan (esim. /media/hdd ja /media/sda1)
            guard !seenDevices.contains(fs) else { continue }
            seenDevices.insert(fs)

            let usedPercent = Int(parts[4].replacingOccurrences(of: "%", with: "")) ?? 0
            let lastPart = mount.components(separatedBy: "/").last ?? ""
            let friendlyName: String
            if lastPart.lowercased().contains("hdd") {
                friendlyName = "Kiintolevy (HDD)"
            } else if lastPart.lowercased().contains("usb") {
                friendlyName = "USB-muisti (\(lastPart))"
            } else if fs.contains("sd") {
                friendlyName = "USB-tallennusväline (\(fs.components(separatedBy: "/").last ?? ""))"
            } else {
                friendlyName = "Tallennusväline (\(lastPart))"
            }

            devices.append(BoxStorageDevice(
                name: friendlyName,
                mountPoint: mount,
                device: fs,
                totalBytes: totalKb * 1024,
                availableBytes: availKb * 1024,
                usedPercent: usedPercent
            ))
        }

        return devices.sorted(by: { $0.availableBytes > $1.availableBytes })
    }
    
    /// Hakee multiboot-slotit ja niihin asennetut imaget
    func fetchMultibootSlots(box: EnigmaBox) async -> (currentSlot: Int?, slots: [MultibootSlotInfo]) {
        let probeScript = "CMDLINE=$(cat /proc/cmdline 2>/dev/null); echo \"CMDLINE:$CMDLINE\"; for s in 1 2 3 4; do if [ -f \"/boot/STARTUP_$s\" ]; then echo \"STARTUP_EXISTS:$s\"; fi; done; mkdir -p /tmp/emmc_probe; ROOT_DEV=$(echo \"$CMDLINE\" | grep -o 'root=[^ ]*' | cut -d= -f2); if [ -n \"$ROOT_DEV\" ] && mount \"$ROOT_DEV\" /tmp/emmc_probe 2>/dev/null; then for s in 1 2 3 4; do if [ -d \"/tmp/emmc_probe/linuxrootfs$s\" ]; then IMG=\"\"; if [ -f \"/tmp/emmc_probe/linuxrootfs$s/etc/image-version\" ]; then DIS=$(grep -i '^distro=' /tmp/emmc_probe/linuxrootfs$s/etc/image-version | cut -d= -f2 | tr -d ' '); [ -z \"$DIS\" ] && DIS=$(grep -i '^creator=' /tmp/emmc_probe/linuxrootfs$s/etc/image-version | cut -d= -f2 | tr -d ' '); VER=$(grep -i '^version=' /tmp/emmc_probe/linuxrootfs$s/etc/image-version | cut -d= -f2 | tr -d ' '); IMG=\"$DIS $VER\"; elif [ -f \"/tmp/emmc_probe/linuxrootfs$s/etc/issue\" ]; then IMG=$(head -n 1 /tmp/emmc_probe/linuxrootfs$s/etc/issue | tr -d '\\r\\n'); fi; echo \"SLOT_INFO:$s:$IMG\"; fi; done; umount /tmp/emmc_probe 2>/dev/null; fi; rmdir /tmp/emmc_probe 2>/dev/null"
        
        let (success, output) = await executeTelnetCommand(
            ip: box.ip,
            command: probeScript,
            timeout: 8.0,
            username: box.username,
            password: box.password
        )
        guard success else {
            return (nil, [MultibootSlotInfo(slot: 1, installedImage: box.distro, isCurrent: true)])
        }
        
        var currentSlot: Int? = nil
        var foundSlots = Set<Int>()
        var slotImages: [Int: String] = [:]
        
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("CMDLINE:") {
                if let match = line.range(of: "rootsubdir=linuxrootfs") {
                    let rest = String(line[match.upperBound...])
                    if let slotChar = rest.first, let num = Int(String(slotChar)) {
                        currentSlot = num
                    }
                }
            } else if line.contains("STARTUP_EXISTS:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2, let s = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    foundSlots.insert(s)
                }
            } else if line.contains("SLOT_INFO:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 3, let s = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)) {
                    let img = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                    slotImages[s] = img
                }
            }
        }
        
        if foundSlots.isEmpty {
            return (1, [MultibootSlotInfo(slot: 1, installedImage: box.distro, isCurrent: true)])
        }
        
        var resultSlots: [MultibootSlotInfo] = []
        for s in 1...4 {
            let isCur = (s == currentSlot)
            var imgName = slotImages[s]
            if isCur && (imgName == nil || imgName?.isEmpty == true) {
                imgName = box.distro
            }
            resultSlots.append(MultibootSlotInfo(
                slot: s,
                installedImage: imgName,
                isCurrent: isCur
            ))
        }
        
        return (currentSlot, resultSlots)
    }
    
    /// Hakee tallennuslaitteilta valmiit image-varmuuskopiot: zip-paketit sekä purettuina
    /// kansioina tallennetut (esim. VTi:n oma "vti-image-backup" tai EnigmaSuiten zip-vapaa varmuuskopio).
    func fetchBoxImageBackups(box: EnigmaBox, storageDevices: [BoxStorageDevice]) async -> [ImageBackupItem] {
        guard !storageDevices.isEmpty else { return [] }
        let mounts = storageDevices.map { "'\($0.mountPoint)'" }.joined(separator: " ")
        // Tulosteen rivit: Z|koko tavuina|aika|polku tai D|koko kt|aika|kansio. Toimii myös BusyBox 1.2x:ssä.
        let cmd = """
        for M in \(mounts); do \
        find "$M" -maxdepth 3 -type f -name '*.zip' 2>/dev/null | grep -v -e '/flash_tmp/' -e '/movie/' -e '/.work_' | while read F; do \
        echo "Z|$(ls -ln "$F" | awk '{print $5}')|$(date -r "$F" +%s 2>/dev/null)|$F"; done; \
        find "$M" -maxdepth 6 -type f \\( -name kernel_auto.bin -o -name kernel.bin -o -name vmlinux.bin \\) 2>/dev/null | grep -v -e '/flash_tmp/' -e '/movie/' -e '/.work_' | while read K; do \
        D=$(dirname "$K"); ls "$D"/rootfs.* >/dev/null 2>&1 || continue; P=$(dirname "$D"); \
        case "$(basename "$P")" in vuplus|gigablue|zgemma|dreambox|edision|octagon|xtrend|formuler|dinobot|axas|maxytec|uclan|mutant|ceryon|airdigital|gfutures|hd|ini|xp|protek|wetek|beyonwiz|abcom|clap|dags|ustym) R=$(dirname "$P");; *) R="$P";; esac; \
        echo "D|$(du -sk "$R" | awk '{print $1}')|$(date -r "$K" +%s 2>/dev/null)|$R"; done; \
        done | sort -u
        """
        let (success, output) = await executeTelnetCommand(
            ip: box.ip,
            command: cmd,
            timeout: 15.0,
            username: box.username,
            password: box.password
        )
        guard success else { return [] }

        var items: [ImageBackupItem] = []
        var seen = Set<String>()
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4, parts[0] == "Z" || parts[0] == "D" else { continue }
            let isFolder = parts[0] == "D"
            let path = parts[3].trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty, !seen.contains(path), let size = Int64(parts[1]) else { continue }
            seen.insert(path)

            let fileName = path.components(separatedBy: "/").last ?? path
            var date = TimeInterval(parts[2]).map { Date(timeIntervalSince1970: $0) }
            if date == nil || date! < Date(timeIntervalSince1970: 86_400 * 365) {
                date = Self.dateFromBackupName(fileName) ?? date
            }
            let mountPoint = storageDevices.first(where: { path.hasPrefix($0.mountPoint + "/") })?.mountPoint ?? ""

            items.append(ImageBackupItem(
                fileName: fileName,
                remotePath: path,
                sizeBytes: isFolder ? size * 1024 : size,
                creationDate: date,
                mountPoint: mountPoint,
                isFolder: isFolder
            ))
        }

        return items.sorted(by: { ($0.creationDate ?? Date.distantPast) > ($1.creationDate ?? Date.distantPast) })
    }

    /// Päivämäärä tiedoston nimestä: 20260801_1401(32) tai 2026-08-01_14-01-32
    nonisolated static func dateFromBackupName(_ name: String) -> Date? {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        let patterns: [(String, (String) -> String?)] = [
            ("\\d{4}-\\d{2}-\\d{2}_\\d{2}-\\d{2}(-\\d{2})?", { $0.count == 19 ? "yyyy-MM-dd_HH-mm-ss" : "yyyy-MM-dd_HH-mm" }),
            ("\\d{8}_\\d{4,6}", { $0.count == 15 ? "yyyyMMdd_HHmmss" : ($0.count == 13 ? "yyyyMMdd_HHmm" : nil) })
        ]
        for (pattern, format) in patterns {
            guard let range = name.range(of: pattern, options: .regularExpression) else { continue }
            let text = String(name[range])
            if let f = format(text) {
                df.dateFormat = f
                if let d = df.date(from: text) { return d }
            }
        }
        return nil
    }
    
    /// Poistaa varmuuskopion boksista (zip-tiedosto tai purettu varmuuskopiokansio)
    func deleteBoxImageBackup(box: EnigmaBox, item: ImageBackupItem) async -> Bool {
        let path = item.remotePath
        // Kansio poistetaan vain, jos se on selvästi tallennuslaitteella oleva varmuuskopio
        let depth = path.split(separator: "/").count
        guard path.hasPrefix("/media/"), !path.contains(".."), !path.contains("'"), depth >= 3 else { return false }
        let (ok, _) = await executeTelnetCommand(
            ip: box.ip,
            command: item.isFolder ? "rm -rf '\(path)'" : "rm -f '\(path)'",
            timeout: 10.0,
            username: box.username,
            password: box.password
        )
        return ok
    }
    
    /// Vaihtaa aktiivisen multiboot-slotin ja käynnistää boksin uudelleen
    func switchBootSlot(box: EnigmaBox, targetSlot: Int) async -> (success: Bool, message: String) {
        let cmd = "if [ -f '/boot/STARTUP_\(targetSlot)' ]; then cp -f '/boot/STARTUP_\(targetSlot)' /boot/STARTUP && sync; sleep 1; reboot; echo 'SUCCESS'; else echo 'NO_STARTUP'; fi"
        let (ok, output) = await executeTelnetCommand(
            ip: box.ip,
            command: cmd,
            timeout: 6.0,
            username: box.username,
            password: box.password
        )
        if ok && output.contains("SUCCESS") {
            return (true, "Boksi käynnistetään slotiin \(targetSlot)...")
        } else if output.contains("NO_STARTUP") {
            return (false, "Slotin \(targetSlot) käynnistystiedostoa /boot/STARTUP_\(targetSlot) ei löytynyt.")
        }
        return (ok, output)
    }
    
    /// Lataa varmuuskopion boksista Macille (FTP)
    func downloadImageBackup(
        box: EnigmaBox,
        remotePath: String,
        localDestination: URL,
        isFolder: Bool = false,
        onProgress: @escaping (Double) -> Void
    ) async -> (success: Bool, error: String?) {
        if isFolder {
            return await downloadImageBackupFolder(box: box, remotePath: remotePath, localDestination: localDestination, onProgress: onProgress)
        }
        await ensureFTPAllowed(box: box)
        let cred = await ftpCredentials(ip: box.ip, username: box.username, password: box.password)
        let cleanPath = remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let ftpURL = "ftp://\(cred)@\(box.ip)//\(cleanPath)"
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        proc.arguments = [
            "-s",
            "--connect-timeout", "10",
            ftpURL,
            "-o", localDestination.path
        ]
        
        do {
            try proc.run()
            
            // Seurataan tiedostokoon kasvua taustalla
            var isRunning = true
            let monitorTask = Task {
                while isRunning {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: localDestination.path),
                       let currentSize = attrs[.size] as? Int64 {
                        // Ilmoitetaan suhteellista edistymistä jos tiedossa
                        onProgress(min(Double(currentSize) / 150_000_000.0, 0.95))
                    }
                }
            }
            
            proc.waitUntilExit()
            isRunning = false
            monitorTask.cancel()
            
            if proc.terminationStatus == 0 {
                onProgress(1.0)
                return (true, nil)
            } else {
                return (false, "Lataus epäonnistui (curl-koodi \(proc.terminationStatus))")
            }
        } catch {
            return (false, "Latauksen käynnistys epäonnistui: \(error.localizedDescription)")
        }
    }
    
    /// Lataa purettuna tallennetun varmuuskopiokansion tiedosto kerrallaan (FTP) ja pakkaa sen
    /// Macilla flashattavaksi zipiksi (sama rakenne kuin kansiossa, esim. vuplus/duo4kse/...).
    private func downloadImageBackupFolder(
        box: EnigmaBox,
        remotePath: String,
        localDestination: URL,
        onProgress: @escaping (Double) -> Void
    ) async -> (success: Bool, error: String?) {
        let (listed, listing) = await executeTelnetCommand(
            ip: box.ip,
            command: "cd '\(remotePath)' && find . -type f ! -name '.DS_Store' ! -name '._*' | while read F; do echo \"F|$(ls -ln \"$F\" | awk '{print $5}')|$F\"; done",
            timeout: 10.0,
            username: box.username,
            password: box.password
        )
        let files: [(path: String, size: Int64)] = listing.components(separatedBy: .newlines).compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2).map(String.init)
            guard parts.count == 3, parts[0] == "F", let size = Int64(parts[1]) else { return nil }
            return (String(parts[2].dropFirst(parts[2].hasPrefix("./") ? 2 : 0)), size)
        }
        guard listed, !files.isEmpty else {
            return (false, "Varmuuskopiokansion tiedostoja ei saatu luettua boksista.")
        }

        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("enigmasuite_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }

        await ensureFTPAllowed(box: box)
        let cred = await ftpCredentials(ip: box.ip, username: box.username, password: box.password)
        let totalBytes = max(files.reduce(0) { $0 + $1.size }, 1)
        var doneBytes: Int64 = 0

        for file in files {
            let local = staging.appendingPathComponent(file.path)
            try? FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
            let remote = (remotePath + "/" + file.path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let encoded = remote.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remote
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            proc.arguments = ["-s", "--connect-timeout", "10", "ftp://\(cred)@\(box.ip)//\(encoded)", "-o", local.path]
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                return (false, "Latauksen käynnistys epäonnistui: \(error.localizedDescription)")
            }
            guard proc.terminationStatus == 0 else {
                return (false, "Tiedoston \(file.path) lataus epäonnistui (curl-koodi \(proc.terminationStatus))")
            }
            doneBytes += file.size
            onProgress(min(Double(doneBytes) / Double(totalBytes), 1.0) * 0.9)
        }

        // Pakataan Macilla: zip-paketin juuressa on kansion sisältö (esim. vuplus/duo4kse/)
        try? FileManager.default.removeItem(at: localDestination)
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = staging
        zip.arguments = ["-r", "-q", localDestination.path, "."]
        do {
            try zip.run()
            zip.waitUntilExit()
        } catch {
            return (false, "Zip-paketin luonti epäonnistui: \(error.localizedDescription)")
        }
        guard zip.terminationStatus == 0 else {
            return (false, "Zip-paketin luonti epäonnistui (koodi \(zip.terminationStatus))")
        }
        onProgress(1.0)
        return (true, nil)
    }

    /// Luo uuden täyden varmuuskopion boksille
    func createFullImageBackup(
        box: EnigmaBox,
        destinationStorage: BoxStorageDevice,
        onProgress: @escaping (String, Double) -> Void
    ) async -> (success: Bool, message: String) {
        let destDir = "\(destinationStorage.mountPoint)/imagebackups"
        
        // 1. Kirjoitetaan ja valmistellaan suoritusskripti boksille
        let setupCmd = """
        cat << 'EOF' > /tmp/enigmasuite_backup.sh
#!/bin/sh
DEST_DIR="$1"
LOG_FILE="/tmp/enigmasuite_backup.log"
STATUS_FILE="/tmp/enigmasuite_backup.status"

echo "STATUS:INIT:0.05:Alustetaan varmuuskopiointia..." > "$STATUS_FILE"

BRAND="vuplus"
if [ -f /proc/stb/info/vumodel ]; then
    MODEL=$(cat /proc/stb/info/vumodel | tr -d '\\r\\n')
    BRAND="vuplus"
elif [ -f /proc/stb/info/model ]; then
    MODEL=$(cat /proc/stb/info/model | tr -d '\\r\\n')
else
    MODEL="unknown"
fi

SUBFOLDER="$MODEL"
if [ "$BRAND" = "vuplus" ]; then
    SUBFOLDER=$(echo "$MODEL" | sed 's/^vu//')
fi

DISTRO="enigma2"
VERSION="backup"
if [ -f /etc/image-version ]; then
    DISTRO=$(grep -i '^distro=' /etc/image-version | cut -d= -f2 | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    [ -z "$DISTRO" ] && DISTRO=$(grep -i '^Creator' /etc/image-version | cut -d= -f2 | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    VERSION=$(grep -i '^Version=' /etc/image-version | cut -d= -f2 | tr -d ' ')
    BUILD=$(grep -i '^Build=' /etc/image-version | cut -d= -f2 | tr -d ' ')
    [ -n "$BUILD" ] && VERSION="${VERSION}.${BUILD}"
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="${DISTRO}-${VERSION}-${MODEL}-backup-${TIMESTAMP}"
# Työkansio kohdelevylle: /tmp on monissa bokseissa pieni RAM-levy
WORK_DIR="${DEST_DIR}/.work_${TIMESTAMP}"
IMAGE_DIR="${WORK_DIR}/${BRAND}/${SUBFOLDER}"

echo "STATUS:INFO:0.10:Malli: ${MODEL} (${BRAND}), Image: ${DISTRO} ${VERSION}" > "$STATUS_FILE"

mkdir -p "$IMAGE_DIR"
mkdir -p "$DEST_DIR"

echo "STATUS:KERNEL:0.20:Kopioidaan kernel-osio..." > "$STATUS_FILE"
CMDLINE=$(cat /proc/cmdline 2>/dev/null)
KERNEL_DEV=""
case "$CMDLINE" in
    *rootsubdir=linuxrootfs[1-9]*)
        SLOT_NUM=$(echo "$CMDLINE" | sed -n 's/.*rootsubdir=linuxrootfs\\([1-9]\\).*/\\1/p')
        [ -e "/dev/disk/by-partlabel/linuxkernel${SLOT_NUM}" ] && KERNEL_DEV="/dev/disk/by-partlabel/linuxkernel${SLOT_NUM}"
        ;;
esac

if [ -z "$KERNEL_DEV" ] && [ -e "/dev/disk/by-partlabel/linuxkernel1" ]; then
    KERNEL_DEV="/dev/disk/by-partlabel/linuxkernel1"
elif [ -z "$KERNEL_DEV" ] && [ -e "/dev/kernel" ]; then
    KERNEL_DEV="/dev/kernel"
elif [ -z "$KERNEL_DEV" ] && [ -e "/dev/disk/by-partlabel/kernel" ]; then
    KERNEL_DEV="/dev/disk/by-partlabel/kernel"
fi

# Vu+ 4K -mallien initrd- ja splash-osiot (kuten boksin oma image-varmuuskopio)
[ -e "/dev/disk/by-partlabel/initrd" ] && dd if="/dev/disk/by-partlabel/initrd" of="${IMAGE_DIR}/initrd_auto.bin" bs=1M 2>> "$LOG_FILE"
[ -e "/dev/disk/by-partlabel/splash" ] && dd if="/dev/disk/by-partlabel/splash" of="${IMAGE_DIR}/splash_auto.bin" bs=1M 2>> "$LOG_FILE"

if [ -n "$KERNEL_DEV" ]; then
    dd if="$KERNEL_DEV" of="${IMAGE_DIR}/kernel_auto.bin" bs=1M 2>> "$LOG_FILE"
elif [ -f /boot/vmlinux.bin ]; then
    cp /boot/vmlinux.bin "${IMAGE_DIR}/vmlinux.bin"
elif [ -f /boot/zImage ]; then
    cp /boot/zImage "${IMAGE_DIR}/kernel_auto.bin"
fi

touch "${IMAGE_DIR}/reboot.update"
[ -f /usr/bin/mkupdate ] && cp /usr/bin/mkupdate "${IMAGE_DIR}/" || true

echo "STATUS:ROOTFS:0.40:Pakataan tiedostojärjestelmä (rootfs.tar.bz2)..." > "$STATUS_FILE"
BIND_DIR="/tmp/backup_bind_${TIMESTAMP}"
mkdir -p "$BIND_DIR"
mount --bind / "$BIND_DIR"

tar -jcf "${IMAGE_DIR}/rootfs.tar.bz2" -C "$BIND_DIR" \\
    --exclude=./media \\
    --exclude=./mnt \\
    --exclude=./tmp \\
    --exclude=./proc \\
    --exclude=./sys \\
    --exclude=./dev \\
    --exclude=./run \\
    --exclude=./var/volatile \\
    --exclude=./var/nmbd \\
    --exclude=./.resizerootfs \\
    --exclude=./linuxrootfs* \\
    --exclude=./.resize-rootfs \\
    --exclude=./.resize-linuxrootfs \\
    --exclude=./.resize-userdata \\
    --exclude=./var/lib/samba/private/msg.sock \\
    . 2>> "$LOG_FILE"

umount -l "$BIND_DIR" 2>/dev/null || true
rmdir "$BIND_DIR" 2>/dev/null || true

echo "STATUS:ZIP:0.85:Luodaan zip-palautuspaketti..." > "$STATUS_FILE"
ZIP_FILE="${DEST_DIR}/${BACKUP_NAME}.zip"
cd "$WORK_DIR"
# Kaikissa imageissa ei ole zip-komentoa (esim. VTi): varalla Pythonin zipfile
if command -v zip >/dev/null 2>&1; then
    zip -r "$ZIP_FILE" "$BRAND" >> "$LOG_FILE" 2>&1 || rm -f "$ZIP_FILE"
elif PY=$(command -v python3 || command -v python); then
    "$PY" -m zipfile -c "$ZIP_FILE" "$BRAND" >> "$LOG_FILE" 2>&1 || rm -f "$ZIP_FILE"
fi
cd /

if [ -f "$ZIP_FILE" ]; then
    rm -rf "$WORK_DIR"
    ZIP_SIZE=$(ls -lh "$ZIP_FILE" | awk '{print $5}')
    echo "STATUS:DONE:1.0:Varmuuskopio valmis: ${BACKUP_NAME}.zip (${ZIP_SIZE})" > "$STATUS_FILE"
elif mv "$WORK_DIR" "${DEST_DIR}/${BACKUP_NAME}"; then
    # Ilman zip-työkalua varmuuskopio jää purettuna kansioksi, joka kelpaa myös Flashiin
    echo "STATUS:DONE:1.0:Varmuuskopio valmis kansiona: ${BACKUP_NAME}" > "$STATUS_FILE"
else
    rm -rf "$WORK_DIR"
    echo "STATUS:ERROR:0.0:Varmuuskopion pakkaaminen epäonnistui." > "$STATUS_FILE"
fi
EOF
chmod +x /tmp/enigmasuite_backup.sh
rm -f /tmp/enigmasuite_backup.status /tmp/enigmasuite_backup.log
"""
        
        let (setupOk, _) = await executeTelnetCommand(
            ip: box.ip,
            command: setupCmd,
            timeout: 5.0,
            username: box.username,
            password: box.password
        )
        guard setupOk else {
            return (false, "Varmuuskopiointiskriptin luonti boksille epäonnistui.")
        }
        
        // 2. Käynnistetään tausta-ajona
        let startCmd = "nohup /bin/sh /tmp/enigmasuite_backup.sh '\(destDir)' > /tmp/enigmasuite_backup.log 2>&1 &"
        _ = await executeTelnetCommand(
            ip: box.ip,
            command: startCmd,
            timeout: 4.0,
            username: box.username,
            password: box.password
        )
        
        // 3. Seurataan tilatiedostoa silmukassa (max 20 min: bzip2-pakkaus on hidas boksin prosessorilla)
        let startTime = Date()
        var currentProgress: Double = 0.05
        
        while Date().timeIntervalSince(startTime) < 1200 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            let (_, statusContent) = await executeTelnetCommand(
                ip: box.ip,
                command: "cat /tmp/enigmasuite_backup.status 2>/dev/null",
                timeout: 4.0,
                username: box.username,
                password: box.password
            )
            
            // Format: STATUS:STAGE:PROGRESS:MESSAGE
            if let statusLine = statusContent.components(separatedBy: .newlines).first(where: { $0.hasPrefix("STATUS:") }) {
                let parts = statusLine.components(separatedBy: ":")
                if parts.count >= 4 {
                    let stage = parts[1]
                    let progVal = Double(parts[2]) ?? currentProgress
                    let msg = parts[3...].joined(separator: ":")
                    
                    currentProgress = progVal
                    onProgress(msg, currentProgress)
                    
                    if stage == "DONE" {
                        _ = await executeTelnetCommand(ip: box.ip, command: "rm -f /tmp/enigmasuite_backup.sh /tmp/enigmasuite_backup.status", timeout: 3.0, username: box.username, password: box.password)
                        return (true, msg)
                    } else if stage == "ERROR" {
                        _ = await executeTelnetCommand(ip: box.ip, command: "rm -f /tmp/enigmasuite_backup.sh", timeout: 3.0, username: box.username, password: box.password)
                        return (false, msg)
                    }
                }
            }
        }
        
        return (false, "Aikakatkaisu: varmuuskopiointi kesti yli 20 minuuttia.")
    }
    
    /// Asentaa imagen (Flash) valittuun slotiin
    func flashImage(
        box: EnigmaBox,
        zipSource: FlashZipSource,
        targetSlot: Int,
        storage: BoxStorageDevice,
        rebootAfter: Bool,
        onProgress: @escaping (String, Double) -> Void
    ) async -> (success: Bool, message: String) {
        // Flash kirjoittaa imagen ofgwritella; tarkistetaan ennen kuin siirretään satoja megatavuja turhaan
        let (_, toolCheck) = await executeTelnetCommand(
            ip: box.ip,
            command: "[ -x /usr/bin/ofgwrite ] && echo OFGWRITE_OK || echo OFGWRITE_MISSING",
            timeout: 6.0,
            username: box.username,
            password: box.password
        )
        if !toolCheck.components(separatedBy: .newlines).contains(where: { $0.trimmingCharacters(in: .whitespaces) == "OFGWRITE_OK" }) {
            return (false, "Boksista puuttuu ofgwrite-ohjelma, jota imagen asennus tarvitsee. Asenna se boksin pakettienhallinnasta (opkg install ofgwrite) tai asenna image boksin omalla flash-toiminnolla.")
        }

        let workDir = "\(storage.mountPoint)/imagebackups/flash_tmp"
        _ = await executeTelnetCommand(ip: box.ip, command: "mkdir -p '\(workDir)'", timeout: 4.0, username: box.username, password: box.password)
        
        let remoteZipPath: String
        switch zipSource {
        case .boxBackup(let path, _):
            remoteZipPath = path
        case .localFile(let url):
            onProgress("Siirretään image-tiedostoa boksille (FTP)...", 0.1)
            await ensureFTPAllowed(box: box)
            let cred = await ftpCredentials(ip: box.ip, username: box.username, password: box.password)
            let targetUploadPath = "\(workDir)/uploaded_image.zip"
            let cleanPath = targetUploadPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let ftpURL = "ftp://\(cred)@\(box.ip)//\(cleanPath)"
            
            let uploadProc = Process()
            uploadProc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            uploadProc.arguments = [
                "-sS",
                "--connect-timeout", "10",
                "-T", url.path,
                ftpURL
            ]
            
            do {
                try uploadProc.run()
                uploadProc.waitUntilExit()
                guard uploadProc.terminationStatus == 0 else {
                    return (false, "Imagen siirto boksille epäonnistui (FTP-koodi \(uploadProc.terminationStatus))")
                }
                remoteZipPath = targetUploadPath
                onProgress("Image siirretty onnistuneesti boksille.", 0.4)
            } catch {
                return (false, "Imagen siirto epäonnistui: \(error.localizedDescription)")
            }
        }
        
        // Luodaan asennusskripti
        let flashScript = """
        cat << 'EOF' > /tmp/enigmasuite_flash.sh
#!/bin/sh
ZIP_PATH="$1"
TARGET_SLOT="$2"
WORK_DIR="$3"
REBOOT_AFTER="$4"
LOG_FILE="/tmp/enigmasuite_flash.log"
STATUS_FILE="/tmp/enigmasuite_flash.status"

rm -rf "${WORK_DIR}/extracted"
if [ -d "$ZIP_PATH" ]; then
    # Purettuna tallennettu varmuuskopio: käytetään kansiota sellaisenaan
    SRC_DIR="$ZIP_PATH"
else
    echo "STATUS:UNPACK:0.45:Puretaan image-arkistoa..." > "$STATUS_FILE"
    mkdir -p "${WORK_DIR}/extracted"
    unzip -o "$ZIP_PATH" -d "${WORK_DIR}/extracted" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        echo "STATUS:ERROR:0.0:Image-tiedoston purkaminen epäonnistui." > "$STATUS_FILE"
        exit 1
    fi
    SRC_DIR="${WORK_DIR}/extracted"
fi

IMAGE_DIR=$(find "$SRC_DIR" -type f \\( -name "kernel_auto.bin" -o -name "vmlinux.bin" -o -name "rootfs.*" \\) -exec dirname {} \\; | head -n 1)

if [ -z "$IMAGE_DIR" ] || [ ! -d "$IMAGE_DIR" ]; then
    echo "STATUS:ERROR:0.0:Arkistosta ei löytynyt asennettavia tiedostoja (kernel / rootfs)." > "$STATUS_FILE"
    exit 1
fi

echo "STATUS:FLASH:0.65:Kirjoitetaan image muistiin (ofgwrite)..." > "$STATUS_FILE"

if [ "$TARGET_SLOT" != "0" ] && [ -n "$TARGET_SLOT" ]; then
    /usr/bin/ofgwrite -r -k -m"${TARGET_SLOT}" "$IMAGE_DIR" >> "$LOG_FILE" 2>&1
else
    /usr/bin/ofgwrite -r -k "$IMAGE_DIR" >> "$LOG_FILE" 2>&1
fi

RETVAL=$?
if [ $RETVAL -ne 0 ]; then
    echo "STATUS:ERROR:0.0:ofgwrite virhe (koodi ${RETVAL}). Katso loki." > "$STATUS_FILE"
    exit 1
fi

rm -rf "${WORK_DIR}/extracted"

if [ "$REBOOT_AFTER" = "true" ]; then
    [ -f "/boot/STARTUP_${TARGET_SLOT}" ] && cp -f "/boot/STARTUP_${TARGET_SLOT}" /boot/STARTUP
    echo "STATUS:DONE:1.0:Asennus onnistui! Boksi käynnistyy uudelleen muutaman sekunnin kuluttua..." > "$STATUS_FILE"
    sync
    sleep 4
    reboot
else
    echo "STATUS:DONE:1.0:Image asennettu onnistuneesti slotiin ${TARGET_SLOT}!" > "$STATUS_FILE"
fi
EOF
chmod +x /tmp/enigmasuite_flash.sh
rm -f /tmp/enigmasuite_flash.status /tmp/enigmasuite_flash.log
"""
        
        let (scriptOk, _) = await executeTelnetCommand(
            ip: box.ip,
            command: flashScript,
            timeout: 5.0,
            username: box.username,
            password: box.password
        )
        guard scriptOk else {
            return (false, "Asennusskriptin luonti boksille epäonnistui.")
        }
        
        // Käynnistetään asennus
        let startCmd = "nohup /bin/sh /tmp/enigmasuite_flash.sh '\(remoteZipPath)' '\(targetSlot)' '\(workDir)' '\(rebootAfter ? "true" : "false")' > /tmp/enigmasuite_flash.log 2>&1 &"
        _ = await executeTelnetCommand(
            ip: box.ip,
            command: startCmd,
            timeout: 4.0,
            username: box.username,
            password: box.password
        )
        
        // Seurataan edistymistä
        let startTime = Date()
        var currentProgress: Double = 0.45
        
        while Date().timeIntervalSince(startTime) < 300 {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            
            let (_, statusContent) = await executeTelnetCommand(
                ip: box.ip,
                command: "cat /tmp/enigmasuite_flash.status 2>/dev/null",
                timeout: 4.0,
                username: box.username,
                password: box.password
            )
            
            if let statusLine = statusContent.components(separatedBy: .newlines).first(where: { $0.hasPrefix("STATUS:") }) {
                let parts = statusLine.components(separatedBy: ":")
                if parts.count >= 4 {
                    let stage = parts[1]
                    let progVal = Double(parts[2]) ?? currentProgress
                    let msg = parts[3...].joined(separator: ":")
                    
                    currentProgress = progVal
                    onProgress(msg, currentProgress)
                    
                    if stage == "DONE" {
                        _ = await executeTelnetCommand(ip: box.ip, command: "rm -f /tmp/enigmasuite_flash.sh /tmp/enigmasuite_flash.status", timeout: 3.0, username: box.username, password: box.password)
                        return (true, msg)
                    } else if stage == "ERROR" {
                        _ = await executeTelnetCommand(ip: box.ip, command: "rm -f /tmp/enigmasuite_flash.sh", timeout: 3.0, username: box.username, password: box.password)
                        return (false, msg)
                    }
                }
            }
        }
        
        return (false, "Aikakatkaisu: asennus kesti yli 5 minuuttia.")
    }
}

