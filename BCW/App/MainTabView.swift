import SwiftUI

/// Schede dell'app su iPhone e iPad. Con Liquid Glass è la `TabView` di sistema (con la scheda
/// Cerca); altrimenti la barra di navigazione di Material 3 con quattro destinazioni (64 punti,
/// `surface-container`, indicatore a pillola 56 × 32 dietro l'icona della scheda aperta) e la
/// ricerca nella barra in cima alla Dashboard.
///
/// Sull'iPad con la finestra larga (`WindowClass.regular`) le sezioni di Tu sono destinazioni a
/// sé: senza Liquid Glass nella barra di navigazione laterale (`NavigationRail`), con la barra
/// superiore della ricerca e la pagina in un pannello (`WideShell.swift`); con Liquid Glass nella
/// barra laterale di sistema (`.sidebarAdaptable`).
/// La `TabView` è una sola e sta sempre nella stessa posizione: barra superiore e barra laterale
/// sono elementi facoltativi accanto a lei, così ruotando, ridimensionando la finestra o
/// cambiando Liquid Glass pile di navigazione, giorni scelti e pagine aperte restano.
struct MainTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.windowClass) private var windowClass
    @Environment(\.railExpands) private var railExpands
    @State private var selection: AppTab = MainTabView.initialTab
    /// Ultima scheda prima della ricerca (iPad largo senza Liquid Glass): la X della ricerca ci torna.
    @State private var lastSelection: AppTab = .dashboard
    @State private var searchQuery = MainTabView.initialQuery
    @FocusState private var searchFocused: Bool
    /// Incrementato toccando di nuovo la scheda già aperta.
    @State private var reselections: [AppTab: Int] = [:]
    @State private var switchingAccount = false
    /// Una pagina può nascondere la barra delle schede (es. la modifica dell'orario).
    @State private var chrome = TabChrome()
    @State private var navigation = AppNavigation()
    /// Barra di navigazione ridotta dall'utente (solo dove può restare espansa, da 1100 punti).
    @AppStorage("railCollapsed") private var railCollapsed = false
    /// Barra di navigazione espansa aperta sopra il pannello (finestre sotto i 1100 punti).
    @State private var railOverlayOpen = false
    #if DEBUG
    @State private var consumedDebugSection = false
    #endif

    enum AppTab: Hashable {
        case dashboard, timetable, grades, you, search
        /// Sezione di Tu come destinazione a sé (solo sull'iPad).
        case section(AppSection)

        /// Le quattro destinazioni principali.
        static let mainTabs: [AppTab] = [.dashboard, .timetable, .grades, .you]
        /// Schede della barra di sistema, nell'ordine (per le icone piene e la pressione su Tu).
        static let barTabs: [AppTab] = [.dashboard, .timetable, .grades, .you, .search]

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .timetable: "Orario"
            case .grades: "Voti"
            case .you: "Tu"
            case .search: "Cerca"
            case let .section(section): section.title
            }
        }

        /// Etichetta della barra di navigazione ridotta.
        var shortTitle: String {
            if case let .section(section) = self { return section.shortTitle }
            return title
        }

        var icon: String {
            switch self {
            case .dashboard: "dashboard"
            case .timetable: "timetable"
            case .grades: "grades"
            case .you: "you"
            case .search: "search"
            case let .section(section): section.icon
            }
        }

        var selectedIcon: String {
            switch self {
            case .dashboard: "dashboardFill"
            case .timetable: "timetableFill"
            case .grades: "gradesFill"
            case .you: "youFill"
            case .search: "search"
            case let .section(section): section.icon
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

    /// Per le prove di sviluppo: `-BCWSearchQuery testo` apre la ricerca con quel testo (con `-BCWTab search`).
    private static var initialQuery: String {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "BCWSearchQuery") ?? ""
        #else
        return ""
        #endif
    }

    private var isRegular: Bool { windowClass == .regular }

    /// La barra di navigazione resta espansa accanto al pannello.
    private var railPinned: Bool { railExpands && !railCollapsed }

    var body: some View {
        let glass = ThemeStore.shared.liquidGlass
        let wide = isRegular && !glass
        shell
        .environment(\.tabChrome, chrome)
        .environment(\.appNavigation, navigation)
        .environment(\.pageGutter, isRegular ? 24 : 16)
        // La barra sta sopra le schede: lo spazio che occupa lo riserva ogni pagina (`pageChrome`),
        // perché né la `TabView` né le pile di navigazione passano il margine di un `safeAreaInset`.
        .overlay(alignment: .bottom) {
            if !glass && !isRegular && !chrome.hidesBar {
                M3NavigationBar(selection: selection, badge: model.unreadNoticesCount) { tab in
                    tabSelection.wrappedValue = tab
                } longPress: { tab in
                    if tab == .you { switchingAccount = true }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .ignoresSafeArea(.keyboard)
            }
        }
        .animation(Motion.spatial, value: chrome.hidesBar)
        // Tenendo premuta la scheda Tu si cambia account al volo.
        .background {
            if glass && !isRegular {
                TabBarItemLongPress(index: 3) { switchingAccount = true }
                TabBarSelectedImages(names: AppTab.barTabs.map(\.selectedIcon))
            }
        }
        .sheet(isPresented: $switchingAccount) {
            AccountSwitcherSheet()
        }
        // Collegamenti dei widget: la scheda; il giorno lo sceglie la scheda stessa.
        .onChange(of: model.openedLink, initial: true) { _, link in
            switch link {
            case .dashboard: selection = .dashboard
            case .timetable: selection = .timetable
            case .grades:
                selection = .grades
                model.openedLink = nil
            case nil: break
            }
        }
        // Senza Liquid Glass la scheda Cerca non è nella barra in basso: si torna alla Dashboard.
        .onChange(of: glass, initial: true) { _, glass in
            if !glass && !isRegular && selection == .search { selection = .dashboard }
            railOverlayOpen = false
            // La barra laterale di sistema aperta con Liquid Glass resterebbe sopra il pannello.
            if WindowClass.isPad { applySidebarMode(glass: glass) }
        }
        .onChange(of: windowClass, initial: true) { old, new in
            windowClassChanged(from: old, to: new)
        }
        .onChange(of: selection) { old, new in
            // Scegliendo un'altra destinazione la ricerca generale si chiude.
            if old == .search && new != .search && wide {
                searchQuery = ""
                searchFocused = false
            }
        }
        .onChange(of: searchFocused) { _, focused in
            // Il campo della barra superiore apre la scheda Cerca.
            if focused && wide && selection != .search {
                lastSelection = selection
                selection = .search
            }
        }
        .onChange(of: navigation.requestedSection) { _, section in
            guard let section else { return }
            navigation.requestedSection = nil
            tabSelection.wrappedValue = .section(section)
        }
        #if DEBUG
        .onChange(of: DebugScript.shared.tab) { _, name in
            guard let name else { return }
            DebugScript.shared.tab = nil
            switch name {
            case "dashboard": tabSelection.wrappedValue = .dashboard
            case "timetable": tabSelection.wrappedValue = .timetable
            case "grades": tabSelection.wrappedValue = .grades
            case "you": tabSelection.wrappedValue = .you
            case "search": tabSelection.wrappedValue = .search
            default: if let section = AppSection(debugKey: name) { tabSelection.wrappedValue = .section(section) }
            }
        }
        .debugAction("settings") { openSettings() }
        .debugAction("rail") { toggleRail() }
        .debugAction("search") { searchFocused = true }
        #endif
    }

    /// Sull'iPhone la `TabView` da sola, come sempre. Sull'iPad (costante: la struttura non cambia mai
    /// a finestra aperta) la `TabView` con accanto, sulla finestra larga senza Liquid Glass, la barra
    /// superiore e la barra di navigazione, e la pagina in un pannello con angoli ampi.
    @ViewBuilder
    private var shell: some View {
        if WindowClass.isPad {
            let wide = isRegular && !ThemeStore.shared.liquidGlass
            let railWidth = railPinned ? WideShellMetrics.railExpanded : WideShellMetrics.railCollapsed
            VStack(spacing: 0) {
                if wide {
                    WideTopBar(railWidth: railWidth, railCollapsed: !railPinned && !railOverlayOpen,
                               query: $searchQuery, focus: $searchFocused, isSearching: selection == .search,
                               toggleRail: toggleRail, closeSearch: closeSearch,
                               openSettings: openSettings, switchAccount: { switchingAccount = true })
                }
                HStack(spacing: 0) {
                    if wide {
                        NavigationRail(expanded: railPinned, selection: selection, select: selectFromRail,
                                       longPressYou: { switchingAccount = true })
                    }
                    // Sempre qui, mai dentro rami diversi: cambiando shell la `TabView` resta la stessa.
                    tabs
                        .clipShape(PanelShape(radius: Theme.radii.xl, clips: wide))
                        .padding(.trailing, wide ? WideShellMetrics.panelInset : 0)
                        .padding(.bottom, wide ? WideShellMetrics.panelInset : 0)
                }
                .overlay(alignment: .leading) {
                    if wide && railOverlayOpen && !railPinned {
                        railOverlay
                    }
                }
            }
            // Il pannello arriva fino a 12 punti dal fondo dello schermo, anche sotto l'indicatore della Home.
            .ignoresSafeArea(.container, edges: wide ? .bottom : [])
            .background((wide ? Theme.surfaceContainer : Theme.background).ignoresSafeArea())
        } else {
            tabs
        }
    }

    /// La `TabView` con tutte le schede. Sull'iPad (costante: la struttura non cambia mai a finestra
    /// aperta) ha lo stile con la barra laterale e le sezioni di Tu, solo nella barra laterale.
    @ViewBuilder
    private var tabs: some View {
        if WindowClass.isPad {
            tabView
                .tabViewStyle(.sidebarAdaptable)
                .tabViewSidebarHeader {
                    SidebarAccountHeader(model: model) { switchingAccount = true }
                        .appTheme()
                }
                .tabViewSidebarBottomBar {
                    SidebarBottomActions(model: model, openSettings: openSettings)
                        .appTheme()
                }
        } else {
            tabView
        }
    }

    private var tabView: some View {
        let glass = ThemeStore.shared.liquidGlass
        // Una sola `TabView` per entrambi gli aspetti: cambiando Liquid Glass nelle Impostazioni
        // le schede (e le pagine aperte) restano dove sono, cambia solo la barra.
        return TabView(selection: tabSelection) {
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
            // Dopo Cerca, così le schede della barra in basso restano ai loro indici.
            if WindowClass.isPad {
                ForEach(AppSection.Group.allCases) { group in
                    TabSection(group.title) {
                        ForEach(group.sections) { section in
                            Tab(value: AppTab.section(section)) {
                                PlatformNavigationStack { section.destination }
                                    .modifier(MaterialTab(reselection: reselections[.section(section), default: 0]))
                            } label: {
                                tabLabel(.section(section))
                            }
                            .tabPlacement(.sidebarOnly)
                            .badge(section.badge(model))
                        }
                    }
                    // Anche il gruppo: altrimenti la barra delle schede in alto lo mostrava (freccia ›).
                    .tabPlacement(.sidebarOnly)
                }
            }
        }
        .modifier(SeparateSearchTab())
        .tabBarMinimizeBehavior(glass ? .onScrollDown : .never)
    }

    /// Barra di navigazione espansa sopra il pannello, con il velo (finestre sotto i 1100 punti).
    private var railOverlay: some View {
        ZStack(alignment: .leading) {
            Theme.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { setRailOverlay(false) }
                .accessibilityHidden(true)
            NavigationRail(expanded: true, selection: selection, select: selectFromRail,
                           longPressYou: { switchingAccount = true })
                .background {
                    UnevenRoundedRectangle(bottomTrailingRadius: Theme.radii.l, topTrailingRadius: Theme.radii.l,
                                           style: .continuous)
                        .fill(Theme.surfaceContainer)
                        .shadow(color: Theme.shadow.opacity(0.2), radius: 12, y: 4)
                        .ignoresSafeArea(edges: .bottom)
                }
                .transition(.move(edge: .leading))
        }
        .transition(.opacity)
    }

    /// Etichetta della scheda per la barra di sistema: sempre l'icona vuota; quella piena (la scheda
    /// aperta, come sul web) è la `selectedImage` dell'elemento, che segue la bolla
    /// (`TabBarSelectedImages`).
    private func tabLabel(_ tab: AppTab) -> some View {
        Label {
            Text(tab.title)
        } icon: {
            Image("m." + tab.icon)
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

    // MARK: Shell larga

    private func selectFromRail(_ tab: AppTab) {
        tabSelection.wrappedValue = tab
        if railOverlayOpen { setRailOverlay(false) }
    }

    /// Pulsante del menu: riduce o espande la barra (da 1100 punti, ricordato), altrimenti apre la
    /// barra espansa sopra il pannello.
    private func toggleRail() {
        if railExpands {
            withAnimation(Motion.spatial) { railCollapsed.toggle() }
        } else {
            setRailOverlay(!railOverlayOpen)
        }
    }

    /// Barra laterale di sistema solo con Liquid Glass (`TabSidebar`). La `TabView` può non esistere
    /// ancora all'avvio: si riprova al giro dopo e dopo un attimo.
    private func applySidebarMode(glass: Bool) {
        TabSidebar.setAvailable(glass)
        DispatchQueue.main.async { TabSidebar.setAvailable(ThemeStore.shared.liquidGlass) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { TabSidebar.setAvailable(ThemeStore.shared.liquidGlass) }
    }

    private func setRailOverlay(_ open: Bool) {
        withAnimation(Motion.spatial) { railOverlayOpen = open }
    }

    private func closeSearch() {
        searchQuery = ""
        searchFocused = false
        if selection == .search { selection = lastSelection == .search ? .dashboard : lastSelection }
    }

    private func openSettings() {
        if railOverlayOpen { setRailOverlay(false) }
        selection = .you
        navigation.openSettings = true
    }

    /// Passando alla finestra stretta le sezioni tornano dentro Tu (la sezione aperta sopra il menu
    /// di Tu) e senza Liquid Glass la ricerca torna nella barra della Dashboard.
    private func windowClassChanged(from old: WindowClass, to new: WindowClass) {
        navigation.sectionsAreDestinations = new == .regular && WindowClass.isPad
        railOverlayOpen = false
        if new == .compact {
            if case let .section(section) = selection {
                selection = .you
                navigation.pendingSection = section
            }
            if selection == .search && !ThemeStore.shared.liquidGlass {
                selection = lastSelection == .search ? .dashboard : lastSelection
                searchQuery = ""
            }
            searchFocused = false
        }
        #if DEBUG
        // `-BCWOpenPage <sezione>` sull'iPad largo sceglie la sezione nella barra di navigazione.
        if new == .regular, !consumedDebugSection, let key = UserDefaults.standard.string(forKey: "BCWOpenPage"),
           let section = AppSection(debugKey: key) {
            consumedDebugSection = true
            selection = .section(section)
        }
        #endif
    }
}

/// Ritaglio del pannello della pagina: angoli ampi sulla finestra larga senza Liquid Glass; altrove
/// un rettangolo molto più grande della `TabView`, che quindi non ritaglia nulla (la barra delle
/// schede di sistema e gli sfondi delle pagine escono dai bordi della `TabView`, nella zona sicura:
/// ritagliati, l'indicatore della Home restava su una fascia vuota). Una forma sola per i due
/// casi, così la `TabView` non cambia identità.
private struct PanelShape: Shape {
    var radius: CGFloat
    var clips: Bool

    func path(in rect: CGRect) -> Path {
        clips ? Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
            : Path(rect.insetBy(dx: -4000, dy: -4000))
    }
}

/// Senza Liquid Glass la barra delle schede di sistema è nascosta (c'è quella di Material 3) e le
/// pagine ricevono il nuovo tocco sulla scheda aperta per tornare in cima.
private struct MaterialTab: ViewModifier {
    let reselection: Int
    @Environment(\.tabChrome) private var chrome
    @Environment(\.windowClass) private var windowClass

    func body(content: Content) -> some View {
        let glass = ThemeStore.shared.liquidGlass
        let regular = windowClass == .regular
        // Sull'iPad largo la barra di navigazione (laterale o in alto) resta anche in modifica: M3
        // vieta la barra degli strumenti insieme alla barra in basso, non insieme a quella laterale.
        let hidden = (chrome?.hidesBar ?? false) && !regular
        content
            .environment(\.tabReselection, glass ? 0 : reselection)
            .toolbarVisibility(glass && !hidden ? .automatic : .hidden, for: .tabBar)
            // Le pagine (dentro le loro pile di navigazione) lasciano lo spazio della barra.
            .environment(\.bottomBarInset, glass || hidden || regular ? 0 : M3NavigationBar.height)
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
            // La ricerca sta nella barra in cima alla Dashboard, come nelle app Google.
            ForEach(MainTabView.AppTab.mainTabs, id: \.self) { tab in
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
