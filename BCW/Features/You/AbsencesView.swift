import SwiftUI

struct AbsencesView: View {
    @Environment(AppModel.self) private var model
    @State private var kind: AbsenceEvent.Kind?
    @State private var onlyPending = false

    private var filtered: [AbsenceEvent] {
        model.absences.filter { a in
            (kind == nil || a.kind == kind || (kind == .late && a.kind == .shortLate))
                && (!onlyPending || !a.isJustified)
        }
    }

    private var byMonth: [(Date, [AbsenceEvent])] {
        Dictionary(grouping: filtered, by: { $0.date.startOfMonth })
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                counters

                if !model.unjustifiedAbsences.isEmpty {
                    Label(model.unjustifiedAbsences.count == 1
                          ? "Hai un evento da giustificare"
                          : "Hai \(model.unjustifiedAbsences.count) eventi da giustificare",
                          systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.poor)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.poor.opacity(0.1), in: .rect(cornerRadius: 16, style: .continuous))
                }

                ChipRow {
                    FilterChip(title: "Da giustificare", symbol: "exclamationmark.circle", isSelected: onlyPending) {
                        onlyPending.toggle()
                    }
                    FilterChip(title: "Tutti", isSelected: kind == nil) { kind = nil }
                    ForEach([AbsenceEvent.Kind.absence, .late, .earlyExit]) { k in
                        FilterChip(title: k.pluralTitle, symbol: k.symbol, isSelected: kind == k) {
                            kind = kind == k ? nil : k
                        }
                    }
                }

                if filtered.isEmpty {
                    ContentUnavailableView("Nessun evento", systemImage: "checkmark.circle",
                                           description: Text("Nessuna assenza, ritardo o uscita registrati."))
                        .padding(.top, 30)
                } else {
                    CardGrid(minWidth: 440, spacing: 18) {
                        ForEach(byMonth, id: \.0) { month, events in
                            VStack(alignment: .leading, spacing: 10) {
                                Eyebrow(text: month.monthYear)
                                    .padding(.leading, 6)
                                VStack(spacing: 12) {
                                    ForEach(events) { event in
                                        // Data, icona e stato restano centrati sull'intera riga,
                                        // anche quando dettaglio e motivo occupano più righe.
                                        HStack(spacing: 12) {
                                            VStack(spacing: 0) {
                                                Text(event.date.it("d"))
                                                    .font(.numeral(20, weight: .bold))
                                                Text(event.date.weekdayShort)
                                                    .font(.caption2)
                                                    .foregroundStyle(Theme.secondaryInk)
                                            }
                                            .frame(width: 38)
                                            AbsenceRow(absence: event, showsReason: true)
                                        }
                                        if event.id != events.last?.id { Divider().overlay(Theme.separator) }
                                    }
                                }
                                .card(padding: 14)
                            }
                        }
                    }
                }
            }
            .pagePadding()
            .padding(.bottom, 24)
            .animation(.snappy, value: filtered)
        }
        .themedBackground()
        .screenTitle("Assenze e ritardi")
        .refreshable { await model.loadAbsences() }
    }

    private var counters: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                StatTile(title: "Assenze", value: "\(count(.absence))", symbol: AbsenceEvent.Kind.absence.symbol, tint: Theme.poor)
                StatTile(title: "Ritardi", value: "\(count(.late) + count(.shortLate))",
                         symbol: AbsenceEvent.Kind.late.symbol, tint: Theme.fair)
                StatTile(title: "Uscite", value: "\(count(.earlyExit))", symbol: AbsenceEvent.Kind.earlyExit.symbol, tint: Theme.neutral)
            }
        }
    }

    private func count(_ kind: AbsenceEvent.Kind) -> Int {
        model.absences.filter { $0.kind == kind }.count
    }
}
