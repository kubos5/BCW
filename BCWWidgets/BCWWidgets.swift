import AppIntents
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

// MARK: - Modifica widget

/// Lo sfondo in "Modifica widget" (tieni premuto il widget).
nonisolated enum WidgetBackgroundOption: String, AppEnum {
    case system, theme

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sfondo")
    static let caseDisplayRepresentations: [WidgetBackgroundOption: DisplayRepresentation] = [
        .system: "Predefinito",
        .theme: "Colore del tema",
    ]

    var style: WidgetBackgroundStyle { self == .theme ? .theme : .system }
}

/// Le opzioni di ogni widget di BCW (nei widget della schermata di blocco lo sfondo lo decide iOS).
nonisolated struct BCWWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Widget di BCW"
    static let description = IntentDescription("Sceglie lo sfondo del widget: quello predefinito, che segue il tema chiaro o scuro di iOS, o il colore del tema di BCW.")

    @Parameter(title: "Sfondo", default: .system)
    var background: WidgetBackgroundOption

    init() {}
}

// MARK: - Widget

/// Un widget di BCW: nome, descrizione e dimensioni vengono da `BCWWidgetKind`. WidgetKit vuole
/// un tipo per widget (creato con `init()`), quindi ognuno indica solo il suo `BCWWidgetKind`.
protocol BCWKindWidget: Widget {
    static var widgetKind: BCWWidgetKind { get }
}

extension BCWKindWidget {
    var body: some WidgetConfiguration {
        let kind = Self.widgetKind
        return AppIntentConfiguration(kind: kind.kind, intent: BCWWidgetIntent.self, provider: BCWTimelineProvider(kind: kind)) { entry in
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
nonisolated struct BCWTimelineProvider: AppIntentTimelineProvider {
    let kind: BCWWidgetKind

    func placeholder(in context: Context) -> BCWWidgetEntry {
        BCWWidgetEntry(date: Date(), snapshot: .sample())
    }

    func snapshot(for configuration: BCWWidgetIntent, in context: Context) async -> BCWWidgetEntry {
        let now = Date()
        let stored = WidgetSnapshot.load()
        let snapshot = context.isPreview && stored?.signedIn != true ? .sample(now: now) : stored ?? WidgetSnapshot()
        return BCWWidgetEntry(date: now, snapshot: snapshot, background: configuration.background.style)
    }

    func timeline(for configuration: BCWWidgetIntent, in context: Context) async -> Timeline<BCWWidgetEntry> {
        #if DEBUG
        WidgetProbe.bump("probeTimelines")
        #endif
        let now = Date()
        let snapshot = WidgetSnapshot.load() ?? WidgetSnapshot()
        let entries = kind.timelineDates(snapshot: snapshot, now: now).map {
            BCWWidgetEntry(date: $0, snapshot: snapshot, background: configuration.background.style)
        }
        // Dopo l'ultima voce (la seconda mezzanotte) WidgetKit chiede una nuova linea temporale.
        return Timeline(entries: entries, policy: .atEnd)
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
        #if DEBUG
        let _ = WidgetProbe.bump("probeRenders")
        #endif
        let palette = WidgetPalette(theme: entry.snapshot.theme, colorScheme: colorScheme, look: WidgetLook(renderingMode),
                                    background: entry.background)
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
