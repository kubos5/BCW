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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if book.activePeriods.count > 1 {
                    Picker("Periodo", selection: $period) {
                        Text("Anno").tag(Int?.none)
                        ForEach(book.activePeriods) { Text($0.name).tag(Optional($0.position)) }
                    }
                    .pickerStyle(.segmented)
                }

                chart
                GoalCalculator(grades: grades, weighted: book.weighted)

                SectionHeader("Voti", subtitle: "\(grades.count) valutazioni")
                LazyVStack(spacing: 10) {
                    ForEach(grades) { grade in
                        GradeCard(grade: grade, book: book, isExpanded: expanded.contains(grade.id)) {
                            withAnimation(.snappy) {
                                if expanded.contains(grade.id) { expanded.remove(grade.id) } else { expanded.insert(grade.id) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .animation(.snappy, value: period)
        }
        .themedBackground()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 18) {
            AverageRing(value: GradeBook.average(of: grades, weighted: book.weighted), size: 96, lineWidth: 9)
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: "Media di materia", color: Theme.subjectColor(subjectId))
                Text(name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if !teachers.isEmpty {
                    Text(teachers.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                }
                let values = grades.filter(\.countsTowardAverage).compactMap(\.value)
                if let best = values.max(), let worst = values.min() {
                    HStack(spacing: 12) {
                        Label(GradeFormat.short(best), systemImage: "arrow.up")
                            .foregroundStyle(Theme.good)
                        Label(GradeFormat.short(worst), systemImage: "arrow.down")
                            .foregroundStyle(Theme.poor)
                    }
                    .font(.footnote.weight(.semibold))
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
                        .foregroundStyle(Theme.secondaryInk.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    ForEach(running.indices, id: \.self) { i in
                        LineMark(x: .value("Data", running[i].date), y: .value("Media", running[i].value))
                            .foregroundStyle(Theme.subjectColor(subjectId))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    ForEach(sorted) { grade in
                        PointMark(x: .value("Data", grade.date.startOfDay), y: .value("Voto", grade.value ?? 0))
                            .foregroundStyle(Theme.gradeColor(grade))
                            .symbolSize(60)
                    }
                }
                .chartYScale(domain: 2...10)
                .chartYAxis {
                    AxisMarks(values: [2, 4, 6, 8, 10]) { _ in
                        AxisGridLine().foregroundStyle(Theme.separator)
                        AxisValueLabel().font(.caption2)
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
                Image(systemName: "target")
                    .foregroundStyle(Theme.accent)
            }

            Stepper(value: $preferences.targetAverage, in: 4...10, step: 0.25) {
                HStack {
                    Text("Media desiderata")
                    Spacer()
                    Text(GradeFormat.short(preferences.targetAverage))
                        .font(.numeral(20, weight: .bold))
                        .contentTransition(.numericText())
                }
            }

            Stepper(value: $upcoming, in: 1...5) {
                HStack {
                    Text("Prossime prove")
                    Spacer()
                    Text("\(upcoming)")
                        .font(.numeral(20, weight: .bold))
                        .contentTransition(.numericText())
                }
            }

            Divider().overlay(Theme.separator)

            Group {
                if let needed {
                    if needed <= 1 {
                        Label("Hai già raggiunto l'obiettivo, qualunque voto prenderai.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.good)
                    } else if needed > 10 {
                        Label("Obiettivo non raggiungibile con \(upcoming == 1 ? "una prova" : "\(upcoming) prove").",
                              systemImage: "xmark.octagon.fill")
                            .foregroundStyle(Theme.poor)
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text(upcoming == 1 ? "Ti serve almeno" : "Ti serve in media almeno")
                                .foregroundStyle(Theme.secondaryInk)
                            Spacer()
                            Text(GradeFormat.average(needed))
                                .font(.numeral(28, weight: .bold))
                                .foregroundStyle(Theme.gradeColor(value: needed))
                                .contentTransition(.numericText())
                        }
                    }
                }
            }
            .font(.subheadline.weight(.medium))
        }
        .font(.subheadline)
        .card()
        .animation(.snappy, value: preferences.targetAverage)
        .animation(.snappy, value: upcoming)
    }
}
