import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: EnigmaSuiteState
    @EnvironmentObject var l10n: LocalizationManager
    
    var body: some View {
        NavigationSplitView {
            // MARK: - Sivupalkki (Sidebar)
            List(selection: $state.selectedTab) {
                Section(l10n.t("Nav_GroupTools")) {
                    Label(l10n.t(NavigationTab.remote.localizationKey), systemImage: NavigationTab.remote.icon)
                        .tag(NavigationTab.remote)
                    Label(l10n.t(NavigationTab.timersAndMovies.localizationKey), systemImage: NavigationTab.timersAndMovies.icon)
                        .tag(NavigationTab.timersAndMovies)
                    Label(l10n.t(NavigationTab.channels.localizationKey), systemImage: NavigationTab.channels.icon)
                        .tag(NavigationTab.channels)
                    Label(l10n.t(NavigationTab.settingsSync.localizationKey), systemImage: NavigationTab.settingsSync.icon)
                        .tag(NavigationTab.settingsSync)
                    Label(l10n.t(NavigationTab.bootlogo.localizationKey), systemImage: NavigationTab.bootlogo.icon)
                        .tag(NavigationTab.bootlogo)
                    Label(l10n.t(NavigationTab.imageManager.localizationKey), systemImage: NavigationTab.imageManager.icon)
                        .tag(NavigationTab.imageManager)
                    Label(l10n.t(NavigationTab.boxManager.localizationKey), systemImage: NavigationTab.boxManager.icon)
                        .tag(NavigationTab.boxManager)
                }
                
                Section(l10n.t("Nav_GroupCommunity")) {
                    Label(l10n.t(NavigationTab.support.localizationKey), systemImage: NavigationTab.support.icon)
                        .tag(NavigationTab.support)
                }
                
                Section(l10n.t("Nav_ActiveBoxHeader")) {
                    if let box = state.activeBox {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(box.isOnline ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(box.name)
                                    .font(.subheadline.bold())
                                Text(box.ip)
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text(l10n.t("Common_NoActiveBox"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
            .id(l10n.effectiveLanguage)
            
        } detail: {
            // MARK: - Päänäkymä valitun välilehden mukaan
            ZStack(alignment: .bottom) {
                switch state.selectedTab ?? .remote {
                case .remote:
                    RemoteControlView()
                case .timersAndMovies:
                    TimersAndMoviesView()
                case .channels:
                    ChannelManagerView()
                case .settingsSync:
                    SettingsSyncView()
                case .bootlogo:
                    BootlogoView()
                case .imageManager:
                    ImageManagerView()
                case .boxManager:
                    BoxManagerView()
                case .support:
                    SupportView()
                }
                
                // Globaali Toast-ilmoitus alalaidassa
                if !state.toastMessage.isEmpty {
                    Text(state.toastMessage)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(state.toastIsError ? Color.red.opacity(0.9) : Color.black.opacity(0.85))
                        .clipShape(Capsule())
                        .shadow(radius: 8)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: state.toastMessage)
            .id(l10n.effectiveLanguage)
        }
        .toolbar {
            // Aktiivisen laitteen valitsin
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 6) {
                    Picker("", selection: $state.activeBox) {
                        ForEach(state.boxes) { box in
                            Text("\(box.name) (\(box.ip))").tag(Optional(box))
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 200, idealWidth: 230, maxWidth: 280)
                    
                    if let box = state.activeBox {
                        Circle()
                            .fill(box.isOnline ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                            .help(box.isOnline ? l10n.t("Common_Refresh") : l10n.t("Common_NoConnection"))
                    }
                }
            }
            
            // Toiminnot oikealla: Päivitysnappi, Kielenvalitsin & Virtavalikko
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: {
                    Task {
                        if let box = state.activeBox {
                            await state.refreshBoxDetails(box)
                        } else {
                            await state.autoDiscoverBoxes(showFeedback: true)
                        }
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help(l10n.t("Header_RefreshTooltip"))
                
                // Kielivalitsin
                Menu {
                    Button(action: { l10n.setLanguage("auto") }) {
                        HStack {
                            Text(l10n.t("Lang_Auto"))
                            if l10n.currentConfiguredLanguage == "auto" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Divider()
                    Button(action: { l10n.setLanguage("fi") }) {
                        HStack {
                            Text(l10n.t("Lang_Fi"))
                            if l10n.currentConfiguredLanguage == "fi" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Button(action: { l10n.setLanguage("en") }) {
                        HStack {
                            Text(l10n.t("Lang_En"))
                            if l10n.currentConfiguredLanguage == "en" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    Label(l10n.t("Header_Language"), systemImage: "globe")
                }
                .help(l10n.t("Header_LanguageTooltip"))
                
                // Virtavalikko
                Menu {
                    Button(action: { powerCommand(0) }) {
                        Label(l10n.t("Power_Standby"), systemImage: "power")
                    }
                    Button(action: { powerCommand(3) }) {
                        Label(l10n.t("Power_RestartGui"), systemImage: "arrow.clockwise")
                    }
                    Button(action: { powerCommand(2) }) {
                        Label(l10n.t("Power_Reboot"), systemImage: "restart")
                    }
                    Divider()
                    Button(action: { powerCommand(1) }) {
                        Label(l10n.t("Power_DeepStandby"), systemImage: "power.circle")
                    }
                } label: {
                    Label(l10n.t("Header_PowerMenu"), systemImage: "power")
                }
                .help(l10n.t("Header_PowerMenuTooltip"))
            }
        }
        .navigationTitle("")
    }
    
    private func powerCommand(_ stateCode: Int) {
        guard let box = state.activeBox else { return }
        Task {
            state.showToast(L10n("Toast_SendingPower"))
            let ok = await EnigmaBoxService.shared.setPowerState(ip: box.ip, state: stateCode, port: box.port, username: box.username, password: box.password)
            if ok {
                state.showToast(L10n("Toast_PowerExecuted"))
            } else {
                state.showToast(L10n("Toast_PowerFailed"), isError: true)
            }
        }
    }
}
