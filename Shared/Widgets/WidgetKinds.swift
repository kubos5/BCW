import SwiftUI
import WidgetKit

/// I widget di BCW: nome, descrizione, dimensioni, contenuto, sfondo e istanti in cui cambiano.
/// Li usano sia l'estensione (`BCWWidgets`) sia la galleria di prova dell'app (solo DEBUG), così
/// le viste sono le stesse.
nonisolated enum BCWWidgetKind: String, CaseIterable, Identifiable, Sendable {
    case timetable, now, agenda, average, nextTest

    var id: String { rawValue }

    /// Identificativo per WidgetKit (non va cambiato: i widget già aggiunti lo usano).
    var kind: String { "com.bcw-classeviva.widget.\(rawValue)" }

    var displayName: String {
        switch self {
        case .timetable: "Orario"
        case .now: "Lezione in corso"
        case .agenda: "Compiti e verifiche"
        case .average: "Media"
        case .nextTest: "Prossima verifica"
        }
    }

    var description: String {
        switch self {
        case .timetable: "L'orario di oggi e, finite le lezioni, quello del giorno seguente."
        case .now: "La lezione in corso con il tempo che manca, poi la successiva."
        case .agenda: "I prossimi compiti, verifiche ed eventi, giorno per giorno."
        case .average: "La media generale e quella del periodo in corso."
        case .nextTest: "La prossima verifica con il conto alla rovescia."
        }
    }

    var families: [WidgetFamily] {
        switch self {
        case .timetable: [.systemSmall, .systemMedium, .systemLarge]
        case .now: [.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline]
        case .agenda: [.systemMedium, .systemLarge]
        case .average: [.systemSmall, .accessoryCircular, .accessoryInline]
        case .nextTest: [.systemSmall, .accessoryRectangular, .accessoryInline]
        }
    }

    @MainActor @ViewBuilder
    func content(snapshot: WidgetSnapshot, now: Date, family: WidgetFamily, palette: WidgetPalette) -> some View {
        switch self {
        case .timetable: TimetableWidgetView(snapshot: snapshot, now: now, family: family, palette: palette)
        case .now: NowWidgetView(snapshot: snapshot, now: now, family: family, palette: palette)
        case .agenda: AgendaWidgetView(snapshot: snapshot, now: now, family: family, palette: palette)
        case .average: AverageWidgetView(snapshot: snapshot, now: now, family: family, palette: palette)
        case .nextTest: NextTestWidgetView(snapshot: snapshot, now: now, family: family, palette: palette)
        }
    }

    /// Sfondo del widget nella schermata Home (con le icone colorate o trasparenti lo toglie iOS).
    @MainActor
    func background(_ palette: WidgetPalette, snapshot: WidgetSnapshot) -> Color {
        switch self {
        case .now where snapshot.signedIn: NowWidgetView.background(palette)
        case .nextTest where snapshot.signedIn: NextTestWidgetView.background(palette)
        default: palette.background
        }
    }

    // MARK: Linea temporale

    /// Istanti in cui il widget cambia: adesso, l'inizio e la fine di ogni evento dell'orario
    /// (così la lezione in corso e il cambio di giorno arrivano all'ora giusta) e le mezzanotti.
    /// Dopo l'ultimo WidgetKit chiede una nuova linea temporale.
    func timelineDates(snapshot: WidgetSnapshot, now: Date) -> [Date] {
        let calendar = BCWShared.calendar
        let today = calendar.startOfDay(for: now)
        var dates: Set<Date> = []
        for offset in 1...2 {
            if let midnight = calendar.date(byAdding: .day, value: offset, to: today) { dates.insert(midnight) }
        }
        if self == .timetable || self == .now, snapshot.signedIn {
            for offset in 0...2 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                for event in snapshot.events(on: day) {
                    dates.insert(BCWShared.date(day, minute: event.start))
                    dates.insert(BCWShared.date(day, minute: event.end))
                }
            }
        }
        let future = dates.filter { $0 > now }.sorted().prefix(120)
        return [now] + future
    }
}

/// Voce della linea temporale: l'istante e l'istantanea da mostrare.
nonisolated struct BCWWidgetEntry: TimelineEntry, Sendable {
    let date: Date
    let snapshot: WidgetSnapshot
}

extension WidgetFamily {
    /// Accessori della schermata di blocco (senza sfondo proprio).
    nonisolated var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: true
        default: false
        }
    }
}
