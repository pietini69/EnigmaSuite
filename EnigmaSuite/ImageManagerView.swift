import SwiftUI
import UniformTypeIdentifiers

struct ImageManagerView: View {
    @EnvironmentObject var state: EnigmaSuiteState
    @EnvironmentObject var l10n: LocalizationManager
    
    enum SubTab: Int, CaseIterable, Identifiable {
        case backups = 0
        case flash = 1
        case multiboot = 2
        
        var id: Int { rawValue }
        
        func title(using l10n: LocalizationManager) -> String {
            switch self {
            case .backups: return l10n.t("Image_TabBackups")
            case .flash: return l10n.t("Image_TabFlash")
            case .multiboot: return l10n.t("Image_TabMultiboot")
            }
        }
        
        var icon: String {
            switch self {
            case .backups: return "archivebox"
            case .flash: return "bolt.badge.automatic"
            case .multiboot: return "square.split.2x2"
            }
        }
    }
    
    @State private var selectedSubTab: SubTab = .backups
    
    // Boksin tiedot
    @State private var storageDevices: [BoxStorageDevice] = []
    @State private var selectedStorage: BoxStorageDevice?
    @State private var multibootSlots: [MultibootSlotInfo] = []
    @State private var currentSlot: Int?
    @State private var existingBackups: [ImageBackupItem] = []
    @State private var isLoadingInfo: Bool = false
    
    // Varmuuskopionti
    @State private var isBackingUp: Bool = false
    @State private var backupStatusText: String = ""
    @State private var backupProgress: Double = 0.0
    
    // Asennus (Flash)
    enum FlashSourceOption: String, CaseIterable, Identifiable {
        case box = "Boksissa oleva"
        case local = "Macin tiedosto"
        var id: String { rawValue }
    }
    @State private var flashSourceOption: FlashSourceOption = .box
    @State private var selectedBoxBackupForFlash: ImageBackupItem?
    @State private var selectedLocalZipURL: URL?
    @State private var selectedTargetSlot: Int = 1
    @State private var rebootAfterFlash: Bool = true
    @State private var isFlashing: Bool = false
    @State private var flashStatusText: String = ""
    @State private var flashProgress: Double = 0.0
    @State private var showFlashConfirmAlert: Bool = false
    
    // Multiboot vaihto
    @State private var slotToBoot: MultibootSlotInfo?
    @State private var showBootSlotAlert: Bool = false
    
    // Lataus ja poisto
    @State private var backupToDelete: ImageBackupItem?
    @State private var showDeleteConfirmAlert: Bool = false
    @State private var downloadingItem: ImageBackupItem?
    @State private var downloadProgress: Double = 0.0
    @State private var isDownloading: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Yläpalkki / Header
                headerView
                
                // MARK: - Välilehtivalitsin
                Picker("", selection: $selectedSubTab) {
                    ForEach(SubTab.allCases) { tab in
                        Label(tab.title(using: l10n), systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 480)
                
                // MARK: - Sisältö
                if let box = state.activeBox {
                    if isLoadingInfo && storageDevices.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(l10n.t("Image_Refreshing"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 40)
                    } else {
                        switch selectedSubTab {
                        case .backups:
                            backupsView(box: box)
                        case .flash:
                            flashView(box: box)
                        case .multiboot:
                            multibootView(box: box)
                        }
                    }
                } else {
                    noActiveBoxView
                }
            }
            .padding(24)
        }
        .task(id: state.activeBox?.id) {
            await loadBoxData()
        }
        .alert(l10n.t("Image_ConfirmDeleteTitle"), isPresented: $showDeleteConfirmAlert) {
            Button(l10n.t("Common_Cancel"), role: .cancel) {}
            Button(l10n.t("Image_BtnDelete"), role: .destructive) {
                if let item = backupToDelete, let box = state.activeBox {
                    Task {
                        let ok = await EnigmaBoxService.shared.deleteBoxImageBackup(box: box, remotePath: item.remotePath)
                        if ok {
                            state.showToast("Varmuuskopio poistettu boksista.")
                            await loadBoxData()
                        } else {
                            state.showToast("Poisto epäonnistui.", isError: true)
                        }
                    }
                }
            }
        } message: {
            if let item = backupToDelete {
                Text(String(format: l10n.t("Image_ConfirmDeleteMsg"), item.fileName))
            }
        }
        .alert(l10n.t("Image_ConfirmFlashTitle"), isPresented: $showFlashConfirmAlert) {
            Button(l10n.t("Common_Cancel"), role: .cancel) {}
            Button(l10n.t("Image_BtnStartFlash"), role: .destructive) {
                startFlashing()
            }
        } message: {
            Text(String(format: l10n.t("Image_ConfirmFlashMsg"), selectedTargetSlot))
        }
        .alert(l10n.t("Image_ConfirmBootTitle"), isPresented: $showBootSlotAlert) {
            Button(l10n.t("Common_Cancel"), role: .cancel) {}
            Button("Käynnistä", role: .destructive) {
                if let slot = slotToBoot, let box = state.activeBox {
                    Task {
                        let (ok, msg) = await EnigmaBoxService.shared.switchBootSlot(box: box, targetSlot: slot.slot)
                        if ok {
                            state.showToast("Boksi käynnistetään slotiin \(slot.slot)...")
                        } else {
                            state.showToast("Käynnistys epäonnistui: \(msg)", isError: true)
                        }
                    }
                }
            }
        } message: {
            if let slot = slotToBoot {
                Text(String(format: l10n.t("Image_ConfirmBootMsg"), slot.slot, slot.installedImage ?? ""))
            }
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t("Image_Title"))
                    .font(.title2.bold())
                
                if let box = state.activeBox {
                    HStack(spacing: 8) {
                        Text("\(box.name) (\(box.ip))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if let model = box.model {
                            Text("•  Malli: \(model)")
                                .font(.caption.bold())
                                .foregroundColor(.primary)
                        }
                        
                        if let curSlot = currentSlot {
                            Text("Slot \(curSlot)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                Task { await loadBoxData() }
            }) {
                HStack(spacing: 6) {
                    if isLoadingInfo {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(l10n.t("Header_Refresh"))
                }
            }
            .buttonStyle(.bordered)
            .disabled(isLoadingInfo || isBackingUp || isFlashing)
        }
    }
    
    // MARK: - Ei valittua boksia
    private var noActiveBoxView: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text(l10n.t("Common_NoActiveBox"))
                .font(.headline)
            Text("Valitse tai lisää Enigma2-laite yläpalkista aloittaaksesi.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Varmuuskopiot Välilehti
    private func backupsView(box: EnigmaBox) -> some View {
        VStack(spacing: 20) {
            // Uuden varmuuskopion luontikortti
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "archivebox.circle.fill")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("Image_CreateBackupTitle"))
                            .font(.headline)
                        Text(l10n.t("Image_CreateBackupDesc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                Divider()
                
                if storageDevices.isEmpty {
                    Text(l10n.t("Image_NoStorageAvailable"))
                        .font(.callout)
                        .foregroundColor(.orange)
                        .padding(.vertical, 6)
                } else {
                    HStack(spacing: 14) {
                        Text(l10n.t("Image_StorageSelect"))
                            .font(.subheadline.bold())
                        
                        Picker("", selection: $selectedStorage) {
                            ForEach(storageDevices) { dev in
                                Text(dev.displayTitle).tag(Optional(dev))
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 340)
                        
                        Spacer()
                        
                        Button(action: startBackup) {
                            HStack(spacing: 6) {
                                if isBackingUp {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Image(systemName: "plus.app.fill")
                                }
                                Text(isBackingUp ? l10n.t("Image_BackupInProgress") : l10n.t("Image_BtnStartBackup"))
                            }
                            .bold()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isBackingUp || selectedStorage == nil || isFlashing)
                    }
                }
                
                // Edistymispalkki varmuuskopioitaessa
                if isBackingUp {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: backupProgress, total: 1.0)
                            .progressViewStyle(.linear)
                        
                        HStack {
                            Text(backupStatusText.isEmpty ? "Valmistellaan..." : backupStatusText)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(backupProgress * 100))%")
                                .font(.caption.bold())
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
            
            // Olemassa olevat varmuuskopiot
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(l10n.t("Image_ExistingBackupsTitle"))
                        .font(.headline)
                    Spacer()
                    Text("\(existingBackups.count) kpl")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if existingBackups.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "doc.zipper")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text(l10n.t("Image_NoBackupsFound"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 30)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(existingBackups) { item in
                            backupRow(item: item)
                        }
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Yksittäinen varmuuskopiorivi
    private func backupRow(item: ImageBackupItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .foregroundColor(.accentColor)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    Text(item.formattedSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(item.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(item.mountPoint)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Toiminnot
            HStack(spacing: 8) {
                // Lataa Macille
                Button(action: { downloadBackupToMac(item: item) }) {
                    Label(l10n.t("Image_BtnDownloadMac"), systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .disabled(isDownloading)
                
                // Asenna slotiin pikavalinta
                Button(action: {
                    selectedBoxBackupForFlash = item
                    flashSourceOption = .box
                    selectedSubTab = .flash
                }) {
                    Label(l10n.t("Image_BtnFlashThis"), systemImage: "bolt.badge.automatic")
                }
                .buttonStyle(.bordered)
                .font(.caption)
                
                // Poista
                Button(action: {
                    backupToDelete = item
                    showDeleteConfirmAlert = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
    }
    
    // MARK: - Flash Välilehti
    private func flashView(box: EnigmaBox) -> some View {
        VStack(spacing: 20) {
            // Varoitusbanneri
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.t("Image_WarningHeader"))
                        .font(.headline)
                        .foregroundColor(.yellow)
                    Text(l10n.t("Image_WarningText"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.1)))
            .overlay(
                RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.3), lineWidth: 1)
            )
            
            // Asennusasetukset
            VStack(alignment: .leading, spacing: 16) {
                Text(l10n.t("Image_FlashTitle"))
                    .font(.headline)
                Text(l10n.t("Image_FlashDesc"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                // 1. Imagen lähde
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("Image_SourceSelect"))
                        .font(.subheadline.bold())
                    
                    Picker("", selection: $flashSourceOption) {
                        Text(l10n.t("Image_SourceBox")).tag(FlashSourceOption.box)
                        Text(l10n.t("Image_SourceLocal")).tag(FlashSourceOption.local)
                    }
                    .pickerStyle(.radioGroup)
                    
                    if flashSourceOption == .box {
                        if existingBackups.isEmpty {
                            Text("Boksista ei löytynyt varmuuskopioita. Valitse paikallinen .zip Macilta.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Picker("Valitse image:", selection: $selectedBoxBackupForFlash) {
                                ForEach(existingBackups) { b in
                                    Text("\(b.fileName) (\(b.formattedSize))").tag(Optional(b))
                                }
                            }
                            .frame(maxWidth: 450)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Button(l10n.t("Image_BtnChooseZip")) {
                                chooseLocalZip()
                            }
                            .buttonStyle(.bordered)
                            
                            if let url = selectedLocalZipURL {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.zipper")
                                        .foregroundColor(.accentColor)
                                    Text(url.lastPathComponent)
                                        .font(.subheadline.bold())
                                }
                            } else {
                                Text("Ei valittua tiedostoa")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Divider()
                
                // 2. Kohdeslotti
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("Image_TargetSlot"))
                        .font(.subheadline.bold())
                    
                    Picker("Kohdeslotti:", selection: $selectedTargetSlot) {
                        ForEach(multibootSlots) { s in
                            Text(s.displayName).tag(s.slot)
                        }
                    }
                    .frame(maxWidth: 380)
                    
                    if selectedTargetSlot == currentSlot {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.orange)
                            Text(l10n.t("Image_TargetSlotWarning"))
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                Divider()
                
                // 3. Asetukset
                Toggle(l10n.t("Image_RebootAfter"), isOn: $rebootAfterFlash)
                    .font(.subheadline)
                
                // 4. Asennuspainike & Edistyminen
                if isFlashing {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: flashProgress, total: 1.0)
                            .progressViewStyle(.linear)
                        
                        HStack {
                            Text(flashStatusText)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(flashProgress * 100))%")
                                .font(.caption.bold())
                        }
                    }
                    .padding(.top, 10)
                } else {
                    HStack {
                        Spacer()
                        Button(action: { showFlashConfirmAlert = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                Text(l10n.t("Image_BtnStartFlash"))
                            }
                            .font(.headline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(!canStartFlash)
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }
    
    private var canStartFlash: Bool {
        if isFlashing || isBackingUp { return false }
        if storageDevices.isEmpty { return false }
        if flashSourceOption == .box {
            return selectedBoxBackupForFlash != nil
        } else {
            return selectedLocalZipURL != nil
        }
    }
    
    // MARK: - Multiboot Välilehti
    private func multibootView(box: EnigmaBox) -> some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "square.split.2x2.fill")
                        .foregroundColor(.accentColor)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("Image_MultibootTitle"))
                            .font(.headline)
                        Text(l10n.t("Image_MultibootDesc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                
                Divider()
                
                VStack(spacing: 12) {
                    ForEach(multibootSlots) { slot in
                        multibootSlotCard(slot: slot)
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }
    
    private func multibootSlotCard(slot: MultibootSlotInfo) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(slot.isCurrent ? Color.green.opacity(0.2) : Color.secondary.opacity(0.1))
                    .frame(width: 36, height: 36)
                Text("\(slot.slot)")
                    .font(.headline)
                    .foregroundColor(slot.isCurrent ? .green : .primary)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Slot \(slot.slot)")
                        .font(.headline)
                    if slot.isCurrent {
                        Text("AKTIIVINEN / KÄYNNISSÄ")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
                
                if let img = slot.installedImage, !img.isEmpty {
                    Text(img)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("(Tyhjä osio)")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            
            Spacer()
            
            if !slot.isCurrent && slot.installedImage != nil && slot.installedImage?.isEmpty == false {
                Button(action: {
                    slotToBoot = slot
                    showBootSlotAlert = true
                }) {
                    Label(l10n.t("Image_BtnBootSlot"), systemImage: "arrow.counterclockwise.circle")
                }
                .buttonStyle(.borderedProminent)
                .font(.caption)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(slot.isCurrent ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
    }
    
    // MARK: - Toiminnot (Logiikka)
    
    private func loadBoxData() async {
        guard let box = state.activeBox else { return }
        isLoadingInfo = true
        defer { isLoadingInfo = false }
        
        // 1. Tallennuslaitteet
        let devs = await EnigmaBoxService.shared.fetchBoxStorageDevices(box: box)
        self.storageDevices = devs
        if self.selectedStorage == nil || !devs.contains(where: { $0.mountPoint == self.selectedStorage?.mountPoint }) {
            self.selectedStorage = devs.first(where: { $0.isUsableForBackup }) ?? devs.first
        }
        
        // 2. Multiboot-slotit
        let (cur, slots) = await EnigmaBoxService.shared.fetchMultibootSlots(box: box)
        self.currentSlot = cur
        self.multibootSlots = slots
        if let cur = cur {
            self.selectedTargetSlot = cur
        } else if let first = slots.first {
            self.selectedTargetSlot = first.slot
        }
        
        // 3. Varmuuskopiot
        let backups = await EnigmaBoxService.shared.fetchBoxImageBackups(box: box, storageDevices: devs)
        self.existingBackups = backups
        if self.selectedBoxBackupForFlash == nil {
            self.selectedBoxBackupForFlash = backups.first
        }
    }
    
    private func startBackup() {
        guard let box = state.activeBox, let storage = selectedStorage else { return }
        isBackingUp = true
        backupProgress = 0.05
        backupStatusText = "Valmistellaan..."
        
        Task {
            let (success, message) = await EnigmaBoxService.shared.createFullImageBackup(
                box: box,
                destinationStorage: storage
            ) { msg, progress in
                Task { @MainActor in
                    self.backupStatusText = msg
                    self.backupProgress = progress
                }
            }
            
            await MainActor.run {
                self.isBackingUp = false
                if success {
                    state.showToast("Varmuuskopiointi valmis!")
                } else {
                    state.showToast("Virhe: \(message)", isError: true)
                }
            }
            
            await loadBoxData()
        }
    }
    
    private func chooseLocalZip() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.zip]
        panel.title = "Valitse asennettava Enigma2 Image (.zip)"
        
        if panel.runModal() == .OK, let url = panel.url {
            self.selectedLocalZipURL = url
        }
    }
    
    private func startFlashing() {
        guard let box = state.activeBox, let storage = selectedStorage ?? storageDevices.first else {
            state.showToast("Ei sopivaa tallennuslaitetta löytynyt väliaikaistiedostoille.", isError: true)
            return
        }
        
        let source: FlashZipSource
        if flashSourceOption == .box {
            guard let item = selectedBoxBackupForFlash else {
                state.showToast("Valitse boksissa oleva image.", isError: true)
                return
            }
            source = .boxBackup(path: item.remotePath, fileName: item.fileName)
        } else {
            guard let url = selectedLocalZipURL else {
                state.showToast("Valitse paikallinen .zip-tiedosto.", isError: true)
                return
            }
            source = .localFile(url: url)
        }
        
        isFlashing = true
        flashProgress = 0.1
        flashStatusText = "Käynnistetään asennus..."
        
        Task {
            let (success, message) = await EnigmaBoxService.shared.flashImage(
                box: box,
                zipSource: source,
                targetSlot: selectedTargetSlot,
                storage: storage,
                rebootAfter: rebootAfterFlash
            ) { msg, progress in
                Task { @MainActor in
                    self.flashStatusText = msg
                    self.flashProgress = progress
                }
            }
            
            await MainActor.run {
                self.isFlashing = false
                if success {
                    state.showToast(message)
                } else {
                    state.showToast("Asennusvirhe: \(message)", isError: true)
                }
            }
            
            await loadBoxData()
        }
    }
    
    private func downloadBackupToMac(item: ImageBackupItem) {
        let panel = NSSavePanel()
        panel.title = "Tallenna varmuuskopio Macille"
        panel.nameFieldStringValue = item.fileName
        panel.allowedContentTypes = [UTType.zip]
        
        if panel.runModal() == .OK, let targetURL = panel.url, let box = state.activeBox {
            isDownloading = true
            downloadingItem = item
            downloadProgress = 0.05
            
            Task {
                let (ok, err) = await EnigmaBoxService.shared.downloadImageBackup(
                    box: box,
                    remotePath: item.remotePath,
                    localDestination: targetURL
                ) { prog in
                    Task { @MainActor in
                        self.downloadProgress = prog
                    }
                }
                
                await MainActor.run {
                    self.isDownloading = false
                    self.downloadingItem = nil
                    if ok {
                        state.showToast("Varmuuskopio ladattu onnistuneesti Macille!")
                    } else {
                        state.showToast("Latausvirhe: \(err ?? "Tuntematon virhe")", isError: true)
                    }
                }
            }
        }
    }
}
