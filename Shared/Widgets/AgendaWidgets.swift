import SwiftUI
import WidgetKit

// MARK: - Widget "Compiti e verifiche"

/// Un giorno dell'agenda con i suoi elementi.
struct AgendaDay {
    let day: Date
    let items: [WidgetSnapshot.AgendaItem]
}

/// I prossimi compiti, verifiche ed eventi dell'agenda raggruppati per giorno, come "Nei
/// prossimi giorni" della Dashboard: la data in un riquadro e gli elementi in una lista segmentata.
struct AgendaWidgetView: View {
    let snapshot: WidgetSnapshot
    let now: Date
    let family: WidgetFamily
    let palette: WidgetPalette

    /// Giorni da oggi in poi con i loro elementi (le verifiche prima, come nella Dashboard).
    static func days(_ snapshot: WidgetSnapshot, now: Date) -> [AgendaDay] {
        let calendar = BCWShared.calendar
        let today = calendar.startOfDay(for: now)
        let upcoming = snapshot.agenda.filter { calendar.startOfDay(for: $0.begin) >= today }
        return Dictionary(grouping: upcoming) { calendar.startOfDay(for: $0.begin) }
            .sorted { $0.key < $1.key }
            .map { AgendaDay(day: $0.key, items: $0.value.sorted { ($0.kind == .test ? 0 : 1, $0.begin) < ($1.kind == .test ? 0 : 1, $1.begin) }) }
    }

    var body: some View {
        let days = Self.days(snapshot, now: now)
        Group {
            if !snapshot.signedIn {
                WidgetEmptyState(icon: "checklist", title: "Apri BCW per accedere",
                                 message: "Compiti e verifiche compariranno qui dopo l'accesso.", palette: palette)
            } else {
                VStack(alignment: .leading, spacing: family == .systemMedium ? 8 : 12) {
                    header(days)
                    if days.isEmpty {
                        empty
                    } else if family == .systemMedium {
                        AgendaCompactList(days: days, now: now, palette: palette)
                    } else {
                        AgendaDayList(days: days, now: now, palette: palette)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .widgetURL(DeepLink.dashboard(days.first?.day).url)
    }

    private func header(_ days: [AgendaDay]) -> some View {
        let items = days.flatMap(\.items)
        let tests = items.filter { $0.kind == .test }.count
        let homework = items.filter { $0.kind == .homework && !$0.isDone }.count
        // Il titolo resta intero: prima si tolgono i chip che non entrano.
        return ViewThatFits(in: .horizontal) {
            headerRow(tests: tests, homework: homework)
            headerRow(tests: tests, homework: tests > 0 ? 0 : homework)
            headerRow(tests: 0, homework: 0)
        }
    }

    private func headerRow(tests: Int, homework: Int) -> some View {
        HStack(spacing: 6) {
            WidgetIcon("checklist", size: 16)
                .foregroundStyle(palette.accent)
                .widgetAccentable()
            Text("Compiti e verifiche")
                .font(palette.font(14, weight: 650))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            if tests > 0 {
                WidgetChip(text: tests == 1 ? "1 verifica" : "\(tests) verifiche", icon: "test",
                           container: palette.container("tertiary"), foreground: palette.onContainer("tertiary"),
                           palette: palette)
                    .fixedSize()
                    .widgetAccentable()
            }
            if homework > 0 {
                WidgetChip(text: homework == 1 ? "1 compito" : "\(homework) compiti", icon: "book",
                           container: palette.container("secondary"), foreground: palette.onContainer("secondary"),
                           palette: palette)
                    .fixedSize()
            }
        }
    }

    private var empty: some View {
        HStack(spacing: 12) {
            ZStack {
                MaterialShape(.cookie9Sided)
                    .fill(palette.isFullColor ? palette.role("good-container") : .white.opacity(0.16))
                WidgetIcon("checkCircleFill", size: 22)
                    .foregroundStyle(palette.isFullColor ? palette.role("on-good-container") : palette.accent)
            }
            .frame(width: 44, height: 44)
            .widgetAccentable()
            VStack(alignment: .leading, spacing: 2) {
                Text("Niente in programma")
                    .font(palette.font(16, weight: 600, rounded: true))
                    .foregroundStyle(palette.ink)
                Text("Nessun compito o verifica nei prossimi \(WidgetSnapshot.agendaDays) giorni.")
                    .font(palette.font(12))
                    .foregroundStyle(palette.secondaryInk)
                    .lineLimit(2)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Icona di un elemento dell'agenda: cerchio della materia per i compiti (con il segno se fatti),
/// verifica, calendario per gli eventi.
private struct AgendaItemIcon: View {
    let item: WidgetSnapshot.AgendaItem
    let palette: WidgetPalette
    var size: CGFloat = 16

    var body: some View {
        Group {
            switch item.kind {
            case .homework: WidgetIcon(item.isDone ? "checkCircleFill" : "circle", size: size)
            case .test: WidgetIcon("test", size: size)
            case .event: WidgetIcon("calendar", size: size)
            }
        }
        .foregroundStyle(item.isDone ? palette.secondaryInk : palette.tint(item.tint))
        .widgetAccentable()
    }
}

/// Medio: righe di una riga raggruppate sotto il nome del giorno, quante ne entrano.
private struct AgendaCompactList: View {
    let days: [AgendaDay]
    let now: Date
    let palette: WidgetPalette

    private enum Line: Identifiable {
        case day(Date, Bool)
        case item(WidgetSnapshot.AgendaItem)
        var id: String {
            switch self {
            case let .day(day, _): "d-\(day.timeIntervalSince1970)"
            case let .item(item): "i-\(item.id)"
            }
        }
    }

    var body: some View {
        let lines = days.flatMap { day in
            [Line.day(day.day, day.items.contains { $0.kind == .test })] + day.items.map(Line.item)
        }
        let total = days.reduce(0) { $0 + $1.items.count }
        ViewThatFits(in: .vertical) {
            ForEach((1...max(1, lines.count)).reversed(), id: \.self) { count in
                let shown = Self.trimmed(Array(lines.prefix(count)))
                let shownItems = shown.filter { if case .item = $0 { true } else { false } }.count
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(shown) { line in
                        switch line {
                        case let .day(day, hasTest): dayLine(day, hasTest: hasTest)
                        case let .item(item): itemLine(item)
                        }
                    }
                    if shownItems < total {
                        Text("+\(total - shownItems) dopo")
                            .font(palette.font(11, weight: 600))
                            .foregroundStyle(palette.secondaryInk)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// Senza il nome di un giorno in fondo, se i suoi elementi non entrano.
    private static func trimmed(_ lines: [Line]) -> [Line] {
        var lines = lines
        while let last = lines.last, case .day = last { lines.removeLast() }
        return lines
    }

    private func dayLine(_ day: Date, hasTest: Bool) -> some View {
        Text(WidgetDates.relativeName(day, now: now) + (WidgetDates.offset(of: day, from: now) > 1 ? " \(BCWShared.calendar.component(.day, from: day))" : ""))
            .font(palette.font(11, weight: 750))
            .tracking(0.4)
            .foregroundStyle(hasTest ? palette.accent : palette.secondaryInk)
            .padding(.top, 2)
    }

    private func itemLine(_ item: WidgetSnapshot.AgendaItem) -> some View {
        HStack(spacing: 6) {
            AgendaItemIcon(item: item, palette: palette, size: 14)
            Text(item.title)
                .font(palette.font(12.5, weight: 650))
                .foregroundStyle(item.isDone ? palette.secondaryInk : palette.ink)
                .lineLimit(1)
                .layoutPriority(1)
            Text(item.text.isEmpty ? "Nessuna descrizione" : item.text)
                .font(palette.font(12))
                .foregroundStyle(palette.secondaryInk)
                .strikethrough(item.isDone)
                .lineLimit(1)
        }
    }
}

/// Grande: per ogni giorno la data in un riquadro (in evidenza se c'è una verifica) e gli elementi
/// in una lista segmentata.
private struct AgendaDayList: View {
    let days: [AgendaDay]
    let now: Date
    let palette: WidgetPalette

    private struct Variant: Identifiable {
        let days: Int
        let items: Int
        let lines: Int
        var id: String { "\(days)-\(items)-\(lines)" }
    }

    var body: some View {
        let total = days.reduce(0) { $0 + $1.items.count }
        // Prima con il testo su due righe, poi su una, togliendo via via gli ultimi elementi.
        let variants = [2, 1].flatMap { lines in
            (1...max(1, total)).reversed().map { count in Variant(days: days.count, items: count, lines: lines) }
        }
        ViewThatFits(in: .vertical) {
            ForEach(variants) { variant in
                list(limit: variant.items, lines: variant.lines, total: total)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func list(limit: Int, lines: Int, total: Int) -> some View {
        var remaining = limit
        var shown: [AgendaDay] = []
        for day in days where remaining > 0 {
            let items = Array(day.items.prefix(remaining))
            remaining -= items.count
            shown.append(AgendaDay(day: day.day, items: items))
        }
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(shown, id: \.day) { group in
                let day = group.day, items = group.items
                HStack(alignment: .top, spacing: 10) {
                    Link(destination: DeepLink.dashboard(day).url) {
                        dateBadge(day, highlighted: items.contains { $0.kind == .test })
                    }
                    VStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item, lines: lines, corners: (index == 0 ? palette.radii.l : palette.radii.xs,
                                                              index == items.count - 1 ? palette.radii.l : palette.radii.xs))
                        }
                    }
                }
            }
            if limit < total {
                Text("+\(total - limit) dopo")
                    .font(palette.font(11, weight: 600))
                    .foregroundStyle(palette.secondaryInk)
                    .padding(.leading, 52)
            }
        }
    }

    /// Come `DateBadge` nell'app: giorno della settimana e numero.
    private func dateBadge(_ day: Date, highlighted: Bool) -> some View {
        let container = highlighted ? palette.container("tertiary") : palette.card
        let ink = highlighted ? palette.onContainer("tertiary") : palette.ink
        return VStack(spacing: 0) {
            Text(WidgetDates.offset(of: day, from: now) == 0 ? "Oggi" : WidgetDates.weekdayShort(day))
                .font(palette.font(10.5, weight: 650))
                .foregroundStyle(highlighted ? ink : palette.secondaryInk)
            Text("\(BCWShared.calendar.component(.day, from: day))")
                .font(palette.numeral(19, weight: 650, rounded: true))
                .foregroundStyle(ink)
        }
        .frame(width: 42, height: 46)
        .background(container, in: .rect(cornerRadius: palette.radii.l, style: .continuous))
        .widgetAccentable(highlighted)
    }

    private func row(_ item: WidgetSnapshot.AgendaItem, lines: Int, corners: (top: CGFloat, bottom: CGFloat)) -> some View {
        HStack(alignment: .top, spacing: 8) {
            AgendaItemIcon(item: item, palette: palette, size: 15)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(palette.font(12.5, weight: 650))
                        .foregroundStyle(item.isDone ? palette.secondaryInk : palette.tint(item.tint))
                        .lineLimit(1)
                    if item.kind == .test {
                        WidgetEyebrow(text: "Verifica", color: palette.accent, palette: palette, size: 9.5)
                            .widgetAccentable()
                    }
                    Spacer(minLength: 0)
                    if item.kind != .homework, !item.isFullDay {
                        Text(WidgetDates.time(item.begin))
                            .font(palette.numeral(10.5, weight: 500))
                            .foregroundStyle(palette.secondaryInk)
                    }
                }
                Text(item.text.isEmpty ? "Nessuna descrizione" : item.text)
                    .font(palette.font(12))
                    .foregroundStyle(item.isDone ? palette.secondaryInk : palette.ink)
                    .strikethrough(item.isDone)
                    .lineLimit(lines)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(palette.card,
                    in: UnevenRoundedRectangle(topLeadingRadius: corners.top, bottomLeadingRadius: corners.bottom,
                                               bottomTrailingRadius: corners.bottom, topTrailingRadius: corners.top,
                                               style: .continuous))
    }
}

// MARK: - Widget "Prossima verifica"

/// La prossima verifica con il conto alla rovescia dei giorni (nel contenitore terziario).
struct NextTestWidgetView: View {
    let snapshot: WidgetSnapshot
    let now: Date
    let family: WidgetFamily
    let palette: WidgetPalette

    static func nextTest(_ snapshot: WidgetSnapshot, now: Date) -> WidgetSnapshot.AgendaItem? {
        let today = BCWShared.calendar.startOfDay(for: now)
        return snapshot.agenda.filter { $0.kind == .test && BCWShared.calendar.startOfDay(for: $0.begin) >= today }
            .min { $0.begin < $1.begin }
    }

    static func background(_ palette: WidgetPalette) -> Color { palette.role("tertiary-container") }

    var body: some View {
        let test = Self.nextTest(snapshot, now: now)
        Group {
            switch family {
            case .accessoryRectangular: rectangular(test)
            case .accessoryInline: inline(test)
            default: small(test)
            }
        }
        .widgetURL(DeepLink.dashboard(test.map { BCWShared.calendar.startOfDay(for: $0.begin) }).url)
    }

    private var ink: Color { palette.onContainer("tertiary") }

    /// "Oggi", "Domani" o il numero di giorni.
    private func countdown(_ test: WidgetSnapshot.AgendaItem) -> (value: String, unit: String?) {
        let days = WidgetDates.offset(of: test.begin, from: now)
        switch days {
        case 0: return ("Oggi", nil)
        case 1: return ("Domani", nil)
        default: return ("\(days)", "giorni")
        }
    }

    private func relative(_ test: WidgetSnapshot.AgendaItem) -> String {
        let days = WidgetDates.offset(of: test.begin, from: now)
        switch days {
        case 0: return "oggi"
        case 1: return "domani"
        default: return "tra \(days) giorni"
        }
    }

    @ViewBuilder
    private func small(_ test: WidgetSnapshot.AgendaItem?) -> some View {
        if !snapshot.signedIn {
            WidgetEmptyState(icon: "test", title: "Apri BCW per accedere", palette: palette, compact: true)
        } else if let test {
            let count = countdown(test)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    WidgetEyebrow(text: "Verifica", color: ink.opacity(0.8), palette: palette, size: 10.5)
                        .padding(.top, 4)
                    Spacer(minLength: 0)
                    // Il conto alla rovescia in un biscotto di M3 Expressive.
                    ZStack {
                        MaterialShape(.cookie9Sided)
                            .fill(palette.isFullColor ? palette.role("tertiary") : .white.opacity(0.2))
                        VStack(spacing: -2) {
                            Text(count.value)
                                .font(palette.numeral(count.unit == nil ? 11 : 20, weight: 750, rounded: true))
                                .minimumScaleFactor(0.6)
                            if let unit = count.unit {
                                Text(unit)
                                    .font(palette.font(8.5, weight: 650))
                            }
                        }
                        .foregroundStyle(palette.isFullColor ? palette.role("on-tertiary") : .white)
                        .padding(5)
                    }
                    .frame(width: 50, height: 50)
                    .widgetAccentable()
                }
                Text(test.title)
                    .font(palette.font(18, weight: 600, rounded: true))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .padding(.top, -6)
                Text(test.text.isEmpty ? "Verifica" : test.text)
                    .font(palette.font(12))
                    .foregroundStyle(ink.opacity(0.9))
                    .lineLimit(2)
                    .padding(.top, 2)
                Spacer(minLength: 4)
                Text(dateLine(test))
                    .font(palette.font(11, weight: 650))
                    .foregroundStyle(ink.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    MaterialShape(.cookie9Sided)
                        .fill(palette.isFullColor ? palette.role("tertiary") : .white.opacity(0.2))
                    WidgetIcon("checkSealFill", size: 22)
                        .foregroundStyle(palette.isFullColor ? palette.role("on-tertiary") : .white)
                }
                .frame(width: 44, height: 44)
                .widgetAccentable()
                Spacer(minLength: 0)
                Text("Nessuna verifica")
                    .font(palette.font(17, weight: 600, rounded: true))
                    .foregroundStyle(ink)
                Text("Nei prossimi \(WidgetSnapshot.agendaDays) giorni non ci sono verifiche in agenda.")
                    .font(palette.font(12))
                    .foregroundStyle(ink.opacity(0.85))
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func dateLine(_ test: WidgetSnapshot.AgendaItem) -> String {
        let day = "\(WidgetDates.weekdayShort(test.begin)) \(WidgetDates.dayMonthShort(test.begin))"
        return test.isFullDay ? day : "\(day) · \(WidgetDates.time(test.begin))"
    }

    @ViewBuilder
    private func rectangular(_ test: WidgetSnapshot.AgendaItem?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                WidgetIcon("test", size: 14)
                Text(test.map { "Verifica di \($0.title)" } ?? "Nessuna verifica")
                    .font(palette.font(15, weight: 700, rounded: true))
                    .lineLimit(1)
            }
            .widgetAccentable()
            if let test {
                Text(test.text.isEmpty ? "Verifica" : test.text)
                    .font(palette.font(13))
                    .lineLimit(1)
                Text("\(relative(test).capitalizedFirstLetter) · \(dateLine(test))")
                    .font(palette.font(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(snapshot.signedIn ? "Nei prossimi giorni" : "Apri BCW per accedere")
                    .font(palette.font(13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inline(_ test: WidgetSnapshot.AgendaItem?) -> some View {
        if let test {
            Label {
                Text("\(test.title): verifica \(relative(test))")
            } icon: {
                Image("m.test")
            }
        } else {
            Text("Nessuna verifica in vista")
        }
    }
}
