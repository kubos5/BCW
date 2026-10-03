import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    /// Si apre sul giorno dopo, come richiesto: è quello per cui servono i compiti.
    @State private var selectedDay = Date().adding(days: 1).startOfDay
    /// Larghezza della barra di navigazione, per capire se il titolo esteso ci sta.
    @State private var barWidth: CGFloat = 0

    private var mode: DashboardMode { model.preferences.dashboardMode }

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
        guard barWidth > 0 else { return true }
        let titleWidth = (text as NSString).size(withAttributes: [.font: UIFont.newYork(size: 34, weight: .bold)]).width
        // Margini laterali, pulsante del menu e spazio dal titolo.
        var reserved: CGFloat = 16 + 16 + 44 + 16
        if !selectedDay.isTomorrow {
            let buttonText = ("Domani" as NSString).size(withAttributes: [.font: UIFont.newYork(size: 17, weight: .regular)]).width
            reserved += buttonText + 32 + 12
        }
        return titleWidth <= barWidth - reserved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let error = model.lastError {
                        StatusBanner(message: error, symbol: model.isOffline ? "wifi.slash" : "exclamationmark.triangle")
                    }

                    switch mode {
                    case .list:
                        WeekStrip(selectedDay: $selectedDay)
                    case .calendar:
                        MonthCalendar(selectedDay: $selectedDay)
                    }

                    DayDetail(day: selectedDay)
                        .id(selectedDay)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))

                    if mode == .list && model.preferences.showUpcomingDays {
                        UpcomingDays(after: selectedDay) { day in
                            withAnimation(.snappy) { selectedDay = day }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .animation(.snappy, value: selectedDay)
            }
            .themedBackground()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
            .refreshable { await model.refreshAll() }
            .toolbar {
                if !selectedDay.isTomorrow {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Domani") {
                            withAnimation(.snappy) { selectedDay = Date().adding(days: 1).startOfDay }
                        }
                    }
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
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
                        if mode == .list {
                            Toggle("Mostra i prossimi giorni", systemImage: "calendar.day.timeline.right",
                                   isOn: Bindable(model.preferences).showUpcomingDays)
                        }
                    } label: {
                        Image(systemName: mode.symbol)
                    }
                }
            }
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
                .buttonStyle(.glass)
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
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    // Solo dissolvenza, rapida: i contenuti non scorrono (la sezione è lunga).
                    withAnimation(.easeOut(duration: 0.18)) { model.preferences.toggleCollapsed(.upcoming) }
                } label: {
                    SectionHeader(title: "Nei prossimi giorni") {
                        Image(systemName: "chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.secondaryInk)
                            .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isCollapsed)

                if !isCollapsed {
                    upcomingList
                        .transition(.opacity)
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
