import SwiftUI

/// Riepilogo della settimana del giorno scelto (iPad largo, colonna laterale dell'Orario, come la
/// versione web sugli schermi larghi): una riga per giorno, da lunedì a venerdì più sabato e
/// domenica se hanno eventi, con il numero di lezioni, l'orario e i colori dei blocchi. Toccando una
/// riga si va a quel giorno.
struct TimetableWeekOverview: View {
    @Environment(AppModel.self) private var model
    let selectedDay: Date
    let onSelect: (Date) -> Void

    /// Un giorno del riepilogo, calcolato una volta per aggiornamento.
    private struct DaySummary: Identifiable {
        let day: Date
        let lessons: Int
        let span: (start: Int, end: Int)?
        let tests: Int
        let isDraft: Bool
        /// Blocchi della giornata (al massimo 8): colore e numero di ore.
        let bars: [(color: Color, hours: Int)]

        var id: Date { day }
    }

    private func summaries() -> [DaySummary] {
        let store = model.timetable
        let monday = selectedDay.startOfWeek
        return (0..<7).compactMap { offset in
            let day = monday.adding(days: offset)
            let content = TimetableDayContent(day: day, model: model)
            guard offset < 5 || !content.entries.isEmpty else { return nil }
            let blocks = content.layout.clusters.flatMap { $0.blocks.map(\.block) }
            return DaySummary(
                day: day,
                lessons: content.entries.filter { !$0.isBreak }.count,
                span: content.layout.span,
                tests: content.badges.values.filter(\.isTest).count + content.unmatchedTests.count,
                isDraft: content.isDraft,
                bars: blocks.prefix(8).map { (Theme.timetableColor($0.entries[0], store: store), $0.entries.count) }
            )
        }
    }

    var body: some View {
        let days = summaries()
        let showsTests = model.preferences.timetableShowsTests
        ListGroup("Settimana") {
            ForEach(days) { summary in
                row(summary, selected: summary.day.isSameDay(as: selectedDay), showsTests: showsTests)
            }
        }
    }

    private func row(_ summary: DaySummary, selected: Bool, showsTests: Bool) -> some View {
        let subtitle = summary.span.map { span in
            "\(summary.lessons == 1 ? "1 lezione" : "\(summary.lessons) lezioni") · "
                + "\(TimeOfDay.string(span.start))–\(TimeOfDay.string(span.end))"
        } ?? "Nessuna lezione"
        return Button {
            guard !selected else { return }
            Haptics.selection()
            onSelect(summary.day)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(summary.day.it("EEEEd").capitalizedFirst)
                            .font(.m3(15, weight: 600))
                            .lineLimit(1)
                        if showsTests && summary.tests > 0 {
                            Icon("test", size: 16)
                                .foregroundStyle(selected ? Theme.onSecondaryContainer : Theme.primary)
                        }
                    }
                    Text(subtitle)
                        .font(.m3(12))
                        .foregroundStyle(selected ? Theme.onSecondaryContainer.opacity(0.8) : Theme.onSurfaceVariant)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    ForEach(summary.bars.indices, id: \.self) { index in
                        let bar = summary.bars[index]
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(bar.color)
                            .frame(width: 6 * CGFloat(bar.hours), height: 14)
                    }
                }
                .opacity(summary.isDraft ? 0.5 : 1)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 60)
            .contentShape(.rect)
        }
        .buttonStyle(ListRowButtonStyle(selected: selected))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.day.longDay), \(subtitle)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Si ricalcola solo se cambia il giorno scelto (`.equatable()`): i dati letti dal modello lo
/// aggiornano comunque, e la chiusura cambia a ogni aggiornamento dell'Orario ma fa sempre la stessa cosa.
extension TimetableWeekOverview: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.selectedDay == rhs.selectedDay }
}
