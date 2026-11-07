import SwiftUI

/// Sposta più eventi insieme di un numero di minuti (Modifica orario › Sposta gli orari): un valore per
/// tutti i giorni e uno per ogni giorno; aprendo un giorno si scelgono gli eventi da spostare, con
/// l'orario nuovo accanto. Gli intervalli si possono lasciare dove sono.
struct TimetableShiftSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Il giorno che si apre da solo: quello che si stava modificando.
    let startWeekday: Int

    /// Il valore in cima, che cambiando vale per tutti i giorni.
    @State private var common = 5
    /// I giorni con minuti propri; gli altri seguono il valore in cima.
    @State private var minutes: [Int: Int] = [:]
    /// Eventi tolti a mano dallo spostamento.
    @State private var excluded: Set<UUID> = []
    @State private var includesBreaks = true
    @State private var expanded: Set<Int> = []
    @State private var prepared = false

    private var store: TimetableStore { model.timetable }

    /// I giorni con eventi.
    private var weekdays: [Int] {
        (1...7).filter { !store.entries(weekday: $0, includingDraft: false).isEmpty }
    }

    private func selectable(_ entry: TimetableEntry) -> Bool {
        includesBreaks || !entry.isBreak
    }

    /// Gli eventi che si spostano, con i loro minuti.
    private var moves: [UUID: Int] {
        var moves: [UUID: Int] = [:]
        for weekday in weekdays {
            let delta = minutes[weekday] ?? common
            guard delta != 0 else { continue }
            for entry in store.entries(weekday: weekday, includingDraft: false)
            where selectable(entry) && !excluded.contains(entry.id) {
                moves[entry.id] = delta
            }
        }
        return moves
    }

    /// Con l'allineamento automatico una lezione può stare solo alle ore e alle mezz'ore.
    private func leavesAutomaticAlignment(_ moves: [UUID: Int]) -> Bool {
        guard store.alignment == .automatic else { return false }
        return store.timetable.entries.contains { entry in
            guard !entry.isBreak, let delta = moves[entry.id], delta != 0 else { return false }
            return entry.shifted(by: delta).start % 30 != 0
        }
    }

    var body: some View {
        let moves = moves
        let leavesAutomatic = leavesAutomaticAlignment(moves)
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero(moves: moves)
                    ListGroup {
                        ToggleRow("Sposta anche gli intervalli", icon: "coffee", isOn: $includesBreaks)
                    }
                    if leavesAutomatic {
                        alignmentNotice
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    ListGroup("Giorno per giorno", footer: "Ogni giorno ha i suoi minuti. Tocca un giorno per vedere i nuovi orari e scegliere quali eventi spostare. La durata degli eventi non cambia.") {
                        ForEach(weekdays, id: \.self) { weekday in
                            dayRow(weekday)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(Motion.spatial, value: leavesAutomatic)
            }
            .scrollDismissesKeyboard(.interactively)
            .sheetChrome("Sposta gli orari", leading: .cancel { dismiss() },
                         trailing: [.confirm("Sposta", disabled: moves.isEmpty) { apply(moves, leavesAutomatic: leavesAutomatic) }])
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fine") { hideKeyboard() }
                }
            }
        }
        .m3Sheet(size: .page)
        .onAppear(perform: prepare)
        // Il valore in cima vale di nuovo per tutti i giorni.
        .onChange(of: common) { minutes = [:] }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        // Il giorno che si stava modificando è aperto: si vedono subito i nuovi orari.
        if weekdays.contains(startWeekday) { expanded = [startWeekday] }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func apply(_ moves: [UUID: Int], leavesAutomatic: Bool) {
        Haptics.success()
        withAnimation(Motion.spatial) { store.shift(moves, freeAlignment: leavesAutomatic) }
        dismiss()
    }

    // MARK: Parti

    /// Il valore per tutti i giorni in primo piano, con le scorciatoie più comuni.
    private func hero(moves: [UUID: Int]) -> some View {
        VStack(spacing: 14) {
            Text("TUTTI I GIORNI")
                .font(.m3(12, weight: 750))
                .tracking(0.8)
                .opacity(0.8)
            MinutesField(value: $common, large: true)
            HStack(spacing: 6) {
                ForEach([-15, -10, -5, 5, 10, 15], id: \.self) { shortcut in
                    Button {
                        Haptics.selection()
                        withAnimation(Motion.spatialFast) { common = shortcut }
                    } label: {
                        Text(MinutesField.signed(shortcut))
                            .font(.numeral(14, weight: 650))
                            .foregroundStyle(common == shortcut ? Theme.onPrimary : Theme.onPrimaryContainer)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(common == shortcut ? Theme.primary : Theme.onPrimaryContainer.opacity(0.08),
                                        in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.pressable(radius: 18, pressed: 10))
                    .accessibilityLabel("\(MinutesField.signed(shortcut)) minuti")
                }
            }
            Text(summary(moves))
                .font(.m3(13, weight: 550))
                .opacity(0.85)
                .contentTransition(.numericText())
        }
        .foregroundStyle(Theme.onPrimaryContainer)
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Theme.primaryContainer, in: .rect(cornerRadius: Theme.radii.xl, style: .continuous))
        .animation(Motion.effects, value: moves.count)
    }

    private func summary(_ moves: [UUID: Int]) -> String {
        if moves.isEmpty { return "Nessun evento da spostare" }
        let days = Set(store.timetable.entries.filter { moves[$0.id] != nil }.map(\.weekday)).count
        let events = moves.count == 1 ? "1 evento" : "\(moves.count) eventi"
        return "\(events) in \(days == 1 ? "1 giorno" : "\(days) giorni")"
    }

    private var alignmentNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Icon("alignFree", size: 20)
            Text("L'orario usa l'allineamento automatico, con gli eventi alle ore e alle mezz'ore. Con questi minuti passerà all'allineamento libero.")
                .font(.m3(13, weight: 550))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.onTertiaryContainer)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.tertiaryContainer, in: .rect(cornerRadius: Theme.radii.li, style: .continuous))
    }

    /// Un giorno: nome, quanti eventi e i suoi minuti; aperto, gli eventi con l'orario nuovo.
    private func dayRow(_ weekday: Int) -> some View {
        let entries = store.entries(weekday: weekday, includingDraft: false).filter(selectable)
        let chosen = entries.filter { !excluded.contains($0.id) }.count
        let isExpanded = expanded.contains(weekday)
        let delta = Binding { minutes[weekday] ?? common } set: { minutes[weekday] = $0 }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(Motion.spatial) {
                        if isExpanded { expanded.remove(weekday) } else { expanded.insert(weekday) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Chevron(collapsed: !isExpanded, rotateUp: true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Weekday.name(weekday))
                                .font(.m3(16, weight: 600))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(chosen == entries.count ? (entries.count == 1 ? "1 evento" : "\(entries.count) eventi")
                                 : "\(chosen) di \(entries.count)")
                                .font(.m3(12))
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(HeaderButtonStyle())
                .accessibilityLabel(Weekday.name(weekday))
                .accessibilityHint(isExpanded ? "Nasconde gli eventi" : "Mostra gli eventi")
                MinutesField(value: delta)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            CollapsibleContent(isExpanded: isExpanded, spacing: 0) {
                VStack(spacing: 2) {
                    ForEach(entries) { entry in
                        entryRow(entry, delta: delta.wrappedValue)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }

    /// Un evento: casella, nome e orario, con quello nuovo se si sposta.
    private func entryRow(_ entry: TimetableEntry, delta: Int) -> some View {
        let isOn = !excluded.contains(entry.id)
        let moved = entry.shifted(by: delta)
        let moves = isOn && moved.start != entry.start
        return Button {
            Haptics.selection()
            withAnimation(Motion.spatialFast) {
                if isOn { excluded.insert(entry.id) } else { excluded.remove(entry.id) }
            }
        } label: {
            HStack(spacing: 10) {
                Icon(isOn ? "checkCircleFill" : "circle", size: 22)
                    .foregroundStyle(isOn ? Theme.primary : Theme.outline)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.timetableColor(entry, store: store))
                    .frame(width: 4, height: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.displayTitle)
                        .font(.m3(14, weight: 600))
                        .foregroundStyle(isOn ? Theme.ink : Theme.secondaryInk)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(entry.timeRange)
                            .strikethrough(moves, color: Theme.secondaryInk)
                            .foregroundStyle(Theme.secondaryInk)
                        if moves {
                            Icon("chevronRight", size: 14)
                                .foregroundStyle(Theme.secondaryInk)
                            Text(moved.timeRange)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.primary)
                                .contentTransition(.numericText())
                        }
                    }
                    .font(.m3(12).monospacedDigit())
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minHeight: 48)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable(radius: Theme.radii.m, pressed: Theme.radii.s))
        .accessibilityLabel("\(entry.displayTitle), \(entry.timeRange)")
        .accessibilityValue(isOn ? "Da spostare" : "Resta dov'è")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Minuti con il segno, tra i pulsanti − e +: si possono anche scrivere (il tastierino non ha il
/// meno: il segno si cambia toccandolo).
struct MinutesField: View {
    @Binding var value: Int
    var large = false
    var range: ClosedRange<Int> = -720...720
    var step = 5
    @FocusState private var focused: Bool

    static func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : (value < 0 ? "−\(-value)" : "0")
    }

    /// Il numero senza segno: vale subito, anche senza chiudere il tastierino. Lo zero è il segnaposto,
    /// altrimenti scrivendo si leggerebbe "07".
    private var magnitude: Binding<String> {
        Binding { value == 0 ? "" : "\(abs(value))" } set: { typed in
            let limited = min(Int(typed.filter(\.isNumber)) ?? 0, range.upperBound)
            value = value < 0 ? -limited : limited
        }
    }

    var body: some View {
        HStack(spacing: large ? 12 : 4) {
            IconButton("minus", label: "Prima", kind: .tonal, size: large ? 48 : 32) { change(by: -step) }
                .disabled(value <= range.lowerBound)
            HStack(spacing: 2) {
                Button {
                    Haptics.selection()
                    value = -value
                } label: {
                    Text(value < 0 ? "−" : "+")
                        .frame(minWidth: large ? 22 : 12, minHeight: large ? 44 : 32)
                        .contentShape(.rect)
                }
                .buttonStyle(HeaderButtonStyle())
                .accessibilityLabel(value < 0 ? "Prima" : "Dopo")
                .accessibilityHint("Cambia il verso")
                .opacity(value == 0 ? 0.35 : 1)
                TextField("0", text: magnitude)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .accessibilityLabel("Minuti")
                if large {
                    Text("min")
                        .font(.m3(18, weight: 500))
                        .padding(.leading, 4)
                }
            }
            .font(.numeral(large ? 40 : 15, weight: large ? 600 : 650))
            .frame(minWidth: large ? 140 : 44)
            IconButton("plus", label: "Dopo", kind: .tonal, size: large ? 48 : 32) { change(by: step) }
                .disabled(value >= range.upperBound)
        }
    }

    private func change(by delta: Int) {
        Haptics.selection()
        focused = false
        withAnimation(Motion.spatialFast) {
            value = min(max(range.lowerBound, value + delta), range.upperBound)
        }
    }
}
