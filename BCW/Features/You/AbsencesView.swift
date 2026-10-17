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
                    HStack(spacing: 12) {
                        Icon("alertCircleFill", size: 22)
                        Text(model.unjustifiedAbsences.count == 1
                             ? "Hai un evento da giustificare"
                             : "Hai \(model.unjustifiedAbsences.count) eventi da giustificare")
                            .font(.m3(14, weight: 600))
                    }
                    .foregroundStyle(Theme.onPoorContainer)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.poorContainer, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
                }

                ChipRow {
                    FilterChip(title: "Da giustificare", icon: "alertCircle", isSelected: onlyPending) {
                        onlyPending.toggle()
                    }
                    FilterChip(title: "Tutti", isSelected: kind == nil) { kind = nil }
                    ForEach([AbsenceEvent.Kind.absence, .late, .earlyExit]) { k in
                        FilterChip(title: k.pluralTitle, icon: k.icon, isSelected: kind == k) {
                            kind = kind == k ? nil : k
                        }
                    }
                }

                if filtered.isEmpty {
                    EmptyState("Nessun evento", icon: "checkCircle", description: "Nessuna assenza, ritardo o uscita registrati.")
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(byMonth, id: \.0) { month, events in
                            ListGroup(month.monthYear) {
                                    ForEach(events) { event in
                                        // Data, icona e stato restano centrati sull'intera riga,
                                        // anche quando dettaglio e motivo occupano più righe.
                                        HStack(spacing: 12) {
                                            VStack(spacing: 0) {
                                                Text(event.date.it("d"))
                                                    .font(.numeral(22))
                                                    .foregroundStyle(Theme.ink)
                                                Text(event.date.weekdayShort.uppercased())
                                                    .font(.m3(11, weight: 600))
                                                    .foregroundStyle(Theme.secondaryInk)
                                            }
                                            .frame(width: 44)
                                            AbsenceRow(absence: event, showsReason: true)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 12)
                                    }
                            }
                        }
                    }
                }
            }
            .pagePadding()
            .padding(.bottom, 32)
            .animation(Motion.spatial, value: filtered)
        }
        .tracksPageScroll()
        .themedBackground()
        .refreshable { await model.loadAbsences() }
        .pageChrome("Assenze e ritardi", style: .inline)
    }

    private var counters: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                StatTile(title: "Assenze", value: "\(count(.absence))", icon: AbsenceEvent.Kind.absence.icon, tint: Theme.poor,
                         shape: .clover4Leaf, corners: .leading, vertical: true)
                StatTile(title: "Ritardi", value: "\(count(.late) + count(.shortLate))",
                         icon: AbsenceEvent.Kind.late.icon, tint: Theme.fair, shape: .sunny, corners: .center, vertical: true)
                StatTile(title: "Uscite", value: "\(count(.earlyExit))", icon: AbsenceEvent.Kind.earlyExit.icon, tint: Theme.neutral,
                         shape: .cookie6Sided, corners: .trailing, vertical: true)
            }
        }
    }

    private func count(_ kind: AbsenceEvent.Kind) -> Int {
        model.absences.filter { $0.kind == kind }.count
    }
}
