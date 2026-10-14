import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct TimetableDetailRequest: Identifiable {
    let id = UUID()
    let entryID: UUID
    let day: Date
}

/// Informazioni su un evento in un certo giorno: verifiche (da Classeviva o segnate a mano),
/// note e file, sia per quel giorno sia per ogni settimana.
struct TimetableEntryDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: TimetableDetailRequest
    var onEdit: (TimetableEntry) -> Void = { _ in }

    /// L'evento com'era all'apertura: se cambiano note, file o verifica ricorrenti si propone
    /// di applicare le modifiche agli altri eventi con lo stesso nome.
    @State private var original: TimetableEntry?
    @State private var dayNote = ""
    @State private var weeklyNote = ""
    /// Dove allegare il file scelto: resta impostato anche dopo che il selettore si è chiuso
    /// (si chiude prima di consegnare i file).
    @State private var importScope: TimetableStore.Scope?
    @State private var showingFileImporter = false
    @State private var photoScope: TimetableStore.Scope?
    @State private var showingPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var previewURL: URL?
    @State private var errorMessage: String?
    @State private var askingPropagation = false

    private var store: TimetableStore { model.timetable }
    private var entry: TimetableEntry? { store.entry(id: request.entryID) }
    private var day: Date { request.day }

    var body: some View {
        NavigationStack {
            Group {
                if let entry {
                    content(entry)
                } else {
                    ContentUnavailableView("Evento eliminato", systemImage: "calendar.badge.minus")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .themedBackground()
            .navigationTitle(entry?.displayTitle ?? "Evento")
            .inlineTitleDisplay()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine", systemImage: "checkmark") { finish() }
                }
                if let entry, !isDraft {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Modifica", systemImage: "pencil") {
                            dismiss()
                            onEdit(entry)
                        }
                    }
                }
            }
        }
        .sheetFrame(width: 520, height: 660)
        .interactiveDismissDisabled(hasRecurringChanges && !sameName.isEmpty)
        .onAppear {
            guard original == nil, let entry else { return }
            original = entry
            dayNote = store.occurrence(entry.id, on: day).note
            weeklyNote = entry.note
        }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item],
                      allowsMultipleSelection: true) { result in
            guard let scope = importScope, let entry else { return }
            switch result {
            case let .success(urls):
                for url in urls {
                    do {
                        try store.attach(fileAt: url, to: entry, scope: scope)
                    } catch {
                        errorMessage = "Impossibile allegare «\(url.lastPathComponent)»: \(error.localizedDescription)"
                    }
                }
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item, let scope = photoScope, let entry else { return }
            Task {
                defer { photoItem = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return }
                    let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                    let name = "Foto \(Date().it("dMMMyyyy")) \(Date().it("HHmmss")).\(ext)"
                        .replacingOccurrences(of: ":", with: ".")
                    try store.attach(data: data, name: name, to: entry, scope: scope)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .quickLookPreview($previewURL)
        .alert("Errore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Applicare le modifiche anche agli altri eventi «\(entry?.displayTitle ?? "")»?",
                            isPresented: $askingPropagation, titleVisibility: .visible) {
            Button("Applica a tutti (\(sameName.count + 1))") {
                propagateRecurringChanges()
                dismiss()
            }
            Button("Solo a questo evento") { dismiss() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Nota, file e verifica di ogni settimana verranno aggiornati in tutti gli eventi con lo stesso nome. Le modifiche dei singoli giorni restano solo a questo evento.")
        }
    }

    private var isDraft: Bool { store.isDraftEntry(request.entryID) }

    private var sameName: [TimetableEntry] {
        guard let entry, !isDraft else { return [] }
        return store.sameNameEntries(as: entry)
    }

    private var hasRecurringChanges: Bool {
        guard let original, let entry else { return false }
        return original.note != entry.note || original.attachments != entry.attachments
            || original.isWeeklyTest != entry.isWeeklyTest
    }

    private func finish() {
        if hasRecurringChanges && !sameName.isEmpty {
            askingPropagation = true
        } else {
            dismiss()
        }
    }

    /// Riporta sugli eventi con lo stesso nome le modifiche ricorrenti fatte qui.
    private func propagateRecurringChanges() {
        guard let original, let entry else { return }
        if original.note != entry.note { store.setNote(entry.note, for: entry, scope: .allSameName) }
        if original.isWeeklyTest != entry.isWeeklyTest { store.setTest(entry.isWeeklyTest, for: entry, scope: .allSameName) }
        let added = entry.attachments.filter { new in !original.attachments.contains { $0.id == new.id } }
        let removed = original.attachments.filter { old in !entry.attachments.contains { $0.id == old.id } }
        for other in sameName {
            var updated = other
            updated.attachments.removeAll { attachment in removed.contains { $0.id == attachment.id } }
            updated.attachments += added.filter { attachment in !updated.attachments.contains { $0.id == attachment.id } }
            if updated.attachments != other.attachments { store.save(updated) }
        }
    }

    // MARK: Contenuto

    private func content(_ entry: TimetableEntry) -> some View {
        let dayContent = TimetableDayContent(day: day, model: model)
        let tint = Theme.timetableColor(entry, store: store)
        return Form {
            Section {
                header(entry, tint: tint)
            }
            .listRowBackground(Color.clear)

            if isDraft {
                Section {
                    Label("Questo evento fa parte della bozza generata dalle lezioni registrate. Applica la bozza per modificarlo o aggiungere note e file.",
                          systemImage: "wand.and.stars")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
                .listRowBackground(Theme.surface)
            } else {
                if !entry.isBreak {
                    testSection(entry, content: dayContent)
                }
                daySection(entry)
                weeklySection(entry)
            }
        }
        .formStyle(.grouped)
        .themedList()
    }

    private func header(_ entry: TimetableEntry, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tint)
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.displayTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("\(day.longDay) · \(entry.timeRange)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.ink)
                Text("Ogni \(Weekday.name(entry.weekday).lowercased()) · \(TimeOfDay.duration(entry.duration))"
                     + (entry.isBreak ? " · Intervallo" : ""))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
                let details = [entry.teacher, entry.room.isEmpty ? "" : "Aula \(entry.room)"].filter { !$0.isEmpty }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryInk)
                }
                if !sameName.isEmpty {
                    Text(sameName.count == 1 ? "C'è un altro evento «\(entry.displayTitle)» nell'orario."
                         : "Ci sono altri \(sameName.count) eventi «\(entry.displayTitle)» nell'orario.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .modifier(EntryFill(tint: tint, isDraft: isDraft))
        .clipShape(.rect(cornerRadius: Theme.corner, style: .continuous))
        .listRowInsets(EdgeInsets())
    }

    private func testSection(_ entry: TimetableEntry, content: TimetableDayContent) -> some View {
        let registerTests = content.registerTests[entry.id] ?? []
        let hiddenTests = content.hiddenTests[entry.id] ?? []
        let dayOverride = store.occurrence(entry.id, on: day).isTest
        return Section {
            ForEach(registerTests) { test in
                RegisterTestRow(test: test, isHidden: false)
            }
            ForEach(hiddenTests) { test in
                RegisterTestRow(test: test, isHidden: true)
            }
            Toggle(isOn: Binding(get: { store.isManualTest(entry, on: day) },
                                 set: { store.setTest($0, for: entry, scope: .day(day)) })) {
                Label("Verifica \(day.isToday ? "oggi" : (day.isTomorrow ? "domani" : "il \(day.it("dMMMM"))"))",
                      systemImage: "pencil.and.list.clipboard")
            }
            Toggle(isOn: Binding(get: { entry.isWeeklyTest },
                                 set: { store.setTest($0, for: entry, scope: .everyWeek) })) {
                Label("Verifica ogni \(Weekday.name(entry.weekday).lowercased())", systemImage: "repeat")
            }
        } header: {
            Text("Verifiche")
        } footer: {
            Text(testFooter(registerTests: registerTests, hiddenTests: hiddenTests, dayOverride: dayOverride, entry: entry))
        }
        .listRowBackground(Theme.surface)
    }

    private func testFooter(registerTests: [AgendaEvent], hiddenTests: [AgendaEvent], dayOverride: Bool?,
                            entry: TimetableEntry) -> String {
        var parts: [String] = []
        if !registerTests.isEmpty {
            parts.append("Le verifiche segnate dai docenti su Classeviva compaiono da sole. Se sono sbagliate puoi nasconderle dall'orario.")
        } else if !hiddenTests.isEmpty {
            parts.append("Le verifiche di Classeviva di questo giorno sono nascoste (le trovi anche in Verifiche nascoste, nel menu dell'orario).")
        } else {
            parts.append("Le verifiche segnate dai docenti su Classeviva compaiono da sole; qui puoi segnarne altre a mano.")
        }
        if entry.isWeeklyTest && dayOverride == false {
            parts.append("Solo per questo giorno hai tolto la verifica settimanale.")
        }
        return parts.joined(separator: " ")
    }

    private func daySection(_ entry: TimetableEntry) -> some View {
        let info = store.occurrence(entry.id, on: day)
        return Section {
            TextField("Nota solo per questo giorno", text: $dayNote, axis: .vertical)
                .lineLimit(2...8)
                .onChange(of: dayNote) { _, note in
                    store.setNote(note, for: entry, scope: .day(day))
                }
            attachmentRows(info.attachments, entry: entry, scope: .day(day))
            addFileMenu(scope: .day(day))
        } header: {
            Text(day.longDay)
        }
        .listRowBackground(Theme.surface)
    }

    private func weeklySection(_ entry: TimetableEntry) -> some View {
        Section {
            TextField("Nota per ogni settimana", text: $weeklyNote, axis: .vertical)
                .lineLimit(2...8)
                .onChange(of: weeklyNote) { _, note in
                    store.setNote(note, for: entry, scope: .everyWeek)
                }
            attachmentRows(entry.attachments, entry: entry, scope: .everyWeek)
            addFileMenu(scope: .everyWeek)
        } header: {
            Text("Ogni \(Weekday.name(entry.weekday).lowercased())")
        } footer: {
            if !sameName.isEmpty {
                Text("Premendo Fine potrai applicare nota, file e verifica di ogni settimana anche agli altri eventi «\(entry.displayTitle)».")
            }
        }
        .listRowBackground(Theme.surface)
    }

    @ViewBuilder
    private func attachmentRows(_ attachments: [TimetableAttachment], entry: TimetableEntry,
                                scope: TimetableStore.Scope) -> some View {
        ForEach(attachments) { attachment in
            Button {
                previewURL = store.shareableURL(for: attachment)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: Self.symbol(for: attachment.name))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attachment.name)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    Spacer(minLength: 4)
                    if let url = store.shareableURL(for: attachment) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Rimuovi", systemImage: "trash", role: .destructive) {
                    withAnimation { store.removeAttachment(attachment, from: entry, scope: scope) }
                }
            }
            .swipeActions {
                Button("Rimuovi", systemImage: "trash", role: .destructive) {
                    withAnimation { store.removeAttachment(attachment, from: entry, scope: scope) }
                }
            }
        }
    }

    private func addFileMenu(scope: TimetableStore.Scope) -> some View {
        Menu {
            Button("Scegli un file…", systemImage: "doc") {
                importScope = scope
                showingFileImporter = true
            }
            Button("Scegli una foto…", systemImage: "photo") {
                photoScope = scope
                showingPhotoPicker = true
            }
        } label: {
            Label("Allega un file", systemImage: "paperclip")
        }
    }

    static func symbol(for name: String) -> String {
        guard let type = UTType(filenameExtension: (name as NSString).pathExtension) else { return "doc" }
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .audiovisualContent) { return "play.rectangle" }
        if type.conforms(to: .presentation) { return "rectangle.on.rectangle" }
        if type.conforms(to: .spreadsheet) { return "tablecells" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
}
