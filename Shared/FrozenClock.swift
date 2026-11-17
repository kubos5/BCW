import SwiftUI

/// Solo DEBUG: un'ora fissa per le immagini della pagina dell'App Store (`StoreAssets`). I testi e le
/// barre del tempo che iOS aggiorna da solo (`Text(timerInterval:)`, `ProgressView(timerInterval:)`)
/// seguono l'ora vera, quindi una lezione delle 10 disegnata di notte sarebbe già finita; con
/// `FrozenClock.date` mostrano il tempo a quell'ora. In Release `pause` è sempre `nil` e
/// `TimerProgress` è il `ProgressView(timerInterval:)` di sempre.
nonisolated enum FrozenClock {
    #if DEBUG
    nonisolated(unsafe) static var date: Date?
    /// L'ora fissa, se c'è, altrimenti adesso.
    static var now: Date { date ?? Date() }
    #else
    static var now: Date { Date() }
    #endif
}

extension Text {
    /// `Text(timerInterval:countsDown:)`. Con l'ora fissa di `FrozenClock` (solo DEBUG) un testo fermo
    /// con il tempo a quell'ora: `pauseTime` non basta, perché il testo si ferma solo quando l'ora vera
    /// l'ha superata.
    static func timer(_ interval: ClosedRange<Date>, countsDown: Bool = true) -> Text {
        #if DEBUG
        if let date = FrozenClock.date {
            let clamped = min(max(date, interval.lowerBound), interval.upperBound)
            let seconds = Int(countsDown ? interval.upperBound.timeIntervalSince(clamped)
                                         : clamped.timeIntervalSince(interval.lowerBound))
            let text = seconds >= 3600
                ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
                : String(format: "%d:%02d", seconds / 60, seconds % 60)
            return Text(verbatim: text)
        }
        #endif
        return Text(timerInterval: interval, countsDown: countsDown)
    }
}

/// `ProgressView(timerInterval:countsDown:)` senza etichetta, fermo all'ora di `FrozenClock` (solo DEBUG).
struct TimerProgress<CurrentValueLabel: View>: View {
    let interval: ClosedRange<Date>
    let countsDown: Bool
    @ViewBuilder var currentValueLabel: () -> CurrentValueLabel

    init(_ interval: ClosedRange<Date>, countsDown: Bool,
         @ViewBuilder currentValueLabel: @escaping () -> CurrentValueLabel = { EmptyView() }) {
        self.interval = interval
        self.countsDown = countsDown
        self.currentValueLabel = currentValueLabel
    }

    var body: some View {
        #if DEBUG
        if let date = FrozenClock.date {
            let total = max(interval.upperBound.timeIntervalSince(interval.lowerBound), 1)
            let done = min(max(date.timeIntervalSince(interval.lowerBound) / total, 0), 1)
            // `ImageRenderer` non disegna la barra di UIKit (`UIProgressView`): qui una barra di SwiftUI.
            ProgressView(value: countsDown ? 1 - done : done) {
                EmptyView()
            } currentValueLabel: {
                currentValueLabel()
            }
            .progressViewStyle(FrozenBarStyle())
        } else {
            live
        }
        #else
        live
        #endif
    }

    #if DEBUG
    /// Barra lineare disegnata da SwiftUI, nel colore della tinta (solo per le immagini ferme).
    private struct FrozenBarStyle: ProgressViewStyle {
        func makeBody(configuration: Configuration) -> some View {
            let value = configuration.fractionCompleted ?? 0
            Capsule()
                .fill(.tint.opacity(0.22))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(.tint).frame(width: max(proxy.size.height, proxy.size.width * value))
                    }
                }
                .frame(height: 4)
        }
    }
    #endif

    private var live: some View {
        ProgressView(timerInterval: interval, countsDown: countsDown) {
            EmptyView()
        } currentValueLabel: {
            currentValueLabel()
        }
    }
}
