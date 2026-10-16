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
    ///
    /// Su macOS con Liquid Glass la barra mette prima gli elementi dei modificatori più esterni:
    /// qui il titolo (e Aggiorna) sta dentro ai pulsanti della pagina, così Aggiorna resta l'ultimo.
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

    func body(content: Content) -> some View {
        if ThemeStore.shared.liquidGlass {
            #if os(macOS)
            content
                .screenTitle(title, subtitle: subtitle)
                .toolbar {
                    ToolbarItemGroup(placement: .trailingBar) { actions() }
                }
            #else
            // Le pagine principali delle schede hanno il titolo grande nella riga dei pulsanti
            // (`.inlineLarge`): solo così toccando di nuovo la scheda il sistema torna in cima con il
            // titolo per intero. Le pagine aperte da un'altra hanno il titolo piccolo al centro.
            let pushed = showsBack ?? !isRootPage
            content
                .navigationTitle(title)
                .toolbarTitleDisplayMode(pushed ? .inline : .inlineLarge)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) { actions() }
                }
            #endif
        } else {
            let back = showsBack ?? !isRootPage
            content
                .environment(\.pageScroll, scroll)
                .environment(\.pageLargeTitle, style == .large && !Platform.isMac ? title : nil)
                #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                #else
                .navigationTitle(title)
                #endif
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: bottomBarInset)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    TopAppBar(title: title, subtitle: subtitle,
                              titleShown: style == .inline || Platform.isMac || scroll.titleShown,
                              scrolled: scroll.scrolled,
                              back: back ? { dismiss() } : nil,
                              actions: actions)
                }
        }
    }
}

/// Barra superiore di Material 3: pulsante indietro, titolo e pulsanti a icona.
struct TopAppBar<Actions: View>: View {
    let title: String
    var subtitle: String?
    var titleShown = true
    var scrolled = false
    var back: (() -> Void)?
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 4) {
            if let back {
                IconButton("arrowBack", label: "Indietro", action: back)
                    .keyboardShortcut("[", modifiers: .command)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.m3(Platform.isMac ? 24 : 22, weight: 500, rounded: true))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .contentTransition(.opacity)
                if let subtitle, titleShown {
                    Text(subtitle)
                        .font(.m3(12))
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            .padding(.leading, back == nil ? (Platform.isMac ? 20 : 12) : 4)
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
            #if os(macOS)
            RefreshButton()
                .buttonStyle(.m3Icon())
            #endif
        }
        .padding(.leading, 4)
        .padding(.trailing, Platform.isMac ? MacChrome.searchReserve : 4)
        .frame(height: Platform.isMac ? 72 : 64)
        .padding(.top, Platform.isMac ? 8 : 0)
        .background {
            (scrolled ? (Platform.isMac ? Theme.surfaceContainerLow : Theme.surfaceContainer) : Theme.surface)
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// Misure della finestra del Mac senza Liquid Glass (spazio per la ricerca generale a destra).
enum MacChrome {
    static var searchReserve: CGFloat = 340
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

    /// Aspetto dei fogli di Material 3: sfondo `surface-container-low` e angoli extra large.
    func m3Sheet() -> some View {
        modifier(M3SheetPresentation())
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
                #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
                #endif
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
                .padding(.horizontal, 110)
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
        .padding(.top, Platform.isMac ? 4 : 10)
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
    func body(content: Content) -> some View {
        content
            .background(Theme.surfaceContainerLow.ignoresSafeArea())
            .environment(\.bottomBarInset, 0)
            .overlayHost()
            #if os(iOS)
            .presentationBackground(Theme.surfaceContainerLow)
            .presentationCornerRadius(ThemeStore.shared.liquidGlass ? nil : Theme.radii.xl)
            .presentationDragIndicator(.visible)
            #endif
    }
}

// MARK: - Indietro con lo scorrimento dal bordo

#if os(iOS)
import UIKit

/// Senza la barra di navigazione di sistema (Material 3) il gesto per tornare indietro dal bordo
/// sinistro resterebbe disattivato: lo si riattiva per tutte le pile di navigazione.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
#endif

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

/// Ricerca dentro una singola pagina (Bacheca, Agenda, Materiale): con Liquid Glass su iPhone è il
/// campo di sistema nella barra; altrimenti la pagina mostra la barra di ricerca di Material 3 nel
/// contenuto (su Mac `LocalSearchField`, perché nella barra c'è già la ricerca generale).
struct GlassLocalSearch: ViewModifier {
    @Binding var text: String
    let prompt: String

    func body(content: Content) -> some View {
        #if os(iOS)
        if ThemeStore.shared.liquidGlass {
            content.searchable(text: $text, prompt: prompt)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// Barra di ricerca della pagina su iPhone senza Liquid Glass (con Liquid Glass è nella barra).
struct PageSearchBar: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        #if os(iOS)
        if !ThemeStore.shared.liquidGlass {
            M3SearchBar(text: $text, prompt: prompt)
        }
        #endif
    }
}
