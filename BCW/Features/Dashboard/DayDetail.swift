import SwiftUI

/// Tutto ciò che riguarda un giorno: in cima il giorno in grande con i chip di stato, sotto
/// verifiche ed eventi, compiti, presenze e — per i giorni passati — le lezioni svolte, ognuno in
/// una sezione segmentata di M3 Expressive.
struct DayDetail: View {
    @Environment(AppModel.self) private var model
    let day: Date
    /// Pulsante per tornare al giorno predefinito (es. "Domani"), se il giorno è un altro.
    var jump: (title: String, action: () -> Void)?

    /// Tutto ciò che serve per disegnare il giorno, calcolato una volta per aggiornamento
    /// (prima ogni sezione, e ogni riga, rifiltrava l'agenda).
    private struct Content {
        let homework: [AgendaEvent]
        let testsAndEvents: [AgendaEvent]
        let completedHomework: Int
        let testCount: Int
        let absences: [AbsenceEvent]
        let lessons: [Lesson]
        let lessonsLoaded: Bool

        var hasAgenda: Bool { !homework.isEmpty || !testsAndEvents.isEmpty || !absences.isEmpty }
    }

    private func makeContent() -> Content {
        let preferences = model.preferences
        let events = model.events(on: day)
            .filter { !(preferences.hideCompletedHomework && preferences.isCompleted($0)) }
        let homework = events.filter { $0.kind == .homework }
        return Content(
            homework: homework,
            testsAndEvents: events.filter { $0.kind != .homework }
                .sorted { ($0.kind == .test ? 0 : 1, $0.begin) < ($1.kind == .test ? 0 : 1, $1.begin) },
            completedHomework: homework.filter { preferences.isCompleted($0) }.count,
            testCount: events.filter { $0.kind == .test }.count,
            absences: model.absences(on: day),
            lessons: model.lessons(on: day),
            lessonsLoaded: model.hasLoadedLessons(on: day)
        )
    }

    private var isPastOrToday: Bool { day.startOfDay <= Date().startOfDay }

    var body: some View {
        let content = makeContent()
        VStack(alignment: .leading, spacing: 20) {
            hero(content)

            if !content.hasAgenda && (content.lessons.isEmpty || !isPastOrToday) {
                emptyState
            }
            agendaSections(content)
            if isPastOrToday {
                lessonsSection(content)
            }
        }
        // Anche dopo ogni aggiornamento completo, che azzera le lezioni già scaricate:
        // altrimenti, aprendo l'app su un giorno passato, resterebbero "in caricamento".
        .task(id: [day.timeIntervalSince1970, model.lastUpdated?.timeIntervalSince1970 ?? 0]) {
            if isPastOrToday {
                await model.ensureLessons(from: day.startOfWeek, to: day.startOfWeek.adding(days: 6))
            }
        }
    }

    // MARK: Giorno in grande

    /// "Domani" (o il giorno della settimana) in grande, la data sotto e i chip di stato. Con
    /// Liquid Glass il nome del giorno è già il titolo della barra: resta solo la data.
    private func hero(_ content: Content) -> some View {
        let relative = day.isToday || day.isTomorrow || day.isYesterday
        let title = relative ? day.relativeDayName : day.it("EEEE").capitalizedFirst
        let subtitle = relative ? day.longDay : day.it("dMMMMyyyy")
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    if !ThemeStore.shared.liquidGlass {
                        Text(title)
                            .font(.m3(40, weight: 500, rounded: true))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Text(subtitle)
                        .font(.m3(16, weight: 500))
                        .foregroundStyle(Theme.secondaryInk)
                }
                Spacer(minLength: 0)
                if let jump, !ThemeStore.shared.liquidGlass {
                    Button(action: jump.action) {
                        Label { Text(jump.title) } icon: { Icon("today") }
                    }
                    .buttonStyle(.m3(.tonal, size: .s))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            let chips = statusChips(content)
            if !chips.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(chips, id: \.text) { chip in chip }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private func statusChips(_ content: Content) -> [StatusChip] {
        var chips: [StatusChip] = []
        let tests = content.testCount
        if tests > 0 {
            chips.append(StatusChip(text: tests == 1 ? "1 verifica" : "\(tests) verifiche", icon: "test",
                                    container: Theme.tertiaryContainer, foreground: Theme.onTertiaryContainer))
        }
        let homework = content.homework.count
        if homework > 0 {
            let done = content.completedHomework
            chips.append(StatusChip(text: done == homework ? "Compiti fatti" : (homework == 1 ? "1 compito" : "\(homework) compiti"),
                                    icon: done == homework ? "checkCircle" : "book"))
        }
        for kind in Set(content.absences.map(\.kind)).sorted(by: { $0.title < $1.title }) {
            chips.append(StatusChip(text: kind.title, icon: "userClock",
                                    container: Theme.poorContainer, foreground: Theme.onPoorContainer))
        }
        if chips.isEmpty {
            if model.calendarStatus(on: day)?.isHoliday == true {
                chips.append(StatusChip(text: "Vacanza", icon: "beach", container: Theme.goodContainer,
                                        foreground: Theme.onGoodContainer))
            } else if day.isWeekend {
                chips.append(StatusChip(text: "Fine settimana", icon: "sun", container: Theme.goodContainer,
                                        foreground: Theme.onGoodContainer))
            }
        }
        if isPastOrToday, !content.lessons.isEmpty {
            let hours = content.lessons.reduce(0) { $0 + Int($1.duration) }
            chips.append(StatusChip(text: hours == 1 ? "1 ora di lezione" : "\(hours) ore di lezione", icon: "bookText",
                                    container: Theme.surfaceContainerHigh, foreground: Theme.onSurfaceVariant))
        }
        return chips
    }

    // MARK: Sezioni

    @ViewBuilder
    private func agendaSections(_ content: Content) -> some View {
        let testsAndEvents = content.testsAndEvents
        if !testsAndEvents.isEmpty {
            SegmentedSection(section: .testsAndEvents, title: "Verifiche ed eventi", icon: "test", tint: Theme.tertiary,
                             trailing: "\(testsAndEvents.count)") {
                ForEach(testsAndEvents) { event in
                    SegmentCell { AgendaEventRow(event: event) }
                }
            }
        }

        let homework = content.homework
        if !homework.isEmpty {
            SegmentedSection(section: .homework, title: "Compiti", icon: "book",
                             trailing: "\(content.completedHomework)/\(homework.count)",
                             progress: Double(content.completedHomework) / Double(homework.count)) {
                ForEach(homework) { event in
                    SegmentCell { AgendaEventRow(event: event) }
                }
            }
        }

        let absences = content.absences
        if !absences.isEmpty {
            SegmentedSection(section: .attendance, title: "Presenze", icon: "userClock", tint: Theme.poor) {
                ForEach(absences) { absence in
                    SegmentCell { AbsenceRow(absence: absence) }
                }
            }
        }
    }

    @ViewBuilder
    private func lessonsSection(_ content: Content) -> some View {
        let lessons = content.lessons
        if !lessons.isEmpty {
            SegmentedSection(section: .lessons, title: "Lezioni", icon: "bookText", tint: Theme.secondary,
                             trailing: "\(lessons.reduce(0) { $0 + Int($1.duration) }) ore") {
                ForEach(lessons) { lesson in
                    SegmentCell { LessonRow(lesson: lesson) }
                }
            }
        } else if !content.lessonsLoaded && !day.isWeekend {
            LoadingCard(text: "Carico le lezioni…")
        }
    }

    /// Niente in programma: una forma grande con l'icona, al centro.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Shaped(shape: day.isWeekend ? .sunny : .cookie9Sided, fill: Theme.tertiaryContainer, size: 88) {
                Icon(day.isWeekend ? "sun" : "checkSeal", size: 40)
                    .foregroundStyle(Theme.onTertiaryContainer)
            }
            VStack(spacing: 4) {
                Text(day.isWeekend ? "Goditi il weekend" : "Niente in programma")
                    .font(.m3(22, weight: 500, rounded: true))
                    .foregroundStyle(Theme.ink)
                Text("Nessun compito, verifica o evento per questo giorno.")
                    .font(.m3(14))
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(Theme.surfaceContainerLow, in: .rect(cornerRadius: Theme.radii.xl, style: .continuous))
    }
}
