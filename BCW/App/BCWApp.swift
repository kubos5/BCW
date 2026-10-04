import SwiftUI

@main
struct BCWApp: App {
    @State private var model = AppModel()
    #if os(macOS)
    @State private var nav = MacNavigation()
    #endif

    init() {
        Theme.configureAppearance()
    }

    var body: some Scene {
        #if os(macOS)
        // Una sola finestra: il registro è uno, come in Musica o Calendario.
        Window("BCW", id: "main") {
            RootView()
                .environment(model)
                .environment(nav)
                .fontDesign(.serif)
                .tint(Theme.accent)
                .onChange(of: model.preferences.appearance, initial: true) { _, mode in
                    MacAppearance.apply(mode)
                }
        }
        .defaultSize(width: 1280, height: 840)
        .commands { BCWCommands(model: model, nav: nav) }

        Settings {
            MacSettingsView()
                .environment(model)
                .environment(nav)
                .fontDesign(.serif)
                .tint(Theme.accent)
        }
        #else
        WindowGroup {
            RootView()
                .environment(model)
                .fontDesign(.serif)
                .tint(Theme.accent)
                .preferredColorScheme(model.preferences.appearance.colorScheme)
        }
        #endif
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var lock = BiometricLock()

    var body: some View {
        ZStack {
            switch model.phase {
            case .launching:
                Theme.background.ignoresSafeArea()
            case .signedOut:
                LoginView()
                    .transition(.opacity)
                    #if os(macOS)
                    .frame(minWidth: 520, minHeight: 640)
                    #if DEBUG
                    .task { DebugSnapshots.captureLogin() }
                    #endif
                    #endif
            case .signedIn:
                #if os(macOS)
                MacRootView()
                    .transition(.opacity)
                #else
                MainTabView()
                    .transition(.opacity)
                #endif
            }

            if lock.isLocked && model.phase == .signedIn {
                LockView(lock: lock)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.smooth, value: model.phase)
        .task {
            model.bootstrap()
            if model.preferences.useBiometrics && model.phase == .signedIn {
                lock.lock()
                await lock.unlock()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard model.preferences.useBiometrics, model.phase == .signedIn else { return }
            if phase == .background { lock.lock() }
            if phase == .active, lock.isLocked { Task { await lock.unlock() } }
        }
    }
}

#if os(iOS)
struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = .dashboard

    enum AppTab: Hashable { case dashboard, grades, you, search }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Dashboard", systemImage: "calendar.day.timeline.left", value: AppTab.dashboard) {
                DashboardView()
            }
            Tab("Voti", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.grades) {
                GradesView()
            }
            Tab("Tu", systemImage: "person.crop.circle", value: AppTab.you) {
                YouView()
            }
            .badge(model.unreadNoticesCount)
            Tab("Cerca", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
#endif

#if os(macOS)
import AppKit

/// Su macOS `preferredColorScheme(nil)` non riporta la finestra all'aspetto di sistema:
/// si imposta quindi l'aspetto dell'intera app (vale anche per la finestra Impostazioni).
enum MacAppearance {
    static func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
#endif
