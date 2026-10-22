import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tabChrome) private var tabChrome
    @Environment(\.windowClass) private var windowClass
    /// Cambia quando si tocca di nuovo la scheda Dashboard (iOS): si torna in cima alla
    /// pagina o, se si è già in cima, alla giornata di domani.
    var reselection = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var isAtTop = true
    /// Cambio di giorno con la transizione ad asse condiviso (anche scorrendo di lato).
    @State private var swipe = DaySwipe()
    /// Si apre sul giorno dopo, come richiesto: è quello per cui servono i compiti.
    @State private var selectedDay = Date().adding(days: DashboardView.initialOffset).startOfDay
    /// Larghezza della barra di navigazione, per capire se il titolo esteso ci sta.
    @State private var barWidth: CGFloat = 0
    /// "Domani" nella barra (vedi `onChange` del giorno scelto).
    @State private var showsTomorrow = false
    /// Ricerca aperta dalla barra in alto (senza Liquid Glass).
    @State private var searching = false
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool
    @State private var switchingAccount = false
    @State private var pickingDate = false

    private var mode: DashboardMode { model.preferences.dashboardMode }

    private static var initialOffset: Int {
        #if DEBUG
        // Per gli screenshot di sviluppo: `-BCWDaysAgo 1` apre su ieri.
        if UserDefaults.standard.object(forKey: "BCWDaysAgo") != nil {
            return -UserDefaults.standard.integer(forKey: "BCWDaysAgo")
        }
        #endif
        return 1
    }

    /// Titolo della barra con Liquid Glass: "Giovedì 1 ottobre" oppure, se non entra (o se
    /// l'utente lo preferisce), la forma breve "Gio 1 ott".
    private var title: String {
        switch model.preferences.titleAbbreviation {
        case .never: selectedDay.relativeDayName
        case .always: selectedDay.relativeShortDayName
        case .automatic: titleFits(selectedDay.relativeDayName) ? selectedDay.relativeDayName : selectedDay.relativeShortDayName
        }
    }

    private func titleFits(_ text: String) -> Bool {
        guard barWidth > 0 else { return true }
        let titleFont = Typography.platformFont(size: 34, weight: 500, rounded: true)
        let titleWidth = (text as NSString).size(withAttributes: [.font: titleFont]).width
        // Margini laterali, pulsante del menu e spazio dal titolo.
        var reserved: CGFloat = 16 + 16 + 44 + 16
        if !selectedDay.isTomorrow {
            let buttonText = ("Domani" as NSString).size(withAttributes: [.font: Typography.platformFont(size: 14, weight: 600)]).width
            reserved += buttonText + 32 + 12
        }
        return titleWidth <= barWidth - reserved
    }

    var body: some View {
        PlatformNavigationStack {
            ZStack {
                content
                if searching {
                    // Vista di ricerca di Material 3: i risultati prendono il posto della pagina
                    // (dissolvenza incrociata), la barra resta sospesa in alto.
                    SearchView(query: $searchQuery, embedded: true)
                        .transition(.fadeThrough)
                        .zIndex(1)
                }
            }
            // Per abbreviare il titolo quando non entra.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
            .onChange(of: selectedDay, initial: true) { _, day in
                guard showsTomorrow == day.isTomorrow else { return }
                withAnimation(Motion.spatial) { showsTomorrow = !day.isTomorrow }
            }
            .onChange(of: searching) { _, searching in
                tabChrome?.hidesBar = searching
                if searching {
                    searchFocused = true
                } else {
                    searchFocused = false
                    searchQuery = ""
                }
            }
            .onDisappear { if searching { tabChrome?.hidesBar = false } }
            // Sull'iPad largo la ricerca è nella barra superiore della finestra.
            .onChange(of: windowClass) { _, windowClass in
                if windowClass == .regular && searching { searching = false }
            }
            .modifier(DashboardChrome(title: windowClass == .regular ? "Dashboard" : title, regular: windowClass == .regular,
                                      query: $searchQuery, searching: $searching, focus: $searchFocused) {
                let glass = ThemeStore.shared.liquidGlass
                let regular = windowClass == .regular
                // Con Liquid Glass sul telefono il giorno è il titolo della barra e "Domani" sta accanto;
                // altrimenti "Domani" è accanto al giorno in grande.
                if showsTomorrow && glass && !regular {
                    BarTextButton(title: "Domani") {
                        select(Date().adding(days: 1).startOfDay)
                    }
                    .help("Vai a domani")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                viewMenu
                // L'avatar: nella barra di ricerca (Material sul telefono) e, sull'iPad largo con
                // Liquid Glass, tra le azioni (senza Liquid Glass è nella barra superiore della finestra).
                if (!glass && !regular) || (glass && regular) {
                    AccountAvatarButton { switchingAccount = true }
                }
            })
            .sheet(isPresented: $switchingAccount) {
                AccountSwitcherSheet()
            }
            .sheet(isPresented: $pickingDate) {
                M3DatePickerSheet(selection: selectedDay) { select($0.startOfDay) }
            }
        }
    }

    /// Vista (lista o calendario) e filtri.
    private var viewMenu: some View {
        BarMenu(icon: mode == .list ? "viewAgenda" : "calendarMonth", label: "Vista e filtri") {
            MenuPicker(title: "Vista", selection: Binding(get: { mode }, set: { new in
                model.preferences.dashboardMode = new
            }), options: DashboardMode.allCases.map { ($0, $0.title, $0.icon) })
            MenuDivider()
            MenuItem("Vai a oggi", icon: "sun") {
                select(Date().startOfDay)
            }
            MenuItem("Nascondi compiti fatti", icon: "checkCircle", checked: model.preferences.hideCompletedHomework) {
                model.preferences.hideCompletedHomework.toggle()
            }
            if mode == .list {
                MenuItem("Mostra i prossimi giorni", icon: "timeline", checked: model.preferences.showUpcomingDays) {
                    model.preferences.showUpcomingDays.toggle()
                }
            }
        }
    }

    /// Cambia il giorno scelto con la transizione ad asse condiviso, nel verso giusto.
    private func select(_ day: Date) {
        let day = day.startOfDay
        guard !day.isSameDay(as: selectedDay) else { return }
        swipe.go(day > selectedDay ? 1 : -1) { selectedDay = day }
    }

    private var daySelection: Binding<Date> {
        Binding { selectedDay } set: { select($0) }
    }

    /// Vista Calendario: sempre il mese; vista Lista: sempre la settimana.
    private var showsMonth: Bool { mode == .calendar }

    @ViewBuilder
    private var content: some View {
        // In alto la settimana (o il mese), ferma; sotto il giorno, che scorre.
        VStack(spacing: 0) {
            CalendarBar(selectedDay: daySelection, showsMonth: showsMonth,
                        pickDate: { pickingDate = true })

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = model.lastError {
                        StatusBanner(message: error, icon: model.isOffline ? "wifiOff" : "alertTriangle")
                    }
                    DayPage(swipe: swipe, day: selectedDay) { day in
                        VStack(alignment: .leading, spacing: 20) {
                            DayDetail(day: day, jump: day.isTomorrow ? nil : ("Domani", {
                                select(Date().adding(days: 1).startOfDay)
                            }))
                            if mode == .list && model.preferences.showUpcomingDays {
                                UpcomingDays(after: day) { select($0) }
                                    .equatable()
                            }
                        }
                    }
                }
                .pagePadding()
                .padding(.top, 4)
                .padding(.bottom, 32)
                .background { DaySwipeGesture(swipe: swipe) }
            }
            .refreshable { await model.refreshAll() }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
            } action: { _, atTop in
                isAtTop = atTop
            }
        }
        .onAppear {
            swipe.onSwipe = { direction in
                select(selectedDay.adding(days: direction))
            }
        }
        // Un widget ha aperto la Dashboard su un giorno.
        .onChange(of: model.openedLink, initial: true) { _, link in
            guard case let .dashboard(day) = link else { return }
            model.openedLink = nil
            if searching { searching = false }
            if let day { select(day) }
        }
        .onChange(of: reselection) {
            if !isAtTop {
                withAnimation(Motion.spatialSlow) { scrollPosition.scrollTo(edge: .top) }
            } else {
                select(Date().adding(days: 1).startOfDay)
            }
        }
        .themedBackground()
    }
}

// MARK: - Giorni successivi

private struct UpcomingDays: View {
    @Environment(AppModel.self) private var model
    let after: Date
    let onSelect: (Date) -> Void

    /// I 20 giorni dopo `after` che hanno qualcosa, dall'indice per giorno (prima si filtrava e
    /// raggruppava l'intera agenda a ogni cambio di giorno).
    static func days(after: Date, model: AppModel) -> [(Date, [AgendaEvent])] {
        let preferences = model.preferences
        let start = after.startOfDay
        return (1...20).compactMap { offset in
            let day = start.adding(days: offset)
            let events = model.events(on: day)
                .filter { !(preferences.hideCompletedHomework && preferences.isCompleted($0)) }
            guard !events.isEmpty else { return nil }
            return (day, events.sorted { ($0.kind == .test ? 0 : 1) < ($1.kind == .test ? 0 : 1) })
        }
    }

    private var isCollapsed: Bool { model.preferences.isCollapsed(.upcoming) }

    var body: some View {
        // Calcolati una volta per aggiornamento e passati all'elenco.
        let days = Self.days(after: after, model: model)
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(Motion.spatial) { model.preferences.toggleCollapsed(.upcoming) }
                } label: {
                    SectionHeader(title: "Nei prossimi giorni") {
                        Chevron(collapsed: isCollapsed)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(HeaderButtonStyle())
                .sensoryFeedback(.selection, trigger: isCollapsed)

                CollapsibleContent(isExpanded: !isCollapsed, spacing: 12) {
                    upcomingList(days)
                }
            }
        }
    }

    private func upcomingList(_ days: [(Date, [AgendaEvent])]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(days, id: \.0) { day, events in
                UpcomingDayCard(day: day, events: events) { onSelect(day) }
                    .equatable()
            }
        }
    }
}

/// Si ricalcolano solo se cambiano i giorni (`.equatable()`): i dati letti dal modello li
/// aggiornano comunque. La chiusura cambia a ogni aggiornamento della Dashboard ma fa sempre la
/// stessa cosa, e confrontandola la sezione (con tutte le righe) si ricalcolava a ogni fotogramma
/// in cui cambiava qualcosa della pagina, es. scorrendo di lato.
extension UpcomingDays: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.after == rhs.after }
}

/// Un giorno in "Nei prossimi giorni", come nella vista Programma di Google Calendar: a sinistra
/// la data in un riquadro (solo toccandola si va a quel giorno), a destra il nome del giorno, che
/// comprime gli elementi, e gli elementi in una lista segmentata, con i loro tocchi (casella del
/// compito, testo che si apre, menu). Lo stato compresso resta finché la Dashboard è aperta.
private struct UpcomingDayCard: View {
    let day: Date
    let events: [AgendaEvent]
    let onSelect: () -> Void
    @State private var isCollapsed = false

    var body: some View {
        LeadingColumnLayout(spacing: 12) {
            Button(action: onSelect) {
                DateBadge(day: day, highlighted: events.contains { $0.kind == .test })
            }
            .buttonStyle(.pressable(radius: Theme.radii.l, pressed: Theme.radii.m))
            .accessibilityLabel("Vai a \(day.relativeDayName)")

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(Motion.spatial) { isCollapsed.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(day.relativeDayName)
                                .font(.m3(16, weight: 600))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text(summary)
                                .font(.m3(13))
                                .foregroundStyle(Theme.secondaryInk)
                                .contentTransition(.opacity)
                        }
                        Spacer()
                        Chevron(collapsed: isCollapsed)
                    }
                    .frame(minHeight: 58)
                    .contentShape(.rect)
                }
                .buttonStyle(HeaderButtonStyle())
                .sensoryFeedback(.selection, trigger: isCollapsed)
                .accessibilityHint(isCollapsed ? "Mostra gli elementi" : "Nasconde gli elementi")

                CollapsibleContent(isExpanded: !isCollapsed, spacing: 0) {
                    ListGroup {
                        ForEach(events) { event in
                            SegmentCell(padding: 14) {
                                AgendaEventRow(event: event)
                                    .equatable()
                            }
                        }
                    }
                }
            }
        }
    }

    private var summary: String {
        let tests = events.filter { $0.kind == .test }.count
        let homework = events.filter { $0.kind == .homework }.count
        let other = events.count - tests - homework
        var parts: [String] = []
        if tests > 0 { parts.append(tests == 1 ? "1 verifica" : "\(tests) verifiche") }
        if homework > 0 { parts.append(homework == 1 ? "1 compito" : "\(homework) compiti") }
        if other > 0 { parts.append(other == 1 ? "1 evento" : "\(other) eventi") }
        return parts.joined(separator: " · ")
    }
}

/// Come `UpcomingDays`: si ricalcola solo se cambiano il giorno o i suoi elementi.
extension UpcomingDayCard: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.day == rhs.day && lhs.events == rhs.events }
}

/// Barra della Dashboard. Con Liquid Glass è quella di sistema con il giorno come titolo (la ricerca
/// ha la sua scheda); altrimenti la barra di ricerca di M3 Expressive, sospesa, con la vista e
/// l'avatar dell'account a destra: toccandola diventa il campo di ricerca (con la freccia per
/// tornare indietro) e i risultati prendono il posto della pagina.
private struct DashboardChrome<Actions: View>: ViewModifier {
    let title: String
    /// iPad con la finestra largo: titolo "Dashboard" (la ricerca è nella barra della finestra).
    let regular: Bool
    @Binding var query: String
    @Binding var searching: Bool
    var focus: FocusState<Bool>.Binding
    @ViewBuilder let actions: () -> Actions
    @Environment(\.bottomBarInset) private var bottomBarInset

    func body(content: Content) -> some View {
        if ThemeStore.shared.liquidGlass || regular {
            content.pageChrome(title, style: .inline, actions: actions)
        } else {
            content
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: bottomBarInset) }
                .safeAreaInset(edge: .top, spacing: 0) {
                    SearchAppBar(prompt: "Cerca nel registro", activePrompt: SearchView.prompt, query: $query,
                                 isActive: $searching, focus: focus, trailing: actions)
                }
        }
    }
}
