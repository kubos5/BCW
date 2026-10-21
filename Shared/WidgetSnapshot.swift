import Foundation

/// Istantanea compatta dei dati per i widget: l'app la scrive nel contenitore dell'App Group
/// (`WidgetExporter`) ogni volta che cambiano i dati che servono, l'estensione la legge. Niente
/// credenziali: solo ciò che i widget mostrano, con i colori già risolti per il tema chiaro e scuro.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1
    /// Giorni dell'orario risolti (da oggi).
    static let dayCount = 8
    /// Giorni dell'agenda (da oggi).
    static let agendaDays = 14

    var version = WidgetSnapshot.currentVersion
    var generatedAt = Date()
    /// `false` senza account: i widget invitano ad aprire l'app.
    var signedIn = false
    var isDemo = false
    var accountName = ""
    /// Ultimo aggiornamento dei dati di Classeviva.
    var lastUpdated: Date?
    /// L'orario ha almeno un evento (altrimenti i widget invitano a crearlo).
    var hasTimetable = false
    /// Eventi dell'orario risolti per giorno (`dayCount` giorni da quello di `generatedAt`).
    var days: [Day] = []
    /// Eventi ricorrenti per giorno della settimana (indice 0 = lunedì), senza le verifiche dei
    /// singoli giorni: servono se l'app non viene aperta per più di `dayCount` giorni.
    var week: [[Event]] = []
    /// Compiti, verifiche ed eventi dell'agenda dei prossimi giorni, in ordine.
    var agenda: [AgendaItem] = []
    var grades: Grades?
    var theme = ThemeSnapshot()

    // MARK: Tipi

    /// Colore chiaro e scuro (RGB esadecimale).
    struct Tint: Codable, Hashable, Sendable {
        var light: Int
        var dark: Int
    }

    struct Day: Codable, Equatable, Sendable {
        /// `yyyy-MM-dd` (`BCWShared.dayKey`).
        var key: String
        var events: [Event]
        var isHoliday = false
    }

    struct Event: Codable, Equatable, Sendable, Identifiable {
        enum Kind: String, Codable, Sendable { case lesson, breakTime }

        var id: String
        var title: String
        var room = ""
        var teacher = ""
        /// Minuti dalla mezzanotte.
        var start: Int
        var end: Int
        var kind: Kind = .lesson
        /// Verifica segnata nell'orario (a mano o da Classeviva), come nella vista Lista.
        var isTest = false
        /// Verifica in quell'ora anche con "Mostra le verifiche" spenta (per l'attività in diretta,
        /// che la segnala sempre). Facoltativo: le istantanee precedenti non ce l'hanno.
        var hasTest: Bool?
        /// Colore della materia o scelto dall'utente.
        var tint: Tint

        var isBreak: Bool { kind == .breakTime }
        var duration: Int { end - start }
    }

    struct AgendaItem: Codable, Equatable, Sendable, Identifiable {
        enum Kind: String, Codable, Sendable { case homework, test, event }

        var id: Int
        var kind: Kind
        var begin: Date
        var end: Date
        var isFullDay: Bool
        /// Materia (o autore, per gli eventi senza materia).
        var title: String
        var text: String
        var author = ""
        /// Compito segnato come fatto.
        var isDone = false
        var tint: Tint
    }

    struct Grades: Codable, Equatable, Sendable {
        struct PeriodAverage: Codable, Equatable, Sendable {
            var position: Int
            var name: String
            var average: Double?
        }

        /// Media generale (tutto l'anno).
        var average: Double?
        /// Periodo in corso, o l'ultimo con dei voti.
        var current: PeriodAverage?
        var periods: [PeriodAverage] = []
        /// Voti che fanno media (tutto l'anno).
        var countingGrades = 0
        /// Materie insufficienti nel periodo in corso.
        var insufficientSubjects = 0
    }

    /// Ruoli di Material 3 del tema scelto in Impostazioni › Aspetto (più i toni degli stati),
    /// angoli e arrotondamento del testo.
    struct ThemeSnapshot: Codable, Equatable, Sendable {
        var light: [String: String] = ThemeDefaults.light.merging(ThemeDefaults.toneRoles.light) { a, _ in a }
        var dark: [String: String] = ThemeDefaults.dark.merging(ThemeDefaults.toneRoles.dark) { a, _ in a }
        /// `square`, `standard` o `round` (Impostazioni › Aspetto › Angoli).
        var corners = "standard"
        /// Asse ROND dei titoli e del testo.
        var rond: Double = 100
        var rondBody: Double = 30
    }

    // MARK: Lettura

    /// Eventi dell'orario di un giorno: quelli risolti dall'app o, oltre, quelli ricorrenti.
    func events(on day: Date) -> [Event] {
        let key = BCWShared.dayKey(day)
        if let resolved = days.first(where: { $0.key == key }) { return resolved.events }
        let weekday = BCWShared.weekday(of: day)
        guard week.indices.contains(weekday - 1) else { return [] }
        return week[weekday - 1]
    }

    /// Stesso contenuto (a parte l'istante in cui è stata costruita): non serve riscriverla.
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        var copy = other
        copy.generatedAt = generatedAt
        return copy == self
    }

    func isHoliday(_ day: Date) -> Bool {
        days.first { $0.key == BCWShared.dayKey(day) }?.isHoliday ?? false
    }

    /// Il giorno che l'orario mostra da solo a un certo istante (`TimetableDefaultDay`).
    func defaultTimetableDay(at date: Date) -> Date {
        TimetableDefaultDay.day(now: date) { day in
            events(on: day).filter { !$0.isBreak }.map { TimetableDefaultDay.Span(start: $0.start, end: $0.end) }
        }
    }

    // MARK: Archivio

    /// File dell'istantanea nel contenitore dell'App Group (`nil` senza l'App Group).
    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BCWShared.appGroup)?
            .appendingPathComponent("Widgets", isDirectory: true)
            .appendingPathComponent("snapshot.json")
    }

    /// L'istantanea salvata, se c'è ed è di una versione conosciuta.
    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version <= currentVersion else { return nil }
        return snapshot
    }

    func save() throws {
        guard let url = Self.fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// MARK: - Dati di esempio

nonisolated extension WidgetSnapshot {
    /// Dati di esempio per l'anteprima nella galleria dei widget di iOS (e come segnaposto),
    /// quando l'app non ha ancora scritto un'istantanea.
    static func sample(now: Date = Date()) -> WidgetSnapshot {
        let calendar = BCWShared.calendar
        let today = calendar.startOfDay(for: now)
        func tint(_ light: Int, _ dark: Int) -> Tint { Tint(light: light, dark: dark) }
        let math = tint(0x5357A0, 0xBFC1FF), italian = tint(0x9E412B, 0xFFB4A3), english = tint(0x29685F, 0x94D2C7)
        let history = tint(0x7C5808, 0xEFBF6A), science = tint(0x306388, 0x9CCCF6), art = tint(0x854A78, 0xF8B0E4)
        let pe = tint(0x4C671D, 0xB1D27B), pause = tint(0x9A8C78, 0xB8AC98)
        let rows: [(String, Tint, String, String)] = [
            ("Matematica", math, "2B", "Rossi Giorgio"), ("Italiano", italian, "2B", "Bianchi Laura"),
            ("Inglese", english, "Lab 1", "Smith Anna"), ("Storia", history, "2B", "Verdi Andrea"),
            ("Scienze", science, "Lab 2", "Neri Paola"), ("Arte", art, "Aula disegno", "Gallo Marco"),
            ("Educazione fisica", pe, "Palestra", "Fontana Luca"),
        ]
        var week: [[Event]] = []
        for weekday in 1...7 {
            guard weekday <= 5 else { week.append([]); continue }
            var events: [Event] = []
            for hour in 0..<5 {
                let row = rows[(hour + weekday * 2) % rows.count]
                let start = 8 * 60 + hour * 60 + (hour >= 3 ? 10 : 0)
                events.append(Event(id: "\(weekday)-\(hour)", title: row.0, room: row.2, teacher: row.3,
                                    start: start, end: start + 60, tint: row.1))
                if hour == 2 {
                    events.append(Event(id: "\(weekday)-b", title: "Intervallo", start: 11 * 60, end: 11 * 60 + 10,
                                        kind: .breakTime, tint: pause))
                }
            }
            week.append(events)
        }
        var days: [Day] = []
        for offset in 0..<dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            var events = week[BCWShared.weekday(of: day) - 1]
            if offset == 2, let index = events.firstIndex(where: { !$0.isBreak }) { events[index].isTest = true }
            days.append(Day(key: BCWShared.dayKey(day), events: events))
        }
        func at(_ offset: Int, _ hour: Int = 0) -> Date {
            calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: offset, to: today) ?? today) ?? today
        }
        let agenda = [
            AgendaItem(id: 1, kind: .homework, begin: at(1), end: at(1), isFullDay: true, title: "Matematica",
                       text: "Esercizi 12–18 a pagina 154", tint: math),
            AgendaItem(id: 2, kind: .homework, begin: at(1), end: at(1), isFullDay: true, title: "Inglese",
                       text: "Leggere il capitolo 4 e rispondere alle domande", tint: english),
            AgendaItem(id: 3, kind: .test, begin: at(2, 9), end: at(2, 10), isFullDay: false, title: "Storia",
                       text: "Verifica scritta sulla Rivoluzione francese", author: "Verdi Andrea", tint: history),
            AgendaItem(id: 4, kind: .event, begin: at(3, 10), end: at(3, 12), isFullDay: false, title: "Uscita didattica",
                       text: "Visita al museo di scienze naturali", tint: science),
            AgendaItem(id: 5, kind: .homework, begin: at(4), end: at(4), isFullDay: true, title: "Italiano",
                       text: "Tema: un viaggio che ricordi", tint: italian),
            AgendaItem(id: 6, kind: .test, begin: at(6, 8), end: at(6, 9), isFullDay: false, title: "Matematica",
                       text: "Verifica su equazioni di secondo grado", author: "Rossi Giorgio", tint: math),
        ]
        let grades = Grades(average: 7.42, current: .init(position: 1, name: "Trimestre", average: 7.42),
                            periods: [.init(position: 1, name: "Trimestre", average: 7.42)],
                            countingGrades: 18, insufficientSubjects: 0)
        return WidgetSnapshot(generatedAt: now, signedIn: true, isDemo: true, accountName: "Giulia Esposito",
                              lastUpdated: now, hasTimetable: true, days: days, week: week, agenda: agenda,
                              grades: grades)
    }
}
