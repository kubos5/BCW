import SwiftUI

/// In cima all'orario di oggi: la lezione in corso (quanto manca, con l'avanzamento ondulato) e
/// quella dopo, oppure la prossima lezione con il tempo che manca. Nel contenitore primario,
/// con l'icona in una forma di M3 Expressive. Toccandola si apre la lezione. Sparisce finite le
/// lezioni.
struct TimetableNowCard: View {
    let content: TimetableDayContent
    let actions: TimetableActions

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let minute = TimeOfDay.nowMinutes(of: context.date)
            let lessons = content.entries.filter { !$0.isBreak }.sorted { $0.start < $1.start }
            let current = lessons.last { $0.start <= minute && minute < $0.end }
            let next = lessons.first { $0.start >= (current?.end ?? minute) && $0.id != current?.id && $0.start > minute }
            if let shown = current ?? next {
                card(shown: shown, isCurrent: current != nil, next: current != nil ? next : nil, minute: minute)
            }
        }
    }

    private func card(shown: TimetableEntry, isCurrent: Bool, next: TimetableEntry?, minute: Int) -> some View {
        Button {
            actions.open(shown, content.day)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isCurrent ? "ADESSO" : "TRA \(TimeOfDay.duration(shown.start - minute).uppercased())")
                            .font(.m3(12, weight: 750))
                            .tracking(0.8)
                            .opacity(0.8)
                        Text(shown.displayTitle)
                            .font(.m3(26, weight: 500, rounded: true))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(detail(shown, isCurrent: isCurrent, minute: minute))
                            .font(.m3(14))
                            .opacity(0.85)
                    }
                    Spacer(minLength: 0)
                    Shaped(shape: isCurrent ? .cookie12Sided : .sunny, fill: Theme.onPrimaryContainer.opacity(0.12), size: 56) {
                        Icon(isCurrent ? "timetableFill" : "schedule", size: 26)
                    }
                }
                if isCurrent {
                    WavyProgress(value: Double(minute - shown.start), total: Double(shown.duration))
                }
                if let next {
                    HStack(spacing: 8) {
                        Icon("chevronRight", size: 18)
                        Text("Poi \(next.displayTitle) alle \(TimeOfDay.string(next.start))")
                            .font(.m3(14, weight: 600))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Theme.onPrimaryContainer.opacity(0.08), in: .capsule)
                }
            }
            .foregroundStyle(Theme.onPrimaryContainer)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.primaryContainer, in: .rect(cornerRadius: Theme.radii.xl, style: .continuous))
        }
        .buttonStyle(.pressable(radius: Theme.radii.xl, pressed: Theme.radii.l))
        .accessibilityElement(children: .combine)
    }

    private func detail(_ entry: TimetableEntry, isCurrent: Bool, minute: Int) -> String {
        var parts = [isCurrent ? "Fino alle \(TimeOfDay.string(entry.end)) · ancora \(TimeOfDay.duration(entry.end - minute))"
                               : "Alle \(TimeOfDay.string(entry.start))"]
        if !entry.room.isEmpty { parts.append(entry.room) }
        return parts.joined(separator: " · ")
    }
}
