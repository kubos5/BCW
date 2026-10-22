import SwiftUI

// MARK: - Stato dello scorrimento della pagina

/// Scorrimento della pagina aperta: la barra superiore cambia sfondo quando il contenuto
/// scorre sotto di lei e mostra il titolo piccolo quando quello grande è uscito.
@Observable
final class PageScrollState {
    var scrolled = false
    var titleShown = false

    func update(offset: CGFloat) {
        let scrolled = offset > 1
        let titleShown = offset > 44
        if scrolled != self.scrolled { withAnimation(Motion.effects) { self.scrolled = scrolled } }
        if titleShown != self.titleShown { withAnimation(Motion.spatial) { self.titleShown = titleShown } }
    }
}

extension EnvironmentValues {
    @Entry var pageScroll: PageScrollState?
    /// Titolo grande della pagina (solo senza Liquid Glass: con Liquid Glass è il sistema a mostrarlo).
    @Entry var pageLargeTitle: String?
    /// Incrementato toccando di nuovo la scheda aperta (barra di Material 3).
    @Entry var tabReselection = 0
    /// Altezza della barra di navigazione di Material 3 in basso, che le pagine lasciano libera.
    @Entry var bottomBarInset: CGFloat = 0
    /// Pagina principale di una pila di navigazione (senza freccia indietro). Le pagine aperte da
    /// un'altra non lo ereditano: prendono l'ambiente della pila, non quello della pagina principale.
    @Entry var isRootPage = false
}

extension View {
    /// Segue lo scorrimento per la barra superiore della pagina (da mettere sullo `ScrollView`).
    func tracksPageScroll() -> some View {
        modifier(PageScrollTracker())
    }
}

private struct PageScrollTracker: ViewModifier {
    @Environment(\.pageScroll) private var state

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                state?.update(offset: offset)
            }
    }
}

/// Titolo grande in cima al contenuto della pagina (come le barre "flessibili" di M3
/// Expressive): scorrendo esce e compare quello piccolo nella barra.
struct PageLargeTitle: View {
    @Environment(\.pageLargeTitle) private var title

    var body: some View {
        if let title {
            Text(title)
                .font(.m3(36, weight: 500, rounded: true))
                .tracking(-0.2)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 4)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

// MARK: - Barra superiore

enum PageTitleStyle {
    /// Titolo grande nel contenuto, piccolo nella barra scorrendo.
    case large
    /// Titolo sempre nella barra (pagine aperte da un'altra, Dashboard e Orario).
    case inline
}

extension View {
    /// Titolo e pulsanti della pagina. Con Liquid Glass sono la barra di navigazione di
    /// sistema; altrimenti la barra superiore di Material 3 (piccola, 64 punti, con il titolo
    /// grande nel contenuto e lo sfondo che cambia scorrendo).
    func pageChrome<Actions: View>(_ title: String, subtitle: String? = nil, style: PageTitleStyle = .large,
                                   showsBack: Bool? = nil,
                                   @ViewBuilder actions: @escaping () -> Actions) -> some View {
        modifier(PageChrome(title: title, subtitle: subtitle, style: style, showsBack: showsBack, actions: actions))
    }

    func pageChrome(_ title: String, subtitle: String? = nil, style: PageTitleStyle = .large,
                    showsBack: Bool? = nil) -> some View {
        modifier(PageChrome(title: title, subtitle: subtitle, style: style, showsBack: showsBack, actions: { EmptyView() }))
    }
}

private struct PageChrome<Actions: View>: ViewModifier {
    let title: String
    let subtitle: String?
    let style: PageTitleStyle
    let showsBack: Bool?
    @ViewBuilder let actions: () -> Actions

    @State private var scroll = PageScrollState()
    @Environment(\.isRootPage) private var isRootPage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.bottomBarInset) private var bottomBarInset
    @Environment(\.windowClass) private var windowClass

    func body(content: Content) -> some View {
        if ThemeStore.shared.liquidGlass {
            // Le pagine principali delle schede hanno il titolo grande nella riga dei pulsanti
            // (`.inlineLarge`): solo così toccando di nuovo la scheda il sistema torna in cima con il
            // titolo per intero. Le pagine aperte da un'altra hanno il titolo piccolo al centro.
            let pushed = showsBack ?? !isRootPage
            if windowClass == .regular && !pushed {
                // Sull'iPad largo, con la barra delle schede in alto, né il titolo grande nella riga
                // dei pulsanti né quello piccolo al centro compaiono (al centro c'è la barra delle
                // schede), e quello grande su una riga a parte restava compresso dopo aver acceso
                // Liquid Glass dalle Impostazioni (verificato). Il titolo grande è quindi fermo sotto
                // la barra, come quello della barra di Material sull'iPad largo.
                content
                    .navigationTitle(title)
                    .toolbarTitleDisplayMode(.inline)
                    .toolbar(removing: .title)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) { actions() }
                    }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        GlassPageTitle(title: title, subtitle: subtitle)
                    }
            } else {
                content
                    .navigationTitle(title)
                    .toolbarTitleDisplayMode(pushed ? .inline : .inlineLarge)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) { actions() }
                    }
            }
        } else {
            let back = showsBack ?? !isRootPage
            // Le pagine principali delle schede hanno il titolo grande nella riga dei pulsanti, come
            // con Liquid Glass (`.inlineLarge`); le altre il titolo grande nel contenuto (o piccolo).
            content
                .environment(\.pageScroll, scroll)
                .environment(\.pageLargeTitle, style == .large && back ? title : nil)
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: bottomBarInset)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    TopAppBar(title: title, subtitle: subtitle,
                              titleShown: style == .inline || !back || scroll.titleShown,
                              scrolled: scroll.scrolled,
                              large: !back,
                              back: back ? { dismiss() } : nil,
                              actions: actions)
                }
        }
    }
}

/// Titolo grande delle pagine principali con Liquid Glass sull'iPad largo: fermo sotto la barra di
/// sistema (con la barra delle schede in alto), sullo sfondo della pagina fino in cima, così il
/// contenuto che scorre non passa dietro il titolo.
private struct GlassPageTitle: View {
    let title: String
    let subtitle: String?
    @Environment(\.pageGutter) private var gutter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.m3(34, weight: 550, rounded: true))
                .tracking(-0.3)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtitle {
                Text(subtitle)
                    .font(.m3(12))
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, gutter)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .bottomLeading)
        .background(Theme.background.ignoresSafeArea(edges: .top))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Barra superiore di Material 3: pulsante indietro, titolo e pulsanti a icona.
struct TopAppBar<Actions: View>: View {
    let title: String
    var subtitle: String?
    var titleShown = true
    var scrolled = false
    /// Titolo grande (34 punti) nella riga dei pulsanti, per le pagine principali delle schede.
    var large = false
    var back: (() -> Void)?
    @ViewBuilder let actions: () -> Actions
    @Environment(\.pageGutter) private var gutter

    var body: some View {
        HStack(spacing: 4) {
            if let back {
                IconButton("arrowBack", label: "Indietro", action: back)
                    .keyboardShortcut("[", modifiers: .command)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.m3(large ? 34 : 22, weight: large ? 550 : 500, rounded: true))
                    .tracking(large ? -0.3 : 0)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.opacity)
                if let subtitle, titleShown {
                    Text(subtitle)
                        .font(.m3(12))
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            // Il titolo si allinea al contenuto (margine della pagina meno i 4 punti della barra).
            .padding(.leading, back == nil ? gutter - 4 : 4)
            .opacity(titleShown ? 1 : 0)
            .offset(y: titleShown ? 0 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            HStack(spacing: 4) {
                actions()
            }
            .buttonStyle(.m3Icon())
            .labelStyle(.iconOnly)
            .menuStyle(.button)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, 4)
        .frame(height: 64)
        .background {
            (scrolled ? Theme.surfaceContainer : Theme.surface)
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// Pulsante di una barra superiore con icona di Material Symbols.
struct BarButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    init(_ label: String, icon: String, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label { Text(label) } icon: { Icon(icon) }
        }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Pulsante con testo per le barre (tonale, o pieno se `prominent`).
struct BarTextButton: View {
    let title: String
    var icon: String?
    var prominent = false
    let action: () -> Void

    var body: some View {
        if ThemeStore.shared.liquidGlass {
            Button(action: action) {
                if let icon {
                    Label { Text(title) } icon: { Image.m(icon) }
                        .labelStyle(.titleAndIcon)
                } else {
                    Text(title)
                }
            }
        } else {
            Button(action: action) {
                if let icon {
                    Label { Text(title) } icon: { Icon(icon) }
                } else {
                    Text(title)
                }
            }
            .buttonStyle(.m3(prominent ? .filled : .tonal, size: .xs))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 4)
        }
    }
}

/// Menu di una barra superiore con l'icona "altro" o un'altra icona.
struct BarMenu<Content: View>: View {
    var icon: String = "more"
    var label: String = "Altro"
    @ViewBuilder let content: () -> Content

    var body: some View {
        AppMenu(content: content) {
            Label { Text(label) } icon: { ThemeStore.shared.liquidGlass ? AnyView(Image.m(icon)) : AnyView(Icon(icon)) }
        }
        .help(label)
        // Il pulsante mostra solo l'icona: senza, VoiceOver non lo nominava.
        .accessibilityLabel(label)
    }
}

// MARK: - Fogli

/// Pulsante della barra di un foglio.
struct SheetAction {
    enum Role { case cancel, close, confirm, destructive, plain }
    let title: String
    var icon: String?
    var role: Role = .plain
    var disabled = false
    let action: () -> Void

    static func close(_ action: @escaping () -> Void) -> SheetAction {
        SheetAction(title: "Chiudi", icon: "x", role: .close, action: action)
    }

    static func cancel(_ title: String = "Annulla", action: @escaping () -> Void) -> SheetAction {
        SheetAction(title: title, icon: "x", role: .cancel, action: action)
    }

    static func confirm(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> SheetAction {
        SheetAction(title: title, role: .confirm, disabled: disabled, action: action)
    }
}

extension View {
    /// Barra di un foglio: con Liquid Glass quella di sistema (dentro una `NavigationStack`),
    /// altrimenti quella di Material 3 (chiudi a sinistra, titolo al centro, azioni a destra).
    func sheetChrome(_ title: String, leading: SheetAction? = nil, trailing: [SheetAction] = []) -> some View {
        modifier(SheetChrome(title: title, leading: leading, trailing: trailing))
    }

    /// Aspetto dei fogli di Material 3: sfondo `surface-container-low`, angoli del sistema (in basso
    /// seguono quelli dello schermo). Sull'iPad il foglio è centrato, della misura indicata.
    func m3Sheet(size: M3SheetSize = .form) -> some View {
        modifier(M3SheetPresentation(size: size))
    }

    /// Misura di un foglio sull'iPad (sull'iPhone non cambia nulla: il foglio sale dal basso).
    func m3SheetSizing(_ size: M3SheetSize) -> some View {
        modifier(M3SheetSizing(size: size))
    }

    /// Rilevamenti di un foglio, solo sull'iPhone: sull'iPad il foglio è centrato con la sua misura
    /// (`m3Sheet(size:)`) e un rilevamento medio lo accorciava lasciandolo in basso.
    func m3Detents(_ detents: Set<PresentationDetent>) -> some View {
        modifier(M3Detents(detents: detents))
    }
}

/// Misura dei fogli sull'iPad.
enum M3SheetSize {
    /// Modulo centrato (editor, accesso, account).
    case form
    /// Quasi tutta la finestra (generatore dell'orario, verifiche nascoste, palette, pagine web).
    case page
}

private struct M3SheetSizing: ViewModifier {
    let size: M3SheetSize

    func body(content: Content) -> some View {
        if WindowClass.isPad {
            switch size {
            case .form: content.presentationSizing(.form)
            case .page: content.presentationSizing(.page)
            }
        } else {
            content
        }
    }
}

private struct M3Detents: ViewModifier {
    let detents: Set<PresentationDetent>

    func body(content: Content) -> some View {
        if WindowClass.isPad {
            content
        } else {
            content.presentationDetents(detents)
        }
    }
}

private struct SheetChrome: ViewModifier {
    let title: String
    let leading: SheetAction?
    let trailing: [SheetAction]

    func body(content: Content) -> some View {
        if ThemeStore.shared.liquidGlass {
            content
                .navigationTitle(title)
                .inlineTitleDisplay()
                .toolbar {
                    if let leading {
                        ToolbarItem(placement: .cancellationAction) {
                            button(leading)
                        }
                    }
                    ForEach(Array(trailing.enumerated()), id: \.offset) { _, action in
                        ToolbarItem(placement: action.role == .confirm ? .confirmationAction : .primaryAction) {
                            button(action)
                        }
                    }
                }
        } else {
            content
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    SheetBar(title: title, leading: leading, trailing: trailing)
                }
        }
    }

    @ViewBuilder private func button(_ action: SheetAction) -> some View {
        switch action.role {
        case .close:
            Button(role: .close, action: action.action)
        case .cancel:
            Button(role: .cancel, action: action.action) { Text(action.title) }
        case .confirm:
            Button(role: .confirm, action: action.action) { Text(action.title) }
                .disabled(action.disabled)
        case .destructive:
            Button(role: .destructive, action: action.action) {
                if let icon = action.icon { Label { Text(action.title) } icon: { Image.m(icon) } } else { Text(action.title) }
            }
            .disabled(action.disabled)
        case .plain:
            Button(action: action.action) {
                if let icon = action.icon { Label { Text(action.title) } icon: { Image.m(icon) } } else { Text(action.title) }
            }
            .disabled(action.disabled)
        }
    }
}

/// Barra di un foglio di Material 3.
struct SheetBar: View {
    let title: String
    var leading: SheetAction?
    var trailing: [SheetAction] = []

    var body: some View {
        ZStack {
            Text(title)
                .font(.m3(20, weight: 500, rounded: true))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 100)
            HStack(spacing: 8) {
                if let leading {
                    button(leading)
                }
                Spacer(minLength: 0)
                ForEach(Array(trailing.enumerated()), id: \.offset) { _, action in
                    button(action)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(minHeight: 64)
        .padding(.top, 10)
        .background(Theme.surfaceContainerLow)
    }

    @ViewBuilder private func button(_ action: SheetAction) -> some View {
        switch action.role {
        case .close, .cancel:
            if action.role == .cancel, action.icon == nil {
                Button(action.title, action: action.action)
                    .buttonStyle(.m3(.text, size: .xs))
                    .keyboardShortcut(.cancelAction)
            } else {
                IconButton(action.icon ?? "x", label: action.title, action: action.action)
                    .keyboardShortcut(.cancelAction)
            }
        case .confirm:
            Button(action.title, action: action.action)
                .buttonStyle(.m3(.filled, size: .xs))
                .disabled(action.disabled)
                .keyboardShortcut(.defaultAction)
        case .destructive:
            if let icon = action.icon {
                IconButton(icon, label: action.title, kind: .danger, action: action.action)
                    .disabled(action.disabled)
            } else {
                Button(action.title, action: action.action)
                    .buttonStyle(.m3(.dangerText, size: .xs))
                    .disabled(action.disabled)
            }
        case .plain:
            if let icon = action.icon {
                IconButton(icon, label: action.title, action: action.action)
                    .disabled(action.disabled)
            } else {
                Button(action.title, action: action.action)
                    .buttonStyle(.m3(.tonal, size: .xs))
                    .disabled(action.disabled)
            }
        }
    }
}

private struct M3SheetPresentation: ViewModifier {
    let size: M3SheetSize

    func body(content: Content) -> some View {
        content
            .background(Theme.surfaceContainerLow.ignoresSafeArea())
            .environment(\.bottomBarInset, 0)
            // Dentro un foglio si usa il layout del telefono, anche sull'iPad.
            .environment(\.windowClass, .compact)
            .environment(\.pageGutter, 16)
            .overlayHost()
            .presentationBackground(Theme.surfaceContainerLow)
            // Angoli del sistema: un raggio fisso varrebbe anche per quelli in basso, che così non
            // seguirebbero più la curva dello schermo.
            // Sull'iPad il foglio è centrato e non si trascina: niente maniglia.
            .presentationDragIndicator(WindowClass.isPad ? .hidden : .visible)
            .m3SheetSizing(size)
    }
}

// MARK: - Indietro con lo scorrimento

import UIKit

/// Senza la barra di navigazione di sistema (Material 3) UIKit disattiva i gesti per tornare
/// indietro: quello dal bordo sinistro e quello che parte da qualsiasi punto del contenuto
/// (iOS 26). Il primo si riattiva con il delegato; il secondo resta spento anche così, quindi
/// con la barra nascosta lo sostituisce un gesto uguale (`ContentPopGesture`) che guida la
/// stessa transizione interattiva di sistema.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
        ContentPopGesture.install(on: self)
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

/// Scorrimento verso destra da qualsiasi punto della pagina per tornare indietro, attivo solo
/// con la barra di navigazione nascosta (con Liquid Glass c'è già quello di sistema).
private final class ContentPopGesture: NSObject, UIGestureRecognizerDelegate {
    nonisolated(unsafe) private static var key: UInt8 = 0
    private weak var navigation: UINavigationController?

    private init(navigation: UINavigationController) {
        self.navigation = navigation
    }

    static func install(on navigation: UINavigationController) {
        // Il gesto di sistema ha come bersaglio l'oggetto che gestisce la transizione, che è
        // anche il suo delegato.
        guard let system = navigation.interactiveContentPopGestureRecognizer ?? navigation.interactivePopGestureRecognizer,
              let transition = system.delegate else { return }
        let action = NSSelectorFromString("handleNavigationTransition:")
        guard transition.responds(to: action) else { return }
        let handler = ContentPopGesture(navigation: navigation)
        objc_setAssociatedObject(navigation, &key, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        let pan = UIPanGestureRecognizer(target: transition, action: action)
        pan.name = "BCW.contentPop"
        pan.delegate = handler
        navigation.view.addGestureRecognizer(pan)
    }

    private var isActive: Bool {
        guard let navigation else { return false }
        return navigation.isNavigationBarHidden && navigation.viewControllers.count > 1
            && navigation.transitionCoordinator == nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        isActive
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isActive, let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
        let velocity = pan.velocity(in: pan.view)
        guard velocity.x > 0, abs(velocity.x) > abs(velocity.y) * 1.5 else { return false }
        // Precedenza agli scorrimenti orizzontali che possono ancora andare verso sinistra.
        let location = pan.location(in: pan.view)
        var view = pan.view?.hitTest(location, with: nil)
        while let current = view {
            if let scroll = current as? UIScrollView, scroll.isScrollEnabled,
               scroll.contentSize.width > scroll.bounds.width + 1,
               scroll.contentOffset.x > -scroll.adjustedContentInset.left + 1 {
                return false
            }
            view = current.superview
        }
        return true
    }

    /// Gli scorrimenti orizzontali aspettano che questo gesto rinunci (subito, se non può
    /// cominciare), così non partono entrambi.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        guard let scroll = other.view as? UIScrollView, other === scroll.panGestureRecognizer else { return false }
        return scroll.contentSize.width > scroll.bounds.width + 1
    }
}

// MARK: - Ritorno in cima

extension View {
    /// Senza Liquid Glass: toccando di nuovo la scheda aperta la pagina torna in cima (con Liquid
    /// Glass lo fa già il sistema). Da mettere sullo `ScrollView` principale della pagina.
    func scrollsToTopOnReselect() -> some View {
        modifier(ScrollToTopOnReselect())
    }
}

private struct ScrollToTopOnReselect: ViewModifier {
    @Environment(\.tabReselection) private var reselection
    @State private var position = ScrollPosition(edge: .top)

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onChange(of: reselection) {
                withAnimation(Motion.spatialSlow) { position.scrollTo(edge: .top) }
            }
    }
}

// MARK: - Ricerca nelle pagine

/// Ricerca dentro una singola pagina (Bacheca, Agenda, Materiale): con Liquid Glass è il campo di
/// sistema nella barra; altrimenti la pagina mostra la barra di ricerca di Material 3 nel contenuto.
/// Sull'iPad largo il campo sta sempre nel contenuto (in cima all'elenco, come la versione web).
struct GlassLocalSearch: ViewModifier {
    @Binding var text: String
    let prompt: String
    @Environment(\.windowClass) private var windowClass

    func body(content: Content) -> some View {
        if ThemeStore.shared.liquidGlass && windowClass == .compact {
            content.searchable(text: $text, prompt: prompt)
        } else {
            content
        }
    }
}

/// Barra di ricerca della pagina su iPhone senza Liquid Glass (con Liquid Glass è nella barra) e
/// sempre sull'iPad largo.
struct PageSearchBar: View {
    @Binding var text: String
    let prompt: String
    @Environment(\.windowClass) private var windowClass

    var body: some View {
        if !ThemeStore.shared.liquidGlass || windowClass == .regular {
            M3SearchBar(text: $text, prompt: prompt)
        }
    }
}
