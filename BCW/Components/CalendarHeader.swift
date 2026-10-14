import SwiftUI

/// Valore intermedio tra `a` (con `t` = 0) e `b` (con `t` = 1).
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

#if os(iOS)
import UIKit

// MARK: - Stato

/// Intestazione mobile con la settimana (o il mese) sopra un'area che scorre, su iPhone: Orario
/// (viste Lista e Giorno) e Dashboard (viste Lista e Calendario). L'intestazione non fa parte dello
/// scorrimento: sta sopra l'area, che si sposta insieme a lei quando si riduce o si apre (`Shift`).
/// Il passaggio non usa lo scorrimento di iOS ma un gesto proprio (`CalendarHeaderPan`):
/// - con l'intestazione intera, trascinando verso l'alto si riduce e l'area sale con lei, al
///   massimo fino a ridotta in un gesto; verso il basso c'è un elastico (o lo scorrimento di iOS,
///   con l'aggiornamento, se `expandedScrolls`);
/// - con l'intestazione ridotta l'area scorre normalmente (e rimbalza in cima); un nuovo gesto
///   verso il basso, partendo dalla cima, la riapre;
/// - un gesto durante uno scatto lo riprende dal punto in cui si trova.
/// Il contenuto segue il dito con una curva di resistenza: prima del punto di resistenza (metà
/// del tratto del dito) resta sempre più indietro, superato il punto lo rincorre (con una
/// vibrazione) ed è tirato verso l'altra posizione. Lasciando il dito decide il lato del punto
/// (con la velocità) e una molla calcolata a ogni fotogramma porta alla posizione, senza superarla.
/// Toccata da ridotta l'intestazione si riapre.
///
/// Gestisce anche lo scorrimento orizzontale per cambiare giorno (`onSwipeDay`): il contenuto
/// segue il dito e, superata una soglia, esce di lato mentre il giorno nuovo entra dall'altro.
/// I valori che cambiano a ogni fotogramma si leggono solo nell'intestazione e in `Shift`: il resto
/// della pagina non si ricalcola.
@Observable
final class WeekHeaderScroll: NSObject {
    /// 0 intera, 1 ridotta; trascinando oltre l'intera scende un poco sotto lo 0 (elastico).
    fileprivate(set) var progress: CGFloat = 0
    /// Ridotta: solo allora l'area scorre (con `expandedScrolls` anche da intera).
    fileprivate(set) var isCollapsed = false
    /// Differenza di altezza tra intera e ridotta: dipende dalla vista (settimana o mese, e nel
    /// mese dal numero di settimane).
    var range: CGFloat = CalendarHeader.weekExpandedHeight - CalendarHeader.collapsedHeight
    /// Spostamento orizzontale del contenuto durante il cambio di giorno.
    fileprivate(set) var swipeOffset: CGFloat = 0

    /// Con l'intestazione intera l'area scorre comunque verso il basso (es. per aggiornare la
    /// Dashboard tirando giù); altrimenti è ferma e c'è un elastico.
    @ObservationIgnored var expandedScrolls = false
    /// Giorno precedente (-1) o successivo (+1); `nil` = niente scorrimento laterale.
    @ObservationIgnored var onSwipeDay: ((Int) -> Void)?
    /// Larghezza dell'area, per far uscire del tutto il contenuto di lato.
    @ObservationIgnored var swipeWidth: CGFloat = 400

    /// Punto di resistenza, a metà del tratto percorso dal dito.
    static let threshold: CGFloat = 0.5
    /// Asintoto della curva di resistenza: quanto al massimo il contenuto si muove prima del punto.
    private static let lag: CGFloat = 0.35
    /// Costante di tempo della rincorsa al passaggio del punto.
    private static let catchUpTime: CGFloat = 0.06

    /// Posizione del dito in avanzamento (0 intera, 1 ridotta), senza resistenza.
    @ObservationIgnored private var finger: CGFloat = 0
    @ObservationIgnored private var fingerStart: CGFloat = 0
    /// Scarto tra il contenuto e la curva, che si riassorbe in fretta (rincorsa dopo il punto).
    @ObservationIgnored private var catchUp: CGFloat = 0
    @ObservationIgnored private var isDragging = false
    /// Gesto che ha ripreso uno scatto a metà: il contenuto segue il dito da dov'è, senza la curva
    /// (riportarlo sulla curva lo farebbe saltare); il punto di resistenza è a metà del tratto.
    @ObservationIgnored private var isDirect = false
    @ObservationIgnored private var directStart: CGFloat = 0
    @ObservationIgnored private let haptics = UIImpactFeedbackGenerator(style: .medium)
    /// Molla calcolata a ogni fotogramma (non un'animazione di SwiftUI): `progress` è sempre il
    /// valore visibile, così un gesto può riprendere l'intestazione a metà di uno scatto.
    @ObservationIgnored private var spring: (target: CGFloat, velocity: CGFloat)?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval = 0

    @ObservationIgnored private var swipeStart: CGFloat = 0
    @ObservationIgnored private var swipeSpring: (target: CGFloat, velocity: CGFloat, completion: (() -> Void)?)?
    @ObservationIgnored private var swipeLink: CADisplayLink?
    @ObservationIgnored private var swipeTimestamp: CFTimeInterval = 0

    /// Ferma in una delle due posizioni (né trascinata né in movimento).
    var isSettled: Bool { displayLink == nil && !isDragging && (progress == 0 || progress == 1) }

    /// Riapre l'intestazione ridotta (tocco sulla striscia, nuovo tocco sulla scheda).
    func open() {
        if progress > 0.5 { haptics.impactOccurred() }
        settle(collapsed: false)
    }

    /// Intestazione intera senza animazione (cambio di vista: lo scorrimento riparte dalla cima).
    func reset() {
        stopLink()
        isDragging = false
        progress = 0
        isCollapsed = false
    }

    // MARK: Curva di resistenza

    /// Rallentamento crescente: segue il dito all'inizio, poi sempre meno.
    private static func slowed(_ x: CGFloat) -> CGFloat {
        lag * (1 - exp(-x / lag))
    }

    /// Dove sta il contenuto con il dito in `finger`: indietro prima del punto, avanti dopo; oltre
    /// la ridotta non si va in un gesto, oltre l'intera c'è un elastico sempre più duro.
    static func resisted(_ finger: CGFloat) -> CGFloat {
        if finger < 0 { return -(1 - 1 / (1 - finger * 0.55)) * 0.5 }
        if finger >= 1 { return 1 }
        return finger < threshold ? slowed(finger) : 1 - slowed(1 - finger)
    }

    /// Quanto si muove il contenuto per un movimento del dito, in `finger`.
    private static func slope(_ finger: CGFloat) -> CGFloat {
        guard finger >= 0, finger < 1 else { return 0.3 }
        return exp(-(finger < threshold ? finger : 1 - finger) / lag)
    }

    /// Posizione del dito che corrisponde al contenuto in `value` (per riprendere un gesto a
    /// metà di uno scatto); nel salto della rincorsa si sceglie il lato più vicino.
    private static func finger(for value: CGFloat) -> CGFloat {
        if value <= 0 { return 0 }
        if value >= 1 { return 1 }
        let edge = slowed(threshold)
        if value <= edge { return -lag * log(max(0.0001, 1 - value / lag)) }
        if value >= 1 - edge { return 1 + lag * log(max(0.0001, 1 - (1 - value) / lag)) }
        return value < 0.5 ? threshold - 0.0001 : threshold
    }

    // MARK: Gesto verticale

    fileprivate func began() {
        let resuming = displayLink != nil
        stopLink()
        isDragging = true
        haptics.prepare()
        catchUp = 0
        isDirect = resuming && progress > 0.001 && progress < 0.999
        if isDirect {
            directStart = progress
            finger = progress
            return
        }
        finger = Self.finger(for: progress)
        fingerStart = finger
    }

    /// `translation`: spostamento del dito verso l'alto, in punti, dall'inizio del gesto.
    fileprivate func changed(_ translation: CGFloat) {
        let previous = finger
        if isDirect {
            finger = min(1, directStart + translation / max(range, 1))
            if (previous < Self.threshold) != (finger < Self.threshold) { haptics.impactOccurred() }
            progress = finger < 0 ? Self.resisted(finger) : finger
            return
        }
        finger = fingerStart + translation / max(range, 1)
        if (previous < Self.threshold) != (finger < Self.threshold), max(previous, finger) > 0, min(previous, finger) < 1 {
            // Superato il punto: il contenuto parte da dov'è e rincorre la nuova posizione.
            catchUp = progress - Self.resisted(finger)
            haptics.impactOccurred()
            haptics.prepare()
            startLink()
        }
        progress = Self.resisted(finger) + catchUp
    }

    /// `velocity`: velocità del dito verso l'alto, in punti al secondo.
    fileprivate func ended(velocity: CGFloat) {
        isDragging = false
        let speed = velocity / max(range, 1)
        // Dove arriverebbe il dito in un decimo di secondo, rispetto al punto di resistenza.
        let heading = finger + speed * 0.1
        let collapsed = heading >= Self.threshold
        // Un colpo veloce supera il punto di resistenza solo lasciando il dito: si vibra qui.
        if collapsed != (finger >= Self.threshold) { haptics.impactOccurred() }
        settle(collapsed: collapsed, velocity: speed * (isDirect ? 1 : Self.slope(finger)))
        isDirect = false
    }

    // MARK: Molla

    /// Porta l'intestazione intera o ridotta con una molla che parte dalla velocità del contenuto
    /// (`velocity` in avanzamento al secondo).
    fileprivate func settle(collapsed: Bool, velocity: CGFloat = 0) {
        isCollapsed = collapsed
        catchUp = 0
        let target: CGFloat = collapsed ? 1 : 0
        // Già lì (es. un gesto arrivato fino in fondo): niente molla, che con la velocità del dito
        // andrebbe oltre.
        guard abs(progress - target) > 0.001 else {
            stopLink()
            progress = target
            return
        }
        spring = (target, velocity)
        startLink()
    }

    private func startLink() {
        guard displayLink == nil else { return }
        displayLink = makeLink(#selector(step(_:)))
        lastTimestamp = 0
    }

    private func makeLink(_ selector: Selector) -> CADisplayLink {
        let link = CADisplayLink(target: self, selector: selector)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        return link
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let elapsed = CGFloat(lastTimestamp == 0 ? link.duration : min(now - lastTimestamp, 1.0 / 30))
        lastTimestamp = now
        if isDragging {
            // Rincorsa dopo il punto di resistenza (o dopo aver ripreso uno scatto a metà).
            catchUp *= exp(-elapsed / Self.catchUpTime)
            if abs(catchUp) < 0.0005 { catchUp = 0; stopLink() }
            progress = Self.resisted(finger) + catchUp
            return
        }
        guard var current = spring else { stopLink(); return }
        // Molla rigida, appena sotto lo smorzamento critico, in passi brevi.
        var value = progress
        let steps = 4
        let dt = elapsed / CGFloat(steps)
        var crossed = false
        for _ in 0..<steps {
            let before = value - current.target
            let acceleration = -560 * before - 43 * current.velocity
            current.velocity += acceleration * dt
            value += current.velocity * dt
            // Niente rimbalzo oltre la posizione finale (con un colpo veloce il contenuto salirebbe
            // oltre l'intestazione ridotta e tornerebbe giù): ci si ferma lì.
            if before != 0, (value - current.target).sign != before.sign { crossed = true; break }
        }
        if crossed || (abs(value - current.target) < 0.0008 && abs(current.velocity) < 0.01) {
            value = current.target
            stopLink()
        } else {
            spring = current
        }
        progress = value
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
        spring = nil
    }

    // MARK: Scorrimento laterale (cambio di giorno)

    /// Giorno accanto mostrato durante lo scorrimento laterale (+1 il successivo, a destra; -1 il
    /// precedente, a sinistra; 0 nessuno). Cambia solo quando cambia il verso, non a ogni fotogramma.
    fileprivate(set) var swipeDirection = 0
    fileprivate func swipeBegan() {
        // Anche durante il cambio di giorno: si riprende il contenuto da dov'è.
        stopSwipe()
        swipeStart = swipeOffset
    }

    fileprivate func swipeChanged(_ translation: CGFloat) {
        swipeOffset = swipeStart + translation
        updateSwipeDirection()
    }

    private func updateSwipeDirection() {
        let direction = swipeOffset < -0.5 ? 1 : (swipeOffset > 0.5 ? -1 : swipeDirection)
        if direction != swipeDirection { swipeDirection = direction }
    }

    /// Oltre un terzo della larghezza (contando la velocità) si cambia giorno, subito al rilascio
    /// (il calendario segna il giorno nuovo e vibra): i due contenuti si scambiano di ruolo nella
    /// stessa posizione (il giorno nuovo diventa quello principale, il vecchio quello accanto) e poi
    /// scorrono insieme fino al giorno nuovo. Altrimenti tutto torna al suo posto.
    fileprivate func swipeEnded(velocity: CGFloat) {
        let heading = swipeOffset + velocity * 0.15
        guard abs(heading) > swipeWidth * 0.3, let onSwipeDay else {
            animateSwipe(to: 0, velocity: velocity) { [weak self] in self?.swipeDirection = 0 }
            return
        }
        let direction = heading < 0 ? 1 : -1
        onSwipeDay(direction)
        swipeOffset += CGFloat(direction) * swipeWidth
        swipeDirection = -direction
        animateSwipe(to: 0, velocity: velocity) { [weak self] in self?.swipeDirection = 0 }
    }

    private func animateSwipe(to target: CGFloat, velocity: CGFloat, completion: (() -> Void)? = nil) {
        swipeSpring = (target, velocity, completion)
        guard swipeLink == nil else { return }
        swipeLink = makeLink(#selector(swipeStep(_:)))
        swipeTimestamp = 0
    }

    @objc private func swipeStep(_ link: CADisplayLink) {
        guard var current = swipeSpring else { stopSwipe(); return }
        let now = link.timestamp
        let elapsed = CGFloat(swipeTimestamp == 0 ? link.duration : min(now - swipeTimestamp, 1.0 / 30))
        swipeTimestamp = now
        var value = swipeOffset
        let steps = 4
        let dt = elapsed / CGFloat(steps)
        var crossed = false
        for _ in 0..<steps {
            let before = value - current.target
            let acceleration = -420 * before - 41 * current.velocity
            current.velocity += acceleration * dt
            value += current.velocity * dt
            // Nessun rimbalzo oltre la posizione finale: ci si ferma lì.
            if before != 0, (value - current.target).sign != before.sign { crossed = true; break }
        }
        if crossed || (abs(value - current.target) < 0.3 && abs(current.velocity) < 20) {
            swipeOffset = current.target
            let completion = current.completion
            stopSwipe()
            completion?()
        } else {
            swipeSpring = current
            swipeOffset = value
        }
    }

    private func stopSwipe() {
        swipeLink?.invalidate()
        swipeLink = nil
        swipeSpring = nil
    }

    // MARK: Modificatore

    /// Sposta l'area con l'intestazione (e di lato durante il cambio di giorno) e, se l'area non
    /// scorre da intera, la blocca finché l'intestazione non è ridotta.
    struct Shift: ViewModifier {
        let state: WeekHeaderScroll

        func body(content: Content) -> some View {
            content
                .offset(x: state.swipeOffset, y: (1 - state.progress) * state.range)
                .scrollDisabled(!state.isCollapsed && !state.expandedScrolls)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { state.swipeWidth = $0 }
        }
    }
}

/// Il giorno accanto, mostrato a fianco del contenuto durante lo scorrimento laterale: va messo sul
/// contenuto dello scorrimento (che deve avere `scrollClipDisabled`), così scorre e si sposta con
/// lui ed è già al suo posto quando i due si scambiano.
struct SwipeNeighbor<Neighbor: View>: ViewModifier {
    let state: WeekHeaderScroll
    @ViewBuilder let neighbor: (Int) -> Neighbor

    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            let direction = state.swipeDirection
            if direction != 0 {
                neighbor(direction)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .offset(x: CGFloat(direction) * state.swipeWidth)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transaction { $0.animation = nil }
            }
        }
    }
}

// MARK: - Gesti

/// I gesti dell'intestazione, aggiunti allo `UIScrollView` dell'area (va nello sfondo del contenuto
/// dello scorrimento, per trovarlo):
/// - verticale, che riduce e apre l'intestazione: parte sempre durante uno scatto; da intera verso
///   l'alto (e verso il basso se l'area non scorre); da ridotta solo verso il basso con l'area in
///   cima;
/// - orizzontale, che cambia giorno (se `onSwipeDay` c'è).
/// Quando uno dei due parte, lo scorrimento aspetta che fallisca e quindi non si muove; le misure
/// sono nella finestra, così lo spostamento dell'area non le altera.
struct CalendarHeaderPan: UIViewRepresentable {
    let state: WeekHeaderScroll
    /// Lo scorrimento laterale è sospeso (es. nella modifica dell'orario).
    var swipeEnabled = true

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let state: WeekHeaderScroll
        var swipeEnabled = true
        weak var scrollView: UIScrollView?
        let vertical = UIPanGestureRecognizer()
        let horizontal = UIPanGestureRecognizer()

        init(state: WeekHeaderScroll) {
            self.state = state
            super.init()
            vertical.addTarget(self, action: #selector(verticalPan(_:)))
            horizontal.addTarget(self, action: #selector(horizontalPan(_:)))
            vertical.delegate = self
            horizontal.delegate = self
        }

        func attach(to scrollView: UIScrollView) {
            guard self.scrollView !== scrollView else { return }
            detach()
            self.scrollView = scrollView
            scrollView.addGestureRecognizer(vertical)
            scrollView.addGestureRecognizer(horizontal)
        }

        func detach() {
            scrollView?.removeGestureRecognizer(vertical)
            scrollView?.removeGestureRecognizer(horizontal)
        }

        @objc private func verticalPan(_ recognizer: UIPanGestureRecognizer) {
            let window = recognizer.view?.window
            switch recognizer.state {
            case .began:
                // Il gesto viene riconosciuto dopo qualche punto di movimento: contare da qui,
                // altrimenti il contenuto salterebbe di quei punti al primo aggiornamento.
                recognizer.setTranslation(.zero, in: window)
                state.began()
            case .changed:
                state.changed(-recognizer.translation(in: window).y)
            case .ended, .cancelled, .failed:
                state.ended(velocity: recognizer.state == .ended ? -recognizer.velocity(in: window).y : 0)
            default:
                break
            }
        }

        @objc private func horizontalPan(_ recognizer: UIPanGestureRecognizer) {
            let window = recognizer.view?.window
            switch recognizer.state {
            case .began:
                state.swipeBegan()
            case .changed:
                state.swipeChanged(recognizer.translation(in: window).x)
            case .ended, .cancelled, .failed:
                state.swipeEnded(velocity: recognizer.state == .ended ? recognizer.velocity(in: window).x : 0)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let scrollView, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: scrollView.window)
            if pan === horizontal {
                return state.isSettled && swipeEnabled && state.onSwipeDay != nil && abs(velocity.x) > abs(velocity.y) * 1.2
            }
            guard abs(velocity.y) > abs(velocity.x) else { return false }
            // Durante uno scatto il gesto lo riprende (anche verso l'alto mentre si riduce: lasciarlo
            // allo scorrimento, che si muove con l'area, lo farebbe tremare).
            if !state.isSettled { return true }
            if !state.isCollapsed { return velocity.y < 0 || !state.expandedScrolls }
            let atTop = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 0.5
            return atTop && velocity.y > 0
        }

        /// Lo scorrimento parte solo se questi gesti non partono.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer === scrollView?.panGestureRecognizer
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        coordinator.swipeEnabled = swipeEnabled
        DispatchQueue.main.async {
            var current = view.superview
            while let candidate = current, !(candidate is UIScrollView) { current = candidate.superview }
            if let scrollView = current as? UIScrollView { coordinator.attach(to: scrollView) }
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }
}

// MARK: - Intestazione

/// La settimana (o il mese) in una card che galleggia sopra il contenuto e si riduce a una
/// striscia con i soli numeri della settimana del giorno scelto. Il passaggio è animato elemento
/// per elemento (`progress` va da 0, intera, a 1, ridotta): i numeri salgono al centro della
/// striscia, il rettangolo (o il cerchio) del giorno scelto diventa un cerchio più piccolo, la riga
/// del mese, le iniziali dei giorni, i pallini e le altre settimane del mese escono salendo e
/// svaniscono; nel mese compaiono i giorni dei mesi accanto che completano la settimana. Tutto è
/// tagliato solo dal bordo della card.
struct CalendarHeader: View {
    enum Style { case week, month }

    @Binding var selectedDay: Date
    let style: Style
    let progress: CGFloat
    let onExpand: () -> Void
    /// Altezza da intera (cambia nel mese con il numero di settimane).
    var onExpandedHeight: (CGFloat) -> Void = { _ in }

    static let weekExpandedHeight: CGFloat = 144
    static let collapsedHeight: CGFloat = 46

    private var isCollapsed: Bool { progress >= 1 }

    var body: some View {
        let p = min(max(progress, 0), 1)
        let shape = RoundedRectangle(cornerRadius: lerp(Theme.corner, Self.collapsedHeight / 2, p), style: .continuous)

        Group {
            switch style {
            case .week:
                WeekMorph(selectedDay: $selectedDay, progress: p)
                    .onAppear { onExpandedHeight(Self.weekExpandedHeight) }
            case .month:
                MonthMorph(selectedDay: $selectedDay, progress: p, onExpandedHeight: onExpandedHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .glassEffect(.regular, in: shape)
        .overlay {
            if isCollapsed {
                // Ridotta, la striscia si tocca solo per riaprirla.
                Color.clear
                    .contentShape(shape)
                    .onTapGesture(perform: onExpand)
                    .accessibilityElement()
                    .accessibilityLabel("Calendario, \(selectedDay.longDay)")
                    .accessibilityHint("Mostra il calendario intero")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
        // Il giorno scelto cambia sempre con l'animazione, anche quando la pagina lo cambia senza
        // (scorrendo di lato, dove il contenuto si scambia di colpo).
        .transaction(value: selectedDay) { transaction in
            transaction.disablesAnimations = false
            if transaction.animation == nil { transaction.animation = .snappy }
        }
    }
}

/// Riga del mese con le frecce, in cima alla card intera.
private struct MonthTitleRow: View {
    let title: String
    let back: () -> Void
    let forward: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Spacer()
            HStack(spacing: 4) {
                Button(action: back) { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Indietro")
                Button(action: forward) { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Avanti")
            }
            .glassButton()
            .buttonBorderShape(.circle)
            .controlSize(.small)
        }
    }
}

// MARK: Settimana

private struct WeekMorph: View {
    @Binding var selectedDay: Date
    let progress: CGFloat
    /// Settimana mostrata (inizio settimana): segue lo scorrimento orizzontale a pagine.
    @State private var visibleWeek: Date?

    private static let monthRowHeight: CGFloat = 40
    private static let expandedCellHeight: CGFloat = 76
    private static let verticalPadding: CGFloat = 14

    init(selectedDay: Binding<Date>, progress: CGFloat) {
        _selectedDay = selectedDay
        self.progress = progress
        _visibleWeek = State(initialValue: Self.week(containing: selectedDay.wrappedValue))
    }

    /// Settimane disponibili: due anni prima e dopo oggi.
    private static let weeks: [Date] = {
        let current = Date().startOfWeek
        return (-104...104).map { current.adding(days: $0 * 7) }
    }()

    private static let weekSet = Set(weeks)

    private static func week(containing day: Date) -> Date {
        let start = day.startOfWeek
        return weekSet.contains(start) ? start : (weeks.first { $0.isSameDay(as: start) } ?? start)
    }

    var body: some View {
        let p = progress
        VStack(spacing: 0) {
            MonthTitleRow(title: selectedDay.monthYear, back: { shift(-7) }, forward: { shift(7) })
                .frame(height: Self.monthRowHeight - 12)
                .padding(.bottom, 12)
                .padding(.horizontal, 14)
                // La riga sale ed esce dalla card (tagliata solo dal suo bordo).
                .padding(.top, -p * Self.monthRowHeight)
                .opacity(max(0, 1 - p * 1.8))
                .allowsHitTesting(p == 0)
            pager(progress: p)
                .frame(height: lerp(Self.expandedCellHeight, CalendarHeader.collapsedHeight, p))
        }
        .padding(.vertical, lerp(Self.verticalPadding, 0, p))
        .frame(height: lerp(CalendarHeader.weekExpandedHeight, CalendarHeader.collapsedHeight, p), alignment: .top)
        .onChange(of: visibleWeek) { _, week in
            // Scorrendo si passa alla settimana accanto mantenendo lo stesso giorno della settimana,
            // con l'animazione come toccando un giorno (anche "Oggi" nella barra compare animato).
            guard let week, !week.isSameDay(as: selectedDay.startOfWeek) else { return }
            let weekday = CVDate.calendar.dateComponents([.day], from: selectedDay.startOfWeek, to: selectedDay.startOfDay).day ?? 0
            withAnimation(.snappy) { selectedDay = week.adding(days: weekday) }
        }
        .onChange(of: selectedDay) { _, day in
            let week = Self.week(containing: day)
            if visibleWeek.map({ !$0.isSameDay(as: week) }) ?? true {
                withAnimation(.snappy) { visibleWeek = week }
            }
        }
    }

    private func pager(progress p: CGFloat) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(Self.weeks, id: \.self) { week in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { offset in
                            let day = week.adding(days: offset)
                            MorphingDayCell(day: day, isSelected: day.isSameDay(as: selectedDay), progress: p) {
                                withAnimation(.snappy) { selectedDay = day }
                            }
                        }
                    }
                    .padding(.horizontal, lerp(14, 8, p))
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $visibleWeek)
        .scrollIndicators(.hidden)
        // Le iniziali dei giorni salgono oltre la riga: le taglia solo la card.
        .scrollClipDisabled()
        .scrollDisabled(p > 0)
        .allowsHitTesting(p == 0)
    }

    private func shift(_ days: Int) {
        withAnimation(.snappy) { selectedDay = selectedDay.adding(days: days) }
    }
}

/// Un giorno della settimana che si trasforma con la card: intero (iniziale, numero, pallini, in un
/// rettangolo arrotondato se scelto) o ridotto (il solo numero, in un cerchio se scelto).
private struct MorphingDayCell: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let isSelected: Bool
    let progress: CGFloat
    let action: () -> Void

    static let circle: CGFloat = 34

    var body: some View {
        let p = progress
        let fade = max(0, 1 - p * 1.8)
        let holiday = model.calendarStatus(on: day)?.isHoliday == true

        Button(action: action) {
            // Posizioni rispetto al centro della cella (alta 76 punti da intera e 46 da ridotta).
            ZStack {
                Text(day.it("EEEEE").uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : Theme.secondaryInk)
                    .offset(y: lerp(-21.5, -38, p))
                    .opacity(fade)
                Text(day.it("d"))
                    .font(.numeral(19, weight: isSelected || day.isToday ? .bold : .medium))
                    .foregroundStyle(DayDots.numberColor(day: day, isSelected: isSelected, holiday: holiday))
                    .scaleEffect(lerp(1, 0.9, p))
                    .offset(y: lerp(3, 0, p))
                DayDots(day: day, isSelected: isSelected, size: 5)
                    .offset(y: lerp(23.5, 8, p))
                    .opacity(fade)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect(cornerRadius: 16))
            .background {
                // Il rettangolo del giorno scelto diventa un cerchio: larghezza e altezza scendono
                // fino al diametro e il raggio degli angoli arriva a metà del diametro.
                GeometryReader { geometry in
                    let width = lerp(geometry.size.width, Self.circle, p)
                    let height = lerp(geometry.size.height, Self.circle, p)
                    let shape = RoundedRectangle(cornerRadius: lerp(16, Self.circle / 2, p), style: .continuous)
                    Group {
                        if isSelected {
                            shape.fill(Theme.accent.gradient)
                        } else if day.isToday {
                            shape.strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
                        }
                    }
                    .frame(width: width, height: height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.longDay)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Pallini di un giorno: compiti, verifiche, eventi, assenze.
private struct DayDots: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        let events = model.events(on: day)
        HStack(spacing: size * 0.6) {
            if events.contains(where: { $0.kind == .homework }) { dot(Theme.neutral) }
            if events.contains(where: { $0.kind == .test }) { dot(isSelected ? .white : Theme.accent) }
            if events.contains(where: { $0.kind == .event }) { dot(Theme.fair) }
            if !model.absences(on: day).isEmpty { dot(Theme.poor) }
        }
        .frame(height: size)
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: size, height: size)
    }

    static func numberColor(day: Date, isSelected: Bool, holiday: Bool) -> Color {
        if isSelected { return .white }
        if day.isToday { return Theme.accent }
        if day.isWeekend || holiday { return Theme.secondaryInk }
        return Theme.ink
    }
}

// MARK: Mese

/// Il mese, che si riduce alla striscia della settimana del giorno scelto: quella settimana sale
/// al centro della striscia, le altre salgono con lei e svaniscono, e i giorni dei mesi accanto che
/// la completano compaiono (e spariscono riaprendo).
private struct MonthMorph: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedDay: Date
    let progress: CGFloat
    let onExpandedHeight: (CGFloat) -> Void
    /// Mese mostrato: segue lo scorrimento orizzontale a pagine.
    @State private var visibleMonth: Date?
    /// Settimane del mese mostrato, cambiate con un'animazione (la card si allunga o si accorcia).
    @State private var rowCount: Int

    private static let padding: CGFloat = 14
    private static let titleHeight: CGFloat = 28
    private static let titleGap: CGFloat = 12
    private static let weekdayHeight: CGFloat = 16
    private static let weekdayGap: CGFloat = 6
    static let cellHeight: CGFloat = 44
    private static let rowSpacing: CGFloat = 4
    private static let legendGap: CGFloat = 12
    private static let legendHeight: CGFloat = 14
    private static let weekdaySymbols = ["L", "M", "M", "G", "V", "S", "D"]

    private static var gridTop: CGFloat { padding + titleHeight + titleGap + weekdayHeight + weekdayGap }

    private static func gridHeight(_ rows: Int) -> CGFloat {
        CGFloat(rows) * cellHeight + CGFloat(rows - 1) * rowSpacing
    }

    static func expandedHeight(rows: Int) -> CGFloat {
        gridTop + gridHeight(rows) + legendGap + legendHeight + padding
    }

    /// Mesi disponibili: due anni prima e dopo il mese corrente.
    private static let months: [Date] = {
        let current = Date().startOfMonth
        return (-24...24).compactMap { CVDate.calendar.date(byAdding: .month, value: $0, to: current)?.startOfMonth }
    }()

    private static let monthSet = Set(months)

    init(selectedDay: Binding<Date>, progress: CGFloat, onExpandedHeight: @escaping (CGFloat) -> Void) {
        _selectedDay = selectedDay
        self.progress = progress
        self.onExpandedHeight = onExpandedHeight
        let month = Self.month(containing: selectedDay.wrappedValue)
        _visibleMonth = State(initialValue: month)
        _rowCount = State(initialValue: Self.rows(of: month).count)
    }

    private static func month(containing day: Date) -> Date {
        let start = day.startOfMonth
        return monthSet.contains(start) ? start : (months.first { $0.isSameDay(as: start) } ?? start)
    }

    /// Settimane del mese, da lunedì a domenica: il giorno e se appartiene al mese.
    static func rows(of month: Date) -> [[(day: Date, inMonth: Bool)]] {
        let first = month.startOfMonth
        let count = CVDate.calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let offset = (CVDate.calendar.component(.weekday, from: first) + 5) % 7
        let start = first.adding(days: -offset)
        let total = Int((Double(offset + count) / 7).rounded(.up)) * 7
        let cells = (0..<total).map { index -> (day: Date, inMonth: Bool) in
            (start.adding(days: index), index >= offset && index < offset + count)
        }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private var currentMonth: Date { visibleMonth ?? selectedDay.startOfMonth }

    var body: some View {
        let p = progress
        let fade = max(0, 1 - p * 1.8)
        let expanded = Self.expandedHeight(rows: rowCount)
        // La settimana del giorno scelto (nel mese mostrato) arriva al centro della striscia.
        let selectedRow = Self.rows(of: currentMonth).firstIndex { row in
            row.contains { $0.inMonth && $0.day.isSameDay(as: selectedDay) }
        } ?? 0
        let rowCenter = Self.gridTop + CGFloat(selectedRow) * (Self.cellHeight + Self.rowSpacing) + Self.cellHeight / 2
        let shift = p * (CalendarHeader.collapsedHeight / 2 - rowCenter)
        let gridHeight = Self.gridHeight(rowCount)

        ZStack(alignment: .top) {
            MonthTitleRow(title: currentMonth.monthYear, back: { shiftMonth(-1) }, forward: { shiftMonth(1) })
                .frame(height: Self.titleHeight)
                .padding(.horizontal, Self.padding)
                .offset(y: Self.padding + shift)
                .opacity(fade)
                .allowsHitTesting(p == 0)

            HStack(spacing: 2) {
                ForEach(Self.weekdaySymbols.indices, id: \.self) { index in
                    Text(Self.weekdaySymbols[index])
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.secondaryInk)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: Self.weekdayHeight)
            .padding(.horizontal, lerp(Self.padding, 8, p))
            .offset(y: Self.padding + Self.titleHeight + Self.titleGap + shift)
            .opacity(fade)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(Self.months, id: \.self) { month in
                        grid(month, progress: p, shift: shift)
                            .padding(.horizontal, lerp(Self.padding, 8, p))
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleMonth)
            .scrollIndicators(.hidden)
            // Le settimane salgono oltre la griglia: le taglia solo la card.
            .scrollClipDisabled()
            .scrollDisabled(p > 0)
            .frame(height: gridHeight, alignment: .top)
            .offset(y: Self.gridTop)
            // Da ridotta la griglia resta (invisibile) sotto la striscia: non deve prendere i tocchi
            // destinati al contenuto.
            .allowsHitTesting(p == 0)

            legend
                .frame(height: Self.legendHeight)
                .padding(.horizontal, Self.padding)
                .offset(y: Self.gridTop + gridHeight + Self.legendGap + shift)
                .opacity(fade)
        }
        .frame(height: lerp(expanded, CalendarHeader.collapsedHeight, p), alignment: .top)
        .onAppear { onExpandedHeight(expanded) }
        .onChange(of: expanded) { _, height in
            withAnimation(.snappy) { onExpandedHeight(height) }
        }
        .onChange(of: visibleMonth) { _, month in
            let count = Self.rows(of: month ?? currentMonth).count
            if count != rowCount { withAnimation(.snappy) { rowCount = count } }
        }
        .onChange(of: selectedDay) { _, day in
            let month = Self.month(containing: day)
            if !currentMonth.isSameDay(as: month) {
                withAnimation(.snappy) { visibleMonth = month }
            }
        }
        .onChange(of: p > 0) { _, collapsing in
            // Si riduce sempre alla settimana del giorno scelto: se si stava guardando un altro mese
            // si torna al suo.
            let month = Self.month(containing: selectedDay)
            guard collapsing, !currentMonth.isSameDay(as: month) else { return }
            visibleMonth = month
            rowCount = Self.rows(of: month).count
        }
    }

    private func grid(_ month: Date, progress p: CGFloat, shift: CGFloat) -> some View {
        let rows = Self.rows(of: month)
        let isSelectedMonth = month.isSameDay(as: selectedDay.startOfMonth)
        return ZStack(alignment: .top) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                let inSelectedWeek = isSelectedMonth && row.contains { $0.inMonth && $0.day.isSameDay(as: selectedDay) }
                HStack(spacing: 2) {
                    ForEach(row.indices, id: \.self) { column in
                        MonthMorphCell(day: row[column].day, inMonth: row[column].inMonth,
                                       isSelected: row[column].inMonth && row[column].day.isSameDay(as: selectedDay),
                                       inSelectedWeek: inSelectedWeek, progress: p) {
                            withAnimation(.snappy) { selectedDay = row[column].day }
                        }
                    }
                }
                .offset(y: CGFloat(index) * (Self.cellHeight + Self.rowSpacing) + shift)
                // Le altre settimane svaniscono salendo.
                .opacity(inSelectedWeek ? 1 : max(0, 1 - p * 1.8))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(p == 0)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(Theme.neutral, "Compiti")
            legendItem(Theme.accent, "Verifiche")
            legendItem(Theme.fair, "Eventi")
            legendItem(Theme.poor, "Assenze")
        }
        .font(.caption2)
        .foregroundStyle(Theme.secondaryInk)
    }

    private func legendItem(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
        }
    }

    private func shiftMonth(_ months: Int) {
        guard let target = CVDate.calendar.date(byAdding: .month, value: months, to: currentMonth) else { return }
        withAnimation(.snappy) { visibleMonth = Self.month(containing: target) }
    }
}

/// Un giorno del mese che si trasforma con la card: da intera il numero con i pallini (in un
/// cerchio se scelto), da ridotta come nella striscia della settimana. I giorni dei mesi accanto
/// compaiono solo nella settimana del giorno scelto, mentre la card si riduce.
private struct MonthMorphCell: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let inMonth: Bool
    let isSelected: Bool
    let inSelectedWeek: Bool
    let progress: CGFloat
    let action: () -> Void

    private static let circle: CGFloat = 42

    var body: some View {
        let p = progress
        let holiday = model.calendarStatus(on: day)?.isHoliday == true
        let diameter = lerp(Self.circle, MorphingDayCell.circle, p)
        // Fuori dal mese: invisibile da intera, compare con la riduzione (solo nella settimana scelta).
        let visibility: CGFloat = inMonth ? 1 : (inSelectedWeek ? p : 0)

        Button(action: action) {
            ZStack {
                Text(day.it("d"))
                    .font(.numeral(16, weight: day.isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(DayDots.numberColor(day: day, isSelected: isSelected, holiday: holiday))
                    // Da ridotta come i numeri della settimana (19 punti ridotti al 90%).
                    .scaleEffect(lerp(1, 17.1 / 16, p))
                    .offset(y: lerp(-4, 0, p))
                DayDots(day: day, isSelected: isSelected, size: 4)
                    .offset(y: lerp(12, 8, p))
                    .opacity(max(0, 1 - p * 1.8))
            }
            .frame(maxWidth: .infinity)
            .frame(height: MonthMorph.cellHeight)
            // Si può toccare tutto il cerchio del giorno, non solo il numero.
            .contentShape(CenteredCircle(diameter: Self.circle))
            .background {
                if isSelected {
                    Circle().fill(Theme.accent.gradient).frame(width: diameter, height: diameter)
                } else if day.isToday && inMonth {
                    Circle().strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1)
                        .frame(width: diameter, height: diameter)
                        .opacity(p)
                } else if holiday && inMonth {
                    Circle().fill(Theme.separator.opacity(0.45)).frame(width: diameter, height: diameter)
                        .opacity(1 - p)
                }
            }
            .opacity(visibility)
        }
        .buttonStyle(.plain)
        .disabled(!inMonth)
        .accessibilityHidden(!inMonth)
        .accessibilityLabel(day.longDay)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
