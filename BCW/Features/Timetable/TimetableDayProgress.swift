import SwiftUI

/// A che punto è la giornata, accanto al giorno in grande della scheda Orario: la percentuale della
/// durata complessiva degli eventi già passata (`DayProgress`) e l'indicatore lineare di Material 3,
/// ondulato mentre la giornata è in corso (come la lezione della card "Adesso"), piatto prima
/// dell'inizio e a giornata finita. Oggi si aggiorna ogni minuto; un giorno passato è al 100%, uno
/// futuro allo 0%.
struct TimetableDayProgress: View {
    let day: Date
    /// Gli eventi del giorno, senza intervalli.
    let spans: [TimetableDefaultDay.Span]

    var body: some View {
        if day.isToday {
            TimelineView(.everyMinute) { context in
                content(minute: TimeOfDay.nowMinutes(of: context.date))
            }
        } else {
            content(minute: day < Date().startOfDay ? 24 * 60 : 0)
        }
    }

    @ViewBuilder
    private func content(minute: Int) -> some View {
        if let progress = DayProgress(spans: spans, minute: minute) {
            // Se accanto al nome del giorno non c'è spazio per la barra resta la percentuale.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    label(progress)
                    bar(progress)
                        .frame(minWidth: 56)
                }
                label(progress)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Avanzamento della giornata")
            .accessibilityValue("\(progress.percent)%")
        }
    }

    private func label(_ progress: DayProgress) -> some View {
        let running = progress.elapsed > 0 && !progress.isFinished
        return Text("\(progress.percent)%")
            .font(.numeral(17, weight: 600))
            .foregroundStyle(running ? Theme.primary : Theme.onSurfaceVariant)
            .contentTransition(.numericText())
            .animation(Motion.effects, value: progress.percent)
            .fixedSize()
    }

    @ViewBuilder
    private func bar(_ progress: DayProgress) -> some View {
        if progress.isFinished {
            // Giornata finita: la traccia attiva piena, senza onda.
            Capsule()
                .fill(Theme.primary)
                .frame(height: 4)
                .frame(height: 12)
        } else {
            WavyProgress(value: Double(progress.elapsed), total: Double(progress.total))
        }
    }
}
