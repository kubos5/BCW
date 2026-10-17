import SwiftUI
import UIKit

// MARK: - Cambio di giorno (asse condiviso X)

/// Cambio di giorno di Dashboard e Orario con la transizione ad asse condiviso orizzontale di
/// Material 3: il giorno che esce scivola e svanisce da una parte, quello nuovo entra dall'altra,
/// con le molle spaziali di M3 Expressive. Scorrendo di lato il contenuto segue il dito (frenato);
/// rilasciato oltre la soglia, o con abbastanza velocità, si passa al giorno accanto.
@Observable
final class DaySwipe {
    /// Spostamento del contenuto mentre il dito trascina.
    fileprivate(set) var offset: CGFloat = 0
    /// Verso dell'ultimo cambio di giorno (+1 = avanti), letto dalla transizione.
    fileprivate(set) var direction = 1
    /// Falso nella modifica dell'orario.
    @ObservationIgnored var isEnabled = true
    /// Giorno precedente (-1) o successivo (+1), chiamato al rilascio.
    @ObservationIgnored var onSwipe: ((Int) -> Void)?

    /// Distanza percorsa dai due giorni nella transizione.
    static let travel: CGFloat = 64

    /// Cambia giorno nel verso indicato. Prima si fissa il verso (il giorno che esce lo legge nella
    /// sua transizione, che SwiftUI prende dall'ultimo aggiornamento in cui c'era), poi si cambia.
    func go(_ direction: Int, change: @escaping () -> Void) {
        if self.direction != direction {
            self.direction = direction
            DispatchQueue.main.async { self.apply(change) }
        } else {
            apply(change)
        }
    }

    private func apply(_ change: () -> Void) {
        withAnimation(Motion.spatial) {
            offset = 0
            change()
        }
    }

    fileprivate func dragChanged(_ translation: CGFloat) {
        // Frenato: segue il dito a metà, e sempre meno allontanandosi.
        let limit: CGFloat = 140
        offset = limit * tanh(translation * 0.6 / limit)
    }

    fileprivate func dragEnded(translation: CGFloat, velocity: CGFloat) {
        let heading = translation + velocity * 0.12
        // Oltre la soglia (contando la velocità) e senza essere tornati indietro.
        if abs(heading) > 72, translation * heading >= 0, let onSwipe {
            Haptics.selection()
            onSwipe(heading < 0 ? 1 : -1)
        } else {
            withAnimation(Motion.spatialFast) { offset = 0 }
        }
    }
}

/// Il giorno mostrato: cambia con la transizione ad asse condiviso X e segue il dito scorrendo.
struct DayPage<Content: View>: View {
    let swipe: DaySwipe
    let day: Date
    @ViewBuilder let content: (Date) -> Content

    var body: some View {
        ZStack(alignment: .top) {
            // Lo spostamento del dito sta sulla pagina (non sul contenitore): al cambio di giorno la
            // pagina vecchia esce da dove l'ha lasciata il dito, quella nuova entra dal lato opposto.
            content(day)
                .offset(x: swipe.offset)
                .opacity(1 - min(abs(swipe.offset) / 420, 0.3))
                .id(day)
                .transition(.sharedAxisX(forward: swipe.direction > 0, distance: DaySwipe.travel))
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - Gesto

/// Scorrimento laterale sul contenuto (da mettere sullo sfondo del contenuto di uno `ScrollView`):
/// un riconoscitore di UIKit aggiunto allo scorrimento, che parte solo per movimenti orizzontali e
/// che lo scorrimento verticale aspetta. Non parte sopra gli elementi che scorrono di lato (chip).
struct DaySwipeGesture: UIViewRepresentable {
    let swipe: DaySwipe

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let swipe: DaySwipe
        weak var scrollView: UIScrollView?
        let pan = UIPanGestureRecognizer()
        /// Scorrimenti fermati mentre il dito sposta il giorno (sempre o orizzontale o verticale).
        private var locked: [UIScrollView] = []

        init(swipe: DaySwipe) {
            self.swipe = swipe
            super.init()
            pan.addTarget(self, action: #selector(handle(_:)))
            pan.delegate = self
            pan.name = "BCW.daySwipe"
        }

        /// Cerca lo scorrimento che contiene `view` e ci aggiunge il gesto (a ogni spostamento nella
        /// gerarchia: ricostruendo la pagina lo scorrimento può cambiare).
        func attach(from view: UIView) {
            guard view.window != nil else { return }
            var current = view.superview
            while let candidate = current, !(candidate is UIScrollView) { current = candidate.superview }
            guard let found = current as? UIScrollView, found !== scrollView || pan.view !== found else { return }
            detach()
            scrollView = found
            found.addGestureRecognizer(pan)
        }

        func detach() {
            if [.began, .changed].contains(pan.state) { swipe.dragEnded(translation: 0, velocity: 0) }
            unlock()
            pan.view?.removeGestureRecognizer(pan)
            scrollView = nil
        }

        /// Gli scorrimenti verticali che contengono il punto toccato: quello del contenuto e quelli
        /// annidati o esterni (dopo un cambio di tema il gesto poteva stare su uno diverso da quello
        /// che scorreva, e si scorreva in diagonale).
        private func verticalScrollViews(at point: CGPoint, in view: UIView) -> [UIScrollView] {
            var found: [UIScrollView] = []
            var current: UIView? = view.hitTest(point, with: nil)
            while let candidate = current {
                if let scroll = candidate as? UIScrollView, scroll.contentSize.width <= scroll.bounds.width + 1 {
                    found.append(scroll)
                }
                current = candidate.superview
            }
            return found
        }

        private func lock(_ scrollViews: [UIScrollView]) {
            unlock()
            for scroll in scrollViews where scroll.isScrollEnabled {
                // Spegnerlo annulla anche uno scorrimento appena partito.
                scroll.isScrollEnabled = false
                locked.append(scroll)
            }
        }

        private func unlock() {
            for scroll in locked { scroll.isScrollEnabled = true }
            locked = []
        }

        @objc private func handle(_ recognizer: UIPanGestureRecognizer) {
            let window = recognizer.view?.window
            switch recognizer.state {
            case .began:
                if let view = recognizer.view {
                    lock(verticalScrollViews(at: recognizer.location(in: view), in: view))
                }
            case .changed:
                swipe.dragChanged(recognizer.translation(in: window).x)
            case .ended:
                unlock()
                swipe.dragEnded(translation: recognizer.translation(in: window).x,
                                velocity: recognizer.velocity(in: window).x)
            case .cancelled, .failed:
                unlock()
                swipe.dragEnded(translation: 0, velocity: 0)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard swipe.isEnabled, swipe.onSwipe != nil, let view = pan.view else { return false }
            let velocity = pan.velocity(in: view)
            guard abs(velocity.x) > abs(velocity.y) * 1.3 else { return false }
            // Se uno scorrimento verticale è già partito, resta verticale.
            let point = pan.location(in: view)
            if verticalScrollViews(at: point, in: view).contains(where: { $0.isDragging || $0.isDecelerating }) {
                return false
            }
            // Gli elementi che scorrono di lato (filtri) hanno la precedenza.
            var hit = view.hitTest(point, with: nil)
            while let current = hit, current !== view {
                if let scroll = current as? UIScrollView, scroll.contentSize.width > scroll.bounds.width + 1 { return false }
                hit = current.superview
            }
            return true
        }

        /// Lo scorrimento verticale parte solo se questo gesto non parte (rinuncia subito se il
        /// movimento è verticale).
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other === scrollView?.panGestureRecognizer
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(swipe: swipe) }

    /// Vista invisibile che segnala quando entra in una finestra o cambia contenitore.
    final class Anchor: UIView {
        var onMove: ((UIView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onMove?(self)
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            onMove?(self)
        }
    }

    func makeUIView(context: Context) -> Anchor {
        let view = Anchor(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isHidden = true
        let coordinator = context.coordinator
        view.onMove = { view in
            DispatchQueue.main.async { [weak view] in
                if let view { coordinator.attach(from: view) }
            }
        }
        return view
    }

    func updateUIView(_ view: Anchor, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async { [weak view] in
            if let view { coordinator.attach(from: view) }
        }
    }

    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) {
        view.onMove = nil
        coordinator.detach()
    }
}
