import SwiftUI
import UserNotifications

@main
struct BCWApp: App {
    @State private var model = AppModel()

    init() {
        Theme.configureAppearance()
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        #if DEBUG
        TimetableSelfTest.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(model.preferences.appearance.colorScheme)
        }
        // Aggiornamento in background per le notifiche delle novità (`NewsNotifications`).
        .backgroundTask(.appRefresh(NewsNotifications.refreshTaskID)) {
            await NewsNotifications.runBackgroundRefresh(model: model)
        }
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
            case .signedIn:
                Group {
                    MainTabView()
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
        .appTheme()
        .overlayHost()
        .task {
            // La finestra ora esiste: prende il colore d'accento del tema per i componenti di UIKit.
            Theme.applyTint()
            model.bootstrap()
            if model.preferences.useBiometrics && model.phase == .signedIn {
                lock.lock()
                await lock.unlock()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { NewsNotifications.scheduleBackgroundRefresh(model: model) }
            guard model.preferences.useBiometrics, model.phase == .signedIn else { return }
            if phase == .background { lock.lock() }
            if phase == .active, lock.isLocked { Task { await lock.unlock() } }
        }
    }
}

extension View {
    /// Carattere, colore d'accento e sfondo dell'app (Google Sans Flex e i colori di Material 3).
    func appTheme() -> some View {
        font(.m3(16))
            .tint(Theme.primary)
            .foregroundStyle(Theme.ink)
    }
}
