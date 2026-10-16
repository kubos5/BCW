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
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        SegmentedButtons(selection: kindBinding,
                                         options: TimetableEntry.Kind.allCases.map { ($0, $0.title, $0.icon) },
                                         height: 44)
                        titleField
                    }

                    ListGroup("Quando", footer: timeFooter) {
                        if isNew {
                            weekdayChips
                        } else {
                            SelectRow("Giorno", icon: "calendar", selection: $draft.weekday,
                                      options: (1...7).map { ($0, Weekday.name($0), nil) })
                        }
                        timeFields
                    }

                    ListGroup("Dettagli") {
                        if !draft.isBreak {
                            TextFieldRow("Docente", text: $draft.teacher, icon: "person")
                            TextFieldRow("Aula", text: $draft.room, icon: "doorOpen")
                        }
                        NavigationLink {
                            EntryColorPicker(color: $draft.color, entry: draft)
                        } label: {
                            ListRow("Colore", leading: { FormIcon("palette") }, trailing: {
                                HStack(spacing: 10) {
                                    colorDescription
                                    Circle()
                                        .fill(Theme.timetableColor(draft, store: store))
                                        .frame(width: 24, height: 24)
                                    Icon("chevronRight", size: 20)
                                        .foregroundStyle(Theme.secondaryInk)
                                }
                            })
                        }
                        .buttonStyle(.listRow)
                        NoteField(text: $draft.note, prompt: "Nota per ogni settimana")
                    }

                    if !isNew {
                        ListGroup {
                            ButtonRow("Elimina evento", icon: "trash", destructive: true) {
                                confirmingDelete = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                // Un evento fuori dalle mezz'ore con l'allineamento automatico (es. da un backup):
                // l'editor lo allinea, come farebbe il passaggio all'allineamento automatico.
                if usesAutomaticAlignment && !draft.isAutoAligned { align() }
            }
            .sheetChrome(isNew ? (draft.isBreak ? "Nuovo intervallo" : "Nuovo evento") : "Modifica evento",
                         leading: .cancel { dismiss() },
                         trailing: [.confirm("Salva", disabled: !isValid) { save() }])
            .m3Dialog("Applicare le modifiche anche agli altri eventi «\(request.entry?.displayTitle ?? "")»?",
                      isPresented: $askingPropagation,
                      message: "Nome, materia, docente, aula, colore e nota verranno aggiornati in tutti gli eventi con lo stesso nome. Orari, giorni e colori delle palette applicate a una giornata restano invariati.",
                      stacked: true) {
                [DialogAction(title: "Applica a tutti (\(sameName.count + 1))", style: .strong) { commit(propagate: true) },
                 DialogAction(title: "Solo a questo evento") { commit(propagate: false) },
                 .cancel()]
            }
            .m3Dialog("Eliminare «\(draft.displayTitle)»?", isPresented: $confirmingDelete, stacked: true) {
                var actions = [DialogAction(title: "Elimina solo questo", style: .destructive) { delete(all: false) }]
                if !sameName.isEmpty {
                    actions.append(DialogAction(title: "Elimina tutti gli eventi «\(draft.displayTitle)» (\(sameName.count + 1))",
                                                style: .destructive) { delete(all: true) })
                }
                actions.append(.cancel())
                return actions
            }
        }
        .m3Sheet()
        .sheetFrame(width: 520, height: 680)
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
        HStack(spacing: 8) {
            TextField(draft.isBreak ? "Nome (es. Intervallo)" : "Materia o evento", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.m3(16))
                .foregroundStyle(Theme.ink)
            if !draft.isBreak && !suggestions.isEmpty {
                AppMenu {
                    MenuSection("Materie") {
                        ForEach(suggestions, id: \.name) { suggestion in
                            MenuItem(suggestion.name, checked: TimetableEntry.normalized(suggestion.name)
                                     == TimetableEntry.normalized(draft.title)) { choose(suggestion) }
                        }
                    }
                } label: {
                    Label { Text("Scegli una materia") } icon: { Icon("list") }
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.m3Icon(.tonal, size: 36))
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .help("Scegli una materia")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(minHeight: 56)
        .background(Theme.surfaceContainerHighest, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Giorni")
                .font(.m3(16, weight: 500))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { weekday in
                    let selected = weekdays.contains(weekday)
                    Button {
                        Haptics.selection()
                        withAnimation(Motion.spatialFast) {
                            if selected { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                        }
                    } label: {
                        Text(Weekday.shortName(weekday))
                            .font(.m3(13, weight: selected ? 700 : 550))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .foregroundStyle(selected ? Theme.onPrimary : Theme.ink)
                            .background(selected ? Theme.primary : Theme.surfaceContainerHighest,
                                        in: .rect(cornerRadius: selected ? 20 : Theme.radii.m, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(16)
    }

    /// Orari inseriti a mano. Con l'allineamento automatico l'inizio si sceglie tra le ore e le
    /// mezz'ore e la durata tra 30 minuti e un'ora; con quello libero (e per gli intervalli)
    /// inizio e fine sono qualsiasi orario.
    @ViewBuilder
    private var timeFields: some View {
        if usesAutomaticAlignment {
            SelectRow("Inizio", icon: "clock", selection: startBinding,
                      options: stride(from: 0, to: 24 * 60, by: 30).map { ($0, TimeOfDay.string($0), nil) })
            ListRow("Durata", leading: { FormIcon("timer") }, trailing: {
                SegmentedButtons(selection: durationBinding, options: [(30, "30 min", nil), (60, "1 ora", nil)],
                                 compact: true, height: 36)
            })
            ValueRow("Fine", value: TimeOfDay.string(draft.end), icon: "clockAlert")
        } else {
            ListRow("Inizio", leading: { FormIcon("clock") }, trailing: { TimeField(minutes: startMinutes) })
            ListRow("Fine", leading: { FormIcon("clockAlert") }, trailing: { TimeField(minutes: endMinutes) })
            ValueRow("Durata", value: draft.end > draft.start ? TimeOfDay.duration(draft.duration) : "—", icon: "timer")
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

    /// Inizio libero: spostandolo la durata resta la stessa.
    private var startMinutes: Binding<Int> {
        Binding {
            min(draft.start, 24 * 60 - 1)
        } set: { minutes in
            let length = max(1, draft.duration)
            draft.start = minutes
            draft.end = min(24 * 60, minutes + length)
        }
    }

    private var endMinutes: Binding<Int> {
        Binding {
            min(draft.end, 24 * 60 - 1)
        } set: { minutes in
            draft.end = minutes == 0 ? 24 * 60 : minutes
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
        Text(text).font(.m3(14)).foregroundStyle(Theme.secondaryInk)
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
        withAnimation(Motion.spatial) {
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
        withAnimation(Motion.spatial) { store.delete(ids) }
        dismiss()
    }
}
