import SwiftUI

/// "Verifiche nascoste" (menu dell'orario): le verifiche di Classeviva nascoste a mano o dalle
/// regole automatiche, con il motivo e il pulsante per mostrarle di nuovo; in cima le regole.
/// Le verifiche mostrate a mano nonostante le regole hanno una sezione a parte, da cui si
/// possono restituire alle regole.
struct TimetableHiddenTestsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showsPast = false

    struct Item: Identifiable {
        let test: AgendaEvent
        let reason: TestHiddenReason?
        let unmatched: Bool
        var id: Int { test.id }
    }

    private var store: TimetableStore { model.timetable }

    var body: some View {
        let items = Self.items(model: model)
        let hidden = items.filter { $0.reason != nil }
        let today = Date().startOfDay
        let upcoming = hidden.filter { $0.test.begin >= today }
        let past = hidden.filter { $0.test.begin < today }.reversed()
        // Mostrate a mano ma nascoste da una regola.
        let overridden = items.filter {
            $0.reason == nil && store.timetable.shownTests.contains($0.test.id)
                && store.ruleReason(for: $0.test, unmatched: $0.unmatched) != nil
        }

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ListGroup(footer: "Le regole nascondono da sole le verifiche segnate dai docenti su Classeviva, ad esempio quelle di un docente, di un giorno della settimana o di un periodo. Puoi sempre mostrarne una a mano.") {
                        NavigationLink {
                            TestHidingRulesView()
                        } label: {
                            ListRow("Nascondi in automatico", leading: { FormIcon("filter") }, trailing: {
                                HStack(spacing: 8) {
                                    Text(rulesSummary)
                                        .font(.m3(14))
                                        .foregroundStyle(Theme.secondaryInk)
                                    Icon("chevronRight", size: 20)
                                        .foregroundStyle(Theme.secondaryInk)
                                }
                            })
                        }
                        .buttonStyle(.listRow)
                    }

                    ListGroup("Prossime") {
                        if upcoming.isEmpty {
                            ListRow("Nessuna verifica nascosta nei prossimi giorni.", titleColor: Theme.secondaryInk)
                        }
                        ForEach(upcoming) { item in
                            HiddenTestRow(item: item)
                        }
                    }

                    if !past.isEmpty {
                        ListGroup("Passate") {
                            if showsPast {
                                ForEach(Array(past)) { item in
                                    HiddenTestRow(item: item)
                                }
                            }
                            ButtonRow(showsPast ? "Nascondi le verifiche passate" : "Mostra le verifiche passate (\(past.count))",
                                      icon: showsPast ? "eyeOff" : "eye") {
                                withAnimation(Motion.spatial) { showsPast.toggle() }
                            }
                        }
                    }

                    if !overridden.isEmpty {
                        ListGroup("Mostrate nonostante le regole", footer: "Le hai mostrate a mano. \"Nascondi\" le restituisce alle regole.") {
                            ForEach(overridden) { item in
                                HiddenTestRow(item: item, overriddenRule: store.ruleReason(for: item.test, unmatched: item.unmatched))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .sheetChrome("Verifiche nascoste", leading: .close { dismiss() }, trailing: [.confirm("Fine") { dismiss() }])
        }
        .m3Sheet()
        .sheetFrame(width: 540, height: 660)
    }

    private var rulesSummary: String {
        let count = store.timetable.testRules.count
        return count == 0 ? "Nessuna" : (count == 1 ? "1 regola" : "\(count) regole")
    }

    /// Tutte le verifiche di Classeviva, in ordine di data, con il motivo per cui sono nascoste.
    static func items(model: AppModel) -> [Item] {
        let store = model.timetable
        return model.agenda.filter { $0.kind == .test }.sorted { $0.begin < $1.begin }.map { test in
            let unmatched = !TimetableDayContent.match([test], to: store.entries(on: test.begin)).unmatched.isEmpty
            return Item(test: test, reason: store.hiddenReason(for: test, unmatched: unmatched), unmatched: unmatched)
        }
    }
}

/// Una verifica nella sezione delle verifiche nascoste: giorno, materia, testo, motivo e pulsante.
private struct HiddenTestRow: View {
    @Environment(AppModel.self) private var model
    let item: TimetableHiddenTestsView.Item
    /// Per le verifiche mostrate nonostante le regole: la regola che le nasconderebbe.
    var overriddenRule: String?

    var body: some View {
        let test = item.test
        HStack(alignment: .top, spacing: 12) {
            Icon("test")
                .foregroundStyle(Theme.secondaryInk)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(test.begin.longDay)
                    .font(.m3(12, weight: 650))
                    .foregroundStyle(Theme.primary)
                Text(test.title)
                    .font(.m3(15, weight: 600))
                    .foregroundStyle(Theme.ink)
                if !test.notes.isEmpty {
                    Text(test.notes)
                        .font(.m3(14))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(3)
                }
                if !test.authorName.isEmpty {
                    Text(test.authorName)
                        .font(.m3(12))
                        .foregroundStyle(Theme.secondaryInk)
                }
                if let overriddenRule {
                    reasonLine("Mostrata a mano · regola «\(overriddenRule)»", icon: "eye")
                } else if let reason = item.reason {
                    reasonLine(reason.description, icon: reason == .manual ? "hand" : "filter")
                }
            }
            Spacer(minLength: 4)
            Group {
                if overriddenRule != nil {
                    Button("Nascondi") {
                        withAnimation(Motion.spatial) { model.timetable.resetTestOverride(test.id) }
                    }
                    .help("Torna a nascondere la verifica come dice la regola")
                } else {
                    Button("Mostra") {
                        withAnimation(Motion.spatial) { model.timetable.setTestHidden(false, test: test, unmatched: item.unmatched) }
                    }
                    .help("Mostra di nuovo la verifica nell'orario")
                }
            }
            .buttonStyle(.m3(.text, size: .xs))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Il motivo, con l'icona attaccata al testo.
    private func reasonLine(_ text: String, icon: String) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Icon(icon, size: 14)
            Text(text)
        }
        .font(.m3(12))
        .foregroundStyle(Theme.secondaryInk)
        .padding(.top, 2)
    }
}

/// Regole per nascondere in automatico le verifiche: docenti, materie, giorni, periodi, parole e
/// verifiche senza lezione in orario.
struct TestHidingRulesView: View {
    @Environment(AppModel.self) private var model
    @State private var newStart = Date().startOfDay
    @State private var newEnd = Date().startOfDay.adding(days: 6)
    @State private var newKeyword = ""

    private var store: TimetableStore { model.timetable }

    private var rules: Binding<TestHidingRules> {
        Binding { store.timetable.testRules } set: { rules in
            withAnimation(Motion.spatial) { store.setTestRules(rules) }
        }
    }

    var body: some View {
        let tests = model.agenda.filter { $0.kind == .test }
        let current = store.timetable.testRules
        let teachers = Set(tests.map(\.authorName).filter { !$0.isEmpty }).union(current.teachers).sorted()
        // Materie: nome da mostrare per ogni chiave normalizzata.
        var subjectNames: [String: String] = [:]
        for name in tests.compactMap(\.subjectName) { subjectNames[TimetableEntry.normalized(name)] = name }
        for key in current.subjects where subjectNames[key] == nil { subjectNames[key] = key.capitalizedFirst }
        let subjects = subjectNames.sorted { $0.value < $1.value }
        let hiddenCount = TimetableHiddenTestsView.items(model: model).filter {
            if case .rule = $0.reason { return true } else { return false }
        }.count

        return ScrollView {
            VStack(spacing: 20) {
                ListGroup(footer: "Una verifica è nascosta se soddisfa almeno una regola. Le trovi tutte in Verifiche nascoste, da dove puoi mostrarle di nuovo.") {
                    ListRow(hiddenCount == 0 ? "Le regole non nascondono nessuna verifica."
                            : (hiddenCount == 1 ? "Le regole nascondono 1 verifica." : "Le regole nascondono \(hiddenCount) verifiche."),
                            titleColor: Theme.secondaryInk, leading: { FormIcon("eyeOff") }, trailing: { EmptyView() })
                        .contentTransition(.numericText())
                }

                ListGroup("Giorni della settimana") {
                    ForEach(1...7, id: \.self) { weekday in
                        ToggleRow(Weekday.name(weekday), isOn: member(\.weekdays, weekday))
                    }
                }

                ListGroup("Docenti", footer: "Nasconde le verifiche segnate da questi docenti.") {
                    if teachers.isEmpty {
                        ListRow("Nessun docente ha ancora segnato verifiche.", titleColor: Theme.secondaryInk)
                    }
                    ForEach(teachers, id: \.self) { teacher in
                        ToggleRow(teacher, isOn: member(\.teachers, teacher))
                    }
                }

                if !subjects.isEmpty {
                    ListGroup("Materie") {
                        ForEach(subjects, id: \.key) { key, name in
                            ToggleRow(name, isOn: member(\.subjects, key))
                        }
                    }
                }

                ListGroup("Periodi", footer: "Nasconde le verifiche di questi periodi (estremi compresi), ad esempio durante una gita o uno scambio.") {
                    ForEach(current.periods) { period in
                        ListRow("\(period.start.shortDayWithYear) – \(period.end.shortDayWithYear)", leading: {
                            FormIcon("calendar")
                        }, trailing: {
                            IconButton("minusCircle", label: "Rimuovi il periodo", kind: .danger, size: 32) {
                                rules.wrappedValue.periods.removeAll { $0.id == period.id }
                            }
                        })
                    }
                    ListRow("Dal", leading: { FormIcon("calendarDay") }, trailing: {
                        DateField(date: $newStart).frame(maxWidth: 220)
                    })
                    ListRow("Al", leading: { FormIcon("calendarDay") }, trailing: {
                        DateField(date: $newEnd, range: newStart...Date.distantFuture).frame(maxWidth: 220)
                    })
                    ButtonRow("Aggiungi il periodo", icon: "plus") {
                        rules.wrappedValue.periods.append(.init(start: newStart.startOfDay, end: max(newEnd, newStart).startOfDay))
                    }
                }

                ListGroup("Parole", footer: "Nasconde le verifiche il cui testo contiene una di queste parole (ad esempio \"recupero\").") {
                    ForEach(current.keywords, id: \.self) { word in
                        ListRow(word, leading: { FormIcon("textSearch") }, trailing: {
                            IconButton("minusCircle", label: "Rimuovi la parola", kind: .danger, size: 32) {
                                rules.wrappedValue.keywords.removeAll { $0 == word }
                            }
                        })
                    }
                    HStack(spacing: 8) {
                        TextFieldRow("Parola o frase", text: $newKeyword, icon: "add")
                            .onSubmit(addKeyword)
                        Button("Aggiungi", action: addKeyword)
                            .buttonStyle(.m3(.tonal, size: .xs))
                            .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                            .padding(.trailing, 12)
                    }
                }

                ListGroup(footer: "Nasconde le verifiche di materie che quel giorno non sono nel tuo orario.") {
                    ToggleRow("Verifiche senza lezione in orario", icon: "calendarMinus", isOn: rules.unmatched)
                }

                if !current.isEmpty {
                    ListGroup {
                        ButtonRow("Elimina tutte le regole", icon: "trash", destructive: true) { rules.wrappedValue = TestHidingRules() }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .themedBackground()
        .pageChrome("Nascondi in automatico", style: .inline, showsBack: true)
    }

    private func member<Value: Hashable>(_ keyPath: WritableKeyPath<TestHidingRules, Set<Value>>, _ value: Value) -> Binding<Bool> {
        Binding {
            store.timetable.testRules[keyPath: keyPath].contains(value)
        } set: { isOn in
            var updated = store.timetable.testRules
            if isOn { updated[keyPath: keyPath].insert(value) } else { updated[keyPath: keyPath].remove(value) }
            rules.wrappedValue = updated
        }
    }

    private func addKeyword() {
        let word = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !store.timetable.testRules.keywords.contains(word) else { return }
        rules.wrappedValue.keywords.append(word)
        newKeyword = ""
    }
}
