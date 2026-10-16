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
                .navigationDestination(for: SubjectSummary.self) { summary in
                    SubjectDetailView(subjectId: summary.subjectId, book: model.gradeBook, subjects: model.subjects)
                }
                #if DEBUG
                .navigationDestination(item: $debugSubject) { summary in
                    SubjectDetailView(subjectId: summary.subjectId, book: model.gradeBook, subjects: model.subjects)
                }
                .task(id: model.grades.count) {
                    guard UserDefaults.standard.bool(forKey: "BCWOpenSubject"), debugSubject == nil else { return }
                    debugSubject = model.gradeBook.subjects().max { $0.name.count < $1.name.count }
                }
                #endif
        }
    }
}

/// Libretto voti, con titolo e filtri nella barra.
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
            .pageChrome("Voti") {
                BarMenu(icon: period != nil || subjectFilter != nil ? "filterFill" : "filter", label: "Filtri") {
                    MenuPicker(title: "Periodo", selection: $period,
                               options: [(Int?.none, "Tutto l'anno", nil)] + book.activePeriods.map { (Optional($0.position), $0.name, nil) })
                    MenuPicker(title: "Materia", selection: $subjectFilter,
                               options: [(Int?.none, "Tutte le materie", nil)] + allSubjects.map { (Optional($0.id), $0.name, nil) })
                    if period != nil || subjectFilter != nil {
                        MenuDivider()
                        MenuItem("Rimuovi filtri", icon: "xCircle", role: .destructive) {
                            period = nil
                            subjectFilter = nil
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private var banner: some View {
        if allowsRefresh, let error = model.lastError {
            StatusBanner(message: error, icon: model.isOffline ? "wifiOff" : "alertTriangle")
        }
    }

    private var emptyBook: some View {
        EmptyState("Nessun voto", icon: "graduationCap",
                   description: "I voti appariranno qui non appena verranno registrati.")
    }

    private var sectionPicker: some View {
        SegmentedButtons(selection: $section, options: Section.allCases.map { ($0, $0.title, nil) },
                         compact: false)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageLargeTitle()
                    .padding(.bottom, -8)
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
            .padding(.bottom, 32)
            .animation(Motion.spatial, value: period)
            .animation(Motion.spatial, value: subjectFilter)
            .animation(Motion.spatial, value: section)
        }
        .tracksPageScroll()
        .scrollsToTopOnReselect()
        .themedBackground()
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
            AppMenu(alignment: .leading) {
                MenuItem("Tutte le materie", checked: subjectFilter == nil) { subjectFilter = nil }
                ForEach(allSubjects, id: \.id) { s in
                    MenuItem(s.name, checked: subjectFilter == s.id) { subjectFilter = s.id }
                }
            } label: {
                HStack(spacing: 8) {
                    Icon("library", size: 18)
                    Text(allSubjects.first { $0.id == subjectFilter }?.name ?? "Materia")
                        .lineLimit(1)
                    Icon("chevronDown", size: 18)
                }
                .font(.m3(14, weight: 550))
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .frame(height: 32)
            }
            .buttonStyle(ChipStyle(selected: subjectFilter != nil))
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var recentList: some View {
        let filteredGrades = filteredGrades
        if filteredGrades.isEmpty {
            EmptyState("Nessun voto", icon: "filter", description: "Nessun voto corrisponde ai filtri selezionati.")
        } else {
            CardGrid(minWidth: 340, spacing: 12) {
                ForEach(filteredGrades) { grade in
                    GradeCard(grade: grade, book: book, isExpanded: expanded.contains(grade.id)) {
                        withAnimation(Motion.spatial) {
                            if expanded.contains(grade.id) { expanded.remove(grade.id) } else { expanded.insert(grade.id) }
                        }
                    }
                }
            }
        }
    }

    private var subjectList: some View {
        CardGrid(minWidth: 300, spacing: 12) {
            ForEach(book.subjects(in: period).filter { subjectFilter == nil || $0.subjectId == subjectFilter }) { summary in
                NavigationLink(value: summary) {
                    SubjectRow(summary: summary, target: model.preferences.targetAverage)
                }
                .buttonStyle(.pressable)
            }
        }
    }
}

// MARK: - Media generale

private struct AverageHero: View {
    let book: GradeBook
    @Binding var selectedPeriod: Int?

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                AverageRing(value: book.average(period: selectedPeriod), size: 118, lineWidth: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: selectedPeriod == nil ? "Media generale" : "Media del periodo")
                    Text(selectedPeriod.flatMap { p in book.activePeriods.first { $0.position == p }?.name } ?? "Tutto l'anno")
                        .font(.m3(24, weight: 500, rounded: true))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.opacity)
                    let count = book.grades(in: selectedPeriod).filter(\.countsTowardAverage).count
                    Text("\(count) voti che fanno media")
                        .font(.m3(14))
                        .foregroundStyle(Theme.secondaryInk)
                    let insufficient = book.subjects(in: selectedPeriod).filter { ($0.average ?? 10) < 6 }.count
                    StatusLine(text: insufficient == 0 ? "Nessuna insufficienza"
                               : (insufficient == 1 ? "1 insufficienza" : "\(insufficient) insufficienze"),
                               icon: insufficient == 0 ? "checkSealFill" : "alertTriangleFill",
                               color: insufficient == 0 ? Theme.good : Theme.poor)
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }

            if !book.activePeriods.isEmpty {
                HStack(spacing: 8) {
                    ForEach(book.activePeriods) { period in
                        Button {
                            Haptics.selection()
                            withAnimation(Motion.spatial) {
                                selectedPeriod = selectedPeriod == period.position ? nil : period.position
                            }
                        } label: {
                            PeriodTile(name: period.name, average: book.average(period: period.position),
                                       isSelected: selectedPeriod == period.position)
                        }
                        .buttonStyle(PeriodTileStyle(selected: selectedPeriod == period.position))
                    }
                }
            }
        }
        .card(padding: 18)
    }
}

/// Riga di stato con icona (es. "Nessuna insufficienza").
struct StatusLine: View {
    let text: String
    let icon: String
    var color: Color = Theme.primary

    var body: some View {
        HStack(spacing: 6) {
            Icon(icon, size: 20)
            Text(text)
                .font(.m3(14, weight: 600))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
    }
}

private struct PeriodTile: View {
    let name: String
    let average: Double?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            AverageRing(value: average, size: 30, lineWidth: 4, showsLabel: false)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.m3(12))
                    .foregroundStyle(isSelected ? Theme.onSecondaryContainer : Theme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(GradeFormat.average(average))
                    .font(.numeral(18))
                    .foregroundStyle(isSelected ? Theme.onSecondaryContainer : Theme.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}

private struct PeriodTileStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let radius = configuration.isPressed ? Theme.radii.s : (selected ? Theme.radii.xl : Theme.radii.l)
        configuration.label
            .background(selected ? Theme.secondaryContainer : Theme.surfaceContainerHigh,
                        in: .rect(cornerRadius: radius, style: .continuous))
            .contentShape(.rect(cornerRadius: radius, style: .continuous))
            .animation(Motion.spatialFast, value: configuration.isPressed)
            .animation(Motion.spatial, value: selected)
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Eyebrow(text: "Andamento della media")
                    Spacer()
                    if let first = points.first?.value, let last = points.last?.value {
                        let delta = last - first
                        HStack(spacing: 2) {
                            Icon(delta >= 0 ? "arrowUpRight" : "arrowDownRight", size: 18)
                            Text(GradeFormat.average(abs(delta)))
                                .font(.numeral(15, weight: 700))
                        }
                        .foregroundStyle(delta >= 0 ? Theme.good : Theme.poor)
                    }
                }
                Chart {
                    RuleMark(y: .value("Sufficienza", 6))
                        .foregroundStyle(Theme.poor.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                    ForEach(points.indices, id: \.self) { i in
                        AreaMark(x: .value("Data", points[i].date), yStart: .value("Base", 3),
                                 yEnd: .value("Media", points[i].value))
                            .foregroundStyle(LinearGradient(colors: [Theme.primary.opacity(0.25), Theme.primary.opacity(0)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Data", points[i].date), y: .value("Media", points[i].value))
                            .foregroundStyle(Theme.primary)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                }
                .chartYScale(domain: 3...10)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [4, 6, 8, 10]) { _ in
                        AxisGridLine().foregroundStyle(Theme.outlineVariant)
                        AxisValueLabel().font(.m3(11)).foregroundStyle(Theme.secondaryInk)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.m3(11)).foregroundStyle(Theme.secondaryInk)
                    }
                }
                .frame(height: 150)
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
            Button(action: onTap) {
                HStack(spacing: 14) {
                    GradeBadge(grade: grade, size: 50)
                    VStack(alignment: .leading, spacing: 2) {
                        SubjectTag(name: grade.subjectName, id: grade.subjectId)
                        Text("\(grade.kind) · \(grade.date.shortDay)")
                            .font(.m3(14))
                            .foregroundStyle(Theme.secondaryInk)
                        if let notes = grade.notes, !isExpanded {
                            Text(notes)
                                .font(.m3(13))
                                .foregroundStyle(Theme.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Chevron(collapsed: !isExpanded, rotateUp: true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(HeaderButtonStyle())
            .accessibilityHint(isExpanded ? "Nasconde i dettagli" : "Mostra i dettagli")

            CollapsibleContent(isExpanded: isExpanded, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    if let notes = grade.notes {
                        Text(notes)
                            .font(.m3(14))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surfaceContainerHigh, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
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
                        StatusLine(text: grade.canceled ? "Voto annullato" : "Non fa media", icon: "info", color: Theme.neutral)
                    } else if let impact {
                        HStack {
                            Text("Effetto sulla media di materia")
                                .foregroundStyle(Theme.secondaryInk)
                            Spacer()
                            HStack(spacing: 2) {
                                Icon(impact >= 0 ? "arrowUp" : "arrowDown", size: 18)
                                Text(GradeFormat.average(abs(impact)))
                                    .font(.numeral(15, weight: 700))
                            }
                            .foregroundStyle(impact >= 0 ? Theme.good : Theme.poor)
                        }
                        .font(.m3(14))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radii.li, style: .continuous))
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
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.name)
                    .font(.m3(16, weight: 600))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                FlowLayout(spacing: 4) {
                    ForEach(summary.grades.prefix(6)) { g in
                        Text(g.displayValue)
                            .font(.m3(12, weight: 700))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(Theme.gradeColor(g))
                            .padding(.horizontal, 6)
                            .frame(minWidth: 30, minHeight: 24)
                            .background(Theme.gradeColor(g).opacity(0.15), in: .rect(cornerRadius: Theme.radii.s, style: .continuous))
                    }
                }
            }
            Spacer(minLength: 4)
            Icon("chevronRight", size: 22)
                .foregroundStyle(Theme.secondaryInk)
        }
        .card(padding: 14)
    }
}
