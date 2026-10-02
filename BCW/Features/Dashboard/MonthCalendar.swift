import SwiftUI

struct MonthCalendar: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedDay: Date
    @State private var month: Date = Date().startOfMonth

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    private var cells: [Date?] {
        let first = month.startOfMonth
        let range = CVDate.calendar.range(of: .day, in: .month, for: first) ?? 1..<31
        // Lunedì = 0
        let offset = (CVDate.calendar.component(.weekday, from: first) + 5) % 7
        var result: [Date?] = Array(repeating: nil, count: offset)
        result += range.map { first.adding(days: $0 - 1) }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(month.monthYear)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                HStack(spacing: 4) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.small)
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(["L", "M", "M", "G", "V", "S", "D"].indices, id: \.self) { index in
                    Text(["L", "M", "M", "G", "V", "S", "D"][index])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(maxWidth: .infinity)
                }
                ForEach(cells.indices, id: \.self) { index in
                    if let day = cells[index] {
                        MonthDayCell(day: day, isSelected: day.isSameDay(as: selectedDay)) {
                            withAnimation(.snappy) { selectedDay = day }
                        }
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }

            legend
        }
        .card(padding: 14)
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -40 { shift(1) }
                    if value.translation.width > 40 { shift(-1) }
                }
        )
        .onAppear { month = selectedDay.startOfMonth }
        .onChange(of: selectedDay) { _, day in
            if !CVDate.calendar.isDate(day, equalTo: month, toGranularity: .month) {
                withAnimation(.snappy) { month = day.startOfMonth }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
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
        withAnimation(.snappy) {
            month = CVDate.calendar.date(byAdding: .month, value: months, to: month)?.startOfMonth ?? month
        }
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
