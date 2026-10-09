import Charts
import SwiftUI

struct GradesView: View {
    @Environment(AppModel.self) private var model
    #if DEBUG
    /// Per gli screenshot di sviluppo: `-BCWOpenSubject YES` apre la materia con il nome più
    /// lungo (il caso peggiore per la barra della finestra).
    @State private var debugSubject: SubjectSummary?
    #endif

    var body: some View {
        PlatformNavigationStack {
            GradeBookView(book: model.gradeBook, subjects: model.subjects, allowsRefresh: true)
                .screenTitle("Voti")
                .navigationDestination(for: SubjectSummary.self) { summary in
                    SubjectDetailView(subjectId: summary.subjectId, book: model.gradeBook, subjects: model.subjects)
                        .pushedPageActions()
                }
                #if DEBUG
                .navigationDestination(item: $debugSubject) { summary in
                    SubjectDetailView(subjectId: summary.subjectId, book: model.gradeBook, subjects: model.subjects)
                        .pushedPageActions()
                }
                .task(id: model.grades.count) {
                    guard UserDefaults.standard.bool(forKey: "BCWOpenSubject"), debugSubject == nil else { return }
                    debugSubject = model.gradeBook.subjects().max { $0.name.count < $1.name.count }
                }
                #endif
        }
    }
}

/// Vista riutilizzabile del libretto voti (usata anche per l'anno precedente).
struct GradeBookView: View {
    @Environment(AppModel.self) private var model
    let book: GradeBook
    var subjects: [Subject] = []
    var allowsRefresh = false

    enum Section: String, CaseIterable, Identifiable {
        case recent, subjects
        var id: String { rawValue }
        var title: String { self == .recent ? "Ultimi voti" : "Materie" }
    }

    @State private var section: Section = .recent
    @State private var period: Int?
    @State private var subjectFilter: Int?
    @State private var expanded: Set<Int> = []

    private var filteredGrades: [Grade] {
        book.grades(in: period)
            .filter { subjectFilter == nil || $0.subjectId == subjectFilter }
            .sorted { $0.date > $1.date }
    }

    private var allSubjects: [(id: Int, name: String)] {
        let pairs = Dictionary(grouping: book.grades, by: \.subjectId).compactMap { id, list in
            list.first.map { (id: id, name: $0.subjectName) }
        }
        return pairs.sorted { $0.name < $1.name }
    }

    var body: some View {
        content
            .refreshable {
                if allowsRefresh { await model.loadGrades() }
            }
            .toolbar {
                ToolbarItem(placement: .trailingBar) {
                    Menu {
                        Picker("Periodo", selection: $period) {
                            Text("Tutto l'anno").tag(Int?.none)
                            ForEach(book.activePeriods) { Text($0.name).tag(Optional($0.position)) }
                        }
                        Picker("Materia", selection: $subjectFilter) {
                            Text("Tutte le materie").tag(Int?.none)
                            ForEach(allSubjects, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                        }
                        .pickerStyle(.menu)
                        if period != nil || subjectFilter != nil {
                            Button("Rimuovi filtri", systemImage: "xmark.circle", role: .destructive) {
                                period = nil
                                subjectFilter = nil
                            }
                        }
                    } label: {
                        Image(systemName: period != nil || subjectFilter != nil
                              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
    }

    @ViewBuilder
    private var banner: some View {
        if allowsRefresh, let error = model.lastError {
            StatusBanner(message: error, symbol: model.isOffline ? "wifi.slash" : "exclamationmark.triangle")
        }
    }

    private var emptyBook: some View {
        ContentUnavailableView("Nessun voto", systemImage: "graduationcap",
                               description: Text("I voti appariranno qui non appena verranno registrati."))
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
    }

    private var sectionPicker: some View {
        Picker("Sezione", selection: $section) {
            ForEach(Section.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        if book.grades.isEmpty {
            ScrollView {
                VStack(spacing: 20) {
                    banner
                    emptyBook
                }
                .pagePadding()
            }
            .themedBackground()
        } else {
            // Medie e andamento restano a sinistra; a destra l'elenco, a griglia se c'è spazio.
            SplitColumns(sideWidth: 350) {
                AverageHero(book: book, selectedPeriod: $period)
                TrendCard(book: book, period: period, subjectId: subjectFilter)
            } main: {
                banner
                sectionPicker
                    .labelsHidden()
                    .fixedSize()
                filters
                switch section {
                case .recent: recentList
                case .subjects: subjectList
                }
            }
            .animation(.snappy, value: period)
            .animation(.snappy, value: subjectFilter)
            .animation(.snappy, value: section)
        }
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                banner

                if book.grades.isEmpty {
                    emptyBook
                } else {
                    AverageHero(book: book, selectedPeriod: $period)
                    TrendCard(book: book, period: period, subjectId: subjectFilter)

                    sectionPicker

                    filters

                    switch section {
                    case .recent: recentList
                    case .subjects: subjectList
                    }
                }
            }
            .pagePadding()
            .padding(.bottom, 24)
            .animation(.snappy, value: period)
            .animation(.snappy, value: subjectFilter)
            .animation(.snappy, value: section)
        }
        .themedBackground()
        #endif
    }

    @ViewBuilder
    private var filters: some View {
        let allSubjects = allSubjects
        ChipRow {
            FilterChip(title: "Tutto l'anno", isSelected: period == nil) { period = nil }
            ForEach(book.activePeriods) { p in
                FilterChip(title: p.name, isSelected: period == p.position) {
                    period = period == p.position ? nil : p.position
                }
            }
            ChipDivider()
            Menu {
                Button("Tutte le materie") { subjectFilter = nil }
                ForEach(allSubjects, id: \.id) { s in
                    Button(s.name) { subjectFilter = s.id }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "books.vertical").imageScale(.small)
                    Text(allSubjects.first { $0.id == subjectFilter }?.name ?? "Materia")
                        .lineLimit(1)
                    Image(systemName: "chevron.down").imageScale(.small)
                }
                .font(.subheadline.weight(subjectFilter == nil ? .regular : .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(subjectFilter == nil ? Theme.ink : .white)
                .background(subjectFilter == nil ? AnyShapeStyle(Theme.surface) : AnyShapeStyle(Theme.accent), in: .capsule)
                .overlay { Capsule().strokeBorder(Theme.separator, lineWidth: subjectFilter == nil ? 0.5 : 0) }
            }
            .plainMenuOnMac()
        }
    }

    @ViewBuilder
    private var recentList: some View {
        let filteredGrades = filteredGrades
        if filteredGrades.isEmpty {
            ContentUnavailableView("Nessun voto", systemImage: "line.3.horizontal.decrease.circle",
                                   description: Text("Nessun voto corrisponde ai filtri selezionati."))
                .frame(maxWidth: .infinity)
        } else {
            CardGrid(minWidth: 340) {
                ForEach(filteredGrades) { grade in
                    GradeCard(grade: grade, book: book, isExpanded: expanded.contains(grade.id)) {
                        withAnimation(.snappy) {
                            if expanded.contains(grade.id) { expanded.remove(grade.id) } else { expanded.insert(grade.id) }
                        }
                    }
                }
            }
        }
    }

    private var subjectList: some View {
        CardGrid(minWidth: 300) {
            ForEach(book.subjects(in: period).filter { subjectFilter == nil || $0.subjectId == subjectFilter }) { summary in
                NavigationLink(value: summary) {
                    SubjectRow(summary: summary, target: model.preferences.targetAverage)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Media generale

private struct AverageHero: View {
    let book: GradeBook
    @Binding var selectedPeriod: Int?

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 20) {
                AverageRing(value: book.average(period: selectedPeriod), size: 118, lineWidth: 11)
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: selectedPeriod == nil ? "Media generale" : "Media del periodo")
                    Text(selectedPeriod.flatMap { p in book.activePeriods.first { $0.position == p }?.name } ?? "Tutto l'anno")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    let count = book.grades(in: selectedPeriod).filter(\.countsTowardAverage).count
                    Text("\(count) voti che fanno media")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                    let insufficient = book.subjects(in: selectedPeriod).filter { ($0.average ?? 10) < 6 }.count
                    if insufficient > 0 {
                        Label(insufficient == 1 ? "1 insufficienza" : "\(insufficient) insufficienze", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.poor)
                    } else {
                        Label("Nessuna insufficienza", systemImage: "checkmark.seal.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.good)
                    }
                }
                Spacer(minLength: 0)
            }

            if book.activePeriods.count > 0 {
                HStack(spacing: 10) {
                    ForEach(book.activePeriods) { period in
                        Button {
                            withAnimation(.snappy) {
                                selectedPeriod = selectedPeriod == period.position ? nil : period.position
                            }
                        } label: {
                            PeriodTile(name: period.name, average: book.average(period: period.position),
                                       isSelected: selectedPeriod == period.position)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card(padding: 18)
    }
}

private struct PeriodTile: View {
    let name: String
    let average: Double?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            AverageRing(value: average, size: 30, lineWidth: 4, showsLabel: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(GradeFormat.average(average))
                    .font(.numeral(19, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Theme.accentSoft : Theme.background.opacity(0.6),
                    in: .rect(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Theme.separator, lineWidth: isSelected ? 1.5 : 0.5)
        }
    }
}

// MARK: - Andamento

private struct TrendCard: View {
    let book: GradeBook
    let period: Int?
    let subjectId: Int?

    var body: some View {
        let points = book.runningAverage(for: subjectId, period: period)
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow(text: "Andamento della media")
                    Spacer()
                    if let first = points.first?.value, let last = points.last?.value {
                        let delta = last - first
                        Label(GradeFormat.average(abs(delta)), systemImage: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(delta >= 0 ? Theme.good : Theme.poor)
                    }
                }
                Chart {
                    RuleMark(y: .value("Sufficienza", 6))
                        .foregroundStyle(Theme.secondaryInk.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    ForEach(points.indices, id: \.self) { i in
                        AreaMark(x: .value("Data", points[i].date), yStart: .value("Base", 3),
                                 yEnd: .value("Media", points[i].value))
                            .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.25), Theme.accent.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Data", points[i].date), y: .value("Media", points[i].value))
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: 3...10)
                .chartYAxis {
                    AxisMarks(values: [4, 6, 8, 10]) { _ in
                        AxisGridLine().foregroundStyle(Theme.separator)
                        AxisValueLabel().font(.caption2)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.caption2)
                    }
                }
                .frame(height: Platform.isMac ? 190 : 150)
            }
            .card()
        }
    }
}

// MARK: - Righe

struct GradeCard: View {
    let grade: Grade
    let book: GradeBook
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                GradeBadge(grade: grade, size: 50)
                VStack(alignment: .leading, spacing: 3) {
                    SubjectTag(name: grade.subjectName, id: grade.subjectId)
                    Text("\(grade.kind) · \(grade.date.shortDay)")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                    if let notes = grade.notes, !isExpanded {
                        Text(notes)
                            .font(.footnote)
                            .foregroundStyle(Theme.ink.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryInk)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }

            CollapsibleContent(isExpanded: isExpanded, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    if let notes = grade.notes {
                        Text(notes)
                            .font(.callout)
                            .foregroundStyle(Theme.ink)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.background.opacity(0.7), in: .rect(cornerRadius: 12, style: .continuous))
                    }
                    DetailRow(label: "Data", value: grade.date.longDay)
                    DetailRow(label: "Tipo", value: grade.kind)
                    if !grade.periodName.isEmpty { DetailRow(label: "Periodo", value: grade.periodName) }
                    if let teacher = grade.teacherName { DetailRow(label: "Docente", value: teacher) }
                    if let weight = grade.weight, weight != 1, weight > 0 {
                        DetailRow(label: "Peso", value: GradeFormat.short(weight * 100) + "%")
                    }
                    if let value = grade.value { DetailRow(label: "Valore", value: GradeFormat.average(value)) }
                    if !grade.countsTowardAverage {
                        Label(grade.canceled ? "Voto annullato" : "Non fa media", systemImage: "info.circle")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.neutral)
                    } else if let impact {
                        HStack {
                            Text("Effetto sulla media di materia")
                                .foregroundStyle(Theme.secondaryInk)
                            Spacer()
                            Label(GradeFormat.average(abs(impact)), systemImage: impact >= 0 ? "arrow.up" : "arrow.down")
                                .foregroundStyle(impact >= 0 ? Theme.good : Theme.poor)
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .card(padding: 14)
        .contentShape(.rect)
        .onTapGesture(perform: onTap)
    }

    /// Di quanto questo voto ha spostato la media della materia.
    private var impact: Double? {
        let sameSubject = book.grades.filter { $0.subjectId == grade.subjectId && $0.periodPosition == grade.periodPosition }
        let before = sameSubject.filter { $0.date < grade.date || ($0.date == grade.date && $0.id < grade.id) }
        guard let avgBefore = GradeBook.average(of: before, weighted: book.weighted),
              let avgAfter = GradeBook.average(of: before + [grade], weighted: book.weighted) else { return nil }
        return avgAfter - avgBefore
    }
}

struct SubjectRow: View {
    let summary: SubjectSummary
    let target: Double

    var body: some View {
        HStack(spacing: 14) {
            AverageRing(value: summary.average, size: 52, lineWidth: 5)
            VStack(alignment: .leading, spacing: 5) {
                Text(summary.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    ForEach(summary.grades.prefix(6)) { g in
                        Text(g.displayValue)
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(Theme.gradeColor(g))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.gradeColor(g).opacity(0.12), in: .capsule)
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryInk)
        }
        .card(padding: 14)
    }
}
