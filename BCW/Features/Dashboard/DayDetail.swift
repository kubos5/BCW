import SwiftUI

/// Tutto ciò che riguarda un giorno: compiti, verifiche ed eventi, presenze
/// e — per i giorni passati — le lezioni svolte, in una sezione separata.
struct DayDetail: View {
    @Environment(AppModel.self) private var model
    let day: Date

    /// Larghezza disponibile: su macOS, se c'è spazio, le lezioni vanno in una colonna a parte.
    @State private var width: CGFloat = 0

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

    private func splitsLessons(_ content: Content) -> Bool {
        Platform.isMac && isPastOrToday && width >= 580 && !(day.isWeekend && content.lessons.isEmpty)
    }

    var body: some View {
        let content = makeContent()
        VStack(alignment: .leading, spacing: 18) {
            header(content)

            if splitsLessons(content) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        if !content.hasAgenda { emptyState }
                        agendaSections(content)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    VStack(alignment: .leading, spacing: 18) {
                        lessonsSection(content)
                        if content.lessons.isEmpty && content.lessonsLoaded {
                            noLessons
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            } else {
                if !content.hasAgenda && (content.lessons.isEmpty || !isPastOrToday) {
                    emptyState
                }
                agendaSections(content)
                if isPastOrToday {
                    lessonsSection(content)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // Anche dopo ogni aggiornamento completo, che azzera le lezioni già scaricate:
        // altrimenti, aprendo l'app su un giorno passato, resterebbero "in caricamento".
        .task(id: [day.timeIntervalSince1970, model.lastUpdated?.timeIntervalSince1970 ?? 0]) {
            if isPastOrToday {
                await model.ensureLessons(from: day.startOfWeek, to: day.startOfWeek.adding(days: 6))
            }
        }
    }

    @ViewBuilder
    private func agendaSections(_ content: Content) -> some View {
        let testsAndEvents = content.testsAndEvents
        if !testsAndEvents.isEmpty {
            let lastID = testsAndEvents.last?.id
            section(.testsAndEvents, title: "Verifiche ed eventi", symbol: "pencil.and.list.clipboard") {
                ForEach(testsAndEvents) { event in
                    AgendaEventRow(event: event)
                    if event.id != lastID { divider }
                }
            }
        }

        let homework = content.homework
        if !homework.isEmpty {
            let lastID = homework.last?.id
            section(.homework, title: "Compiti", symbol: "book.closed",
                    trailing: "\(content.completedHomework)/\(homework.count)") {
                ForEach(homework) { event in
                    AgendaEventRow(event: event)
                    if event.id != lastID { divider }
                }
            }
        }

        let absences = content.absences
        if !absences.isEmpty {
            let lastID = absences.last?.id
            section(.attendance, title: "Presenze", symbol: "person.badge.clock") {
                ForEach(absences) { absence in
                    AbsenceRow(absence: absence)
                    if absence.id != lastID { divider }
                }
            }
        }
    }

    private var noLessons: some View {
        Label("Nessuna lezione registrata", systemImage: "text.book.closed")
            .font(.subheadline)
            .foregroundStyle(Theme.secondaryInk)
            .frame(maxWidth: .infinity)
            .card()
    }

    private func header(_ content: Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.longDay)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.ink)
            if let status = statusText(content) {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(.horizontal, 4)
    }

    private func statusText(_ content: Content) -> String? {
        var parts: [String] = []
        let tests = content.testCount
        if tests > 0 { parts.append(tests == 1 ? "1 verifica" : "\(tests) verifiche") }
        let homework = content.homework.count
        if homework > 0 { parts.append(homework == 1 ? "1 compito" : "\(homework) compiti") }
        if parts.isEmpty {
            if model.calendarStatus(on: day)?.isHoliday == true { return "Giorno di vacanza" }
            if day.isWeekend { return "Fine settimana" }
            return nil
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func lessonsSection(_ content: Content) -> some View {
        let lessons = content.lessons
        if !lessons.isEmpty {
            let lastID = lessons.last?.id
            section(.lessons, title: "Lezioni", symbol: "text.book.closed", trailing: "\(lessons.reduce(0) { $0 + Int($1.duration) }) ore") {
                ForEach(lessons) { lesson in
                    LessonRow(lesson: lesson)
                    if lesson.id != lastID { divider }
                }
            }
        } else if !content.lessonsLoaded && !day.isWeekend {
            LoadingCard(text: "Carico le lezioni…")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: day.isWeekend ? "sun.max" : "checkmark.seal")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accent)
            Text(day.isWeekend ? "Goditi il weekend" : "Niente in programma")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text("Nessun compito, verifica o evento per questo giorno.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .card()
    }

    private var divider: some View {
        Divider().overlay(Theme.separator)
    }

    private func section<SectionContent: View>(_ id: DashboardSection, title: String, symbol: String, trailing: String? = nil,
                                               @ViewBuilder content: @escaping () -> SectionContent) -> some View {
        CollapsibleCard(section: id, title: title, symbol: symbol, trailing: trailing, content: content)
    }
}

/// Card con intestazione toccabile che comprime o espande il contenuto.
/// Lo stato è ricordato tra un avvio e l'altro.
struct CollapsibleCard<Content: View>: View {
    @Environment(AppModel.self) private var model
    let section: DashboardSection
    let title: String
    let symbol: String
    var trailing: String?
    @ViewBuilder let content: () -> Content

    private var isCollapsed: Bool { model.preferences.isCollapsed(section) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { model.preferences.toggleCollapsed(section) }
            } label: {
                HStack {
                    Label(title, systemImage: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.secondaryInk)
                    Spacer()
                    if let trailing {
                        Text(trailing)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryInk)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(HeaderButtonStyle())
            .accessibilityHint(isCollapsed ? "Espande la sezione" : "Comprime la sezione")
            .sensoryFeedback(.selection, trigger: isCollapsed)

            CollapsibleContent(isExpanded: !isCollapsed, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) { content() }
            }
        }
        .card()
    }
}
