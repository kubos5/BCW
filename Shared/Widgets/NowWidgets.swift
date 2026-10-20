import SwiftUI
import WidgetKit

// MARK: - Widget "Lezione in corso"

/// La lezione in corso con il tempo che manca e l'avanzamento (aggiornati da iOS con
/// `Text(timerInterval:)` e `ProgressView(timerInterval:)`), poi la successiva; senza lezione in
/// corso la prossima. Piccolo nella schermata Home e accessori della schermata di blocco.
struct NowWidgetView: View {
    let snapshot: WidgetSnapshot
    let now: Date
    let family: WidgetFamily
    let palette: WidgetPalette

    var body: some View {
        let day = TimetableWidgetDay(snapshot: snapshot, now: now)
        Group {
            switch family {
            case .accessoryRectangular: NowRectangularView(day: day, snapshot: snapshot, palette: palette)
            case .accessoryCircular: NowCircularView(day: day, snapshot: snapshot, palette: palette)
            case .accessoryInline: NowInlineView(day: day, snapshot: snapshot)
            default: NowSmallView(day: day, snapshot: snapshot, palette: palette)
            }
        }
        .widgetURL(DeepLink.timetable(snapshot.signedIn ? day.day : nil).url)
    }

    /// Sfondo: il contenitore primario, come la card "Adesso" della scheda Orario.
    static func background(_ palette: WidgetPalette) -> Color { palette.role("primary-container") }
}

/// Piccolo: "Adesso", materia, aula, quanto manca e la barra di avanzamento; sotto la successiva.
private struct NowSmallView: View {
    let day: TimetableWidgetDay
    let snapshot: WidgetSnapshot
    let palette: WidgetPalette

    private var ink: Color { palette.onContainer("primary") }

    var body: some View {
        if !snapshot.signedIn {
            onContainer(WidgetEmptyState(icon: "timetable", title: "Apri BCW per accedere", palette: palette, compact: true))
        } else if !snapshot.hasTimetable {
            onContainer(WidgetEmptyState(icon: "calendarPlus", title: "Crea il tuo orario",
                                         message: "Tocca per aprire BCW.", palette: palette, compact: true))
        } else if let current = day.current {
            lesson(current, isCurrent: true)
        } else if let next = day.next {
            lesson(next, isCurrent: false)
        } else {
            onContainer(WidgetEmptyState(icon: "sun", title: "Nessuna lezione",
                                         message: "Niente in orario nei prossimi giorni.", palette: palette, compact: true))
        }
    }

    private func onContainer(_ content: WidgetEmptyState) -> some View { content }

    private func lesson(_ event: WidgetSnapshot.Event, isCurrent: Bool) -> some View {
        let interval = day.interval(event)
        let following = day.following.first
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    WidgetEyebrow(text: eyebrow(event, isCurrent: isCurrent), color: ink.opacity(0.8), palette: palette,
                                  size: 10.5)
                    Text(event.title)
                        .font(palette.font(19, weight: 600, rounded: true))
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
                ZStack {
                    MaterialShape(isCurrent ? .cookie12Sided : .sunny)
                        .fill(ink.opacity(palette.isFullColor ? 0.12 : 0.18))
                    WidgetIcon(isCurrent ? "timetableFill" : "schedule", size: 17)
                        .foregroundStyle(ink)
                }
                .frame(width: 34, height: 34)
                .widgetAccentable()
            }
            Text(event.room.isEmpty ? event.teacher.isEmpty ? TimeOfDay.string(event.start) + "–" + TimeOfDay.string(event.end) : event.teacher
                 : event.room)
                .font(palette.font(12))
                .foregroundStyle(ink.opacity(0.85))
                .lineLimit(1)
                .padding(.top, 2)
            Spacer(minLength: 4)
            if isCurrent {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("ancora")
                        .font(palette.font(11.5, weight: 500))
                    Text(timerInterval: interval, countsDown: true)
                        .font(palette.numeral(15, weight: 700))
                        .contentTransition(.numericText(countsDown: true))
                }
                .foregroundStyle(ink)
                .lineLimit(1)
                ProgressView(timerInterval: interval, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(palette.isFullColor ? ink : palette.accent)
                .widgetAccentable()
                .padding(.top, 4)
            } else if day.isToday {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("tra")
                        .font(palette.font(11.5, weight: 500))
                    Text(timerInterval: day.now...max(day.now, interval.lowerBound), countsDown: true)
                        .font(palette.numeral(15, weight: 700))
                }
                .foregroundStyle(ink)
                .lineLimit(1)
            } else {
                Text("\(day.dayName) alle \(TimeOfDay.string(event.start))")
                    .font(palette.font(13, weight: 650))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let following {
                HStack(spacing: 4) {
                    WidgetIcon("chevronRight", size: 12)
                    Text("\(TimeOfDay.string(following.start)) \(following.title)")
                        .font(palette.font(11, weight: 600))
                        .lineLimit(1)
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(ink.opacity(palette.isFullColor ? 0.08 : 0.12), in: .capsule)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func eyebrow(_ event: WidgetSnapshot.Event, isCurrent: Bool) -> String {
        if isCurrent { return "Adesso" }
        return day.isToday ? "Alle \(TimeOfDay.string(event.start))" : day.dayName
    }
}

/// Schermata di blocco, rettangolare: materia, aula e fine; sotto l'avanzamento o la successiva.
private struct NowRectangularView: View {
    let day: TimetableWidgetDay
    let snapshot: WidgetSnapshot
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !snapshot.signedIn || !snapshot.hasTimetable {
                header(icon: "timetable", title: "BCW")
                Text(snapshot.signedIn ? "Crea l'orario nell'app" : "Apri BCW per accedere")
                    .font(palette.font(13))
                    .lineLimit(2)
            } else if let current = day.current {
                header(icon: "timetableFill", title: current.title)
                Text(current.room.isEmpty ? "Fino alle \(TimeOfDay.string(current.end))"
                     : "\(current.room) · fino alle \(TimeOfDay.string(current.end))")
                    .font(palette.font(13))
                    .lineLimit(1)
                ProgressView(timerInterval: day.interval(current), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .widgetAccentable()
                .padding(.top, 3)
            } else if let next = day.next {
                header(icon: "schedule", title: next.title)
                Text(day.isToday ? "Alle \(TimeOfDay.string(next.start))" + (next.room.isEmpty ? "" : " · \(next.room)")
                     : "\(day.dayName) alle \(TimeOfDay.string(next.start))")
                    .font(palette.font(13))
                    .lineLimit(1)
                if let after = day.lessons.first(where: { $0.start >= next.end }) {
                    Text("Poi \(after.title)")
                        .font(palette.font(13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                header(icon: "sun", title: "Nessuna lezione")
                Text("Niente in orario")
                    .font(palette.font(13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(icon: String, title: String) -> some View {
        HStack(spacing: 4) {
            WidgetIcon(icon, size: 14)
                .widgetAccentable()
            Text(title)
                .font(palette.font(15, weight: 700, rounded: true))
                .lineLimit(1)
                .widgetAccentable()
        }
    }
}

/// Schermata di blocco, rotondo: anello di avanzamento con la sigla della materia.
private struct NowCircularView: View {
    let day: TimetableWidgetDay
    let snapshot: WidgetSnapshot
    let palette: WidgetPalette

    var body: some View {
        if let current = day.current, snapshot.signedIn {
            ProgressView(timerInterval: day.interval(current), countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Text(Self.abbreviation(current.title))
                    .font(palette.font(14, weight: 750, rounded: true))
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        } else {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    WidgetIcon(day.next == nil ? "timetable" : "schedule", size: 14)
                        .widgetAccentable()
                    Text(day.next.map { TimeOfDay.string($0.start) } ?? "–")
                        .font(palette.numeral(14, weight: 700, rounded: true))
                        .minimumScaleFactor(0.7)
                    if let next = day.next {
                        Text(Self.abbreviation(next.title))
                            .font(palette.font(10, weight: 600))
                            .lineLimit(1)
                    }
                }
                .padding(4)
            }
        }
    }

    /// Sigla di una materia: le prime tre lettere ("MAT"), o le iniziali di più parole ("EF").
    static func abbreviation(_ title: String) -> String {
        let words = title.split(whereSeparator: { !$0.isLetter }).filter { $0.count > 2 }
        if words.count >= 2 { return words.prefix(3).compactMap(\.first).map(String.init).joined().uppercased() }
        return String(title.prefix(3)).uppercased()
    }
}

/// Schermata di blocco, in linea (sopra l'ora): la lezione in corso o la prossima.
private struct NowInlineView: View {
    let day: TimetableWidgetDay
    let snapshot: WidgetSnapshot

    var body: some View {
        if !snapshot.signedIn {
            Text("BCW: accedi nell'app")
        } else if let current = day.current {
            Label {
                Text("\(current.title) fino alle \(TimeOfDay.string(current.end))")
            } icon: {
                Image("m.timetableFill")
            }
        } else if let next = day.next {
            Label {
                Text(day.isToday ? "\(next.title) alle \(TimeOfDay.string(next.start))"
                     : "\(WidgetDates.relativeShort(day.day, now: day.now)): \(next.title) \(TimeOfDay.string(next.start))")
            } icon: {
                Image("m.schedule")
            }
        } else {
            Text("Nessuna lezione")
        }
    }
}
