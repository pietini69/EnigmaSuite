import SwiftUI
import Combine
import AppKit

@MainActor
final class EnigmaSuiteState: NSObject, ObservableObject {
    public private(set) static weak var shared: EnigmaSuiteState?
    
    // MARK: - Boksiluettelo ja aktiivinen laite
    @Published var boxes: [EnigmaBox] = []
    @Published var activeBox: EnigmaBox? {
        didSet {
            guard oldValue?.id != activeBox?.id else { return }
            if let box = activeBox {
                UserDefaults.standard.set(box.id.uuidString, forKey: "EnigmaSuiteActiveBoxId")
                Task {
                    await refreshBoxDetails(box)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: "EnigmaSuiteActiveBoxId")
            }
        }
    }
    
    // MARK: - Navigaatio
    @Published var selectedTab: NavigationTab? = .remote {
        didSet {
            if let tab = selectedTab {
                UserDefaults.standard.set(tab.rawValue, forKey: "EnigmaSuiteSelectedTab")
            }
        }
    }
    
    // MARK: - Asennuspaketin avaus
    @Published var pendingPackageURL: URL?
    
    // MARK: - Globaali tilailmoitus (Toast)
    @Published var toastMessage: String = ""
    @Published var toastIsError: Bool = false
    private var toastTask: Task<Void, Never>?
    
    // MARK: - Automaattinen tilanpäivitys
    private var heartbeatTimer: AnyCancellable?
    
    override init() {
        super.init()
        Self.shared = self
        if let savedTab = UserDefaults.standard.string(forKey: "EnigmaSuiteSelectedTab"),
           let tab = NavigationTab(rawValue: savedTab) {
            self.selectedTab = tab
        } else {
            self.selectedTab = .remote
        }
        loadBoxes()
        setupHeartbeat()
    }
    
    // MARK: - Toast-ilmoitukset
    func showToast(_ message: String, isError: Bool = false) {
        toastTask?.cancel()
        toastMessage = message
        toastIsError = isError
        
        let duration: Double = isError ? 5.0 : 3.0
        toastTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled && toastMessage == message {
                toastMessage = ""
            }
        }
    }
    
    // MARK: - Verkkohaku
    @Published var isDiscovering: Bool = false
    
    // MARK: - Boksien tallennus & lataus
    func loadBoxes() {
        if let data = UserDefaults.standard.data(forKey: "EnigmaSuiteBoxes"),
           let decoded = try? JSONDecoder().decode([EnigmaBox].self, from: data),
           !decoded.isEmpty {
            self.boxes = decoded
        } else {
            // Ei kovakoodattuja bokseja! Aloitetaan dynaamisesti.
            self.boxes = []
        }
        
        // Palautetaan viimeksi valittu boksi
        if let savedId = UserDefaults.standard.string(forKey: "EnigmaSuiteActiveBoxId"),
           let uuid = UUID(uuidString: savedId),
           let match = boxes.first(where: { $0.id == uuid }) {
            self.activeBox = match
        } else {
            self.activeBox = boxes.first
        }
        
        // Etsitään tai päivitetään boksit aina automaattisesti taustalla
        Task {
            if boxes.isEmpty {
                await autoDiscoverBoxes(showFeedback: false)
            } else {
                for box in boxes {
                    await refreshBoxDetails(box)
                }
                // Etsitään verkosta kaikki uudet ja DHCP:n kautta siirtyneet laitteet
                await autoDiscoverBoxes(showFeedback: false)
            }
        }
    }
    
    // MARK: - Automaattinen verkkohaku
    func autoDiscoverBoxes(showFeedback: Bool = true) async {
        isDiscovering = true
        if showFeedback {
            showToast(L10n("Toast_SearchingBoxes"))
        }
        
        let found = await EnigmaBoxService.shared.discoverNetworkBoxes()
        
        for discovered in found {
            // 1. Onko meillä jo boksi tällä samalla IP:llä?
            if let idx = boxes.firstIndex(where: { $0.ip == discovered.ip }) {
                boxes[idx].isOnline = true
                boxes[idx].model = discovered.model
                boxes[idx].distro = discovered.distro
                boxes[idx].tuners = discovered.tuners
                if boxes[idx].name.isEmpty || boxes[idx].name == boxes[idx].ip {
                    boxes[idx].name = discovered.name
                }
            } else if let matchIdx = boxes.firstIndex(where: {
                // 2. Onko meillä tallennettu boksi, joka on offline ja jonka nimi tai malli täsmää?
                guard !$0.isOnline else { return false }
                let dm = (discovered.model ?? "").lowercased()
                let existingModel = ($0.model ?? "").lowercased()
                let existingName = $0.name.lowercased()
                
                if !existingModel.isEmpty && existingModel == dm {
                    return true
                }
                if !dm.isEmpty && (existingName.contains(dm) || dm.contains(existingName)) {
                    return true
                }
                return false
            }) {
                print("[AutoDiscovery] Päivitetään boksin '\(boxes[matchIdx].name)' IP: \(boxes[matchIdx].ip) -> \(discovered.ip)")
                boxes[matchIdx].ip = discovered.ip
                boxes[matchIdx].isOnline = true
                boxes[matchIdx].model = discovered.model
                boxes[matchIdx].distro = discovered.distro
                boxes[matchIdx].tuners = discovered.tuners
                if boxes[matchIdx].name.isEmpty || boxes[matchIdx].name == boxes[matchIdx].ip {
                    boxes[matchIdx].name = discovered.name
                }
            } else {
                // 3. Uusi laite
                boxes.append(discovered)
            }
        }
        
        // 4. Siivotaan pois offline-duplikaatit, joille löytyi toimiva online-laite
        boxes.removeAll { offlineBox in
            guard !offlineBox.isOnline else { return false }
            return boxes.contains { onlineBox in
                onlineBox.isOnline && onlineBox.id != offlineBox.id &&
                ((onlineBox.model != nil && onlineBox.model == offlineBox.model) ||
                 (onlineBox.name.lowercased() == offlineBox.name.lowercased()))
            }
        }
        
        // 5. Päivitetään aktiivinen boksi: suositaan aina toimivaa online-laitetta
        if let cur = activeBox, let updated = boxes.first(where: { $0.id == cur.id }) {
            self.activeBox = updated
        }
        if self.activeBox == nil || !(self.activeBox?.isOnline ?? false) {
            if let firstOnline = boxes.first(where: { $0.isOnline }) {
                self.activeBox = firstOnline
            } else {
                self.activeBox = boxes.first
            }
        }
        
        saveBoxes()
        isDiscovering = false
        
        if showFeedback {
            if found.isEmpty {
                showToast(L10n("Toast_NoBoxesFound"), isError: true)
            } else {
                showToast(L10n("Toast_BoxesFound", found.count))
            }
        }
    }
    
    func saveBoxes() {
        if let data = try? JSONEncoder().encode(boxes) {
            UserDefaults.standard.set(data, forKey: "EnigmaSuiteBoxes")
        }
    }
    
    func addBox(name: String, ip: String, port: Int = 80, username: String = "root", password: String = "") {
        let cleanIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanIP.isEmpty else { return }
        
        let newBox = EnigmaBox(name: cleanName.isEmpty ? cleanIP : cleanName, ip: cleanIP, port: port, username: username, password: password)
        boxes.append(newBox)
        activeBox = newBox
        saveBoxes()
        showToast(L10n("Toast_BoxAdded", newBox.name))
        
        Task {
            await refreshBoxDetails(newBox)
        }
    }
    
    func updateBox(_ updatedBox: EnigmaBox) {
        if let idx = boxes.firstIndex(where: { $0.id == updatedBox.id }) {
            boxes[idx] = updatedBox
            if activeBox?.id == updatedBox.id {
                activeBox = updatedBox
            }
            saveBoxes()
            showToast(L10n("Toast_BoxUpdated"))
        }
    }
    
    func deleteBox(_ box: EnigmaBox) {
        boxes.removeAll { $0.id == box.id }
        if activeBox?.id == box.id {
            activeBox = boxes.first
        }
        saveBoxes()
        showToast(L10n("Toast_BoxDeleted", box.name))
    }
    
    // MARK: - Yhteyden ja laitetietojen päivitys
    func refreshBoxDetails(_ box: EnigmaBox) async {
        let info = await EnigmaBoxService.shared.queryBoxInfo(ip: box.ip, port: box.port, username: box.username, password: box.password)
        if let idx = boxes.firstIndex(where: { $0.id == box.id }) {
            boxes[idx].isOnline = info.isOnline
            if let m = info.model { boxes[idx].model = m }
            if let d = info.distro { boxes[idx].distro = d }
            if !info.tuners.isEmpty { boxes[idx].tuners = info.tuners }
            
            if activeBox?.id == box.id {
                activeBox = boxes[idx]
            }
        }
    }
    
    func refreshAllBoxes() async {
        await autoDiscoverBoxes(showFeedback: true)
    }
    
    // MARK: - VLC & Striimaus
    func openInVLC(sRef: String) {
        guard let box = activeBox, let url = box.streamURL(for: sRef) else {
            showToast(L10n("Toast_NoBoxForStreaming"), isError: true)
            return
        }
        
        // Kokeillaan avata VLC suoraan komentoriviltä tai oletusohjelmalla
        let vlcPaths = [
            "/Applications/VLC.app/Contents/MacOS/VLC",
            "/Applications/VLC.app",
            "/Applications/IINA.app"
        ]
        
        for path in vlcPaths {
            if FileManager.default.fileExists(atPath: path) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-a", path, url.absoluteString]
                if (try? p.run()) != nil {
                    showToast(L10n("Toast_OpeningPlayer", url.absoluteString))
                    return
                }
            }
        }
        
        // Varavaihtoehto: avaa järjestelmän oletusohjelmalla
        NSWorkspace.shared.open(url)
        showToast(L10n("Toast_StreamOpened", url.absoluteString))
    }
    
    // MARK: - Heartbeat
    private func setupHeartbeat() {
        // Päivitetään aktiivisen laitteen tila 15 sekunnin välein
        heartbeatTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let box = self.activeBox else { return }
                Task {
                    await self.refreshBoxDetails(box)
                }
            }
    }
}
