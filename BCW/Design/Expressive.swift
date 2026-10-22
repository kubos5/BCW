import SwiftUI

// Componenti propri di M3 Expressive che la versione web non ha: barra di ricerca in alto,
// menu del pulsante d'azione flottante, barra degli strumenti flottante, schede, gruppi di
// pulsanti collegati con contenuto libero, sezioni segmentate, chip di stato e date.

// MARK: - Barra di ricerca in alto

/// Barra superiore con la barra di ricerca (come Gmail e Google Foto): una pillola sospesa di 56
/// punti con l'icona, l'invito e, a destra, pulsanti a icona e l'avatar dell'account. Toccandola
/// diventa il campo di ricerca (la lente lascia il posto alla freccia per tornare indietro, a
/// destra la X per cancellare) e resta sospesa sopra i risultati.
struct SearchAppBar<Trailing: View>: View {
    let prompt: String
    var activePrompt: String
    @Binding var query: String
    @Binding var isActive: Bool
    var focus: FocusState<Bool>.Binding
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            if isActive {
                IconButton("arrowBack", label: "Chiudi la ricerca") {
                    withAnimation(Motion.spatial) { isActive = false }
                }
                .padding(.leading, 4)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                TextField(activePrompt, text: $query)
                    .textFieldStyle(.plain)
                    .font(.m3(16))
                    .foregroundStyle(Theme.ink)
                    .focused(focus)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .padding(.leading, 4)
                    .transition(.opacity)
                if !query.isEmpty {
                    IconButton("x", label: "Cancella") { query = "" }
                        .padding(.trailing, 4)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            } else {
                Button {
                    withAnimation(Motion.spatial) { isActive = true }
                } label: {
                    HStack(spacing: 14) {
                        Icon("search")
                            .foregroundStyle(Theme.onSurface)
                        Text(prompt)
                            .font(.m3(16))
                            .foregroundStyle(Theme.onSurfaceVariant)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 16)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(HeaderButtonStyle())
                .accessibilityLabel("Cerca")
                .transition(.opacity)
                HStack(spacing: 0) {
                    trailing()
                }
                .buttonStyle(.m3Icon())
                .labelStyle(.iconOnly)
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .padding(.trailing, 4)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(height: 56)
        .background(isActive ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Theme.surface.ignoresSafeArea(edges: .top))
        .animation(Motion.spatial, value: query.isEmpty)
    }
}

/// Avatar dell'account attivo (40 punti, in un biscotto): apre il popup per cambiare account.
struct AccountAvatarButton: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 34
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Avatar(initials: model.card?.initials ?? String(model.displayName.prefix(1)), size: size, shape: .cookie9Sided)
                .frame(width: 48, height: 48)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account, \(model.displayName)")
        .accessibilityHint("Cambia o aggiunge un account")
    }
}

// MARK: - Menu del pulsante d'azione flottante

/// Voce del menu del FAB.
struct FABMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    var disabled = false
    let action: () -> Void
}

/// Menu del pulsante d'azione flottante di M3 Expressive: il FAB (quadrato arrotondato nel
/// contenitore primario) diventa un cerchio pieno con la X e sopra salgono, allineate a destra,
/// da 2 a 6 voci a pillola. Con Liquid Glass è un menu di sistema su un pulsante di vetro.
/// Va messo in una sovrapposizione che copre la pagina: aperto, un velo chiude il menu al tocco.
struct FABMenu: View {
    let icon: String
    let label: String
    let items: [FABMenuItem]
    @State private var isExpanded = false
    @Environment(\.windowClass) private var windowClass

    var body: some View {
        if ThemeStore.shared.liquidGlass {
            GlassFABMenu(icon: icon, label: label, items: items, isExpanded: $isExpanded)
        } else {
            ZStack(alignment: .bottomTrailing) {
                if isExpanded {
                    Theme.surface.opacity(0.6)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { toggle() }
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .trailing, spacing: 4) {
                    if isExpanded {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            Button {
                                toggle()
                                item.action()
                            } label: {
                                Label { Text(item.title) } icon: { Icon(item.icon) }
                            }
                            .buttonStyle(FABMenuItemStyle())
                            .disabled(item.disabled)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.4, anchor: .bottomTrailing).combined(with: .opacity)
                                    .animation(Motion.spatial.delay(Double(items.count - 1 - index) * 0.035)),
                                removal: .scale(scale: 0.7, anchor: .bottomTrailing).combined(with: .opacity)
                                    .animation(Motion.effects)))
                        }
                    }
                    toggleButton
                        .padding(.top, isExpanded ? 6 : 0)
                }
                // Sull'iPad largo a 24 punti dai bordi del pannello, come sul web.
                .padding(windowClass == .regular ? 24 : 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)
        }
    }

    private var toggleButton: some View {
        Button(action: toggle) {
            Icon(isExpanded ? "x" : icon, size: 24)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .foregroundStyle(isExpanded ? Theme.onPrimary : Theme.onPrimaryContainer)
                .frame(width: 56, height: 56)
                .background {
                    RoundedRectangle(cornerRadius: isExpanded ? 28 : Theme.radii.l, style: .continuous)
                        .fill(isExpanded ? Theme.primary : Theme.primaryContainer)
                        .shadow(color: Theme.shadow.opacity(isExpanded ? 0.12 : 0.22), radius: 3, y: 1)
                        .shadow(color: Theme.shadow.opacity(0.1), radius: 8, y: 4)
                }
                .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Chiudi il menu" : label)
    }

    private func toggle() {
        withAnimation(Motion.spatial) { isExpanded.toggle() }
    }
}

/// Menu del FAB con Liquid Glass: un pulsante di vetro tinto e interattivo da cui, toccandolo, si
/// staccano le voci, pillole di vetro che escono dal pulsante e ci rientrano (stesso
/// `GlassEffectContainer`). Non è un `Menu` di sistema: chiudendosi il suo vetro scuro rientrava
/// nel pulsante senza tinta (nero fino alla fine dell'animazione).
/// Della misura del pulsante di ricerca della barra delle schede, allineato sopra di esso.
private struct GlassFABMenu: View {
    let icon: String
    let label: String
    let items: [FABMenuItem]
    @Binding var isExpanded: Bool
    @Namespace private var glass
    @Environment(\.windowClass) private var windowClass

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isExpanded {
                Theme.surface.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { toggle() }
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
            GlassEffectContainer(spacing: 6) {
                VStack(alignment: .trailing, spacing: 10) {
                    if isExpanded {
                        ForEach(items) { item in
                            Button {
                                toggle()
                                item.action()
                            } label: {
                                Label { Text(item.title) } icon: { Icon(item.icon) }
                                    .labelStyle(M3ButtonLabelStyle(iconSize: 22))
                                    .font(.m3(16, weight: 600))
                                    .foregroundStyle(Theme.ink)
                                    .padding(.leading, 18)
                                    .padding(.trailing, 22)
                                    .frame(height: 52)
                                    .contentShape(.capsule)
                            }
                            .buttonStyle(.plain)
                            .disabled(item.disabled)
                            .opacity(item.disabled ? 0.5 : 1)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .glassEffectID(item.id, in: glass)
                        }
                    }
                    Button(action: toggle) {
                        Icon(isExpanded ? "x" : icon, size: 24)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(Theme.onPrimary)
                            .frame(width: 60, height: 60)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(Theme.primary).interactive(), in: .circle)
                    .glassEffectID("fab", in: glass)
                    .accessibilityLabel(isExpanded ? "Chiudi il menu" : label)
                }
            }
            // Sopra il pulsante di ricerca della barra delle schede; sull'iPad largo (barra in alto)
            // a 24 punti dai bordi.
            .padding(.trailing, windowClass == .regular ? 24 : 21)
            .padding(.bottom, windowClass == .regular ? 24 : 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .sensoryFeedback(.impact(weight: .light), trigger: isExpanded)
    }

    private func toggle() {
        withAnimation(Motion.spatial) { isExpanded.toggle() }
    }
}

/// Voce del menu del FAB: pillola di 56 punti nel contenitore primario.
private struct FABMenuItemStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: configuration.isPressed ? Theme.radii.l : 28, style: .continuous)
        configuration.label
            .labelStyle(M3ButtonLabelStyle(iconSize: 24))
            .font(.m3(16, weight: 600))
            .foregroundStyle(Theme.onPrimaryContainer)
            .padding(.leading, 20)
            .padding(.trailing, 24)
            .frame(height: 56)
            .background {
                shape.fill(Theme.primaryContainer)
                    .overlay(shape.fill(Theme.onPrimaryContainer.opacity(configuration.isPressed ? 0.12 : 0)))
                    .shadow(color: Theme.shadow.opacity(0.16), radius: 3, y: 1)
            }
            .contentShape(shape)
            .animation(Motion.spatialFast, value: configuration.isPressed)
    }
}

// MARK: - Barra degli strumenti flottante

extension EnvironmentValues {
    /// Barra degli strumenti flottante vivace (contenitore primario), per i colori dei pulsanti.
    @Entry var floatingToolbarVibrant = false
}

/// Barra degli strumenti flottante di M3 Expressive: una pillola di 64 punti in basso al centro
/// con i comandi della pagina. Quella vivace (contenitore primario) segnala una modalità
/// temporanea, come la modifica. Con Liquid Glass è una pillola di vetro.
struct FloatingToolbar<Content: View>: View {
    var vibrant = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        if ThemeStore.shared.liquidGlass {
            GlassEffectContainer {
                HStack(spacing: 4) { content() }
                    .padding(6)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            .environment(\.floatingToolbarVibrant, false)
        } else {
            HStack(spacing: 4) { content() }
                .padding(8)
                .frame(minHeight: 64)
                .background {
                    Capsule(style: .continuous)
                        .fill(vibrant ? Theme.primaryContainer : Theme.surfaceContainer)
                        .shadow(color: Theme.shadow.opacity(0.18), radius: 4, y: 2)
                        .shadow(color: Theme.shadow.opacity(0.1), radius: 12, y: 6)
                }
                .environment(\.floatingToolbarVibrant, vibrant)
        }
    }
}

/// Pulsante a icona (48 punti) di una barra degli strumenti flottante; `selected` per gli
/// interruttori (pieno nel colore primario).
struct ToolbarIconButton: View {
    let icon: String
    let label: String
    var selected = false
    let action: () -> Void
    @Environment(\.floatingToolbarVibrant) private var vibrant

    init(_ icon: String, label: String, selected: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Icon(icon)
        }
        .buttonStyle(ToolbarButtonStyle(selected: selected, vibrant: vibrant))
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Pulsante con testo di una barra degli strumenti flottante (pieno, es. "Fine").
struct ToolbarTextButton: View {
    let title: String
    var icon: String?
    let action: () -> Void

    var body: some View {
        if ThemeStore.shared.liquidGlass {
            Button(action: action) {
                Label { Text(title) } icon: { Image.m(icon ?? "check") }
                    .labelStyle(.titleAndIcon)
                    .font(.m3(16, weight: 600))
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 6)
                    .frame(height: 36)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.primary)
        } else {
            Button(action: action) {
                if let icon {
                    Label { Text(title) } icon: { Icon(icon) }
                } else {
                    Text(title)
                }
            }
            .buttonStyle(.m3(.filled, size: .m))
            .frame(height: 48)
            .clipShape(.capsule)
        }
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    let selected: Bool
    let vibrant: Bool

    func makeBody(configuration: Configuration) -> some View {
        let glass = ThemeStore.shared.liquidGlass
        let foreground = selected ? Theme.onPrimary
            : (vibrant ? Theme.onPrimaryContainer : (glass ? Theme.ink : Theme.onSurfaceVariant))
        let shape = RoundedRectangle(cornerRadius: configuration.isPressed ? Theme.radii.m : 24, style: .continuous)
        configuration.label
            .foregroundStyle(foreground)
            .frame(width: 48, height: 48)
            .background {
                shape.fill(selected ? Theme.primary : .clear)
                    .overlay(shape.fill(foreground.opacity(configuration.isPressed ? 0.12 : 0)))
            }
            .contentShape(shape)
            .animation(Motion.spatialFast, value: configuration.isPressed)
            .animation(Motion.spatialFast, value: selected)
    }
}

/// Separatore verticale tra gruppi di comandi di una barra degli strumenti.
struct ToolbarSeparator: View {
    @Environment(\.floatingToolbarVibrant) private var vibrant

    var body: some View {
        Capsule()
            .fill((vibrant ? Theme.onPrimaryContainer : Theme.outlineVariant).opacity(vibrant ? 0.25 : 1))
            .frame(width: 1, height: 24)
            .padding(.horizontal, 4)
    }
}

// MARK: - Schede

/// Schede principali di Material 3: etichette di uguale larghezza con l'indicatore (3 punti,
/// angoli superiori arrotondati) sotto quella scelta, che scivola con una molla.
struct PrimaryTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let tabs: [(value: Value, title: String, icon: String?)]
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in
                let selected = tab.value == selection
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withAnimation(Motion.spatial) { selection = tab.value }
                } label: {
                    // L'indicatore poggia sul separatore ed è largo quanto l'etichetta.
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            if let icon = tab.icon { Icon(icon, size: 20) }
                            Text(tab.title)
                                .font(.m3(15, weight: selected ? 650 : 550))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selected ? Theme.primary : Theme.onSurfaceVariant)
                        .frame(maxHeight: .infinity)
                        ZStack {
                            if selected {
                                UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                                    .fill(Theme.primary)
                                    .matchedGeometryEffect(id: "indicator", in: namespace)
                            }
                        }
                        .frame(height: 3)
                        .padding(.horizontal, -2)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(.rect)
                }
                .buttonStyle(TabButtonStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.outlineVariant).frame(height: 1)
        }
    }
}

private struct TabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Theme.onSurface.opacity(configuration.isPressed ? 0.08 : 0))
            .animation(Motion.effectsFast, value: configuration.isPressed)
    }
}

// MARK: - Gruppo di pulsanti collegati con contenuto libero

/// Gruppo di pulsanti collegati di M3 Expressive con un'etichetta su più righe (es. periodo e
/// media): 2 punti tra i pulsanti, angoli interni piccoli ed esterni pieni; quello scelto diventa
/// tutto arrotondato e pieno, quello premuto stringe gli angoli.
struct ConnectedButtonGroup<Value: Hashable, Label: View>: View {
    @Binding var selection: Value
    let values: [Value]
    var height: CGFloat = 56
    @ViewBuilder let label: (Value, Bool) -> Label

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                let selected = value == selection
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withAnimation(Motion.spatial) { selection = value }
                } label: {
                    label(value, selected)
                        .frame(maxWidth: .infinity, minHeight: height)
                        .contentShape(.rect)
                }
                .buttonStyle(ConnectedStyle(selected: selected, first: index == 0, last: index == values.count - 1,
                                            height: height))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private struct ConnectedStyle: ButtonStyle {
        let selected: Bool
        let first: Bool
        let last: Bool
        let height: CGFloat

        func makeBody(configuration: Configuration) -> some View {
            let full = min(height / 2, Theme.radii.xl)
            let inner: CGFloat = configuration.isPressed ? 4 : Theme.radii.s
            let leading = selected || first ? full : inner
            let trailing = selected || last ? full : inner
            let shape = UnevenRoundedRectangle(topLeadingRadius: leading, bottomLeadingRadius: leading,
                                               bottomTrailingRadius: trailing, topTrailingRadius: trailing,
                                               style: .continuous)
            let foreground = selected ? Theme.onPrimary : Theme.onSurface
            configuration.label
                .foregroundStyle(foreground)
                .background {
                    shape.fill(selected ? Theme.primary : Theme.surfaceContainerHigh)
                        .overlay(shape.fill(foreground.opacity(configuration.isPressed ? 0.12 : 0)))
                }
                .contentShape(shape)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.spatialFast, value: configuration.isPressed)
                .animation(Motion.spatial, value: selected)
        }
    }
}

// MARK: - Sezioni segmentate

/// Sezione di una pagina in stile M3 Expressive: intestazione (icona nella sua forma, titolo,
/// valore a destra e freccia) e sotto le voci in una lista segmentata (`ListGroup`). Toccando
/// l'intestazione la lista si chiude; lo stato è ricordato tra un avvio e l'altro.
struct SegmentedSection<Content: View>: View {
    @Environment(AppModel.self) private var model
    let section: DashboardSection
    let title: String
    let icon: String
    var tint: Color = Theme.primary
    var trailing: String?
    /// Avanzamento (0…1) mostrato come barra ondulata accanto al valore (es. compiti fatti).
    var progress: Double?
    @ViewBuilder let content: () -> Content

    private var isCollapsed: Bool { model.preferences.isCollapsed(section) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.spatial) { model.preferences.toggleCollapsed(section) }
            } label: {
                HStack(spacing: 12) {
                    Icon(icon, size: 20)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.m3(16, weight: 600))
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    if let progress {
                        WavyProgress(value: progress, total: 1)
                            .frame(width: 44, height: 10)
                    }
                    if let trailing {
                        Text(trailing)
                            .font(.m3(13, weight: 600).monospacedDigit())
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    Chevron(collapsed: isCollapsed)
                }
                .padding(.leading, 8)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(HeaderButtonStyle())
            .accessibilityHint(isCollapsed ? "Espande la sezione" : "Comprime la sezione")
            .sensoryFeedback(.selection, trigger: isCollapsed)

            CollapsibleContent(isExpanded: !isCollapsed, spacing: 6) {
                ListGroup { content() }
            }
        }
    }
}

/// Voce di una sezione segmentata: il contenuto con i margini delle voci delle liste.
struct SegmentCell<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, padding)
            .padding(.vertical, padding - 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Chip di stato e date

/// Chip di stato (32 punti, contenitore tonale): un conteggio o uno stato del giorno.
struct StatusChip: View {
    let text: String
    let icon: String
    var container: Color = Theme.secondaryContainer
    var foreground: Color = Theme.onSecondaryContainer

    var body: some View {
        HStack(spacing: 6) {
            Icon(icon, size: 18)
            Text(text)
                .font(.m3(13, weight: 600))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 32)
        .background(container, in: .rect(cornerRadius: Theme.radii.s, style: .continuous))
        .fixedSize()
    }
}

/// Data in un riquadro (iniziali del giorno e numero), come nella vista Programma di Google
/// Calendar: piena nel colore primario se è oggi, nel contenitore terziario se c'è una verifica.
struct DateBadge: View {
    let day: Date
    var highlighted = false

    var body: some View {
        let today = day.isToday
        VStack(spacing: 0) {
            Text(day.it("EEE").uppercased().replacingOccurrences(of: ".", with: ""))
                .font(.m3(11, weight: 700))
                .tracking(0.6)
            Text(day.it("d"))
                .font(.numeral(22, weight: 650))
        }
        .foregroundStyle(today ? Theme.onPrimary : (highlighted ? Theme.onTertiaryContainer : Theme.ink))
        .frame(width: 52, height: 58)
        .background(today ? Theme.primary : (highlighted ? Theme.tertiaryContainer : Theme.surfaceContainerHigh),
                    in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(day.longDay)
    }
}

// MARK: - Barre in fondo che si nascondono

/// Stato condiviso tra le schede e la barra di navigazione: una pagina può nasconderla per una
/// modalità temporanea (es. la modifica dell'orario, che mostra la sua barra degli strumenti).
@Observable
final class TabChrome {
    var hidesBar = false
}

extension EnvironmentValues {
    @Entry var tabChrome: TabChrome?
}
