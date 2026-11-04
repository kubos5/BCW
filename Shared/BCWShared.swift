import Foundation

/// Valori comuni all'app e all'estensione dei widget (cartella `Shared`, compilata in entrambi i
/// target): App Group, schema dei collegamenti e calendario.
nonisolated enum BCWShared {
    /// App Group condiviso con l'estensione dei widget (istantanea dei dati in `Widgets/`).
    static let appGroup = "group.com.bcw-classeviva.app"
    /// Schema dei collegamenti che aprono l'app (`bcw://orario?giorno=2026-10-21`).
    static let urlScheme = "bcw"

    /// Calendario dell'app: gregoriano, in italiano, ora di Roma, settimana dal lunedì. È lo stesso
    /// di `CVDate.calendar`, così app e widget vedono gli stessi giorni e gli stessi minuti.
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "it_IT")
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        cal.firstWeekday = 2
        return cal
    }()

    /// Chiave di un giorno, `yyyy-MM-dd` (come `CVDate.dayKey`).
    static func dayKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Giorno di una chiave `yyyy-MM-dd` (inizio della giornata).
    static func day(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// Minuti dalla mezzanotte.
    static func minutes(of date: Date) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// L'istante di un giorno a un certo minuto (ora dell'orologio: nei giorni del cambio dell'ora
    /// le 8:00 restano le 8:00, mentre sommare 480 minuti alla mezzanotte darebbe le 7:00 o le 9:00).
    /// 24:00 è la mezzanotte successiva.
    static func date(_ day: Date, minute: Int) -> Date {
        let start = calendar.startOfDay(for: day)
        let minute = min(max(minute, 0), 24 * 60)
        if minute == 24 * 60 { return calendar.date(byAdding: .day, value: 1, to: start) ?? start }
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: start)
            ?? start.addingTimeInterval(TimeInterval(minute * 60))
    }

    /// Giorno della settimana dell'orario: 1 = lunedì … 7 = domenica.
    static func weekday(of date: Date) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7 + 1
    }
}

// MARK: - Giorno predefinito dell'orario

/// Il giorno che l'orario mostra da solo (scheda Orario all'apertura e widget "Orario" e "Lezione
/// in corso"). È la stessa regola della versione web:
/// - se oggi c'è almeno un evento dell'orario non ancora finito (fine dopo adesso), oggi;
/// - altrimenti (eventi di oggi tutti finiti, o nessun evento oggi) il primo giorno successivo
///   con eventi, cercando fino a 7 giorni avanti; se non ce n'è nessuno resta oggi.
/// Contano gli eventi dell'orario dell'utente (non gli intervalli, né le verifiche di Classeviva).
/// Il pulsante "Oggi" porta sempre a oggi.
nonisolated enum TimetableDefaultDay {
    /// Inizio e fine di un evento, in minuti dalla mezzanotte.
    struct Span: Equatable, Sendable {
        let start: Int
        let end: Int
    }

    /// Giorni successivi in cui cercare.
    static let lookahead = 7

    /// - Parameters:
    ///   - now: adesso.
    ///   - nowMinute: il minuto attuale del giorno (l'app lo passa da `TimeOfDay.nowMinutes`, che
    ///     nelle prove si può spostare).
    ///   - spans: gli eventi dell'orario di un giorno (inizio della giornata), senza intervalli.
    static func day(now: Date, nowMinute: Int? = nil, calendar: Calendar = BCWShared.calendar,
                    spans: (Date) -> [Span]) -> Date {
        let today = calendar.startOfDay(for: now)
        let minute = nowMinute ?? BCWShared.minutes(of: now)
        if spans(today).contains(where: { $0.end > minute }) { return today }
        for offset in 1...lookahead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if !spans(day).isEmpty { return day }
        }
        return today
    }
}

// MARK: - Avanzamento della giornata

/// A che punto è la giornata dell'orario (barra accanto al giorno in grande nella scheda Orario e
/// nei widget "Orario"): la parte già passata della durata complessiva degli eventi. Con 5 ore di
/// lezione e un'ora e mezza passata, il 30%. Gli eventi sovrapposti contano una volta sola; negli
/// spazi tra un evento e l'altro (intervalli, ore libere) l'avanzamento resta fermo. Come per il
/// giorno predefinito contano gli eventi dell'utente, non gli intervalli.
nonisolated struct DayProgress: Equatable, Sendable {
    /// Minuti degli eventi passati e durata complessiva (sempre più di zero).
    let elapsed: Int
    let total: Int
    /// Gli eventi uniti dove si toccano o si sovrappongono (tratti in cui l'avanzamento cresce).
    let blocks: [TimetableDefaultDay.Span]

    /// - Parameters:
    ///   - spans: gli eventi del giorno, senza intervalli.
    ///   - minute: il minuto attuale per oggi; per un giorno passato 24 × 60, per uno futuro 0.
    /// - Returns: `nil` se il giorno non ha eventi.
    init?(spans: [TimetableDefaultDay.Span], minute: Int) {
        var merged: [TimetableDefaultDay.Span] = []
        for span in spans.filter({ $0.end > $0.start }).sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1] = .init(start: last.start, end: max(last.end, span.end))
            } else {
                merged.append(span)
            }
        }
        let total = merged.reduce(0) { $0 + $1.end - $1.start }
        guard total > 0 else { return nil }
        self.total = total
        elapsed = merged.reduce(0) { $0 + max(0, min($1.end, minute) - $1.start) }
        blocks = merged
    }

    var fraction: Double { Double(elapsed) / Double(total) }
    /// Percentuale per difetto: il 100% solo a giornata finita.
    var percent: Int { elapsed * 100 / total }
    var isFinished: Bool { elapsed >= total }
}

// MARK: - Collegamenti

/// Collegamenti `bcw://` con cui i widget aprono l'app su una scheda e un giorno.
nonisolated enum DeepLink: Equatable, Sendable {
    case dashboard(Date?)
    case timetable(Date?)
    case grades

    var url: URL {
        var components = URLComponents()
        components.scheme = BCWShared.urlScheme
        switch self {
        case let .dashboard(day):
            components.host = "dashboard"
            if let day { components.queryItems = [URLQueryItem(name: "giorno", value: BCWShared.dayKey(day))] }
        case let .timetable(day):
            components.host = "orario"
            if let day { components.queryItems = [URLQueryItem(name: "giorno", value: BCWShared.dayKey(day))] }
        case .grades:
            components.host = "voti"
        }
        return components.url ?? URL(string: "\(BCWShared.urlScheme)://dashboard")!
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == BCWShared.urlScheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let day = components.queryItems?.first { $0.name == "giorno" }?.value.flatMap(BCWShared.day(fromKey:))
        switch components.host?.lowercased() {
        case "dashboard": self = .dashboard(day)
        case "orario": self = .timetable(day)
        case "voti": self = .grades
        default: return nil
        }
    }
}
