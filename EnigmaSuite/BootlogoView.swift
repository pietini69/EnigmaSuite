import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BootlogoView: View {
    @EnvironmentObject var state: EnigmaSuiteState
    @EnvironmentObject var l10n: LocalizationManager
    
    // Kuvalähde
    @State private var sourceImageURL: URL?
    @State private var previewImage: NSImage?
    @State private var generatedMviData: Data?
    
    // Asetukset
    @State private var selectedBootlogo: BootlogoType = .bootlogo
    @State private var resolution: ResolutionOption = .fhd1080
    @State private var scalingMode: ScalingMode = .pad
    @State private var distro: EnigmaImageDistro = .auto
    
    // Tilat
    @State private var isProcessing: Bool = false
    @State private var statusText: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - YLÄOSIO: Lähdekuvan valinta & Esikatselu
                HStack(alignment: .top, spacing: 24) {
                    // Esikatseluruutu
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n("Bootlogo_PreviewTitle"))
                                .font(.headline)
                            Spacer()
                            Text("\(resolution.width) × \(resolution.height) • \(scalingMode.title)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        ZStack {
                            Color.black
                            
                            if let img = previewImage {
                                Group {
                                    switch scalingMode {
                                    case .pad:
                                        Image(nsImage: img)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                    case .crop:
                                        Image(nsImage: img)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    case .stretch:
                                        Image(nsImage: img)
                                            .resizable()
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                    Text(L10n("Bootlogo_DragDropPrompt"))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if isProcessing {
                                ProgressView()
                                    .scaleEffect(1.2)
                                    .padding(16)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .frame(maxHeight: 280)
                        .clipped()
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                        .animation(.easeInOut(duration: 0.2), value: scalingMode)
                        .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                            handleDrop(providers: providers)
                        }
                        
                        // Kuvalähteen painikkeet
                        HStack(spacing: 10) {
                            Button(action: selectFile) {
                                Label(L10n("Bootlogo_BtnFile"), systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                            .help(L10n("Bootlogo_SelectFileHelp"))
                            
                            Button(action: {
                                Task { await grabScreenshotFromBox() }
                            }) {
                                Label(L10n("Bootlogo_BtnTv"), systemImage: "tv")
                            }
                            .buttonStyle(.bordered)
                            .help(L10n("Bootlogo_TvHelp"))
                            
                            Button(action: {
                                Task { await fetchBootlogoFromBox() }
                            }) {
                                Label(L10n("Bootlogo_BtnBox"), systemImage: "arrow.down.doc")
                            }
                            .buttonStyle(.bordered)
                            .help(L10n("Bootlogo_BoxHelp"))
                            
                            Spacer()
                            
                            Button(action: saveImageToMac) {
                                Label(L10n("Bootlogo_SaveImageLocalShort"), systemImage: "photo.badge.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .disabled(previewImage == nil || isProcessing)
                            .help(L10n("Bootlogo_SaveImageHelp"))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Asetukset & Kohteet
                    VStack(alignment: .leading, spacing: 18) {
                        Text(L10n("Bootlogo_SettingsTitle"))
                            .font(.headline)
                        
                        // Kohdekuva
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n("Bootlogo_TargetImageLabel"))
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Picker("", selection: $selectedBootlogo) {
                                ForEach(BootlogoType.allCases) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .labelsHidden()
                            Text(selectedBootlogo.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        // Resoluutio
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n("Bootlogo_ResolutionLabel"))
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Picker("", selection: $resolution) {
                                ForEach(ResolutionOption.allCases) { res in
                                    Text(res.rawValue).tag(res)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        // Sovitusmuoto
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n("Bootlogo_ScalingLabel"))
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Picker("", selection: $scalingMode) {
                                ForEach(ScalingMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        // Image-jakelu (Polku)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n("Bootlogo_DistroLabel"))
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Picker("", selection: $distro) {
                                ForEach(EnigmaImageDistro.allCases) { d in
                                    Text(d.title).tag(d)
                                }
                            }
                            .labelsHidden()
                            Text("\(L10n("Bootlogo_TargetPathLabel")) \(distro.resolvedBootlogoPath(for: state.activeBox))/\(selectedBootlogo.rawValue)")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Toimintopainikkeet
                        VStack(spacing: 10) {
                            Button(action: {
                                Task { await convertAndUpload() }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.up.circle.fill")
                                    Text(L10n("Bootlogo_InstallToBox"))
                                        .bold()
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(previewImage == nil || isProcessing)
                            
                            Button(action: saveImageToMac) {
                                Label(L10n("Bootlogo_SaveImageLocal"), systemImage: "photo.badge.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(previewImage == nil || isProcessing)
                            .help(L10n("Bootlogo_SaveImageHelp"))
                            
                            HStack(spacing: 8) {
                                Button(action: {
                                    Task { await saveMviToMac() }
                                }) {
                                    Label(L10n("Bootlogo_SaveMviLocal"), systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.bordered)
                                .disabled(previewImage == nil || isProcessing)
                                .help(L10n("Bootlogo_SaveLocalHelp"))
                                
                                Button(action: {
                                    Task { await restartGUI() }
                                }) {
                                    Label(L10n("Power_RestartGui"), systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .help(L10n("Bootlogo_RestartGuiHelp"))
                            }
                        }
                    }
                    .frame(width: 320)
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                }
                
                // MARK: - FFmpeg tilarivi
                HStack(spacing: 8) {
                    Circle()
                        .fill(FFmpegService.shared.isAvailable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    if FFmpegService.shared.isAvailable {
                        Text("\(L10n("Bootlogo_FfmpegAvailable")): \(FFmpegService.shared.ffmpegPath ?? "")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(L10n("Bootlogo_FfmpegNotFound"))
                            .font(.caption.bold())
                            .foregroundColor(.red)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
            }
            .padding(24)
        }
        .task {
            if let box = state.activeBox, box.distro == nil {
                await state.refreshBoxDetails(box)
            }
        }
    }
    
    // MARK: - Toiminnot
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            self.sourceImageURL = url
            if let img = NSImage(contentsOf: url) {
                self.previewImage = img
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        self.sourceImageURL = url
                        if let img = NSImage(contentsOf: url) {
                            self.previewImage = img
                        }
                    }
                }
            }
            return true
        }
        return false
    }
    
    private func grabScreenshotFromBox() async {
        guard let box = state.activeBox else { return }
        isProcessing = true
        state.showToast("Noudetaan kuva televisiosta")
        if let img = await EnigmaBoxService.shared.grabScreenshot(ip: box.ip, port: box.port, username: box.username, password: box.password) {
            // Tallennetaan tilapäistiedostoksi FFmpegiä varten
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("screenshot_\(UUID().uuidString).png")
            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: tempFile)
                self.sourceImageURL = tempFile
                self.previewImage = img
                state.showToast("Ruutukaappaus ladattu pohjakuvaksi!")
            }
        } else {
            state.showToast("Kuvakaappauksen nouto epäonnistui", isError: true)
        }
        isProcessing = false
    }
    
    private func fetchBootlogoFromBox() async {
        guard let box = state.activeBox, !box.ip.isEmpty else {
            state.showToast("Ei valittua boksia", isError: true)
            return
        }
        isProcessing = true
        state.showToast("Haetaan \(selectedBootlogo.rawValue) boksista (\(box.name))")
        
        let (mviDataOpt, error) = await EnigmaBoxService.shared.downloadBootlogo(
            ip: box.ip,
            port: box.port,
            fileName: selectedBootlogo.rawValue,
            distro: distro,
            box: box,
            username: box.username,
            password: box.password
        )
        
        guard let mviData = mviDataOpt, !mviData.isEmpty else {
            state.showToast("Kuvan nouto epäonnistui: \(error ?? "Tuntematon virhe")", isError: true)
            isProcessing = false
            return
        }
        
        state.showToast("Muunnetaan esikatselukuva")
        if let img = await FFmpegService.shared.convertMviToImage(mviData: mviData) {
            let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("bootlogo_box_\(UUID().uuidString).png")
            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: tempFile)
                self.sourceImageURL = tempFile
                self.previewImage = img
                self.generatedMviData = mviData
                state.showToast("\(selectedBootlogo.rawValue) ladattu boksista esikatseluun!")
            } else {
                self.previewImage = img
                state.showToast("\(selectedBootlogo.rawValue) ladattu!")
            }
        } else {
            state.showToast("MVI-kuvan muunto esikatseluksi epäonnistui", isError: true)
        }
        isProcessing = false
    }
    
    private func convertAndUpload() async {
        guard let box = state.activeBox, let url = sourceImageURL else { return }
        isProcessing = true
        state.showToast("Muunnetaan kuvaa .mvi -muotoon")
        
        guard let mvi = await FFmpegService.shared.convertImageToMvi(sourceURL: url, resolution: resolution, scaling: scalingMode) else {
            let detail = FFmpegService.shared.lastErrorMessage ?? "Muunnos epäonnistui"
            state.showToast("FFmpeg-muunnos epäonnistui: \(detail)", isError: true)
            isProcessing = false
            return
        }
        
        self.generatedMviData = mvi
        state.showToast("Siirretään \(selectedBootlogo.rawValue) boksille (\(box.name))")
        
        let res = await EnigmaBoxService.shared.uploadBootlogo(
            ip: box.ip,
            mviData: mvi,
            targetFileName: selectedBootlogo.rawValue,
            distro: distro,
            box: box,
            username: box.username,
            password: box.password
        )
        
        isProcessing = false
        if res.success {
            state.showToast("Käynnistyskuva siirretty onnistuneesti boksille!")
        } else {
            state.showToast("Siirto epäonnistui: \(res.error ?? "")", isError: true)
        }
    }
    
    private func saveImageToMac() {
        guard let img = previewImage else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        let baseName = selectedBootlogo.rawValue.replacingOccurrences(of: ".mvi", with: "")
        savePanel.nameFieldStringValue = "\(baseName).png"
        savePanel.canCreateDirectories = true
        savePanel.title = L10n("Bootlogo_SaveImageLocal")
        savePanel.prompt = L10n("Common_Save")
        
        if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            let ext = targetURL.pathExtension.lowercased()
            let isJpg = (ext == "jpg" || ext == "jpeg")
            let fileType: NSBitmapImageRep.FileType = isJpg ? .jpeg : .png
            let props: [NSBitmapImageRep.PropertyKey: Any] = isJpg ? [.compressionFactor: 0.95] : [:]
            
            // Skaalataan kuva käyttäjän valitseman resoluution ja sovitusmuodon (ScalingMode) mukaisesti
            let targetSize = CGSize(width: resolution.width, height: resolution.height)
            let scaledImage = scalingMode.renderScaledImage(img, targetSize: targetSize)
            
            if let tiff = scaledImage.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: fileType, properties: props) {
                do {
                    try data.write(to: targetURL)
                    state.showToast("Tallennettu: \(targetURL.lastPathComponent)")
                } catch {
                    state.showToast("Tallennus epäonnistui: \(error.localizedDescription)", isError: true)
                }
            } else {
                state.showToast("Kuvan muunto tallennukseen epäonnistui", isError: true)
            }
        }
    }
    
    private func saveMviToMac() async {
        isProcessing = true
        state.showToast("Valmistellaan MVI-tiedostoa")
        
        let mviToSave: Data?
        if let existing = generatedMviData {
            mviToSave = existing
        } else if let url = sourceImageURL {
            mviToSave = await FFmpegService.shared.convertImageToMvi(sourceURL: url, resolution: resolution, scaling: scalingMode)
        } else {
            mviToSave = nil
        }
        
        guard let mvi = mviToSave else {
            let detail = FFmpegService.shared.lastErrorMessage ?? "Muunnos epäonnistui"
            state.showToast("FFmpeg-muunnos epäonnistui: \(detail)", isError: true)
            isProcessing = false
            return
        }
        
        isProcessing = false
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "mvi") ?? .data]
        savePanel.nameFieldStringValue = selectedBootlogo.rawValue
        savePanel.prompt = L10n("Common_Save")
        
        if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            do {
                try mvi.write(to: targetURL)
                state.showToast("Tallennettu: \(targetURL.lastPathComponent)")
            } catch {
                state.showToast("Tallennus epäonnistui", isError: true)
            }
        }
    }
    
    private func restartGUI() async {
        guard let box = state.activeBox else { return }
        state.showToast("Käynnistetään Enigma2 GUI uudelleen")
        let ok = await EnigmaBoxService.shared.setPowerState(ip: box.ip, state: 3, port: box.port, username: box.username, password: box.password)
        if ok {
            state.showToast("GUI-käynnistyskomento lähetetty!")
        } else {
            state.showToast("Komento epäonnistui", isError: true)
        }
    }
}
