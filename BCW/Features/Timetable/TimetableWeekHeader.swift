import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Riduce un'intestazione mobile insieme alla barra delle schede di iOS
/// (`tabBarMinimizeBehavior(.onScrollDown)`). Su iPhone segue lo stato vero della barra
/// (`TabBarMinimizedState`): si riduce quando si riduce lei e torna intera quando torna intera lei.
/// Se la barra è ridotta e l'intestazione è stata riaperta toccandola, scorrendo ancora verso il
/// basso si riduce di nuovo. Se lo stato della barra non si può leggere vale una regola che la imita
/// (misurata sul simulatore, ma la barra tiene conto anche della velocità dei gesti):
/// - scorrendo verso il basso si riduce, ma non subito: dopo un tratto e lontano dalla cima;
/// - scorrendo verso l'alto resta ridotta, come la barra delle schede (verificato: non si
///   riespande nemmeno dopo centinaia di punti o con un colpo veloce);
/// - in cima alla pagina è sempre intera;
/// - in fondo alla pagina, se si prova a scorrere oltre (con il dito), torna intera.
/// Contano solo gli scorrimenti dell'utente: quelli fatti dall'app (es. la vista Giorno che va alla
/// prima lezione) non la riducono. Lo stato è in `isCollapsed`, che cambia con un'animazione.
struct FloatingHeaderCollapse: ViewModifier {
    var isCollapsed: Binding<Bool>?
    @State private var tracker = UnobservedValue(Tracker())
    #if os(iOS)
    @State private var tabBar = TabBarMinimizedState()
    #endif

    struct Tracker {
        var lastOffset: CGFloat = 0
        var down: CGFloat = 0
        var phase: ScrollPhase = .idle
        /// Ultimo stato letto dalla barra delle schede.
        var tabBarMinimized: Bool?
        /// La barra sta passando da uno stato all'altro.
        var tabBarChanging = false
    }

    struct Metrics: Equatable {
        var offset: CGFloat
        var maxOffset: CGFloat
    }

    /// Tratto da scorrere verso il basso prima di ridurre e distanza minima dalla cima. Misurata
    /// sulla barra delle schede: dalla cima non si riduce entro 120 punti, si riduce a 150, anche
    /// con più trascinamenti brevi (conta la posizione, non il singolo gesto).
    static let collapseDistance: CGFloat = 30
    static let minimumOffset: CGFloat = 140
    /// Quanto tirare oltre il fondo per tornare intera.
    static let bottomPull: CGFloat = 16

    static let animation = Animation.smooth(duration: 0.42)

    func body(content: Content) -> some View {
        if let isCollapsed {
            content
                .onScrollPhaseChange { _, phase in
                    tracker.value.phase = phase
                    if !phase.isScrolling {
                        tracker.value.down = 0
                        // La barra può cambiare stato alla fine del rimbalzo: si ricontrolla.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            syncWithTabBar(isCollapsed: isCollapsed)
                        }
                    }
                }
                .onScrollGeometryChange(for: Metrics.self) { geometry in
                    let offset = geometry.contentOffset.y + geometry.contentInsets.top
                    // `containerSize` è già la parte visibile, senza i margini (verificato).
                    return Metrics(offset: offset, maxOffset: max(0, geometry.contentSize.height - geometry.containerSize.height))
                } action: { _, metrics in
                    update(metrics, isCollapsed: isCollapsed)
                }
                #if os(iOS)
                .background { TabBarFinder(state: tabBar) }
                #endif
        } else {
            content
        }
    }

    /// Segue i cambi di stato della barra delle schede. Restituisce `false` se lo stato non si
    /// può leggere (si usa allora la regola di riserva).
    @discardableResult
    private func syncWithTabBar(isCollapsed: Binding<Bool>) -> Bool {
        #if os(iOS)
        guard let state = tabBar.state else { return false }
        let previous = tracker.value.tabBarMinimized
        // Appena la barra comincia a cambiare la settimana parte con lei, verso lo stato opposto;
        // lo stato finale, letto dopo, corregge un eventuale passaggio interrotto.
        let minimized: Bool
        switch state {
        case .changing:
            guard let previous, !tracker.value.tabBarChanging else { return true }
            tracker.value.tabBarChanging = true
            minimized = !previous
        case .minimized:
            tracker.value.tabBarChanging = false
            minimized = true
        case .expanded:
            tracker.value.tabBarChanging = false
            minimized = false
        }
        tracker.value.tabBarMinimized = minimized
        if let previous, previous != minimized, isCollapsed.wrappedValue != minimized {
            withAnimation(Self.animation) { isCollapsed.wrappedValue = minimized }
        }
        return true
        #else
        return false
        #endif
    }

    private func update(_ metrics: Metrics, isCollapsed: Binding<Bool>) {
        if syncWithTabBar(isCollapsed: isCollapsed) {
            var state = tracker.value
            defer { tracker.value = state }
            let delta = metrics.offset - state.lastOffset
            state.lastOffset = metrics.offset
            let byUser = state.phase == .tracking || state.phase == .interacting || state.phase == .decelerating
            // Riaperta toccandola mentre la barra resta ridotta: scorrendo verso il basso si riduce
            // di nuovo, insieme alla barra.
            if state.tabBarMinimized == true, !isCollapsed.wrappedValue, byUser, delta > 0 {
                state.down += delta
                if state.down >= Self.collapseDistance {
                    state.down = 0
                    withAnimation(Self.animation) { isCollapsed.wrappedValue = true }
                }
            } else if delta < 0 {
                state.down = 0
            }
            return
        }
        var state = tracker.value
        defer { tracker.value = state }
        let delta = metrics.offset - state.lastOffset
        state.lastOffset = metrics.offset
        let byUser = state.phase == .tracking || state.phase == .interacting || state.phase == .decelerating
        let dragging = state.phase == .tracking || state.phase == .interacting

        func set(_ collapsed: Bool) {
            state.down = 0
            guard isCollapsed.wrappedValue != collapsed else { return }
            withAnimation(Self.animation) { isCollapsed.wrappedValue = collapsed }
        }

        if metrics.offset <= 4 { set(false); return }
        if dragging, metrics.maxOffset > 0, metrics.offset > metrics.maxOffset + Self.bottomPull { set(false); return }
        guard byUser else { return }
        if delta > 0 {
            state.down += delta
            if state.down >= Self.collapseDistance, metrics.offset >= Self.minimumOffset,
               metrics.offset <= metrics.maxOffset {
                set(true)
            }
        } else if delta < 0 {
            state.down = 0
        }
    }
}

#if os(iOS)
/// Stato della barra delle schede (ridotta o intera). UIKit non lo rende pubblico, e la proprietà
/// interna `_isMinimized` è riservata alle app di Apple (chiamarla fa chiudere l'app con "This can
/// only be called by an approved app", verificato). Si guarda invece com'è fatta la barra: contiene
/// due "piatti" (`_UITabBarPlatterView`), quello intero e quello ridotto, e ne è visibile uno solo;
/// quello ridotto è il più stretto (verificato su iOS 26.3 e 27). Si leggono solo proprietà pubbliche
/// (`isHidden`, `bounds`). Durante il passaggio sono visibili entrambi (`.changing`); se la struttura
/// non è questa (`nil`) vale la regola di riserva di `FloatingHeaderCollapse`.
@MainActor
final class TabBarMinimizedState {
    enum State { case expanded, minimized, changing }

    weak var tabBar: UITabBar?

    var state: State? {
        guard let tabBar else { return nil }
        let platters = tabBar.subviews.filter { String(describing: type(of: $0)).contains("PlatterView") }
        guard platters.count == 2 else { return nil }
        let visible = platters.filter { !$0.isHidden }
        guard visible.count == 1, let shown = visible.first,
              let hidden = platters.first(where: { $0 !== shown }) else { return .changing }
        guard shown.bounds.width > 0, hidden.bounds.width > 0, shown.bounds.width != hidden.bounds.width else {
            return nil
        }
        return shown.bounds.width < hidden.bounds.width ? .minimized : .expanded
    }
}

/// Trova la barra delle schede della finestra (come `TabBarItemLongPress`).
private struct TabBarFinder: UIViewRepresentable {
    let state: TabBarMinimizedState

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            guard state.tabBar == nil, let window = view.window else { return }
            state.tabBar = Self.tabBar(in: window)
        }
    }

    private static func tabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for subview in view.subviews {
            if let bar = tabBar(in: subview) { return bar }
        }
        return nil
    }
}

/// Settimana della vista Lista su iPhone. La settimana non fa parte dello scorrimento: sta sopra
/// l'area degli eventi, che si sposta insieme a lei quando si riduce o si apre
/// (`WeekHeaderScroll.Shift`). Il passaggio non usa lo scorrimento di iOS ma un gesto proprio
/// (`WeekHeaderPan`) che segue il dito e, lasciandolo, finisce con una molla nella posizione più
/// vicina (tenendo conto della velocità), mai a metà:
/// - con la settimana intera gli eventi non scorrono: trascinando verso l'alto la settimana si
///   riduce e l'area sale con lei, al massimo fino a ridotta in un gesto; verso il basso c'è un
///   po' di elastico;
/// - con la settimana ridotta gli eventi scorrono normalmente (e rimbalzano in cima, con la
///   settimana che resta ridotta); un nuovo gesto verso il basso, partendo dalla cima, la riapre.
/// Toccata da ridotta la settimana si riapre. L'avanzamento si legge solo nella settimana e nello
/// spostamento dell'area: il resto della pagina non si ricalcola a ogni fotogramma.
@Observable
final class WeekHeaderScroll: NSObject {
    static let range = TimetableWeekHeader.expandedHeight - TimetableWeekHeader.collapsedHeight

    /// 0 intera, 1 ridotta; trascinando oltre l'intera scende un poco sotto lo 0 (elastico).
    fileprivate(set) var progress: CGFloat = 0
    /// Ridotta: solo allora gli eventi scorrono. Cambia solo nei passaggi.
    fileprivate(set) var isCollapsed = false

    /// Punto di resistenza, a metà del tratto percorso dal dito. Prima il contenuto resta sempre
    /// più indietro rispetto al dito; superato il punto lo raggiunge (con una breve animazione e
    /// una vibrazione) e da lì è tirato verso l'altra posizione, davanti al dito. Lasciando il
    /// dito conta da che parte del punto si è (e la velocità).
    static let threshold: CGFloat = 0.5
    /// Asintoto della curva di resistenza: quanto al massimo il contenuto si muove prima del punto.
    private static let lag: CGFloat = 0.35
    /// Durata (costante di tempo) della rincorsa al passaggio del punto.
    private static let catchUpTime: CGFloat = 0.06

    /// Posizione del dito in avanzamento (0 intera, 1 ridotta), senza resistenza.
    @ObservationIgnored private var finger: CGFloat = 0
    @ObservationIgnored private var fingerStart: CGFloat = 0
    /// Scarto tra il contenuto e la curva, che si riassorbe in fretta (rincorsa dopo il punto).
    @ObservationIgnored private var catchUp: CGFloat = 0
    @ObservationIgnored private var isDragging = false
    @ObservationIgnored private let haptics = UIImpactFeedbackGenerator(style: .medium)
    /// Molla calcolata a ogni fotogramma (non un'animazione di SwiftUI): `progress` è sempre il
    /// valore visibile, così un gesto può riprendere la settimana a metà di uno scatto.
    @ObservationIgnored private var spring: (target: CGFloat, velocity: CGFloat)?
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval = 0

    /// Riapre la settimana ridotta (tocco sulla striscia, nuovo tocco sulla scheda).
    func open() {
        if progress > 0.5 { haptics.impactOccurred() }
        settle(collapsed: false)
    }

    /// Settimana intera senza animazione (cambio di vista: lo scorrimento riparte dalla cima).
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

    // MARK: Gesto

    fileprivate func began() {
        stopLink()
        isDragging = true
        finger = Self.finger(for: progress)
        fingerStart = finger
        // Riprendendo a metà di uno scatto il contenuto resta dov'è e poi raggiunge la curva.
        catchUp = progress - Self.resisted(finger)
        haptics.prepare()
        if catchUp != 0 { startLink() }
    }

    /// `translation`: spostamento del dito verso l'alto, in punti, dall'inizio del gesto.
    fileprivate func changed(_ translation: CGFloat) {
        let previous = finger
        finger = fingerStart + translation / Self.range
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
        let speed = velocity / Self.range
        // Dove arriverebbe il dito in un decimo di secondo, rispetto al punto di resistenza.
        let heading = finger + speed * 0.1
        settle(collapsed: heading >= Self.threshold, velocity: speed * Self.slope(finger))
    }

    // MARK: Molla

    /// Porta la settimana intera o ridotta con una molla che parte dalla velocità del contenuto
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
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        lastTimestamp = 0
        link.add(to: .main, forMode: .common)
        displayLink = link
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
            // Niente rimbalzo oltre la posizione finale (con un colpo veloce gli eventi salirebbero
            // oltre la settimana ridotta e tornerebbero giù): ci si ferma lì.
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

    /// Sposta l'area degli eventi con la settimana e abilita lo scorrimento solo da ridotta.
    struct Shift: ViewModifier {
        let state: WeekHeaderScroll

        func body(content: Content) -> some View {
            content
                .offset(y: (1 - state.progress) * WeekHeaderScroll.range)
                .scrollDisabled(!state.isCollapsed)
        }
    }
}

/// Il gesto che riduce e apre la settimana, aggiunto allo `UIScrollView` degli eventi (va nello
/// sfondo del contenuto dello scorrimento, per trovarlo). Parte solo per trascinamenti verticali:
/// sempre con la settimana intera (lo scorrimento è spento), da ridotta solo verso il basso e con
/// gli eventi in cima. Quando parte, lo scorrimento aspetta che fallisca e quindi non si muove;
/// le misure sono nella finestra, così lo spostamento dell'area non le altera.
struct WeekHeaderPan: UIViewRepresentable {
    let state: WeekHeaderScroll

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let state: WeekHeaderScroll
        weak var scrollView: UIScrollView?
        let recognizer = UIPanGestureRecognizer()

        init(state: WeekHeaderScroll) {
            self.state = state
            super.init()
            recognizer.addTarget(self, action: #selector(pan(_:)))
            recognizer.delegate = self
        }

        func attach(to scrollView: UIScrollView) {
            guard self.scrollView !== scrollView else { return }
            self.scrollView?.removeGestureRecognizer(recognizer)
            self.scrollView = scrollView
            scrollView.addGestureRecognizer(recognizer)
        }

        @objc private func pan(_ recognizer: UIPanGestureRecognizer) {
            let window = recognizer.view?.window
            switch recognizer.state {
            case .began:
                state.began()
            case .changed:
                state.changed(-recognizer.translation(in: window).y)
            case .ended, .cancelled, .failed:
                state.ended(velocity: recognizer.state == .ended ? -recognizer.velocity(in: window).y : 0)
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let scrollView else { return false }
            let velocity = recognizer.velocity(in: scrollView.window)
            guard abs(velocity.y) > abs(velocity.x) else { return false }
            if !state.isCollapsed { return true }
            let atTop = scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top + 0.5
            return atTop && velocity.y > 0
        }

        /// Lo scorrimento parte solo se questo gesto non parte.
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
        DispatchQueue.main.async {
            var current = view.superview
            while let candidate = current, !(candidate is UIScrollView) { current = candidate.superview }
            if let scrollView = current as? UIScrollView { coordinator.attach(to: scrollView) }
        }
    }

    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.scrollView?.removeGestureRecognizer(coordinator.recognizer)
    }
}

/// La settimana dell'orario su iPhone: una card che galleggia sopra gli eventi. Scorrendo si
/// riduce a una striscia con i soli numeri dei giorni (nella vista Lista seguendo lo scorrimento,
/// `WeekHeaderScroll`; nella vista Giorno insieme alla barra delle schede, `FloatingHeaderCollapse`);
/// toccandola torna intera. Il passaggio è animato elemento per elemento (`progress` va da 0, intera, a 1,
/// ridotta): i numeri salgono al centro della striscia, il rettangolo del giorno scelto diventa
/// un cerchio intorno al suo numero, la riga del mese, le iniziali dei giorni e i pallini
/// scompaiono salendo, e la card diventa una capsula.
struct TimetableWeekHeader: View, Animatable {
    @Environment(AppModel.self) private var model
    @Binding var selectedDay: Date
    var progress: CGFloat
    /// Avanzamento richiesto (`progress` cambia durante le animazioni).
    let target: CGFloat
    let isCollapsed: Bool
    let onExpand: () -> Void
    /// Settimana mostrata (inizio settimana): segue lo scorrimento orizzontale a pagine.
    @State private var visibleWeek: Date?

    static let expandedHeight: CGFloat = 144
    static let collapsedHeight: CGFloat = 46
    private static let monthRowHeight: CGFloat = 40
    private static let expandedCellHeight: CGFloat = 76
    private static let verticalPadding: CGFloat = 14

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// Posizione di riposo per il feedback aptico: vibra arrivando intera o ridotta.
    private enum Detent { case expanded, between, collapsed }

    /// Vibra arrivando intera o ridotta (nella vista Lista vibra invece il gesto, al punto di
    /// resistenza: `WeekHeaderScroll`).
    var arrivalFeedback = true

    init(selectedDay: Binding<Date>, progress: CGFloat, arrivalFeedback: Bool = true, onExpand: @escaping () -> Void) {
        self.arrivalFeedback = arrivalFeedback
        _selectedDay = selectedDay
        self.progress = progress
        target = progress
        isCollapsed = progress >= 1
        self.onExpand = onExpand
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
        // Le molle con rimbalzo supererebbero l'intervallo: si limita come in `CollapseBody`.
        let p = min(max(progress, 0), 1)
        let fade = max(0, 1 - p * 1.8)
        let shape = RoundedRectangle(cornerRadius: lerp(Theme.corner, Self.collapsedHeight / 2, p), style: .continuous)

        VStack(spacing: 0) {
            monthRow
                .frame(height: Self.monthRowHeight - 12)
                .padding(.bottom, 12)
                .padding(.horizontal, 14)
                // La riga si accorcia dall'alto: il contenuto sale ed esce dalla card.
                .frame(height: lerp(Self.monthRowHeight, 0, p), alignment: .bottom)
                .clipped()
                .opacity(fade)
                .allowsHitTesting(!isCollapsed)
            pager(progress: p)
                .frame(height: lerp(Self.expandedCellHeight, Self.collapsedHeight, p))
        }
        .padding(.vertical, lerp(Self.verticalPadding, 0, p))
        .frame(maxWidth: .infinity)
        .frame(height: lerp(Self.expandedHeight, Self.collapsedHeight, p), alignment: .top)
        .clipShape(shape)
        .glassEffect(.regular, in: shape)
        .overlay {
            if isCollapsed {
                // Ridotta, la striscia si tocca solo per riaprirla.
                Color.clear
                    .contentShape(shape)
                    .onTapGesture(perform: onExpand)
                    .accessibilityElement()
                    .accessibilityLabel("Settimana, \(selectedDay.longDay)")
                    .accessibilityHint("Mostra la settimana intera")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .onChange(of: visibleWeek) { _, week in
            // Scorrendo si passa alla settimana accanto mantenendo lo stesso giorno della settimana.
            guard let week, !week.isSameDay(as: selectedDay.startOfWeek) else { return }
            let weekday = CVDate.calendar.dateComponents([.day], from: selectedDay.startOfWeek, to: selectedDay.startOfDay).day ?? 0
            // Con l'animazione, come toccando un giorno: anche "Oggi" nella barra compare animato.
            withAnimation(.snappy) { selectedDay = week.adding(days: weekday) }
        }
        .onChange(of: selectedDay) { _, day in
            let week = Self.week(containing: day)
            if visibleWeek.map({ !$0.isSameDay(as: week) }) ?? true {
                withAnimation(.snappy) { visibleWeek = week }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
        .sensoryFeedback(.impact(weight: .light), trigger: detent) { _, new in arrivalFeedback && new != .between }
    }

    private var detent: Detent {
        isCollapsed ? .collapsed : (target <= 0 ? .expanded : .between)
    }

    private var monthRow: some View {
        HStack {
            Text(selectedDay.monthYear)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .contentTransition(.numericText())
            Spacer()
            HStack(spacing: 4) {
                Button { shift(-7) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Settimana precedente")
                Button { shift(7) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Settimana successiva")
            }
            .glassButton()
            .buttonBorderShape(.circle)
            .controlSize(.small)
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
        .scrollDisabled(isCollapsed)
        .allowsHitTesting(!isCollapsed)
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

    private static let circle: CGFloat = 34

    var body: some View {
        let p = progress
        let fade = max(0, 1 - p * 1.8)
        let events = model.events(on: day)
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
                    .foregroundStyle(numberColor(holiday: holiday))
                    .scaleEffect(lerp(1, 0.9, p))
                    .offset(y: lerp(3, 0, p))
                HStack(spacing: 3) {
                    if events.contains(where: { $0.kind == .homework }) { dot(Theme.neutral) }
                    if events.contains(where: { $0.kind == .test }) { dot(isSelected ? .white : Theme.accent) }
                    if events.contains(where: { $0.kind == .event }) { dot(Theme.fair) }
                    if !model.absences(on: day).isEmpty { dot(Theme.poor) }
                }
                .frame(height: 5)
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

    private func numberColor(holiday: Bool) -> Color {
        if isSelected { return .white }
        if day.isToday { return Theme.accent }
        if day.isWeekend || holiday { return Theme.secondaryInk }
        return Theme.ink
    }

    private func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 5, height: 5)
    }
}
#endif

/// Valore intermedio tra `a` (con `t` = 0) e `b` (con `t` = 1).
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}
