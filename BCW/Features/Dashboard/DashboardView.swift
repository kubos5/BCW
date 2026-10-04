import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    /// Si apre sul giorno dopo, come richiesto: è quello per cui servono i compiti.
    @State private var selectedDay = Date().adding(days: DashboardView.initialOffset).startOfDay
    /// Larghezza della barra di navigazione, per capire se il titolo esteso ci sta.
    @State private var barWidth: CGFloat = 0

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
                        Button("Domani") { jump(to: Date().adding(days: 1)) }
                            .keyboardShortcut("t", modifiers: [.command, .shift])
                            .disabled(selectedDay.isTomorrow)
                            .help("Vai a domani (⇧⌘T)")
                    }
                    #else
                    if !selectedDay.isTomorrow {
                        ToolbarItem(placement: .trailingBar) {
                            Button("Domani") {
                                withAnimation(.snappy) { selectedDay = Date().adding(days: 1).startOfDay }
                            }
                        }
                        ToolbarSpacer(.fixed, placement: .trailingBar)
                    }
                    #endif
                    ToolbarItem(placement: .trailingBar) {
                        Menu {
                            Picker("Vista", selection: Bindable(model.preferences).dashboardMode) {
                                ForEach(DashboardMode.allCases) { mode in
                                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                                }
                            }
                            Button("Vai a oggi", systemImage: "sun.max") {
                                withAnimation(.snappy) { selectedDay = Date().startOfDay }
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
                }
                // Applicato dopo la barra della pagina: su macOS il titolo resta il primo elemento.
                .screenTitle(title, subtitle: subtitle)
                #if os(iOS)
                .toolbarTitleDisplayMode(.inlineLarge)
                #endif
        }
    }

    /// Su macOS il titolo relativo ("Domani") è accompagnato dalla data completa.
    private var subtitle: String? {
        selectedDay.relativeDayName == selectedDay.longDay ? nil : selectedDay.longDay
    }

    private func jump(to day: Date) {
        withAnimation(.snappy) { selectedDay = day.startOfDay }
    }

    private func shift(_ days: Int) {
        withAnimation(.snappy) { selectedDay = selectedDay.adding(days: days) }
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
                StatusBanner(message: error, symbol: model.isOffline ? "wifi.slash" : "exclamationmark.triangle")
            }
            DayDetail(day: selectedDay)
                .id(selectedDay)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            StackAware { stacked in
                if stacked { upcoming }
            }
        }
        .animation(.snappy, value: selectedDay)
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let error = model.lastError {
                    StatusBanner(message: error, symbol: model.isOffline ? "wifi.slash" : "exclamationmark.triangle")
                }

                calendar

                DayDetail(day: selectedDay)
                    .id(selectedDay)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                if mode == .list && model.preferences.showUpcomingDays {
                    // Stessa transizione del contenuto del giorno: cambia insieme a esso.
                    UpcomingDays(after: selectedDay) { day in
                        withAnimation(.snappy) { selectedDay = day }
                    }
                    .id(selectedDay)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .pagePadding()
            .padding(.bottom, 24)
            .animation(.snappy, value: selectedDay)
        }
        .themedBackground()
        #endif
    }

    @ViewBuilder
    private var upcoming: some View {
        if model.preferences.showUpcomingDays {
            UpcomingDays(after: selectedDay) { day in
                withAnimation(.snappy) { selectedDay = day }
            }
            .id(selectedDay)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    @ViewBuilder
    private var calendar: some View {
        switch mode {
        case .list:
            WeekStrip(selectedDay: $selectedDay)
        case .calendar:
            MonthCalendar(selectedDay: $selectedDay)
        }
    }
}

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
        return weeks.first { $0.isSameDay(as: start) } ?? start
    }

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

    private var days: [(Date, [AgendaEvent])] {
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
                    upcomingList
                }
            }
        }
    }

    private var upcomingList: some View {
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
                    ForEach(events) { event in
                        AgendaEventRow(event: event)
                        if event.id != events.last?.id { Divider().overlay(Theme.separator) }
                    }
                }
                .card()
            }
        }
    }
}
