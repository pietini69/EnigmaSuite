import Foundation
import SwiftUI

// MARK: - Navigaatio-välilehdet
enum NavigationTab: String, CaseIterable, Identifiable {
    case remote = "Kaukosäädin"
    case timersAndMovies = "Ajastukset & Tallenteet"
    case channels = "Kanavat & Suosikit"
    case settingsSync = "Asetusten vertailu"
    case bootlogo = "Käynnistyskuvat (MVI)"
    case imageManager = "Image & Varmuuskopiot"
    case boxManager = "Laitteiden hallinta"
    case support = "Tue kehitystä"
    
    var id: String { rawValue }
    
    var localizationKey: String {
        switch self {
        case .remote: return "Nav_Remote"
        case .timersAndMovies: return "Nav_Timers"
        case .channels: return "Nav_Channels"
        case .settingsSync: return "Nav_SettingsSync"
        case .bootlogo: return "Nav_Bootlogo"
        case .imageManager: return "Nav_ImageManager"
        case .boxManager: return "Nav_BoxManager"
        case .support: return "Nav_Support"
        }
    }
    
    var title: String {
        L10n(localizationKey)
    }
    
    func title(using l10n: LocalizationManager) -> String {
        l10n.t(localizationKey)
    }
    
    var icon: String {
        switch self {
        case .remote: return "tv"
        case .timersAndMovies: return "clock.badge.checkmark"
        case .channels: return "list.star"
        case .settingsSync: return "arrow.triangle.2.circlepath"
        case .bootlogo: return "photo.on.rectangle"
        case .imageManager: return "archivebox.fill"
        case .boxManager: return "server.rack"
        case .support: return "cup.and.saucer.fill"
        }
    }
}

// MARK: - Enigma2 Boksi
struct EnigmaBox: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var ip: String
    var port: Int = 80
    var username: String = "root"
    var password: String = ""
    var isOnline: Bool = false
    var model: String?
    var distro: String?
    var tuners: [TunerInfo] = []
    
    var hasAuth: Bool {
        !password.isEmpty
    }
    
    var baseURL: String {
        if port == 80 {
            return "http://\(ip)"
        }
        return "http://\(ip):\(port)"
    }
    
    func streamURL(for sRef: String) -> URL? {
        // Enigma2 stream-portti on oletuksena 8001
        let authPrefix: String
        if hasAuth {
            let u = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
            let p = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
            authPrefix = "\(u):\(p)@"
        } else {
            authPrefix = ""
        }
        return URL(string: "http://\(authPrefix)\(ip):8001/\(sRef)")
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, ip, port, username, password, isOnline, model, distro, tuners
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        ip: String,
        port: Int = 80,
        username: String = "root",
        password: String = "",
        isOnline: Bool = false,
        model: String? = nil,
        distro: String? = nil,
        tuners: [TunerInfo] = []
    ) {
        self.id = id
        self.name = name
        self.ip = ip
        self.port = port
        self.username = username
        self.password = password
        self.isOnline = isOnline
        self.model = model
        self.distro = distro
        self.tuners = tuners
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.ip = try container.decode(String.self, forKey: .ip)
        self.port = (try? container.decode(Int.self, forKey: .port)) ?? 80
        self.username = (try? container.decode(String.self, forKey: .username)) ?? "root"
        self.password = (try? container.decode(String.self, forKey: .password)) ?? ""
        self.isOnline = (try? container.decode(Bool.self, forKey: .isOnline)) ?? false
        self.model = try? container.decodeIfPresent(String.self, forKey: .model)
        self.distro = try? container.decodeIfPresent(String.self, forKey: .distro)
        self.tuners = (try? container.decode([TunerInfo].self, forKey: .tuners)) ?? []
    }
    
    static func == (lhs: EnigmaBox, rhs: EnigmaBox) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Viritinmallit
enum TunerFamily: String, Codable, Hashable {
    case cable = "DVB-C"
    case satellite = "DVB-S2"
    case terrestrial = "DVB-T2"
    case unknown = "Tuntematon"
    
    var icon: String {
        switch self {
        case .cable: return "cable.connector"
        case .satellite: return "antenna.radiowaves.left.and.right"
        case .terrestrial: return "wave.3.up"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct TunerInfo: Identifiable, Codable, Hashable {
    var id: String { "\(index)_\(name)" }
    let index: Int
    let name: String
    let type: String
    let family: TunerFamily
    
    var shortLetter: String {
        if index < 26 {
            return String(UnicodeScalar(65 + index)!)
        }
        return "\(index)"
    }
}

enum TunerCompatibility: Hashable {
    case notTuner
    case compatible
    case incompatibleType(sourceType: String, targetType: String)
    case missingInTarget(sourceType: String)
    case unknown
    
    var badgeText: String {
        switch self {
        case .notTuner: return ""
        case .compatible: return L10n("Sync_TunerCompatible")
        case .incompatibleType: return L10n("Sync_TunerIncompatible")
        case .missingInTarget: return L10n("Sync_TunerMissing")
        case .unknown: return L10n("Sync_TunerUnknown")
        }
    }
    
    var badgeColor: Color {
        switch self {
        case .notTuner: return .clear
        case .compatible: return .green
        case .incompatibleType: return .orange
        case .missingInTarget: return .red
        case .unknown: return .gray
        }
    }
}

// MARK: - Asetusmallit
enum SettingsCategory: String, CaseIterable, Identifiable {
    case all = "Kaikki"
    case tuners = "Virittimet (NIM)"
    case skinAndDisplay = "Käyttöliittymä & OSD"
    case recording = "Tallennus & Toisto"
    case language = "Kielet & Tekstitys"
    case epg = "Ohjelmaopas (EPG)"
    case timezone = "Aika & Alue"
    case plugins = "Liitännäiset (Plugins)"
    case usage = "Toiminnot & Valikot"
    case misc = "Muut asetukset"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .all: return L10n("Sync_CatAll")
        case .tuners: return L10n("Sync_CatTuners")
        case .skinAndDisplay: return L10n("Sync_CatSkin")
        case .recording: return L10n("Sync_CatRec")
        case .language: return L10n("Sync_CatLang")
        case .epg: return L10n("Sync_CatEpg")
        case .timezone: return L10n("Sync_CatTime")
        case .plugins: return L10n("Sync_CatPlugins")
        case .usage: return L10n("Sync_CatUsage")
        case .misc: return L10n("Sync_CatMisc")
        }
    }
    
    var icon: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .tuners: return "antenna.radiowaves.left.and.right"
        case .skinAndDisplay: return "paintpalette"
        case .recording: return "record.circle"
        case .language: return "character.bubble"
        case .epg: return "list.bullet.rectangle"
        case .timezone: return "globe.europe.africa"
        case .plugins: return "puzzlepiece.extension"
        case .usage: return "slider.horizontal.3"
        case .misc: return "gearshape.2"
        }
    }
}

struct SettingEntry: Identifiable, Hashable {
    var id: String { key }
    let key: String
    var sourceValue: String?
    var targetValue: String?
    let category: SettingsCategory
    var tunerCompatibility: TunerCompatibility = .notTuner
    var isSelected: Bool = false
    
    var isDifferent: Bool {
        return sourceValue != targetValue
    }
    
    var isOnlyInSource: Bool {
        return sourceValue != nil && targetValue == nil
    }
    
    var isOnlyInTarget: Bool {
        return sourceValue == nil && targetValue != nil
    }
}

struct BackupRecord: Identifiable, Hashable {
    var id: URL { fileURL }
    let boxName: String
    let boxIP: String
    let date: Date
    let fileURL: URL
    let entryCount: Int
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Kanavat ja suosikit
struct Bouquet: Identifiable, Codable, Hashable {
    let id: String // Service Reference
    var name: String
    var isRadio: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case id = "servicereference"
        case name = "servicename"
    }
}

struct Channel: Identifiable, Codable, Hashable {
    let id: String // Service Reference
    var name: String
    var currentTitle: String = ""
    var currentDesc: String = ""
    var duration: Int = 0
    var progress: Double = 0.0
    
    enum CodingKeys: String, CodingKey {
        case id = "servicereference"
        case name = "servicename"
    }
}

struct ServicesResponse: Codable {
    let services: [Bouquet]
}

// MARK: - Aikamuunnokset (Safe Unix Timestamps)
enum EnigmaTimeUtil {
    static let epoch = Date(timeIntervalSince1970: 0)
    
    static func safeUnixToDate(_ unixSeconds: Double) -> Date {
        guard unixSeconds > 0 && unixSeconds < 253402300799 else {
            return epoch
        }
        return Date(timeIntervalSince1970: unixSeconds)
    }
}

// MARK: - EPG, Ajastukset ja Tallenteet
struct EPGEvent: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String
    let description: String
    let longDescription: String
    let beginTimestamp: Double
    let duration: Int
    var sRef: String
    
    var beginDate: Date { EnigmaTimeUtil.safeUnixToDate(beginTimestamp) }
    var endDate: Date {
        let dur = TimeInterval(duration)
        if dur > 0 && dur < 86400 * 30 {
            return beginDate.addingTimeInterval(dur)
        }
        return beginDate
    }
    
    init(id: Int, title: String, description: String, longDescription: String, beginTimestamp: Double, duration: Int, sRef: String) {
        self.id = id; self.title = title; self.description = description; self.longDescription = longDescription
        self.beginTimestamp = beginTimestamp; self.duration = duration; self.sRef = sRef
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(Int.self, forKey: .id)) ?? (try? container.decode(Int.self, forKey: .eventid)) ?? 0
        let rawTitle = try container.decodeIfPresent(String.self, forKey: .title) ?? "Ei otsikkoa"
        self.title = rawTitle.unescapingHTMLEntities()
        let rawDesc = (try? container.decodeIfPresent(String.self, forKey: .description)) ?? (try? container.decodeIfPresent(String.self, forKey: .shortdesc)) ?? ""
        self.description = rawDesc.unescapingHTMLEntities()
        let rawLongDesc = (try? container.decodeIfPresent(String.self, forKey: .longDescription)) ?? (try? container.decodeIfPresent(String.self, forKey: .longdesc)) ?? ""
        self.longDescription = rawLongDesc.unescapingHTMLEntities()
        self.beginTimestamp = try container.decodeIfPresent(Double.self, forKey: .beginTimestamp) ?? 0.0
        self.duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        self.sRef = try container.decodeIfPresent(String.self, forKey: .sRef) ?? ""
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "id"; case eventid = "eventid"; case title = "title"
        case description = "shortdescription"; case shortdesc = "shortdesc"
        case longDescription = "longdescription"; case longdesc = "longdesc"
        case beginTimestamp = "begin_timestamp"; case duration = "duration"; case sRef = "servicereference"
    }
}

struct EnigmaTimer: Identifiable, Hashable {
    let id = UUID()
    let eventId: Int
    let sRef: String
    let name: String
    let description: String
    let begin: Double
    let end: Double
    var state: Int = 0
    
    var startDate: Date { EnigmaTimeUtil.safeUnixToDate(begin) }
    var endDate: Date { EnigmaTimeUtil.safeUnixToDate(end) }
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: EnigmaTimer, rhs: EnigmaTimer) -> Bool { lhs.id == rhs.id }
}

struct AutoTimerRule: Identifiable, Hashable {
    let id = UUID()
    let ruleId: String
    let name: String
    let match: String
}

struct EnigmaMovie: Identifiable, Codable, Hashable {
    let id: String // serviceref
    let name: String
    let description: String
    let filename: String
    let filesize: Int64
    let time: Double
    
    var date: Date { EnigmaTimeUtil.safeUnixToDate(time) }
    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: filesize, countStyle: .file)
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "serviceref"
        case name = "eventname"
        case description = "description"
        case filename = "filename"
        case filesize = "filesize"
        case time = "recordingtime"
    }
}

struct MovieResponse: Codable {
    let movies: [EnigmaMovie]
}

// MARK: - Käynnistyskuvamallit (Bootlogo & MVI)
enum BootlogoType: String, CaseIterable, Identifiable {
    case bootlogo = "bootlogo.mvi"
    case bootlogoWait = "bootlogo_wait.mvi"
    case backdrop = "backdrop.mvi"
    case reboot = "reboot.mvi"
    case switchoff = "switchoff.mvi"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .bootlogo: return L10n("Bootlogo_TypeBootlogo")
        case .bootlogoWait: return L10n("Bootlogo_TypeWait")
        case .backdrop: return L10n("Bootlogo_TypeBackdrop")
        case .reboot: return L10n("Bootlogo_TypeReboot")
        case .switchoff: return L10n("Bootlogo_TypeSwitchoff")
        }
    }
    
    var description: String {
        switch self {
        case .bootlogo: return L10n("Bootlogo_DescBootlogo")
        case .bootlogoWait: return L10n("Bootlogo_DescWait")
        case .backdrop: return L10n("Bootlogo_DescBackdrop")
        case .reboot: return L10n("Bootlogo_DescReboot")
        case .switchoff: return L10n("Bootlogo_DescSwitchoff")
        }
    }
}

struct BootlogoFile: Identifiable, Hashable {
    var id: String { type.rawValue }
    let type: BootlogoType
    var previewImage: NSImage?
    var fileSize: Int?
    var isCustomLoaded: Bool = false
    
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: BootlogoFile, rhs: BootlogoFile) -> Bool { lhs.id == rhs.id }
}

enum EnigmaImageDistro: String, CaseIterable, Identifiable {
    case auto = "Automaattinen tunnistus"
    case vti = "Vu+ VTi Image"
    case openvix = "OpenViX"
    case openatv = "OpenATV"
    case blackhole = "Black Hole / OpenBlackHole"
    case openpli = "OpenPLi"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .auto: return L10n("Bootlogo_DistroAuto")
        case .vti: return "Vu+ VTi Image"
        case .openvix: return "OpenViX"
        case .openatv: return "OpenATV"
        case .blackhole: return "Black Hole / OpenBlackHole"
        case .openpli: return "OpenPLi"
        }
    }
    
    func resolvedBootlogoPath(for box: EnigmaBox?) -> String {
        switch self {
        case .openvix:
            return "/usr/share"
        case .vti, .blackhole:
            return "/usr/share/vuplus-bootlogo"
        case .openatv, .openpli:
            return "/usr/share/enigma2"
        case .auto:
            if let d = box?.distro?.lowercased() {
                if d.contains("vix") {
                    return "/usr/share"
                } else if d.contains("vti") || d.contains("blackhole") {
                    return "/usr/share/vuplus-bootlogo"
                } else if d.contains("atv") || d.contains("pli") {
                    return "/usr/share/enigma2"
                }
            }
            if let m = box?.model?.lowercased(), m.contains("vu") {
                return "/usr/share/vuplus-bootlogo"
            }
            return "/usr/share/vuplus-bootlogo"
        }
    }
    
    var bootlogoPath: String {
        resolvedBootlogoPath(for: nil)
    }
}

enum ResolutionOption: String, CaseIterable, Identifiable {
    case fhd1080 = "1080p Full HD (1920 × 1080)"
    case hd720 = "720p HD (1280 × 720)"
    case uhd4k = "4K Ultra HD (3840 × 2160)"
    
    var id: String { rawValue }
    
    var width: Int {
        switch self {
        case .fhd1080: return 1920
        case .hd720: return 1280
        case .uhd4k: return 3840
        }
    }
    
    var height: Int {
        switch self {
        case .fhd1080: return 1080
        case .hd720: return 720
        case .uhd4k: return 2160
        }
    }
}

enum ScalingMode: String, CaseIterable, Identifiable {
    case pad = "Mustat reunat (Pad/Letterbox)"
    case crop = "Rajaa kuva-alaan (Crop/Fill)"
    case stretch = "Venytä kuva-alaan (Stretch)"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .pad: return L10n("Bootlogo_ScalePad")
        case .crop: return L10n("Bootlogo_ScaleCrop")
        case .stretch: return L10n("Bootlogo_ScaleStretch")
        }
    }
    
    func ffmpegFilter(width: Int, height: Int) -> String {
        switch self {
        case .pad:
            return "scale=\(width):\(height):force_original_aspect_ratio=decrease,pad=\(width):\(height):(ow-iw)/2:(oh-ih)/2:black"
        case .crop:
            return "scale=\(width):\(height):force_original_aspect_ratio=increase,crop=\(width):\(height)"
        case .stretch:
            return "scale=\(width):\(height)"
        }
    }
    
    /// Tuottaa valitun sovitusmuodon mukaisen kuvan halutussa kohdekoossa (esim. 1920×1080)
    func renderScaledImage(_ image: NSImage, targetSize: CGSize) -> NSImage {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        
        let targetRect = NSRect(origin: .zero, size: targetSize)
        
        switch self {
        case .pad:
            NSColor.black.setFill()
            targetRect.fill()
            
            let imgRatio = image.size.width / max(image.size.height, 1)
            let targetRatio = targetSize.width / max(targetSize.height, 1)
            
            var drawRect = targetRect
            if imgRatio > targetRatio {
                let drawHeight = targetSize.width / imgRatio
                drawRect.origin.y = (targetSize.height - drawHeight) / 2
                drawRect.size.height = drawHeight
            } else {
                let drawWidth = targetSize.height * imgRatio
                drawRect.origin.x = (targetSize.width - drawWidth) / 2
                drawRect.size.width = drawWidth
            }
            image.draw(in: drawRect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1.0)
            
        case .crop:
            let imgRatio = image.size.width / max(image.size.height, 1)
            let targetRatio = targetSize.width / max(targetSize.height, 1)
            
            var drawRect = targetRect
            if imgRatio > targetRatio {
                let drawWidth = targetSize.height * imgRatio
                drawRect.origin.x = (targetSize.width - drawWidth) / 2
                drawRect.size.width = drawWidth
            } else {
                let drawHeight = targetSize.width / imgRatio
                drawRect.origin.y = (targetSize.height - drawHeight) / 2
                drawRect.size.height = drawHeight
            }
            
            let clipPath = NSBezierPath(rect: targetRect)
            clipPath.addClip()
            image.draw(in: drawRect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1.0)
            
        case .stretch:
            image.draw(in: targetRect, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1.0)
        }
        
        newImage.unlockFocus()
        return newImage
    }
}

// MARK: - HTML Entity Decoding Extension
extension String {
    public func unescapingHTMLEntities() -> String {
        return self
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Image & Varmuuskopiot Mallit

public struct BoxStorageDevice: Identifiable, Hashable {
    public var id: String { mountPoint }
    public let name: String
    public let mountPoint: String
    public let device: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let usedPercent: Int
    
    public init(name: String, mountPoint: String, device: String, totalBytes: Int64, availableBytes: Int64, usedPercent: Int) {
        self.name = name
        self.mountPoint = mountPoint
        self.device = device
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.usedPercent = usedPercent
    }
    
    public var formattedTotal: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    public var formattedAvailable: String {
        ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
    }
    
    public var isUsableForBackup: Bool {
        availableBytes > 400 * 1024 * 1024 // Vähintään ~400 MB vapaata
    }
    
    public var displayTitle: String {
        "\(name) (\(mountPoint)) - \(formattedAvailable) \(L10n("Common_Vapaana"))"
    }
}

public struct MultibootSlotInfo: Identifiable, Hashable {
    public var id: Int { slot }
    public let slot: Int
    public let installedImage: String?
    public let isCurrent: Bool
    
    public init(slot: Int, installedImage: String?, isCurrent: Bool) {
        self.slot = slot
        self.installedImage = installedImage
        self.isCurrent = isCurrent
    }
    
    public var displayName: String {
        let title: String
        if let img = installedImage, !img.isEmpty {
            title = "Slot \(slot): \(img)"
        } else {
            title = "Slot \(slot): (\(L10n("Common_Tyhja")))"
        }
        return isCurrent ? "\(title) [\(L10n("Common_Aktiivinen"))]" : title
    }
}

public struct ImageBackupItem: Identifiable, Hashable {
    public var id: String { remotePath }
    public let fileName: String
    public let remotePath: String
    public let sizeBytes: Int64
    public let creationDate: Date?
    public let mountPoint: String
    /// Purettu varmuuskopiokansio (esim. VTi:n oma image-varmuuskopio) zip-tiedoston sijaan
    public let isFolder: Bool
    
    public init(fileName: String, remotePath: String, sizeBytes: Int64, creationDate: Date?, mountPoint: String, isFolder: Bool = false) {
        self.fileName = fileName
        self.remotePath = remotePath
        self.sizeBytes = sizeBytes
        self.creationDate = creationDate
        self.mountPoint = mountPoint
        self.isFolder = isFolder
    }
    
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
    
    public var formattedDate: String {
        guard let date = creationDate else { return "-" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }
}

public enum FlashZipSource: Hashable {
    case boxBackup(path: String, fileName: String)
    case localFile(url: URL)
    
    public var displayName: String {
        switch self {
        case .boxBackup(_, let fileName):
            return fileName
        case .localFile(let url):
            return url.lastPathComponent
        }
    }
}

