import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    /// Si apre sul giorno dopo, come richiesto: è quello per cui servono i compiti.
    @State private var selectedDay = Date().adding(days: 1).startOfDay

    private var mode: DashboardMode { model.preferences.dashboardMode }

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

                    if mode == .list {
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
            .navigationTitle(selectedDay.relativeDayName)
            .toolbarTitleDisplayMode(.inlineLarge)
            .refreshable { await model.refreshAll() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !selectedDay.isTomorrow {
                        Button("Domani") {
                            withAnimation(.snappy) { selectedDay = Date().adding(days: 1).startOfDay }
                        }
                    }
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

    private var days: [Date] {
        let start = selectedDay.startOfWeek
        return (0..<7).map { start.adding(days: $0) }
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
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    DayCell(day: day, isSelected: day.isSameDay(as: selectedDay)) {
                        selectedDay = day
                    }
                }
            }
        }
        .card(padding: 14)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -40 { shift(7) }
                    if value.translation.width > 40 { shift(-7) }
                }
        )
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

    var body: some View {
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Nei prossimi giorni")
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
}
