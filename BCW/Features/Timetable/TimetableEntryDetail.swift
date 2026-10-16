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
                    EmptyState("Evento eliminato", icon: "calendarMinus")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .sheetChrome(entry?.displayTitle ?? "Evento", leading: .close { finish() }, trailing: trailingActions)
        }
        .m3Sheet()
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
        .m3Dialog("Errore", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
                  message: errorMessage) {
            [.cancel("OK")]
        }
        .m3Dialog("Applicare le modifiche anche agli altri eventi «\(entry?.displayTitle ?? "")»?",
                  isPresented: $askingPropagation,
                  message: "Nota, file e verifica di ogni settimana verranno aggiornati in tutti gli eventi con lo stesso nome. Le modifiche dei singoli giorni restano solo a questo evento.",
                  stacked: true) {
            [DialogAction(title: "Applica a tutti (\(sameName.count + 1))", style: .strong) {
                propagateRecurringChanges()
                dismiss()
            },
             DialogAction(title: "Solo a questo evento") { dismiss() },
             .cancel()]
        }
    }

    private var trailingActions: [SheetAction] {
        var actions: [SheetAction] = []
        if let entry, !isDraft {
            actions.append(SheetAction(title: "Modifica", icon: "edit") {
                dismiss()
                onEdit(entry)
            })
        }
        actions.append(.confirm("Fine") { finish() })
        return actions
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
        return ScrollView {
            VStack(spacing: 16) {
                header(entry, tint: tint)

                if isDraft {
                    HStack(alignment: .top, spacing: 12) {
                        Icon("wand")
                        Text("Questo evento fa parte della bozza generata dalle lezioni registrate. Applica la bozza per modificarlo o aggiungere note e file.")
                            .font(.m3(14))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.onSecondaryContainer)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.secondaryContainer, in: .rect(cornerRadius: Theme.radii.li, style: .continuous))
                } else {
                    if !entry.isBreak {
                        testSection(entry, content: dayContent)
                    }
                    daySection(entry)
                    weeklySection(entry)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func header(_ entry: TimetableEntry, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tint)
                .frame(width: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.m3(24, weight: 500, rounded: true))
                    .foregroundStyle(Theme.ink)
                Text("\(day.longDay) · \(entry.timeRange)")
                    .font(.m3(14).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                Text("Ogni \(Weekday.name(entry.weekday).lowercased()) · \(TimeOfDay.duration(entry.duration))"
                     + (entry.isBreak ? " · Intervallo" : ""))
                    .font(.m3(14))
                    .foregroundStyle(Theme.secondaryInk)
                let details = [entry.teacher, entry.room.isEmpty ? "" : "Aula \(entry.room)"].filter { !$0.isEmpty }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.m3(14))
                        .foregroundStyle(Theme.secondaryInk)
                }
                if !sameName.isEmpty {
                    Text(sameName.count == 1 ? "C'è un altro evento «\(entry.displayTitle)» nell'orario."
                         : "Ci sono altri \(sameName.count) eventi «\(entry.displayTitle)» nell'orario.")
                        .font(.m3(12))
                        .foregroundStyle(Theme.secondaryInk)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .background(tint.mix(Theme.surfaceContainerHigh, 0.2), in: .rect(cornerRadius: Theme.radii.li, style: .continuous))
    }

    private func testSection(_ entry: TimetableEntry, content: TimetableDayContent) -> some View {
        let registerTests = content.registerTests[entry.id] ?? []
        let hiddenTests = content.hiddenTests[entry.id] ?? []
        let dayOverride = store.occurrence(entry.id, on: day).isTest
        return ListGroup("Verifiche", footer: testFooter(registerTests: registerTests, hiddenTests: hiddenTests,
                                                         dayOverride: dayOverride, entry: entry)) {
            ForEach(registerTests) { test in
                RegisterTestRow(test: test, isHidden: false)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            ForEach(hiddenTests) { test in
                RegisterTestRow(test: test, isHidden: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            ToggleRow("Verifica \(day.isToday ? "oggi" : (day.isTomorrow ? "domani" : "il \(day.it("dMMMM"))"))", icon: "test",
                      isOn: Binding(get: { store.isManualTest(entry, on: day) },
                                    set: { store.setTest($0, for: entry, scope: .day(day)) }))
            ToggleRow("Verifica ogni \(Weekday.name(entry.weekday).lowercased())", icon: "repeat",
                      isOn: Binding(get: { entry.isWeeklyTest },
                                    set: { store.setTest($0, for: entry, scope: .everyWeek) }))
        }
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
        return ListGroup(day.longDay) {
            NoteField(text: $dayNote, prompt: "Nota solo per questo giorno")
                .onChange(of: dayNote) { _, note in
                    store.setNote(note, for: entry, scope: .day(day))
                }
            attachmentRows(info.attachments, entry: entry, scope: .day(day))
            addFileMenu(scope: .day(day))
        }
    }

    private func weeklySection(_ entry: TimetableEntry) -> some View {
        ListGroup("Ogni \(Weekday.name(entry.weekday).lowercased())",
                  footer: sameName.isEmpty ? nil
                  : "Premendo Fine potrai applicare nota, file e verifica di ogni settimana anche agli altri eventi «\(entry.displayTitle)».") {
            NoteField(text: $weeklyNote, prompt: "Nota per ogni settimana")
                .onChange(of: weeklyNote) { _, note in
                    store.setNote(note, for: entry, scope: .everyWeek)
                }
            attachmentRows(entry.attachments, entry: entry, scope: .everyWeek)
            addFileMenu(scope: .everyWeek)
        }
    }

    @ViewBuilder
    private func attachmentRows(_ attachments: [TimetableAttachment], entry: TimetableEntry,
                                scope: TimetableStore.Scope) -> some View {
        ForEach(attachments) { attachment in
            HStack(spacing: 4) {
                Button {
                    previewURL = store.shareableURL(for: attachment)
                } label: {
                    ListRow(attachment.name,
                            subtitle: ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file),
                            leading: { FormIcon(Self.icon(for: attachment.name)) }, trailing: { EmptyView() })
                }
                .buttonStyle(.listRow)
                if let url = store.shareableURL(for: attachment) {
                    ShareLink(item: url) {
                        Icon("share")
                    }
                    .buttonStyle(.m3Icon())
                    .help("Condividi")
                }
                IconButton("trash", label: "Rimuovi", kind: .danger) {
                    withAnimation(Motion.spatial) { store.removeAttachment(attachment, from: entry, scope: scope) }
                }
                .padding(.trailing, 8)
            }
        }
    }

    private func addFileMenu(scope: TimetableStore.Scope) -> some View {
        AppMenu(alignment: .leading) {
            MenuItem("Scegli un file…", icon: "file") {
                importScope = scope
                showingFileImporter = true
            }
            MenuItem("Scegli una foto…", icon: "photo") {
                photoScope = scope
                showingPhotoPicker = true
            }
        } label: {
            ListRow("Allega un file", titleColor: Theme.primary, leading: {
                FormIcon("paperclip", color: Theme.primary)
            }, trailing: { EmptyView() })
        }
        .buttonStyle(.listRow)
        .menuStyle(.button)
        .menuIndicator(.hidden)
    }

    /// Icona di Material Symbols per il tipo di file.
    static func icon(for name: String) -> String {
        guard let type = UTType(filenameExtension: (name as NSString).pathExtension) else { return "file" }
        if type.conforms(to: .image) { return "image" }
        if type.conforms(to: .pdf) { return "fileText" }
        if type.conforms(to: .audiovisualContent) { return "film" }
        if type.conforms(to: .presentation) { return "presentation" }
        if type.conforms(to: .spreadsheet) { return "table" }
        if type.conforms(to: .text) { return "alignLeft" }
        return "file"
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

/// Campo per una nota, dentro una voce di una lista (trasparente, pieno quando è attivo).
struct NoteField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField(prompt, text: $text, axis: .vertical)
            .lineLimit(2...8)
            .textFieldStyle(.plain)
            .font(.m3(16))
            .foregroundStyle(Theme.ink)
            .focused($focused)
            .padding(16)
            .frame(minHeight: 64, alignment: .topLeading)
            .background(focused ? Theme.surfaceContainerHighest : .clear,
                        in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
            .padding(8)
            .animation(Motion.effects, value: focused)
    }
}
