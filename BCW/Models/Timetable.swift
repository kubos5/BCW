import Foundation

// MARK: - Orario settimanale
//
// L'orario è dell'utente, non di Classeviva: viene salvato solo sul dispositivo (una copia per
// account, vedi `TimetableStore`) e si può esportare in un backup. La decodifica è tollerante
// (ogni campo ha un valore predefinito), così i backup restano leggibili anche quando il formato
// si arricchisce.

/// Allineamento di tutto l'orario, scelto nella modalità di modifica. Automatico: gli eventi
/// iniziano e finiscono all'ora o alla mezz'ora e durano 30 minuti o un'ora (passandoci, gli
/// eventi non allineati vengono allineati, vedi `TimetableEntry.alignedPieces`). Libero: qualsiasi
/// orario. Il formato dei dati è lo stesso (minuti dalla mezzanotte), quindi un orario fatto con
/// l'allineamento libero rispettando la mezz'ora è identico a quello fatto con l'automatico.
/// Gli intervalli sono sempre liberi.
enum TimetableAlignment: String, Codable, CaseIterable, Identifiable {
    case automatic, free
    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Allineamento automatico"
        case .free: "Allineamento libero"
        }
    }

    var shortTitle: String { self == .automatic ? "Automatico" : "Libero" }

    var symbol: String { self == .automatic ? "rectangle.split.1x2" : "slider.horizontal.below.rectangle" }
    /// Icona di Material Symbols.
    var icon: String { self == .automatic ? "alignAuto" : "alignFree" }

    /// Passo con cui si spostano gli eventi trascinandoli.
    var dragStep: Int { self == .automatic ? 30 : 5 }
}

/// Colore di un evento.
nonisolated enum EntryColor: Codable, Hashable {
    /// Uno dei colori pastello delle materie (`Theme.subjectColor`), con variante chiara e scura.
    case pastel(Int)
    /// Colore scelto dall'utente (RGB esadecimale).
    case custom(Int)
    /// Posizione in una palette applicata a una serie di eventi della stessa giornata.
    case series(paletteID: String, index: Int, count: Int)

    var paletteID: String? {
        if case let .series(id, _, _) = self { return id }
        return nil
    }
}

/// File allegato a un evento (ricorrente o di un solo giorno), copiato nella cartella dell'orario.
nonisolated struct TimetableAttachment: Codable, Identifiable, Hashable {
    var id: UUID
    /// Nome mostrato (quello del file originale).
    var name: String
    /// Nome del file salvato nella cartella `Files` dell'orario.
    var storedName: String
    var size: Int
    var addedAt: Date

    init(id: UUID = UUID(), name: String, storedName: String, size: Int, addedAt: Date = .now) {
        self.id = id
        self.name = name
        self.storedName = storedName
        self.size = size
        // Al secondo: i backup salvano le date in ISO 8601, senza frazioni di secondo.
        self.addedAt = Date(timeIntervalSince1970: addedAt.timeIntervalSince1970.rounded(.down))
    }
}

/// Un evento dell'orario: si ripete ogni settimana nello stesso giorno.
nonisolated struct TimetableEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case lesson, breakTime
        var id: String { rawValue }
        var title: String { self == .lesson ? "Lezione" : "Intervallo" }
        var symbol: String { self == .lesson ? "book.closed" : "cup.and.saucer" }
        /// Icona di Material Symbols.
        var icon: String { self == .lesson ? "book" : "coffee" }
    }

    var id: UUID
    /// 1 = lunedì … 7 = domenica.
    var weekday: Int
    /// Minuti dalla mezzanotte.
    var start: Int
    var end: Int
    var kind: Kind
    var title: String
    /// Materia di Classeviva collegata (per riconoscere le verifiche).
    var subjectId: Int?
    var teacher: String
    var room: String
    /// `nil` = colore automatico, quello della materia nella sezione Lezioni.
    var color: EntryColor?
    /// Nota che vale ogni settimana.
    var note: String
    /// File che valgono ogni settimana.
    var attachments: [TimetableAttachment]
    /// Verifica segnata a mano per ogni ricorrenza.
    var isWeeklyTest: Bool

    init(id: UUID = UUID(), weekday: Int, start: Int, end: Int, kind: Kind = .lesson, title: String,
         subjectId: Int? = nil, teacher: String = "", room: String = "", color: EntryColor? = nil,
         note: String = "", attachments: [TimetableAttachment] = [], isWeeklyTest: Bool = false) {
        self.id = id
        self.weekday = weekday
        self.start = start
        self.end = end
        self.kind = kind
        self.title = title
        self.subjectId = subjectId
        self.teacher = teacher
        self.room = room
        self.color = color
        self.note = note
        self.attachments = attachments
        self.isWeeklyTest = isWeeklyTest
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        weekday = min(7, max(1, try c.decodeIfPresent(Int.self, forKey: .weekday) ?? 1))
        let start = min(24 * 60 - 1, max(0, try c.decodeIfPresent(Int.self, forKey: .start) ?? 8 * 60))
        self.start = start
        end = min(24 * 60, max(start + 1, try c.decodeIfPresent(Int.self, forKey: .end) ?? start + 60))
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .lesson
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        subjectId = try c.decodeIfPresent(Int.self, forKey: .subjectId)
        teacher = try c.decodeIfPresent(String.self, forKey: .teacher) ?? ""
        room = try c.decodeIfPresent(String.self, forKey: .room) ?? ""
        color = try? c.decodeIfPresent(EntryColor.self, forKey: .color)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        attachments = try c.decodeIfPresent([TimetableAttachment].self, forKey: .attachments) ?? []
        isWeeklyTest = try c.decodeIfPresent(Bool.self, forKey: .isWeeklyTest) ?? false
    }

    var duration: Int { end - start }
    var isBreak: Bool { kind == .breakTime }

    /// Nome usato per riconoscere gli eventi "dello stesso tipo".
    var matchKey: String { TimetableEntry.normalized(title) }

    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "it_IT"))
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return isBreak ? "Intervallo" : "Senza titolo"
    }

    /// Rispetta i vincoli dell'allineamento automatico (inizio alla mezz'ora, 30 o 60 minuti).
    /// Gli intervalli sono sempre liberi.
    var isAutoAligned: Bool {
        isBreak || (start % 30 == 0 && (duration == 30 || duration == 60))
    }

    /// L'evento con l'allineamento automatico: inizio e fine vanno all'ora o alla mezz'ora più
    /// vicina (presi uno per uno, così gli eventi che erano di seguito restano di seguito, senza
    /// sovrapporsi) e un evento più lungo di un'ora diventa una serie di eventi uguali da un'ora
    /// (l'ultimo eventualmente da mezz'ora), che l'orario mostra uniti. Note, file e verifiche
    /// restano sul primo, che conserva l'identificativo (e con esso le modifiche dei singoli giorni).
    func alignedPieces() -> [TimetableEntry] {
        guard !isAutoAligned else { return [self] }
        let start = min(max(0, TimeOfDay.snapped(self.start, step: 30)), 24 * 60 - 30)
        let end = min(24 * 60, max(start + 30, TimeOfDay.snapped(self.end, step: 30)))
        var pieces: [TimetableEntry] = []
        var cursor = start
        while cursor < end {
            let length = end - cursor >= 60 ? 60 : 30
            var piece = self
            if !pieces.isEmpty {
                piece.id = UUID()
                piece.note = ""
                piece.attachments = []
                piece.isWeeklyTest = false
            }
            piece.start = cursor
            piece.end = cursor + length
            pieces.append(piece)
            cursor += length
        }
        return pieces
    }

    var timeRange: String { "\(TimeOfDay.string(start))–\(TimeOfDay.string(end))" }
}

/// Modifiche di un solo giorno a un evento ricorrente.
struct OccurrenceInfo: Codable, Hashable {
    var note: String = ""
    var attachments: [TimetableAttachment] = []
    /// `nil` = come ogni settimana; `true`/`false` = verifica segnata (o tolta) solo quel giorno.
    var isTest: Bool?

    init(note: String = "", attachments: [TimetableAttachment] = [], isTest: Bool? = nil) {
        self.note = note
        self.attachments = attachments
        self.isTest = isTest
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        attachments = try c.decodeIfPresent([TimetableAttachment].self, forKey: .attachments) ?? []
        isTest = try c.decodeIfPresent(Bool.self, forKey: .isTest)
    }

    var isEmpty: Bool { note.isEmpty && attachments.isEmpty && isTest == nil }

    static func key(_ entryID: UUID, _ day: Date) -> String {
        "\(entryID.uuidString)@\(CVDate.dayKey(day))"
    }
}

/// Palette di colori: sfumatura (i colori intermedi si interpolano) o elenco di colori distinti.
struct ColorPalette: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var colors: [Int]
    var isGradient: Bool

    init(id: String = UUID().uuidString, name: String, colors: [Int], isGradient: Bool = true) {
        self.id = id
        self.name = name
        self.colors = colors
        self.isGradient = isGradient
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Palette"
        colors = try c.decodeIfPresent([Int].self, forKey: .colors) ?? []
        isGradient = try c.decodeIfPresent(Bool.self, forKey: .isGradient) ?? true
    }

    var isBuiltIn: Bool { id.hasPrefix("builtin.") }

    /// Colore dell'elemento `index` di una serie di `count` eventi.
    func color(at index: Int, of count: Int) -> Int {
        guard !colors.isEmpty else { return 0x8FA3B8 }
        guard isGradient, colors.count > 1, count > 1 else { return colors[index % colors.count] }
        let t = Double(min(max(index, 0), count - 1)) / Double(count - 1)
        return Self.interpolate(colors, at: t)
    }

    /// Campioni per mostrare la palette (le sfumature in `count` passi).
    func samples(_ count: Int = 6) -> [Int] {
        guard isGradient, colors.count > 1 else { return colors }
        return (0..<count).map { color(at: $0, of: count) }
    }

    static func interpolate(_ stops: [Int], at t: Double) -> Int {
        let position = min(max(t, 0), 1) * Double(stops.count - 1)
        let lower = min(Int(position), stops.count - 2)
        let fraction = position - Double(lower)
        func channel(_ hex: Int, _ shift: Int) -> Double { Double((hex >> shift) & 0xFF) }
        var result = 0
        for shift in [16, 8, 0] {
            let value = channel(stops[lower], shift) * (1 - fraction) + channel(stops[lower + 1], shift) * fraction
            result |= Int(value.rounded()) << shift
        }
        return result
    }

    /// Indice nella palette pastello delle materie, per la palette "Pastello" (colori dinamici).
    static let pastelID = "builtin.pastel"

    static let builtIn: [ColorPalette] = [
        ColorPalette(id: pastelID, name: "Pastello (Lezioni)",
                     colors: [0xB5523B, 0x3F7D73, 0x5B5FA8, 0xA0782A, 0x8A4F7D, 0x4F7FA6,
                              0x6E8B3D, 0xB0563F, 0x7A6A58, 0x2F7A8C, 0x9A4A5A, 0x5E7F52],
                     isGradient: false),
        ColorPalette(id: "builtin.ocean", name: "Oceano", colors: [0xA6D8F2, 0x5FA8DC, 0x2F6FB5, 0x1B3F7A]),
        ColorPalette(id: "builtin.sunset", name: "Tramonto", colors: [0xF4D35E, 0xF59E3B, 0xE8613C, 0xC0392B]),
        ColorPalette(id: "builtin.lagoon", name: "Laguna", colors: [0x8BCF7E, 0x3FA796, 0x2E86AB, 0x2B5C9E]),
        ColorPalette(id: "builtin.lavender", name: "Lavanda", colors: [0xF4A6C6, 0xC98BD9, 0x9A7BD6, 0x6A5ACD]),
        ColorPalette(id: "builtin.forest", name: "Bosco", colors: [0xC5E1A5, 0x8BC34A, 0x4E9A45, 0x2E6B34]),
        ColorPalette(id: "builtin.earth", name: "Terra", colors: [0xE9D8A6, 0xD4A373, 0xB07D4F, 0x7F5539]),
        ColorPalette(id: "builtin.rainbow", name: "Arcobaleno",
                     colors: [0xE57373, 0xF0A35E, 0xE8C95A, 0x81C784, 0x64B5F6, 0x9575CD]),
        ColorPalette(id: "builtin.slate", name: "Ardesia", colors: [0xC2CAD3, 0x8794A3, 0x5C6B7A, 0x3B4754]),
    ]
}

/// Impostazioni per generare l'orario dalle lezioni registrate.
struct GenerationSettings: Codable, Hashable {
    /// Inizio della prima ora (minuti dalla mezzanotte).
    var firstHourStart: Int = 8 * 60
    /// Durata di un'ora di lezione in minuti.
    var hourLength: Int = 60
    /// Settimane da esaminare (0 = tutto l'anno scolastico).
    var weeks: Int = 6
    /// Intervalli da aggiungere ogni giorno.
    var breaks: [BreakRule] = []

    struct BreakRule: Codable, Hashable, Identifiable {
        var id = UUID()
        var start: Int
        var duration: Int
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        firstHourStart = try c.decodeIfPresent(Int.self, forKey: .firstHourStart) ?? 8 * 60
        hourLength = max(10, try c.decodeIfPresent(Int.self, forKey: .hourLength) ?? 60)
        weeks = try c.decodeIfPresent(Int.self, forKey: .weeks) ?? 6
        breaks = try c.decodeIfPresent([BreakRule].self, forKey: .breaks) ?? []
    }
}

/// Tutto l'orario di un account.
struct Timetable: Codable, Equatable {
    var entries: [TimetableEntry] = []
    /// Modifiche dei singoli giorni, per chiave `OccurrenceInfo.key`.
    var occurrences: [String: OccurrenceInfo] = [:]
    /// Verifiche di Classeviva nascoste a mano dall'orario (id degli eventi dell'agenda).
    var hiddenTests: Set<Int> = []
    /// Verifiche mostrate a mano anche se le regole le nasconderebbero.
    var shownTests: Set<Int> = []
    /// Regole per nascondere da sole le verifiche di Classeviva.
    var testRules = TestHidingRules()
    var alignment: TimetableAlignment = .automatic
    var customColors: [Int] = []
    var customPalettes: [ColorPalette] = []
    var generation = GenerationSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([TimetableEntry].self, forKey: .entries) ?? []
        occurrences = try c.decodeIfPresent([String: OccurrenceInfo].self, forKey: .occurrences) ?? [:]
        hiddenTests = try c.decodeIfPresent(Set<Int>.self, forKey: .hiddenTests) ?? []
        shownTests = (try? c.decodeIfPresent(Set<Int>.self, forKey: .shownTests)) ?? []
        testRules = (try? c.decodeIfPresent(TestHidingRules.self, forKey: .testRules)) ?? TestHidingRules()
        alignment = (try? c.decodeIfPresent(TimetableAlignment.self, forKey: .alignment)) ?? .automatic
        customColors = try c.decodeIfPresent([Int].self, forKey: .customColors) ?? []
        customPalettes = try c.decodeIfPresent([ColorPalette].self, forKey: .customPalettes) ?? []
        generation = (try? c.decodeIfPresent(GenerationSettings.self, forKey: .generation)) ?? GenerationSettings()
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Tutti i file a cui l'orario fa riferimento.
    var referencedFiles: Set<String> {
        var names = Set(entries.flatMap { $0.attachments.map(\.storedName) })
        for info in occurrences.values { names.formUnion(info.attachments.map(\.storedName)) }
        return names
    }
}

/// Regole per nascondere da sole le verifiche di Classeviva dall'orario (ad esempio quelle di un
/// docente che le segna in modo sbagliato, quelle del sabato o di un periodo di viaggio). Una
/// verifica è nascosta se soddisfa almeno una regola; si può comunque mostrare a mano.
nonisolated struct TestHidingRules: Codable, Equatable {
    /// Docenti, come in `AgendaEvent.authorName`.
    var teachers: Set<String> = []
    /// Materie, come `TimetableEntry.normalized` del nome.
    var subjects: Set<String> = []
    /// Giorni della settimana (1 = lunedì).
    var weekdays: Set<Int> = []
    /// Periodi (estremi compresi).
    var periods: [Period] = []
    /// Parole che, nel testo della verifica, la nascondono.
    var keywords: [String] = []
    /// Verifiche di materie che non sono nell'orario quel giorno.
    var unmatched = false

    struct Period: Codable, Equatable, Identifiable {
        var id = UUID()
        var start: Date
        var end: Date
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        teachers = (try? c.decodeIfPresent(Set<String>.self, forKey: .teachers)) ?? []
        subjects = (try? c.decodeIfPresent(Set<String>.self, forKey: .subjects)) ?? []
        weekdays = (try? c.decodeIfPresent(Set<Int>.self, forKey: .weekdays)) ?? []
        periods = (try? c.decodeIfPresent([Period].self, forKey: .periods)) ?? []
        keywords = (try? c.decodeIfPresent([String].self, forKey: .keywords)) ?? []
        unmatched = (try? c.decodeIfPresent(Bool.self, forKey: .unmatched)) ?? false
    }

    var isEmpty: Bool {
        teachers.isEmpty && subjects.isEmpty && weekdays.isEmpty && periods.isEmpty && keywords.isEmpty && !unmatched
    }

    var count: Int {
        teachers.count + subjects.count + weekdays.count + periods.count + keywords.count + (unmatched ? 1 : 0)
    }
}

/// Perché una verifica di Classeviva è nascosta.
enum TestHiddenReason: Equatable {
    case manual
    /// Nascosta da una regola (descritta, es. "Docente: Rossi Giorgio").
    case rule(String)

    var description: String {
        switch self {
        case .manual: "Nascosta a mano"
        case let .rule(rule): "Nascosta dalla regola «\(rule)»"
        }
    }
}

/// File di backup dell'orario: JSON con l'orario e i file allegati (in base64).
struct TimetableBackup: Codable {
    static let formatID = "com.bcw.timetable-backup"
    static let currentVersion = 1

    struct File: Codable {
        var storedName: String
        var data: Data
    }

    var format: String = formatID
    var version: Int = currentVersion
    var exportedAt: Date = .now
    var appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    var timetable: Timetable
    var files: [File]

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Orari come minuti dalla mezzanotte.
nonisolated enum TimeOfDay {
    static func string(_ minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 24 * 60)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// Durata leggibile: "1 ora", "30 min", "1 h 20 min".
    static func duration(_ minutes: Int) -> String {
        if minutes == 60 { return "1 ora" }
        if minutes % 60 == 0 { return "\(minutes / 60) ore" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    @MainActor static func minutes(of date: Date) -> Int {
        let c = CVDate.calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Data di oggi all'ora indicata (per i `DatePicker` delle ore).
    @MainActor static func date(_ minutes: Int) -> Date {
        CVDate.calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func snapped(_ minutes: Int, step: Int) -> Int {
        Int((Double(minutes) / Double(step)).rounded()) * step
    }
}

extension Date {
    /// Giorno della settimana dell'orario: 1 = lunedì … 7 = domenica.
    var timetableWeekday: Int {
        (CVDate.calendar.component(.weekday, from: self) + 5) % 7 + 1
    }
}

enum Weekday {
    static let names = ["Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"]
    static let shortNames = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]

    static func name(_ weekday: Int) -> String { names[(weekday - 1 + 7) % 7] }
    static func shortName(_ weekday: Int) -> String { shortNames[(weekday - 1 + 7) % 7] }
}
