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
            ScrollView {
                VStack(spacing: 20) {
                    ListGroup("Ore di lezione", footer: hoursFooter) {
                        ListRow("Inizio della prima ora") {
                            TimeField(minutes: $settings.firstHourStart)
                        }
                        StepperRow(title: "Durata di un'ora", value: $settings.hourLength, range: 30...120, step: 5) { "\($0) min" }
                        SelectRow("Lezioni da esaminare", selection: $settings.weeks,
                                  options: [(2, "Ultime 2 settimane", nil), (4, "Ultime 4 settimane", nil), (6, "Ultime 6 settimane", nil),
                                            (10, "Ultime 10 settimane", nil), (0, "Tutto l'anno", nil)])
                    }

                    ListGroup("Intervalli", footer: "Facoltativi: compaiono sopra le lezioni nei giorni in cui c'è scuola a quell'ora, senza cambiarne la durata. Per toglierne uno usa il pulsante rosso accanto.") {
                        ForEach($settings.breaks) { $rule in
                            breakRow($rule)
                        }
                        ButtonRow("Aggiungi intervallo", icon: "coffee") {
                            let after = settings.breaks.last.map { $0.start + 120 }
                                ?? (settings.firstHourStart + settings.hourLength * 3 - 10)
                            withAnimation(Motion.spatial) { settings.breaks.append(.init(start: min(after, 23 * 60), duration: 10)) }
                        }
                        if !settings.breaks.isEmpty {
                            ButtonRow("Rimuovi gli intervalli", icon: "trash", destructive: true) {
                                withAnimation(Motion.spatial) { settings.breaks = [] }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            Task { await generate() }
                        } label: {
                            Label {
                                Text("Crea l'anteprima")
                            } icon: {
                                if isGenerating { InlineProgress(tint: Theme.onPrimary) } else { Icon("wand") }
                            }
                        }
                        .buttonStyle(.m3(.filled, size: .m, wide: true))
                        .disabled(isGenerating)
                        ListFooter("BCW guarda in quale ora della giornata si è svolta ogni materia, settimana per settimana, e tiene quelle che si ripetono (le settimane recenti contano di più, supplenze e recuperi isolati vengono ignorati). Vedrai l'orario in anteprima, con i bordi tratteggiati, prima di applicarlo.")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .sheetChrome("Genera l'orario", leading: .close { dismiss() })
            .m3Dialog("Impossibile creare l'orario", isPresented: Binding(get: { errorMessage != nil },
                                                                        set: { if !$0 { errorMessage = nil } }),
                      message: errorMessage) {
                [.cancel("OK")]
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
        .m3Sheet()
    }

    private var hoursFooter: String {
        let aligned = settings.firstHourStart % 30 == 0 && (settings.hourLength == 30 || settings.hourLength == 60)
        if store.alignment == .automatic && !aligned {
            return "L'orario usa l'allineamento automatico: con questi orari le lezioni verranno spostate all'ora o alla mezz'ora più vicina. Per tenere gli orari esatti passa all'allineamento libero in Modifica orario."
        }
        return "Classeviva registra solo in quale ora della giornata si svolge una lezione: l'orario si ricava da qui."
    }

    /// Un intervallo: inizio, durata e il pulsante per toglierlo.
    private func breakRow(_ rule: Binding<GenerationSettings.BreakRule>) -> some View {
        let id = rule.wrappedValue.id
        let number = (settings.breaks.firstIndex { $0.id == id } ?? 0) + 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                FormIcon("coffee")
                Text("Intervallo \(number)")
                    .font(.m3(16, weight: 500))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                IconButton("minusCircle", label: "Rimuovi l'intervallo", kind: .danger, size: 32) {
                    withAnimation(Motion.spatial) { settings.breaks.removeAll { $0.id == id } }
                }
                .help("Rimuovi questo intervallo")
            }
            HStack(spacing: 12) {
                TimeField(minutes: rule.start)
                Spacer(minLength: 0)
                M3Stepper(value: rule.duration, range: 5...60, step: 5) { "\($0) min" }
            }
            .padding(.leading, 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        withAnimation(Motion.spatial) {
            store.draft = TimetableDraft(entries: result.entries, settings: settings, analyzedDays: result.analyzedDays,
                                         from: range.from, to: range.to)
        }
        dismiss()
    }
}

/// Banner dell'anteprima: applica o scarta l'orario generato (bordo tratteggiato, come la bozza).
struct TimetableDraftBanner: View {
    @Environment(AppModel.self) private var model
    let onSettings: () -> Void
    @State private var confirmingApply = false

    var body: some View {
        if let draft = model.timetable.draft {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Icon("wand")
                        .foregroundStyle(Theme.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Anteprima dell'orario generato")
                            .font(.m3(15, weight: 650))
                            .foregroundStyle(Theme.ink)
                        Text("\(lessonCount(draft)) lezioni ricavate da \(draft.analyzedDays) giorni di registro (\(draft.from.shortDay) – \(draft.to.shortDay)). Controllale prima di applicarle.")
                            .font(.m3(12))
                            .foregroundStyle(Theme.secondaryInk)
                            .lineLimit(4)
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        if model.timetable.timetable.isEmpty {
                            withAnimation(Motion.spatial) { model.timetable.applyDraft(replacing: true) }
                        } else {
                            confirmingApply = true
                        }
                    } label: {
                        Label { Text("Applica") } icon: { Icon("check") }
                    }
                    .buttonStyle(.m3(.filled, size: .xs))
                    Button {
                        withAnimation(Motion.spatial) { model.timetable.draft = nil }
                    } label: {
                        Label { Text("Scarta") } icon: { Icon("x") }
                    }
                    .buttonStyle(.m3(.tonal, size: .xs))
                    Spacer(minLength: 0)
                    IconButton("tune", label: "Cambia le impostazioni e rigenera", kind: .tonal, size: 32, action: onSettings)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.secondaryContainer.mix(Theme.surfaceContainerLow, 0.6),
                        in: .rect(cornerRadius: Theme.radii.li, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radii.li, style: .continuous)
                    .strokeBorder(Theme.primary.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
            .m3Dialog("Hai già un orario", isPresented: $confirmingApply,
                      message: "Sostituendolo, eventi, note, file e verifiche segnate a mano dell'orario attuale verranno eliminati.",
                      stacked: true) {
                [DialogAction(title: "Sostituisci l'orario attuale", style: .destructive) {
                    withAnimation(Motion.spatial) { model.timetable.applyDraft(replacing: true) }
                },
                 DialogAction(title: "Aggiungi solo dove è libero") {
                    withAnimation(Motion.spatial) { model.timetable.applyDraft(replacing: false) }
                },
                 .cancel()]
            }
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
        ListGroup("Vista e allineamento", footer: "Con \"Mostra le verifiche\" la vista Lista segna le verifiche di Classeviva e quelle segnate a mano; si vedono sempre nel dettaglio dell'evento e nella vista Giorno. Quelle nascoste, e le regole per nasconderle in automatico, sono in Verifiche nascoste (menu dell'orario). L'allineamento vale per tutto l'orario e per la modalità di modifica (menu dell'orario › Modifica orario). Automatico: gli eventi iniziano all'ora o alla mezz'ora e durano 30 minuti o un'ora; passando all'automatico gli eventi non allineati vengono allineati, dopo una conferma. Libero: qualsiasi orario e durata. Gli intervalli si posizionano sempre liberamente.") {
            TimetableAlignmentPicker()
            ToggleRow("Mostra le verifiche nella lista", icon: "test", isOn: Bindable(model.preferences).timetableShowsTests)
        }

        ListGroup("Backup dell'orario", footer: "L'orario è salvato solo su questo dispositivo, separato per ogni account. Il backup contiene eventi, colori, palette, note, verifiche segnate e file allegati; importandolo sostituisce l'orario attuale. È compatibile con la versione web di BCW.") {
            ButtonRow("Esporta un backup dell'orario", icon: "upload") { export() }
                .disabled(store.owner == nil)
            ButtonRow("Importa un backup…", icon: "download") { importing = true }
                .disabled(store.owner == nil)
            ButtonRow("Elimina l'orario", icon: "trash", destructive: true) { confirmingDeleteAll = true }
                .disabled(store.timetable.isEmpty)
        }
        // Le finestre di esportazione e importazione.
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
        .m3Dialog("Importare questo orario?", isPresented: $firstConfirmation,
                  message: pendingBackup.map(firstMessage)) {
            [DialogAction.cancel { pendingBackup = nil },
             DialogAction(title: "Continua", style: .strong) {
                Task {
                    // La seconda conferma arriva dopo che la prima si è chiusa.
                    try? await Task.sleep(for: .milliseconds(350))
                    secondConfirmation = true
                }
            }]
        }
        // Seconda conferma: l'operazione non si può annullare.
        .m3Dialog("Sostituire l'orario attuale?", isPresented: $secondConfirmation,
                  message: store.timetable.isEmpty
                  ? "Colori, palette e impostazioni dell'orario di questo account verranno sostituiti da quelli del backup."
                  : "L'orario attuale, con le sue note, i file, le verifiche segnate, i colori e le palette salvati, verrà eliminato definitivamente e non potrà essere recuperato. Se vuoi conservarlo, annulla ed esportane prima un backup.") {
            [DialogAction.cancel { pendingBackup = nil },
             DialogAction(title: "Sostituisci", style: .destructive) {
                if let backup = pendingBackup { restore(backup) }
            }]
        }
        .m3Dialog(result?.title ?? "", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } }),
                  message: result?.message) {
            [.cancel("OK")]
        }
        .m3Dialog("Eliminare l'orario?", isPresented: $confirmingDeleteAll,
                  message: "Verranno eliminati tutti gli eventi con note, file e verifiche segnate. Colori e palette salvati restano.") {
            [.cancel(), DialogAction(title: "Elimina l'orario", style: .destructive) { store.deleteAll() }]
        }

        ListGroup("iCloud", footer: "Work in progress: la sincronizzazione dell'orario tra i tuoi dispositivi con iCloud non è ancora disponibile. Nel frattempo puoi spostare l'orario con un backup.") {
            Toggle(isOn: .constant(false)) {
                HStack(spacing: 16) {
                    FormIcon("cloud")
                    Text("Sincronizza con iCloud")
                        .font(.m3(16, weight: 500))
                        .foregroundStyle(Theme.ink)
                    Pill(text: "Work in progress", short: "WIP", color: Theme.fair, small: true)
                }
            }
            .toggleStyle(.m3)
            .disabled(true)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
        }
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
