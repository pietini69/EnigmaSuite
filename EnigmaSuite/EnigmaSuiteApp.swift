import SwiftUI

@main
struct EnigmaSuiteApp: App {
    @StateObject private var appState = EnigmaSuiteState()
    @StateObject private var l10n = LocalizationManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(l10n)
                .frame(minWidth: 1280, minHeight: 800)
                .onOpenURL { url in
                    appState.selectedTab = .settingsSync
                    if url.isFileURL {
                        appState.pendingPackageURL = url
                    } else if url.scheme == "enigmasuite",
                              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                              let p = comps.queryItems?.first(where: { $0.name == "path" })?.value {
                        appState.pendingPackageURL = URL(fileURLWithPath: p)
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1440, height: 900)
    }
}
