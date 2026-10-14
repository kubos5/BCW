import SwiftUI

/// Vista Giorno: le ore della giornata in verticale, come in Calendario. Su iPhone una colonna
/// (il giorno scelto), su Mac una colonna per ogni giorno della settimana.
/// Nella modalità di modifica (`isEditing`) gli eventi si spostano trascinandoli (su iPhone dopo
/// averli tenuti premuti) e si allungano dal bordo inferiore, seguendo l'allineamento dell'orario;
/// un doppio tocco su uno spazio vuoto crea un evento a quell'ora. Fuori dalla modifica un tocco
/// apre il dettaglio dell'evento.
struct TimetableTimeline: View {
    @Environment(AppModel.self) private var model
    let days: [Date]
    let selectedDay: Date
    var onSelectDay: (Date) -> Void = { _ in }
    let actions: TimetableActions
    var isEditing = false
    /// Spazio in cima per un'intestazione che galleggia sopra la giornata (iPhone): gli eventi
    /// cominciano sotto di essa e scorrendo le passano sotto. Con l'intestazione mobile le
    /// verifiche senza lezione sono mostrate da chi la disegna.
    var topInset: CGFloat = 0
    #if os(iOS)
    /// Intestazione mobile (iPhone): la giornata si sposta con lei e i suoi gesti stanno qui.
    var headerState: WeekHeaderScroll? = nil
    #endif
    var hourHeight: CGFloat = Platform.isMac ? 52 : 60

    static let gutter: CGFloat = 54
    private static let verticalPadding: CGFloat = 12

    var body: some View {
        let contents = days.map { TimetableDayContent(day: $0, model: model) }
        VStack(spacing: 0) {
            if days.count > 1 {
                header
                Divider().overlay(Theme.separator)
            }
            if topInset == 0,
               let unmatched = contents.first(where: { $0.day.isSameDay(as: selectedDay) })?.unmatchedTests,
               !unmatched.isEmpty {
                unmatchedBanner(unmatched)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        HourGrid(hourHeight: hourHeight, showsNow: days.contains(where: \.isToday))
                        HStack(spacing: 0) {
                            ForEach(Array(contents.enumerated()), id: \.element.day) { index, content in
                                TimelineDayColumn(content: content, dayIndex: index, days: days,
                                                  isSelected: content.day.isSameDay(as: selectedDay),
                                                  hourHeight: hourHeight, isEditing: isEditing, actions: actions)
                                if index < contents.count - 1 {
                                    Rectangle().fill(Theme.separator.opacity(0.6)).frame(width: 0.5)
                                }
                            }
                        }
                        .padding(.leading, Self.gutter)
                        .padding(.trailing, 6)
                    }
                    .frame(height: 24 * hourHeight)
                    .padding(.vertical, Self.verticalPadding)
                    .padding(.bottom, Platform.isMac ? 0 : 60)
                    #if os(iOS)
                    .background {
                        if let headerState { CalendarHeaderPan(state: headerState, swipeEnabled: !isEditing) }
                    }
                    .modifier(OptionalSwipeNeighbor(state: headerState) { direction in
                        neighborPage(selectedDay.adding(days: direction).startOfDay)
                    })
                    #endif
                }
                #if os(iOS)
                .scrollClipDisabled(headerState != nil)
                #endif
                .scrollIndicators(.hidden)
                .safeAreaPadding(.top, topInset)
                #if os(iOS)
                .modifier(OptionalHeaderShift(state: headerState))
                #endif
                .onAppear { proxy.scrollTo(HourGrid.anchor(initialHour(contents)), anchor: .top) }
                .onChange(of: selectedDay) { _, _ in
                    // Su iPhone, cambiando giorno, si va alla prima lezione del nuovo giorno.
                    if days.count == 1 {
                        withAnimation(.snappy) { proxy.scrollTo(HourGrid.anchor(initialHour(contents)), anchor: .top) }
                    }
                }
            }
        }
    }

    #if os(iOS)
    /// Il giorno accanto durante lo scorrimento laterale (iPhone): le stesse ore, in sola lettura.
    private func neighborPage(_ day: Date) -> some View {
        ZStack(alignment: .topLeading) {
            HourGrid(hourHeight: hourHeight, showsNow: day.isToday)
            TimelineDayColumn(content: TimetableDayContent(day: day, model: model), dayIndex: 0, days: [day],
                              isSelected: true, hourHeight: hourHeight, isEditing: false, actions: actions)
                .padding(.leading, Self.gutter)
                .padding(.trailing, 6)
        }
        .frame(height: 24 * hourHeight)
        .padding(.vertical, Self.verticalPadding)
        .padding(.bottom, 60)
    }
    #endif

    private func initialHour(_ contents: [TimetableDayContent]) -> Int {
        let starts = contents.compactMap { $0.layout.span?.start }
        guard let first = starts.min() else { return 7 }
        return max(0, (first - 30) / 60)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutter)
            ForEach(days, id: \.self) { day in
                let selected = day.isSameDay(as: selectedDay)
                Button { onSelectDay(day) } label: {
                    HStack(spacing: 6) {
                        Text(day.it("EEE").capitalizedFirst)
                            .font(.subheadline)
                            .foregroundStyle(selected ? Theme.accent : Theme.secondaryInk)
                        Text(day.it("d"))
                            .font(.numeral(15, weight: .bold))
                            .foregroundStyle(selected ? Color.white : (day.isToday ? Theme.accent : Theme.ink))
                            .frame(width: 28, height: 28)
                            .background { if selected { Circle().fill(Theme.accent.gradient) } }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.longDay)
            }
            Color.clear.frame(width: 6)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func unmatchedBanner(_ tests: [AgendaEvent]) -> some View {
        Label(tests.count == 1 ? "1 verifica senza lezione in orario: \(tests[0].title)"
              : "\(tests.count) verifiche senza lezione in orario",
              systemImage: "exclamationmark.triangle")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentSoft.opacity(0.6))
    }
}

/// Righe delle ore con le etichette a sinistra (e l'ora attuale in rosso).
private struct HourGrid: View {
    let hourHeight: CGFloat
    let showsNow: Bool

    static func anchor(_ hour: Int) -> String { "ora-\(hour)" }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    HStack(alignment: .top, spacing: 6) {
                        Text(TimeOfDay.string(hour * 60))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.secondaryInk)
                            .frame(width: TimetableTimeline.gutter - 10, alignment: .trailing)
                            .offset(y: -7)
                        VStack(spacing: 0) {
                            Rectangle().fill(Theme.separator).frame(height: 0.5)
                            Spacer(minLength: 0)
                            // Mezz'ora, più leggera.
                            Rectangle().fill(Theme.separator.opacity(0.35)).frame(height: 0.5)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(height: hourHeight, alignment: .top)
                    .id(Self.anchor(hour))
                }
            }
            if showsNow {
                TimelineView(.everyMinute) { context in
                    let minutes = TimeOfDay.minutes(of: context.date)
                    Text(TimeOfDay.string(minutes))
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.poor, in: .capsule)
                        .frame(width: TimetableTimeline.gutter - 4, alignment: .trailing)
                        .offset(y: CGFloat(minutes) / 60 * hourHeight - 8)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Colonna di un giorno: lezioni affiancate se contemporanee, gruppi uniti, intervalli sopra.
private struct TimelineDayColumn: View {
    @Environment(AppModel.self) private var model
    let content: TimetableDayContent
    let dayIndex: Int
    let days: [Date]
    let isSelected: Bool
    let hourHeight: CGFloat
    let isEditing: Bool
    let actions: TimetableActions

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                // Sfondo: doppio tocco per creare un evento a quell'ora.
                Rectangle()
                    .fill(days.count > 1 && isSelected ? Theme.accent.opacity(0.04) : Color.clear)
                    .contentShape(.rect)
                    .onTapGesture(count: 2, coordinateSpace: .local) { location in
                        guard isEditing, !content.isDraft else { return }
                        let minute = TimeOfDay.snapped(Int(location.y / hourHeight * 60) - 15, step: 30)
                        actions.create(content.day.timetableWeekday, min(max(0, minute), 23 * 60 + 30))
                    }

                ForEach(content.layout.clusters) { cluster in
                    let columnWidth = width / CGFloat(cluster.columns)
                    ForEach(cluster.blocks) { placed in
                        let entries = placed.block.entries
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            TimelineSegment(entry: entry, badges: content.badges[entry.id] ?? EntryBadges(),
                                            roundsTop: index == 0, roundsBottom: index == entries.count - 1,
                                            x: columnWidth * CGFloat(placed.column) + 2, width: columnWidth - 4,
                                            dayWidth: width, dayIndex: dayIndex, days: days,
                                            hourHeight: hourHeight, day: content.day, isDraft: content.isDraft,
                                            isEditing: isEditing, actions: actions)
                        }
                    }
                }

                // Gli intervalli stanno sopra le lezioni, su tutta la larghezza.
                ForEach(content.layout.breaks) { entry in
                    TimelineSegment(entry: entry, badges: EntryBadges(), roundsTop: true, roundsBottom: true,
                                    x: 8, width: width - 12, dayWidth: width, dayIndex: dayIndex, days: days,
                                    hourHeight: hourHeight, day: content.day, isDraft: content.isDraft,
                                    isEditing: isEditing, actions: actions)
                        .zIndex(2)
                }

                if content.day.isToday {
                    TimelineView(.everyMinute) { context in
                        let y = CGFloat(TimeOfDay.minutes(of: context.date)) / 60 * hourHeight
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.poor).frame(height: 1.5)
                            Circle().fill(Theme.poor).frame(width: 8, height: 8).offset(x: -4)
                        }
                        .offset(y: y - 0.75)
                        .allowsHitTesting(false)
                    }
                    .zIndex(3)
                }
            }
        }
        .overlay {
            if content.entries.isEmpty && days.count == 1 {
                VStack(spacing: 6) {
                    Text("Nessuna lezione il \(Weekday.name(content.day.timetableWeekday).lowercased())")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(isEditing
                         ? (Platform.isMac ? "Fai doppio clic su un'ora per aggiungere un evento."
                            : "Tocca due volte un'ora per aggiungere un evento.")
                         : "Aggiungi eventi con + o da Modifica orario.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.surface.opacity(0.95), in: .rect(cornerRadius: 14, style: .continuous))
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 8 * hourHeight)
                .allowsHitTesting(false)
            }
        }
    }
}

/// Un evento nella linea del tempo: un tocco apre il dettaglio (in modifica l'editor). In modifica
/// si sposta trascinandolo e si allunga dal bordo inferiore; gli orari seguono l'allineamento
/// dell'orario (mezz'ora o 5 minuti), gli intervalli si spostano sempre liberamente.
private struct TimelineSegment: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    let entry: TimetableEntry
    let badges: EntryBadges
    let roundsTop: Bool
    let roundsBottom: Bool
    let x: CGFloat
    let width: CGFloat
    /// Larghezza di una colonna-giorno, per spostare l'evento in un altro giorno (Mac).
    let dayWidth: CGFloat
    let dayIndex: Int
    let days: [Date]
    let hourHeight: CGFloat
    let day: Date
    let isDraft: Bool
    let isEditing: Bool
    let actions: TimetableActions

    @State private var move: CGSize = .zero
    @State private var resize: CGFloat = 0
    @State private var isLifted = false

    private static let radius: CGFloat = 7

    private var step: Int { entry.isBreak ? 5 : model.timetable.alignment.dragStep }
    private var isAutomatic: Bool { !entry.isBreak && model.timetable.alignment == .automatic }

    /// Orari e giorno mentre si trascina (già allineati).
    private var preview: (start: Int, end: Int, dayShift: Int) {
        var start = entry.start
        var end = entry.end
        let moveMinutes = Double(move.height) / Double(hourHeight) * 60
        if abs(moveMinutes) >= Double(step) / 2 {
            start = TimeOfDay.snapped(entry.start + Int(moveMinutes.rounded()), step: step)
            start = min(max(0, start), 24 * 60 - entry.duration)
            end = start + entry.duration
        }
        let resizeMinutes = Double(resize) / Double(hourHeight) * 60
        if abs(resizeMinutes) >= Double(step) / 2 {
            var duration = entry.duration + Int(resizeMinutes.rounded())
            duration = isAutomatic ? (duration < 45 ? 30 : 60) : max(5, TimeOfDay.snapped(duration, step: 5))
            end = min(24 * 60, start + duration)
        }
        var shift = 0
        if days.count > 1, dayWidth > 0 {
            shift = Int((move.width / dayWidth).rounded())
            shift = min(max(shift, -dayIndex), days.count - 1 - dayIndex)
        }
        return (start, end, shift)
    }

    var body: some View {
        let preview = preview
        let tint = Theme.timetableColor(entry, store: model.timetable)
        let height = max(entry.isBreak ? 10 : 16, CGFloat(preview.end - preview.start) / 60 * hourHeight - (roundsBottom ? 1.5 : 0))
        let dragging = move != .zero || resize != 0 || isLifted

        segment(tint: tint, start: preview.start, end: preview.end, height: height)
            .frame(width: width, height: height, alignment: .topLeading)
            .overlay(alignment: .bottom) {
                if canEdit { resizeHandle }
            }
            .scaleEffect(isLifted ? 1.02 : 1)
            .shadow(color: .black.opacity(dragging ? 0.18 : (entry.isBreak ? 0.12 : 0)), radius: dragging ? 8 : 3, y: dragging ? 4 : 1)
            .overlay(alignment: .topLeading) {
                if dragging {
                    Text("\(TimeOfDay.string(preview.start))–\(TimeOfDay.string(preview.end))"
                         + (preview.dayShift != 0 ? " · \(days[dayIndex + preview.dayShift].it("EEE"))" : ""))
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.accent, in: .capsule)
                        .fixedSize()
                        .offset(y: -20)
                }
            }
            // Tocchi e gesti vanno prima di `offset`: dopo, varrebbero per la posizione di partenza
            // (in cima alla colonna) e non per quella in cui l'evento è disegnato.
            .contentShape(.rect)
            .onTapGesture {
                if canEdit { actions.edit(entry) } else { actions.open(entry, day) }
            }
            #if os(macOS)
            .gesture(moveGesture, isEnabled: canEdit)
            .contextMenu { EntryContextMenu(entry: entry, isDraft: isDraft, actions: actions) }
            #else
            .gesture(moveGesture)
            #endif
            .offset(x: x + CGFloat(preview.dayShift) * dayWidth,
                    y: CGFloat(preview.start) / 60 * hourHeight)
            .zIndex(dragging ? 10 : 0)
            .sensoryFeedback(.selection, trigger: preview.start)
            .sensoryFeedback(.impact(weight: .medium), trigger: isLifted) { _, lifted in lifted }
            .animation(.snappy(duration: 0.2), value: preview.start)
            .animation(.snappy(duration: 0.2), value: preview.end)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entry.displayTitle), \(entry.timeRange)")
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func segment(tint: Color, start: Int, end: Int, height: CGFloat) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: roundsTop ? Self.radius : 0,
                                           bottomLeadingRadius: roundsBottom ? Self.radius : 0,
                                           bottomTrailingRadius: roundsBottom ? Self.radius : 0,
                                           topTrailingRadius: roundsTop ? Self.radius : 0,
                                           style: .continuous)
        ZStack(alignment: .topLeading) {
            if entry.isBreak {
                shape.fill(Theme.surfaceRaised)
                shape.fill(tint.opacity(isDraft ? 0.15 : 0.32))
                DiagonalStripes().stroke(tint.opacity(0.25), lineWidth: 3).clipShape(shape)
            } else {
                shape.fill(Theme.surface)
                shape.fill(tint.opacity((colorScheme == .dark ? 0.32 : 0.22) * (isDraft ? 0.5 : 1)))
            }
            HStack(alignment: .top, spacing: 0) {
                if !entry.isBreak {
                    Rectangle().fill(tint.opacity(isDraft ? 0.6 : 1)).frame(width: 3)
                }
                label(start: start, end: end, height: height, tint: tint)
                    .padding(.leading, 6)
                    .padding(.trailing, 4)
                    .padding(.top, height >= 26 ? 4 : 1)
                Spacer(minLength: 0)
            }
            .clipShape(shape)
        }
        .overlay {
            if isDraft {
                shape.stroke(tint, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            } else if entry.isBreak {
                shape.strokeBorder(tint.opacity(0.6), lineWidth: 0.75)
            }
        }
        .overlay(alignment: .top) {
            if !roundsTop {
                Line()
                    .stroke(tint.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 1)
                    .padding(.leading, 3)
            }
        }
    }

    @ViewBuilder
    private func label(start: Int, end: Int, height: CGFloat, tint: Color) -> some View {
        let time = "\(TimeOfDay.string(start))–\(TimeOfDay.string(end))"
        if height >= 34 {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.displayTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(height >= 70 ? 2 : 1)
                    Spacer(minLength: 0)
                    icons
                }
                Text([time, entry.room].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
                if badges.isTest && height >= 52 {
                    Text("Verifica")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        } else {
            // Eventi brevi: una riga sola; se non c'è posto per l'orario resta il nome.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    Text(entry.displayTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.secondaryInk)
                    Spacer(minLength: 0)
                    icons
                }
                .fixedSize()
                Text(entry.displayTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            .lineLimit(1)
        }
    }

    private var icons: some View {
        HStack(spacing: 3) {
            if badges.isTest {
                Image(systemName: "pencil.and.list.clipboard")
                    .foregroundStyle(Theme.accent)
            }
            // Nelle colonne strette (eventi affiancati, settimana su Mac) il nome ha la precedenza.
            if width >= 100 {
                if badges.hasNote { Image(systemName: "note.text") }
                if badges.attachmentCount > 0 { Image(systemName: "paperclip") }
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Theme.secondaryInk)
    }

    private var canEdit: Bool { isEditing && !isDraft }

    /// Bordo inferiore: trascinandolo cambia la durata. In modifica ha una maniglia visibile.
    private var resizeHandle: some View {
        Color.clear
            .frame(height: 12)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(Theme.ink.opacity(0.35))
                    .frame(width: 22, height: 3)
                    .padding(.bottom, 3)
            }
            .contentShape(.rect)
            #if os(macOS)
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            #endif
            .gesture(resizeGesture)
    }

    // MARK: Gesti

    #if os(macOS)
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { move = $0.translation }
            .onEnded { _ in commit() }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { resize = $0.translation.height }
            .onEnded { _ in commit() }
    }
    #else
    /// Su iPhone si tiene premuto e poi si trascina. Un riconoscitore di UIKit: quelli di SwiftUI,
    /// dentro lo scorrimento della giornata, perdevano contro lo scorrimento stesso.
    private var moveGesture: LongPressDragRecognizer {
        // In modifica basta una pressione breve: uno scorrimento rapido fa comunque scorrere la giornata.
        LongPressDragRecognizer(minimumDuration: 0.2, isEnabled: canEdit) {
            isLifted = true
        } onChanged: { translation in
            move = translation
        } onEnded: {
            // Premuto senza spostarlo: è un tocco un po' lungo, apre l'evento.
            let moved = abs(move.height) >= 4 || abs(move.width) >= 4
            commit()
            if !moved { actions.edit(entry) }
        }
    }

    private var resizeGesture: LongPressDragRecognizer {
        LongPressDragRecognizer(minimumDuration: 0.1, isEnabled: canEdit) {
            isLifted = true
        } onChanged: { translation in
            resize = translation.height
        } onEnded: {
            commit()
        }
    }
    #endif

    private func commit() {
        let result = preview
        let weekday = days[dayIndex + result.dayShift].timetableWeekday
        withAnimation(.snappy) {
            move = .zero
            resize = 0
            isLifted = false
            model.timetable.move(entry.id, weekday: weekday, start: result.start, end: result.end)
        }
    }
}

#if os(iOS)
import UIKit

/// `SwipeNeighbor` solo se c'è un'intestazione mobile.
private struct OptionalSwipeNeighbor<Neighbor: View>: ViewModifier {
    let state: WeekHeaderScroll?
    @ViewBuilder let neighbor: (Int) -> Neighbor

    func body(content: Content) -> some View {
        if let state { content.modifier(SwipeNeighbor(state: state, neighbor: neighbor)) } else { content }
    }
}

/// `WeekHeaderScroll.Shift` solo se c'è un'intestazione mobile.
private struct OptionalHeaderShift: ViewModifier {
    let state: WeekHeaderScroll?

    func body(content: Content) -> some View {
        if let state { content.modifier(WeekHeaderScroll.Shift(state: state)) } else { content }
    }
}

/// Tieni premuto e trascina: riporta lo spostamento del dito da quando la pressione è stata
/// riconosciuta. Mentre è attivo lo scorrimento della pagina resta fermo.
struct LongPressDragRecognizer: UIGestureRecognizerRepresentable {
    var minimumDuration: TimeInterval
    var isEnabled = true
    var onBegan: () -> Void
    var onChanged: (CGSize) -> Void
    var onEnded: () -> Void

    final class Coordinator {
        var start: CGPoint = .zero
        var isActive = false
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        recognizer.allowableMovement = 12
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let location = context.converter.location(in: .global)
        switch recognizer.state {
        case .began:
            context.coordinator.start = location
            context.coordinator.isActive = true
            onBegan()
        case .changed:
            let start = context.coordinator.start
            onChanged(CGSize(width: location.x - start.x, height: location.y - start.y))
        case .ended, .cancelled, .failed:
            guard context.coordinator.isActive else { return }
            context.coordinator.isActive = false
            onEnded()
        default:
            break
        }
    }
}
#endif
