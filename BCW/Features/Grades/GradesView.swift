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

    private var sectionTabs: some View {
        PrimaryTabs(selection: $section, tabs: Section.allCases.map { ($0, $0.title, nil) })
            .padding(.horizontal, -16)
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                banner

                if book.grades.isEmpty {
                    emptyBook
                } else {
                    AverageHero(book: book, selectedPeriod: $period)
                    TrendCard(book: book, period: period, subjectId: subjectFilter)

                    VStack(alignment: .leading, spacing: 16) {
                        sectionTabs
                        filters
                        // Asse condiviso orizzontale tra le schede: gli ultimi voti stanno a sinistra,
                        // le materie a destra.
                        Group {
                            switch section {
                            case .recent: recentList
                            case .subjects: subjectList
                            }
                        }
                        .id(section)
                        .transition(.sharedAxisX(forward: section == .subjects))
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

    /// Filtro per materia (il periodo si sceglie con il gruppo di pulsanti della media).
    @ViewBuilder
    private var filters: some View {
        let allSubjects = allSubjects
        ChipRow {
            AppMenu(alignment: .leading) {
                MenuItem("Tutte le materie", checked: subjectFilter == nil) { subjectFilter = nil }
                ForEach(allSubjects, id: \.id) { s in
                    MenuItem(s.name, checked: subjectFilter == s.id) { subjectFilter = s.id }
                }
            } label: {
                HStack(spacing: 8) {
                    Icon(subjectFilter == nil ? "library" : "check", size: 18)
                    Text(allSubjects.first { $0.id == subjectFilter }?.name ?? "Tutte le materie")
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
            if subjectFilter != nil {
                FilterChip(title: "Rimuovi filtro", icon: "x", isSelected: false) { subjectFilter = nil }
            }
        }
    }

    /// Ultimi voti divisi per mese, ognuno in una lista segmentata.
    @ViewBuilder
    private var recentList: some View {
        let filteredGrades = filteredGrades
        if filteredGrades.isEmpty {
            EmptyState("Nessun voto", icon: "filter", description: "Nessun voto corrisponde ai filtri selezionati.")
        } else {
            let months = Dictionary(grouping: filteredGrades) { $0.date.startOfMonth }
                .sorted { $0.key > $1.key }
            VStack(alignment: .leading, spacing: 20) {
                ForEach(months, id: \.key) { month, grades in
                    ListGroup(month.monthYear) {
                        ForEach(grades) { grade in
                            GradeCard(grade: grade, book: book, isExpanded: expanded.contains(grade.id)) {
                                withAnimation(Motion.spatial) {
                                    if expanded.contains(grade.id) { expanded.remove(grade.id) } else { expanded.insert(grade.id) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var subjectList: some View {
        ListGroup {
            ForEach(book.subjects(in: period).filter { subjectFilter == nil || $0.subjectId == subjectFilter }) { summary in
                NavigationLink(value: summary) {
                    SubjectRow(summary: summary, target: model.preferences.targetAverage)
                }
                .buttonStyle(.listRow)
            }
        }
    }
}

// MARK: - Media generale

/// La media in primo piano: un grande indicatore circolare ondulato al centro, sotto il periodo
/// e lo stato delle insufficienze; poi i periodi in un gruppo di pulsanti collegati, ognuno con
/// la sua media (quello scelto cambia la media mostrata e i voti sotto).
private struct AverageHero: View {
    let book: GradeBook
    @Binding var selectedPeriod: Int?

    var body: some View {
        let insufficient = book.subjects(in: selectedPeriod).filter { ($0.average ?? 10) < 6 }.count
        let count = book.grades(in: selectedPeriod).filter(\.countsTowardAverage).count
        VStack(spacing: 20) {
            VStack(spacing: 14) {
                AverageRing(value: book.average(period: selectedPeriod), size: 188, lineWidth: 14)
                VStack(spacing: 4) {
                    Text(selectedPeriod.flatMap { p in book.activePeriods.first { $0.position == p }?.name }
                         .map { "Media del \($0.lowercased())" } ?? "Media generale")
                        .font(.m3(22, weight: 500, rounded: true))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.opacity)
                    Text(count == 1 ? "1 voto che fa media" : "\(count) voti che fanno media")
                        .font(.m3(14))
                        .foregroundStyle(Theme.secondaryInk)
                }
                StatusChip(text: insufficient == 0 ? "Nessuna insufficienza"
                           : (insufficient == 1 ? "1 insufficienza" : "\(insufficient) insufficienze"),
                           icon: insufficient == 0 ? "checkSealFill" : "alertTriangleFill",
                           container: insufficient == 0 ? Theme.goodContainer : Theme.poorContainer,
                           foreground: insufficient == 0 ? Theme.onGoodContainer : Theme.onPoorContainer)
            }
            .frame(maxWidth: .infinity)

            if !book.activePeriods.isEmpty {
                ConnectedButtonGroup(selection: $selectedPeriod,
                                     values: [nil] + book.activePeriods.map { Optional($0.position) },
                                     height: 64) { period, selected in
                    VStack(spacing: 1) {
                        Text(period.flatMap { p in book.activePeriods.first { $0.position == p }?.name } ?? "Anno")
                            .font(.m3(12, weight: 600))
                            .opacity(selected ? 1 : 0.8)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(GradeFormat.average(book.average(period: period)))
                            .font(.numeral(19, weight: 700))
                    }
                    .padding(.horizontal, 6)
                }
            }
        }
        .padding(.top, 4)
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

// MARK: - Andamento

/// Andamento della media in stile Material 3 Expressive: linea spessa e arrotondata sul colore
/// primario con l'area tonale sotto, la fascia dell'insufficienza nel contenitore rosso e l'ultimo
/// valore segnato da un punto grande. Toccando o trascinando sul grafico si legge la media di quel
/// giorno (in grande sopra il grafico).
private struct TrendCard: View {
    let book: GradeBook
    let period: Int?
    let subjectId: Int?
    @State private var selected: Date?

    var body: some View {
        let points = book.runningAverage(for: subjectId, period: period)
        if points.count >= 2, let last = points.last, let first = points.first {
            let shown = selected.flatMap { date in
                points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
            } ?? last
            let delta = last.value - first.value
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Andamento della media")
                            .font(.m3(14, weight: 600))
                            .foregroundStyle(Theme.onSurfaceVariant)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(GradeFormat.average(shown.value))
                                .font(.numeral(34, weight: 650))
                                .foregroundStyle(Theme.ink)
                                .contentTransition(.numericText(value: shown.value))
                            Text(selected == nil ? "ultimo voto" : shown.date.longDay)
                                .font(.m3(13))
                                .foregroundStyle(Theme.onSurfaceVariant)
                                .contentTransition(.opacity)
                        }
                    }
                    Spacer(minLength: 8)
                    StatusChip(text: (delta >= 0 ? "+" : "−") + GradeFormat.average(abs(delta)),
                               icon: delta >= 0 ? "trendingUp" : "trendingDown",
                               container: delta >= 0 ? Theme.goodContainer : Theme.poorContainer,
                               foreground: delta >= 0 ? Theme.onGoodContainer : Theme.onPoorContainer)
                }
                Chart {
                    // Fascia dell'insufficienza.
                    RectangleMark(yStart: .value("Base", 3), yEnd: .value("Sufficienza", 6))
                        .foregroundStyle(Theme.poorContainer.opacity(0.15))
                    ForEach(points.indices, id: \.self) { i in
                        AreaMark(x: .value("Data", points[i].date), yStart: .value("Base", 3),
                                 yEnd: .value("Media", points[i].value))
                            .foregroundStyle(Theme.primary.opacity(0.1))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Data", points[i].date), y: .value("Media", points[i].value))
                            .foregroundStyle(Theme.primary)
                            .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                    if selected != nil {
                        RuleMark(x: .value("Data", shown.date))
                            .foregroundStyle(Theme.outline)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))
                    }
                    PointMark(x: .value("Data", shown.date), y: .value("Media", shown.value))
                        .symbol {
                            Circle()
                                .fill(Theme.primary)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(Theme.surfaceContainerLow, lineWidth: 3))
                        }
                }
                .chartYScale(domain: 3...10)
                .chartXSelection(value: $selected)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [4, 6, 8, 10]) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(Theme.outlineVariant)
                        AxisValueLabel().font(.m3(11, weight: 500)).foregroundStyle(Theme.onSurfaceVariant)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.m3(11, weight: 500))
                            .foregroundStyle(Theme.onSurfaceVariant)
                    }
                }
                .frame(height: 160)
                .sensoryFeedback(.selection, trigger: shown.date)
                .animation(Motion.spatialFast, value: shown.date)
            }
            .card(padding: 20, color: Theme.surfaceContainerLow, radius: Theme.radii.xl)
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
                            .background(Theme.surfaceContainerHighest, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}
