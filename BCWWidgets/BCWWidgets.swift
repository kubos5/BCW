import SwiftUI
import WidgetKit

/// Estensione dei widget e dell'attività in diretta di BCW. Le viste, i tipi e la linea temporale sono nella cartella
/// `Shared` (compilata anche nell'app, per la galleria di prova); qui solo ciò che serve a
/// WidgetKit: l'elenco dei widget e il fornitore delle voci, che legge l'istantanea scritta
/// dall'app nel contenitore dell'App Group (`WidgetSnapshot.load`).
@main
struct BCWWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TimetableWidget()
        NowWidget()
        AgendaWidget()
        NextTestWidget()
        AverageWidget()
        TimetableLiveActivity()
    }
}

/// Un widget di BCW: nome, descrizione e dimensioni vengono da `BCWWidgetKind`. WidgetKit vuole
/// un tipo per widget (creato con `init()`), quindi ognuno indica solo il suo `BCWWidgetKind`.
protocol BCWKindWidget: Widget {
    static var widgetKind: BCWWidgetKind { get }
}

extension BCWKindWidget {
    var body: some WidgetConfiguration {
        let kind = Self.widgetKind
        return StaticConfiguration(kind: kind.kind, provider: BCWTimelineProvider(kind: kind)) { entry in
            BCWWidgetEntryView(kind: kind, entry: entry)
        }
        .configurationDisplayName(kind.displayName)
        .description(kind.description)
        .supportedFamilies(kind.families)
    }
}

struct TimetableWidget: BCWKindWidget { static let widgetKind = BCWWidgetKind.timetable }
struct NowWidget: BCWKindWidget { static let widgetKind = BCWWidgetKind.now }
struct AgendaWidget: BCWKindWidget { static let widgetKind = BCWWidgetKind.agenda }
struct NextTestWidget: BCWKindWidget { static let widgetKind = BCWWidgetKind.nextTest }
struct AverageWidget: BCWKindWidget { static let widgetKind = BCWWidgetKind.average }

/// Voci della linea temporale: l'istantanea dell'app a ogni istante in cui il widget cambia
/// (inizio e fine degli eventi dell'orario, mezzanotte). Senza istantanea i widget invitano ad
/// aprire l'app; nella galleria dei widget di iOS, senza dati veri, si vede l'esempio.
nonisolated struct BCWTimelineProvider: TimelineProvider {
    let kind: BCWWidgetKind

    func placeholder(in context: Context) -> BCWWidgetEntry {
        BCWWidgetEntry(date: Date(), snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (BCWWidgetEntry) -> Void) {
        let now = Date()
        let stored = WidgetSnapshot.load()
        let snapshot = context.isPreview && stored?.signedIn != true ? .sample(now: now) : stored ?? WidgetSnapshot()
        completion(BCWWidgetEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BCWWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load() ?? WidgetSnapshot()
        let entries = kind.timelineDates(snapshot: snapshot, now: now).map { BCWWidgetEntry(date: $0, snapshot: snapshot) }
        // Dopo l'ultima voce (la seconda mezzanotte) WidgetKit chiede una nuova linea temporale.
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Contenuto e sfondo del widget, con i colori del tema secondo l'aspetto (chiaro o scuro) e la
/// modalità di resa (a colori, icone colorate o trasparenti, schermata di blocco).
struct BCWWidgetEntryView: View {
    let kind: BCWWidgetKind
    let entry: BCWWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let palette = WidgetPalette(theme: entry.snapshot.theme, colorScheme: colorScheme, look: WidgetLook(renderingMode))
        kind.content(snapshot: entry.snapshot, now: entry.date, family: family, palette: palette)
            .containerBackground(for: .widget) {
                if family.isAccessory {
                    Color.clear
                } else {
                    kind.background(palette)
                }
            }
    }
}
