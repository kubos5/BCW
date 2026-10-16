import Charts
import SwiftUI

struct SubjectDetailView: View {
    @Environment(AppModel.self) private var model
    let subjectId: Int
    let book: GradeBook
    var subjects: [Subject] = []

    @State private var period: Int?
    @State private var expanded: Set<Int> = []

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
            SegmentedButtons(selection: $period,
                             options: [(Int?.none, "Anno", nil)] + book.activePeriods.map { (Optional($0.position), $0.name, nil) })
        }
    }

    private var gradeList: some View {
        CardGrid(minWidth: 340, spacing: 12) {
            ForEach(grades) { grade in
                GradeCard(grade: grade, book: book, isExpanded: expanded.contains(grade.id)) {
                    withAnimation(Motion.spatial) {
                        if expanded.contains(grade.id) { expanded.remove(grade.id) } else { expanded.insert(grade.id) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        SplitColumns(sideWidth: 350) {
            header
            periodPicker
            chart
            GoalCalculator(grades: grades, weighted: book.weighted)
        } main: {
            SectionHeader("Voti", subtitle: "\(grades.count) valutazioni")
            gradeList
        }
        .animation(Motion.spatial, value: period)
        #else
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                periodPicker
                chart
                GoalCalculator(grades: grades, weighted: book.weighted)

                SectionHeader("Voti", subtitle: "\(grades.count) valutazioni")
                gradeList
            }
            .pagePadding()
            .padding(.bottom, 32)
            .animation(Motion.spatial, value: period)
        }
        .tracksPageScroll()
        .themedBackground()
        #endif
    }

    private var header: some View {
        HStack(spacing: 20) {
            AverageRing(value: GradeBook.average(of: grades, weighted: book.weighted), size: 96, lineWidth: 8)
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Media di materia", color: Theme.subjectColor(subjectId))
                Text(name)
                    .font(.m3(24, weight: 500, rounded: true))
                    .foregroundStyle(Theme.ink)
                if !teachers.isEmpty {
                    Text(teachers.joined(separator: ", "))
                        .font(.m3(14))
                        .foregroundStyle(Theme.secondaryInk)
                }
                let values = grades.filter(\.countsTowardAverage).compactMap(\.value)
                if let best = values.max(), let worst = values.min() {
                    HStack(spacing: 12) {
                        HStack(spacing: 2) {
                            Icon("arrowUp", size: 18)
                            Text(GradeFormat.short(best))
                        }
                        .foregroundStyle(Theme.good)
                        HStack(spacing: 2) {
                            Icon("arrowDown", size: 18)
                            Text(GradeFormat.short(worst))
                        }
                        .foregroundStyle(Theme.poor)
                    }
                    .font(.numeral(15, weight: 700))
                    .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 18)
    }

    @ViewBuilder
    private var chart: some View {
        let sorted = grades.filter(\.countsTowardAverage).sorted { $0.date < $1.date }
        let running = book.runningAverage(for: subjectId, period: period)
        if sorted.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Voti e media")
                Chart {
                    RuleMark(y: .value("Sufficienza", 6))
                        .foregroundStyle(Theme.poor.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                    ForEach(running.indices, id: \.self) { i in
                        LineMark(x: .value("Data", running[i].date), y: .value("Media", running[i].value))
                            .foregroundStyle(Theme.subjectColor(subjectId))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    ForEach(sorted) { grade in
                        PointMark(x: .value("Data", grade.date.startOfDay), y: .value("Voto", grade.value ?? 0))
                            .foregroundStyle(Theme.gradeColor(grade))
                            .symbolSize(78)
                    }
                }
                .chartYScale(domain: 2...10)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [2, 4, 6, 8, 10]) { _ in
                        AxisGridLine().foregroundStyle(Theme.outlineVariant)
                        AxisValueLabel().font(.m3(11)).foregroundStyle(Theme.secondaryInk)
                    }
                }
                .frame(height: 170)
            }
            .card()
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
            HStack {
                Eyebrow(text: "Obiettivo")
                Spacer()
                Icon("target")
                    .foregroundStyle(Theme.primary)
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
        .card()
        .animation(Motion.spatial, value: preferences.targetAverage)
        .animation(Motion.spatial, value: upcoming)
    }
}
