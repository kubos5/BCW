import SwiftUI
import WidgetKit

// MARK: - Giorno mostrato

/// Il giorno che i widget dell'orario mostrano a un certo istante, secondo la regola del giorno
/// predefinito (`TimetableDefaultDay`): oggi finché c'è un evento non ancora finito, poi il primo
/// giorno successivo con eventi. Con la lezione in corso e la prossima, come `TimetableNowCard`.
struct TimetableWidgetDay {
    typealias Event = WidgetSnapshot.Event

    let now: Date
    let day: Date
    /// Eventi del giorno in ordine, intervalli compresi.
    let events: [Event]
    let lessons: [Event]
    /// Le lezioni con le ore uguali di seguito unite in una (come le righe dei widget, i gruppi
    /// dell'orario e l'attività in diretta): due ore di Italiano sono "fino alle 12:00", poi la
    /// materia dopo, non "poi Italiano alle 11:00".
    let mergedLessons: [Event]
    let isToday: Bool
    /// Minuto attuale, se il giorno è oggi.
    let minute: Int?
    /// La lezione in corso (ore uguali di seguito unite).
    let current: Event?
    /// La prossima lezione (dopo quella in corso, o la prima del giorno se non è oggi).
    let next: Event?
    let isHoliday: Bool
    /// A che punto è la giornata (`nil` senza lezioni o con la barra spenta in Impostazioni ›
    /// Orario): per un giorno dopo oggi allo 0%.
    let progress: DayProgress?

    init(snapshot: WidgetSnapshot, now: Date) {
        self.now = now
        let day = snapshot.defaultTimetableDay(at: now)
        self.day = day
        events = snapshot.events(on: day).sorted { ($0.start, $0.end, $0.title) < ($1.start, $1.end, $1.title) }
        lessons = events.filter { !$0.isBreak }
        // L'ora unita tiene l'id della prima: `isCurrent(_:)` la ritrova nel suo blocco.
        let merged = TimetableBlock.blocks(lessons).map { block -> Event in
            var event = block.first
            event.end = block.end
            event.room = block.room
            event.teacher = block.teacher
            event.isTest = block.isTest
            event.hasTest = block.events.contains { $0.hasTest == true } ? true : nil
            return event
        }
        mergedLessons = merged
        isToday = BCWShared.calendar.isDate(day, inSameDayAs: now)
        isHoliday = snapshot.isHoliday(day)
        if isToday {
            let minute = BCWShared.minutes(of: now)
            self.minute = minute
            let current = merged.last { $0.start <= minute && minute < $0.end }
            self.current = current
            next = merged.first { $0.start > minute && $0.start >= (current?.end ?? minute) && $0.id != current?.id }
        } else {
            minute = nil
            current = nil
            next = merged.first
        }
        progress = snapshot.showsDayProgress == true
            ? DayProgress(spans: lessons.map { TimetableDefaultDay.Span(start: $0.start, end: $0.end) }, minute: minute ?? 0)
            : nil
    }

    /// Le lezioni dopo quella in evidenza (in corso o prossima), con le ore uguali unite.
    var following: [Event] {
        guard let featured = current ?? next else { return [] }
        return mergedLessons.filter { $0.start >= featured.end && $0.id != featured.id }
    }

    func date(_ minute: Int) -> Date { BCWShared.date(day, minute: minute) }

    /// Intervallo di un evento come date, per i timer e le barre di avanzamento.
    func interval(_ event: Event) -> ClosedRange<Date> {
        let start = date(event.start)
        return start...max(start.addingTimeInterval(60), date(event.end))
    }

    var span: (start: Int, end: Int)? {
        guard let start = events.map(\.start).min(), let end = events.map(\.end).max() else { return nil }
        return (start, end)
    }

    var testCount: Int { lessons.filter(\.isTest).count }

    /// Lezioni del giorno (le ore, come il chip della scheda Orario).
    var lessonCount: Int { lessons.count }

    func isPast(_ block: TimetableBlock) -> Bool {
        guard let minute else { return false }
        return block.end <= minute
    }

    func isCurrent(_ block: TimetableBlock) -> Bool {
        guard let current else { return false }
        return block.events.contains { $0.id == current.id }
    }

    var dayName: String { WidgetDates.relativeName(day, now: now) }

    var summary: String {
        var parts: [String] = []
        let count = lessonCount
        if count > 0 { parts.append(count == 1 ? "1 lezione" : "\(count) lezioni") }
        if let span { parts.append("\(TimeOfDay.string(span.start))–\(TimeOfDay.string(span.end))") }
        return parts.joined(separator: " · ")
    }
}

/// Ore uguali di seguito (stessa materia e colore) unite in una riga, come i gruppi dell'app;
/// gli intervalli restano righe a parte.
struct TimetableBlock: Identifiable {
    let events: [WidgetSnapshot.Event]
    var id: String { events[0].id }
    var first: WidgetSnapshot.Event { events[0] }
    var start: Int { events[0].start }
    var end: Int { events.last!.end }
    var isBreak: Bool { first.isBreak }
    var isTest: Bool { events.contains(where: \.isTest) }
    var title: String { first.title }
    var room: String { events.first { !$0.room.isEmpty }?.room ?? "" }
    var teacher: String { events.first { !$0.teacher.isEmpty }?.teacher ?? "" }
    var timeRange: String { "\(TimeOfDay.string(start))–\(TimeOfDay.string(end))" }

    static func blocks(_ events: [WidgetSnapshot.Event]) -> [TimetableBlock] {
        var result: [[WidgetSnapshot.Event]] = []
        for event in events {
            if !event.isBreak, var last = result.last, let previous = last.last, !previous.isBreak,
               previous.end == event.start, previous.tint == event.tint,
               previous.title.lowercased() == event.title.lowercased() {
                last.append(event)
                result[result.count - 1] = last
            } else {
                result.append([event])
            }
        }
        return result.map(TimetableBlock.init(events:))
    }
}

// MARK: - Widget "Orario"

/// Orario di oggi o, dopo l'ultimo evento, del giorno seguente (come la scheda Orario). In alto il
/// giorno con la barra di avanzamento della giornata, sotto le lezioni in una lista segmentata con
/// quella in corso più alta, nel contenitore primario.
struct TimetableWidgetView: View {
    let snapshot: WidgetSnapshot
    let now: Date
    let family: WidgetFamily
    let palette: WidgetPalette

    var body: some View {
        let day = TimetableWidgetDay(snapshot: snapshot, now: now)
        Group {
            if !snapshot.signedIn {
                WidgetEmptyState(icon: "timetable", title: "Apri BCW per accedere",
                                 message: family == .systemSmall ? nil : "L'orario comparirà qui dopo l'accesso.",
                                 palette: palette)
            } else if !snapshot.hasTimetable {
                WidgetEmptyState(icon: "calendarPlus", title: "Crea il tuo orario",
                                 message: family == .systemSmall ? "Tocca per aprire BCW."
                                     : "Aggiungilo a mano o generalo dalle lezioni nella scheda Orario.",
                                 palette: palette)
            } else if day.lessons.isEmpty {
                WidgetEmptyState(icon: "sun", title: "Nessuna lezione",
                                 message: "Nei prossimi giorni non ci sono lezioni in orario.", palette: palette)
            } else {
                switch family {
                case .systemMedium: TimetableMediumView(day: day, palette: palette)
                case .systemLarge, .systemExtraLarge: TimetableLargeView(day: day, palette: palette)
                default: TimetableSmallView(day: day, palette: palette)
                }
            }
        }
        .widgetURL(DeepLink.timetable(snapshot.signedIn ? day.day : nil).url)
    }
}

// MARK: Avanzamento della giornata

/// Il giorno ("Oggi", "Domani", "Lunedì") e, a destra, a che punto è la giornata, come il giorno in
/// grande della scheda Orario.
private struct TimetableWidgetHeader: View {
    let day: TimetableWidgetDay
    let palette: WidgetPalette
    var titleSize: CGFloat = 24

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(day.dayName)
                .font(palette.font(titleSize, weight: 500, rounded: true))
                .tracking(-0.3)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
            if let progress = day.progress {
                HStack(spacing: 8) {
                    WidgetDayPercent(progress: progress, palette: palette, size: titleSize * 0.62)
                    WidgetLinearProgress(progress: progress, palette: palette)
                }
                .frame(maxWidth: .infinity)
            } else {
                Spacer(minLength: 0)
            }
        }
    }
}

/// "30%": nel colore primario mentre la giornata è in corso.
private struct WidgetDayPercent: View {
    let progress: DayProgress
    let palette: WidgetPalette
    var size: CGFloat = 15

    var body: some View {
        let running = progress.elapsed > 0 && !progress.isFinished
        Text("\(progress.percent)%")
            .font(palette.numeral(size, weight: 650, rounded: true))
            .foregroundStyle(running ? palette.primary : palette.secondaryInk)
            .lineLimit(1)
            .fixedSize()
            .widgetAccentable(running)
            .accessibilityLabel("Giornata al \(progress.percent)%")
    }
}

/// Indicatore lineare di Material 3 Expressive: la parte passata (ondulata mentre la giornata è in
/// corso, come la card "Adesso" dell'app, qui ferma), uno spazio e la traccia con il punto finale.
/// Si aggiorna con le voci della linea temporale (ogni 5 minuti durante le lezioni).
private struct WidgetLinearProgress: View {
    let progress: DayProgress
    let palette: WidgetPalette

    var body: some View {
        let fraction = min(1, max(0, progress.fraction))
        let running = fraction > 0 && fraction < 1
        let active = palette.primary
        let track = palette.isFullColor ? palette.role("secondary-container") : Color.white.opacity(0.25)
        GeometryReader { proxy in
            let width = proxy.size.width
            let gap: CGFloat = running ? 4 : 0
            let filled = fraction >= 1 ? width : max(0, (width - gap) * fraction)
            ZStack(alignment: .leading) {
                if fraction < 1 {
                    Capsule()
                        .fill(track)
                        .frame(width: max(4, width - filled - gap), height: 4)
                        .overlay(alignment: .trailing) {
                            Circle().fill(active).frame(width: 4, height: 4).widgetAccentable()
                        }
                        .offset(x: filled + gap)
                }
                if filled > 0 {
                    Group {
                        if running && filled > 14 {
                            ProgressWave()
                                .stroke(active, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                                .padding(.horizontal, 2)
                                .frame(width: filled, height: 10)
                        } else {
                            Capsule().fill(active).frame(width: filled, height: 4)
                        }
                    }
                    .widgetAccentable()
                }
            }
            .frame(width: width, height: proxy.size.height, alignment: .leading)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// Onda della parte passata dell'indicatore, dal bordo sinistro (le onde dei separatori, invece,
/// sono intere e centrate).
private struct ProgressWave: Shape {
    var amplitude: CGFloat = 2
    var wavelength: CGFloat = 20

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0 else { return path }
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        var x: CGFloat = 0
        while x < rect.width {
            x = min(x + 1, rect.width)
            path.addLine(to: CGPoint(x: rect.minX + x, y: rect.midY - sin(x / wavelength * 2 * .pi) * amplitude))
        }
        return path
    }
}

// MARK: Piccolo

/// Piccolo: il giorno con la percentuale e la barra, la lezione in corso (o la prossima) e quelle
/// dopo; per un altro giorno le prime ore.
private struct TimetableSmallView: View {
    let day: TimetableWidgetDay
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(day.dayName)
                        .font(palette.font(17, weight: 600, rounded: true))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer(minLength: 0)
                    if let progress = day.progress {
                        WidgetDayPercent(progress: progress, palette: palette, size: 13)
                    }
                }
                if let progress = day.progress {
                    WidgetLinearProgress(progress: progress, palette: palette)
                }
            }
            if day.isToday, let featured = day.current ?? day.next {
                ViewThatFits(in: .vertical) {
                    todayContent(featured, titleLines: 2, rows: 2)
                    todayContent(featured, titleLines: 1, rows: 2)
                    todayContent(featured, titleLines: 1, rows: 1)
                    todayContent(featured, titleLines: 1, rows: 0)
                }
            } else {
                otherDay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func todayContent(_ featured: WidgetSnapshot.Event, titleLines: Int, rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            FeaturedLessonCard(event: featured, isCurrent: day.current != nil, titleLines: titleLines, palette: palette)
            ForEach(Array(TimetableBlock.blocks(day.following).prefix(rows))) { block in
                CompactLessonRow(block: block, palette: palette)
            }
        }
    }

    private var otherDay: some View {
        let blocks = TimetableBlock.blocks(day.lessons)
        return ViewThatFits(in: .vertical) {
            ForEach((1...max(1, min(blocks.count, 5))).reversed(), id: \.self) { count in
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(blocks.prefix(count))) { block in
                        CompactLessonRow(block: block, palette: palette, large: true)
                    }
                    if count < blocks.count {
                        Text("+\(blocks.count - count) dopo")
                            .font(palette.font(11, weight: 600))
                            .foregroundStyle(palette.secondaryInk)
                    }
                }
            }
        }
    }
}

/// La lezione in corso (nel contenitore primario, "Adesso") o la prossima (nella sua tinta, con
/// l'ora), nel widget piccolo.
private struct FeaturedLessonCard: View {
    let event: WidgetSnapshot.Event
    let isCurrent: Bool
    var titleLines = 2
    let palette: WidgetPalette

    var body: some View {
        let foreground = isCurrent ? palette.onContainer("primary") : palette.ink
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isCurrent && palette.isFullColor ? palette.onContainer("primary") : palette.tint(event.tint))
                .frame(width: 4)
                .padding(.vertical, 2)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                WidgetEyebrow(text: isCurrent ? "In corso" : "Alle \(TimeOfDay.string(event.start))",
                              color: foreground.opacity(0.75), palette: palette, size: 9.5)
                Text(event.title)
                    .font(palette.font(15, weight: 600, rounded: true))
                    .foregroundStyle(foreground)
                    .lineLimit(titleLines)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(palette.font(11))
                    .foregroundStyle(foreground.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(isCurrent ? palette.container("primary") : palette.eventFill(event.tint),
                    in: .rect(cornerRadius: palette.radii.m, style: .continuous))
    }

    private var detail: String {
        var parts = [isCurrent ? "Fino alle \(TimeOfDay.string(event.end))"
                     : TimeOfDay.string(event.start) + "–" + TimeOfDay.string(event.end)]
        if !event.room.isEmpty { parts.append(event.room) }
        return parts.joined(separator: " · ")
    }
}

/// Riga stretta di una lezione: tinta, ora e materia.
private struct CompactLessonRow: View {
    let block: TimetableBlock
    let palette: WidgetPalette
    var large = false

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(palette.tint(block.first.tint))
                .frame(width: 3, height: large ? 16 : 14)
                .widgetAccentable()
            Text(TimeOfDay.string(block.start))
                .font(palette.numeral(11, weight: 500))
                .foregroundStyle(palette.secondaryInk)
            Text(block.title)
                .font(palette.font(large ? 13 : 12, weight: 600))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            if block.isTest {
                WidgetIcon("test", size: 12)
                    .foregroundStyle(palette.accent)
                    .widgetAccentable()
            }
        }
    }
}

// MARK: Medio e grande

/// Medio: il giorno con l'avanzamento e le lezioni da quella in corso (o dalla prossima).
private struct TimetableMediumView: View {
    let day: TimetableWidgetDay
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TimetableWidgetHeader(day: day, palette: palette, titleSize: 20)
            TimetableRowList(day: day, blocks: blocks, palette: palette, showsHiddenCount: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// Oggi si parte dalla lezione in corso (o dalla prossima): quelle finite (e gli intervalli
    /// passati) non servono più.
    private var blocks: [TimetableBlock] {
        let all = TimetableBlock.blocks(day.events)
        guard day.isToday else { return all }
        let remaining = all.filter { !day.isPast($0) }
        return remaining.contains(where: { !$0.isBreak }) ? remaining : all
    }
}

/// Grande: il giorno con l'avanzamento e la giornata intera, con le lezioni finite sbiadite e la
/// lezione in corso in evidenza.
private struct TimetableLargeView: View {
    let day: TimetableWidgetDay
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimetableWidgetHeader(day: day, palette: palette, titleSize: 26)
            if day.isHoliday {
                WidgetChip(text: "Vacanza", icon: "beach", container: palette.container("tertiary"),
                           foreground: palette.onContainer("tertiary"), palette: palette)
            }
            TimetableRowList(day: day, blocks: TimetableBlock.blocks(day.events), palette: palette)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

/// Elenco delle lezioni in una lista segmentata (2 punti tra una riga e l'altra), con la lezione in
/// corso più alta e in evidenza. Gli intervalli non hanno una riga (più spazio alle lezioni): dove
/// c'era un intervallo, o un'ora libera, la lista si divide in gruppi con un piccolo stacco. Gli
/// angoli esterni dei gruppi sono piccoli (con quelli ampi dell'app le righe sembravano pillole).
/// Mostra le righe che entrano, nello stile più comodo possibile: prima va via lo spazio in più
/// delle righe e la seconda riga di quella in corso, poi le ultime lezioni ("+N altre lezioni").
private struct TimetableRowList: View {
    /// Righe su una riga più alta o stretta.
    enum Style {
        case relaxed, compact

        /// Altezza massima di una riga quando avanza spazio (le righe crescono fin qui).
        var maxHeight: CGFloat { self == .relaxed ? 40 : 30 }
    }

    let day: TimetableWidgetDay
    /// Lezioni e intervalli in ordine (gli intervalli dividono i gruppi).
    let blocks: [TimetableBlock]
    let palette: WidgetPalette
    /// "+N altre lezioni" sotto l'ultima riga (nel medio una riga in più vale di più).
    var showsHiddenCount = true

    /// Stacco tra due gruppi, dove c'era un intervallo.
    private static let groupGap: CGFloat = 5

    private struct Variant: Identifiable {
        let count: Int
        let style: Style
        /// La lezione in corso su due righe (con fino a quando, aula e docente).
        let expandsCurrent: Bool
        let hidden: Int
        var id: String { "\(count)-\(style)-\(expandsCurrent)" }
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            ForEach(variants) { variant in
                list(variant)
            }
        }
    }

    private var lessonCount: Int { blocks.filter { !$0.isBreak }.count }

    private var variants: [Variant] {
        let lessons = lessonCount
        let layouts: [(Style, Bool)] = [(.relaxed, true), (.compact, true), (.compact, false)]
        return (1...max(1, lessons)).reversed().flatMap { count in
            layouts.map { Variant(count: count, style: $0.0, expandsCurrent: $0.1, hidden: lessons - min(count, lessons)) }
        }
    }

    private func list(_ variant: Variant) -> some View {
        let corner = palette.radii.s
        return VStack(alignment: .leading, spacing: Self.groupGap) {
            ForEach(groups(count: variant.count), id: \.first!.id) { group in
                VStack(spacing: 2) {
                    ForEach(Array(group.enumerated()), id: \.element.id) { index, block in
                        TimetableLessonRow(day: day, block: block, palette: palette, style: variant.style,
                                           expandsCurrent: variant.expandsCurrent,
                                           corners: (index == 0 ? corner : palette.radii.xs,
                                                     index == group.count - 1 ? corner : palette.radii.xs))
                    }
                }
            }
            if variant.hidden > 0, showsHiddenCount {
                Text(variant.hidden == 1 ? "+1 altra lezione" : "+\(variant.hidden) altre lezioni")
                    .font(palette.font(11, weight: 600))
                    .foregroundStyle(palette.secondaryInk)
                    .padding(.leading, 4)
            }
        }
    }

    /// Le prime `count` lezioni in gruppi: un intervallo, o più di 5 minuti tra una lezione e la
    /// successiva, chiudono il gruppo.
    private func groups(count: Int) -> [[TimetableBlock]] {
        var groups: [[TimetableBlock]] = []
        var current: [TimetableBlock] = []
        var shown = 0
        for block in blocks {
            if block.isBreak {
                if !current.isEmpty { groups.append(current) }
                current = []
                continue
            }
            guard shown < count else { break }
            if let previous = current.last, block.start > previous.end + 5 {
                groups.append(current)
                current = []
            }
            current.append(block)
            shown += 1
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
}

/// Riga di una lezione come nella lista della scheda Orario: ora, tinta e materia (con l'aula).
/// Quella in corso sta nel contenitore primario, più alta, con "In corso" a destra e sotto la
/// materia fino a quando, l'aula e il docente; quelle finite sono sbiadite.
private struct TimetableLessonRow: View {
    let day: TimetableWidgetDay
    let block: TimetableBlock
    let palette: WidgetPalette
    let style: TimetableRowList.Style
    var expandsCurrent = true
    let corners: (top: CGFloat, bottom: CGFloat)

    var body: some View {
        let isCurrent = day.isCurrent(block)
        let expanded = isCurrent && expandsCurrent
        let foreground = isCurrent ? palette.onContainer("primary") : palette.ink
        let secondary = isCurrent ? palette.onContainer("primary").opacity(0.8) : palette.secondaryInk
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(TimeOfDay.string(block.start))
                    .font(palette.numeral(13, weight: 650))
                    .foregroundStyle(foreground)
                if expanded {
                    Text(TimeOfDay.string(block.end))
                        .font(palette.numeral(11, weight: 450))
                        .foregroundStyle(secondary)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .frame(width: 42, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.tint(block.first.tint))
                .frame(width: 4)
                .frame(maxHeight: expanded ? 30 : (style == .relaxed ? 18 : 16))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                if isCurrent {
                    // "In corso" solo se entra per intero: prima va via l'aula, poi l'etichetta (la
                    // riga in evidenza basta a dirlo).
                    ViewThatFits(in: .horizontal) {
                        titleLine(foreground: foreground, secondary: secondary, showsRoom: !expanded, showsBadge: true)
                        titleLine(foreground: foreground, secondary: secondary, showsRoom: false, showsBadge: true)
                        titleLine(foreground: foreground, secondary: secondary, showsRoom: false, showsBadge: false)
                    }
                } else {
                    titleLine(foreground: foreground, secondary: secondary, showsRoom: true, showsBadge: true)
                }
                if expanded {
                    Text(currentDetail)
                        .font(palette.font(11.5))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, expanded ? 9 : (style == .relaxed ? 8 : 5))
        .padding(.leading, 4)
        .padding(.trailing, 10)
        // Lo spazio che avanza si divide tra le righe, fino a un'altezza comoda.
        .frame(maxHeight: expanded ? 60 : style.maxHeight)
        .background(isCurrent ? palette.container("primary") : palette.eventFill(block.first.tint),
                    in: UnevenRoundedRectangle(topLeadingRadius: corners.top, bottomLeadingRadius: corners.bottom,
                                               bottomTrailingRadius: corners.bottom, topTrailingRadius: corners.top,
                                               style: .continuous))
        .opacity(day.isPast(block) && !isCurrent ? 0.55 : 1)
    }

    /// Materia (con l'aula) e, a destra, "In corso" o l'icona della verifica.
    private func titleLine(foreground: Color, secondary: Color, showsRoom: Bool, showsBadge: Bool) -> some View {
        HStack(spacing: 6) {
            Text(block.title)
                .font(palette.font(day.isCurrent(block) && expandsCurrent ? 15 : (style == .compact ? 13 : 14), weight: 600))
                .foregroundStyle(foreground)
                .lineLimit(1)
            if showsRoom, !block.room.isEmpty {
                Text(block.room)
                    .font(palette.font(11))
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 0)
            if block.isTest {
                WidgetIcon("test", size: 13)
                    .foregroundStyle(day.isCurrent(block) ? foreground : palette.accent)
                    .widgetAccentable()
            }
            if showsBadge, day.isCurrent(block) {
                currentChip
            }
        }
    }

    /// Chip "In corso" pieno nel colore primario, come i chip di stato dell'app.
    private var currentChip: some View {
        Text("In corso")
            .font(palette.font(11, weight: 650))
            .foregroundStyle(palette.isFullColor ? palette.role("on-primary") : .white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(palette.isFullColor ? palette.role("primary") : Color.white.opacity(0.22), in: .capsule)
            .widgetAccentable()
    }

    private var currentDetail: String {
        var parts = ["Fino alle \(TimeOfDay.string(block.end))"]
        parts += [block.room, block.teacher].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}
