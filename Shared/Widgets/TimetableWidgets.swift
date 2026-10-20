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
    let isToday: Bool
    /// Minuto attuale, se il giorno è oggi.
    let minute: Int?
    let current: Event?
    /// La prossima lezione (dopo quella in corso, o la prima del giorno se non è oggi).
    let next: Event?
    let isHoliday: Bool

    init(snapshot: WidgetSnapshot, now: Date) {
        self.now = now
        let day = snapshot.defaultTimetableDay(at: now)
        self.day = day
        events = snapshot.events(on: day).sorted { ($0.start, $0.end, $0.title) < ($1.start, $1.end, $1.title) }
        lessons = events.filter { !$0.isBreak }
        isToday = BCWShared.calendar.isDate(day, inSameDayAs: now)
        isHoliday = snapshot.isHoliday(day)
        if isToday {
            let minute = BCWShared.minutes(of: now)
            self.minute = minute
            let current = lessons.last { $0.start <= minute && minute < $0.end }
            self.current = current
            next = lessons.first { $0.start > minute && $0.start >= (current?.end ?? minute) && $0.id != current?.id }
        } else {
            minute = nil
            current = nil
            next = lessons.first
        }
    }

    /// Le lezioni dopo quella in evidenza (in corso o prossima).
    var following: [Event] {
        guard let featured = current ?? next else { return [] }
        return lessons.filter { $0.start >= featured.end && $0.id != featured.id }
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

    /// Lezioni del giorno contando una volta le ore uguali di seguito.
    var lessonCount: Int { TimetableBlock.blocks(lessons).count }

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

/// Orario di oggi o, dopo l'ultimo evento, del giorno seguente (come la scheda Orario).
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
                case .systemMedium: TimetableMediumView(day: day, snapshot: snapshot, palette: palette)
                case .systemLarge, .systemExtraLarge: TimetableLargeView(day: day, snapshot: snapshot, palette: palette)
                default: TimetableSmallView(day: day, palette: palette)
                }
            }
        }
        .widgetURL(DeepLink.timetable(snapshot.signedIn ? day.day : nil).url)
    }
}

/// Piccolo: la lezione in corso (o la prossima) e quelle dopo; per un altro giorno, le prime ore.
private struct TimetableSmallView: View {
    let day: TimetableWidgetDay
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                WidgetEyebrow(text: day.dayName, color: palette.accent, palette: palette)
                    .widgetAccentable()
                Spacer(minLength: 0)
                if day.testCount > 0 {
                    WidgetIcon("test", size: 14)
                        .foregroundStyle(palette.accent)
                        .widgetAccentable()
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
        VStack(alignment: .leading, spacing: 6) {
            FeaturedLessonCard(day: day, event: featured, isCurrent: day.current != nil, titleLines: titleLines,
                               palette: palette)
            ForEach(Array(TimetableBlock.blocks(day.following).prefix(rows))) { block in
                CompactLessonRow(block: block, palette: palette)
            }
        }
    }

    private var otherDay: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(day.summary)
                .font(palette.font(11.5, weight: 500))
                .foregroundStyle(palette.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            let blocks = TimetableBlock.blocks(day.lessons)
            ViewThatFits(in: .vertical) {
                ForEach((1...max(1, min(blocks.count, 5))).reversed(), id: \.self) { count in
                    VStack(alignment: .leading, spacing: 4) {
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
}

/// La lezione in corso (nel contenitore primario, con l'avanzamento) o la prossima (nella sua tinta).
private struct FeaturedLessonCard: View {
    let day: TimetableWidgetDay
    let event: WidgetSnapshot.Event
    let isCurrent: Bool
    var titleLines = 2
    let palette: WidgetPalette

    var body: some View {
        let foreground = isCurrent ? palette.onContainer("primary") : palette.ink
        HStack(spacing: 8) {
            if !isCurrent {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(palette.tint(event.tint))
                    .frame(width: 4)
                    .widgetAccentable()
            }
            VStack(alignment: .leading, spacing: 2) {
                WidgetEyebrow(text: isCurrent ? "Adesso" : "Alle \(TimeOfDay.string(event.start))",
                              color: foreground.opacity(0.75), palette: palette, size: 10)
                Text(event.title)
                    .font(palette.font(16, weight: 600, rounded: true))
                    .foregroundStyle(foreground)
                    .lineLimit(titleLines)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(palette.font(11))
                    .foregroundStyle(foreground.opacity(0.8))
                    .lineLimit(1)
                if isCurrent {
                    ProgressView(timerInterval: day.interval(event), countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(palette.isFullColor ? palette.onContainer("primary") : palette.accent)
                    .widgetAccentable()
                    .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, isCurrent ? 10 : 6)
        .padding(.vertical, 7)
        .background(isCurrent ? palette.container("primary") : palette.eventFill(event.tint),
                    in: .rect(cornerRadius: palette.radii.l, style: .continuous))
    }

    private var detail: String {
        var parts = [isCurrent ? "Fino alle \(TimeOfDay.string(event.end))" : TimeOfDay.string(event.start) + "–" + TimeOfDay.string(event.end)]
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

// MARK: Medio

/// Medio: a sinistra il giorno in grande con i chip, a destra le lezioni (da quella in corso).
private struct TimetableMediumView: View {
    let day: TimetableWidgetDay
    let snapshot: WidgetSnapshot
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            TimetableDayHeading(day: day, snapshot: snapshot, palette: palette, compact: true)
                .frame(width: 112, alignment: .leading)
            TimetableRowList(day: day, blocks: blocks, palette: palette, styles: [.regular, .relaxed, .compact],
                             showsBreaks: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// Oggi si parte dalla lezione in corso (o dalla prossima): quelle finite non servono più.
    private var blocks: [TimetableBlock] {
        let all = TimetableBlock.blocks(day.lessons)
        guard day.isToday else { return all }
        let remaining = all.filter { !day.isPast($0) }
        return remaining.isEmpty ? all : remaining
    }
}

/// Il giorno in grande (come nella scheda Orario) con i chip di lezioni, orario e verifiche.
private struct TimetableDayHeading: View {
    let day: TimetableWidgetDay
    let snapshot: WidgetSnapshot
    let palette: WidgetPalette
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 2) {
            Text(day.dayName)
                .font(palette.font(compact ? 26 : 30, weight: 500, rounded: true))
                .tracking(-0.4)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(dateLine)
                .font(palette.font(compact ? 12 : 13, weight: 500))
                .foregroundStyle(palette.secondaryInk)
                .lineLimit(compact ? 2 : 1)
            if compact {
                Spacer(minLength: 6)
                chips
            }
        }
    }

    private var dateLine: String {
        let relative = WidgetDates.offset(of: day.day, from: day.now)
        return (0...1).contains(relative) ? WidgetDates.long(day.day) : WidgetDates.dayMonth(day.day)
    }

    @ViewBuilder
    var chips: some View {
        VStack(alignment: .leading, spacing: 4) {
            let count = day.lessonCount
            WidgetChip(text: count == 1 ? "1 lezione" : "\(count) lezioni", icon: "bookText",
                       container: palette.container("secondary"), foreground: palette.onContainer("secondary"),
                       palette: palette)
            if let span = day.span {
                WidgetChip(text: "\(TimeOfDay.string(span.start))–\(TimeOfDay.string(span.end))", icon: "schedule",
                           container: palette.cardHigh, foreground: palette.secondaryInk, palette: palette)
            }
            if day.testCount > 0 {
                WidgetChip(text: day.testCount == 1 ? "1 verifica" : "\(day.testCount) verifiche", icon: "test",
                           container: palette.container("tertiary"), foreground: palette.onContainer("tertiary"),
                           palette: palette)
                    .widgetAccentable()
            } else if day.isHoliday {
                WidgetChip(text: "Vacanza", icon: "beach", container: palette.container("tertiary"),
                           foreground: palette.onContainer("tertiary"), palette: palette)
            } else if snapshot.isDemo && !compact {
                WidgetChip(text: "Demo", container: palette.cardHigh, foreground: palette.secondaryInk, palette: palette)
            }
        }
    }
}

/// Elenco delle lezioni in una lista segmentata (angoli ampi solo in cima e in fondo, 2 punti tra
/// una riga e l'altra), con la lezione in corso in evidenza. Mostra le righe che entrano, nello
/// stile più comodo possibile, con "+N" per quelle che restano fuori.
private struct TimetableRowList: View {
    /// Righe su due righe (con aula e docente), su una riga più alta, o su una riga stretta.
    enum Style {
        case regular, relaxed, compact
        var isOneLine: Bool { self != .regular }
    }

    let day: TimetableWidgetDay
    let blocks: [TimetableBlock]
    let palette: WidgetPalette
    let styles: [Style]
    var showsBreaks = true
    var showsProgress = false

    private struct Variant: Identifiable {
        let style: Style
        let count: Int
        var id: String { "\(style)-\(count)" }
    }

    private var lessonCount: Int { blocks.filter { !$0.isBreak }.count }

    var body: some View {
        let shown = showsBreaks ? blocks : blocks.filter { !$0.isBreak }
        // Prima più righe possibile; a parità di righe lo stile più comodo.
        let variants = (1...max(1, shown.count)).reversed().flatMap { count in
            styles.map { Variant(style: $0, count: count) }
        }
        ViewThatFits(in: .vertical) {
            ForEach(variants) { variant in
                list(Array(shown.prefix(variant.count)), style: variant.style, hidden: shown.count - variant.count)
            }
        }
    }

    private func list(_ rows: [TimetableBlock], style: Style, hidden: Int) -> some View {
        VStack(alignment: .leading, spacing: style == .compact ? 4 : 6) {
            // Le lezioni di seguito formano gruppi; gli intervalli li separano.
            ForEach(groups(rows), id: \.first!.id) { group in
                if group.count == 1, group[0].isBreak {
                    TimetableBreakRow(block: group[0], palette: palette, compact: style == .compact)
                } else {
                    VStack(spacing: 2) {
                        ForEach(Array(group.enumerated()), id: \.element.id) { index, block in
                            TimetableLessonRow(day: day, block: block, palette: palette, style: style,
                                               showsProgress: showsProgress,
                                               corners: (index == 0 ? palette.radii.li : palette.radii.xs,
                                                         index == group.count - 1 ? palette.radii.li : palette.radii.xs))
                        }
                    }
                }
            }
            if hidden > 0 {
                let hiddenLessons = Set(blocks.filter { !$0.isBreak }.map(\.id)).subtracting(rows.map(\.id)).count
                Text(hiddenLessons == 1 ? "+1 altra lezione" : "+\(max(hiddenLessons, 1)) altre lezioni")
                    .font(palette.font(11, weight: 600))
                    .foregroundStyle(palette.secondaryInk)
                    .padding(.leading, 4)
            }
        }
    }

    private func groups(_ rows: [TimetableBlock]) -> [[TimetableBlock]] {
        var groups: [[TimetableBlock]] = []
        for row in rows {
            if row.isBreak {
                groups.append([row])
            } else if let last = groups.last, let previous = last.last, !previous.isBreak, row.start <= previous.end + 5 {
                groups[groups.count - 1].append(row)
            } else {
                groups.append([row])
            }
        }
        return groups
    }
}

/// Riga di una lezione: ora, tinta, materia e aula; quella in corso nel contenitore primario.
private struct TimetableLessonRow: View {
    let day: TimetableWidgetDay
    let block: TimetableBlock
    let palette: WidgetPalette
    let style: TimetableRowList.Style
    var showsProgress = false
    let corners: (top: CGFloat, bottom: CGFloat)

    var body: some View {
        let isCurrent = day.isCurrent(block)
        let isPast = day.isPast(block)
        let foreground = isCurrent ? palette.onContainer("primary") : palette.ink
        let secondary = isCurrent ? palette.onContainer("primary").opacity(0.8) : palette.secondaryInk
        HStack(alignment: style == .regular ? .top : .center, spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                Text(TimeOfDay.string(block.start))
                    .font(palette.numeral(style == .regular ? 13 : 12, weight: 650))
                    .foregroundStyle(foreground)
                if style == .regular {
                    Text(TimeOfDay.string(block.end))
                        .font(palette.numeral(10.5, weight: 450))
                        .foregroundStyle(secondary)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .frame(width: 40, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(palette.tint(block.first.tint))
                .frame(width: 4)
                .frame(maxHeight: style == .regular ? 28 : (style == .relaxed ? 18 : 16))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(block.title)
                        .font(palette.font(style == .compact ? 13 : 14, weight: 600))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                    if style.isOneLine, !block.room.isEmpty {
                        Text(block.room)
                            .font(palette.font(11))
                            .foregroundStyle(secondary)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                    Spacer(minLength: 0)
                    if isCurrent {
                        WidgetEyebrow(text: "In corso", color: foreground, palette: palette, size: 9.5)
                    } else if block.isTest {
                        WidgetIcon("test", size: 13)
                            .foregroundStyle(palette.accent)
                            .widgetAccentable()
                    }
                }
                if style == .regular {
                    Text(detail)
                        .font(palette.font(11))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
                if showsProgress && isCurrent && style == .regular {
                    ProgressView(timerInterval: day.date(block.start)...day.date(block.end), countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(palette.isFullColor ? palette.onContainer("primary") : palette.accent)
                    .widgetAccentable()
                    .padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, style == .regular ? 7 : (style == .relaxed ? 8 : 5))
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .background(isCurrent ? palette.container("primary") : palette.eventFill(block.first.tint),
                    in: UnevenRoundedRectangle(topLeadingRadius: corners.top, bottomLeadingRadius: corners.bottom,
                                               bottomTrailingRadius: corners.bottom, topTrailingRadius: corners.top,
                                               style: .continuous))
        .opacity(isPast && !isCurrent ? 0.55 : 1)
    }

    private var detail: String {
        var parts = [block.room, block.teacher].filter { !$0.isEmpty }
        if block.events.count > 1 { parts.append("\(block.events.count) ore") }
        if parts.isEmpty { parts.append(block.timeRange) }
        return parts.joined(separator: " · ")
    }
}

/// Intervallo: una pillola tra due linee ondulate, come `BreakRow` nell'app.
private struct TimetableBreakRow: View {
    let block: TimetableBlock
    let palette: WidgetPalette
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            wave
            HStack(spacing: 4) {
                WidgetIcon("coffeeFill", size: 13)
                    .foregroundStyle(palette.tint(block.first.tint))
                    .widgetAccentable()
                Text("\(block.title) · \(block.timeRange)")
                    .font(palette.numeral(10.5, weight: 600))
                    .foregroundStyle(palette.secondaryInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: compact ? 18 : 22)
            .background(palette.isFullColor ? palette.eventFill(block.first.tint, amount: 0.2) : .white.opacity(0.1),
                        in: .capsule)
            .fixedSize()
            wave
        }
        .padding(.horizontal, 6)
    }

    private var wave: some View {
        WavyLine(amplitude: 1.6, wavelength: 9)
            .stroke(palette.secondaryInk.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            .frame(height: 5)
            .frame(maxWidth: .infinity)
    }
}

// MARK: Grande

/// Grande: la giornata intera con gli orari, gli intervalli come separatori e la lezione in corso
/// in evidenza (con l'avanzamento).
private struct TimetableLargeView: View {
    let day: TimetableWidgetDay
    let snapshot: WidgetSnapshot
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                TimetableDayHeading(day: day, snapshot: snapshot, palette: palette)
                Spacer(minLength: 8)
                if snapshot.isDemo {
                    WidgetChip(text: "Demo", container: palette.cardHigh, foreground: palette.secondaryInk, palette: palette)
                }
            }
            chips
            TimetableRowList(day: day, blocks: TimetableBlock.blocks(day.events), palette: palette,
                             styles: [.regular, .relaxed, .compact], showsBreaks: true, showsProgress: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            let count = day.lessonCount
            WidgetChip(text: count == 1 ? "1 lezione" : "\(count) lezioni", icon: "bookText",
                       container: palette.container("secondary"), foreground: palette.onContainer("secondary"),
                       palette: palette)
            if let span = day.span {
                WidgetChip(text: "\(TimeOfDay.string(span.start))–\(TimeOfDay.string(span.end))", icon: "schedule",
                           container: palette.cardHigh, foreground: palette.secondaryInk, palette: palette)
            }
            if day.testCount > 0 {
                WidgetChip(text: day.testCount == 1 ? "1 verifica" : "\(day.testCount) verifiche", icon: "test",
                           container: palette.container("tertiary"), foreground: palette.onContainer("tertiary"),
                           palette: palette)
                    .widgetAccentable()
            }
            if day.isHoliday {
                WidgetChip(text: "Vacanza", icon: "beach", container: palette.container("tertiary"),
                           foreground: palette.onContainer("tertiary"), palette: palette)
            }
        }
    }
}
