import SwiftUI

// MARK: - Materie e docenti

struct SubjectsView: View {
    @Environment(AppModel.self) private var model

    private var sortedSubjects: [Subject] { model.subjects.sorted { $0.order < $1.order } }

    var body: some View {
        content
            .overlay {
                if model.subjects.isEmpty {
                    EmptyState("Nessuna materia", icon: "library")
                }
            }
            .pageChrome("Materie", style: .inline)
            .refreshable { await model.loadGrades() }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            ListGroup {
                ForEach(sortedSubjects) { subject in
                    NavigationLink {
                        SubjectDetailView(subjectId: subject.id, book: model.gradeBook, subjects: model.subjects)
                    } label: {
                        SubjectListRow(subject: subject, average: average(of: subject))
                    }
                    .buttonStyle(.listRow)
                }
            }
            // Sull'iPad largo larga al massimo 860 punti (come la versione web).
            .readableWidth()
            .pagePadding()
            .padding(.bottom, Theme.bottomInset)
        }
        .tracksPageScroll()
        .themedBackground()
    }

    private func average(of subject: Subject) -> Double? {
        model.gradeBook.subjects().first { $0.subjectId == subject.id }?.average
    }
}

private struct SubjectListRow: View {
    let subject: Subject
    let average: Double?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Theme.subjectColor(subject.id))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(subject.name)
                    .font(.m3(16, weight: 550))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                if !subject.teachers.isEmpty {
                    Text(subject.teachers.joined(separator: ", "))
                        .font(.m3(13))
                        .foregroundStyle(Theme.secondaryInk)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer()
            Text(GradeFormat.average(average))
                .font(.numeral(18))
                .foregroundStyle(Theme.gradeColor(value: average))
            if showsChevron {
                Icon("chevronRight", size: 22)
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(14)
        .frame(minHeight: 56)
        .contentShape(.rect)
    }
}

// MARK: - Libri di testo

struct SchoolbooksView: View {
    @Environment(AppModel.self) private var model
    @State private var loading = false

    var body: some View {
        content
            .overlay {
                if loading && model.schoolbooks.isEmpty {
                    LoadingIndicator(size: 48)
                } else if model.schoolbooks.isEmpty {
                    EmptyState("Nessun libro", icon: "library", description: "La scuola non ha pubblicato le adozioni.")
                }
            }
            .pageChrome("Libri di testo", style: .inline)
            .task {
                loading = true
                await model.loadSchoolbooks()
                loading = false
            }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(model.schoolbooks) { course in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(course.name)
                        ListGroup {
                            ForEach(course.books) { book in
                                BookRow(book: book)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                        }
                    }
                }
            }
            .readableWidth()
            .pagePadding()
            .padding(.bottom, Theme.bottomInset)
        }
        .tracksPageScroll()
        .themedBackground()
    }
}

private struct BookRow: View {
    let book: Schoolbook

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(book.title)
                    .font(.m3(15, weight: 600))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if let price = book.price, price > 0 {
                    Text(price, format: .currency(code: "EUR"))
                        .font(.m3(14).monospacedDigit())
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            Text([book.subject, book.volume].compactMap { $0 }.joined(separator: " · "))
                .font(.m3(12))
                .foregroundStyle(Theme.primary)
            Text([book.author, book.publisher].compactMap { $0 }.joined(separator: " · "))
                .font(.m3(12))
                .foregroundStyle(Theme.secondaryInk)
            HStack(spacing: 6) {
                if book.toBuy { tag("Da acquistare", Theme.fair) }
                if book.inUse { tag("Già in uso", Theme.good) }
                if book.recommended { tag("Consigliato", Theme.neutral) }
                Spacer()
                if !book.isbn.isEmpty {
                    Text("ISBN \(book.isbn)")
                        .font(.m3(11).monospacedDigit())
                        .foregroundStyle(Theme.secondaryInk)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Pill(text: text, color: color, small: true)
    }
}

// MARK: - Calendario scolastico

struct SchoolCalendarView: View {
    @Environment(AppModel.self) private var model
    /// iPad largo con il contenuto largo almeno 640 punti: anno e prossima vacanza affiancati.
    @State private var wideSummary = false

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
            VStack(alignment: .leading, spacing: 24) {
                if wideSummary {
                    // iPad largo: le due card affiancate; la prossima vacanza, con meno contenuto,
                    // è più stretta (come la versione web).
                    HStack(alignment: .top, spacing: 12) {
                        yearProgress
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.card, in: .rect(cornerRadius: Theme.radii.li, style: .continuous))
                        nextHoliday
                            .frame(width: 300, alignment: .leading)
                            .frame(maxHeight: .infinity)
                            .background(Theme.card, in: .rect(cornerRadius: Theme.radii.li, style: .continuous))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Anno scolastico e prossima vacanza formano una lista segmentata.
                    ListGroup {
                        yearProgress
                        nextHoliday
                    }
                }
                VStack(alignment: .leading, spacing: 24) {
                    holidayList
                }
                .readableWidth()
            }
            .widthAtLeast(640, isOn: $wideSummary)
            .pagePadding()
            .padding(.bottom, 32)
        }
        .tracksPageScroll()
        .themedBackground()
        .pageChrome("Calendario", style: .inline)
        .task { if model.calendarDays.isEmpty { await model.loadCalendar() } }
    }

    @ViewBuilder
    private var yearProgress: some View {
        if stats.total > 0 {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Anno scolastico")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(stats.done)")
                        .font(.numeral(45))
                        .foregroundStyle(Theme.ink)
                    Text("di \(stats.total) giorni di lezione")
                        .font(.m3(16))
                        .foregroundStyle(Theme.secondaryInk)
                }
                WavyProgress(value: Double(stats.done), total: Double(max(stats.total, 1)))
                Text("Mancano \(stats.total - stats.done) giorni di scuola")
                    .font(.m3(12))
                    .foregroundStyle(Theme.secondaryInk)
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var nextHoliday: some View {
        if let next = holidays.first(where: { $0.end >= Date().startOfDay }) {
            let daysLeft = CVDate.calendar.dateComponents([.day], from: Date().startOfDay, to: next.start).day ?? 0
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Prossima vacanza", color: Theme.primary)
                VStack(alignment: .leading, spacing: 8) {
                    Text(range(next))
                        .font(.m3(22, weight: 500, rounded: true))
                        .foregroundStyle(Theme.ink)
                    Text(daysLeft <= 0 ? "Sei in vacanza!" : "Tra \(daysLeft) giorni")
                        .font(.m3(16))
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private var holidayList: some View {
        SectionHeader("Vacanze e chiusure")
        ListGroup {
            ForEach(holidays.indices, id: \.self) { i in
                let h = holidays[i]
                HStack(spacing: 12) {
                    Icon(h.end < Date().startOfDay ? "checkCircle" : "sun")
                        .foregroundStyle(h.end < Date().startOfDay ? Theme.secondaryInk : Theme.fair)
                    Text(range(h))
                        .font(.m3(15))
                        .foregroundStyle(h.end < Date().startOfDay ? Theme.secondaryInk : Theme.ink)
                    Spacer()
                    let count = (CVDate.calendar.dateComponents([.day], from: h.start, to: h.end).day ?? 0) + 1
                    Text(count == 1 ? "1 giorno" : "\(count) giorni")
                        .font(.m3(12))
                        .foregroundStyle(Theme.secondaryInk)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
            }
            if holidays.isEmpty {
                Text("Il calendario non è ancora disponibile.")
                    .font(.m3(14))
                    .foregroundStyle(Theme.secondaryInk)
                    .padding(16)
            }
        }
    }

    private func range(_ h: (start: Date, end: Date)) -> String {
        h.start.isSameDay(as: h.end) ? h.start.longDay : "\(h.start.shortDay) – \(h.end.shortDay)"
    }
}
