import SwiftUI
import UserNotifications

@main
struct BCWApp: App {
    @State private var model = AppModel()
    #if os(macOS)
    @State private var nav = MacNavigation()
    #endif

    init() {
        Theme.configureAppearance()
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        #if DEBUG
        TimetableSelfTest.runIfRequested()
        #endif
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
        // Aggiornamento in background per le notifiche delle novità (`NewsNotifications`).
        .backgroundTask(.appRefresh(NewsNotifications.refreshTaskID)) {
            await NewsNotifications.runBackgroundRefresh(model: model)
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
                #if os(macOS)
                // Dentro una pila di navigazione la finestra ha la stessa barra (e gli stessi
                // margini dei pulsanti a semaforo) della finestra principale.
                NavigationStack {
                    LoginView()
                }
                .transition(.opacity)
                .frame(minWidth: 520, minHeight: 640)
                #if DEBUG
                .task { DebugSnapshots.captureLogin() }
                #endif
                #else
                LoginView()
                    .transition(.opacity)
                #endif
            case .signedIn:
                Group {
                    #if os(macOS)
                    MacRootView()
                    #else
                    MainTabView()
                    #endif
                }
                // Cambiando account tutto scompare e riappare con i nuovi dati (`changeSession`).
                .opacity(model.isChangingSession ? 0 : 1)
                .background(Theme.background.ignoresSafeArea())
                .transition(.opacity)
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
            #if os(iOS)
            if phase == .background { NewsNotifications.scheduleBackgroundRefresh(model: model) }
            #endif
            guard model.preferences.useBiometrics, model.phase == .signedIn else { return }
            if phase == .background { lock.lock() }
            if phase == .active, lock.isLocked { Task { await lock.unlock() } }
        }
    }
}

#if os(iOS)
struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = MainTabView.initialTab
    @State private var searchQuery = ""
    /// Incrementato toccando la scheda Dashboard quando è già quella aperta.
    @State private var dashboardReselection = 0
    @State private var timetableReselection = 0
    @State private var switchingAccount = false

    enum AppTab: Hashable { case dashboard, timetable, grades, you, search }

    private static var initialTab: AppTab {
        #if DEBUG
        // Per le prove di sviluppo: `-BCWTab timetable` apre l'Orario.
        if UserDefaults.standard.string(forKey: "BCWTab") == "timetable" { return .timetable }
        #endif
        return .dashboard
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Dashboard", systemImage: "calendar.day.timeline.left", value: AppTab.dashboard) {
                DashboardView(reselection: dashboardReselection)
            }
            Tab("Orario", systemImage: "tablecells", value: AppTab.timetable) {
                TimetableView(reselection: timetableReselection)
            }
            Tab("Voti", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.grades) {
                GradesView()
            }
            Tab("Tu", systemImage: "person.crop.circle", value: AppTab.you) {
                YouView()
            }
            .badge(model.unreadNoticesCount)
            Tab("Cerca", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                SearchView(query: $searchQuery)
            }
        }
        .modifier(SeparateSearchTab())
        .tabBarMinimizeBehavior(.onScrollDown)
        // Tenendo premuta la scheda Tu si cambia account al volo.
        .background {
            TabBarItemLongPress(index: 3) { switchingAccount = true }
        }
        .sheet(isPresented: $switchingAccount) {
            AccountSwitcherSheet()
        }
    }

    /// Selezione delle schede che riconosce un nuovo tocco sulla scheda già aperta.
    private var tabSelection: Binding<AppTab> {
        Binding {
            selection
        } set: { tab in
            if tab == selection, tab == .dashboard { dashboardReselection += 1 }
            if tab == selection, tab == .timetable { timetableReselection += 1 }
            selection = tab
        }
    }
}

/// Con l'SDK di iOS 27 la scheda Cerca finisce dentro la barra delle schede e il campo va in
/// alto. Legando l'attivazione della ricerca alla selezione della scheda torna come su iOS 26:
/// un pulsante separato, con il campo che prende il posto della barra.
/// Su iOS 26 il comportamento è già quello, quindi resta com'è.
private struct SeparateSearchTab: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content.tabViewSearchActivation(.searchTabSelection)
        } else {
            content
        }
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

