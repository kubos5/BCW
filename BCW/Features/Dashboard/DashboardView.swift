import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    /// Cambia quando si tocca di nuovo la scheda Dashboard (iOS): si torna in cima alla
    /// pagina o, se si è già in cima, alla giornata di domani.
    var reselection = 0
    #if os(iOS)
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var isAtTop = true
    /// Calendario mobile, intero o ridotto (`CalendarHeader`).
    @State private var headerState = WeekHeaderScroll()
    #endif
    /// Si apre sul giorno dopo, come richiesto: è quello per cui servono i compiti.
    @State private var selectedDay = Date().adding(days: DashboardView.initialOffset).startOfDay
    /// Larghezza della barra di navigazione, per capire se il titolo esteso ci sta.
    @State private var barWidth: CGFloat = 0
    /// "Domani" nella barra (vedi `onChange` del giorno scelto).
    @State private var showsTomorrow = false
    #if os(macOS)
    /// Identità dei giorni successivi: cambia (con transizione) solo quando cambia il giorno
    /// scelto e con esso il contenuto della sezione espansa (vedi `select`). Su iPhone è il giorno
    /// della pagina (`upcoming(after:)`).
    @State private var upcomingGeneration = 0
    #endif
    /// Altezza del giorno scelto: i giorni successivi si spostano di altrettanto nella
    /// transizione, così si muovono come il contenuto principale (vedi `upcomingTransition`).
    /// Non è uno stato osservato: aprendo una sezione l'altezza cambia a ogni fotogramma, e
    /// ridisegnare l'intera Dashboard (calendario compreso) ogni volta rallentava l'animazione.
    /// Serve solo quando cambia il giorno, e allora la vista si aggiorna comunque.
    @State private var dayDetailHeight = UnobservedValue<CGFloat>(300)

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

    /// Titolo grande: "Giovedì 1 ottobre" oppure, se non entra (o se l'utente lo
    /// preferisce), la forma breve "Gio 1 ott".
    private var title: String {
        switch model.preferences.titleAbbreviation {
        case .never: selectedDay.relativeDayName
        case .always: selectedDay.relativeShortDayName
        case .automatic: titleFits(selectedDay.relativeDayName) ? selectedDay.relativeDayName : selectedDay.relativeShortDayName
        }
    }

    private func titleFits(_ text: String) -> Bool {
        // Su macOS il titolo sta nella barra della finestra, dove c'è sempre spazio.
        guard !Platform.isMac, barWidth > 0 else { return true }
        let glass = ThemeStore.shared.liquidGlass
        let titleFont = glass ? Typography.platformFont(size: 34, weight: 500, rounded: true)
            : Typography.platformFont(size: 22, weight: 500, rounded: true)
        let titleWidth = (text as NSString).size(withAttributes: [.font: titleFont]).width
        // Margini laterali, pulsante del menu e spazio dal titolo.
        var reserved: CGFloat = glass ? 16 + 16 + 44 + 16 : 16 + 48 + 8
        if !selectedDay.isTomorrow {
            let buttonText = ("Domani" as NSString).size(withAttributes: [.font: Typography.platformFont(size: 14, weight: 600)]).width
            reserved += buttonText + (glass ? 32 + 12 : 24 + 8)
        }
        return titleWidth <= barWidth - reserved
    }

    var body: some View {
        PlatformNavigationStack {
            content
                #if os(iOS)
                // Solo per abbreviare il titolo su iPhone: su Mac ricalcolerebbe la pagina a ogni
                // fotogramma mentre si ridimensiona la finestra.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
                #endif
                .refreshable { await model.refreshAll() }
                .onChange(of: selectedDay, initial: true) { _, day in
                    // Sempre con un'animazione, anche quando il giorno cambia senza (scorrendo di lato).
                    guard showsTomorrow == day.isTomorrow else { return }
                    withAnimation(Motion.spatial) { showsTomorrow = !day.isTomorrow }
                }
                .pageChrome(title, style: .inline) {
                    if showsTomorrow {
                        BarTextButton(title: "Domani") {
                            select(Date().adding(days: 1).startOfDay)
                        }
                        .keyboardShortcut("t", modifiers: [.command, .shift])
                        .help("Vai a domani (⇧⌘T)")
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    viewMenu
                }
        }
    }

    /// Vista (lista o calendario) e filtri.
    private var viewMenu: some View {
        BarMenu(icon: mode.icon, label: "Vista e filtri") {
            MenuPicker(title: "Vista", selection: Bindable(model.preferences).dashboardMode,
                       options: DashboardMode.allCases.map { ($0, $0.title, $0.icon) })
            MenuDivider()
            MenuItem("Vai a oggi", icon: "sun") {
                select(Date().startOfDay)
            }
            MenuItem("Nascondi compiti fatti", icon: "checkCircle", checked: model.preferences.hideCompletedHomework) {
                model.preferences.hideCompletedHomework.toggle()
            }
            if mode == .list || Platform.isMac {
                MenuItem("Mostra i prossimi giorni", icon: "timeline", checked: model.preferences.showUpcomingDays) {
                    model.preferences.showUpcomingDays.toggle()
                }
            }
        }
    }

    /// Cambia il giorno scelto. Nella stessa transazione può cambiare anche l'identità dei
    /// giorni successivi, così la sezione vecchia esce con il contenuto vecchio e quella nuova
    /// entra insieme al giorno: su iOS sempre (l'identità è il giorno), su macOS solo se la sezione
    /// è espansa e il suo contenuto cambia davvero.
    private func select(_ day: Date, animated: Bool = true) {
        guard !day.isSameDay(as: selectedDay) else { return }
        #if os(macOS)
        let replacesUpcoming = !model.preferences.isCollapsed(.upcoming)
            && upcomingKey(after: selectedDay) != upcomingKey(after: day)
        let update = {
            selectedDay = day
            if replacesUpcoming { upcomingGeneration += 1 }
        }
        #else
        let update = { selectedDay = day }
        #endif
        if animated { withAnimation(Motion.spatial, update) } else { update() }
    }

    /// Per le viste del calendario, che animano da sé la selezione.
    private var daySelection: Binding<Date> {
        Binding { selectedDay } set: { select($0, animated: false) }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        // Calendario e giorni successivi restano a sinistra mentre si legge il giorno scelto.
        SplitColumns(sideWidth: 340) {
            calendar
            // Con le colonne impilate i giorni successivi vanno in fondo, dopo il giorno scelto.
            StackAware { stacked in
                if !stacked { upcoming }
            }
        } main: {
            if let error = model.lastError {
                StatusBanner(message: error, icon: model.isOffline ? "wifiOff" : "alertTriangle")
            }
            DayDetail(day: selectedDay)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if $0 > 0 { dayDetailHeight.value = $0 } }
                .id(selectedDay)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            StackAware { stacked in
                if stacked { upcoming }
            }
        }
        .animation(Motion.spatial, value: selectedDay)
        #else
        // Il calendario (settimana o mese) galleggia sopra il contenuto (`CalendarHeader`), come
        // nell'Orario: il contenuto parte sotto il calendario ridotto e si sposta con lui.
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = model.lastError {
                        StatusBanner(message: error, icon: model.isOffline ? "wifiOff" : "alertTriangle")
                    }

                    // Con il giorno accanto, già visibile mentre si scorre di lato.
                    SwipeDayPages(state: headerState, day: selectedDay) { day, isMain in
                        VStack(alignment: .leading, spacing: 16) {
                            DayDetail(day: day)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                    if isMain && $0 > 0 { dayDetailHeight.value = $0 }
                                }
                                .id(day)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))

                            if mode == .list {
                                upcoming(after: day)
                            }
                        }
                    }
                }
                .pagePadding()
                .padding(.bottom, 32)
                .animation(Motion.spatial, value: selectedDay)
                .background { CalendarHeaderPan(state: headerState) }
            }
            .tracksPageScroll()
            // Il giorno accanto sta fuori dai bordi dello scorrimento finché non entra.
            .scrollClipDisabled()
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 1
            } action: { _, atTop in
                isAtTop = atTop
            }
            .safeAreaPadding(.top, 4 + CalendarHeader.collapsedHeight + 16)
            .modifier(WeekHeaderScroll.Shift(state: headerState))

            DashboardHeaderHost(selectedDay: daySelection, style: mode == .list ? .week : .month, state: headerState)
                .padding(.horizontal)
                .padding(.top, 4)
        }
        .onAppear {
            // Da calendario intero si può tirare giù per aggiornare; scorrendo di lato si cambia giorno.
            headerState.expandedScrolls = true
            headerState.onSwipeDay = { direction in
                // Il contenuto è fuori dallo schermo: si cambia senza le transizioni del giorno.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    select(selectedDay.adding(days: direction).startOfDay, animated: false)
                }
            }
        }
        .onChange(of: mode) { headerState.reset() }
        .onChange(of: reselection) {
            if !isAtTop {
                withAnimation(Motion.spatialSlow) { scrollPosition.scrollTo(edge: .top) }
            } else if headerState.isCollapsed {
                headerState.open()
            } else {
                select(Date().adding(days: 1).startOfDay)
            }
        }
        .themedBackground()
        #endif
    }

    #if os(iOS)
    /// I giorni successivi di una pagina: cambiano (con la transizione) insieme al suo giorno. Su
    /// iPhone l'identità è il giorno stesso e non `upcomingGeneration`: così, quando le pagine si
    /// scambiano di ruolo scorrendo di lato, non vengono ricostruiti.
    @ViewBuilder
    private func upcoming(after day: Date) -> some View {
        if model.preferences.showUpcomingDays {
            UpcomingDays(after: day) { day in
                select(day)
            }
            .equatable()
            .id(day)
            .transition(upcomingTransition)
        }
    }
    #endif

    #if os(macOS)
    /// I giorni successivi cambiano insieme al giorno scelto, con la stessa transizione,
    /// ma solo se il loro contenuto cambia davvero: da compressi o con gli stessi giorni ed
    /// eventi restano fermi. L'identità non dipende dallo stato compresso, altrimenti
    /// comprimere ed espandere sostituirebbe l'intera sezione (intestazione compresa).
    @ViewBuilder
    private var upcoming: some View {
        if model.preferences.showUpcomingDays {
            UpcomingDays(after: selectedDay) { day in
                select(day)
            }
            .id(upcomingGeneration)
            .transition(upcomingTransition)
        }
    }
    #endif

    /// Il giorno scelto usa `.move(edge:)`, che sposta una vista di tutta la sua altezza: con la
    /// stessa transizione i giorni successivi si sposterebbero troppo da aperti (settimane di card)
    /// e troppo poco da chiusi (solo l'intestazione). Si spostano invece quanto il giorno scelto,
    /// così si muovono insieme al resto del contenuto.
    private var upcomingTransition: AnyTransition {
        .opacity.combined(with: .offset(y: dayDetailHeight.value))
    }

    private func upcomingKey(after day: Date) -> String {
        UpcomingDays.days(after: day, model: model)
            .map { day, events in "\(CVDate.dayKey(day)):\(events.map { String($0.id) }.joined(separator: ","))" }
            .joined(separator: "|")
    }

    @ViewBuilder
    private var calendar: some View {
        switch mode {
        case .list:
            WeekStrip(selectedDay: daySelection)
        case .calendar:
            MonthCalendar(selectedDay: daySelection)
        }
    }
}

#if os(iOS)
/// Il calendario con l'avanzamento dello stato, letto solo qui (cambia a ogni fotogramma).
private struct DashboardHeaderHost: View {
    @Binding var selectedDay: Date
    let style: CalendarHeader.Style
    let state: WeekHeaderScroll

    var body: some View {
        CalendarHeader(selectedDay: $selectedDay, style: style, progress: state.progress, onExpand: state.open) { height in
            state.range = height - CalendarHeader.collapsedHeight
        }
    }
}
#endif

// MARK: - Striscia settimanale

struct WeekStrip: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedDay: Date
    /// Settimana mostrata (inizio settimana): segue lo scorrimento orizzontale a pagine.
    @State private var visibleWeek: Date?

    /// Settimane disponibili: due anni prima e dopo oggi.
    private static let weeks: [Date] = {
        let current = Date().startOfWeek
        return (-104...104).map { current.adding(days: $0 * 7) }
    }()

    init(selectedDay: Binding<Date>) {
        _selectedDay = selectedDay
        _visibleWeek = State(initialValue: Self.week(containing: selectedDay.wrappedValue))
    }

    private static func week(containing day: Date) -> Date {
        let start = day.startOfWeek
        // Le settimane sono già inizi di settimana: basta l'uguaglianza, molto più rapida
        // del confronto con il calendario (chiamato a ogni aggiornamento della striscia).
        return weekSet.contains(start) ? start : (weeks.first { $0.isSameDay(as: start) } ?? start)
    }

    private static let weekSet = Set(weeks)

    var body: some View {
        VStack(spacing: 0) {
            CalendarCardHead(title: selectedDay.monthYear, previousLabel: "Settimana precedente",
                             nextLabel: "Settimana successiva") { shift(-7) } next: { shift(7) }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Self.weeks, id: \.self) { week in
                        HStack(spacing: 2) {
                            ForEach(0..<7, id: \.self) { offset in
                                let day = week.adding(days: offset)
                                DayCell(day: day, isSelected: day.isSameDay(as: selectedDay)) {
                                    selectedDay = day
                                }
                            }
                        }
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleWeek)
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Theme.surfaceContainer, in: .rect(cornerRadius: Theme.radii.xl, style: .continuous))
        .onChange(of: visibleWeek) { _, week in
            // Scorrendo si passa alla settimana accanto mantenendo lo stesso giorno della settimana.
            guard let week, !week.isSameDay(as: selectedDay.startOfWeek) else { return }
            let weekday = CVDate.calendar.dateComponents([.day], from: selectedDay.startOfWeek, to: selectedDay.startOfDay).day ?? 0
            selectedDay = week.adding(days: weekday)
        }
        .onChange(of: selectedDay) { _, day in
            let week = Self.week(containing: day)
            if visibleWeek.map({ !$0.isSameDay(as: week) }) ?? true {
                withAnimation(Motion.spatial) { visibleWeek = week }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
    }

    private func shift(_ days: Int) {
        withAnimation(Motion.spatial) { selectedDay = selectedDay.adding(days: days) }
    }
}

/// Intestazione delle card del calendario: mese e anno, frecce per spostarsi.
struct CalendarCardHead: View {
    let title: String
    var previousLabel = "Precedente"
    var nextLabel = "Successivo"
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.m3(16, weight: 650))
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Spacer()
            HStack(spacing: 4) {
                IconButton("chevronLeft", label: previousLabel, size: 32, action: previous)
                IconButton("chevronRight", label: nextLabel, size: 32, action: next)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 44)
    }
}

private struct DayCell: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let events = model.events(on: day)
        let hasTest = events.contains { $0.kind == .test }
        let hasHomework = events.contains { $0.kind == .homework }
        let hasOther = events.contains { $0.kind == .event }
        let hasAbsence = !model.absences(on: day).isEmpty
        let holiday = model.calendarStatus(on: day)?.isHoliday == true
        let emphasized = isSelected || day.isToday

        Button(action: action) {
            VStack(spacing: 2) {
                Text(day.it("EEEEE").uppercased())
                    .font(.m3(12, weight: emphasized ? 700 : 600))
                    .foregroundStyle(isSelected ? Theme.onPrimary : (day.isToday ? Theme.primary : Theme.secondaryInk))
                Text(day.it("d"))
                    .font(.numeral(18, weight: emphasized ? 700 : 550))
                    .foregroundStyle(numberColor(holiday: holiday))
                    .frame(width: 40, height: 40)
                HStack(spacing: 3) {
                    if hasHomework { dot(Theme.neutral) }
                    if hasTest { dot(isSelected ? Theme.onPrimary : Theme.primary) }
                    if hasOther { dot(Theme.fair) }
                    if hasAbsence { dot(Theme.poor) }
                }
                .frame(height: 6)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 76, alignment: .top)
            // Si può fare clic su tutto il riquadro, non solo sul testo.
            .contentShape(.rect(cornerRadius: Theme.radii.li))
            .background {
                let shape = RoundedRectangle(cornerRadius: Theme.radii.li, style: .continuous)
                if isSelected {
                    shape.fill(Theme.primary)
                } else if day.isToday {
                    shape.strokeBorder(Theme.primary, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.longDay)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func numberColor(holiday: Bool) -> Color {
        if isSelected { return Theme.onPrimary }
        if day.isToday { return Theme.primary }
        if day.isWeekend || holiday { return Theme.secondaryInk }
        return Theme.ink
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 5, height: 5)
    }
}

// MARK: - Giorni successivi

private struct UpcomingDays: View {
    @Environment(AppModel.self) private var model
    let after: Date
    let onSelect: (Date) -> Void

    static func days(after: Date, model: AppModel) -> [(Date, [AgendaEvent])] {
        let start = after.adding(days: 1)
        let end = after.adding(days: 21)
        let upcoming = model.agenda.filter { $0.begin >= start && $0.begin < end }
            .filter { !(model.preferences.hideCompletedHomework && model.preferences.isCompleted($0)) }
        return Dictionary(grouping: upcoming, by: \.day)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value.sorted { ($0.kind == .test ? 0 : 1) < ($1.kind == .test ? 0 : 1) }) }
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
        VStack(alignment: .leading, spacing: 12) {
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

/// Un giorno in "Nei prossimi giorni". Toccando l'intestazione si comprime (come le altre
/// sezioni); toccando un punto del contenuto che non fa già qualcosa si va a quel giorno: non la
/// casella di un compito, né il testo di un evento tagliato (che si apre); i margini e le righe
/// con il testo intero sì. Lo stato compresso resta
/// finché la Dashboard è aperta.
private struct UpcomingDayCard: View {
    let day: Date
    let events: [AgendaEvent]
    let onSelect: () -> Void
    @State private var isCollapsed = false

    var body: some View {
        let lastID = events.last?.id
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.spatial) { isCollapsed.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Eyebrow(text: day.relativeDayName, color: Theme.primary)
                    Spacer()
                    if isCollapsed {
                        Text(events.count == 1 ? "1 elemento" : "\(events.count) elementi")
                            .font(.m3(12))
                            .foregroundStyle(Theme.secondaryInk)
                            .transition(.opacity)
                    }
                    Chevron(collapsed: isCollapsed)
                }
                .frame(minHeight: 36)
                .contentShape(.rect)
            }
            .buttonStyle(HeaderButtonStyle())
            .sensoryFeedback(.selection, trigger: isCollapsed)
            .accessibilityHint(isCollapsed ? "Mostra gli elementi" : "Nasconde gli elementi")

            CollapsibleContent(isExpanded: !isCollapsed, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(events) { event in
                        AgendaEventRow(event: event, onPlainTap: onSelect)
                            .equatable()
                        if event.id != lastID { M3Divider() }
                    }
                }
            }
        }
        .padding(.top, -4)
        .card()
        // Intestazione e righe hanno i loro tocchi (comprimere, aprire, segnare come fatto), che
        // hanno la precedenza: questo vale solo negli spazi vuoti, margini della card compresi.
        .contentShape(.rect(cornerRadius: Theme.corner))
        .onTapGesture(perform: onSelect)
        .accessibilityAction(named: "Vai a \(day.relativeDayName)", onSelect)
    }
}

/// Come `UpcomingDays`: si ricalcola solo se cambiano il giorno o i suoi elementi.
extension UpcomingDayCard: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.day == rhs.day && lhs.events == rhs.events }
}
