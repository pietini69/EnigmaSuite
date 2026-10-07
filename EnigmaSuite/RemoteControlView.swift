import SwiftUI
import AppKit
import Combine

struct RemoteControlView: View {
    @EnvironmentObject var state: EnigmaSuiteState
    @EnvironmentObject var l10n: LocalizationManager
    
    // Live-tiedot
    @State private var currentChannel: String = ""
    @State private var currentTitle: String = ""
    @State private var currentDesc: String = ""
    @State private var currentStart: Double = 0
    @State private var currentDuration: Int = 0
    @State private var liveScreenshot: NSImage?
    @State private var isRefreshingLive: Bool = false
    
    // Viestin lähetys
    @State private var showMessageDialog = false
    @State private var messageText = ""
    @State private var messageTimeout = 8
    
    // Ajastin live-tietojen päivitykselle
    let refreshTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - NYT TOISTETAAN & LIVE ESIKATSELU
                nowPlayingCard
                
                // MARK: - KAUKOSÄÄDIN
                remoteControllerCard
            }
            .padding(24)
        }
        .task {
            await refreshNowPlaying()
        }
        .onChange(of: state.activeBox) { _, _ in
            liveScreenshot = nil
            currentChannel = ""
            currentTitle = ""
            currentDesc = ""
            Task { await refreshNowPlaying() }
        }
        .onReceive(refreshTimer) { _ in
            Task { await refreshNowPlaying() }
        }
        .sheet(isPresented: $showMessageDialog) {
            sendMessageSheet
        }
    }
    
    // MARK: - Now Playing -kortti
    private var nowPlayingCard: some View {
        HStack(alignment: .top, spacing: 18) {
            // Live-kuvakaappaus / TV ruutu
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.15))
                    .frame(width: 240, height: 135)
                
                if let img = liveScreenshot {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 240, height: 135)
                        .cornerRadius(10)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "tv")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text(L10n("Remote_NoPreview"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if isRefreshingLive {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .overlay(
                Button(action: { Task { await grabScreenshot() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.bold())
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(L10n("Remote_RefreshScreenshot"))
                .padding(6),
                alignment: .topTrailing
            )
            
            // Ohjelman tiedot
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let box = state.activeBox {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(box.isOnline ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(box.name)
                                .font(.subheadline.bold())
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Button(action: { showMessageDialog = true }) {
                        Label(L10n("Remote_SendMessage"), systemImage: "message")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                
                Text(currentChannel.isEmpty ? L10n("Remote_NoActiveChannel") : currentChannel)
                    .font(.title3.bold())
                    .lineLimit(1)
                
                Text(currentTitle.isEmpty ? L10n("Remote_NoEpgData") : currentTitle)
                    .font(.headline)
                    .foregroundColor(.accentColor)
                    .lineLimit(1)
                
                if !currentDesc.isEmpty {
                    Text(currentDesc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                if currentChannel.contains("Valmiustila") || currentChannel.contains("Standby") {
                    Button(action: { sendKey("KEY_POWER") }) {
                        Label(L10n("Remote_StandbyWakeup"), systemImage: "power")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .padding(.top, 4)
                } else if currentChannel == L10n("Remote_NoActiveChannel") || currentChannel == "Ei aktiivista kanavaa" {
                    HStack(spacing: 8) {
                        Button(action: { sendKey("KEY_TV") }) {
                            Label(L10n("Remote_OpenTvMode"), systemImage: "tv")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { sendKey("KEY_1") }) {
                            Label(L10n("Remote_Channel1"), systemImage: "play.fill")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
                
                // Aikajana / Edistyminen
                if currentDuration > 0 {
                    let elapsed = max(0, Date().timeIntervalSince1970 - currentStart)
                    let prog = min(1.0, max(0.0, elapsed / Double(currentDuration)))
                    VStack(spacing: 3) {
                        ProgressView(value: prog)
                            .progressViewStyle(.linear)
                        HStack {
                            let startDate = Date(timeIntervalSince1970: currentStart)
                            let endDate = startDate.addingTimeInterval(TimeInterval(currentDuration))
                            Text(startDate.formatted(.dateTime.hour().minute()))
                            Spacer()
                            Text(endDate.formatted(.dateTime.hour().minute()))
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
    
    // MARK: - Kaukosäädin
    private var remoteControllerCard: some View {
        VStack(spacing: 16) {
            Text(L10n("Remote_Title"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 14) {
                // Rivi 1: Virta, Mute, TV/Radio, Aspect
                HStack(spacing: 16) {
                    remoteButton(title: L10n("Remote_TooltipPower"), icon: "power", color: .red) { sendKey("KEY_POWER") }
                    remoteButton(title: L10n("Remote_TooltipMute"), icon: "speaker.slash.fill") { sendKey("KEY_MUTE") }
                    remoteButton(title: L10n("Remote_TooltipTv"), icon: "antenna.radiowaves.left.and.right") { sendKey("KEY_TV") }
                    remoteButton(title: L10n("Remote_TooltipMode"), icon: "rectangle.inset.filled") { sendKey("KEY_MODE") }
                }
                
                Divider().padding(.horizontal, 20)
                
                // Numeronäppäimistö (1-9, 0)
                VStack(spacing: 10) {
                    HStack(spacing: 16) {
                        numButton("1") { sendKey("KEY_1") }
                        numButton("2") { sendKey("KEY_2") }
                        numButton("3") { sendKey("KEY_3") }
                    }
                    HStack(spacing: 16) {
                        numButton("4") { sendKey("KEY_4") }
                        numButton("5") { sendKey("KEY_5") }
                        numButton("6") { sendKey("KEY_6") }
                    }
                    HStack(spacing: 16) {
                        numButton("7") { sendKey("KEY_7") }
                        numButton("8") { sendKey("KEY_8") }
                        numButton("9") { sendKey("KEY_9") }
                    }
                    HStack(spacing: 16) {
                        remoteButton(title: L10n("Channels_Down"), icon: "backward.end.fill") { sendKey("KEY_PREVIOUS") }
                        numButton("0") { sendKey("KEY_0") }
                        remoteButton(title: L10n("Channels_Up"), icon: "forward.end.fill") { sendKey("KEY_NEXT") }
                    }
                }
                
                Divider().padding(.horizontal, 20)
                
                // Ristikko-ohjain (D-Pad & OK) + Äänenvoimakkuus & Kanava
                HStack(spacing: 24) {
                    // Vol +/-
                    VStack(spacing: 10) {
                        remoteButton(title: "Vol +", icon: "speaker.plus.fill") { sendKey("KEY_VOLUMEUP") }
                        Text("VOL").font(.caption2.bold()).foregroundColor(.secondary)
                        remoteButton(title: "Vol -", icon: "speaker.minus.fill") { sendKey("KEY_VOLUMEDOWN") }
                    }
                    
                    // D-Pad ympyrä
                    VStack(spacing: 8) {
                        remoteButton(title: L10n("Channels_Up"), icon: "chevron.up") { sendKey("KEY_UP") }
                        HStack(spacing: 8) {
                            remoteButton(title: L10n("Remote_Left"), icon: "chevron.left") { sendKey("KEY_LEFT") }
                            Button(action: { sendKey("KEY_OK") }) {
                                Text("OK")
                                    .font(.headline.bold())
                                    .frame(width: 58, height: 58)
                                    .background(Color.accentColor.opacity(0.2))
                                    .foregroundColor(.accentColor)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            remoteButton(title: L10n("Remote_Right"), icon: "chevron.right") { sendKey("KEY_RIGHT") }
                        }
                        remoteButton(title: L10n("Channels_Down"), icon: "chevron.down") { sendKey("KEY_DOWN") }
                    }
                    
                    // Kanava +/-
                    VStack(spacing: 10) {
                        remoteButton(title: "Ch +", icon: "chevron.up.circle.fill") { sendKey("KEY_CHANNELUP") }
                        Text("CH").font(.caption2.bold()).foregroundColor(.secondary)
                        remoteButton(title: "Ch -", icon: "chevron.down.circle.fill") { sendKey("KEY_CHANNELDOWN") }
                    }
                }
                
                Divider().padding(.horizontal, 20)
                
                // Toimintonäppäimet: Valikko, Poistu, Info, EPG
                HStack(spacing: 14) {
                    actionButton(title: L10n("Remote_TooltipMenu"), icon: "line.3.horizontal") { sendKey("KEY_MENU") }
                    actionButton(title: L10n("Remote_TooltipExit"), icon: "xmark.circle") { sendKey("KEY_EXIT") }
                    actionButton(title: L10n("Remote_TooltipInfo"), icon: "info.circle") { sendKey("KEY_INFO") }
                    actionButton(title: L10n("Remote_TooltipEpg"), icon: "list.bullet.rectangle") { sendKey("KEY_EPG") }
                    actionButton(title: L10n("Remote_TooltipAudio"), icon: "waveform") { sendKey("KEY_AUDIO") }
                    actionButton(title: L10n("Remote_TooltipSubtitle"), icon: "captions.bubble") { sendKey("KEY_SUBTITLE") }
                }
                
                // Värinäppäimet (Punainen, Vihreä, Keltainen, Sininen)
                HStack(spacing: 16) {
                    colorButton(color: .red, label: L10n("Remote_Red")) { sendKey("KEY_RED") }
                    colorButton(color: .green, label: L10n("Remote_Green")) { sendKey("KEY_GREEN") }
                    colorButton(color: .yellow, label: L10n("Remote_Yellow")) { sendKey("KEY_YELLOW") }
                    colorButton(color: .blue, label: L10n("Remote_Blue")) { sendKey("KEY_BLUE") }
                }
                .padding(.top, 4)
                
                // Toistonohjaus (Media)
                HStack(spacing: 14) {
                    remoteButton(title: L10n("Remote_Rewind"), icon: "backward.fill") { sendKey("KEY_REWIND") }
                    remoteButton(title: L10n("Remote_Play"), icon: "play.fill") { sendKey("KEY_PLAY") }
                    remoteButton(title: L10n("Remote_Pause"), icon: "pause.fill") { sendKey("KEY_PAUSE") }
                    remoteButton(title: L10n("Remote_FastForward"), icon: "forward.fill") { sendKey("KEY_FASTFORWARD") }
                    remoteButton(title: L10n("Remote_Stop"), icon: "stop.fill") { sendKey("KEY_STOP") }
                    remoteButton(title: L10n("Remote_Record"), icon: "circle.fill", color: .red) { sendKey("KEY_RECORD") }
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        }
    }
    
    // MARK: - Painiketyylit
    private func numButton(_ number: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(number)
                .font(.title2.bold())
                .frame(width: 58, height: 42)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    
    private func remoteButton(title: String, icon: String, color: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 48, height: 40)
                .background(Color(nsColor: .windowBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(title)
    }
    
    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.caption2.bold())
            }
            .frame(width: 54, height: 46)
            .background(Color(nsColor: .windowBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
    
    private func colorButton(color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Capsule()
                    .fill(color)
                    .frame(width: 44, height: 12)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(label)
    }
    
    // MARK: - Toiminnot
    private func sendKey(_ key: String) {
        guard let box = state.activeBox else {
            state.showToast(L10n("Toast_NoActiveBox"), isError: true)
            return
        }
        Task {
            let ok = await EnigmaBoxService.shared.sendRemoteKey(ip: box.ip, key: key, port: box.port, username: box.username, password: box.password)
            if !ok {
                state.showToast(L10n("Toast_RemoteKeyFailed", key), isError: true)
            } else {
                if key == "KEY_POWER" {
                    state.showToast(L10n("Toast_PowerPressed"))
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await refreshNowPlaying()
                    await state.refreshBoxDetails(box)
                } else if key == "KEY_CHANNELUP" || key == "KEY_CHANNELDOWN" || key == "KEY_TV" || key.starts(with: "KEY_") {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await refreshNowPlaying()
                }
            }
        }
    }
    
    private func refreshNowPlaying() async {
        guard let box = state.activeBox, !box.ip.isEmpty else { return }
        isRefreshingLive = true
        async let nowTask = EnigmaBoxService.shared.fetchNowPlaying(ip: box.ip, port: box.port, username: box.username, password: box.password)
        async let grabTask = EnigmaBoxService.shared.grabScreenshot(ip: box.ip, port: box.port, username: box.username, password: box.password)
        
        let (info, img) = await (nowTask, grabTask)
        
        if let info = info {
            self.currentChannel = info.channel
            self.currentTitle = info.eventTitle
            self.currentDesc = info.desc
            self.currentStart = info.start
            self.currentDuration = info.duration
        } else {
            self.currentChannel = L10n("Remote_NoActiveChannel")
            self.currentTitle = L10n("Remote_NoActivePlayback")
            self.currentDesc = L10n("Remote_NoPlaybackDesc")
            self.currentStart = 0
            self.currentDuration = 0
        }
        
        if let img = img {
            self.liveScreenshot = img
        }
        isRefreshingLive = false
    }
    
    private func grabScreenshot() async {
        guard let box = state.activeBox else { return }
        isRefreshingLive = true
        if let img = await EnigmaBoxService.shared.grabScreenshot(ip: box.ip, port: box.port, username: box.username, password: box.password) {
            self.liveScreenshot = img
            state.showToast(L10n("Toast_ScreenshotUpdated"))
        } else {
            state.showToast(L10n("Toast_ScreenshotFailed"), isError: true)
        }
        isRefreshingLive = false
    }
    
    // MARK: - Viestin lähetys Sheet
    private var sendMessageSheet: some View {
        VStack(spacing: 16) {
            Text(L10n("Dialog_SendMessageTitle"))
                .font(.headline)
            
            TextField(L10n("Dialog_SendMessageDesc"), text: $messageText)
                .textFieldStyle(.roundedBorder)
            
            Stepper("\(L10n("Dialog_TimeoutLabel")) \(messageTimeout) s", value: $messageTimeout, in: 2...60)
            
            HStack {
                Button(L10n("Common_Cancel")) {
                    showMessageDialog = false
                    messageText = ""
                }
                Spacer()
                Button(L10n("Dialog_SendToTv")) {
                    if let box = state.activeBox, !messageText.isEmpty {
                        Task {
                            let ok = await EnigmaBoxService.shared.sendMessage(ip: box.ip, text: messageText, timeout: messageTimeout, port: box.port, username: box.username, password: box.password)
                            if ok {
                                state.showToast(L10n("Toast_MessageSent"))
                            } else {
                                state.showToast(L10n("Toast_MessageFailed"), isError: true)
                            }
                            showMessageDialog = false
                            messageText = ""
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
