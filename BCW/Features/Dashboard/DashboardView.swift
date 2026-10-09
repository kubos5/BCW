import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    /// Cambia quando si tocca di nuovo la scheda Dashboard (iOS): si torna in cima alla
    /// pagina o, se si è già in cima, alla giornata di domani.
    var reselection = 0
    #if os(iOS)
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var isAtTop = true
    #endif
    /// Si apre sul giorno dopo, come richiesto: è quello per cui servono i compiti.
    @State private var selectedDay = Date().adding(days: DashboardView.initialOffset).startOfDay
    /// Larghezza della barra di navigazione, per capire se il titolo esteso ci sta.
    @State private var barWidth: CGFloat = 0
    /// Identità dei giorni successivi: cambia (con transizione) solo quando cambia il giorno
    /// scelto e con esso il contenuto della sezione espansa (vedi `select`).
    @State private var upcomingGeneration = 0
    #if os(macOS)
    /// Allineamento del menu della vista al bordo destro del calendario (coordinate della
    /// finestra). Si misurano solo elementi di larghezza fissa che stanno prima del menu
    /// (Oggi e Domani) e il menu stesso: niente dipende dal distanziatore, quindi non ci sono
    /// misure che si inseguono.
    @State private var calendarMaxX: CGFloat = 0
    @State private var todayMaxX: CGFloat = 0
    @State private var tomorrowFrame: CGRect = .zero
    @State private var menuWidth: CGFloat = 36
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
        let titleWidth = (text as NSString).size(withAttributes: [.font: PlatformFont.newYork(size: 34, weight: .bold)]).width
        // Margini laterali, pulsante del menu e spazio dal titolo.
        var reserved: CGFloat = 16 + 16 + 44 + 16
        if !selectedDay.isTomorrow {
            let buttonText = ("Domani" as NSString).size(withAttributes: [.font: PlatformFont.newYork(size: 17, weight: .regular)]).width
            reserved += buttonText + 32 + 12
        }
        return titleWidth <= barWidth - reserved
    }

    var body: some View {
        PlatformNavigationStack {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
                .refreshable { await model.refreshAll() }
                .toolbar {
                    #if os(macOS)
                    // Su macOS lo spostamento tra i giorni sta accanto al titolo, con le scorciatoie.
                    ToolbarItemGroup(placement: .navigation) {
                        Button("Giorno precedente", systemImage: "chevron.left") { shift(-1) }
                            .keyboardShortcut(.leftArrow, modifiers: .command)
                            .help("Giorno precedente (⌘←)")
                        Button("Giorno successivo", systemImage: "chevron.right") { shift(1) }
                            .keyboardShortcut(.rightArrow, modifiers: .command)
                            .help("Giorno successivo (⌘→)")
                        Button("Oggi") { jump(to: Date()) }
                            .keyboardShortcut("t")
                            .disabled(selectedDay.isToday)
                            .help("Vai a oggi (⌘T)")
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxX } action: { todayMaxX = $0 }
                        Button("Domani") { jump(to: Date().adding(days: 1)) }
                            .keyboardShortcut("t", modifiers: [.command, .shift])
                            .disabled(selectedDay.isTomorrow)
                            .help("Vai a domani (⇧⌘T)")
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { tomorrowFrame = $0 }
                    }
                    // Il menu della vista sta nella barra, allineato al bordo destro del calendario
                    // da un distanziatore. La barra non ridimensiona bene un elemento che cambia
                    // larghezza (lo centra nel vecchio spazio e decide l'overflow su misure
                    // vecchie): a ogni nuova larghezza si inserisce quindi un elemento nuovo, e con
                    // le colonne impilate il distanziatore non c'è proprio.
                    let spacer = menuSpacer
                    if spacer > 0 {
                        ToolbarItem(id: "allineamento-menu-\(Int(spacer))", placement: .navigation) {
                            Color.clear
                                .frame(width: spacer, height: 1)
                                .accessibilityHidden(true)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                    ToolbarItem(placement: .navigation) {
                        viewMenu
                            .menuIndicator(.hidden)
                            .help("Vista e filtri")
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                                if width > 0 { menuWidth = width }
                            }
                    }
                    #else
                    if !selectedDay.isTomorrow {
                        ToolbarItem(placement: .trailingBar) {
                            Button("Domani") {
                                select(Date().adding(days: 1).startOfDay)
                            }
                        }
                        ToolbarSpacer(.fixed, placement: .trailingBar)
                    }
                    ToolbarItem(placement: .trailingBar) {
                        viewMenu
                    }
                    #endif
                }
                #if os(macOS)
                // Su macOS il titolo sta nel contenuto, sopra il calendario: nella barra della
                // finestra restano solo i comandi per spostarsi tra i giorni.
                .navigationTitle(title)
                .toolbar(removing: .title)
                #else
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inlineLarge)
                #endif
        }
    }

    /// Vista (lista o calendario) e filtri. Su macOS non ha "Vai a oggi", che è già un pulsante
    /// nella barra.
    private var viewMenu: some View {
        Menu {
            Picker("Vista", selection: Bindable(model.preferences).dashboardMode) {
                ForEach(DashboardMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            if !Platform.isMac {
                Button("Vai a oggi", systemImage: "sun.max") {
                    select(Date().startOfDay)
                }
            }
            Toggle("Nascondi compiti fatti", systemImage: "checkmark.circle",
                   isOn: Bindable(model.preferences).hideCompletedHomework)
            if mode == .list || Platform.isMac {
                Toggle("Mostra i prossimi giorni", systemImage: "calendar.day.timeline.right",
                       isOn: Bindable(model.preferences).showUpcomingDays)
            }
        } label: {
            Image(systemName: mode.symbol)
        }
    }

    /// Cambia il giorno scelto. Nella stessa transazione può cambiare anche l'identità dei
    /// giorni successivi, così la sezione vecchia esce con il contenuto vecchio e quella nuova
    /// entra insieme al giorno: su iOS sempre, su macOS solo se la sezione è espansa e il suo
    /// contenuto cambia davvero.
    private func select(_ day: Date, animated: Bool = true) {
        guard !day.isSameDay(as: selectedDay) else { return }
        #if os(macOS)
        let replacesUpcoming = !model.preferences.isCollapsed(.upcoming)
            && upcomingKey(after: selectedDay) != upcomingKey(after: day)
        #else
        let replacesUpcoming = true
        #endif
        let update = {
            selectedDay = day
            if replacesUpcoming { upcomingGeneration += 1 }
        }
        if animated { withAnimation(.snappy, update) } else { update() }
    }

    /// Per le viste del calendario, che animano da sé la selezione.
    private var daySelection: Binding<Date> {
        Binding { selectedDay } set: { select($0, animated: false) }
    }

    private func jump(to day: Date) {
        select(day.startOfDay)
    }

    private func shift(_ days: Int) {
        select(selectedDay.adding(days: days))
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        // Calendario e giorni successivi restano a sinistra mentre si legge il giorno scelto.
        SplitColumns(sideWidth: 340) {
            Text(title)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)
            calendar
            // Con le colonne impilate i giorni successivi vanno in fondo, dopo il giorno scelto.
            StackAware { stacked in
                if !stacked { upcoming }
            }
        } main: {
            if let error = model.lastError {
                StatusBanner(message: error, symbol: model.isOffline ? "wifi.slash" : "exclamationmark.triangle")
            }
            DayDetail(day: selectedDay)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if $0 > 0 { dayDetailHeight.value = $0 } }
                .id(selectedDay)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            StackAware { stacked in
                if stacked { upcoming }
            }
        }
        .animation(.snappy, value: selectedDay)
        .macToolbarBackground()
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let error = model.lastError {
                    StatusBanner(message: error, symbol: model.isOffline ? "wifi.slash" : "exclamationmark.triangle")
                }

                calendar

                DayDetail(day: selectedDay)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if $0 > 0 { dayDetailHeight.value = $0 } }
                    .id(selectedDay)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                if mode == .list {
                    upcoming
                }
            }
            .pagePadding()
            .padding(.bottom, 24)
            .animation(.snappy, value: selectedDay)
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top <= 1
        } action: { _, atTop in
            isAtTop = atTop
        }
        .onChange(of: reselection) {
            if isAtTop {
                select(Date().adding(days: 1).startOfDay)
            } else {
                withAnimation(.smooth) { scrollPosition.scrollTo(edge: .top) }
            }
        }
        .themedBackground()
        #endif
    }

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

    #if os(macOS)
    /// Larghezza del distanziatore davanti al menu della vista: il bordo destro del menu deve
    /// coincidere con quello del calendario. Tra due elementi della barra c'è sempre lo stesso
    /// spazio (misurato tra Oggi e Domani): uno prima e uno dopo il distanziatore.
    private var menuSpacer: CGFloat {
        // Con le colonne impilate (sotto i 780 punti di `SplitColumns`) il menu non si allinea.
        // Si controlla anche la larghezza attuale: all'apertura `SplitColumns` mostra per un
        // istante le due colonne, e quella misura del calendario può arrivare dopo l'altra.
        guard barWidth >= 780, calendarMaxX > 0, tomorrowFrame.width > 0 else { return 0 }
        let measuredGap = tomorrowFrame.minX - todayMaxX
        let gap = (0...30).contains(measuredGap) ? measuredGap : 8
        return max(0, (calendarMaxX - tomorrowFrame.maxX - 2 * gap - menuWidth).rounded())
    }
    #endif

    @ViewBuilder
    private var calendar: some View {
        Group {
            switch mode {
            case .list:
                WeekStrip(selectedDay: daySelection)
            case .calendar:
                MonthCalendar(selectedDay: daySelection)
            }
        }
        #if os(macOS)
        .modifier(CalendarEdgeReader { calendarMaxX = $0 })
        #endif
    }
}

#if os(macOS)
/// Riporta il bordo destro del calendario solo quando sta nella colonna laterale: con le
/// colonne impilate riporta 0. Legge lo stato dal layout stesso (`columnsStacked`), così la
/// misura non arriva mai in ritardo rispetto al cambio di colonne.
private struct CalendarEdgeReader: ViewModifier {
    @Environment(\.columnsStacked) private var stacked
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                stacked ? 0 : proxy.frame(in: .global).maxX
            } action: { onChange($0) }
            .onChange(of: stacked) { _, isStacked in if isStacked { onChange(0) } }
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
        VStack(spacing: 12) {
            HStack {
                Text(selectedDay.monthYear)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Spacer()
                HStack(spacing: 4) {
                    Button { shift(-7) } label: { Image(systemName: "chevron.left") }
                    Button { shift(7) } label: { Image(systemName: "chevron.right") }
                }
                .glassButton()
                .buttonBorderShape(.circle)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(Self.weeks, id: \.self) { week in
                        HStack(spacing: 4) {
                            ForEach(0..<7, id: \.self) { offset in
                                let day = week.adding(days: offset)
                                DayCell(day: day, isSelected: day.isSameDay(as: selectedDay)) {
                                    selectedDay = day
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleWeek)
            .scrollIndicators(.hidden)
        }
        .padding(.vertical, 14)
        .card(padding: 0)
        .onChange(of: visibleWeek) { _, week in
            // Scorrendo si passa alla settimana accanto mantenendo lo stesso giorno della settimana.
            guard let week, !week.isSameDay(as: selectedDay.startOfWeek) else { return }
            let weekday = CVDate.calendar.dateComponents([.day], from: selectedDay.startOfWeek, to: selectedDay.startOfDay).day ?? 0
            selectedDay = week.adding(days: weekday)
        }
        .onChange(of: selectedDay) { _, day in
            let week = Self.week(containing: day)
            if visibleWeek.map({ !$0.isSameDay(as: week) }) ?? true {
                withAnimation(.snappy) { visibleWeek = week }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
    }

    private func jump(to day: Date) {
        withAnimation(.snappy) { selectedDay = day.startOfDay }
    }

    private func shift(_ days: Int) {
        withAnimation(.snappy) { selectedDay = selectedDay.adding(days: days) }
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

        Button(action: action) {
            VStack(spacing: 6) {
                Text(day.it("EEEEE").uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryInk)
                Text(day.it("d"))
                    .font(.numeral(19, weight: isSelected || day.isToday ? .bold : .medium))
                    .foregroundStyle(numberColor(holiday: holiday))
                HStack(spacing: 3) {
                    if hasHomework { dot(Theme.neutral) }
                    if hasTest { dot(isSelected ? .white : Theme.accent) }
                    if hasOther { dot(Theme.fair) }
                    if hasAbsence { dot(Theme.poor) }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            // Si può fare clic su tutto il riquadro, non solo sul testo.
            .contentShape(.rect(cornerRadius: 16))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.accent.gradient)
                } else if day.isToday {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.longDay)
    }

    private func numberColor(holiday: Bool) -> Color {
        if isSelected { return .white }
        if day.isToday { return Theme.accent }
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
                    withAnimation(.snappy) { model.preferences.toggleCollapsed(.upcoming) }
                } label: {
                    SectionHeader(title: "Nei prossimi giorni") {
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.secondaryInk)
                            .rotationEffect(.degrees(isCollapsed ? -90 : 0))
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
                VStack(alignment: .leading, spacing: 12) {
                    Button { onSelect(day) } label: {
                        HStack {
                            Eyebrow(text: day.relativeDayName, color: Theme.accent)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.secondaryInk)
                        }
                    }
                    .buttonStyle(.plain)
                    let lastID = events.last?.id
                    ForEach(events) { event in
                        AgendaEventRow(event: event)
                        if event.id != lastID { Divider().overlay(Theme.separator) }
                    }
                }
                .card()
            }
        }
    }
}
