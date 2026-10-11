import SwiftUI

// MARK: - Materie e docenti

struct SubjectsView: View {
    @Environment(AppModel.self) private var model

    private var sortedSubjects: [Subject] { model.subjects.sorted { $0.order < $1.order } }

    var body: some View {
        content
            .overlay {
                if model.subjects.isEmpty {
                    ContentUnavailableView("Nessuna materia", systemImage: "books.vertical")
                }
            }
            .screenTitle("Materie")
            .refreshable { await model.loadGrades() }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        ScrollView {
            // Le card della stessa riga hanno tutte l'altezza della più alta (es. una materia
            // con molti docenti), con il contenuto sempre centrato in verticale.
            CardGrid(minWidth: 320, equalRowHeights: true) {
                ForEach(sortedSubjects) { subject in
                    NavigationLink {
                        SubjectDetailView(subjectId: subject.id, book: model.gradeBook, subjects: model.subjects)
                    } label: {
                        SubjectListRow(subject: subject, average: average(of: subject), showsChevron: true)
                            .frame(maxHeight: .infinity)
                            .card(padding: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .pagePadding()
            .padding(.bottom, Theme.bottomInset)
        }
        // A tutta pagina, così il messaggio "Nessuna materia" sta al centro della finestra.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedBackground()
        #else
        List {
            ForEach(sortedSubjects) { subject in
                NavigationLink {
                    SubjectDetailView(subjectId: subject.id, book: model.gradeBook, subjects: model.subjects)
                } label: {
                    SubjectListRow(subject: subject, average: average(of: subject))
                }
                .listRowBackground(Theme.surface)
            }
        }
        .themedList()
        #endif
    }

    private func average(of subject: Subject) -> Double? {
        model.gradeBook.subjects().first { $0.subjectId == subject.id }?.average
    }
}

private struct SubjectListRow: View {
    let subject: Subject
    let average: Double?
    var showsChevron = false

    var body: some View {
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
            Text(GradeFormat.average(average))
                .font(.numeral(17, weight: .bold))
                .foregroundStyle(Theme.gradeColor(value: average))
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
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
                    InlineProgress()
                } else if model.schoolbooks.isEmpty {
                    ContentUnavailableView("Nessun libro", systemImage: "books.vertical",
                                           description: Text("La scuola non ha pubblicato le adozioni."))
                }
            }
            .screenTitle("Libri di testo")
            .task {
                loading = true
                await model.loadSchoolbooks()
                loading = false
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(model.schoolbooks) { course in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(course.name)
                        CardGrid(minWidth: 380, equalRowHeights: true) {
                            ForEach(course.books) { book in
                                BookRow(book: book)
                                    .frame(maxHeight: .infinity, alignment: .top)
                                    .card(padding: 14)
                            }
                        }
                    }
                }
            }
            .pagePadding()
            .padding(.bottom, Theme.bottomInset)
        }
        // A tutta pagina: altrimenti, senza libri, la pagina è larga quanto il suo contenuto
        // (cioè nulla) e il messaggio o la rotella restano schiacciati in una colonna.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedBackground()
        #else
        List {
            ForEach(model.schoolbooks) { course in
                Section(course.name) {
                    ForEach(course.books) { book in
                        BookRow(book: book)
                            .padding(.vertical, 4)
                            .listRowBackground(Theme.surface)
                    }
                }
            }
        }
        .themedList()
        #endif
    }
}

private struct BookRow: View {
    let book: Schoolbook

    var body: some View {
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
                #if os(macOS)
                // Su macOS i due riepiloghi stanno affiancati; la prossima vacanza ha meno
                // contenuto, quindi la sua card è più stretta.
                HStack(alignment: .top, spacing: 14) {
                    yearProgress
                    nextHoliday
                        .frame(width: 300)
                }
                .fixedSize(horizontal: false, vertical: true)
                #else
                yearProgress
                nextHoliday
                #endif
                holidayList
            }
            .pagePadding()
            .padding(.bottom, 24)
        }
        .themedBackground()
        .screenTitle("Calendario")
        .task { if model.calendarDays.isEmpty { await model.loadCalendar() } }
    }

    @ViewBuilder
    private var yearProgress: some View {
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
            .frame(maxHeight: .infinity, alignment: .top)
            .card()
        }
    }

    @ViewBuilder
    private var nextHoliday: some View {
        if let next = holidays.first(where: { $0.end >= Date().startOfDay }) {
            let daysLeft = CVDate.calendar.dateComponents([.day], from: Date().startOfDay, to: next.start).day ?? 0
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Prossima vacanza", color: Theme.accent)
                // Su macOS data e giorni mancanti stanno al centro dello spazio sotto l'occhiello.
                VStack(alignment: Platform.isMac ? .center : .leading, spacing: 8) {
                    Text(range(next))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(daysLeft <= 0 ? "Sei in vacanza!" : "Tra \(daysLeft) giorni")
                        .foregroundStyle(Theme.secondaryInk)
                }
                .multilineTextAlignment(Platform.isMac ? .center : .leading)
                .frame(maxWidth: Platform.isMac ? .infinity : nil,
                       maxHeight: Platform.isMac ? .infinity : nil)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .card()
        }
    }

    @ViewBuilder
    private var holidayList: some View {
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

    private func range(_ h: (start: Date, end: Date)) -> String {
        h.start.isSameDay(as: h.end) ? h.start.longDay : "\(h.start.shortDay) – \(h.end.shortDay)"
    }
}
