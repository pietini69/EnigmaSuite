import SwiftUI

enum TimerSubTab: String, CaseIterable, Identifiable {
    case timers = "timers"
    case autotimers = "autotimers"
    case movies = "movies"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .timers: return L10n("Timers_TabTimers")
        case .autotimers: return L10n("Timers_TabAutoTimers")
        case .movies: return L10n("Timers_TabMovies")
        }
    }
    
    var icon: String {
        switch self {
        case .timers: return "timer"
        case .autotimers: return "clock.arrow.2.circlepath"
        case .movies: return "film"
        }
    }
}

struct TimersAndMoviesView: View {
    @EnvironmentObject var state: EnigmaSuiteState
    @EnvironmentObject var l10n: LocalizationManager
    @State private var subTab: TimerSubTab = .timers
    
    @State private var timers: [EnigmaTimer] = []
    @State private var autoTimers: [AutoTimerRule] = []
    @State private var movies: [EnigmaMovie] = []
    @State private var isLoading: Bool = false
    
    // Suodatin
    @State private var searchText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Yläpalkki / Alavalinnat
            HStack {
                Picker("", selection: $subTab) {
                    ForEach(TimerSubTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
                
                Spacer()
                
                TextField(L10n("Common_Search"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                
                Button(action: { Task { await refreshCurrentTab() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help(L10n("Common_Refresh"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch subTab {
                case .timers:
                    timersList
                case .autotimers:
                    autoTimersList
                case .movies:
                    moviesList
                }
            }
        }
        .task {
            await refreshCurrentTab()
        }
        .onChange(of: subTab) { _, _ in
            Task { await refreshCurrentTab() }
        }
        .onChange(of: state.activeBox) { _, _ in
            Task { await refreshCurrentTab() }
        }
    }
    
    // MARK: - Ajastuslista
    private var filteredTimers: [EnigmaTimer] {
        if searchText.isEmpty { return timers }
        return timers.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var timersList: some View {
        Group {
            if filteredTimers.isEmpty {
                emptyPlaceholder(title: L10n("Timers_EmptyTimersTitle"), desc: L10n("Timers_EmptyTimersDesc"))
            } else {
                List {
                    ForEach(filteredTimers) { timer in
                        HStack(spacing: 14) {
                            Image(systemName: "timer")
                                .font(.title2)
                                .foregroundColor(.accentColor)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(timer.name)
                                    .font(.headline)
                                
                                HStack(spacing: 12) {
                                    Text(timer.startDate.formatted(.dateTime.weekday(.wide).day().month().hour().minute()) + " – " + timer.endDate.formatted(.dateTime.hour().minute()))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if !timer.description.isEmpty {
                                        Text("• \(timer.description)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Button(role: .destructive, action: {
                                deleteTimer(timer)
                            }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(L10n("Common_Delete"))
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }
    
    // MARK: - Automaattiajastukset
    private var filteredAutoTimers: [AutoTimerRule] {
        if searchText.isEmpty { return autoTimers }
        return autoTimers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.match.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var autoTimersList: some View {
        Group {
            if filteredAutoTimers.isEmpty {
                emptyPlaceholder(title: L10n("Timers_EmptyAutoTimersTitle"), desc: L10n("Timers_EmptyAutoTimersDesc"))
            } else {
                List {
                    ForEach(filteredAutoTimers, id: \.ruleId) { rule in
                        HStack(spacing: 14) {
                            Image(systemName: "clock.arrow.2.circlepath")
                                .font(.title2)
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.name.isEmpty ? rule.match : rule.name)
                                    .font(.headline)
                                Text("\(L10n("Timers_Keyword")): \"\(rule.match)\"")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(role: .destructive, action: {
                                deleteAutoTimer(rule)
                            }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(L10n("Common_Delete"))
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }
    
    // MARK: - Tallenteet (Movies)
    private var filteredMovies: [EnigmaMovie] {
        if searchText.isEmpty { return movies }
        return movies.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var moviesList: some View {
        Group {
            if filteredMovies.isEmpty {
                emptyPlaceholder(title: L10n("Timers_EmptyMoviesTitle"), desc: L10n("Timers_EmptyMoviesDesc"))
            } else {
                List {
                    ForEach(filteredMovies) { movie in
                        HStack(spacing: 14) {
                            Image(systemName: "film")
                                .font(.title2)
                                .foregroundColor(.purple)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.name)
                                    .font(.headline)
                                
                                HStack(spacing: 12) {
                                    Text(movie.date.formatted(.dateTime.day().month().year().hour().minute()))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text("• \(movie.sizeString)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if !movie.description.isEmpty {
                                        Text("• \(movie.description)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                state.openInVLC(sRef: movie.id)
                            }) {
                                Label(L10n("Timers_Play"), systemImage: "play.circle.fill")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                            .help(L10n("Timers_PlayVlc"))
                            
                            Button(role: .destructive, action: {
                                deleteMovie(movie)
                            }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(L10n("Common_Delete"))
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }
    
    private func emptyPlaceholder(title: String, desc: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(desc)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Toiminnot
    private func refreshCurrentTab() async {
        guard let box = state.activeBox, !box.ip.isEmpty else { return }
        isLoading = true
        switch subTab {
        case .timers:
            self.timers = await EnigmaBoxService.shared.fetchTimers(ip: box.ip, port: box.port, username: box.username, password: box.password)
        case .autotimers:
            self.autoTimers = await EnigmaBoxService.shared.fetchAutoTimers(ip: box.ip, port: box.port, username: box.username, password: box.password)
        case .movies:
            self.movies = await EnigmaBoxService.shared.fetchMovies(ip: box.ip, port: box.port, username: box.username, password: box.password)
        }
        isLoading = false
    }
    
    private func deleteTimer(_ timer: EnigmaTimer) {
        guard let box = state.activeBox else { return }
        Task {
            let ok = await EnigmaBoxService.shared.deleteTimer(ip: box.ip, sRef: timer.sRef, begin: timer.begin, end: timer.end, port: box.port, username: box.username, password: box.password)
            if ok {
                state.showToast("Ajastus poistettu: \(timer.name)")
                await refreshCurrentTab()
            } else {
                state.showToast("Ajastuksen poisto epäonnistui", isError: true)
            }
        }
    }
    
    private func deleteAutoTimer(_ rule: AutoTimerRule) {
        guard let box = state.activeBox else { return }
        Task {
            let ok = await EnigmaBoxService.shared.deleteAutoTimer(ip: box.ip, ruleId: rule.ruleId, port: box.port, username: box.username, password: box.password)
            if ok {
                state.showToast("AutoTimer-sääntö poistettu")
                await refreshCurrentTab()
            } else {
                state.showToast("Poisto epäonnistui", isError: true)
            }
        }
    }
    
    private func deleteMovie(_ movie: EnigmaMovie) {
        guard let box = state.activeBox else { return }
        Task {
            let ok = await EnigmaBoxService.shared.deleteMovie(ip: box.ip, sRef: movie.id, port: box.port, username: box.username, password: box.password)
            if ok {
                state.showToast("Tallenne poistettu: \(movie.name)")
                await refreshCurrentTab()
            } else {
                state.showToast("Poisto epäonnistui", isError: true)
            }
        }
    }
}
