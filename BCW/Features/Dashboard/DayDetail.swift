import SwiftUI

/// Tutto ciò che riguarda un giorno: compiti, verifiche ed eventi, presenze
/// e — per i giorni passati — le lezioni svolte, in una sezione separata.
struct DayDetail: View {
    @Environment(AppModel.self) private var model
    let day: Date

    private var events: [AgendaEvent] {
        model.events(on: day)
            .filter { !(model.preferences.hideCompletedHomework && model.preferences.isCompleted($0)) }
    }

    private var homework: [AgendaEvent] { events.filter { $0.kind == .homework } }
    private var testsAndEvents: [AgendaEvent] {
        events.filter { $0.kind != .homework }.sorted { ($0.kind == .test ? 0 : 1, $0.begin) < ($1.kind == .test ? 0 : 1, $1.begin) }
    }
    private var absences: [AbsenceEvent] { model.absences(on: day) }
    private var lessons: [Lesson] { model.lessons(on: day) }
    private var isPastOrToday: Bool { day.startOfDay <= Date().startOfDay }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if homework.isEmpty && testsAndEvents.isEmpty && absences.isEmpty && (lessons.isEmpty || !isPastOrToday) {
                emptyState
            }

            if !testsAndEvents.isEmpty {
                section(.testsAndEvents, title: "Verifiche ed eventi", symbol: "pencil.and.list.clipboard") {
                    ForEach(testsAndEvents) { event in
                        AgendaEventRow(event: event)
                        if event.id != testsAndEvents.last?.id { divider }
                    }
                }
            }

            if !homework.isEmpty {
                section(.homework, title: "Compiti", symbol: "book.closed",
                        trailing: "\(homework.filter { model.preferences.isCompleted($0) }.count)/\(homework.count)") {
                    ForEach(homework) { event in
                        AgendaEventRow(event: event)
                        if event.id != homework.last?.id { divider }
                    }
                }
            }

            if !absences.isEmpty {
                section(.attendance, title: "Presenze", symbol: "person.badge.clock") {
                    ForEach(absences) { absence in
                        AbsenceRow(absence: absence)
                        if absence.id != absences.last?.id { divider }
                    }
                }
            }

            if isPastOrToday {
                lessonsSection
            }
        }
        .task(id: day) {
            if isPastOrToday {
                await model.ensureLessons(from: day.startOfWeek, to: day.startOfWeek.adding(days: 6))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.longDay)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.ink)
            if let status = statusText {
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(.horizontal, 4)
    }

    private var statusText: String? {
        var parts: [String] = []
        let tests = events.filter { $0.kind == .test }.count
        if tests > 0 { parts.append(tests == 1 ? "1 verifica" : "\(tests) verifiche") }
        if !homework.isEmpty { parts.append(homework.count == 1 ? "1 compito" : "\(homework.count) compiti") }
        if parts.isEmpty {
            if model.calendarStatus(on: day)?.isHoliday == true { return "Giorno di vacanza" }
            if day.isWeekend { return "Fine settimana" }
            return nil
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var lessonsSection: some View {
        if !lessons.isEmpty {
            section(.lessons, title: "Lezioni", symbol: "text.book.closed", trailing: "\(lessons.reduce(0) { $0 + Int($1.duration) }) ore") {
                ForEach(lessons) { lesson in
                    LessonRow(lesson: lesson)
                    if lesson.id != lessons.last?.id { divider }
                }
            }
        } else if !model.hasLoadedLessons(on: day) && !day.isWeekend {
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

    private func section<Content: View>(_ id: DashboardSection, title: String, symbol: String, trailing: String? = nil,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
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
