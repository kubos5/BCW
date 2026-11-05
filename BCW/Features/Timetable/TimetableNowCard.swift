import SwiftUI

/// In cima all'orario di oggi: la lezione in corso (quanto manca, con l'avanzamento ondulato) e
/// quella dopo, oppure la prossima lezione con il tempo che manca. Le ore uguali di seguito contano
/// come una lezione sola, come nell'attività in diretta e nei widget: due ore di Italiano sono
/// "fino alle 12:00" con una barra sola, poi la materia dopo. Nel contenitore primario, con l'icona
/// in una forma di M3 Expressive. Toccandola si apre la lezione. Sparisce finite le lezioni. In basso
/// a destra un pulsante a icona avvia o ferma l'attività in diretta (pieno quando è in corso).
struct TimetableNowCard: View {
    let content: TimetableDayContent
    let actions: TimetableActions
    @Environment(AppModel.self) private var model
    @Environment(OverlayHost.self) private var host: OverlayHost?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let minute = TimeOfDay.nowMinutes(of: context.date)
            // Come la Lista: un intervallo sul passaggio tra due ore uguali le tiene separate.
            let lessons = TimetableLayout(entries: content.entries, splitAtBreaks: true).clusters
                .flatMap { $0.blocks.map(\.block) }
                .sorted { $0.start < $1.start }
            let current = lessons.last { $0.start <= minute && minute < $0.end }
            let next = lessons.first { $0.start >= (current?.end ?? minute) && $0.id != current?.id && $0.start > minute }
            if let shown = current ?? next {
                card(shown: shown, isCurrent: current != nil, next: current != nil ? next : nil, minute: minute)
            }
        }
    }

    private func card(shown: TimetableLayout.Block, isCurrent: Bool, next: TimetableLayout.Block?, minute: Int) -> some View {
        let showsLiveToggle = model.liveActivities.areActivitiesEnabled
        let title = shown.entries[0].displayTitle
        return Button {
            // L'ora in corso del gruppo, con le sue note e i suoi file.
            actions.open(shown.entries.last { $0.start <= minute } ?? shown.entries[0], content.day)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isCurrent ? "ADESSO" : "TRA \(TimeOfDay.duration(shown.start - minute).uppercased())")
                            .font(.m3(12, weight: 750))
                            .tracking(0.8)
                            .opacity(0.8)
                        Text(title)
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
                    WavyProgress(value: Double(minute - shown.start), total: Double(shown.end - shown.start))
                        // Senza la lezione dopo, il pulsante dell'attività in diretta sta accanto.
                        .padding(.trailing, showsLiveToggle && next == nil ? 48 : 0)
                }
                if let next {
                    HStack(spacing: 8) {
                        Icon("chevronRight", size: 18)
                        Text("Poi \(next.entries[0].displayTitle) alle \(TimeOfDay.string(next.start))")
                            .font(.m3(14, weight: 600))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Theme.onPrimaryContainer.opacity(0.08), in: .capsule)
                    // Lo spazio del pulsante dell'attività in diretta, sovrapposto.
                    .padding(.trailing, showsLiveToggle ? 44 : 0)
                } else if showsLiveToggle && !isCurrent {
                    Color.clear.frame(height: 36)
                }
            }
            .foregroundStyle(Theme.onPrimaryContainer)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.primaryContainer, in: .rect(cornerRadius: Theme.radii.xl, style: .continuous))
        }
        .buttonStyle(.pressable(radius: Theme.radii.xl, pressed: Theme.radii.l))
        .accessibilityElement(children: .combine)
        .overlay(alignment: .bottomTrailing) {
            if showsLiveToggle {
                liveToggle
                    .padding(20)
            }
        }
    }

    /// Avvia o ferma l'attività in diretta di oggi: pulsante a icona tonale, pieno quando è in corso.
    private var liveToggle: some View {
        let isRunning = model.liveActivities.isRunningToday
        return Button {
            Haptics.selection()
            Task {
                // L'avviso arriva quando si sa com'è andata.
                let result = await model.liveActivities.toggleToday()
                host?.showToast(result.message, icon: result.failed ? "alertCircle" : (isRunning ? "lock" : "lockClock"))
            }
        } label: {
            Icon("lockClock", size: 20)
                .foregroundStyle(isRunning ? Theme.primaryContainer : Theme.onPrimaryContainer)
                .frame(width: 36, height: 36)
                .background(isRunning ? Theme.onPrimaryContainer : Theme.onPrimaryContainer.opacity(0.08), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.pressable(radius: 18, pressed: 10))
        .accessibilityLabel(isRunning ? "Ferma l'attività in diretta" : "Avvia l'attività in diretta")
        .animation(Motion.spatialFast, value: isRunning)
    }

    private func detail(_ block: TimetableLayout.Block, isCurrent: Bool, minute: Int) -> String {
        var parts = [isCurrent ? "Fino alle \(TimeOfDay.string(block.end)) · ancora \(TimeOfDay.duration(block.end - minute))"
                               : "Alle \(TimeOfDay.string(block.start))"]
        if let room = block.entries.first(where: { !$0.room.isEmpty })?.room { parts.append(room) }
        return parts.joined(separator: " · ")
    }
}
