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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Vista", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .day: dayView
                case .subject: subjectView
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .themedBackground()
        .navigationTitle("Lezioni")
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

    @ViewBuilder
    private var dayView: some View {
        HStack {
            Button { day = previousSchoolDay(from: day) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            Spacer()
            DatePicker("Giorno", selection: $day, in: CVDate.schoolYear().start...Date(), displayedComponents: .date)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "it_IT"))
            Spacer()
            Button { day = min(Date().startOfDay, nextSchoolDay(from: day)) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .disabled(day.isToday)
        }

        Text(day.longDay)
            .font(.title2.weight(.semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 4)

        let lessons = model.lessons(on: day)
        if lessons.isEmpty {
            if model.hasLoadedLessons(on: day) {
                ContentUnavailableView("Nessuna lezione", systemImage: "text.book.closed",
                                       description: Text(day.isWeekend ? "È il fine settimana." : "Non ci sono lezioni registrate per questo giorno."))
            } else {
                LoadingCard()
            }
        } else {
            VStack(spacing: 14) {
                ForEach(lessons) { lesson in
                    LessonRow(lesson: lesson)
                    if lesson.id != lessons.last?.id { Divider().overlay(Theme.separator) }
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private var subjectView: some View {
        if loadingAll {
            LoadingCard(text: "Carico il registro dell'anno…")
        } else {
            let subjects = Dictionary(grouping: allLessons, by: { $0.subjectId ?? 0 })
                .map { (id: $0.key, name: $0.value.first?.subjectName ?? "", lessons: $0.value.sorted { $0.date > $1.date }) }
                .sorted { $0.name < $1.name }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(title: "Tutte", isSelected: subjectFilter == nil) { subjectFilter = nil }
                    ForEach(subjects, id: \.id) { s in
                        FilterChip(title: s.name, isSelected: subjectFilter == s.id) {
                            subjectFilter = subjectFilter == s.id ? nil : s.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()

            ForEach(subjects.filter { subjectFilter == nil || $0.id == subjectFilter }, id: \.id) { subject in
                let topics = subject.lessons.filter { !$0.topic.isEmpty }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SubjectTag(name: subject.name, id: subject.id)
                        Spacer()
                        Text("\(subject.lessons.reduce(0) { $0 + Int($1.duration) }) ore")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    ForEach(topics.prefix(subjectFilter == nil ? 4 : 200)) { lesson in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(lesson.date.shortDay)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.secondaryInk)
                                .frame(width: 52, alignment: .leading)
                            Text(lesson.topic)
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    if subjectFilter == nil && topics.count > 4 {
                        Button("Mostra tutti i \(topics.count) argomenti") { subjectFilter = subject.id }
                            .font(.footnote.weight(.semibold))
                    }
                }
                .card()
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
