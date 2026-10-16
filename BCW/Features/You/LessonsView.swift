import SwiftUI

struct LessonsView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .day
    @State private var day = Date().startOfDay
    @State private var allLessons: [Lesson] = []
    @State private var loadingAll = false
    @State private var subjectFilter: Int?

    enum Mode: String, CaseIterable, Identifiable {
        case day, subject
        var id: String { rawValue }
        var title: String { self == .day ? "Per giorno" : "Per materia" }
    }

    var body: some View {
        content
            .pageChrome("Lezioni", style: .inline)
            .task(id: day) {
                await model.ensureLessons(from: day.startOfWeek, to: day.startOfWeek.adding(days: 6))
            }
            .task(id: mode) {
                guard mode == .subject, allLessons.isEmpty else { return }
                loadingAll = true
                allLessons = (try? await model.fetchLessons(from: CVDate.schoolYear().start, to: Date())) ?? []
                loadingAll = false
            }
    }

    private var modePicker: some View {
        SegmentedButtons(selection: $mode, options: Mode.allCases.map { ($0, $0.title, nil) })
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                modePicker

                switch mode {
                case .day:
                    dayNavigator
                    dayLessons
                case .subject:
                    if !loadingAll { subjectChips }
                    subjectCards
                }
            }
            .pagePadding()
            .padding(.bottom, 32)
        }
        .tracksPageScroll()
        .themedBackground()
    }

    private var dayNavigator: some View {
        HStack(spacing: 8) {
            IconButton("chevronLeft", label: "Giorno precedente", kind: .tonal) { day = previousSchoolDay(from: day) }
            DateField(date: $day, range: CVDate.schoolYear().start...Date())
            IconButton("chevronRight", label: "Giorno successivo", kind: .tonal) {
                day = min(Date().startOfDay, nextSchoolDay(from: day))
            }
            .disabled(day.isToday)
        }
    }

    @ViewBuilder
    private var dayLessons: some View {
        Text(day.longDay)
            .font(.m3(22, weight: 500, rounded: true))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 4)

        let lessons = model.lessons(on: day)
        if lessons.isEmpty {
            if day.startOfDay > Date().startOfDay {
                EmptyState("Nessuna lezione", icon: "bookText",
                           description: "Le lezioni compaiono nel registro dopo essere state svolte.")
            } else if model.hasLoadedLessons(on: day) {
                EmptyState("Nessuna lezione", icon: "bookText",
                           description: day.isWeekend ? "È il fine settimana." : "Non ci sono lezioni registrate per questo giorno.")
            } else {
                LoadingCard()
            }
        } else {
            VStack(spacing: 14) {
                ForEach(lessons) { lesson in
                    LessonRow(lesson: lesson)
                    if lesson.id != lessons.last?.id { M3Divider() }
                }
            }
            .card()
        }
    }

    private var subjectGroups: [(id: Int, name: String, lessons: [Lesson])] {
        Dictionary(grouping: allLessons, by: { $0.subjectId ?? 0 })
            .map { (id: $0.key, name: $0.value.first?.subjectName ?? "", lessons: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.name < $1.name }
    }

    private var subjectChips: some View {
        ChipRow {
            FilterChip(title: "Tutte", isSelected: subjectFilter == nil) { subjectFilter = nil }
            ForEach(subjectGroups, id: \.id) { s in
                FilterChip(title: s.name, isSelected: subjectFilter == s.id) {
                    subjectFilter = subjectFilter == s.id ? nil : s.id
                }
            }
        }
    }

    @ViewBuilder
    private var subjectCards: some View {
        if loadingAll {
            LoadingCard(text: "Carico il registro dell'anno…")
        } else {
            CardGrid(minWidth: 380, spacing: 12) {
                ForEach(subjectGroups.filter { subjectFilter == nil || $0.id == subjectFilter }, id: \.id) { subject in
                    let topics = subject.lessons.filter { !$0.topic.isEmpty }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            SubjectTag(name: subject.name, id: subject.id)
                            Spacer()
                            Text("\(subject.lessons.reduce(0) { $0 + Int($1.duration) }) ore")
                                .font(.m3(12))
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        ForEach(topics.prefix(subjectFilter == nil ? 4 : 200)) { lesson in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(lesson.date.shortDay)
                                    .font(.m3(14).monospacedDigit())
                                    .foregroundStyle(Theme.secondaryInk)
                                    .frame(width: 56, alignment: .leading)
                                Text(lesson.topic)
                                    .font(.m3(14))
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        if subjectFilter == nil && topics.count > 4 {
                            Button("Mostra tutti i \(topics.count) argomenti") { subjectFilter = subject.id }
                                .buttonStyle(LinkButtonStyle())
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .card()
                }
            }
        }
    }

    private func previousSchoolDay(from date: Date) -> Date {
        var d = date.adding(days: -1)
        while d.isWeekend { d = d.adding(days: -1) }
        return d
    }

    private func nextSchoolDay(from date: Date) -> Date {
        var d = date.adding(days: 1)
        while d.isWeekend { d = d.adding(days: 1) }
        return d
    }
}
