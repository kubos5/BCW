import Charts
import SwiftUI

struct SubjectDetailView: View {
    @Environment(AppModel.self) private var model
    let subjectId: Int
    let book: GradeBook
    var subjects: [Subject] = []

    @State private var period: Int?
    @State private var expanded: Set<Int> = []
    /// iPad largo con la pagina larga almeno 792 punti: media, periodi e obiettivo a sinistra,
    /// grafico e voti a destra.
    @State private var isSplit = false

    private var grades: [Grade] {
        book.grades(in: period).filter { $0.subjectId == subjectId }.sorted { $0.date > $1.date }
    }

    private var name: String {
        book.grades.first { $0.subjectId == subjectId }?.subjectName ?? "Materia"
    }

    private var teachers: [String] {
        let fromSubjects = subjects.first { $0.id == subjectId }?.teachers ?? []
        if !fromSubjects.isEmpty { return fromSubjects }
        return Array(Set(grades.compactMap(\.teacherName))).sorted()
    }

    var body: some View {
        content
            .pageChrome(name, style: .inline)
    }

    @ViewBuilder
    private var periodPicker: some View {
        if book.activePeriods.count > 1 {
            ConnectedButtonGroup(selection: $period, values: [nil] + book.activePeriods.map { Optional($0.position) },
                                 height: 48) { period, _ in
                Text(period.flatMap { p in book.activePeriods.first { $0.position == p }?.name } ?? "Anno")
                    .font(.m3(14, weight: 600))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var gradeList: some View {
        ListGroup {
            ForEach(grades) { grade in
                GradeCard(grade: grade, book: book, isExpanded: expanded.contains(grade.id)) {
                    withAnimation(Motion.spatial) {
                        if expanded.contains(grade.id) { expanded.remove(grade.id) } else { expanded.insert(grade.id) }
                    }
                }
            }
        }
    }

    private var content: some View {
        ZStack {
            if isSplit {
                SplitPage(sideWidth: 360, mainMaxWidth: 760) {
                    VStack(alignment: .leading, spacing: 20) {
                        header(ringSize: 140)
                        periodPicker
                        GoalCalculator(grades: grades, weighted: book.weighted)
                    }
                } main: {
                    VStack(alignment: .leading, spacing: 20) {
                        chart(height: 240)
                        gradesSection
                    }
                }
                .animation(Motion.spatial, value: period)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(ringSize: 156)
                        periodPicker
                        chart(height: 170)
                        GoalCalculator(grades: grades, weighted: book.weighted)
                        gradesSection
                    }
                    .pagePadding()
                    .padding(.bottom, 32)
                    .animation(Motion.spatial, value: period)
                }
                .tracksPageScroll()
            }
        }
        // Sull'iPad largo, da 792 punti di pagina, in due colonne (come la versione web).
        .widthAtLeast(SplitMetrics.threshold, isOn: $isSplit)
        .themedBackground()
    }

    @ViewBuilder
    private var gradesSection: some View {
        SectionHeader("Voti", subtitle: grades.count == 1 ? "1 valutazione" : "\(grades.count) valutazioni")
            .padding(.bottom, -8)
        gradeList
    }

    /// La media della materia in primo piano, al centro, con docenti e voto migliore e peggiore.
    private func header(ringSize: CGFloat) -> some View {
        VStack(spacing: 14) {
            AverageRing(value: GradeBook.average(of: grades, weighted: book.weighted), size: ringSize, lineWidth: 12)
            VStack(spacing: 4) {
                Text(name)
                    .font(.m3(24, weight: 500, rounded: true))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                if !teachers.isEmpty {
                    Text(teachers.joined(separator: ", "))
                        .font(.m3(14))
                        .foregroundStyle(Theme.secondaryInk)
                        .multilineTextAlignment(.center)
                }
            }
            let values = grades.filter(\.countsTowardAverage).compactMap(\.value)
            if let best = values.max(), let worst = values.min() {
                HStack(spacing: 8) {
                    StatusChip(text: "Migliore \(GradeFormat.short(best))", icon: "arrowUp",
                               container: Theme.goodContainer, foreground: Theme.onGoodContainer)
                    StatusChip(text: "Peggiore \(GradeFormat.short(worst))", icon: "arrowDown",
                               container: Theme.poorContainer, foreground: Theme.onPoorContainer)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func chart(height: CGFloat) -> some View {
        let sorted = grades.filter(\.countsTowardAverage).sorted { $0.date < $1.date }
        let running = book.runningAverage(for: subjectId, period: period)
        if sorted.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Voti e media")
                    .font(.m3(18, weight: 550))
                    .foregroundStyle(Theme.ink)
                Chart {
                    RectangleMark(yStart: .value("Base", 2), yEnd: .value("Sufficienza", 6))
                        .foregroundStyle(Theme.poorContainer.opacity(0.15))
                    ForEach(running.indices, id: \.self) { i in
                        LineMark(x: .value("Data", running[i].date), y: .value("Media", running[i].value))
                            .foregroundStyle(Theme.subjectColor(subjectId))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(sorted) { grade in
                        PointMark(x: .value("Data", grade.date.startOfDay), y: .value("Voto", grade.value ?? 0))
                            .symbol {
                                Circle()
                                    .fill(Theme.gradeColor(grade))
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Theme.surfaceContainerLow, lineWidth: 2.5))
                            }
                    }
                }
                .chartYScale(domain: 2...10)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [2, 4, 6, 8, 10]) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(Theme.outlineVariant)
                        AxisValueLabel().font(.m3(11, weight: 500)).foregroundStyle(Theme.onSurfaceVariant)
                    }
                }
                .frame(height: height)
            }
            .card(padding: 18, color: Theme.surfaceContainerLow, radius: Theme.radii.xl)
        }
    }
}

/// "Quanto devo prendere?": voto necessario per raggiungere una media obiettivo.
struct GoalCalculator: View {
    @Environment(AppModel.self) private var model
    let grades: [Grade]
    let weighted: Bool
    @State private var upcoming = 1

    var body: some View {
        @Bindable var preferences = model.preferences
        let needed = GradeBook.neededGrade(target: preferences.targetAverage, current: grades,
                                           count: upcoming, weighted: weighted)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Shaped(shape: .cookie9Sided, fill: Theme.tertiaryContainer, size: 40) {
                    Icon("target", size: 22)
                        .foregroundStyle(Theme.onTertiaryContainer)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Obiettivo")
                        .font(.m3(18, weight: 550))
                    Text("Quanto ti serve per arrivarci")
                        .font(.m3(13))
                        .foregroundStyle(Theme.secondaryInk)
                }
            }

            HStack {
                Text("Media desiderata")
                Spacer()
                M3Stepper(value: $preferences.targetAverage, range: 4...10, step: 0.25) { GradeFormat.short($0) }
            }
            .frame(minHeight: 40)

            HStack {
                Text("Prossime prove")
                Spacer()
                M3Stepper(value: $upcoming, range: 1...5, step: 1) { "\($0)" }
            }
            .frame(minHeight: 40)

            M3Divider()

            if let needed {
                if needed <= 1 {
                    StatusLine(text: "Hai già raggiunto l'obiettivo, qualunque voto prenderai.", icon: "checkSealFill", color: Theme.good)
                } else if needed > 10 {
                    StatusLine(text: "Obiettivo non raggiungibile con \(upcoming == 1 ? "una prova" : "\(upcoming) prove").",
                               icon: "octagonX", color: Theme.poor)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text(upcoming == 1 ? "Ti serve almeno" : "Ti serve in media almeno")
                            .foregroundStyle(Theme.secondaryInk)
                        Spacer()
                        Text(GradeFormat.average(needed))
                            .font(.numeral(32))
                            .foregroundStyle(Theme.gradeColor(value: needed))
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .font(.m3(16))
        .foregroundStyle(Theme.ink)
        .card(padding: 18, color: Theme.surfaceContainerLow, radius: Theme.radii.xl)
        .animation(Motion.spatial, value: preferences.targetAverage)
        .animation(Motion.spatial, value: upcoming)
    }
}
