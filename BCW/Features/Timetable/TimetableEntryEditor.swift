import SwiftUI

/// Richiesta di aprire l'editor: per un evento esistente o per uno nuovo.
struct TimetableEditorRequest: Identifiable {
    let id = UUID()
    var entry: TimetableEntry?
    var weekday: Int = 1
    var start: Int?
    var kind: TimetableEntry.Kind = .lesson
}

/// Crea o modifica un evento dell'orario.
struct TimetableEntryEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: TimetableEditorRequest

    @State private var draft: TimetableEntry
    /// Per i nuovi eventi si possono scegliere più giorni.
    @State private var weekdays: Set<Int>
    @State private var askingPropagation = false
    @State private var confirmingDelete = false

    init(request: TimetableEditorRequest) {
        self.request = request
        if let entry = request.entry {
            _draft = State(initialValue: entry)
            _weekdays = State(initialValue: [entry.weekday])
        } else {
            let start = request.start ?? 8 * 60
            let length = request.kind == .breakTime ? 10 : 60
            _draft = State(initialValue: TimetableEntry(weekday: request.weekday, start: start,
                                                        end: min(24 * 60, start + length), kind: request.kind,
                                                        title: request.kind == .breakTime ? "Intervallo" : ""))
            _weekdays = State(initialValue: [request.weekday])
        }
    }

    private var store: TimetableStore { model.timetable }
    private var isNew: Bool { request.entry == nil }
    /// Gli intervalli si posizionano sempre liberamente.
    private var usesAutomaticAlignment: Bool { store.alignment == .automatic && !draft.isBreak }
    private var sameName: [TimetableEntry] {
        guard let original = request.entry else { return [] }
        return store.sameNameEntries(as: original)
    }

    private var isValid: Bool {
        draft.end > draft.start && !weekdays.isEmpty
            && (draft.isBreak || !draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: kindBinding) {
                        ForEach(TimetableEntry.Kind.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    titleField
                }
                .listRowBackground(Theme.surface)

                Section {
                    if isNew {
                        weekdayChips
                    } else {
                        Picker("Giorno", selection: $draft.weekday) {
                            ForEach(1...7, id: \.self) { Text(Weekday.name($0)).tag($0) }
                        }
                    }
                    timeFields
                } header: {
                    Text("Quando")
                } footer: {
                    Text(timeFooter)
                }
                .listRowBackground(Theme.surface)

                Section("Dettagli") {
                    if !draft.isBreak {
                        TextField("Docente", text: $draft.teacher)
                        TextField("Aula", text: $draft.room)
                    }
                    NavigationLink {
                        EntryColorPicker(color: $draft.color, entry: draft)
                    } label: {
                        HStack {
                            Text("Colore")
                            Spacer()
                            colorDescription
                            Circle()
                                .fill(Theme.timetableColor(draft, store: store))
                                .frame(width: 22, height: 22)
                        }
                    }
                    TextField("Nota per ogni settimana", text: $draft.note, axis: .vertical)
                        .lineLimit(2...6)
                }
                .listRowBackground(Theme.surface)

                if !isNew {
                    Section {
                        Button("Elimina evento", systemImage: "trash", role: .destructive) {
                            confirmingDelete = true
                        }
                        .foregroundStyle(Theme.poor)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .formStyle(.grouped)
            .themedList()
            .onAppear {
                // Un evento fuori dalle mezz'ore con l'allineamento automatico (es. da un backup):
                // l'editor lo allinea, come farebbe il passaggio all'allineamento automatico.
                if usesAutomaticAlignment && !draft.isAutoAligned { align() }
            }
            .navigationTitle(isNew ? (draft.isBreak ? "Nuovo intervallo" : "Nuovo evento") : "Modifica evento")
            .inlineTitleDisplay()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", systemImage: "checkmark") { save() }
                        .disabled(!isValid)
                }
            }
            .confirmationDialog("Applicare le modifiche anche agli altri eventi «\(request.entry?.displayTitle ?? "")»?",
                                isPresented: $askingPropagation, titleVisibility: .visible) {
                Button("Applica a tutti (\(sameName.count + 1))") { commit(propagate: true) }
                Button("Solo a questo evento") { commit(propagate: false) }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Nome, materia, docente, aula, colore e nota verranno aggiornati in tutti gli eventi con lo stesso nome. Orari, giorni e colori delle palette applicate a una giornata restano invariati.")
            }
            .confirmationDialog("Eliminare «\(draft.displayTitle)»?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Elimina solo questo", role: .destructive) { delete(all: false) }
                if !sameName.isEmpty {
                    Button("Elimina tutti gli eventi «\(draft.displayTitle)» (\(sameName.count + 1))", role: .destructive) {
                        delete(all: true)
                    }
                }
                Button("Annulla", role: .cancel) {}
            }
        }
        .sheetFrame(width: 500, height: 640)
    }

    // MARK: Campi

    private var kindBinding: Binding<TimetableEntry.Kind> {
        Binding {
            draft.kind
        } set: { kind in
            draft.kind = kind
            if kind == .breakTime {
                if draft.title.isEmpty { draft.title = "Intervallo" }
                if draft.duration > 30 { draft.end = draft.start + 10 }
            } else {
                if draft.title == "Intervallo" { draft.title = "" }
                if store.alignment == .automatic, !draft.isAutoAligned { align() }
            }
        }
    }

    @ViewBuilder
    private var titleField: some View {
        HStack {
            TextField(draft.isBreak ? "Nome (es. Intervallo)" : "Materia o evento", text: $draft.title)
            if !draft.isBreak && !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.name) { suggestion in
                        Button(suggestion.name) { choose(suggestion) }
                    }
                } label: {
                    Image(systemName: "list.bullet.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
                .plainMenuOnMac()
                .help("Scegli una materia")
                .accessibilityLabel("Scegli una materia")
            }
        }
    }

    private struct Suggestion {
        let name: String
        let subjectId: Int?
        let teacher: String?
    }

    /// Materie di Classeviva e nomi già usati nell'orario.
    private var suggestions: [Suggestion] {
        var seen = Set<String>()
        var result: [Suggestion] = []
        for subject in model.subjects.sorted(by: { $0.order < $1.order }) where !subject.name.isEmpty {
            if seen.insert(TimetableEntry.normalized(subject.name)).inserted {
                result.append(Suggestion(name: subject.name, subjectId: subject.id, teacher: subject.teachers.first?.nameCased))
            }
        }
        for title in store.knownTitles where seen.insert(TimetableEntry.normalized(title)).inserted {
            result.append(Suggestion(name: title, subjectId: nil, teacher: nil))
        }
        return result
    }

    private func choose(_ suggestion: Suggestion) {
        draft.title = suggestion.name
        // Se c'è già un evento con questo nome, il nuovo ne prende i dettagli.
        if let existing = store.timetable.entries.first(where: { $0.matchKey == draft.matchKey && $0.id != draft.id }) {
            draft.subjectId = existing.subjectId ?? suggestion.subjectId
            if draft.teacher.isEmpty { draft.teacher = existing.teacher }
            if draft.room.isEmpty { draft.room = existing.room }
            if draft.color == nil, existing.color?.paletteID == nil { draft.color = existing.color }
        } else {
            draft.subjectId = suggestion.subjectId
            if draft.teacher.isEmpty, let teacher = suggestion.teacher { draft.teacher = teacher }
        }
    }

    private var weekdayChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Giorni")
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { weekday in
                    let selected = weekdays.contains(weekday)
                    Button {
                        if selected { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                    } label: {
                        Text(Weekday.shortName(weekday))
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .foregroundStyle(selected ? Color.white : Theme.ink)
                            .background(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.background),
                                        in: .rect(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    /// Orari inseriti a mano. Con l'allineamento automatico l'inizio si sceglie tra le ore e le
    /// mezz'ore e la durata tra 30 minuti e un'ora; con quello libero (e per gli intervalli)
    /// inizio e fine sono qualsiasi orario.
    @ViewBuilder
    private var timeFields: some View {
        if usesAutomaticAlignment {
            Picker("Inizio", selection: startBinding) {
                ForEach(Array(stride(from: 0, to: 24 * 60, by: 30)), id: \.self) { minute in
                    Text(TimeOfDay.string(minute)).tag(minute)
                }
            }
            Picker("Durata", selection: durationBinding) {
                Text("30 minuti").tag(30)
                Text("1 ora").tag(60)
            }
            .pickerStyle(.segmented)
            LabeledContent("Fine", value: TimeOfDay.string(draft.end))
        } else {
            DatePicker("Inizio", selection: minuteBinding(\.start), displayedComponents: .hourAndMinute)
            DatePicker("Fine", selection: minuteBinding(\.end), displayedComponents: .hourAndMinute)
            LabeledContent("Durata", value: draft.end > draft.start ? TimeOfDay.duration(draft.duration) : "—")
        }
    }

    private var timeFooter: String {
        if draft.end <= draft.start { return "L'evento deve finire dopo l'inizio." }
        if draft.isBreak {
            return "Gli intervalli si posizionano sempre liberamente e compaiono sopra le lezioni, senza cambiarne la durata."
        }
        if usesAutomaticAlignment {
            return "Allineamento automatico: gli eventi iniziano all'ora o alla mezz'ora e durano 30 minuti o un'ora. Per orari liberi passa all'allineamento libero in Modifica orario."
        }
        return "Allineamento libero: inizio e fine possono essere qualsiasi orario."
    }

    private var startBinding: Binding<Int> {
        Binding {
            draft.start
        } set: { start in
            let length = draft.duration
            draft.start = min(start, 24 * 60 - length)
            draft.end = draft.start + length
        }
    }

    private var durationBinding: Binding<Int> {
        Binding {
            draft.duration
        } set: { duration in
            draft.start = min(draft.start, 24 * 60 - duration)
            draft.end = draft.start + duration
        }
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<TimetableEntry, Int>) -> Binding<Date> {
        Binding {
            TimeOfDay.date(min(draft[keyPath: keyPath], 24 * 60 - 1))
        } set: { date in
            let minutes = TimeOfDay.minutes(of: date)
            if keyPath == \.start {
                // Spostando l'inizio la durata resta la stessa.
                let length = max(1, draft.duration)
                draft.start = minutes
                draft.end = min(24 * 60, minutes + length)
            } else {
                draft.end = minutes == 0 ? 24 * 60 : minutes
            }
        }
    }

    /// Porta l'evento sulle ore e mezz'ore (30 minuti o un'ora): l'editor con l'allineamento
    /// automatico non può mostrare altri orari.
    private func align() {
        let start = TimeOfDay.snapped(draft.start, step: 30)
        let duration = draft.duration < 45 ? 30 : 60
        draft.start = min(max(0, start), 24 * 60 - duration)
        draft.end = draft.start + duration
    }

    @ViewBuilder
    private var colorDescription: some View {
        let text: String = switch draft.color {
        case nil: "Automatico"
        case .pastel?: "Suggerito"
        case .custom?: "Personalizzato"
        case let .series(id, _, _)?: store.palette(id: id)?.name ?? "Palette"
        }
        Text(text).foregroundStyle(Theme.secondaryInk)
    }

    // MARK: Salvataggio

    private func save() {
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let original = request.entry, !sameName.isEmpty, TimetableStore.SharedFields.differences(original, draft) {
            askingPropagation = true
        } else {
            commit(propagate: false)
        }
    }

    private func commit(propagate: Bool) {
        withAnimation(.snappy) {
            if isNew {
                let entries = weekdays.sorted().enumerated().map { index, weekday in
                    var entry = draft
                    entry.weekday = weekday
                    if index > 0 { entry.id = UUID() }
                    return entry
                }
                store.add(entries)
            } else {
                store.save(draft, propagatingFrom: propagate ? request.entry : nil)
            }
        }
        dismiss()
    }

    private func delete(all: Bool) {
        guard let original = request.entry else { return }
        let ids = Set([original.id] + (all ? sameName.map(\.id) : []))
        withAnimation(.snappy) { store.delete(ids) }
        dismiss()
    }
}
