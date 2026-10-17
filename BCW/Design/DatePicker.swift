import SwiftUI

/// Selettore della data di Material 3 (modale): in alto la data scelta in grande, sotto il mese
/// con le frecce, la griglia dei giorni (cerchi da 40 punti: pieno il giorno scelto, il bordo per
/// oggi) e i pulsanti di testo. Toccando il mese si sceglie mese e anno da una griglia; scorrendo
/// di lato si cambia mese. Lo usano il calendario della Dashboard e la settimana dell'Orario.
struct M3DatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (Date) -> Void
    @State private var selection: Date
    @State private var month: Date
    @State private var choosingMonth = false
    /// Verso dell'ultimo cambio di mese, per la transizione della griglia.
    @State private var direction = 1

    private static let weekdaySymbols = ["L", "M", "M", "G", "V", "S", "D"]
    private static let monthSymbols = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]

    init(selection: Date, onPick: @escaping (Date) -> Void) {
        self.onPick = onPick
        _selection = State(initialValue: selection.startOfDay)
        _month = State(initialValue: selection.startOfMonth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                Text("Scegli una data")
                    .font(.m3(14, weight: 550))
                    .foregroundStyle(Theme.onSurfaceVariant)
                Text(selection.it("EEEdMMM").replacingOccurrences(of: ".", with: "").capitalizedFirst)
                    .font(.m3(32, weight: 450, rounded: true))
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)
            M3Divider()

            monthRow
                .padding(.horizontal, 12)
                .padding(.top, 8)

            ZStack(alignment: .top) {
                if choosingMonth {
                    monthGrid
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    dayGrid
                        .transition(.opacity)
                }
            }
            .frame(height: 300, alignment: .top)
            .padding(.horizontal, 12)

            HStack(spacing: 4) {
                Button("Oggi") {
                    withAnimation(Motion.spatial) {
                        selection = Date().startOfDay
                        change(to: Date().startOfMonth)
                        choosingMonth = false
                    }
                }
                .buttonStyle(.m3(.text))
                Spacer()
                Button("Annulla") { dismiss() }
                    .buttonStyle(.m3(.text))
                Button("OK") {
                    onPick(selection)
                    dismiss()
                }
                .buttonStyle(.m3(.text))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceContainerHigh.ignoresSafeArea())
        .presentationBackground(Theme.surfaceContainerHigh)
        .presentationDetents([.height(540)])
        .presentationDragIndicator(.hidden)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var monthRow: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(Motion.spatial) { choosingMonth.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(month.monthYear)
                        .font(.m3(15, weight: 600))
                        .contentTransition(.numericText())
                    Icon("chevronDown", size: 18)
                        .rotationEffect(.degrees(choosingMonth ? 180 : 0))
                }
                .foregroundStyle(Theme.onSurfaceVariant)
                .padding(.horizontal, 12)
                .frame(height: 40)
                .contentShape(.capsule)
            }
            .buttonStyle(.pressable(radius: 20, pressed: 20))
            Spacer()
            if !choosingMonth {
                IconButton("chevronLeft", label: "Mese precedente") { shift(-1) }
                IconButton("chevronRight", label: "Mese successivo") { shift(1) }
            }
        }
        .frame(height: 48)
    }

    // MARK: Giorni

    private var dayGrid: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Self.weekdaySymbols.indices, id: \.self) { index in
                    Text(Self.weekdaySymbols[index])
                        .font(.m3(14, weight: 500))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 40)
            VStack(spacing: 4) {
                ForEach(Array(rows(of: month).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(row.indices, id: \.self) { index in
                            if let day = row[index] {
                                dayCell(day)
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: 40)
                            }
                        }
                    }
                }
            }
            .id(month)
            .transition(.asymmetric(insertion: .move(edge: direction > 0 ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: direction > 0 ? .leading : .trailing).combined(with: .opacity)))
        }
        .clipped()
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    shift(value.translation.width < 0 ? 1 : -1)
                }
        )
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = day.isSameDay(as: selection)
        let today = day.isToday
        return Button {
            withAnimation(Motion.spatialFast) { selection = day }
        } label: {
            Text(day.it("d"))
                .font(.m3(14, weight: selected || today ? 650 : 450).monospacedDigit())
                .foregroundStyle(selected ? Theme.onPrimary : (today ? Theme.primary : Theme.ink))
                .frame(width: 40, height: 40)
                .background {
                    if selected {
                        Circle().fill(Theme.primary)
                    } else if today {
                        Circle().strokeBorder(Theme.primary, lineWidth: 1)
                    }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(day.longDay)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Settimane del mese da lunedì a domenica; `nil` per i giorni dei mesi accanto.
    private func rows(of month: Date) -> [[Date?]] {
        let first = month.startOfMonth
        let count = CVDate.calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let offset = (CVDate.calendar.component(.weekday, from: first) + 5) % 7
        let total = Int((Double(offset + count) / 7).rounded(.up)) * 7
        let cells: [Date?] = (0..<total).map { index in
            index >= offset && index < offset + count ? first.adding(days: index - offset) : nil
        }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    // MARK: Mesi e anni

    private var monthGrid: some View {
        let year = CVDate.calendar.component(.year, from: month)
        return VStack(spacing: 12) {
            HStack {
                IconButton("chevronLeft", label: "Anno precedente") { changeYear(-1) }
                Spacer()
                Text(String(year))
                    .font(.m3(18, weight: 600).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .contentTransition(.numericText())
                Spacer()
                IconButton("chevronRight", label: "Anno successivo") { changeYear(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 10) {
                ForEach(0..<12, id: \.self) { index in
                    let selected = CVDate.calendar.component(.month, from: month) == index + 1
                    Button {
                        guard let target = CVDate.calendar.date(from: DateComponents(year: year, month: index + 1, day: 1)) else { return }
                        withAnimation(Motion.spatial) {
                            change(to: target)
                            choosingMonth = false
                        }
                    } label: {
                        Text(Self.monthSymbols[index].capitalizedFirst)
                            .font(.m3(15, weight: selected ? 650 : 500))
                            .foregroundStyle(selected ? Theme.onPrimary : Theme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(selected ? Theme.primary : Theme.surfaceContainerHighest, in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(.top, 4)
    }

    private func shift(_ months: Int) {
        guard let target = CVDate.calendar.date(byAdding: .month, value: months, to: month) else { return }
        Haptics.selection()
        withAnimation(Motion.spatial) { change(to: target) }
    }

    private func changeYear(_ years: Int) {
        guard let target = CVDate.calendar.date(byAdding: .year, value: years, to: month) else { return }
        withAnimation(Motion.spatial) { change(to: target) }
    }

    private func change(to target: Date) {
        let start = target.startOfMonth
        direction = start > month ? 1 : -1
        month = start
    }
}
