import SwiftUI

// MARK: - Materie e docenti

struct SubjectsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(model.subjects.sorted { $0.order < $1.order }) { subject in
                let summary = model.gradeBook.subjects().first { $0.subjectId == subject.id }
                NavigationLink {
                    SubjectDetailView(subjectId: subject.id, book: model.gradeBook, subjects: model.subjects)
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Theme.subjectColor(subject.id))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(subject.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(Theme.ink)
                            if !subject.teachers.isEmpty {
                                Text(subject.teachers.joined(separator: ", "))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryInk)
                            }
                        }
                        Spacer()
                        Text(GradeFormat.average(summary?.average))
                            .font(.numeral(17, weight: .bold))
                            .foregroundStyle(Theme.gradeColor(value: summary?.average))
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .themedList()
        .overlay {
            if model.subjects.isEmpty {
                ContentUnavailableView("Nessuna materia", systemImage: "books.vertical")
            }
        }
        .navigationTitle("Materie")
        .refreshable { await model.loadGrades() }
    }
}

// MARK: - Libri di testo

struct SchoolbooksView: View {
    @Environment(AppModel.self) private var model
    @State private var loading = false

    var body: some View {
        List {
            ForEach(model.schoolbooks) { course in
                Section(course.name) {
                    ForEach(course.books) { book in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(book.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                if let price = book.price, price > 0 {
                                    Text(price, format: .currency(code: "EUR"))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(Theme.secondaryInk)
                                }
                            }
                            Text([book.subject, book.volume].compactMap { $0 }.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(Theme.accent)
                            Text([book.author, book.publisher].compactMap { $0 }.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryInk)
                            HStack(spacing: 6) {
                                if book.toBuy { tag("Da acquistare", Theme.fair) }
                                if book.inUse { tag("Già in uso", Theme.good) }
                                if book.recommended { tag("Consigliato", Theme.neutral) }
                                Spacer()
                                if !book.isbn.isEmpty {
                                    Text("ISBN \(book.isbn)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(Theme.secondaryInk)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Theme.surface)
                    }
                }
            }
        }
        .themedList()
        .overlay {
            if loading && model.schoolbooks.isEmpty {
                ProgressView()
            } else if model.schoolbooks.isEmpty {
                ContentUnavailableView("Nessun libro", systemImage: "books.vertical",
                                       description: Text("La scuola non ha pubblicato le adozioni."))
            }
        }
        .navigationTitle("Libri di testo")
        .task {
            loading = true
            await model.loadSchoolbooks()
            loading = false
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Pill(text: text, color: color, font: .caption2.weight(.bold))
    }
}

// MARK: - Calendario scolastico

struct SchoolCalendarView: View {
    @Environment(AppModel.self) private var model

    /// Periodi consecutivi di vacanza nei giorni feriali.
    private var holidays: [(start: Date, end: Date)] {
        let days = model.calendarDays.sorted { $0.date < $1.date }
        var result: [(start: Date, end: Date)] = []
        var current: (start: Date, end: Date)?
        for day in days {
            if day.isHoliday && !day.date.isWeekend {
                if let c = current, day.date.timeIntervalSince(c.end) <= 3 * 86_400 {
                    current = (c.start, day.date)
                } else {
                    if let c = current { result.append(c) }
                    current = (day.date, day.date)
                }
            }
        }
        if let current { result.append(current) }
        return result
    }

    private var stats: (done: Int, total: Int) {
        let school = model.calendarDays.filter(\.isSchoolDay)
        return (school.filter { $0.date < Date().startOfDay }.count, school.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if stats.total > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        Eyebrow(text: "Anno scolastico")
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(stats.done)")
                                .font(.numeral(34, weight: .bold))
                            Text("di \(stats.total) giorni di lezione")
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        ProgressView(value: Double(stats.done), total: Double(max(stats.total, 1)))
                            .tint(Theme.accent)
                        Text("Mancano \(stats.total - stats.done) giorni di scuola")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    .card()
                }

                if let next = holidays.first(where: { $0.end >= Date().startOfDay }) {
                    let daysLeft = CVDate.calendar.dateComponents([.day], from: Date().startOfDay, to: next.start).day ?? 0
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Prossima vacanza", color: Theme.accent)
                        Text(range(next))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(daysLeft <= 0 ? "Sei in vacanza!" : "Tra \(daysLeft) giorni")
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    .card()
                }

                SectionHeader("Vacanze e chiusure")
                VStack(spacing: 12) {
                    ForEach(holidays.indices, id: \.self) { i in
                        let h = holidays[i]
                        HStack {
                            Image(systemName: h.end < Date().startOfDay ? "checkmark.circle" : "sun.max")
                                .foregroundStyle(h.end < Date().startOfDay ? Theme.secondaryInk : Theme.fair)
                                .frame(width: 26)
                            Text(range(h))
                                .foregroundStyle(h.end < Date().startOfDay ? Theme.secondaryInk : Theme.ink)
                            Spacer()
                            let count = (CVDate.calendar.dateComponents([.day], from: h.start, to: h.end).day ?? 0) + 1
                            Text(count == 1 ? "1 giorno" : "\(count) giorni")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryInk)
                        }
                        if i != holidays.count - 1 { Divider().overlay(Theme.separator) }
                    }
                    if holidays.isEmpty {
                        Text("Il calendario non è ancora disponibile.")
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                .card()
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .themedBackground()
        .navigationTitle("Calendario")
        .task { if model.calendarDays.isEmpty { await model.loadCalendar() } }
    }

    private func range(_ h: (start: Date, end: Date)) -> String {
        h.start.isSameDay(as: h.end) ? h.start.longDay : "\(h.start.shortDay) – \(h.end.shortDay)"
    }
}
