import ActivityKit
import Foundation

// MARK: - Scelta per evento

/// Attività in diretta per un evento dell'orario (editor dell'evento, richiesta dell'utente, 3.3): `nil`
/// segue l'impostazione (Impostazioni › Orario › Attività in diretta, o l'avvio a mano di oggi).
nonisolated enum LiveActivityChoice: String, Codable, Hashable, Sendable, CaseIterable {
    /// L'attività segue l'evento anche con l'avvio automatico spento.
    case show
    /// L'attività salta l'evento, come se non fosse nell'orario.
    case hide

    /// L'evento entra nell'attività in diretta, con `showsByDefault` per chi segue l'impostazione.
    static func includes(_ choice: LiveActivityChoice?, showsByDefault: Bool) -> Bool {
        switch choice {
        case .show?: true
        case .hide?: false
        case nil: showsByDefault
        }
    }
}

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
/// stato porta la fase attuale e le successive: passata la fine della prima (`staleDate`), iOS
/// ridisegna l'attività con `isStale` e la vista mostra la seconda come attuale (verificato sul
/// simulatore con l'app chiusa). iOS ridisegna una volta sola: senza un nuovo aggiornamento, alla
/// fine della seconda fase il conto alla rovescia resta a zero.
nonisolated struct TimetableActivityState: Codable, Hashable, Sendable {
    /// La fase attuale e le successive (al massimo `TimetableActivityPlan.carried`).
    var phases: [TimetableActivityPhase]
    /// Lezioni del giorno (ore uguali di seguito contano una volta).
    var lessonCount: Int
    var theme: TimetableActivityTheme
    /// Tempo in formato compatto ("1h39", "45min", "15s") nella Dynamic Island ai lati della
    /// fotocamera (Impostazioni › Orario). Facoltativo: gli stati di prima non ce l'hanno.
    var compactTime: Bool?
    /// Tratto del conto alla rovescia (`TimetableActivityPhase.timerStep`): cambia quando il tempo
    /// perde delle cifre. L'isola prende la larghezza solo quando viene ridisegnata, e iOS la
    /// ridisegna solo se lo stato cambia: senza questo valore l'aggiornamento non partiva.
    var timerStep: Int?

    /// La fase da mostrare: quella in corso al momento del disegno, anche se il contenuto non è ancora
    /// scaduto (iOS lo segna scaduto non prima di 120 s dall'ultimo aggiornamento: un disegno più tardi
    /// del previsto mostrava la fase già finita, con "0:00"). Scaduto il contenuto, almeno la seconda
    /// (iOS può disegnare un attimo prima del suo inizio).
    func phase(isStale: Bool, now: Date = Date()) -> TimetableActivityPhase? {
        guard !phases.isEmpty else { return nil }
        let current = phases.indices.last { phases[$0].start <= now } ?? 0
        return phases[isStale ? max(current, min(1, phases.count - 1)) : current]
    }

    /// Rispetto a `other` cambia solo il tratto del conto alla rovescia.
    func differsOnlyInTimerStep(from other: TimetableActivityState) -> Bool {
        var copy = other
        copy.timerStep = timerStep
        return copy == self
    }
}

/// Un tratto della giornata con lo stesso contenuto: prima dell'inizio, una lezione, un intervallo
/// o un'ora libera, lezioni finite.
nonisolated struct TimetableActivityPhase: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Prima della prima lezione: conto alla rovescia all'inizio.
        case before
        /// Lezione in corso.
        case lesson
        /// Un intervallo dell'orario (con `title`, al posto della lezione in corso se le si
        /// sovrappone) o un'ora libera tra due lezioni: conto alla rovescia alla fine.
        case pause
        /// Dopo l'ultima lezione (solo come contenuto finale o scaduto).
        case finished
    }

    var kind: Kind
    var start: Date
    var end: Date
    /// La lezione in evidenza: quella in corso, o la prossima (prima dell'inizio e nelle pause;
    /// `nil` se dopo un intervallo non ci sono altre lezioni).
    var lesson: TimetableActivityLesson?
    /// La lezione dopo quella in evidenza (`nil`: è l'ultima).
    var next: TimetableActivityLesson?
    /// Nome della pausa preso dall'orario ("Intervallo"); `nil` se nell'orario non c'è.
    var title: String?
    /// Posizione della lezione in evidenza (1 = la prima del giorno).
    var position: Int

    var interval: ClosedRange<Date> { start...max(start.addingTimeInterval(1), end) }

    /// Dove arriva il conto alla rovescia: la fine della fase; prima dell'inizio la prima lezione,
    /// anche se in mezzo c'è un intervallo.
    var countdownEnd: Date { kind == .before ? lesson?.start ?? end : end }

    /// Secondi che mancano sotto i quali il conto alla rovescia ha meno cifre ("0:00:00", "00:00",
    /// "0:00").
    static let timerThresholds: [TimeInterval] = [3600, 600]

    /// Quante soglie del conto alla rovescia sono passate a un certo istante.
    func timerStep(at date: Date) -> Int {
        let remaining = countdownEnd.timeIntervalSince(date)
        return Self.timerThresholds.filter { remaining < $0 }.count
    }

    /// Gli istanti in cui il conto alla rovescia perde delle cifre.
    var timerChanges: [Date] {
        kind == .finished ? [] : Self.timerThresholds.map { countdownEnd.addingTimeInterval(-$0) }
    }
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
    /// Fasi portate da ogni contenuto: quella in corso e le successive (lo stato resta sotto i 4 KB
    /// che ActivityKit accetta).
    static let carried = 4
    /// iOS segna scaduto un contenuto non prima di 120 secondi dall'ultimo aggiornamento (visto nei
    /// registri di `liveactivitiesd`): un aggiornamento più vicino di così alla fine della fase farebbe
    /// slittare il passaggio alla fase dopo.
    static let staleFloor: TimeInterval = 130

    let day: Date
    let lessons: [TimetableActivityLesson]
    /// Prima dell'inizio, lezioni e pause in ordine, lezioni finite.
    let phases: [TimetableActivityPhase]

    /// `nil` senza lezioni.
    init?(day: Date, items: [Item]) {
        self.day = day
        // Intervalli in ordine e senza sovrapposizioni.
        var breaks: [Item] = []
        for item in items.filter({ $0.isBreak && $0.end > $0.start }).sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            var item = item
            if let last = breaks.last {
                if item.end <= last.end { continue }
                item.start = max(item.start, last.end)
            }
            breaks.append(item)
        }
        // Lezioni in ordine, senza sovrapposizioni; ore uguali di seguito (stessa materia, colore,
        // aula) unite come nei gruppi dell'orario, ma non se sul passaggio c'è un intervallo (come
        // nella vista Lista, `TimetableLayout(splitAtBreaks:)`).
        var merged: [TimetableActivityLesson] = []
        for item in items.filter({ !$0.isBreak && $0.end > $0.start }).sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            var start = item.start
            if let last = merged.last {
                if item.end <= last.end { continue }
                start = max(start, last.end)
                if start == last.end, item.title == last.title, item.tint == last.tint, item.room == last.room,
                   !breaks.contains(where: { $0.start <= start && start <= $0.end }) {
                    merged[merged.count - 1].end = item.end
                    merged[merged.count - 1].isTest = last.isTest || item.isTest
                    if merged[merged.count - 1].teacher.isEmpty { merged[merged.count - 1].teacher = item.teacher }
                    continue
                }
            }
            merged.append(TimetableActivityLesson(title: item.title, room: item.room, teacher: item.teacher,
                                                  start: start, end: item.end, tint: item.tint, isTest: item.isTest))
        }
        // Mentre è in corso un intervallo si vede l'intervallo: le lezioni perdono i tratti coperti
        // (una lezione con un intervallo in mezzo diventa due).
        var lessons: [TimetableActivityLesson] = []
        for lesson in merged {
            var part = lesson
            for pause in breaks where pause.end > part.start && pause.start < lesson.end {
                if pause.start > part.start {
                    part.end = pause.start
                    lessons.append(part)
                }
                part.start = pause.end
                part.end = lesson.end
            }
            if part.start < part.end { lessons.append(part) }
        }
        guard let first = lessons.first, let schoolEnd = merged.last?.end else { return nil }
        self.lessons = lessons

        // Gli intervalli che contano: dalla mezz'ora prima della prima lezione fino alla fine
        // dell'ultima (uno rimasto dopo l'ultima lezione non tiene aperta l'attività, come nel
        // giorno predefinito dell'orario).
        let autoStart = first.start.addingTimeInterval(-Self.lead)
        var pending = breaks.filter { $0.end > autoStart && $0.start < schoolEnd }[...]

        func lesson(_ index: Int) -> TimetableActivityLesson? { lessons.indices.contains(index) ? lessons[index] : nil }
        var phases: [TimetableActivityPhase] = []
        var cursor = autoStart
        /// La prima lezione non ancora cominciata.
        var upcoming = 0
        /// Il tratto senza lezioni né intervalli fino a `date`.
        func addWait(until date: Date) {
            guard date > cursor else { return }
            phases.append(TimetableActivityPhase(kind: upcoming == 0 ? .before : .pause, start: cursor, end: date,
                                                 lesson: lesson(upcoming), next: lesson(upcoming + 1),
                                                 position: upcoming + 1))
        }
        while upcoming < lessons.count || !pending.isEmpty {
            if let pause = pending.first, upcoming == lessons.count || pause.start <= lessons[upcoming].start {
                let start = max(pause.start, cursor)
                addWait(until: start)
                phases.append(TimetableActivityPhase(kind: .pause, start: start, end: pause.end,
                                                     lesson: lesson(upcoming), next: lesson(upcoming + 1),
                                                     title: pause.title, position: min(upcoming + 1, lessons.count)))
                cursor = pause.end
                pending.removeFirst()
            } else {
                let current = lessons[upcoming]
                addWait(until: current.start)
                phases.append(TimetableActivityPhase(kind: .lesson, start: current.start, end: current.end,
                                                     lesson: current, next: lesson(upcoming + 1),
                                                     position: upcoming + 1))
                cursor = current.end
                upcoming += 1
            }
        }
        phases.append(TimetableActivityPhase(kind: .finished, start: cursor, end: cursor.addingTimeInterval(3600),
                                             position: lessons.count))
        self.phases = phases
    }

    /// Il piano di un giorno dall'istantanea dei widget (`nil` se quel giorno non ci sono lezioni da
    /// mostrare). Contano gli eventi con "Mostra" e, con `showsByDefault`, quelli che seguono
    /// l'impostazione; quelli con "Non mostrare" mai: l'attività li salta come se non ci fossero (tra due
    /// eventi mostrati, al loro posto c'è il tempo che manca al successivo).
    init?(snapshot: WidgetSnapshot, day: Date, showsByDefault: Bool = true) {
        let start = BCWShared.calendar.startOfDay(for: day)
        let events = snapshot.events(on: start).filter {
            LiveActivityChoice.includes($0.liveActivity, showsByDefault: showsByDefault)
        }
        let items = events.map { event in
            Item(title: event.title, room: event.room, teacher: event.teacher,
                 start: BCWShared.date(start, minute: event.start), end: BCWShared.date(start, minute: event.end),
                 tint: event.tint, isTest: event.isTest || event.hasTest == true, isBreak: event.isBreak)
        }
        self.init(day: start, items: items)
    }

    /// Inizio della prima lezione.
    var firstStart: Date { lessons[0].start }
    /// Fine dell'ultima lezione (o dell'intervallo che la scavalca): lì l'attività finisce.
    var end: Date { phases[phases.count - 1].start }
    /// Inizio dell'avvio automatico.
    var autoStart: Date { firstStart.addingTimeInterval(-Self.lead) }

    /// Indice della fase in corso a un certo istante (prima dell'avvio automatico, la prima).
    func phaseIndex(at date: Date) -> Int {
        phases.lastIndex { $0.start <= date } ?? 0
    }

    /// Contenuto dell'attività a un certo istante: la fase in corso e le successive, scaduto alla
    /// fine della fase in corso. `nil` dopo l'ultima lezione.
    func content(at date: Date, theme: TimetableActivityTheme,
                 compactTime: Bool = false) -> ActivityContent<TimetableActivityState>? {
        guard date < end else { return nil }
        let index = phaseIndex(at: date)
        let shown = Array(phases[index...].prefix(Self.carried))
        return ActivityContent(state: TimetableActivityState(phases: shown, lessonCount: lessons.count, theme: theme,
                                                             compactTime: compactTime,
                                                             timerStep: phases[index].timerStep(at: date)),
                               staleDate: phases[index].end)
    }

    /// Contenuto finale, quando l'attività finisce: lezioni finite.
    func finalContent(theme: TimetableActivityTheme) -> ActivityContent<TimetableActivityState> {
        ActivityContent(state: TimetableActivityState(phases: Array(phases.suffix(1)), lessonCount: lessons.count,
                                                      theme: theme),
                        staleDate: nil)
    }

    /// Il prossimo istante in cui il contenuto cambia: inizio di una fase, fine delle lezioni o
    /// conto alla rovescia che perde delle cifre (l'isola va ridisegnata per stringersi).
    func nextChange(after date: Date) -> Date? {
        (phases.map(\.start) + phases[phaseIndex(at: date)].timerChanges).filter { $0 > date }.min()
    }

    /// Il prossimo inizio di una fase (o la fine delle lezioni): gli unici cambi che contano davvero.
    func nextPhaseStart(after date: Date) -> Date? {
        phases.map(\.start).filter { $0 > date }.min()
    }
}

#if DEBUG
// MARK: - Prova

nonisolated extension TimetableActivityPlan {
    /// Orario finto per le prove (`-BCWLiveActivityDemo YES` e galleria dei widget): prima lezione a
    /// `start`, lezioni da 2 `unit`, un intervallo da `unit`, la seconda lezione con una verifica e
    /// un intervallo sovrapposto da mezza `unit`.
    static func sampleItems(start: Date, unit: TimeInterval) -> [Item] {
        func at(_ units: Double) -> Date { start.addingTimeInterval(units * unit) }
        func tint(_ light: Int, _ dark: Int) -> WidgetSnapshot.Tint { .init(light: light, dark: dark) }
        return [
            Item(title: "Matematica", room: "2B", teacher: "Rossi Giorgio", start: at(0), end: at(2),
                 tint: tint(0x5357A0, 0xBFC1FF)),
            Item(title: "Intervallo", start: at(2), end: at(3), tint: tint(0x9A8C78, 0xB8AC98), isBreak: true),
            Item(title: "Storia", room: "Lab 2", teacher: "Verdi Andrea", start: at(3), end: at(5),
                 tint: tint(0x7C5808, 0xEFBF6A), isTest: true),
            Item(title: "Ricreazione", start: at(3.5), end: at(4), tint: tint(0x9A8C78, 0xB8AC98), isBreak: true),
            Item(title: "Inglese", room: "Lab 1", teacher: "Smith Anna", start: at(5), end: at(7),
                 tint: tint(0x29685F, 0x94D2C7)),
        ]
    }
}
#endif
