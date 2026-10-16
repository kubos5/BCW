import SwiftUI

/// Schede dell'app su iPhone e iPad. Con Liquid Glass è la `TabView` di sistema; altrimenti la
/// barra di navigazione di Material 3 (64 punti, `surface-container`, indicatore a pillola
/// 56 × 32 dietro l'icona della scheda aperta), come la versione web.
struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: AppTab = MainTabView.initialTab
    @State private var searchQuery = ""
    /// Incrementato toccando di nuovo la scheda già aperta.
    @State private var reselections: [AppTab: Int] = [:]
    @State private var switchingAccount = false

    enum AppTab: Hashable, CaseIterable {
        case dashboard, timetable, grades, you, search

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .timetable: "Orario"
            case .grades: "Voti"
            case .you: "Tu"
            case .search: "Cerca"
            }
        }

        var icon: String {
            switch self {
            case .dashboard: "dashboard"
            case .timetable: "timetable"
            case .grades: "grades"
            case .you: "you"
            case .search: "search"
            }
        }

        var selectedIcon: String {
            switch self {
            case .dashboard: "dashboardFill"
            case .timetable: "timetableFill"
            case .grades: "gradesFill"
            case .you: "youFill"
            case .search: "search"
            }
        }
    }

    private static var initialTab: AppTab {
        #if DEBUG
        // Per le prove di sviluppo: `-BCWTab timetable` apre l'Orario (anche grades, you, search).
        switch UserDefaults.standard.string(forKey: "BCWTab") {
        case "timetable": return .timetable
        case "grades": return .grades
        case "you": return .you
        case "search": return .search
        default: break
        }
        #endif
        return .dashboard
    }

    var body: some View {
        let glass = ThemeStore.shared.liquidGlass
        // Una sola `TabView` per entrambi gli aspetti: cambiando Liquid Glass nelle Impostazioni
        // le schede (e le pagine aperte) restano dove sono, cambia solo la barra.
        TabView(selection: tabSelection) {
            Tab(value: AppTab.dashboard) {
                DashboardView(reselection: reselections[.dashboard, default: 0])
                    .modifier(MaterialTab(reselection: reselections[.dashboard, default: 0]))
            } label: {
                tabLabel(.dashboard)
            }
            Tab(value: AppTab.timetable) {
                TimetableView(reselection: reselections[.timetable, default: 0])
                    .modifier(MaterialTab(reselection: reselections[.timetable, default: 0]))
            } label: {
                tabLabel(.timetable)
            }
            Tab(value: AppTab.grades) {
                GradesView()
                    .modifier(MaterialTab(reselection: reselections[.grades, default: 0]))
            } label: {
                tabLabel(.grades)
            }
            Tab(value: AppTab.you) {
                YouView()
                    .modifier(MaterialTab(reselection: reselections[.you, default: 0]))
            } label: {
                tabLabel(.you)
            }
            .badge(glass ? model.unreadNoticesCount : 0)
            Tab(value: AppTab.search, role: .search) {
                SearchView(query: $searchQuery)
                    .modifier(MaterialTab(reselection: reselections[.search, default: 0]))
            } label: {
                tabLabel(.search)
            }
        }
        .modifier(SeparateSearchTab())
        .tabBarMinimizeBehavior(glass ? .onScrollDown : .never)
        // La barra sta sopra le schede: lo spazio che occupa lo riserva ogni pagina (`pageChrome`),
        // perché né la `TabView` né le pile di navigazione passano il margine di un `safeAreaInset`.
        .overlay(alignment: .bottom) {
            if !glass {
                M3NavigationBar(selection: selection, badge: model.unreadNoticesCount) { tab in
                    tabSelection.wrappedValue = tab
                } longPress: { tab in
                    if tab == .you { switchingAccount = true }
                }
            }
        }
        // Tenendo premuta la scheda Tu si cambia account al volo.
        .background {
            if glass {
                TabBarItemLongPress(index: 3) { switchingAccount = true }
            }
        }
        .sheet(isPresented: $switchingAccount) {
            AccountSwitcherSheet()
        }
    }

    /// Etichetta della scheda per la barra di sistema: come sul web, la scheda aperta ha l'icona piena.
    private func tabLabel(_ tab: AppTab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image("m." + (selection == tab ? tab.selectedIcon : tab.icon))
        }
    }

    /// Selezione delle schede che riconosce un nuovo tocco sulla scheda già aperta.
    private var tabSelection: Binding<AppTab> {
        Binding {
            selection
        } set: { tab in
            if tab == selection { reselections[tab, default: 0] += 1 }
            selection = tab
        }
    }
}

/// Senza Liquid Glass la barra delle schede di sistema è nascosta (c'è quella di Material 3) e le
/// pagine ricevono il nuovo tocco sulla scheda aperta per tornare in cima.
private struct MaterialTab: ViewModifier {
    let reselection: Int

    func body(content: Content) -> some View {
        let glass = ThemeStore.shared.liquidGlass
        content
            .environment(\.tabReselection, glass ? 0 : reselection)
            .toolbarVisibility(glass ? .automatic : .hidden, for: .tabBar)
            // Le pagine (dentro le loro pile di navigazione) lasciano lo spazio della barra.
            .environment(\.bottomBarInset, glass ? 0 : M3NavigationBar.height)
    }
}

/// Barra di navigazione di Material 3 (corta, 64 punti) con l'indicatore a pillola.
private struct M3NavigationBar: View {
    static let height: CGFloat = 68
    let selection: MainTabView.AppTab
    let badge: Int
    let select: (MainTabView.AppTab) -> Void
    let longPress: (MainTabView.AppTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTabView.AppTab.allCases, id: \.self) { tab in
                NavigationBarItem(tab: tab, selected: tab == selection, badge: tab == .you ? badge : 0,
                                  select: { select(tab) }, longPress: { longPress(tab) })
            }
        }
        .padding(.horizontal, 4)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Theme.surfaceContainer.ignoresSafeArea(edges: .bottom))
    }
}

private struct NavigationBarItem: View {
    let tab: MainTabView.AppTab
    let selected: Bool
    let badge: Int
    let select: () -> Void
    let longPress: () -> Void
    @State private var pressed = false
    /// La pressione prolungata ha già agito: il tocco che finisce dopo non seleziona la scheda.
    @State private var longPressed = false

    var body: some View {
        Button {
            if longPressed {
                longPressed = false
                return
            }
            Haptics.selection()
            select()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(Theme.secondaryContainer)
                        .scaleEffect(x: selected ? 1 : 0, y: 1)
                        .opacity(selected ? 1 : 0)
                    Capsule(style: .continuous)
                        .fill(Theme.onSurfaceVariant.opacity(pressed ? 0.12 : 0))
                    Icon(selected ? tab.selectedIcon : tab.icon)
                        .foregroundStyle(selected ? Theme.onSecondaryContainer : Theme.onSurfaceVariant)
                    if badge > 0 {
                        CountBadge(count: badge)
                            .offset(x: 13, y: -10)
                    }
                }
                .frame(width: 56, height: 32)
                Text(tab.title)
                    .font(.m3(12, weight: selected ? 750 : 550))
                    .tracking(0.3)
                    .foregroundStyle(selected ? Theme.secondary : Theme.onSurfaceVariant)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressReportingStyle(pressed: $pressed))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                guard tab == .you else { return }
                longPressed = true
                Haptics.soft()
                longPress()
            }
        )
        .animation(Motion.effectsFast, value: pressed)
        .animation(Motion.spatial, value: selected)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(badge > 0 ? "\(badge) da leggere" : "")
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
