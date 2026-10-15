import SwiftUI

/// Impostazioni per creare una bozza dell'orario dalle lezioni registrate.
struct TimetableGeneratorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var settings = GenerationSettings()
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var loaded = false

    private var store: TimetableStore { model.timetable }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Inizio della prima ora", selection: minuteBinding(\.firstHourStart),
                               displayedComponents: .hourAndMinute)
                    LabeledStepper("Durata di un'ora", value: "\(settings.hourLength) min",
                                   number: $settings.hourLength, in: 30...120, step: 5)
                    Picker("Lezioni da esaminare", selection: $settings.weeks) {
                        Text("Ultime 2 settimane").tag(2)
                        Text("Ultime 4 settimane").tag(4)
                        Text("Ultime 6 settimane").tag(6)
                        Text("Ultime 10 settimane").tag(10)
                        Text("Tutto l'anno").tag(0)
                    }
                } header: {
                    Text("Ore di lezione")
                } footer: {
                    Text(hoursFooter)
                }
                .listRowBackground(Theme.surface)

                Section {
                    ForEach($settings.breaks) { $rule in
                        breakRow($rule)
                    }
                    .onDelete { settings.breaks.remove(atOffsets: $0) }
                    Button("Aggiungi intervallo", systemImage: "cup.and.saucer") {
                        let after = settings.breaks.last.map { $0.start + 120 }
                            ?? (settings.firstHourStart + settings.hourLength * 3 - 10)
                        settings.breaks.append(.init(start: min(after, 23 * 60), duration: 10))
                    }
                    if !settings.breaks.isEmpty {
                        Button("Rimuovi gli intervalli", role: .destructive) { settings.breaks = [] }
                            .foregroundStyle(Theme.poor)
                    }
                } header: {
                    Text("Intervalli")
                } footer: {
                    Text("Facoltativi: compaiono sopra le lezioni nei giorni in cui c'è scuola a quell'ora, senza cambiarne la durata. "
                         + (Platform.isMac ? "Per toglierne uno fai clic sul pulsante rosso accanto." : "Per toglierne uno scorri verso sinistra."))
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack {
                            Label("Crea l'anteprima", systemImage: "wand.and.stars")
                            Spacer()
                            if isGenerating { InlineProgress() }
                        }
                    }
                    .disabled(isGenerating)
                } footer: {
                    Text("BCW guarda in quale ora della giornata si è svolta ogni materia, settimana per settimana, e tiene quelle che si ripetono (le settimane recenti contano di più, supplenze e recuperi isolati vengono ignorati). Vedrai l'orario in anteprima, con i bordi tratteggiati, prima di applicarlo.")
                }
                .listRowBackground(Theme.surface)
            }
            .formStyle(.grouped)
            .themedList()
            .navigationTitle("Genera l'orario")
            .inlineTitleDisplay()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", systemImage: "xmark") { dismiss() }
                }
            }
            .alert("Impossibile creare l'orario", isPresented: Binding(get: { errorMessage != nil },
                                                                     set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                settings = store.draft?.settings ?? store.timetable.generation
                #if DEBUG
                // Per gli screenshot: `-BCWGeneratorBreaks N` aggiunge N intervalli.
                let extra = UserDefaults.standard.integer(forKey: "BCWGeneratorBreaks")
                for index in 0..<extra { settings.breaks.append(.init(start: 9 * 60 + 50 + index * 120, duration: 10)) }
                #endif
            }
        }
        .sheetFrame(width: 480, height: 620)
    }

    private var hoursFooter: String {
        let aligned = settings.firstHourStart % 30 == 0 && (settings.hourLength == 30 || settings.hourLength == 60)
        if store.alignment == .automatic && !aligned {
            return "L'orario usa l'allineamento automatico: con questi orari le lezioni verranno spostate all'ora o alla mezz'ora più vicina. Per tenere gli orari esatti passa all'allineamento libero in Modifica orario."
        }
        return "Classeviva registra solo in quale ora della giornata si svolge una lezione: l'orario si ricava da qui."
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<GenerationSettings, Int>) -> Binding<Date> {
        Binding { TimeOfDay.date(settings[keyPath: keyPath]) } set: { settings[keyPath: keyPath] = TimeOfDay.minutes(of: $0) }
    }

    /// Un intervallo: inizio e durata a destra del titolo (in un'unica riga di controlli, che su
    /// macOS altrimenti finirebbero uno sopra l'altro, tagliati); su Mac anche il pulsante per
    /// toglierlo, che su iPhone è lo scorrimento verso sinistra.
    private func breakRow(_ rule: Binding<GenerationSettings.BreakRule>) -> some View {
        let id = rule.wrappedValue.id
        let number = (settings.breaks.firstIndex { $0.id == id } ?? 0) + 1
        return LabeledContent {
            HStack(spacing: 10) {
                DatePicker("Inizio", selection: breakStartBinding(rule), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                Text("\(rule.wrappedValue.duration) min")
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryInk)
                Stepper("Durata", value: rule.duration, in: 5...60, step: 5)
                    .labelsHidden()
                #if os(macOS)
                Button("Rimuovi l'intervallo", systemImage: "minus.circle.fill", role: .destructive) {
                    withAnimation(.snappy) { settings.breaks.removeAll { $0.id == id } }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.poor)
                .help("Rimuovi questo intervallo")
                #endif
            }
            .fixedSize()
        } label: {
            Label("Intervallo \(number)", systemImage: "cup.and.saucer")
                .lineLimit(1)
        }
    }

    private func breakStartBinding(_ rule: Binding<GenerationSettings.BreakRule>) -> Binding<Date> {
        Binding { TimeOfDay.date(rule.wrappedValue.start) } set: { rule.wrappedValue.start = TimeOfDay.minutes(of: $0) }
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        let range = TimetableGenerator.range(for: settings)
        let lessons: [Lesson]
        do {
            lessons = try await model.fetchLessons(from: range.from, to: range.to)
        } catch {
            errorMessage = "Non riesco a scaricare le lezioni: \(error.localizedDescription)"
            return
        }
        var result = TimetableGenerator.generate(from: lessons, settings: settings)
        // Con l'allineamento automatico anche la bozza rispetta le ore e le mezz'ore.
        if store.alignment == .automatic {
            result.entries = result.entries.flatMap { $0.alignedPieces() }
        }
        guard !result.entries.isEmpty else {
            errorMessage = lessons.isEmpty
                ? "Non ci sono lezioni registrate nel periodo scelto. Riprova più avanti o esamina un periodo più lungo."
                : "Le lezioni registrate sono troppo poche o troppo irregolari per ricavare un orario. Prova a esaminare un periodo più lungo."
            return
        }
        withAnimation(.snappy) {
            store.draft = TimetableDraft(entries: result.entries, settings: settings, analyzedDays: result.analyzedDays,
                                         from: range.from, to: range.to)
        }
        dismiss()
    }
}

/// Banner dell'anteprima: applica o scarta l'orario generato.
struct TimetableDraftBanner: View {
    @Environment(AppModel.self) private var model
    let onSettings: () -> Void
    @State private var confirmingApply = false

    var body: some View {
        if let draft = model.timetable.draft {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "wand.and.stars")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Anteprima dell'orario generato")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text("\(lessonCount(draft)) lezioni ricavate da \(draft.analyzedDays) giorni di registro (\(draft.from.shortDay) – \(draft.to.shortDay)). Controllale prima di applicarle.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                            .lineLimit(4)
                    }
                }
                HStack(spacing: 8) {
                    Button("Applica", systemImage: "checkmark") {
                        if model.timetable.timetable.isEmpty {
                            withAnimation(.snappy) { model.timetable.applyDraft(replacing: true) }
                        } else {
                            confirmingApply = true
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .confirmationDialog("Hai già un orario", isPresented: $confirmingApply, titleVisibility: .visible) {
                        Button("Sostituisci l'orario attuale", role: .destructive) {
                            withAnimation(.snappy) { model.timetable.applyDraft(replacing: true) }
                        }
                        Button("Aggiungi solo dove è libero") {
                            withAnimation(.snappy) { model.timetable.applyDraft(replacing: false) }
                        }
                        Button("Annulla", role: .cancel) {}
                    } message: {
                        Text("Sostituendolo, eventi, note, file e verifiche segnate a mano dell'orario attuale verranno eliminati.")
                    }
                    Button("Scarta", systemImage: "xmark") {
                        withAnimation(.snappy) { model.timetable.draft = nil }
                    }
                    .glassButton()
                    Spacer(minLength: 0)
                    Button("Impostazioni", systemImage: "slider.horizontal.3", action: onSettings)
                        .labelStyle(.iconOnly)
                        .glassButton()
                        .help("Cambia le impostazioni e rigenera")
                }
                .controlSize(.small)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.accentSoft.opacity(0.55))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func lessonCount(_ draft: TimetableDraft) -> Int {
        draft.entries.filter { !$0.isBreak }.count
    }
}

// MARK: - Impostazioni

/// Impostazioni dell'orario: allineamento, backup e (in arrivo) iCloud.
struct TimetableSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var exportDocument: TimetableBackupDocument?
    @State private var importing = false
    @State private var pendingBackup: TimetableBackup?
    @State private var firstConfirmation = false
    @State private var secondConfirmation = false
    @State private var confirmingDeleteAll = false
    @State private var result: (title: String, message: String)?

    private var store: TimetableStore { model.timetable }

    var body: some View {
        Section {
            TimetableAlignmentPicker()
            Toggle("Mostra le verifiche nella lista", isOn: Bindable(model.preferences).timetableShowsTests)
        } header: {
            Text("Vista e allineamento")
        } footer: {
            Text("Con \"Mostra le verifiche\" la vista Lista segna le verifiche di Classeviva e quelle segnate a mano; si vedono sempre nel dettaglio dell'evento e nella vista Giorno. Quelle nascoste, e le regole per nasconderle in automatico, sono in Verifiche nascoste (menu dell'orario). L'allineamento vale per tutto l'orario e per la modalità di modifica (menu dell'orario › Modifica orario). Automatico: gli eventi iniziano all'ora o alla mezz'ora e durano 30 minuti o un'ora; passando all'automatico gli eventi non allineati vengono allineati, dopo una conferma. Libero: qualsiasi orario e durata. Gli intervalli si posizionano sempre liberamente.")
        }
        .listRowBackground(Theme.surface)

        Section {
            Button("Esporta un backup dell'orario", systemImage: "square.and.arrow.up") { export() }
                .disabled(store.owner == nil)
            Button("Importa un backup…", systemImage: "square.and.arrow.down") { importing = true }
                .disabled(store.owner == nil)
                // Le finestre di esportazione, importazione e conferma partono da questa riga.
                .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                              document: exportDocument, contentType: .json,
                              defaultFilename: TimetableBackupDocument.defaultFilename) { outcome in
                    switch outcome {
                    case .success:
                        result = ("Backup esportato", "Potrai importarlo da qui in qualsiasi momento, anche su un altro dispositivo.")
                    case let .failure(error):
                        result = ("Esportazione non riuscita", error.localizedDescription)
                    }
                    exportDocument = nil
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { outcome in
                    switch outcome {
                    case let .success(url):
                        read(url)
                    case let .failure(error):
                        result = ("Importazione non riuscita", error.localizedDescription)
                    }
                }
                // Prima conferma: cosa c'è nel backup e cosa verrà sostituito.
                .alert("Importare questo orario?", isPresented: $firstConfirmation, presenting: pendingBackup) { _ in
                    Button("Continua") {
                        Task {
                            // La seconda conferma arriva dopo che la prima si è chiusa.
                            try? await Task.sleep(for: .milliseconds(350))
                            secondConfirmation = true
                        }
                    }
                    Button("Annulla", role: .cancel) { pendingBackup = nil }
                } message: { backup in
                    Text(firstMessage(backup))
                }
                // Seconda conferma: l'operazione non si può annullare.
                .alert("Sostituire l'orario attuale?", isPresented: $secondConfirmation, presenting: pendingBackup) { backup in
                    Button("Sostituisci", role: .destructive) { restore(backup) }
                    Button("Annulla", role: .cancel) { pendingBackup = nil }
                } message: { _ in
                    Text(store.timetable.isEmpty
                         ? "Colori, palette e impostazioni dell'orario di questo account verranno sostituiti da quelli del backup."
                         : "L'orario attuale, con le sue note, i file, le verifiche segnate, i colori e le palette salvati, verrà eliminato definitivamente e non potrà essere recuperato. Se vuoi conservarlo, annulla ed esportane prima un backup.")
                }
                .alert(result?.title ?? "", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(result?.message ?? "")
                }
            Button("Elimina l'orario", systemImage: "trash", role: .destructive) { confirmingDeleteAll = true }
                .foregroundStyle(Theme.poor)
                .disabled(store.timetable.isEmpty)
                .confirmationDialog("Eliminare l'orario?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
                    Button("Elimina l'orario", role: .destructive) { store.deleteAll() }
                } message: {
                    Text("Verranno eliminati tutti gli eventi con note, file e verifiche segnate. Colori e palette salvati restano.")
                }
        } header: {
            Text("Backup dell'orario")
        } footer: {
            Text("L'orario è salvato solo su questo dispositivo, separato per ogni account. Il backup contiene eventi, colori, palette, note, verifiche segnate e file allegati; importandolo sostituisce l'orario attuale.")
        }
        .listRowBackground(Theme.surface)

        Section {
            Toggle(isOn: .constant(false)) {
                HStack(spacing: 8) {
                    Label("Sincronizza con iCloud", systemImage: "icloud")
                    Pill(text: "Work in progress", short: "WIP", color: Theme.fair)
                }
            }
            .disabled(true)
        } header: {
            Text("iCloud")
        } footer: {
            Text("Work in progress: la sincronizzazione dell'orario tra i tuoi dispositivi con iCloud non è ancora disponibile. Nel frattempo puoi spostare l'orario con un backup.")
        }
        .listRowBackground(Theme.surface)
    }

    private func export() {
        do {
            exportDocument = TimetableBackupDocument(data: try store.makeBackup())
        } catch {
            result = ("Esportazione non riuscita", error.localizedDescription)
        }
    }

    private func read(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            pendingBackup = try TimetableStore.readBackup(data)
            firstConfirmation = true
        } catch {
            result = ("Importazione non riuscita", error.localizedDescription)
        }
    }

    private func firstMessage(_ backup: TimetableBackup) -> String {
        let events = backup.timetable.entries.count
        let files = backup.files.count
        let current = store.timetable.entries.count
        var text = "Il backup del \(backup.exportedAt.it("dMMMMyyyy")) contiene \(events == 1 ? "1 evento" : "\(events) eventi")"
        if files > 0 { text += " e \(files == 1 ? "1 file" : "\(files) file")" }
        text += ". "
        text += current > 0
            ? "Il tuo orario attuale (\(current == 1 ? "1 evento" : "\(current) eventi")) verrà sostituito."
            : "Il tuo orario attuale è vuoto."
        return text
    }

    private func restore(_ backup: TimetableBackup) {
        let outcome: (title: String, message: String)
        do {
            try store.restore(backup)
            let events = store.timetable.entries.count
            outcome = ("Orario importato", "Ora l'orario contiene \(events == 1 ? "1 evento" : "\(events) eventi").")
        } catch {
            outcome = ("Importazione non riuscita", error.localizedDescription)
        }
        pendingBackup = nil
        Task {
            // L'esito compare dopo che la conferma si è chiusa.
            try? await Task.sleep(for: .milliseconds(350))
            result = outcome
        }
    }
}
