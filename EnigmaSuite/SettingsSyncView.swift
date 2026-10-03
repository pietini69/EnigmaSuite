import SwiftUI
import UniformTypeIdentifiers

struct SettingsSyncView: View {
    @EnvironmentObject var state: EnigmaSuiteState
    @EnvironmentObject var l10n: LocalizationManager
    
    // Lähde ja Kohde
    @State private var sourceBox: EnigmaBox?
    @State private var targetBox: EnigmaBox?
    
    // Asennuspaketit ja tiedostot
    @State private var loadedPackages: [EnigmaBox] = []
    @State private var isDropTargeted: Bool = false
    @State private var isExtractingPackage: Bool = false
    
    // Asetusdata
    @State private var sourceSettings: [String: String] = [:]
    @State private var targetSettings: [String: String] = [:]
    @State private var entries: [SettingEntry] = []
    
    // Tilat
    @State private var isLoading: Bool = false
    @State private var isSyncing: Bool = false
    @State private var syncStatusMessage: String = ""
    @State private var selectedCategory: SettingsCategory = .all
    @State private var showOnlyDifferences: Bool = true
    @State private var searchText: String = ""
    @State private var includeTunersInSync: Bool = false
    
    // Varmuuskopiot
    @State private var showBackupsSheet: Bool = false
    @State private var backups: [BackupRecord] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - YLÄPALKKI: Boksin valinnat & Synkronointi-painike
            topBar
            
            if let target = resolvedTargetBox, !target.ip.hasPrefix("package://"), !isTargetOnline {
                targetOfflineBanner(target: target)
            }
            
            Divider()
            
            // MARK: - KATEGORIAFILTERIT (RIVITTYVÄ FLOWLAYOUT)
            categoryChips
            
            Divider()
            
            // MARK: - VIRITINTEN VERTAILUKORTTI
            if selectedCategory == .all || selectedCategory == .tuners {
                tunersComparisonCard
            }
            
            // MARK: - ASETUSTEN DIFF-LISTA
            if isLoading || isExtractingPackage {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(isExtractingPackage ? L10n("Sync_Extracting") : L10n("Sync_Fetching"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "shippingbox.and.arrow.backward")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor.opacity(0.8))
                    
                    Text(L10n("Sync_EmptyTitle"))
                        .font(.headline)
                    
                    Text(L10n("Sync_EmptyDesc"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                    
                    HStack(spacing: 12) {
                        Button(action: { openPackageFileDialog(isSource: true) }) {
                            Label(L10n("Sync_OpenRootfsBtn"), systemImage: "shippingbox")
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button(action: {
                            Task { await fetchAllSettings() }
                        }) {
                            Label(L10n("Sync_Fetch"), systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(sourceBox == nil || targetBox == nil)
                    }
                    
                    Text(L10n("Sync_DropHint"))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                settingsListView
            }
        }
        .overlay(
            Group {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                        .background(Color.accentColor.opacity(0.12))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.accentColor)
                                Text(L10n("Sync_DropOverlay"))
                                    .font(.title3.bold())
                                    .foregroundColor(.accentColor)
                            }
                        )
                        .padding(12)
                }
            }
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                Task { @MainActor in
                    await loadPackageFromURL(url, isSource: true)
                }
            }
            return true
        }
        .onAppear {
            setupInitialBoxes()
            if let pending = state.pendingPackageURL {
                state.pendingPackageURL = nil
                Task {
                    await loadPackageFromURL(pending, isSource: true)
                }
            }
        }
        .onChange(of: state.pendingPackageURL) { _, newURL in
            if let url = newURL {
                state.pendingPackageURL = nil
                Task {
                    await loadPackageFromURL(url, isSource: true)
                }
            }
        }
        .sheet(isPresented: $showBackupsSheet) {
            backupsSheet
        }
    }
    
    // MARK: - Yläpalkki
    private var topBar: some View {
        HStack(spacing: 16) {
            // Lähdeboksi
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(L10n("Sync_SourceHeader"))
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: { openPackageFileDialog(isSource: true) }) {
                        HStack(spacing: 3) {
                            Image(systemName: "shippingbox")
                            Text(L10n("Sync_OpenRootfs"))
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help(L10n("Sync_OpenRootfsHelp"))
                }
                
                Picker("", selection: $sourceBox) {
                    Section(L10n("Sync_BoxesSection")) {
                        ForEach(state.boxes) { box in
                            Text("\(box.isOnline ? "🟢" : "🔴") \(box.name) (\(box.ip))\(box.isOnline ? "" : " [Offline]")").tag(Optional(box))
                        }
                    }
                    if !loadedPackages.isEmpty {
                        Section(L10n("Sync_PackagesSection")) {
                            ForEach(loadedPackages) { pkg in
                                Text("📦 \(pkg.name)").tag(Optional(pkg))
                            }
                        }
                    }
                }
                .labelsHidden()
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
            }
            
            Image(systemName: "arrow.right.circle.fill")
                .font(.title2)
                .foregroundColor(.accentColor)
                .padding(.top, 14)
            
            // Kohdeboksi
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(L10n("Sync_TargetHeader"))
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: { openPackageFileDialog(isSource: false) }) {
                        HStack(spacing: 3) {
                            Image(systemName: "shippingbox")
                            Text(L10n("Sync_OpenRootfs"))
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help(L10n("Sync_TargetRootfsHelp"))
                }
                
                Picker("", selection: $targetBox) {
                    Section(L10n("Sync_BoxesSection")) {
                        ForEach(state.boxes) { box in
                            Text("\(box.isOnline ? "🟢" : "🔴") \(box.name) (\(box.ip))\(box.isOnline ? "" : " [Offline]")").tag(Optional(box))
                        }
                    }
                    if !loadedPackages.isEmpty {
                        Section(L10n("Sync_PackagesSection")) {
                            ForEach(loadedPackages) { pkg in
                                Text("📦 \(pkg.name)").tag(Optional(pkg))
                            }
                        }
                    }
                }
                .labelsHidden()
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 460)
            }
            
            Button(action: {
                Task { await fetchAllSettings() }
            }) {
                Label(L10n("Sync_Fetch"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || isSyncing || isExtractingPackage)
            .padding(.top, 14)
            
            Spacer()
            
            // Varmuuskopiot
            Button(action: {
                loadBackups()
                showBackupsSheet = true
            }) {
                Label(L10n("Sync_Backups"), systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.bordered)
            .padding(.top, 14)
            
            // Synkronoi
            Button(action: {
                Task { await performSync() }
            }) {
                HStack {
                    if isSyncing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    }
                    Text("\(L10n("Sync_SyncSelected")) (\(selectedCount))")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(selectedCount == 0 || isSyncing || targetBox?.ip.hasPrefix("package://") == true || !isTargetOnline)
            .help(
                targetBox?.ip.hasPrefix("package://") == true ? "Kohde on asennuspaketti (vain luku)" :
                (!isTargetOnline ? "Kohdeboksi ei ole linjoilla (FTP-yhteyttä ei saada)" :
                "Synkronoi valitut asetukset kohdeboksille")
            )
            .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Rivityvä Kategorialista (FlowLayout)
    private var categoryChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n("Sync_Categories"))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Toggle(L10n("Sync_OnlyDiffs"), isOn: $showOnlyDifferences)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                
                TextField(L10n("Sync_SearchPlaceholder"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                
                Button(L10n("Sync_SelectAll")) { selectAll(true) }
                    .font(.caption)
                    .buttonStyle(.borderless)
                
                Button(L10n("Sync_ClearSelection")) { selectAll(false) }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
            
            FlowLayout(spacing: 8) {
                ForEach(SettingsCategory.allCases) { cat in
                    let count = countForCategory(cat)
                    Button(action: {
                        selectedCategory = cat
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: cat.icon)
                            Text(cat.title)
                                .lineLimit(1)
                            if count > 0 {
                                Text("(\(count))")
                                    .font(.caption2.bold())
                                    .lineLimit(1)
                                    .padding(.horizontal, 4)
                                    .background(selectedCategory == cat ? Color.white.opacity(0.3) : Color.secondary.opacity(0.2))
                                    .clipShape(Capsule())
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selectedCategory == cat ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .foregroundColor(selectedCategory == cat ? .white : .primary)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Virittimien Vertailukortti
    private var tunersComparisonCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L10n("Sync_TunerComparison"), systemImage: "antenna.radiowaves.left.and.right")
                    .font(.subheadline.bold())
                
                Spacer()
                
                Toggle(L10n("Sync_CopyTuners"), isOn: $includeTunersInSync)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .onChange(of: includeTunersInSync) { _, enabled in
                        toggleTunerSelection(enabled)
                    }
            }
            
            let sTuners = sourceBox?.tuners ?? []
            let tTuners = targetBox?.tuners ?? []
            
            if sTuners.isEmpty && tTuners.isEmpty {
                Text(L10n("Sync_NoTunersDetected"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(L10n("Sync_Source")) \(sourceBox?.name ?? "") (\(sTuners.count) \(L10n("Boxes_Pcs")))")
                            .font(.caption.bold())
                        ForEach(sTuners.prefix(8)) { t in
                            HStack(spacing: 4) {
                                Text("\(L10n("Sync_Tuner")) \(t.shortLetter):")
                                    .font(.caption2.bold())
                                Text(t.type)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(L10n("Sync_Target")) \(targetBox?.name ?? "") (\(tTuners.count) \(L10n("Boxes_Pcs")))")
                            .font(.caption.bold())
                        ForEach(tTuners.prefix(8)) { t in
                            HStack(spacing: 4) {
                                Text("\(L10n("Sync_Tuner")) \(t.shortLetter):")
                                    .font(.caption2.bold())
                                Text(t.type)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
    
    // MARK: - Diff-lista
    private var filteredEntries: [SettingEntry] {
        entries.filter { entry in
            if selectedCategory != .all && entry.category != selectedCategory {
                return false
            }
            if showOnlyDifferences && !entry.isDifferent {
                return false
            }
            if !searchText.isEmpty {
                let lower = searchText.lowercased()
                let kMatch = entry.key.lowercased().contains(lower)
                let sMatch = entry.sourceValue?.lowercased().contains(lower) ?? false
                let tMatch = entry.targetValue?.lowercased().contains(lower) ?? false
                if !kMatch && !sMatch && !tMatch { return false }
            }
            return true
        }
    }
    
    private var selectedCount: Int {
        entries.filter { $0.isSelected }.count
    }
    
    private var settingsListView: some View {
        List {
            ForEach($entries) { $entry in
                if shouldShowEntry(entry) {
                    HStack(spacing: 12) {
                        Toggle("", isOn: $entry.isSelected)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.key)
                                    .font(.system(.subheadline, design: .monospaced).bold())
                                    .foregroundColor(entry.isDifferent ? .primary : .secondary)
                                
                                if case .compatible = entry.tunerCompatibility {
                                    badge(text: L10n("Sync_TunerCompatible"), color: .green)
                                } else if case .incompatibleType = entry.tunerCompatibility {
                                    badge(text: L10n("Sync_TunerIncompatible"), color: .orange)
                                } else if case .missingInTarget = entry.tunerCompatibility {
                                    badge(text: L10n("Sync_TunerMissing"), color: .red)
                                }
                            }
                            
                            HStack(spacing: 16) {
                                HStack(spacing: 4) {
                                    Text(L10n("Sync_Source"))
                                        .font(.caption2.bold())
                                        .foregroundColor(.secondary)
                                    Text(entry.sourceValue ?? "(\(L10n("Sync_Missing")))")
                                        .font(.caption)
                                        .foregroundColor(entry.sourceValue == nil ? .secondary : .accentColor)
                                }
                                
                                HStack(spacing: 4) {
                                    Text(L10n("Sync_Target"))
                                        .font(.caption2.bold())
                                        .foregroundColor(.secondary)
                                    Text(entry.targetValue ?? "(\(L10n("Sync_Missing")))")
                                        .font(.caption)
                                        .foregroundColor(entry.targetValue == nil ? .secondary : (entry.isDifferent ? .orange : .secondary))
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
    
    private func shouldShowEntry(_ entry: SettingEntry) -> Bool {
        if selectedCategory != .all && entry.category != selectedCategory { return false }
        if showOnlyDifferences && !entry.isDifferent { return false }
        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            let kMatch = entry.key.lowercased().contains(lower)
            let sMatch = entry.sourceValue?.lowercased().contains(lower) ?? false
            let tMatch = entry.targetValue?.lowercased().contains(lower) ?? false
            if !kMatch && !sMatch && !tMatch { return false }
        }
        return true
    }
    
    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
    }
    
    // MARK: - Boksin tilojen tarkistus ja resoluutio
    private var resolvedSourceBox: EnigmaBox? {
        guard let source = sourceBox else { return nil }
        if source.ip.hasPrefix("package://") { return source }
        return state.boxes.first(where: { $0.id == source.id }) ?? source
    }
    
    private var resolvedTargetBox: EnigmaBox? {
        guard let target = targetBox else { return nil }
        if target.ip.hasPrefix("package://") { return target }
        return state.boxes.first(where: { $0.id == target.id }) ?? target
    }
    
    private var isSourceOnline: Bool {
        guard let s = resolvedSourceBox else { return false }
        if s.ip.hasPrefix("package://") { return true }
        return s.isOnline
    }
    
    private var isTargetOnline: Bool {
        guard let t = resolvedTargetBox else { return false }
        if t.ip.hasPrefix("package://") { return false }
        return t.isOnline
    }
    
    private func targetOfflineBanner(target: EnigmaBox) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(L10n("Sync_OfflineBanner"))
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
    }
    
    // MARK: - Toiminnot
    private func setupInitialBoxes() {
        loadSavedPackages()
        let onlineBoxes = state.boxes.filter { $0.isOnline }
        
        if sourceBox == nil {
            if let active = state.activeBox, active.isOnline {
                sourceBox = active
            } else {
                sourceBox = onlineBoxes.first ?? state.boxes.first
            }
        }
        
        if targetBox == nil {
            if let secondOnline = onlineBoxes.first(where: { $0.id != sourceBox?.id }) {
                targetBox = secondOnline
            } else if let active = state.activeBox, active.id != sourceBox?.id {
                targetBox = active
            } else {
                targetBox = state.boxes.first(where: { $0.id != sourceBox?.id }) ?? state.boxes.first
            }
        }
    }
    
    private func loadSavedPackages() {
        if let data = UserDefaults.standard.data(forKey: "EnigmaSuiteLoadedPackages"),
           let pkgs = try? JSONDecoder().decode([EnigmaBox].self, from: data) {
            self.loadedPackages = pkgs
        }
    }
    
    private func savePackage(_ box: EnigmaBox) {
        if let idx = loadedPackages.firstIndex(where: { $0.ip == box.ip }) {
            loadedPackages[idx] = box
        } else {
            loadedPackages.append(box)
        }
        if let data = try? JSONEncoder().encode(loadedPackages) {
            UserDefaults.standard.set(data, forKey: "EnigmaSuiteLoadedPackages")
        }
    }
    
    private func openPackageFileDialog(isSource: Bool) {
        let panel = NSOpenPanel()
        panel.title = "Valitse asennuspaketti tai asetustiedosto"
        panel.prompt = "Avaa"
        panel.message = "Valitse rootfs.tar.bz2, asennusimage (.zip), kansio tai settings-tiedosto"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "bz2") ?? .data,
            UTType(filenameExtension: "tar") ?? .data,
            UTType(filenameExtension: "zip") ?? .data,
            UTType(filenameExtension: "gz") ?? .data,
            .item,
            .folder
        ]
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await loadPackageFromURL(url, isSource: isSource)
            }
        }
    }
    
    private func loadPackageFromURL(_ url: URL, isSource: Bool) async {
        isExtractingPackage = true
        state.showToast("Puretaan asetuksia tiedostosta \(url.lastPathComponent)")
        
        let result = await RootfsPackageService.shared.extractSettings(from: url)
        isExtractingPackage = false
        
        if let info = result.info {
            let box = RootfsPackageService.shared.createBox(from: info)
            savePackage(box)
            if isSource {
                sourceBox = box
                // Jos kohdeboksi on offline-tilassa tai paketti, vaihdetaan ensisijaisesti online-boksiin
                let currentTargetId = targetBox?.id
                let isCurrentTargetOnline = state.boxes.first(where: { $0.id == currentTargetId })?.isOnline ?? false
                if targetBox == nil || targetBox?.ip.hasPrefix("package://") == true || !isCurrentTargetOnline {
                    if let firstOnline = state.boxes.first(where: { $0.isOnline }) {
                        targetBox = firstOnline
                    }
                }
            } else {
                targetBox = box
            }
            state.showToast("Asennuspaketin asetukset (\(info.settings.count) kpl) ladattu onnistuneesti!")
            await fetchAllSettings()
        } else {
            state.showToast(result.error ?? "Asetusten purku epäonnistui", isError: true)
        }
    }
    
    private func countForCategory(_ cat: SettingsCategory) -> Int {
        if cat == .all {
            return entries.filter { $0.isDifferent }.count
        }
        return entries.filter { $0.category == cat && $0.isDifferent }.count
    }
    
    private func selectAll(_ select: Bool) {
        for idx in entries.indices {
            if shouldShowEntry(entries[idx]) {
                entries[idx].isSelected = select
            }
        }
    }
    
    private func toggleTunerSelection(_ enabled: Bool) {
        for idx in entries.indices where entries[idx].category == .tuners {
            if enabled {
                if case .compatible = entries[idx].tunerCompatibility {
                    entries[idx].isSelected = true
                }
            } else {
                entries[idx].isSelected = false
            }
        }
    }
    
    private func fetchAllSettings() async {
        guard let s = resolvedSourceBox, let t = resolvedTargetBox else { return }
        isLoading = true
        
        async let sRes = EnigmaBoxService.shared.fetchSettings(ip: s.ip, port: s.port, username: s.username, password: s.password)
        async let tRes = EnigmaBoxService.shared.fetchSettings(ip: t.ip, port: t.port, username: t.username, password: t.password)
        
        let (sData, tData) = await (sRes, tRes)
        
        if let err = sData.error {
            state.showToast("Lähdeboksin virhe: \(err)", isError: true)
        }
        if let err = tData.error {
            state.showToast("Kohdeboksin virhe: \(err)", isError: true)
        }
        
        self.sourceSettings = SettingsParser.shared.parse(content: sData.content)
        self.targetSettings = SettingsParser.shared.parse(content: tData.content)
        
        let defaultCats: Set<SettingsCategory> = [.skinAndDisplay, .recording, .language, .epg, .timezone, .usage]
        self.entries = SettingsParser.shared.buildEntries(
            source: sourceSettings,
            target: targetSettings,
            sourceTuners: s.tuners,
            targetTuners: t.tuners,
            defaultSelectedCategories: defaultCats
        )
        
        isLoading = false
        if sData.error == nil && tData.error == nil {
            state.showToast("Asetukset noudettu ja vertailtu onnistuneesti!")
        }
    }
    
    private func performSync() async {
        guard let target = resolvedTargetBox else { return }
        if target.ip.hasPrefix("package://") {
            state.showToast("Kohde on asennuspaketti (vain luku). Valitse kohteeksi aktiivinen digiboksi.", isError: true)
            return
        }
        
        guard isTargetOnline else {
            state.showToast("Kohdeboksi \(target.name) (\(target.ip)) ei ole linjoilla.", isError: true)
            return
        }
        
        isSyncing = true
        
        // 0. Tarkistetaan FTP-yhteys nopeasti ennen init 4 -komennon suorittamista
        state.showToast("Tarkistetaan FTP-yhteys kohteeseen \(target.ip)...")
        let canConnect = await EnigmaBoxService.shared.checkFTPConnection(ip: target.ip, username: target.username, password: target.password)
        guard canConnect else {
            isSyncing = false
            state.showToast("FTP-yhteys kohteeseen \(target.name) (\(target.ip)) epäonnistui. Varmista että laite on päällä ja verkossa.", isError: true)
            return
        }
        
        // 1. Luodaan paikallinen varmuuskopio kohdeboksin asetuksista ennen muutosta
        let targetContent = targetSettings.map { "\($0.key)=\($0.value)" }.joined(separator: "\n") + "\n"
        if let backupURL = EnigmaBoxService.shared.saveBackup(box: target, content: targetContent) {
            print("[SettingsSync] Varmuuskopio tallennettu: \(backupURL.path)")
        }
        
        // 2. Muodostetaan uusi settings-tiedosto
        let newContent = SettingsParser.shared.applySelected(selectedEntries: entries, into: targetSettings)
        
        // 3. Suoritetaan Enigma2 turvallinen päivityssekvenssi:
        //    a) init 4 (pysäyttää Enigma2 niin se ei ylikirjoita muistissa olevilla asetuksilla)
        //    b) siirretään uusi /etc/enigma2/settings FTP:llä
        //    c) init 3 (käynnistää Enigma2 uusilla asetuksilla)
        state.showToast("Pysäytetään Enigma2 (init 4)")
        let stopped = await EnigmaBoxService.shared.runTelnetCommand(ip: target.ip, command: "init 4", username: target.username, password: target.password)
        if !stopped {
            print("[SettingsSync] Telnet init 4 varoitus, yritetään silti siirtoa...")
        }
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        state.showToast("Siirretään uudet asetukset boksille")
        let upload = await EnigmaBoxService.shared.uploadSettings(ip: target.ip, content: newContent, port: target.port, username: target.username, password: target.password)
        guard upload.success else {
            state.showToast("Asetusten siirto epäonnistui: \(upload.error ?? "")", isError: true)
            let _ = await EnigmaBoxService.shared.runTelnetCommand(ip: target.ip, command: "init 3", username: target.username, password: target.password)
            isSyncing = false
            return
        }
        
        state.showToast("Käynnistetään Enigma2 uudelleen (init 3)")
        let _ = await EnigmaBoxService.shared.runTelnetCommand(ip: target.ip, command: "init 3", username: target.username, password: target.password)
        
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        isSyncing = false
        state.showToast("Asetukset synkronoitu onnistuneesti kohteeseen \(target.name)!")
        
        // Noudetaan uudet asetukset automaattisesti
        await fetchAllSettings()
    }
    
    private func loadBackups() {
        if let target = resolvedTargetBox {
            self.backups = EnigmaBoxService.shared.listBackups(for: target)
        }
    }
    
    // MARK: - Varmuuskopiot Sheet
    private var backupsSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("\(L10n("Dialog_BackupsHeader")): \(resolvedTargetBox?.name ?? "")")
                    .font(.headline)
                Spacer()
                Button(L10n("Common_Close")) { showBackupsSheet = false }
            }
            
            if backups.isEmpty {
                Text(L10n("Sync_BackupsEmpty"))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(backups) { rec in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rec.formattedDate).font(.subheadline.bold())
                            Text("\(rec.entryCount) \(L10n("Dialog_SettingsCount")) • \(rec.fileURL.lastPathComponent)")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button(L10n("Sync_RestoreVersion")) {
                            restoreBackup(rec)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .frame(width: 500, height: 380)
    }
    
    private func restoreBackup(_ rec: BackupRecord) {
        guard let target = resolvedTargetBox,
              !target.ip.hasPrefix("package://"),
              let content = try? String(contentsOf: rec.fileURL, encoding: .utf8) else { return }
        
        guard isTargetOnline else {
            state.showToast("Kohdeboksi \(target.name) (\(target.ip)) ei ole linjoilla.", isError: true)
            return
        }
        
        Task {
            showBackupsSheet = false
            state.showToast("Tarkistetaan yhteys kohteeseen \(target.ip)...")
            let canConnect = await EnigmaBoxService.shared.checkFTPConnection(ip: target.ip, username: target.username, password: target.password)
            guard canConnect else {
                state.showToast("FTP-yhteys kohteeseen \(target.name) (\(target.ip)) epäonnistui.", isError: true)
                return
            }
            
            state.showToast("Palautetaan varmuuskopio")
            let _ = await EnigmaBoxService.shared.runTelnetCommand(ip: target.ip, command: "init 4", username: target.username, password: target.password)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let res = await EnigmaBoxService.shared.uploadSettings(ip: target.ip, content: content, port: target.port, username: target.username, password: target.password)
            let _ = await EnigmaBoxService.shared.runTelnetCommand(ip: target.ip, command: "init 3", username: target.username, password: target.password)
            
            if res.success {
                state.showToast("Varmuuskopio palautettu onnistuneesti!")
                await fetchAllSettings()
            } else {
                state.showToast("Palautus epäonnistui: \(res.error ?? "")", isError: true)
            }
        }
    }
}
