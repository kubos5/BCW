import SwiftUI

// Shell dell'iPad con la finestra larga e senza Liquid Glass, come la versione web sugli schermi
// larghi: barra superiore con logo, ricerca generale, Aggiorna, Impostazioni e account; barra di
// navigazione laterale con tutte le sezioni (espansa da 1100 punti, altrimenti ridotta e
// apribile sopra la pagina); la pagina in un pannello con angoli ampi.

enum WideShellMetrics {
    /// Barra di navigazione espansa e ridotta.
    static let railExpanded: CGFloat = 264
    static let railCollapsed: CGFloat = 96
    /// Barra superiore (sotto la barra di stato).
    static let topBarHeight: CGFloat = 72
    /// Margine del pannello della pagina a destra e in basso.
    static let panelInset: CGFloat = 12

    /// Blocco iniziale della barra superiore (pulsante del menu e logo): largo quanto la barra di
    /// navigazione meno 20 punti, almeno 164.
    static func leadWidth(railWidth: CGFloat) -> CGFloat { max(164, railWidth - 20) }
}

// MARK: - Barra superiore

struct WideTopBar: View {
    @Environment(AppModel.self) private var model
    /// Larghezza della barra di navigazione accanto al pannello.
    let railWidth: CGFloat
    /// La barra di navigazione è ridotta (l'icona del menu si capovolge).
    let railCollapsed: Bool
    @Binding var query: String
    var focus: FocusState<Bool>.Binding
    /// La scheda Cerca è aperta.
    let isSearching: Bool
    let toggleRail: () -> Void
    let closeSearch: () -> Void
    let openSettings: () -> Void
    let switchAccount: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 12) {
                IconButton("menuOpen", label: railCollapsed ? "Espandi la barra di navigazione" : "Riduci la barra di navigazione",
                           action: toggleRail)
                    .scaleEffect(x: railCollapsed ? -1 : 1)
                BCWLogo(size: 22)
            }
            .frame(width: WideShellMetrics.leadWidth(railWidth: railWidth), alignment: .leading)
            .animation(Motion.spatial, value: railWidth)

            GlobalSearchField(query: $query, focus: focus, isSearching: isSearching, close: closeSearch)
                .frame(maxWidth: 720)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    if model.isRefreshing {
                        InlineProgress(size: 22)
                    } else {
                        Label { Text("Aggiorna") } icon: { Icon("refresh") }
                    }
                }
                .buttonStyle(.m3Icon())
                .disabled(model.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
                .help("Aggiorna i dati da Classeviva")
                .accessibilityLabel("Aggiorna")
                IconButton("gear", label: "Impostazioni", action: openSettings)
                    .keyboardShortcut(",", modifiers: .command)
                AccountAvatarButton(size: 36, action: switchAccount)
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.top, 8)
        .frame(height: WideShellMetrics.topBarHeight)
        .background(Theme.surfaceContainer.ignoresSafeArea(edges: .top))
    }
}

/// Campo della ricerca generale (`surface-container-highest`, con il fuoco più chiaro e un'ombra
/// leggera, come `.global-search` del web). Prendendo il fuoco si apre la scheda Cerca; la X (o
/// Esc) svuota il campo e torna alla pagina di prima.
private struct GlobalSearchField: View {
    @Binding var query: String
    var focus: FocusState<Bool>.Binding
    let isSearching: Bool
    let close: () -> Void

    var body: some View {
        let focused = focus.wrappedValue
        HStack(spacing: 12) {
            Icon("search")
                .foregroundStyle(Theme.onSurfaceVariant)
            TextField("Cerca nel registro", text: $query)
                .textFieldStyle(.plain)
                .font(.m3(16))
                .foregroundStyle(Theme.ink)
                .focused(focus)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
            if isSearching || !query.isEmpty {
                IconButton("x", label: "Chiudi la ricerca", size: 36, action: close)
                    .keyboardShortcut(.cancelAction)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 52)
        .background {
            Capsule(style: .continuous)
                .fill(focused ? Theme.surfaceContainerLowest : Theme.surfaceContainerHighest)
                .shadow(color: Theme.shadow.opacity(focused ? 0.16 : 0), radius: 3, y: 1)
        }
        .contentShape(.capsule)
        .onTapGesture { focus.wrappedValue = true }
        .animation(Motion.effects, value: focused)
        .animation(Motion.spatial, value: isSearching || !query.isEmpty)
        .keyboardShortcut("f", modifiers: .command)
        .help("Cerca")
    }
}

// MARK: - Barra di navigazione

/// Barra di navigazione laterale di M3 Expressive. Espansa (264 punti): voci di 56 punti con
/// l'indicatore a pillola largo quanto la voce, i gruppi con il titolo e i conteggi a destra.
/// Ridotta (96 punti): l'icona nell'indicatore 56 × 32 con l'etichetta breve sotto, i gruppi
/// separati da una linea e i conteggi sull'icona.
struct NavigationRail: View {
    @Environment(AppModel.self) private var model
    let expanded: Bool
    let selection: MainTabView.AppTab
    let select: (MainTabView.AppTab) -> Void
    /// Pressione prolungata su Tu: cambio dell'account, come nella barra in basso.
    let longPressYou: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                VStack(spacing: 2) {
                    ForEach(MainTabView.AppTab.mainTabs, id: \.self) { tab in
                        item(tab, badge: 0)
                    }
                }
                ForEach(AppSection.Group.allCases) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        if expanded {
                            Text(group.title)
                                .font(.m3(14, weight: 600))
                                .foregroundStyle(Theme.onSurfaceVariant)
                                .lineLimit(1)
                                .padding(EdgeInsets(top: 16, leading: 16, bottom: 6, trailing: 16))
                                .accessibilityAddTraits(.isHeader)
                        } else {
                            Rectangle()
                                .fill(Theme.outlineVariant)
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                        ForEach(group.sections) { section in
                            item(.section(section), badge: section.badge(model))
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, expanded ? 12 : 8)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: expanded ? WideShellMetrics.railExpanded : WideShellMetrics.railCollapsed)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sezioni")
    }

    private func item(_ tab: MainTabView.AppTab, badge: Int) -> some View {
        RailItem(tab: tab, selected: tab == selection, expanded: expanded, badge: badge,
                 select: { select(tab) }, longPress: tab == .you ? longPressYou : nil)
    }
}

private struct RailItem: View {
    let tab: MainTabView.AppTab
    let selected: Bool
    let expanded: Bool
    let badge: Int
    let select: () -> Void
    var longPress: (() -> Void)?
    @State private var pressed = false
    /// La pressione prolungata ha già agito: il tocco che finisce dopo non sceglie la voce.
    @State private var longPressed = false

    var body: some View {
        Button {
            if longPressed {
                longPressed = false
                return
            }
            Haptics.selection()
            select()
        } label: {
            if expanded { expandedLabel } else { collapsedLabel }
        }
        .buttonStyle(PressReportingStyle(pressed: $pressed))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                guard let longPress else { return }
                longPressed = true
                Haptics.soft()
                longPress()
            }
        )
        .modifier(MainTabShortcut(tab: tab))
        .hoverEffect(.highlight)
        .animation(Motion.effectsFast, value: pressed)
        .animation(Motion.spatial, value: selected)
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(badge > 0 ? "\(badge)" : "")
    }

    private var icon: String { selected ? tab.selectedIcon : tab.icon }

    private var expandedLabel: some View {
        HStack(spacing: 4) {
            Icon(icon)
                .frame(width: 52, height: 32)
            Text(tab.title)
                .font(.m3(14, weight: selected ? 750 : 550))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if badge > 0 {
                Text("\(badge)")
                    .font(.m3(12, weight: 650))
                    .monospacedDigit()
                    .padding(.horizontal, 8)
            }
        }
        .foregroundStyle(selected ? Theme.onSecondaryContainer : Theme.onSurfaceVariant)
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: 56)
        .background {
            ZStack {
                Capsule(style: .continuous)
                    .fill(Theme.secondaryContainer)
                    .scaleEffect(x: selected ? 1 : 0.7, y: 1, anchor: .leading)
                    .opacity(selected ? 1 : 0)
                Capsule(style: .continuous)
                    .fill(Theme.onSurfaceVariant.opacity(pressed ? 0.12 : 0))
            }
        }
        .contentShape(.capsule)
    }

    private var collapsedLabel: some View {
        VStack(spacing: 4) {
            ZStack {
                Capsule(style: .continuous)
                    .fill(Theme.secondaryContainer)
                    .scaleEffect(x: selected ? 1 : 0, y: 1)
                    .opacity(selected ? 1 : 0)
                Capsule(style: .continuous)
                    .fill(Theme.onSurfaceVariant.opacity(pressed ? 0.12 : 0))
                Icon(icon)
                    .foregroundStyle(selected ? Theme.onSecondaryContainer : Theme.onSurfaceVariant)
                if badge > 0 {
                    CountBadge(count: badge)
                        .offset(x: 13, y: -10)
                }
            }
            .frame(width: 56, height: 32)
            Text(tab.shortTitle)
                .font(.m3(12, weight: selected ? 750 : 550))
                .tracking(0.2)
                .foregroundStyle(selected ? Theme.secondary : Theme.onSurfaceVariant)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 2)
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
    }
}

/// ⌘1–⌘4 per Dashboard, Orario, Voti e Tu (con una tastiera collegata).
private struct MainTabShortcut: ViewModifier {
    let tab: MainTabView.AppTab

    func body(content: Content) -> some View {
        if let index = MainTabView.AppTab.mainTabs.firstIndex(of: tab) {
            content.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        } else {
            content
        }
    }
}

// MARK: - Barra laterale di sistema (Liquid Glass)

/// Intestazione della barra laterale di sistema: logo e account attivo (apre il cambio account).
/// Il modello arriva come parametro: UIKit ospita intestazione e barra in fondo a parte, e a volte
/// senza l'ambiente della finestra (l'app si chiudeva cercando `AppModel` nell'ambiente).
struct SidebarAccountHeader: View {
    let model: AppModel
    let switchAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            BCWLogo(size: 22)
                .padding(.leading, 4)
            Button(action: switchAccount) {
                HStack(spacing: 12) {
                    Avatar(initials: model.card?.initials ?? String(model.displayName.prefix(1)), size: 40,
                           shape: .cookie9Sided)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.displayName)
                            .font(.m3(15, weight: 650))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        if let school = model.card?.schoolDescription {
                            Text(school)
                                .font(.m3(12))
                                .foregroundStyle(Theme.secondaryInk)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Icon("switchAccount", size: 20)
                        .foregroundStyle(Theme.onSurfaceVariant)
                }
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account, \(model.displayName)")
            .accessibilityHint("Cambia o aggiunge un account")
        }
        .padding(.bottom, 4)
    }
}

/// In fondo alla barra laterale di sistema: Impostazioni e Aggiorna.
struct SidebarBottomActions: View {
    let model: AppModel
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: openSettings) {
                Label { Text("Impostazioni") } icon: { Image.m("gear") }
            }
            .keyboardShortcut(",", modifiers: .command)
            Spacer(minLength: 0)
            Button {
                Task { await model.refreshAll() }
            } label: {
                if model.isRefreshing {
                    InlineProgress(size: 20)
                } else {
                    Label { Text("Aggiorna") } icon: { Image.m("refresh") }
                        .labelStyle(.iconOnly)
                }
            }
            .disabled(model.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityLabel("Aggiorna")
        }
        .buttonStyle(.glass)
    }
}
