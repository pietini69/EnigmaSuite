import SwiftUI

struct ChannelManagerView: View {
    @EnvironmentObject var state: EnigmaSuiteState
    @EnvironmentObject var l10n: LocalizationManager
    
    // Vakiot
    private let allChannelsTag = "__ALL_CHANNELS__"
    
    // Tila
    @State private var isRadioMode: Bool = false
    @State private var bouquets: [Bouquet] = []
    @State private var selectedSourceId: String = ""
    @State private var channels: [Channel] = []
    @State private var allChannelsCount: Int = 0
    @State private var selectedChannel: Channel?
    @State private var epgEvents: [EPGEvent] = []
    @State private var isLoadingBouquets: Bool = false
    @State private var isLoadingChannels: Bool = false
    @State private var isLoadingEPG: Bool = false
    
    // Monivalinta (Valitse kaikki / poista)
    @State private var selectedChannelIds: Set<String> = []
    
    // Toiminnot & Dialogit
    @State private var showNewBouquetAlert: Bool = false
    @State private var newBouquetName: String = ""
    @State private var bouquetToDelete: Bouquet?
    @State private var showDeleteBouquetAlert: Bool = false
    @State private var channelToDelete: Channel?
    @State private var showDeleteChannelAlert: Bool = false
    @State private var showDeleteSelectedAlert: Bool = false
    @State private var showDeleteAllAlert: Bool = false
    
    // Lamedb Globaalit poistot (Kaikki kanavat)
    @State private var channelToDeleteFromLamedb: Channel?
    @State private var showDeleteSingleLamedbAlert: Bool = false
    @State private var showDeleteSelectedLamedbAlert: Bool = false
    @State private var showDeleteAllLamedbAlert: Bool = false
    @State private var isPerformingLamedbOperation: Bool = false
    @State private var lamedbProgressText: String = ""
    
    // Haku
    @State private var searchText: String = ""
    
    // Apumuuttujat
    private var isShowingAllChannels: Bool {
        return selectedSourceId == allChannelsTag
    }
    
    private var currentBouquet: Bouquet? {
        if isShowingAllChannels { return nil }
        return bouquets.first(where: { $0.id == selectedSourceId })
    }
    
    private var filteredChannels: [Channel] {
        if searchText.isEmpty { return channels }
        return channels.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var isAllFilteredSelected: Bool {
        guard !filteredChannels.isEmpty else { return false }
        return filteredChannels.allSatisfy { selectedChannelIds.contains($0.id) }
    }
    
    private var moveAction: ((IndexSet, Int) -> Void)? {
        if isShowingAllChannels || !searchText.isEmpty {
            return nil
        }
        return onMoveChannels
    }
    
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                sidebarView
                    .frame(width: 230)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                
                Divider()
                
                channelListView
                    .frame(minWidth: 380, idealWidth: 420, maxWidth: 520)
                
                Divider()
                
                epgDetailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            if isPerformingLamedbOperation {
                Color.black.opacity(0.65)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.4)
                    
                    Text("Päivitetään digiboksin kanavatietokantaa")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(lamedbProgressText)
                        .font(.subheadline)
                        .foregroundColor(.yellow)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Text("Boksin käyttöliittymä käynnistetään uudelleen (init 4 -> init 3).")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
                .shadow(radius: 20)
                .frame(maxWidth: 420)
            }
        }
        .task {
            await loadInitialData()
        }
        .onChange(of: isRadioMode) { _, _ in
            Task { await loadInitialData() }
        }
        .onChange(of: state.activeBox) { _, _ in
            Task { await loadInitialData() }
        }
        .onChange(of: selectedSourceId) { _, _ in
            selectedChannelIds.removeAll()
            Task { await loadChannelsForCurrentSelection() }
        }
        .onChange(of: selectedChannel) { _, newC in
            if let ch = newC {
                Task { await fetchEPG(for: ch) }
            } else {
                epgEvents = []
            }
        }
    }
    
    // MARK: - SARAKE 1: Sivupalkki (Kaikki kanavat & Suosikit)
    private var sidebarView: some View {
        VStack(spacing: 0) {
            Picker("", selection: $isRadioMode) {
                Label(L10n("Channels_TvMode"), systemImage: "tv").tag(false)
                Label(L10n("Channels_RadioMode"), systemImage: "radio").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(12)
            
            Divider()
            
            if isLoadingBouquets {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedSourceId) {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.accentColor)
                            Text(isRadioMode ? L10n("Channels_RadioMode") : L10n("Channels_AllChannelsItem"))
                                .font(.body)
                            Spacer()
                            if allChannelsCount > 0 {
                                Text("\(allChannelsCount)")
                                    .font(.caption2.bold())
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSourceId = allChannelsTag
                        }
                        .tag(allChannelsTag)
                    } header: {
                        Text(L10n("Channels_AllChannelsHeader"))
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                    
                    Section {
                        ForEach(bouquets) { b in
                            HStack(spacing: 8) {
                                Image(systemName: isRadioMode ? "radio" : "tv")
                                    .foregroundColor(.accentColor)
                                Text(b.name)
                                    .font(.body)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Button(action: {
                                    bouquetToDelete = b
                                    showDeleteBouquetAlert = true
                                }) {
                                    Image(systemName: "trash")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help(L10n("Common_Delete"))
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedSourceId = b.id
                            }
                            .tag(b.id)
                            .contextMenu {
                                Button(role: .destructive) {
                                    bouquetToDelete = b
                                    showDeleteBouquetAlert = true
                                } label: {
                                    Label(L10n("Common_Delete"), systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("\(L10n("Channels_BouquetsHeader")) (\(bouquets.count))")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                newBouquetName = ""
                                showNewBouquetAlert = true
                            }) {
                                Image(systemName: "plus.circle")
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help(L10n("Channels_NewBouquetTooltip"))
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .alert("Uusi suosikkilista", isPresented: $showNewBouquetAlert) {
            TextField("Listan nimi (esim. Urheilu)", text: $newBouquetName)
            Button("Luo") {
                Task { await createBouquet() }
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Syötä nimi uudelle \(isRadioMode ? "radio" : "TV")-suosikkilistalle:")
        }
        .alert("Poista suosikkilista?", isPresented: $showDeleteBouquetAlert, presenting: bouquetToDelete) { b in
            Button("Poista", role: .destructive) {
                Task { await confirmDeleteBouquet(b) }
            }
            Button("Peruuta", role: .cancel) {}
        } message: { b in
            Text("Haluatko varmasti poistaa suosikkilistan '\(b.name)' boksista?")
        }
    }
    
    // MARK: - SARAKE 2: Kanavalista
    private var channelListView: some View {
        VStack(spacing: 0) {
            // Yläpalkki
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(L10n("Common_Search"), text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider().frame(height: 16)
                    
                    Button(action: {
                        Task { await reloadCurrentList() }
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n("Common_Refresh"))
                }
                .padding(7)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                
                // Toimintopalkki
                HStack(spacing: 6) {
                    Button(action: {
                        if isAllFilteredSelected {
                            deselectAllChannels()
                        } else {
                            selectAllChannels()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: isAllFilteredSelected ? "checkmark.circle.fill" : "circle")
                            Text(isAllFilteredSelected ? L10n("Common_Close") : L10n("Sync_SelectAll"))
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    if !selectedChannelIds.isEmpty {
                        Text("\(selectedChannelIds.count) valittu")
                            .font(.caption2.bold())
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                    
                    Spacer()
                    
                    if !isShowingAllChannels {
                        if !selectedChannelIds.isEmpty {
                            Button(action: {
                                showDeleteSelectedAlert = true
                            }) {
                                Label("Poista", systemImage: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Poista valitut kanavat suosikkilistalta")
                        } else {
                            Button(action: {
                                showDeleteAllAlert = true
                            }) {
                                Label("Tyhjennä lista", systemImage: "trash.slash")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(channels.isEmpty)
                            .help("Poista kaikki kanavat tältä suosikkilistalta")
                        }
                    } else {
                        if !selectedChannelIds.isEmpty {
                            if !bouquets.isEmpty {
                                Menu {
                                    ForEach(bouquets) { b in
                                        Button(b.name) {
                                            Task { await addSelectedChannelsToBouquet(bouquet: b) }
                                        }
                                    }
                                } label: {
                                    Label("Suosikit", systemImage: "plus.circle")
                                        .font(.caption)
                                }
                                .menuStyle(.borderedButton)
                                .controlSize(.small)
                            }
                            
                            Button(action: {
                                showDeleteSelectedLamedbAlert = true
                            }) {
                                Label("Poista", systemImage: "trash")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Poista valitut kanavat pysyvästi digiboksin kanavatietokannasta (lamedb)")
                        } else {
                            Button(action: {
                                showDeleteAllLamedbAlert = true
                            }) {
                                Label("Poista kaikki boksista", systemImage: "trash.slash")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(channels.isEmpty)
                            .help("Poista kaikki kanavat digiboksin lamedb-tietokannasta (init 4/3)")
                        }
                    }
                }
            }
            .padding(10)
            
            Divider()
            
            if isLoadingChannels {
                ProgressView("Ladataan kanavia")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredChannels.isEmpty {
                emptyChannelsView
            } else {
                List(selection: $selectedChannel) {
                    ForEach(Array(filteredChannels.enumerated()), id: \.element.id) { index, channel in
                        channelRow(channel: channel, index: index)
                            .tag(channel)
                            .padding(.vertical, 3)
                            .contextMenu {
                                channelContextMenu(channel: channel, index: index)
                            }
                    }
                    .onMove(perform: moveAction)
                }
            }
        }
        .alert("Poista kanava listalta?", isPresented: $showDeleteChannelAlert, presenting: channelToDelete) { ch in
            Button("Poista", role: .destructive) {
                Task { await confirmDeleteChannel(ch) }
            }
            Button("Peruuta", role: .cancel) {}
        } message: { ch in
            Text("Haluatko poistaa kanavan '\(ch.name)' suosikkilistalta '\(currentBouquet?.name ?? "")'?")
        }
        .alert("Poista valitut kanavat?", isPresented: $showDeleteSelectedAlert) {
            Button("Poista \(selectedChannelIds.count) kanavaa", role: .destructive) {
                Task { await confirmDeleteSelectedChannels() }
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Haluatko varmasti poistaa \(selectedChannelIds.count) valittua kanavaa suosikkilistalta '\(currentBouquet?.name ?? "")'?")
        }
        .alert("Poista kaikki kanavat?", isPresented: $showDeleteAllAlert) {
            Button("Poista kaikki kanavat", role: .destructive) {
                Task { await confirmDeleteAllChannels() }
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Haluatko varmasti poistaa kaikki \(channels.count) kanavaa suosikkilistalta '\(currentBouquet?.name ?? "")'?")
        }
        .alert("Poista kanava pysyvästi boksista?", isPresented: $showDeleteSingleLamedbAlert, presenting: channelToDeleteFromLamedb) { ch in
            Button("Poista pysyvästi (init 4/3)", role: .destructive) {
                Task { await deleteSingleChannelFromLamedb(ch) }
            }
            Button("Peruuta", role: .cancel) {}
        } message: { ch in
            Text("Haluatko varmasti poistaa kanavan '\(ch.name)' pysyvästi digiboksin kanavatietokannasta (lamedb)?\n\nTämä pysäyttää boksin käyttöliittymän (init 4), muokkaa lamedb-tiedostoa ja käynnistää käyttöliittymän uudelleen (init 3).")
        }
        .alert("Poista valitut kanavat boksista?", isPresented: $showDeleteSelectedLamedbAlert) {
            Button("Poista \(selectedChannelIds.count) kanavaa (init 4/3)", role: .destructive) {
                Task { await deleteSelectedChannelsFromLamedb() }
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Haluatko varmasti poistaa \(selectedChannelIds.count) valittua kanavaa pysyvästi digiboksin lamedb-tietokannasta?\n\nTämä pysäyttää boksin käyttöliittymän (init 4), poistaa kanavat ja käynnistää käyttöliittymän uudelleen (init 3).")
        }
        .alert("Poista KAIKKI kanavat boksista?", isPresented: $showDeleteAllLamedbAlert) {
            Button("Tyhjennä kaikki kanavat (init 4/3)", role: .destructive) {
                Task { await deleteAllChannelsFromLamedb() }
            }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("VAROITUS: Haluatko varmasti poistaa kaikki \(channels.count) kanavaa pysyvästi digiboksin lamedb-tietokannasta?\n\nTämä tyhjentää viritetyt kanavat boksista (init 4/3). Kanavat pitää virittää uudelleen jos haluat ne takaisin.")
        }
    }
    
    private var emptyChannelsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tv.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(isShowingAllChannels ? "Ei kanavia löytynyt" : "Suosikkilista on tyhjä")
                .foregroundColor(.secondary)
            if isShowingAllChannels {
                Text("Tarkista virittimen kanavahaku boksilla.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Voit lisätä kanavia 'Kaikki kanavat' -näkymästä.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Kanavarivin esitys
    @ViewBuilder
    private func channelRow(channel: Channel, index: Int) -> some View {
        HStack(spacing: 8) {
            // Valintaruutu
            Button(action: {
                toggleChannelSelection(channel.id)
            }) {
                Image(systemName: selectedChannelIds.contains(channel.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedChannelIds.contains(channel.id) ? .accentColor : .secondary)
                    .font(.body)
            }
            .buttonStyle(.borderless)
            .help("Valitse kanava")
            
            // Järjestysnumero
            Text("\(index + 1)")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .frame(width: 26, alignment: .trailing)
            
            // Nimi
            Text(channel.name)
                .font(.body)
                .lineLimit(1)
            
            Spacer()
            
            if !isShowingAllChannels {
                // Järjestelynuolet
                Button(action: {
                    Task { await moveChannelItem(channel: channel, fromIndex: index, toIndex: index - 1) }
                }) {
                    Image(systemName: "chevron.up")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .help("Siirrä ylemmäs")
                
                Button(action: {
                    Task { await moveChannelItem(channel: channel, fromIndex: index, toIndex: index + 1) }
                }) {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .disabled(index == channels.count - 1)
                .help("Siirrä alemmas")
            } else {
                // Lisää suosikkiin
                Menu {
                    ForEach(bouquets) { b in
                        Button(b.name) {
                            Task { await addChannelToBouquet(channel, bouquet: b) }
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 20)
                .help("Lisää suosikkilistaan")
            }
            
            // Vaihda kanavalle (Zap)
            Button(action: {
                zapTo(channel)
            }) {
                Image(systemName: "tv.badge.wifi")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Vaihda televisio tälle kanavalle")
            
            // Toista Macilla (VLC)
            Button(action: {
                state.openInVLC(sRef: channel.id)
            }) {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Toista striimi Macilla / VLC:llä")
            
            if !isShowingAllChannels {
                // Poista kanava suosikkilistalta
                Button(action: {
                    channelToDelete = channel
                    showDeleteChannelAlert = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Poista kanava suosikkilistalta")
            } else {
                // Poista kanava boksista (lamedb)
                Button(action: {
                    channelToDeleteFromLamedb = channel
                    showDeleteSingleLamedbAlert = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Poista kanava pysyvästi digiboksin kanavatietokannasta (lamedb)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedChannel = channel
        }
    }
    
    // MARK: - Kanavan kontekstivalikko
    @ViewBuilder
    private func channelContextMenu(channel: Channel, index: Int) -> some View {
        Button {
            zapTo(channel)
        } label: {
            Label("Vaihda kanavalle", systemImage: "tv.badge.wifi")
        }
        
        Button {
            state.openInVLC(sRef: channel.id)
        } label: {
            Label("Toista Macilla (VLC)", systemImage: "play.circle")
        }
        
        Divider()
        
        if !isShowingAllChannels {
            Button {
                Task { await moveChannelItem(channel: channel, fromIndex: index, toIndex: 0) }
            } label: {
                Label("Siirrä alkuun (sijalle 1)", systemImage: "arrow.up.to.line")
            }
            .disabled(index == 0)
            
            Button {
                Task { await moveChannelItem(channel: channel, fromIndex: index, toIndex: index - 1) }
            } label: {
                Label("Siirrä ylemmäs", systemImage: "chevron.up")
            }
            .disabled(index == 0)
            
            Button {
                Task { await moveChannelItem(channel: channel, fromIndex: index, toIndex: index + 1) }
            } label: {
                Label("Siirrä alemmas", systemImage: "chevron.down")
            }
            .disabled(index == channels.count - 1)
            
            Button {
                Task { await moveChannelItem(channel: channel, fromIndex: index, toIndex: channels.count - 1) }
            } label: {
                Label("Siirrä loppuun", systemImage: "arrow.down.to.line")
            }
            .disabled(index == channels.count - 1)
            
            Divider()
            
            Button(role: .destructive) {
                channelToDelete = channel
                showDeleteChannelAlert = true
            } label: {
                Label("Poista kanava listalta", systemImage: "trash")
            }
        } else {
            Menu("Lisää suosikkilistaan") {
                ForEach(bouquets) { b in
                    Button(b.name) {
                        Task { await addChannelToBouquet(channel, bouquet: b) }
                    }
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                channelToDeleteFromLamedb = channel
                showDeleteSingleLamedbAlert = true
            } label: {
                Label("Poista pysyvästi boksista (lamedb)", systemImage: "trash")
            }
        }
    }
    
    // MARK: - SARAKE 3: Kanavan EPG & Tiedot
    private var epgDetailView: some View {
        VStack(spacing: 0) {
            if let channel = selectedChannel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(channel.name)
                        .font(.title2.bold())
                        .lineLimit(1)
                    
                    Text(channel.id)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Button(action: { zapTo(channel) }) {
                            Label(L10n("Channels_ZapToTv"), systemImage: "tv.badge.wifi")
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { state.openInVLC(sRef: channel.id) }) {
                            Label(L10n("Channels_StreamVlc"), systemImage: "play.circle")
                        }
                        .buttonStyle(.bordered)
                        
                        if isShowingAllChannels && !bouquets.isEmpty {
                            Menu {
                                ForEach(bouquets) { b in
                                    Button(b.name) {
                                        Task { await addChannelToBouquet(channel, bouquet: b) }
                                    }
                                }
                            } label: {
                                Label("Suosikkeihin", systemImage: "plus.circle")
                            }
                            .menuStyle(.borderedButton)
                        }
                        
                        Spacer()
                        
                        Button(action: { Task { await fetchEPG(for: channel) } }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help(L10n("Common_Refresh"))
                    }
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
                
                if isLoadingEPG {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if epgEvents.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(L10n("Remote_NoEpgData"))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(epgEvents) { event in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(event.beginDate.formatted(.dateTime.hour().minute()) + " – " + event.endDate.formatted(.dateTime.hour().minute()))
                                        .font(.caption.bold())
                                        .foregroundColor(.accentColor)
                                    
                                    Text(event.title)
                                        .font(.headline)
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        scheduleRecording(for: event)
                                    }) {
                                        Label(L10n("Channels_AddTimer"), systemImage: "record.circle")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                }
                                
                                if !event.description.isEmpty {
                                    Text(event.description)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                }
                                
                                if !event.longDescription.isEmpty && event.longDescription != event.description {
                                    Text(event.longDescription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "list.star")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(L10n("Channels_SelectChannelPrompt"))
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Tietojen lataus
    private func loadInitialData() async {
        guard let box = state.activeBox, !box.ip.isEmpty else { return }
        isLoadingBouquets = true
        
        async let fetchedBouquets = EnigmaBoxService.shared.fetchBouquets(ip: box.ip, isRadio: isRadioMode, port: box.port, username: box.username, password: box.password)
        async let fetchedAll = EnigmaBoxService.shared.fetchAllChannels(ip: box.ip, isRadio: isRadioMode, port: box.port, username: box.username, password: box.password)
        
        let (bqList, allList) = await (fetchedBouquets, fetchedAll)
        self.bouquets = bqList
        self.allChannelsCount = allList.count
        
        if selectedSourceId.isEmpty || (selectedSourceId != allChannelsTag && !bqList.contains(where: { $0.id == selectedSourceId })) {
            self.selectedSourceId = bqList.first?.id ?? allChannelsTag
        }
        
        isLoadingBouquets = false
        await loadChannelsForCurrentSelection()
    }
    
    private func loadChannelsForCurrentSelection() async {
        guard let box = state.activeBox, !box.ip.isEmpty else { return }
        isLoadingChannels = true
        
        if isShowingAllChannels {
            let list = await EnigmaBoxService.shared.fetchAllChannels(ip: box.ip, isRadio: isRadioMode, port: box.port, username: box.username, password: box.password)
            self.channels = list
            self.allChannelsCount = list.count
            self.selectedChannel = list.first
        } else if let b = currentBouquet {
            let list = await EnigmaBoxService.shared.fetchChannels(ip: box.ip, bouquetRef: b.id, port: box.port, username: box.username, password: box.password)
            self.channels = list
            self.selectedChannel = list.first
        } else {
            self.channels = []
            self.selectedChannel = nil
        }
        isLoadingChannels = false
    }
    
    private func reloadCurrentList() async {
        guard let box = state.activeBox else { return }
        _ = await EnigmaBoxService.shared.reloadServiceList(ip: box.ip, port: box.port, username: box.username, password: box.password)
        await loadChannelsForCurrentSelection()
        state.showToast("Kanavalista päivitetty!")
    }
    
    private func fetchEPG(for channel: Channel) async {
        guard let box = state.activeBox else { return }
        isLoadingEPG = true
        let list = await EnigmaBoxService.shared.fetchEPG(ip: box.ip, sRef: channel.id, port: box.port, username: box.username, password: box.password)
        self.epgEvents = list
        isLoadingEPG = false
    }
    
    // MARK: - Valintatoiminnot
    private func toggleChannelSelection(_ id: String) {
        if selectedChannelIds.contains(id) {
            selectedChannelIds.remove(id)
        } else {
            selectedChannelIds.insert(id)
        }
    }
    
    private func selectAllChannels() {
        let ids = filteredChannels.map { $0.id }
        selectedChannelIds.formUnion(ids)
    }
    
    private func deselectAllChannels() {
        selectedChannelIds.removeAll()
    }
    
    // MARK: - Kanavien järjestely (Reordering)
    private func moveChannelItem(channel: Channel, fromIndex: Int, toIndex: Int) async {
        guard let box = state.activeBox, let b = currentBouquet else { return }
        guard toIndex >= 0 && toIndex < channels.count else { return }
        
        withAnimation {
            channels.swapAt(fromIndex, toIndex)
        }
        
        let (ok, msg) = await EnigmaBoxService.shared.moveChannel(ip: box.ip, bouquetRef: b.id, channelRef: channel.id, position: toIndex, port: box.port, username: box.username, password: box.password)
        if ok {
            state.showToast("Siirretty: \(channel.name) -> sijalle \(toIndex + 1)")
        } else {
            state.showToast("Siirto epäonnistui: \(msg)", isError: true)
            await loadChannelsForCurrentSelection()
        }
    }
    
    private func onMoveChannels(from source: IndexSet, to destination: Int) {
        guard let box = state.activeBox, let b = currentBouquet else { return }
        guard let sourceIndex = source.first else { return }
        let channel = channels[sourceIndex]
        let targetIndex = destination > sourceIndex ? destination - 1 : destination
        
        channels.move(fromOffsets: source, toOffset: destination)
        
        Task {
            let (ok, msg) = await EnigmaBoxService.shared.moveChannel(ip: box.ip, bouquetRef: b.id, channelRef: channel.id, position: targetIndex, port: box.port, username: box.username, password: box.password)
            if ok {
                state.showToast("Siirretty: \(channel.name)")
            } else {
                state.showToast("Siirto epäonnistui: \(msg)", isError: true)
                await loadChannelsForCurrentSelection()
            }
        }
    }
    
    // MARK: - Suosikkilistan ja kanavan muokkaukset
    private func createBouquet() async {
        guard let box = state.activeBox, !newBouquetName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let name = newBouquetName.trimmingCharacters(in: .whitespaces)
        state.showToast("Luodaan suosikkilistaa '\(name)'")
        let (ok, msg) = await EnigmaBoxService.shared.addBouquet(ip: box.ip, name: name, isRadio: isRadioMode, port: box.port, username: box.username, password: box.password)
        if ok {
            state.showToast("Suosikkilista '\(name)' luotu!")
            await loadInitialData()
            if let created = bouquets.first(where: { $0.name == name }) {
                selectedSourceId = created.id
            }
        } else {
            state.showToast("Luonti epäonnistui: \(msg)", isError: true)
        }
    }
    
    private func confirmDeleteBouquet(_ bouquet: Bouquet) async {
        guard let box = state.activeBox else { return }
        state.showToast("Poistetaan suosikkilistaa '\(bouquet.name)'")
        let (ok, msg) = await EnigmaBoxService.shared.deleteBouquet(ip: box.ip, bouquetRef: bouquet.id, isRadio: isRadioMode, port: box.port, username: box.username, password: box.password)
        if ok {
            state.showToast("Suosikkilista '\(bouquet.name)' poistettu!")
            if selectedSourceId == bouquet.id {
                selectedSourceId = allChannelsTag
            }
            await loadInitialData()
        } else {
            state.showToast("Poisto epäonnistui: \(msg)", isError: true)
        }
    }
    
    private func confirmDeleteChannel(_ channel: Channel) async {
        guard let box = state.activeBox, let bouquet = currentBouquet else { return }
        state.showToast("Poistetaan kanavaa '\(channel.name)'")
        let (ok, msg) = await EnigmaBoxService.shared.deleteChannelFromBouquet(ip: box.ip, bouquetRef: bouquet.id, channelRef: channel.id, port: box.port, username: box.username, password: box.password)
        if ok {
            state.showToast("Kanava '\(channel.name)' poistettu listalta!")
            selectedChannelIds.remove(channel.id)
            if selectedChannel?.id == channel.id {
                selectedChannel = nil
            }
            await loadChannelsForCurrentSelection()
        } else {
            state.showToast("Poisto epäonnistui: \(msg)", isError: true)
        }
    }
    
    private func confirmDeleteSelectedChannels() async {
        guard let box = state.activeBox, let bouquet = currentBouquet else { return }
        let idsToDelete = Array(selectedChannelIds)
        guard !idsToDelete.isEmpty else { return }
        
        state.showToast("Poistetaan \(idsToDelete.count) kanavaa")
        let (ok, count) = await EnigmaBoxService.shared.deleteMultipleChannelsFromBouquet(ip: box.ip, bouquetRef: bouquet.id, channelRefs: idsToDelete, port: box.port, username: box.username, password: box.password)
        if ok {
            state.showToast("\(count) kanavaa poistettu suosikkilistalta!")
            selectedChannelIds.removeAll()
            await loadChannelsForCurrentSelection()
        } else {
            state.showToast("Poisto epäonnistui", isError: true)
        }
    }
    
    private func confirmDeleteAllChannels() async {
        guard let box = state.activeBox, let bouquet = currentBouquet else { return }
        let allIds = channels.map { $0.id }
        guard !allIds.isEmpty else { return }
        
        state.showToast("Poistetaan kaikki kanavat suosikkilistalta")
        let (ok, count) = await EnigmaBoxService.shared.deleteMultipleChannelsFromBouquet(ip: box.ip, bouquetRef: bouquet.id, channelRefs: allIds, port: box.port, username: box.username, password: box.password)
        if ok {
            state.showToast("Kaikki (\(count)) kanavaa poistettu suosikkilistalta!")
            selectedChannelIds.removeAll()
            selectedChannel = nil
            await loadChannelsForCurrentSelection()
        } else {
            state.showToast("Poisto epäonnistui", isError: true)
        }
    }
    
    // MARK: - Globaali lamedb poisto (Kaikki kanavat)
    private func deleteSingleChannelFromLamedb(_ channel: Channel) async {
        guard let box = state.activeBox else { return }
        isPerformingLamedbOperation = true
        lamedbProgressText = "Aloitetaan kanavan '\(channel.name)' poisto"
        
        let (ok, _, msg) = await EnigmaBoxService.shared.deleteChannelsGloballyFromLamedb(
            ip: box.ip,
            channelRefs: [channel.id],
            port: box.port,
            username: box.username,
            password: box.password
        ) { progress in
            Task { @MainActor in
                self.lamedbProgressText = progress
            }
        }
        
        isPerformingLamedbOperation = false
        if ok {
            state.showToast("Kanava '\(channel.name)' poistettu pysyvästi boksista!")
            selectedChannelIds.remove(channel.id)
            if selectedChannel?.id == channel.id {
                selectedChannel = nil
            }
            await loadInitialData()
        } else {
            state.showToast(msg, isError: true)
        }
    }
    
    private func deleteSelectedChannelsFromLamedb() async {
        guard let box = state.activeBox else { return }
        let idsToDelete = Array(selectedChannelIds)
        guard !idsToDelete.isEmpty else { return }
        
        isPerformingLamedbOperation = true
        
        // Jos käyttäjä on valinnut kaikki kanavat, tyhjennetään tietokanta puhtaasti
        if isShowingAllChannels && idsToDelete.count >= channels.count {
            lamedbProgressText = "Tyhjennetään kaikki kanavat boksista"
            let (ok, count, msg) = await EnigmaBoxService.shared.clearAllChannelsGloballyFromLamedb(
                ip: box.ip,
                port: box.port,
                username: box.username,
                password: box.password
            ) { progress in
                Task { @MainActor in
                    self.lamedbProgressText = progress
                }
            }
            
            isPerformingLamedbOperation = false
            if ok {
                state.showToast("Kaikki kanavat (\(count) kpl) poistettu pysyvästi boksista!")
                selectedChannelIds.removeAll()
                selectedChannel = nil
                await loadInitialData()
            } else {
                state.showToast(msg, isError: true)
            }
            return
        }
        
        lamedbProgressText = "Aloitetaan \(idsToDelete.count) kanavan poisto"
        let (ok, count, msg) = await EnigmaBoxService.shared.deleteChannelsGloballyFromLamedb(
            ip: box.ip,
            channelRefs: idsToDelete,
            port: box.port,
            username: box.username,
            password: box.password
        ) { progress in
            Task { @MainActor in
                self.lamedbProgressText = progress
            }
        }
        
        isPerformingLamedbOperation = false
        if ok {
            state.showToast("\(count) kanavaa poistettu pysyvästi boksista!")
            selectedChannelIds.removeAll()
            selectedChannel = nil
            await loadInitialData()
        } else {
            state.showToast(msg, isError: true)
        }
    }
    
    private func deleteAllChannelsFromLamedb() async {
        guard let box = state.activeBox else { return }
        
        isPerformingLamedbOperation = true
        lamedbProgressText = "Aloitetaan kaikkien kanavien tyhjennys boksista"
        
        let (ok, count, msg) = await EnigmaBoxService.shared.clearAllChannelsGloballyFromLamedb(
            ip: box.ip,
            port: box.port,
            username: box.username,
            password: box.password
        ) { progress in
            Task { @MainActor in
                self.lamedbProgressText = progress
            }
        }
        
        isPerformingLamedbOperation = false
        if ok {
            state.showToast("Kaikki kanavat (\(count) kpl) poistettu boksista!", isError: false)
            selectedChannelIds.removeAll()
            selectedChannel = nil
            await loadInitialData()
        } else {
            state.showToast(msg, isError: true)
        }
    }
    
    private func addChannelToBouquet(_ channel: Channel, bouquet: Bouquet) async {
        guard let box = state.activeBox else { return }
        state.showToast("Lisätään kanavaa '\(channel.name)' listalle '\(bouquet.name)'")
        let (ok, msg) = await EnigmaBoxService.shared.addChannelToBouquet(ip: box.ip, bouquetRef: bouquet.id, channelRef: channel.id, port: box.port, username: box.username, password: box.password)
        if ok {
            state.showToast("Kanava '\(channel.name)' lisätty listalle '\(bouquet.name)'!")
        } else {
            state.showToast("Lisäys epäonnistui: \(msg)", isError: true)
        }
    }
    
    private func addSelectedChannelsToBouquet(bouquet: Bouquet) async {
        guard let box = state.activeBox else { return }
        let ids = Array(selectedChannelIds)
        guard !ids.isEmpty else { return }
        
        state.showToast("Lisätään \(ids.count) kanavaa listalle '\(bouquet.name)'")
        var successCount = 0
        for chId in ids {
            let (ok, _) = await EnigmaBoxService.shared.addChannelToBouquet(ip: box.ip, bouquetRef: bouquet.id, channelRef: chId, port: box.port, username: box.username, password: box.password)
            if ok { successCount += 1 }
        }
        state.showToast("\(successCount) kanavaa lisätty listalle '\(bouquet.name)'!")
        selectedChannelIds.removeAll()
    }
    
    // MARK: - Toisto & Zap
    private func zapTo(_ channel: Channel) {
        guard let box = state.activeBox else { return }
        Task {
            let ok = await EnigmaBoxService.shared.zap(ip: box.ip, sRef: channel.id, port: box.port, username: box.username, password: box.password)
            if ok {
                state.showToast("Vaihdettu: \(channel.name)")
            } else {
                state.showToast("Kanavan vaihto epäonnistui", isError: true)
            }
        }
    }
    
    private func scheduleRecording(for event: EPGEvent) {
        guard let box = state.activeBox else { return }
        Task {
            let ok = await EnigmaBoxService.shared.addTimerByEventId(ip: box.ip, sRef: event.sRef, eventId: event.id, port: box.port, username: box.username, password: box.password)
            if ok {
                state.showToast("Tallennus ajastettu: \(event.title)!")
            } else {
                state.showToast("Ajastuksen tallennus epäonnistui", isError: true)
            }
        }
    }
}
