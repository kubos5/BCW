import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Orario dell'account attivo: lo carica e lo salva in Application Support (una cartella per
/// account, con i file allegati), applica le modifiche e gestisce backup e bozze generate.
@Observable
final class TimetableStore {
    private(set) var timetable = Timetable()
    /// Proprietario dei dati caricati (id dell'account o "demo"), `nil` senza sessione.
    private(set) var owner: String?
    /// Bozza generata dalle lezioni registrate: finché c'è, l'orario la mostra in anteprima.
    var draft: TimetableDraft?
    /// Ultimo errore di salvataggio (mostrato nelle impostazioni dell'orario).
    private(set) var saveError: String?

    /// Indice degli eventi per giorno della settimana, ricostruito quando cambiano gli eventi.
    @ObservationIgnored private var byWeekday: [Int: [TimetableEntry]] = [:]

    // MARK: Caricamento e salvataggio

    nonisolated static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Timetable", isDirectory: true)
    }

    nonisolated static func directory(owner: String) -> URL {
        rootDirectory.appendingPathComponent(safeName(owner), isDirectory: true)
    }

    nonisolated private static func safeName(_ owner: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let name = String(owner.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return name.isEmpty ? "default" : name
    }

    private var directory: URL? { owner.map(Self.directory(owner:)) }
    private var dataURL: URL? { directory?.appendingPathComponent("timetable.json") }
    var filesDirectory: URL? { directory?.appendingPathComponent("Files", isDirectory: true) }

    /// Carica l'orario di un account (o lo svuota con `nil`).
    func load(owner: String?) {
        self.owner = owner
        draft = nil
        saveError = nil
        guard let url = dataURL, let data = try? Data(contentsOf: url),
              let stored = try? TimetableBackup.decoder().decode(Timetable.self, from: data) else {
            timetable = Timetable()
            rebuildIndex()
            return
        }
        timetable = stored
        rebuildIndex()
        removeUnreferencedFiles()
    }

    /// Elimina tutti i dati dell'orario di un proprietario (usato per la demo).
    static func removeData(owner: String) {
        try? FileManager.default.removeItem(at: directory(owner: owner))
    }

    private func save() {
        guard let directory, let url = dataURL else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try TimetableBackup.encoder().encode(timetable)
            try data.write(to: url, options: .atomic)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// Applica una modifica all'orario e la salva.
    private func mutate(_ change: (inout Timetable) -> Void) {
        let oldEntries = timetable.entries
        change(&timetable)
        if timetable.entries != oldEntries { rebuildIndex() }
        save()
    }

    private func rebuildIndex() {
        byWeekday = Dictionary(grouping: timetable.entries, by: \.weekday)
            .mapValues { $0.sorted(by: Self.order) }
    }

    nonisolated static func order(_ a: TimetableEntry, _ b: TimetableEntry) -> Bool {
        (a.start, a.end, a.displayTitle) < (b.start, b.end, b.displayTitle)
    }

    // MARK: Lettura

    var alignment: TimetableAlignment { timetable.alignment }

    /// Eventi di un giorno della settimana (quelli della bozza, se c'è un'anteprima).
    func entries(weekday: Int, includingDraft: Bool = true) -> [TimetableEntry] {
        if includingDraft, let draft { return draft.entries(weekday: weekday) }
        _ = timetable.entries  // dipendenza osservata: l'indice non è osservato
        return byWeekday[weekday] ?? []
    }

    func entries(on day: Date) -> [TimetableEntry] {
        entries(weekday: day.timetableWeekday)
    }

    func entry(id: UUID) -> TimetableEntry? {
        timetable.entries.first { $0.id == id } ?? draft?.entries.first { $0.id == id }
    }

    func isDraftEntry(_ id: UUID) -> Bool {
        draft?.entries.contains { $0.id == id } == true && !timetable.entries.contains { $0.id == id }
    }

    func occurrence(_ entryID: UUID, on day: Date) -> OccurrenceInfo {
        timetable.occurrences[OccurrenceInfo.key(entryID, day)] ?? OccurrenceInfo()
    }

    /// Altri eventi con lo stesso nome (in qualsiasi giorno).
    func sameNameEntries(as entry: TimetableEntry) -> [TimetableEntry] {
        let key = entry.matchKey
        guard !key.isEmpty else { return [] }
        return timetable.entries.filter { $0.id != entry.id && $0.kind == entry.kind && $0.matchKey == key }
    }

    /// Verifica segnata a mano per quel giorno (o per ogni settimana).
    func isManualTest(_ entry: TimetableEntry, on day: Date?) -> Bool {
        if let day, let override = occurrence(entry.id, on: day).isTest { return override }
        return entry.isWeeklyTest
    }

    func palette(id: String) -> ColorPalette? {
        ColorPalette.builtIn.first { $0.id == id } ?? timetable.customPalettes.first { $0.id == id }
    }

    var allPalettes: [ColorPalette] { ColorPalette.builtIn + timetable.customPalettes }

    /// Materie conosciute (dai nomi già usati nell'orario), per i suggerimenti.
    var knownTitles: [String] {
        var seen = Set<String>()
        return timetable.entries.filter { !$0.isBreak }.map(\.displayTitle)
            .filter { seen.insert(TimetableEntry.normalized($0)).inserted }
            .sorted()
    }

    // MARK: Modifiche agli eventi

    /// Campi condivisi tra gli eventi dello stesso tipo (non orari, giorno o palette della serie).
    struct SharedFields: Equatable {
        var title: String
        var subjectId: Int?
        var teacher: String
        var room: String
        var color: EntryColor?
        var note: String

        init(_ entry: TimetableEntry) {
            title = entry.title
            subjectId = entry.subjectId
            teacher = entry.teacher
            room = entry.room
            // Il colore di una serie vale solo per quel giorno: non si propaga.
            color = entry.color?.paletteID == nil ? entry.color : nil
            note = entry.note
        }

        static func differences(_ old: TimetableEntry, _ new: TimetableEntry) -> Bool {
            let a = SharedFields(old), b = SharedFields(new)
            return a.title != b.title || a.subjectId != b.subjectId || a.teacher != b.teacher
                || a.room != b.room || a.note != b.note || (old.color != new.color && new.color?.paletteID == nil)
        }
    }

    /// Salva un evento (nuovo o modificato). Con `propagatingFrom` i campi condivisi cambiati
    /// vengono applicati anche agli altri eventi che avevano lo stesso nome.
    func save(_ entry: TimetableEntry, propagatingFrom original: TimetableEntry? = nil) {
        mutate { table in
            if let original {
                let key = original.matchKey
                for index in table.entries.indices
                where table.entries[index].id != entry.id && table.entries[index].kind == original.kind
                    && table.entries[index].matchKey == key {
                    var other = table.entries[index]
                    if original.title != entry.title { other.title = entry.title }
                    if original.subjectId != entry.subjectId { other.subjectId = entry.subjectId }
                    if original.teacher != entry.teacher { other.teacher = entry.teacher }
                    if original.room != entry.room { other.room = entry.room }
                    if original.note != entry.note { other.note = entry.note }
                    if original.color != entry.color, entry.color?.paletteID == nil { other.color = entry.color }
                    table.entries[index] = other
                }
            }
            if let index = table.entries.firstIndex(where: { $0.id == entry.id }) {
                table.entries[index] = entry
            } else {
                table.entries.append(entry)
            }
        }
    }

    func add(_ entries: [TimetableEntry]) {
        mutate { $0.entries.append(contentsOf: entries) }
    }

    func delete(_ ids: Set<UUID>) {
        mutate { table in
            table.entries.removeAll { ids.contains($0.id) }
            table.occurrences = table.occurrences.filter { key, _ in
                !ids.contains { key.hasPrefix($0.uuidString) }
            }
        }
        removeUnreferencedFiles()
    }

    /// Sposta o allunga un evento (trascinandolo nella vista Giorno).
    func move(_ id: UUID, weekday: Int? = nil, start: Int, end: Int) {
        guard let index = timetable.entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = timetable.entries[index]
        let newWeekday = weekday ?? entry.weekday
        guard entry.start != start || entry.end != end || entry.weekday != newWeekday else { return }
        mutate { table in
            table.entries[index].start = start
            table.entries[index].end = end
            table.entries[index].weekday = newWeekday
        }
    }

    func duplicate(_ entry: TimetableEntry, to weekday: Int? = nil) -> TimetableEntry {
        var copy = entry
        copy.id = UUID()
        if let weekday { copy.weekday = weekday } else {
            // Subito dopo l'originale.
            let length = entry.duration
            copy.start = min(entry.end, 24 * 60 - length)
            copy.end = copy.start + length
        }
        // La palette di una serie appartiene alla giornata di origine.
        if copy.color?.paletteID != nil { copy.color = nil }
        add([copy])
        return copy
    }

    /// Eventi che l'allineamento automatico sposterebbe (o dividerebbe).
    var unalignedEntries: [TimetableEntry] {
        timetable.entries.filter { !$0.isAutoAligned }
    }

    /// Cambia l'allineamento di tutto l'orario. Passando all'automatico gli eventi non allineati
    /// vengono allineati davvero (vedi `TimetableEntry.alignedPieces`): va chiesta prima conferma
    /// se `unalignedEntries` non è vuoto.
    func setAlignment(_ alignment: TimetableAlignment) {
        mutate { table in
            table.alignment = alignment
            if alignment == .automatic {
                table.entries = table.entries.flatMap { $0.alignedPieces() }
            }
        }
    }

    func setGeneration(_ settings: GenerationSettings) {
        mutate { $0.generation = settings }
    }

    // MARK: Note, verifiche e file

    /// A chi si applica una modifica fatta dal dettaglio di un evento.
    enum Scope: Hashable {
        /// Solo il giorno indicato.
        case day(Date)
        /// Ogni settimana, solo questo evento.
        case everyWeek
        /// Ogni settimana, questo evento e tutti quelli con lo stesso nome.
        case allSameName
    }

    private func targets(_ entry: TimetableEntry, _ scope: Scope) -> [UUID] {
        scope == .allSameName ? [entry.id] + sameNameEntries(as: entry).map(\.id) : [entry.id]
    }

    private func updateOccurrence(_ entryID: UUID, _ day: Date, in table: inout Timetable,
                                  _ change: (inout OccurrenceInfo) -> Void) {
        let key = OccurrenceInfo.key(entryID, day)
        var info = table.occurrences[key] ?? OccurrenceInfo()
        change(&info)
        table.occurrences[key] = info.isEmpty ? nil : info
    }

    func setNote(_ note: String, for entry: TimetableEntry, scope: Scope) {
        // Calcolati prima: dentro `mutate` l'orario non si può leggere (accesso simultaneo).
        let ids = Set(targets(entry, scope))
        mutate { table in
            switch scope {
            case let .day(day):
                updateOccurrence(entry.id, day, in: &table) { $0.note = note }
            case .everyWeek, .allSameName:
                for index in table.entries.indices where ids.contains(table.entries[index].id) {
                    table.entries[index].note = note
                }
            }
        }
    }

    /// Segna o toglie una verifica manuale.
    func setTest(_ isTest: Bool, for entry: TimetableEntry, scope: Scope) {
        // Calcolati prima: dentro `mutate` l'orario non si può leggere (accesso simultaneo).
        let ids = Set(targets(entry, scope))
        mutate { table in
            switch scope {
            case let .day(day):
                // Se coincide con la ricorrenza non serve un'eccezione per quel giorno.
                let weekly = table.entries.first { $0.id == entry.id }?.isWeeklyTest ?? false
                updateOccurrence(entry.id, day, in: &table) { $0.isTest = isTest == weekly ? nil : isTest }
            case .everyWeek, .allSameName:
                for index in table.entries.indices where ids.contains(table.entries[index].id) {
                    table.entries[index].isWeeklyTest = isTest
                }
                // Le eccezioni dei singoli giorni uguali alla nuova ricorrenza non servono più.
                for (key, info) in table.occurrences where info.isTest == isTest
                    && ids.contains(where: { key.hasPrefix($0.uuidString) }) {
                    var updated = info
                    updated.isTest = nil
                    table.occurrences[key] = updated.isEmpty ? nil : updated
                }
            }
        }
    }

    func setTestHidden(_ hidden: Bool, eventID: Int) {
        mutate { table in
            if hidden { table.hiddenTests.insert(eventID) } else { table.hiddenTests.remove(eventID) }
        }
    }

    func isTestHidden(_ eventID: Int) -> Bool { timetable.hiddenTests.contains(eventID) }

    /// Copia un file nella cartella dell'orario e lo allega.
    func attach(fileAt url: URL, to entry: TimetableEntry, scope: Scope) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        try attach(data: data, name: url.lastPathComponent, to: entry, scope: scope)
    }

    func attach(data: Data, name: String, to entry: TimetableEntry, scope: Scope) throws {
        guard let filesDirectory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        let id = UUID()
        let ext = (name as NSString).pathExtension
        let storedName = ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)"
        try data.write(to: filesDirectory.appendingPathComponent(storedName), options: .atomic)
        let attachment = TimetableAttachment(id: id, name: name, storedName: storedName, size: data.count)
        let ids = Set(targets(entry, scope))
        mutate { table in
            switch scope {
            case let .day(day):
                updateOccurrence(entry.id, day, in: &table) { $0.attachments.append(attachment) }
            case .everyWeek, .allSameName:
                for index in table.entries.indices where ids.contains(table.entries[index].id) {
                    table.entries[index].attachments.append(attachment)
                }
            }
        }
    }

    /// Toglie un allegato (dal giorno o dalla ricorrenza); il file si cancella quando nessuno lo usa più.
    func removeAttachment(_ attachment: TimetableAttachment, from entry: TimetableEntry, scope: Scope) {
        // Calcolati prima: dentro `mutate` l'orario non si può leggere (accesso simultaneo).
        let ids = Set(targets(entry, scope))
        mutate { table in
            switch scope {
            case let .day(day):
                updateOccurrence(entry.id, day, in: &table) { $0.attachments.removeAll { $0.id == attachment.id } }
            case .everyWeek, .allSameName:
                for index in table.entries.indices where ids.contains(table.entries[index].id) {
                    table.entries[index].attachments.removeAll { $0.id == attachment.id }
                }
            }
        }
        removeUnreferencedFiles()
    }

    func url(for attachment: TimetableAttachment) -> URL? {
        filesDirectory?.appendingPathComponent(attachment.storedName)
    }

    /// Copia temporanea con il nome originale, per l'anteprima e la condivisione (il file salvato
    /// ha un nome univoco, che altrimenti comparirebbe come titolo).
    func shareableURL(for attachment: TimetableAttachment) -> URL? {
        guard let source = url(for: attachment) else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("BCWTimetable", isDirectory: true)
            .appendingPathComponent(attachment.id.uuidString, isDirectory: true)
        let name = (attachment.name as NSString).lastPathComponent
        let target = folder.appendingPathComponent(name.isEmpty ? attachment.storedName : name)
        if !FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard (try? FileManager.default.copyItem(at: source, to: target)) != nil else { return source }
        }
        return target
    }

    /// Cancella i file che nessun evento usa più.
    private func removeUnreferencedFiles() {
        guard let filesDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: filesDirectory.path) else { return }
        let referenced = timetable.referencedFiles
        for name in names where !referenced.contains(name) {
            try? FileManager.default.removeItem(at: filesDirectory.appendingPathComponent(name))
        }
    }

    // MARK: Colori e palette

    func saveCustomColor(_ hex: Int) {
        guard !timetable.customColors.contains(hex) else { return }
        mutate { $0.customColors.append(hex) }
    }

    func deleteCustomColor(_ hex: Int) {
        mutate { $0.customColors.removeAll { $0 == hex } }
    }

    func savePalette(_ palette: ColorPalette) {
        mutate { table in
            if let index = table.customPalettes.firstIndex(where: { $0.id == palette.id }) {
                table.customPalettes[index] = palette
            } else {
                table.customPalettes.append(palette)
            }
        }
    }

    func deletePalette(_ id: String) {
        mutate { table in
            table.customPalettes.removeAll { $0.id == id }
            // Gli eventi colorati con quella palette tornano al colore automatico.
            for index in table.entries.indices where table.entries[index].color?.paletteID == id {
                table.entries[index].color = nil
            }
        }
    }

    /// Applica una palette a una serie di eventi della stessa giornata. Gli eventi uguali
    /// accostati (es. due ore di matematica) prendono lo stesso colore.
    func applyPalette(_ paletteID: String?, to ids: [UUID]) {
        let selected = ids.compactMap { id in timetable.entries.first { $0.id == id } }
            .sorted(by: Self.order)
        let positions = Self.seriesPositions(selected)
        mutate { table in
            for (offset, entry) in selected.enumerated() {
                guard let index = table.entries.firstIndex(where: { $0.id == entry.id }) else { continue }
                if let paletteID {
                    table.entries[index].color = .series(paletteID: paletteID, index: positions.index[offset],
                                                         count: positions.count)
                } else {
                    table.entries[index].color = nil
                }
            }
        }
    }

    /// Posizione di ogni evento nella serie (gli eventi vanno passati in ordine, `order`): gli
    /// eventi uguali accostati contano una volta sola.
    static func seriesPositions(_ entries: [TimetableEntry]) -> (index: [Int], count: Int) {
        var indexes: [Int] = []
        var count = 0
        // Fine dell'ultimo evento di ogni nome → la sua posizione (anche se nell'ordine della
        // giornata tra i due c'è un evento contemporaneo).
        var open: [String: (end: Int, index: Int)] = [:]
        for entry in entries {
            if let previous = open[entry.matchKey], previous.end == entry.start, !entry.matchKey.isEmpty {
                indexes.append(previous.index)
                open[entry.matchKey] = (entry.end, previous.index)
            } else {
                indexes.append(count)
                open[entry.matchKey] = (entry.end, count)
                count += 1
            }
        }
        return (indexes, count)
    }

    // MARK: Bozza generata

    /// Applica la bozza: sostituisce l'orario o aggiunge solo gli eventi che non si sovrappongono.
    func applyDraft(replacing: Bool) {
        guard let draft else { return }
        let generated = draft.entries
        let generatedSettings = draft.settings
        mutate { table in
            if replacing {
                table.entries = generated
                table.occurrences = [:]
            } else {
                let additions = generated.filter { new in
                    !table.entries.contains { old in
                        old.weekday == new.weekday && old.isBreak == new.isBreak && old.start < new.end && new.start < old.end
                    }
                }
                table.entries.append(contentsOf: additions)
            }
            table.generation = generatedSettings
        }
        self.draft = nil
        removeUnreferencedFiles()
    }

    func deleteAll() {
        mutate { table in
            table.entries = []
            table.occurrences = [:]
            table.hiddenTests = []
        }
        removeUnreferencedFiles()
    }

    // MARK: Backup

    enum BackupError: LocalizedError {
        case notABackup, newerVersion, noSession

        var errorDescription: String? {
            switch self {
            case .notABackup: "Il file scelto non è un backup dell'orario di BCW."
            case .newerVersion: "Il backup è stato creato da una versione più recente di BCW. Aggiorna l'app per importarlo."
            case .noSession: "Accedi a un account per importare l'orario."
            }
        }
    }

    /// Backup completo: orario e file allegati.
    func makeBackup() throws -> Data {
        var files: [TimetableBackup.File] = []
        if let filesDirectory {
            for name in timetable.referencedFiles.sorted() {
                let url = filesDirectory.appendingPathComponent(name)
                if let data = try? Data(contentsOf: url) {
                    files.append(TimetableBackup.File(storedName: name, data: data))
                }
            }
        }
        return try TimetableBackup.encoder().encode(TimetableBackup(timetable: timetable, files: files))
    }

    /// Legge e controlla un backup, senza applicarlo.
    static func readBackup(_ data: Data) throws -> TimetableBackup {
        struct Header: Decodable {
            let format: String?
            let version: Int?
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.format == TimetableBackup.formatID else { throw BackupError.notABackup }
        guard (header.version ?? 0) <= TimetableBackup.currentVersion else { throw BackupError.newerVersion }
        do {
            return try TimetableBackup.decoder().decode(TimetableBackup.self, from: data)
        } catch {
            throw BackupError.notABackup
        }
    }

    /// Sostituisce l'orario attuale con quello del backup. I file vengono prima scritti in una
    /// cartella temporanea e solo alla fine prendono il posto di quelli attuali, così un errore
    /// a metà non lascia l'orario senza allegati.
    func restore(_ backup: TimetableBackup) throws {
        guard let directory, let filesDirectory else { throw BackupError.noSession }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent("Files-import-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for file in backup.files {
                // Solo nomi semplici: un backup non deve poter scrivere fuori dalla cartella.
                let name = (file.storedName as NSString).lastPathComponent
                guard !name.isEmpty, name == file.storedName, !name.hasPrefix(".") else { continue }
                try file.data.write(to: staging.appendingPathComponent(name), options: .atomic)
            }
            if fileManager.fileExists(atPath: filesDirectory.path) {
                try fileManager.removeItem(at: filesDirectory)
            }
            try fileManager.moveItem(at: staging, to: filesDirectory)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        draft = nil
        mutate { $0 = backup.timetable }
        removeUnreferencedFiles()
    }
}

/// Orario generato in attesa di conferma.
struct TimetableDraft {
    var entries: [TimetableEntry]
    var settings: GenerationSettings
    /// Giorni di lezione esaminati.
    var analyzedDays: Int
    /// Da quando a quando.
    var from: Date
    var to: Date

    func entries(weekday: Int) -> [TimetableEntry] {
        entries.filter { $0.weekday == weekday }.sorted(by: TimetableStore.order)
    }
}

/// Documento per esportare il backup con `fileExporter`.
struct TimetableBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static var defaultFilename: String {
        "Orario BCW \(Date().it("ddMMyyyy").replacingOccurrences(of: "/", with: "-"))"
    }
}
