import SwiftUI

struct MonthCalendar: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedDay: Date
    /// Mese mostrato: segue lo scorrimento orizzontale a pagine.
    @State private var visibleMonth: Date?
    /// Settimane mostrate: aggiornate con un'animazione, così il resto della pagina
    /// sale o scende insieme al calendario invece di scattare.
    @State private var rowCount: Int

    private static let cellHeight: CGFloat = 44
    private static let rowSpacing: CGFloat = 4
    private static let weekdaySymbols = ["L", "M", "M", "G", "V", "S", "D"]

    /// Mesi disponibili: due anni prima e dopo il mese corrente.
    private static let months: [Date] = {
        let current = Date().startOfMonth
        return (-24...24).compactMap { CVDate.calendar.date(byAdding: .month, value: $0, to: current)?.startOfMonth }
    }()

    init(selectedDay: Binding<Date>) {
        _selectedDay = selectedDay
        let month = Self.month(containing: selectedDay.wrappedValue)
        _visibleMonth = State(initialValue: month)
        _rowCount = State(initialValue: Self.rows(of: month).count)
    }

    private static func month(containing day: Date) -> Date {
        let start = day.startOfMonth
        return months.first { $0.isSameDay(as: start) } ?? start
    }

    /// Settimane del mese, da lunedì a domenica (`nil` = giorno di un altro mese).
    private static func rows(of month: Date) -> [[Date?]] {
        let first = month.startOfMonth
        let range = CVDate.calendar.range(of: .day, in: .month, for: first) ?? 1..<31
        // Lunedì = 0
        let offset = (CVDate.calendar.component(.weekday, from: first) + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: offset)
        cells += range.map { first.adding(days: $0 - 1) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private var currentMonth: Date { visibleMonth ?? selectedDay.startOfMonth }

    /// L'altezza segue il numero di settimane del mese visibile (4-6).
    private var gridHeight: CGFloat {
        let count = CGFloat(rowCount)
        return count * Self.cellHeight + (count - 1) * Self.rowSpacing
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                HStack {
                    Text(currentMonth.monthYear)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: visibleMonth)
                    Spacer()
                    HStack(spacing: 4) {
                        Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    }
                    .glassButton()
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                }

                HStack(spacing: 2) {
                    ForEach(Self.weekdaySymbols.indices, id: \.self) { index in
                        Text(Self.weekdaySymbols[index])
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.secondaryInk)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(Self.months, id: \.self) { month in
                        monthGrid(month)
                            .padding(.horizontal, 14)
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleMonth)
            .scrollIndicators(.hidden)
            .frame(height: gridHeight, alignment: .top)

            legend
                .padding(.horizontal, 14)
        }
        .padding(.vertical, 14)
        .card(padding: 0)
        .onChange(of: visibleMonth) { _, month in
            let count = Self.rows(of: month ?? currentMonth).count
            if count != rowCount { withAnimation(.snappy) { rowCount = count } }
        }
        .onChange(of: selectedDay) { _, day in
            let month = Self.month(containing: day)
            if !currentMonth.isSameDay(as: month) {
                withAnimation(.snappy) { visibleMonth = month }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
    }

    private func monthGrid(_ month: Date) -> some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(Array(Self.rows(of: month).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 2) {
                    ForEach(row.indices, id: \.self) { index in
                        if let day = row[index] {
                            MonthDayCell(day: day, isSelected: day.isSameDay(as: selectedDay)) {
                                withAnimation(.snappy) { selectedDay = day }
                            }
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: Self.cellHeight)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(Theme.neutral, "Compiti")
            legendItem(Theme.accent, "Verifiche")
            legendItem(Theme.fair, "Eventi")
            legendItem(Theme.poor, "Assenze")
        }
        .font(.caption2)
        .foregroundStyle(Theme.secondaryInk)
    }

    private func legendItem(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
        }
    }

    private func shift(_ months: Int) {
        guard let target = CVDate.calendar.date(byAdding: .month, value: months, to: currentMonth) else { return }
        withAnimation(.snappy) { visibleMonth = Self.month(containing: target) }
    }
}

private struct MonthDayCell: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let events = model.events(on: day)
        let holiday = model.calendarStatus(on: day)?.isHoliday == true
        let colors = dotColors(events: events)

        Button(action: action) {
            VStack(spacing: 3) {
                Text(day.it("d"))
                    .font(.numeral(16, weight: day.isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(numberColor(holiday: holiday))
                HStack(spacing: 2) {
                    ForEach(colors.indices, id: \.self) { i in
                        Circle().fill(colors[i]).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            // Si può fare clic su tutto il cerchio del giorno, non solo sul numero.
            .contentShape(CenteredCircle(diameter: 42))
            .background {
                if isSelected {
                    Circle().fill(Theme.accent.gradient).frame(width: 42, height: 42)
                } else if holiday {
                    Circle().fill(Theme.separator.opacity(0.45)).frame(width: 42, height: 42)
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

    private func dotColors(events: [AgendaEvent]) -> [Color] {
        var colors: [Color] = []
        if events.contains(where: { $0.kind == .homework }) { colors.append(Theme.neutral) }
        if events.contains(where: { $0.kind == .test }) { colors.append(isSelected ? Color.white : Theme.accent) }
        if events.contains(where: { $0.kind == .event }) { colors.append(Theme.fair) }
        if !model.absences(on: day).isEmpty { colors.append(Theme.poor) }
        return colors
    }
}
