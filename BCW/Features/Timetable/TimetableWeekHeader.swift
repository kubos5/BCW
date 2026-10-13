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

/// La settimana dell'orario su iPhone: una card che galleggia sopra gli eventi. Scorrendo si
/// riduce a una striscia con i soli numeri dei giorni (`FloatingHeaderCollapse`); toccandola
/// torna intera. Il passaggio è animato elemento per elemento (`progress` va da 0, intera, a 1,
/// ridotta): i numeri salgono al centro della striscia, il rettangolo del giorno scelto diventa
/// un cerchio intorno al suo numero, la riga del mese, le iniziali dei giorni e i pallini
/// scompaiono salendo, e la card diventa una capsula.
struct TimetableWeekHeader: View, Animatable {
    @Environment(AppModel.self) private var model
    @Binding var selectedDay: Date
    var progress: CGFloat
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

    init(selectedDay: Binding<Date>, isCollapsed: Bool, onExpand: @escaping () -> Void) {
        _selectedDay = selectedDay
        progress = isCollapsed ? 1 : 0
        self.isCollapsed = isCollapsed
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
            selectedDay = week.adding(days: weekday)
        }
        .onChange(of: selectedDay) { _, day in
            let week = Self.week(containing: day)
            if visibleWeek.map({ !$0.isSameDay(as: week) }) ?? true {
                withAnimation(.snappy) { visibleWeek = week }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedDay)
        .sensoryFeedback(.impact(weight: .light), trigger: isCollapsed)
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
