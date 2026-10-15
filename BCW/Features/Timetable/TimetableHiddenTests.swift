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
            Form {
                Section {
                    NavigationLink {
                        TestHidingRulesView()
                    } label: {
                        LabeledContent {
                            Text(rulesSummary)
                        } label: {
                            Label("Nascondi in automatico", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                } footer: {
                    Text("Le regole nascondono da sole le verifiche segnate dai docenti su Classeviva, ad esempio quelle di un docente, di un giorno della settimana o di un periodo. Puoi sempre mostrarne una a mano.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    if upcoming.isEmpty {
                        Text("Nessuna verifica nascosta nei prossimi giorni.")
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    ForEach(upcoming) { item in
                        HiddenTestRow(item: item)
                    }
                } header: {
                    Text("Prossime")
                }
                .listRowBackground(Theme.surface)

                if !past.isEmpty {
                    Section {
                        if showsPast {
                            ForEach(Array(past)) { item in
                                HiddenTestRow(item: item)
                            }
                        }
                        Button(showsPast ? "Nascondi le verifiche passate" : "Mostra le verifiche passate (\(past.count))") {
                            withAnimation(.snappy) { showsPast.toggle() }
                        }
                    } header: {
                        Text("Passate")
                    }
                    .listRowBackground(Theme.surface)
                }

                if !overridden.isEmpty {
                    Section {
                        ForEach(overridden) { item in
                            HiddenTestRow(item: item, overriddenRule: store.ruleReason(for: item.test, unmatched: item.unmatched))
                        }
                    } header: {
                        Text("Mostrate nonostante le regole")
                    } footer: {
                        Text("Le hai mostrate a mano. \"Nascondi\" le restituisce alle regole.")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .formStyle(.grouped)
            .themedList()
            .navigationTitle("Verifiche nascoste")
            .inlineTitleDisplay()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .sheetFrame(width: 520, height: 640)
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "pencil.and.list.clipboard")
                .foregroundStyle(Theme.secondaryInk)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(test.begin.longDay)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                Text(test.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if !test.notes.isEmpty {
                    Text(test.notes)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .lineLimit(3)
                }
                if !test.authorName.isEmpty {
                    Text(test.authorName)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
                if let overriddenRule {
                    reasonLine("Mostrata a mano · regola «\(overriddenRule)»", symbol: "eye")
                } else if let reason = item.reason {
                    reasonLine(reason.description, symbol: reason == .manual ? "hand.raised" : "line.3.horizontal.decrease.circle")
                }
            }
            Spacer(minLength: 4)
            Group {
                if overriddenRule != nil {
                    Button("Nascondi") {
                        withAnimation(.snappy) { model.timetable.resetTestOverride(test.id) }
                    }
                    .help("Torna a nascondere la verifica come dice la regola")
                } else {
                    Button("Mostra") {
                        withAnimation(.snappy) { model.timetable.setTestHidden(false, test: test, unmatched: item.unmatched) }
                    }
                    .help("Mostra di nuovo la verifica nell'orario")
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderless)
        }
    }

    /// Il motivo, con l'icona attaccata al testo (una `Label` la staccherebbe di molto su iPhone).
    private func reasonLine(_ text: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.caption)
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
            withAnimation(.snappy) { store.setTestRules(rules) }
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

        return Form {
            Section {
                Label(hiddenCount == 0 ? "Le regole non nascondono nessuna verifica."
                      : (hiddenCount == 1 ? "Le regole nascondono 1 verifica." : "Le regole nascondono \(hiddenCount) verifiche."),
                      systemImage: "eye.slash")
                    .foregroundStyle(Theme.secondaryInk)
                    .contentTransition(.numericText())
            } footer: {
                Text("Una verifica è nascosta se soddisfa almeno una regola. Le trovi tutte in Verifiche nascoste, da dove puoi mostrarle di nuovo.")
            }
            .listRowBackground(Theme.surface)

            Section("Giorni della settimana") {
                ForEach(1...7, id: \.self) { weekday in
                    Toggle(Weekday.name(weekday), isOn: member(\.weekdays, weekday))
                }
            }
            .listRowBackground(Theme.surface)

            Section {
                if teachers.isEmpty {
                    Text("Nessun docente ha ancora segnato verifiche.")
                        .foregroundStyle(Theme.secondaryInk)
                }
                ForEach(teachers, id: \.self) { teacher in
                    Toggle(teacher, isOn: member(\.teachers, teacher))
                }
            } header: {
                Text("Docenti")
            } footer: {
                Text("Nasconde le verifiche segnate da questi docenti.")
            }
            .listRowBackground(Theme.surface)

            if !subjects.isEmpty {
                Section("Materie") {
                    ForEach(subjects, id: \.key) { key, name in
                        Toggle(name, isOn: member(\.subjects, key))
                    }
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                ForEach(current.periods) { period in
                    HStack {
                        Label("\(period.start.shortDayWithYear) – \(period.end.shortDayWithYear)", systemImage: "calendar")
                        Spacer()
                        Button("Rimuovi", systemImage: "minus.circle", role: .destructive) {
                            rules.wrappedValue.periods.removeAll { $0.id == period.id }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.poor)
                        .help("Rimuovi il periodo")
                    }
                }
                DatePicker("Dal", selection: $newStart, displayedComponents: .date)
                DatePicker("Al", selection: $newEnd, in: newStart..., displayedComponents: .date)
                Button("Aggiungi il periodo", systemImage: "plus") {
                    rules.wrappedValue.periods.append(.init(start: newStart.startOfDay, end: max(newEnd, newStart).startOfDay))
                }
            } header: {
                Text("Periodi")
            } footer: {
                Text("Nasconde le verifiche di questi periodi (estremi compresi), ad esempio durante una gita o uno scambio.")
            }
            .listRowBackground(Theme.surface)

            Section {
                ForEach(current.keywords, id: \.self) { word in
                    HStack {
                        Label(word, systemImage: "text.magnifyingglass")
                        Spacer()
                        Button("Rimuovi", systemImage: "minus.circle", role: .destructive) {
                            rules.wrappedValue.keywords.removeAll { $0 == word }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.poor)
                        .help("Rimuovi la parola")
                    }
                }
                HStack {
                    TextField("Parola o frase", text: $newKeyword)
                        .onSubmit(addKeyword)
                    Button("Aggiungi", action: addKeyword)
                        .disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Parole")
            } footer: {
                Text("Nasconde le verifiche il cui testo contiene una di queste parole (ad esempio \"recupero\").")
            }
            .listRowBackground(Theme.surface)

            Section {
                Toggle("Verifiche senza lezione in orario", isOn: rules.unmatched)
            } footer: {
                Text("Nasconde le verifiche di materie che quel giorno non sono nel tuo orario.")
            }
            .listRowBackground(Theme.surface)

            if !current.isEmpty {
                Section {
                    Button("Elimina tutte le regole", role: .destructive) { rules.wrappedValue = TestHidingRules() }
                        .foregroundStyle(Theme.poor)
                }
                .listRowBackground(Theme.surface)
            }
        }
        .formStyle(.grouped)
        .themedList()
        .navigationTitle("Nascondi in automatico")
        .inlineTitleDisplay()
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
