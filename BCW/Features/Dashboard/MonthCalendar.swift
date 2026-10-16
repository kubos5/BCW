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
    private static let rowSpacing: CGFloat = 2
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
        // I mesi sono già inizi di mese: basta l'uguaglianza, più rapida del calendario.
        return monthSet.contains(start) ? start : (months.first { $0.isSameDay(as: start) } ?? start)
    }

    private static let monthSet = Set(months)

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
        VStack(spacing: 0) {
            CalendarCardHead(title: currentMonth.monthYear, previousLabel: "Mese precedente",
                             nextLabel: "Mese successivo") { shift(-1) } next: { shift(1) }
                .animation(Motion.spatial, value: visibleMonth)

            HStack(spacing: 0) {
                ForEach(Self.weekdaySymbols.indices, id: \.self) { index in
                    Text(Self.weekdaySymbols[index])
                        .font(.m3(12, weight: 600))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 20)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(Self.months, id: \.self) { month in
                        monthGrid(month)
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
                .padding(.top, 8)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Theme.surfaceContainer, in: .rect(cornerRadius: Theme.radii.xl, style: .continuous))
        .onChange(of: visibleMonth) { _, month in
            let count = Self.rows(of: month ?? currentMonth).count
            if count != rowCount { withAnimation(Motion.spatial) { rowCount = count } }
        }
        .onChange(of: selectedDay) { _, day in
            let month = Self.month(containing: day)
            if !currentMonth.isSameDay(as: month) {
                withAnimation(Motion.spatial) { visibleMonth = month }
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
                                withAnimation(Motion.spatial) { selectedDay = day }
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
            legendItem(Theme.primary, "Verifiche")
            legendItem(Theme.fair, "Eventi")
            legendItem(Theme.poor, "Assenze")
        }
        .font(.m3(12))
        .foregroundStyle(Theme.secondaryInk)
    }

    private func legendItem(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }

    private func shift(_ months: Int) {
        guard let target = CVDate.calendar.date(byAdding: .month, value: months, to: currentMonth) else { return }
        withAnimation(Motion.spatial) { visibleMonth = Self.month(containing: target) }
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
                    .font(.numeral(15, weight: day.isToday || isSelected ? 700 : 550))
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
            .contentShape(CenteredCircle(diameter: 40))
            .background {
                if isSelected {
                    Circle().fill(Theme.primary).frame(width: 40, height: 40)
                } else if day.isToday {
                    Circle().strokeBorder(Theme.primary, lineWidth: 1.5).frame(width: 40, height: 40)
                } else if holiday {
                    Circle().fill(Theme.secondaryContainer.opacity(0.7)).frame(width: 40, height: 40)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.longDay)
    }

    private func numberColor(holiday: Bool) -> Color {
        if isSelected { return Theme.onPrimary }
        if day.isToday { return Theme.primary }
        if day.isWeekend || holiday { return Theme.secondaryInk }
        return Theme.ink
    }

    private func dotColors(events: [AgendaEvent]) -> [Color] {
        var colors: [Color] = []
        if events.contains(where: { $0.kind == .homework }) { colors.append(Theme.neutral) }
        if events.contains(where: { $0.kind == .test }) { colors.append(isSelected ? Theme.onPrimary : Theme.primary) }
        if events.contains(where: { $0.kind == .event }) { colors.append(Theme.fair) }
        if !model.absences(on: day).isEmpty { colors.append(Theme.poor) }
        return colors
    }
}
