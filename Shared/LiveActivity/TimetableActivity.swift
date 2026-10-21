import ActivityKit
import Foundation

// MARK: - Attributi e stato

/// Attività in diretta "Orario di oggi": la lezione in corso con il tempo che manca e
/// l'avanzamento, poi la successiva (come `TimetableNowCard` nella scheda Orario), nella schermata
/// di blocco e nella Dynamic Island. Comune all'app (che la avvia e la aggiorna,
/// `LiveActivityManager`) e all'estensione dei widget (che la disegna).
nonisolated struct TimetableActivityAttributes: ActivityAttributes {
    typealias ContentState = TimetableActivityState

    /// Giorno seguito (`yyyy-MM-dd`, `BCWShared.dayKey`).
    var dayKey: String
    /// Inizio programmato dell'avvio automatico (`nil` se avviata subito): se cambia l'orario,
    /// un'attività in attesa con un altro inizio va rifatta.
    var scheduledStart: Date?
}

/// Contenuto dell'attività. Senza server l'app la aggiorna solo quando è in esecuzione, quindi lo
/// stato porta la fase attuale e la successiva: passata la fine della prima (`staleDate`), iOS
/// ridisegna l'attività con `isStale` e la vista mostra la seconda come attuale.
nonisolated struct TimetableActivityState: Codable, Hashable, Sendable {
    /// La fase attuale e quella dopo.
    var phases: [TimetableActivityPhase]
    /// Lezioni del giorno (ore uguali di seguito contano una volta).
    var lessonCount: Int
    var theme: TimetableActivityTheme

    /// La fase da mostrare: la seconda quando la prima è finita (contenuto scaduto).
    func phase(isStale: Bool) -> TimetableActivityPhase? {
        isStale && phases.count > 1 ? phases[1] : phases.first
    }
}

/// Un tratto della giornata con lo stesso contenuto: prima dell'inizio, una lezione, una pausa tra
/// due lezioni, lezioni finite.
nonisolated struct TimetableActivityPhase: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Prima della prima lezione: conto alla rovescia all'inizio.
        case before
        /// Lezione in corso.
        case lesson
        /// Intervallo o ora libera tra due lezioni: conto alla rovescia alla prossima.
        case pause
        /// Dopo l'ultima lezione (solo come contenuto finale o scaduto).
        case finished
    }

    var kind: Kind
    var start: Date
    var end: Date
    /// La lezione in evidenza: quella in corso, o la prossima (prima dell'inizio e nelle pause).
    var lesson: TimetableActivityLesson?
    /// La lezione dopo quella in evidenza (`nil`: è l'ultima).
    var next: TimetableActivityLesson?
    /// Nome della pausa preso dall'orario ("Intervallo"); `nil` se nell'orario non c'è.
    var title: String?
    /// Posizione della lezione in evidenza (1 = la prima del giorno).
    var position: Int

    var interval: ClosedRange<Date> { start...max(start.addingTimeInterval(1), end) }
}

/// Una lezione (ore uguali di seguito unite).
nonisolated struct TimetableActivityLesson: Codable, Hashable, Sendable {
    var title: String
    var room: String
    var teacher: String
    var start: Date
    var end: Date
    var tint: WidgetSnapshot.Tint
    /// C'è una verifica (segnata a mano o di Classeviva, non nascosta).
    var isTest: Bool

    var interval: ClosedRange<Date> { start...max(start.addingTimeInterval(1), end) }
}

/// I pochi ruoli del tema che servono all'attività, per il tema chiaro e scuro (la Dynamic Island
/// usa sempre quelli scuri). Nello stato e non negli attributi: cambiando l'aspetto nell'app
/// l'attività si aggiorna.
nonisolated struct TimetableActivityTheme: Codable, Hashable, Sendable {
    struct Roles: Codable, Hashable, Sendable {
        var surface: Int
        var container: Int
        var containerHigh: Int
        var onSurface: Int
        var onSurfaceVariant: Int
        var primary: Int
        var outlineVariant: Int
    }

    var light: Roles
    var dark: Roles
    var rond: Double
    var rondBody: Double

    init(_ theme: WidgetSnapshot.ThemeSnapshot) {
        func roles(_ values: [String: String], _ defaults: [String: String]) -> Roles {
            func value(_ name: String) -> Int {
                ThemeDefaults.hexValue(values[name]) ?? ThemeDefaults.hexValue(defaults[name]) ?? 0x808080
            }
            return Roles(surface: value("surface"), container: value("surface-container"),
                         containerHigh: value("surface-container-highest"), onSurface: value("on-surface"),
                         onSurfaceVariant: value("on-surface-variant"), primary: value("primary"),
                         outlineVariant: value("outline-variant"))
        }
        light = roles(theme.light, ThemeDefaults.light)
        dark = roles(theme.dark, ThemeDefaults.dark)
        rond = theme.rond
        rondBody = theme.rondBody
    }
}

// MARK: - Piano della giornata

/// Le fasi di una giornata di lezioni, da cui l'app ricava il contenuto dell'attività a un certo
/// istante e i momenti in cui cambia.
nonisolated struct TimetableActivityPlan {
    /// Un evento dell'orario con le sue date.
    struct Item {
        var title: String
        var room = ""
        var teacher = ""
        var start: Date
        var end: Date
        var tint: WidgetSnapshot.Tint
        var isTest = false
        var isBreak = false
    }

    /// Anticipo dell'avvio automatico sulla prima lezione (fase "prima dell'inizio").
    static let lead: TimeInterval = 30 * 60

    let day: Date
    let lessons: [TimetableActivityLesson]
    /// Prima dell'inizio, lezioni e pause in ordine, lezioni finite.
    let phases: [TimetableActivityPhase]

    /// `nil` senza lezioni.
    init?(day: Date, items: [Item]) {
        self.day = day
        // Lezioni in ordine, senza sovrapposizioni; ore uguali di seguito (stessa materia, colore,
        // aula) unite come nei gruppi dell'orario.
        var lessons: [TimetableActivityLesson] = []
        for item in items.filter({ !$0.isBreak && $0.end > $0.start }).sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            var start = item.start
            if let last = lessons.last {
                if item.end <= last.end { continue }
                start = max(start, last.end)
                if start == last.end, item.title == last.title, item.tint == last.tint, item.room == last.room {
                    lessons[lessons.count - 1].end = item.end
                    lessons[lessons.count - 1].isTest = last.isTest || item.isTest
                    if lessons[lessons.count - 1].teacher.isEmpty { lessons[lessons.count - 1].teacher = item.teacher }
                    continue
                }
            }
            lessons.append(TimetableActivityLesson(title: item.title, room: item.room, teacher: item.teacher,
                                                   start: start, end: item.end, tint: item.tint, isTest: item.isTest))
        }
        guard let first = lessons.first, let last = lessons.last else { return nil }
        self.lessons = lessons
        let breaks = items.filter(\.isBreak)

        func lesson(_ index: Int) -> TimetableActivityLesson? { lessons.indices.contains(index) ? lessons[index] : nil }
        var phases = [TimetableActivityPhase(kind: .before, start: first.start.addingTimeInterval(-Self.lead),
                                             end: first.start, lesson: first, next: lesson(1), position: 1)]
        for (index, current) in lessons.enumerated() {
            phases.append(TimetableActivityPhase(kind: .lesson, start: current.start, end: current.end, lesson: current,
                                                 next: lesson(index + 1), position: index + 1))
            if let following = lesson(index + 1), following.start > current.end {
                // Il nome dell'intervallo che cade nella pausa, se nell'orario c'è.
                let pause = breaks.first { $0.start < following.start && $0.end > current.end }
                phases.append(TimetableActivityPhase(kind: .pause, start: current.end, end: following.start,
                                                     lesson: following, next: lesson(index + 2),
                                                     title: pause?.title, position: index + 2))
            }
        }
        phases.append(TimetableActivityPhase(kind: .finished, start: last.end, end: last.end.addingTimeInterval(3600),
                                             position: lessons.count))
        self.phases = phases
    }

    /// Il piano di un giorno dall'istantanea dei widget (`nil` se quel giorno non ci sono lezioni).
    init?(snapshot: WidgetSnapshot, day: Date) {
        let start = BCWShared.calendar.startOfDay(for: day)
        let items = snapshot.events(on: start).map { event in
            Item(title: event.title, room: event.room, teacher: event.teacher,
                 start: BCWShared.date(start, minute: event.start), end: BCWShared.date(start, minute: event.end),
                 tint: event.tint, isTest: event.isTest || event.hasTest == true, isBreak: event.isBreak)
        }
        self.init(day: start, items: items)
    }

    /// Inizio della prima lezione.
    var firstStart: Date { lessons[0].start }
    /// Fine dell'ultima lezione: lì l'attività finisce.
    var end: Date { lessons[lessons.count - 1].end }
    /// Inizio dell'avvio automatico.
    var autoStart: Date { firstStart.addingTimeInterval(-Self.lead) }

    /// Indice della fase in corso a un certo istante (prima dell'avvio automatico, la prima).
    func phaseIndex(at date: Date) -> Int {
        phases.lastIndex { $0.start <= date } ?? 0
    }

    /// Contenuto dell'attività a un certo istante: la fase in corso e la successiva, scaduto alla
    /// fine della fase in corso. `nil` dopo l'ultima lezione.
    func content(at date: Date, theme: TimetableActivityTheme) -> ActivityContent<TimetableActivityState>? {
        guard date < end else { return nil }
        let index = phaseIndex(at: date)
        let shown = Array(phases[index...].prefix(2))
        return ActivityContent(state: TimetableActivityState(phases: shown, lessonCount: lessons.count, theme: theme),
                               staleDate: phases[index].end)
    }

    /// Contenuto finale, quando l'attività finisce: lezioni finite.
    func finalContent(theme: TimetableActivityTheme) -> ActivityContent<TimetableActivityState> {
        ActivityContent(state: TimetableActivityState(phases: Array(phases.suffix(1)), lessonCount: lessons.count,
                                                      theme: theme),
                        staleDate: nil)
    }

    /// Il prossimo istante in cui il contenuto cambia (inizio di una fase o fine delle lezioni).
    func nextChange(after date: Date) -> Date? {
        phases.map(\.start).first { $0 > date }
    }
}

#if DEBUG
// MARK: - Prova

nonisolated extension TimetableActivityPlan {
    /// Orario finto per le prove (`-BCWLiveActivityDemo YES` e galleria dei widget): prima lezione a
    /// `start`, lezioni da 2 `unit`, un intervallo da `unit`, la seconda lezione con una verifica.
    static func sampleItems(start: Date, unit: TimeInterval) -> [Item] {
        func at(_ units: Double) -> Date { start.addingTimeInterval(units * unit) }
        func tint(_ light: Int, _ dark: Int) -> WidgetSnapshot.Tint { .init(light: light, dark: dark) }
        return [
            Item(title: "Matematica", room: "2B", teacher: "Rossi Giorgio", start: at(0), end: at(2),
                 tint: tint(0x5357A0, 0xBFC1FF)),
            Item(title: "Intervallo", start: at(2), end: at(3), tint: tint(0x9A8C78, 0xB8AC98), isBreak: true),
            Item(title: "Storia", room: "Lab 2", teacher: "Verdi Andrea", start: at(3), end: at(5),
                 tint: tint(0x7C5808, 0xEFBF6A), isTest: true),
            Item(title: "Inglese", room: "Lab 1", teacher: "Smith Anna", start: at(5), end: at(7),
                 tint: tint(0x29685F, 0x94D2C7)),
        ]
    }
}
#endif
