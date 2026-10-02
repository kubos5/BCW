import SwiftUI

@main
struct BCWApp: App {
    @State private var model = AppModel()

    init() {
        Theme.configureAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .fontDesign(.serif)
                .tint(Theme.accent)
                .preferredColorScheme(model.preferences.appearance.colorScheme)
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
                MainTabView()
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
            guard model.preferences.useBiometrics, model.phase == .signedIn else { return }
            if phase == .background { lock.lock() }
            if phase == .active, lock.isLocked { Task { await lock.unlock() } }
        }
    }
}

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
