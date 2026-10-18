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

// MARK: - Selettore dell'orario

/// Selettore dell'orario di Material 3 (modale, 24 ore): in alto ore e minuti in due riquadri
/// (quello che si sta scegliendo è nel contenitore primario), sotto il quadrante. Per le ore il
/// quadrante ha due anelli (fuori 0–11, dentro 12–23); scelta l'ora si passa da soli ai minuti
/// (etichette ogni 5, trascinando si sceglie qualsiasi minuto). L'icona della tastiera passa
/// all'inserimento con i numeri. Lo apre `TimeField`.
struct M3TimePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (Int) -> Void
    @State private var hour: Int
    @State private var minute: Int
    @State private var choosingMinutes = false
    @State private var typing = false
    @State private var hourText = ""
    @State private var minuteText = ""
    @FocusState private var focusedField: Field?

    private enum Field { case hour, minute }

    private static let dial: CGFloat = 276

    /// `minutes`: minuti dalla mezzanotte.
    init(minutes: Int, onPick: @escaping (Int) -> Void) {
        self.onPick = onPick
        let value = max(0, min(minutes, 24 * 60 - 1))
        _hour = State(initialValue: value / 60)
        _minute = State(initialValue: value % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(typing ? "Inserisci un orario" : "Scegli un orario")
                .font(.m3(14, weight: 550))
                .foregroundStyle(Theme.onSurfaceVariant)
            if typing { inputRow } else { boxes }
            if !typing {
                dial
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            HStack(spacing: 4) {
                IconButton(typing ? "schedule" : "keyboard",
                           label: typing ? "Scegli dal quadrante" : "Inserisci con la tastiera") {
                    withAnimation(Motion.spatial) { setTyping(!typing) }
                }
                .padding(.leading, -8)
                Spacer()
                Button("Annulla") { dismiss() }
                    .buttonStyle(.m3(.text))
                Button("OK") {
                    if typing { commitTyped() }
                    onPick(hour * 60 + minute)
                    dismiss()
                }
                .buttonStyle(.m3(.text))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceContainerHigh.ignoresSafeArea())
        .presentationBackground(Theme.surfaceContainerHigh)
        .presentationDetents([.height(typing ? 260 : 540)])
        .presentationDragIndicator(.hidden)
        .sensoryFeedback(.selection, trigger: hour * 60 + minute)
    }

    // MARK: Riquadri

    private var boxes: some View {
        HStack(spacing: 6) {
            box(String(format: "%02d", hour), selected: !choosingMinutes, label: "Ore") {
                withAnimation(Motion.spatial) { choosingMinutes = false }
            }
            Text(":")
                .font(.numeral(52, weight: 400))
                .foregroundStyle(Theme.ink)
                .frame(width: 24)
            box(String(format: "%02d", minute), selected: choosingMinutes, label: "Minuti") {
                withAnimation(Motion.spatial) { choosingMinutes = true }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func box(_ text: String, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.numeral(52, weight: 400))
                .contentTransition(.numericText())
                .foregroundStyle(selected ? Theme.onPrimaryContainer : Theme.ink)
                .frame(width: 96, height: 80)
                .background(selected ? Theme.primaryContainer : Theme.surfaceContainerHighest,
                            in: .rect(cornerRadius: Theme.radii.m, style: .continuous))
        }
        .buttonStyle(.pressable(radius: Theme.radii.m, pressed: Theme.radii.s))
        .accessibilityLabel("\(label): \(text)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Inserimento con la tastiera

    private var inputRow: some View {
        HStack(alignment: .top, spacing: 6) {
            field("Ore", text: $hourText, placeholder: String(format: "%02d", hour), field: .hour)
            Text(":")
                .font(.numeral(52, weight: 400))
                .foregroundStyle(Theme.ink)
                .frame(width: 24, height: 80)
            field("Minuti", text: $minuteText, placeholder: String(format: "%02d", minute), field: .minute)
        }
        .frame(maxWidth: .infinity)
    }

    /// Campo di ore o minuti: selezionato si svuota e mostra il valore attuale come suggerimento
    /// (le cifre scritte lo sostituiscono; lasciato vuoto resta quello di prima).
    private func field(_ label: String, text: Binding<String>, placeholder: String, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: field)
                .multilineTextAlignment(.center)
                .font(.numeral(52, weight: 400))
                .foregroundStyle(focusedField == field ? Theme.onPrimaryContainer : Theme.ink)
                .frame(width: 96, height: 80)
                .background(focusedField == field ? Theme.primaryContainer : Theme.surfaceContainerHighest,
                            in: .rect(cornerRadius: Theme.radii.m, style: .continuous))
                .onChange(of: text.wrappedValue) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(2))
                    if digits != value { text.wrappedValue = digits }
                    // Al giro dopo: spostando il campo attivo durante la battuta la cifra finiva
                    // anche nei minuti.
                    if field == .hour && digits.count == 2 {
                        DispatchQueue.main.async { focusedField = .minute }
                    }
                }
                .onChange(of: focusedField) { old, new in
                    // Lasciando il campo vale quanto scritto; tornandoci si ricomincia.
                    if old == field { commit(field) }
                    if new == field { text.wrappedValue = "" }
                }
            Text(label)
                .font(.m3(12))
                .foregroundStyle(Theme.onSurfaceVariant)
        }
    }

    private func setTyping(_ on: Bool) {
        if on {
            hourText = ""
            minuteText = ""
            typing = true
            focusedField = .hour
        } else {
            commitTyped()
            focusedField = nil
            typing = false
        }
    }

    /// Ore e minuti scritti, riportati negli intervalli validi.
    private func commitTyped() {
        commit(.hour)
        commit(.minute)
    }

    /// Il valore scritto in un campo (se c'è), che poi si svuota e lo mostra come suggerimento.
    private func commit(_ field: Field) {
        switch field {
        case .hour:
            if let h = Int(hourText) { hour = min(max(h, 0), 23) }
            hourText = ""
        case .minute:
            if let m = Int(minuteText) { minute = min(max(m, 0), 59) }
            minuteText = ""
        }
    }

    // MARK: Quadrante

    private var dial: some View {
        let size = Self.dial
        let center = CGPoint(x: size / 2, y: size / 2)
        // Anelli a 48 punti di distanza: il cerchio della lancetta (44) non copre le etichette vicine.
        let outer = size / 2 - 26
        let inner = outer - 48
        let value = choosingMinutes ? minute : hour
        let handRadius = choosingMinutes || hour < 12 ? outer : inner
        let handAngle = choosingMinutes ? Double(minute) / 60 : Double(hour % 12) / 12
        let handPoint = point(center: center, radius: handRadius, fraction: handAngle)
        return ZStack {
            Circle().fill(Theme.surfaceContainerHighest)
            // Lancetta: linea dal centro e cerchio pieno sul valore.
            Path { path in
                path.move(to: center)
                path.addLine(to: handPoint)
            }
            .stroke(Theme.primary, lineWidth: 2)
            Circle().fill(Theme.primary).frame(width: 8, height: 8).position(center)
            Circle().fill(Theme.primary).frame(width: 44, height: 44).position(handPoint)
            if choosingMinutes {
                ForEach(0..<12, id: \.self) { index in
                    label(String(format: "%02d", index * 5), selected: minute == index * 5, small: false)
                        .position(point(center: center, radius: outer, fraction: Double(index) / 12))
                }
            } else {
                ForEach(0..<12, id: \.self) { index in
                    label(index == 0 ? "00" : "\(index)", selected: hour == index, small: false)
                        .position(point(center: center, radius: outer, fraction: Double(index) / 12))
                    label("\(index + 12)", selected: hour == index + 12, small: true)
                        .position(point(center: center, radius: inner, fraction: Double(index) / 12))
                }
            }
        }
        .frame(width: size, height: size)
        .animation(Motion.spatialFast, value: value)
        .animation(Motion.spatialFast, value: choosingMinutes)
        .contentShape(.circle)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in select(at: drag.location, center: center, inner: inner, outer: outer) }
                .onEnded { _ in
                    // Scelta l'ora si passa ai minuti, come in Material 3.
                    if !choosingMinutes { withAnimation(Motion.spatial) { choosingMinutes = true } }
                }
        )
        .accessibilityElement()
        .accessibilityLabel(choosingMinutes ? "Minuti" : "Ore")
        .accessibilityValue(choosingMinutes ? "\(minute)" : "\(hour)")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 1 : -1
            if choosingMinutes { minute = (minute + step + 60) % 60 } else { hour = (hour + step + 24) % 24 }
        }
    }

    private func label(_ text: String, selected: Bool, small: Bool) -> some View {
        Text(text)
            .font(.m3(small ? 14 : 16, weight: selected ? 650 : 500).monospacedDigit())
            .foregroundStyle(selected ? Theme.onPrimary : (small ? Theme.onSurfaceVariant : Theme.ink))
            .frame(width: 40, height: 40)
            .allowsHitTesting(false)
    }

    /// Punto del quadrante: `fraction` del giro in senso orario partendo dall'alto.
    private func point(center: CGPoint, radius: CGFloat, fraction: Double) -> CGPoint {
        let angle = fraction * 2 * .pi
        return CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
    }

    private func select(at location: CGPoint, center: CGPoint, inner: CGFloat, outer: CGFloat) {
        let dx = location.x - center.x, dy = location.y - center.y
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        let fraction = angle / (2 * .pi)
        if choosingMinutes {
            minute = Int((fraction * 60).rounded()) % 60
        } else {
            let index = Int((fraction * 12).rounded()) % 12
            let distance = hypot(dx, dy)
            hour = distance < (inner + outer) / 2 ? index + 12 : index
        }
    }
}
