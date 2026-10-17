import SwiftUI

/// Settimana o mese di Dashboard e Orario come gruppo di pulsanti di M3 Expressive. Nella
/// settimana c'è un pulsante per giorno (iniziali e numero): quello scelto è pieno nel colore
/// primario, tutto arrotondato e più largo degli altri, che si stringono (come i gruppi di
/// pulsanti standard). Nel mese gli stessi pulsanti, più bassi, in una griglia; passando dalla
/// settimana al mese la settimana del giorno scelto resta e le altre compaiono con una molla.
/// Sopra: il periodo (apre il selettore della data), l'eventuale pulsante del mese e le frecce;
/// scorrendo di lato sui giorni si cambia settimana (o mese).
struct CalendarBar: View {
    @Binding var selectedDay: Date
    /// Il mese intero; altrimenti la settimana del giorno scelto.
    var showsMonth = false
    /// Pulsante per aprire o chiudere il mese (vista Calendario della Dashboard).
    var monthToggle: (() -> Void)?
    let pickDate: () -> Void

    private static let weekdaySymbols = ["L", "M", "M", "G", "V", "S", "D"]

    var body: some View {
        let month = selectedDay.startOfMonth
        let weeks = showsMonth ? Self.weeks(of: month) : [selectedDay.startOfWeek]
        VStack(spacing: 6) {
            header
            if showsMonth {
                HStack(spacing: 4) {
                    ForEach(Self.weekdaySymbols.indices, id: \.self) { index in
                        Text(Self.weekdaySymbols[index])
                            .font(.m3(12, weight: 600))
                            .foregroundStyle(Theme.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 20)
                .transition(.opacity)
            }
            VStack(spacing: 4) {
                ForEach(weeks, id: \.self) { week in
                    row(week, month: showsMonth ? month : nil)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -10)),
                                                removal: .opacity))
                }
            }
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                        shift(value.translation.width < 0 ? 1 : -1)
                    }
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: pickDate) {
                HStack(spacing: 4) {
                    Text(showsMonth ? selectedDay.monthYear : Self.rangeTitle(selectedDay.startOfWeek))
                        .font(.m3(15, weight: 600))
                        .contentTransition(.numericText())
                    Icon("chevronDown", size: 18)
                }
                .foregroundStyle(Theme.onSurfaceVariant)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .contentShape(.capsule)
            }
            .buttonStyle(.pressable(radius: 20, pressed: 20))
            .padding(.leading, -12)
            .accessibilityHint("Sceglie una data")
            Spacer()
            if let monthToggle {
                IconButton(showsMonth ? "viewAgenda" : "calendarMonth",
                           label: showsMonth ? "Mostra la settimana" : "Mostra il mese", action: monthToggle)
            }
            IconButton("chevronLeft", label: showsMonth ? "Mese precedente" : "Settimana precedente") { shift(-1) }
            IconButton("chevronRight", label: showsMonth ? "Mese successivo" : "Settimana successiva") { shift(1) }
                .padding(.trailing, -8)
        }
    }

    /// Una settimana: nella settimana i giorni hanno pesi diversi (lo scelto è più largo), nel
    /// mese sono uguali e quelli dei mesi accanto sono attenuati.
    private func row(_ week: Date, month: Date?) -> some View {
        let days = (0..<7).map { week.adding(days: $0) }
        let selectedIndex = days.firstIndex { $0.isSameDay(as: selectedDay) }
        let compact = month != nil
        return WeightedRow(weights: days.indices.map { !compact && $0 == selectedIndex ? 1.45 : 1 }, spacing: 4) {
            ForEach(days, id: \.self) { day in
                CalendarDayButton(day: day, isSelected: day.isSameDay(as: selectedDay), compact: compact,
                                  outside: month.map { !CVDate.calendar.isDate(day, equalTo: $0, toGranularity: .month) } ?? false) {
                    guard !day.isSameDay(as: selectedDay) else { return }
                    Haptics.selection()
                    selectedDay = day
                }
            }
        }
        .frame(height: compact ? 44 : 68)
    }

    /// "12 – 18 ottobre", oppure "28 set – 4 ott" a cavallo di due mesi.
    static func rangeTitle(_ week: Date) -> String {
        let end = week.adding(days: 6)
        if CVDate.calendar.isDate(week, equalTo: end, toGranularity: .month) {
            return "\(week.it("d")) – \(end.it("dMMMM"))"
        }
        return "\(week.it("dMMM")) – \(end.it("dMMM"))".replacingOccurrences(of: ".", with: "")
    }

    /// Inizi delle settimane (lunedì) che contengono i giorni del mese.
    static func weeks(of month: Date) -> [Date] {
        let first = month.startOfMonth
        let count = CVDate.calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let last = first.adding(days: count - 1)
        var weeks: [Date] = []
        var week = first.startOfWeek
        while week <= last {
            weeks.append(week)
            week = week.adding(days: 7)
        }
        return weeks
    }

    /// Settimana (o mese) prima o dopo, mantenendo il giorno della settimana (o il numero del giorno).
    private func shift(_ direction: Int) {
        let target = showsMonth
            ? CVDate.calendar.date(byAdding: .month, value: direction, to: selectedDay) ?? selectedDay
            : selectedDay.adding(days: 7 * direction)
        Haptics.selection()
        selectedDay = target.startOfDay
    }
}

/// Un giorno: iniziali (solo nella settimana), numero e un pallino per verifiche, compiti e assenze.
private struct CalendarDayButton: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let isSelected: Bool
    let compact: Bool
    /// Giorno di un mese accanto (nel mese): attenuato.
    let outside: Bool
    let action: () -> Void

    var body: some View {
        let holiday = model.calendarStatus(on: day)?.isHoliday == true
        let quiet = (day.isWeekend || holiday) && !isSelected
        Button(action: action) {
            VStack(spacing: compact ? 0 : 1) {
                if !compact {
                    Text(day.it("EEE").replacingOccurrences(of: ".", with: "").capitalizedFirst)
                        .font(.m3(12, weight: isSelected ? 700 : 550))
                        .lineLimit(1)
                        .transition(.opacity)
                }
                Text(day.it("d"))
                    .font(.numeral(compact ? 16 : 20, weight: isSelected || day.isToday ? 700 : 550))
                dots
            }
            .foregroundStyle(isSelected ? Theme.onPrimary
                             : (day.isToday ? Theme.primary : (quiet ? Theme.onSurfaceVariant : Theme.ink)))
            .opacity(outside && !isSelected ? 0.45 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(CalendarDayStyle(selected: isSelected, today: day.isToday, compact: compact, outside: outside))
        .accessibilityLabel(day.longDay)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dots: some View {
        let events = model.events(on: day)
        let size: CGFloat = compact ? 4 : 5
        return HStack(spacing: 3) {
            if events.contains(where: { $0.kind == .test }) { dot(isSelected ? Theme.onPrimary : Theme.tertiary, size) }
            if events.contains(where: { $0.kind == .homework }) { dot(isSelected ? Theme.onPrimary.opacity(0.7) : Theme.neutral, size) }
            if events.contains(where: { $0.kind == .event }) { dot(isSelected ? Theme.onPrimary.opacity(0.7) : Theme.fair, size) }
            if !model.absences(on: day).isEmpty { dot(isSelected ? Theme.onPrimary.opacity(0.7) : Theme.poor, size) }
        }
        .frame(height: size)
    }

    private func dot(_ color: Color, _ size: CGFloat) -> some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

private struct CalendarDayStyle: ButtonStyle {
    let selected: Bool
    let today: Bool
    let compact: Bool
    let outside: Bool

    func makeBody(configuration: Configuration) -> some View {
        let full: CGFloat = compact ? 22 : 34
        let radius = configuration.isPressed ? Theme.radii.s : (selected ? full : (compact ? Theme.radii.m : Theme.radii.l))
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .background {
                shape.fill(selected ? Theme.primary : (outside ? Theme.surfaceContainer : Theme.surfaceContainerHigh))
                    .overlay {
                        if today && !selected { shape.strokeBorder(Theme.primary, lineWidth: 1.5) }
                    }
                    .overlay(shape.fill(Theme.onSurface.opacity(configuration.isPressed ? 0.1 : 0)))
            }
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.spatialFast, value: configuration.isPressed)
            .animation(Motion.spatial, value: selected)
    }
}

/// Riga di viste con larghezze proporzionali ai pesi (i cambi di peso si animano).
struct WeightedRow: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 320, height: proposal.height ?? 68)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let total = weights.prefix(subviews.count).reduce(0, +)
        let available = bounds.width - spacing * CGFloat(max(0, subviews.count - 1))
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            let weight = index < weights.count ? weights[index] : 1
            let width = total > 0 ? available * weight / total : 0
            subview.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}
