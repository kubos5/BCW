import SwiftUI

/// "E se prendessi…": come cambierebbe la media con uno o più voti ipotetici. Nella pagina di una
/// materia i voti sono di quella materia, nei Voti si sceglie la materia di ognuno. Nulla viene
/// salvato: i voti ipotetici spariscono uscendo dalla pagina.
struct GradeSimulator: View {
    let book: GradeBook
    /// Periodo scelto nella pagina (`nil` = tutto l'anno).
    let period: Int?
    /// Materia della pagina; `nil` nei Voti, dove si sceglie per ogni voto.
    var subjectId: Int?
    /// Materia del filtro dei Voti, proposta per primo.
    var suggestedSubject: Int?
    /// Comprimibile (nei Voti, dove starebbe sopra l'elenco); aperto nella pagina di una materia.
    var collapsible = false

    @State private var isExpanded = false
    @State private var grades: [HypotheticalGrade] = []
    @State private var value = 7.0
    @State private var weight = 1.0
    @State private var chosenSubject: Int?

    private var subjects: [(id: Int, name: String)] {
        let pairs = Dictionary(grouping: book.grades, by: \.subjectId).compactMap { id, list in
            list.first.map { (id: id, name: $0.subjectName) }
        }
        return pairs.sorted { $0.name < $1.name }
    }

    private var targetSubject: Int? {
        subjectId ?? chosenSubject ?? suggestedSubject ?? subjects.first?.id
    }

    private func name(of subject: Int) -> String {
        book.grades.first { $0.subjectId == subject }?.subjectName ?? "Materia"
    }

    /// In che periodo cade un voto ipotetico: quello scelto o, con tutto l'anno, l'ultimo.
    private var targetPeriod: (position: Int, name: String) {
        if let period, let chosen = book.activePeriods.first(where: { $0.position == period }) {
            return (chosen.position, chosen.name)
        }
        if let last = book.activePeriods.last { return (last.position, last.name) }
        return (period ?? 1, "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if collapsible {
                Button {
                    withAnimation(Motion.spatial) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        heading
                        Spacer(minLength: 8)
                        Chevron(collapsed: !isExpanded, rotateUp: true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(HeaderButtonStyle())
                .accessibilityHint(isExpanded ? "Nasconde la simulazione" : "Apre la simulazione")
            } else {
                heading
            }
            CollapsibleContent(isExpanded: !collapsible || isExpanded, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    form
                    if !grades.isEmpty {
                        chips
                            .transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
                        M3Divider()
                        results
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .font(.m3(16))
        .foregroundStyle(Theme.ink)
        .card(padding: 18, color: Theme.surfaceContainerLow, radius: Theme.radii.xl)
        .animation(Motion.spatial, value: grades)
    }

    private var heading: some View {
        HStack(spacing: 12) {
            Shaped(shape: .clover4Leaf, fill: Theme.secondaryContainer, size: 40) {
                Icon("wand", size: 22)
                    .foregroundStyle(Theme.onSecondaryContainer)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("E se prendessi…")
                    .font(.m3(18, weight: 550))
                    .foregroundStyle(Theme.ink)
                Text("Come cambierebbe la media")
                    .font(.m3(13))
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        if subjectId == nil, !subjects.isEmpty {
            HStack {
                Text("Materia")
                Spacer(minLength: 12)
                SelectButton(selection: Binding { targetSubject ?? subjects[0].id } set: { chosenSubject = $0 },
                             options: subjects.map { ($0.id, $0.name, nil) }, label: "Materia",
                             fill: Theme.surfaceContainerHighest, minHeight: 40)
            }
            .frame(minHeight: 40)
        }
        HStack {
            Text("Voto")
            Spacer()
            M3Stepper(value: $value, range: 1...10, step: 0.25) { GradeFormat.short($0) }
        }
        .frame(minHeight: 40)
        if book.weighted {
            HStack {
                Text("Peso")
                Spacer()
                M3Stepper(value: $weight, range: 0.25...3, step: 0.25) { GradeFormat.short($0 * 100) + "%" }
            }
            .frame(minHeight: 40)
        }
        Button(action: add) {
            Label { Text("Aggiungi questo voto") } icon: { Icon("plus") }
        }
        .buttonStyle(.m3(.tonal, size: .s, wide: true))
        .disabled(targetSubject == nil)
    }

    /// I voti ipotetici: toccandone uno si toglie.
    private var chips: some View {
        FlowLayout(spacing: 6) {
            ForEach(grades) { grade in
                Button {
                    Haptics.selection()
                    grades.removeAll { $0.id == grade.id }
                } label: {
                    HStack(spacing: 6) {
                        Text(GradeFormat.short(grade.value))
                            .font(.numeral(15, weight: 700))
                        if subjectId == nil {
                            Text(grade.subjectName)
                                .font(.m3(12, weight: 550))
                                .lineLimit(1)
                        }
                        if book.weighted, grade.weight != 1 {
                            Text(GradeFormat.short(grade.weight * 100) + "%")
                                .font(.m3(12, weight: 550))
                        }
                        Icon("x", size: 16)
                    }
                    .foregroundStyle(Theme.tone(value: grade.value).onContainer)
                    .padding(.leading, 10)
                    .padding(.trailing, 6)
                    .frame(height: 32)
                    .background(Theme.tone(value: grade.value).container, in: .capsule)
                    .contentShape(.capsule)
                }
                .buttonStyle(.pressable(radius: 16, pressed: 8))
                .accessibilityLabel("Togli il voto \(GradeFormat.short(grade.value))")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
    }

    /// Prima e dopo: la media della materia (o delle materie toccate) e quella generale.
    @ViewBuilder
    private var results: some View {
        let simulated = book.adding(grades, position: targetPeriod.position, periodName: targetPeriod.name)
        VStack(spacing: 10) {
            ForEach(Array(Set(grades.map(\.subjectId))).sorted(by: { name(of: $0) < name(of: $1) }), id: \.self) { subject in
                row(title: subjectId == nil ? name(of: subject) : "Media della materia",
                    before: GradeBook.average(of: book.grades(in: period).filter { $0.subjectId == subject }, weighted: book.weighted),
                    after: GradeBook.average(of: simulated.grades(in: period).filter { $0.subjectId == subject }, weighted: book.weighted),
                    prominent: subjectId != nil)
            }
            row(title: period == nil ? "Media generale" : "Media del periodo",
                before: book.average(period: period), after: simulated.average(period: period),
                prominent: subjectId == nil)
        }
        HStack {
            Spacer()
            Button("Azzera") { grades = [] }
                .buttonStyle(.m3(.text, size: .xs))
        }
    }

    private func row(title: String, before: Double?, after: Double?, prominent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.m3(14, weight: 550))
                .foregroundStyle(Theme.secondaryInk)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(GradeFormat.average(before))
                .font(.numeral(15, weight: 500))
                .foregroundStyle(Theme.secondaryInk)
            Icon("chevronRight", size: 16)
                .foregroundStyle(Theme.secondaryInk)
            Text(GradeFormat.average(after))
                .font(.numeral(prominent ? 32 : 20, weight: 650))
                .foregroundStyle(Theme.gradeColor(value: after))
                .contentTransition(.numericText())
            if let delta = difference(before, after) {
                Text(delta.text)
                    .font(.m3(12, weight: 700).monospacedDigit())
                    .foregroundStyle(delta.up ? Theme.onGoodContainer : Theme.onPoorContainer)
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(delta.up ? Theme.goodContainer : Theme.poorContainer, in: .capsule)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func difference(_ before: Double?, _ after: Double?) -> (text: String, up: Bool)? {
        guard let after else { return nil }
        guard let before else { return nil }
        let delta = after - before
        guard abs(delta) >= 0.005 else { return nil }
        return ((delta > 0 ? "+" : "−") + GradeFormat.average(abs(delta)), delta > 0)
    }

    private func add() {
        guard let subject = targetSubject else { return }
        Haptics.selection()
        grades.append(HypotheticalGrade(subjectId: subject, subjectName: name(of: subject), value: value,
                                        weight: book.weighted ? weight : 1))
    }
}
