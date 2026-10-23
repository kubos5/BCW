import SwiftUI

// MARK: - Livello delle sovrapposizioni (menu, dialoghi, avvisi)

/// Menu, dialoghi e avvisi in stile Material 3, disegnati sopra la pagina (come i livelli
/// `.menu-layer`, `.dialog-layer` e `.snackbar` della versione web). Ogni finestra e ogni
/// foglio ne ha uno (`overlayHost()`), così un menu aperto in un foglio resta sopra al foglio.
@Observable
final class OverlayHost {
    struct MenuPresentation: Identifiable {
        let id = UUID()
        let anchor: CGRect
        let alignment: HorizontalAlignment
        let content: AnyView
    }

    struct DialogPresentation: Identifiable {
        let id = UUID()
        let title: String
        let message: String?
        let actions: [DialogAction]
        let stacked: Bool
    }

    struct ToastPresentation: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let icon: String
        static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    }

    var menu: MenuPresentation?
    var dialog: DialogPresentation?
    var toast: ToastPresentation?
    /// Origine del livello nelle coordinate globali (per posizionare i menu).
    @ObservationIgnored var origin: CGPoint = .zero
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    func showMenu(anchor: CGRect, alignment: HorizontalAlignment, content: AnyView) {
        Haptics.soft()
        withAnimation(Motion.spatialFast) {
            menu = MenuPresentation(anchor: anchor, alignment: alignment, content: content)
        }
    }

    func closeMenu() {
        withAnimation(Motion.effects) { menu = nil }
    }

    func showDialog(_ dialog: DialogPresentation) {
        menu = nil
        withAnimation(Motion.spatial) { self.dialog = dialog }
    }

    func closeDialog() {
        withAnimation(Motion.effects) { dialog = nil }
    }

    func showToast(_ message: String, icon: String = "checkCircle") {
        withAnimation(Motion.spatial) { toast = ToastPresentation(message: message, icon: icon) }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.6))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.effects) { self?.toast = nil }
        }
    }
}

/// Pulsante di un dialogo.
struct DialogAction: Identifiable {
    enum Style { case normal, strong, destructive, cancel }
    let id = UUID()
    let title: String
    var style: Style = .normal
    var action: () -> Void = {}

    static func cancel(_ title: String = "Annulla", action: @escaping () -> Void = {}) -> DialogAction {
        DialogAction(title: title, style: .cancel, action: action)
    }
}

extension View {
    /// Livello per menu, dialoghi e avvisi di Material 3 (alla radice della finestra e di ogni foglio).
    func overlayHost() -> some View {
        modifier(OverlayHostModifier())
    }
}

private struct OverlayHostModifier: ViewModifier {
    @State private var host = OverlayHost()

    func body(content: Content) -> some View {
        content
            .environment(host)
            .overlay {
                OverlayLayer(host: host)
            }
            .onGeometryChange(for: CGPoint.self) { $0.frame(in: .global).origin } action: { host.origin = $0 }
    }
}

private struct OverlayLayer: View {
    @Bindable var host: OverlayHost
    @Environment(\.windowClass) private var windowClass

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                if let menu = host.menu {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { host.closeMenu() }
                        .ignoresSafeArea()
                    MenuPanel(menu: menu, container: proxy.size, origin: host.origin, close: host.closeMenu)
                        .id(menu.id)
                }
                if let dialog = host.dialog {
                    Theme.scrim
                        .ignoresSafeArea()
                        .onTapGesture { }
                        .transition(.opacity)
                    DialogPanel(dialog: dialog, close: host.closeDialog)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                if let toast = host.toast {
                    ToastView(toast: toast)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        // Sopra la barra in basso; sull'iPad largo (senza barra in basso) vicino al fondo.
                        .padding(.bottom, windowClass == .regular ? 24 : 96)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
        }
    }
}

// MARK: - Menu

extension EnvironmentValues {
    /// Come disegnare le voci di un menu: di sistema (Liquid Glass) o di Material 3.
    @Entry var menuRendering: MenuRendering = .system
    /// Chiude il menu di Material 3 aperto.
    @Entry var closeMenu: () -> Void = {}
}

enum MenuRendering { case system, material }

/// Menu che segue Impostazioni › Aspetto › Liquid Glass: con Liquid Glass è il `Menu` di
/// sistema, altrimenti il menu espressivo di Material 3 (angoli 16, voci alte 44, voce scelta
/// nel contenitore terziario), aperto accanto al pulsante.
struct AppMenu<Label: View, Content: View>: View {
    var alignment: HorizontalAlignment = .trailing
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> Label

    @Environment(OverlayHost.self) private var host: OverlayHost?
    @State private var frame: CGRect = .zero

    init(alignment: HorizontalAlignment = .trailing, @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder label: @escaping () -> Label) {
        self.alignment = alignment
        self.content = content
        self.label = label
    }

    var body: some View {
        if ThemeStore.shared.liquidGlass || host == nil {
            Menu {
                content().environment(\.menuRendering, .system)
            } label: {
                label()
            }
        } else {
            Button {
                host?.showMenu(anchor: frame, alignment: alignment, content: AnyView(content()))
            } label: {
                label()
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        }
    }
}

/// Voce di un menu.
struct MenuItem: View {
    let title: String
    var icon: String?
    var subtitle: String?
    var checked = false
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, subtitle: String? = nil, checked: Bool = false,
         role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.checked = checked
        self.role = role
        self.action = action
    }

    @Environment(\.menuRendering) private var rendering
    @Environment(\.closeMenu) private var closeMenu
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        switch rendering {
        case .system:
            Button(role: role, action: action) {
                if checked {
                    SwiftUI.Label(title, systemImage: "checkmark")
                } else if let icon {
                    SwiftUI.Label { labelText } icon: { Image.m(icon) }
                } else {
                    labelText
                }
            }
        case .material:
            Button {
                closeMenu()
                action()
            } label: {
                HStack(spacing: 12) {
                    if checked || icon != nil {
                        Icon(checked ? "check" : (icon ?? "check"), size: 20)
                            .foregroundStyle(checked || role == .destructive ? AnyShapeStyle(.foreground) : AnyShapeStyle(Theme.onSurfaceVariant))
                            .frame(width: 20)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.m3(15))
                        if let subtitle {
                            Text(subtitle)
                                .font(.m3(12))
                                .foregroundStyle(checked ? AnyShapeStyle(.foreground.opacity(0.8)) : AnyShapeStyle(Theme.onSurfaceVariant))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuRowStyle(checked: checked, destructive: role == .destructive))
            .opacity(isEnabled || checked ? 1 : 0.38)
            .modifier(CheckedMenuItemAnchor(checked: checked))
        }
    }

    @ViewBuilder private var labelText: some View {
        if let subtitle {
            Text(title)
            Text(subtitle)
        } else {
            Text(title)
        }
    }
}

/// La voce scelta di un menu che scorre: il menu si apre con lei in vista (es. 13:00 tra gli orari
/// a mezz'ora dell'editor dell'evento, invece di 00:00).
private struct CheckedMenuItemAnchor: ViewModifier {
    static let id = "BCW.menu.checked"
    let checked: Bool

    func body(content: Content) -> some View {
        if checked {
            content.id(Self.id)
        } else {
            content
        }
    }
}

private struct MenuRowStyle: ButtonStyle {
    let checked: Bool
    let destructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radii.m, style: .continuous)
        let foreground = checked ? Theme.onTertiaryContainer : (destructive ? Theme.error : Theme.ink)
        configuration.label
            .foregroundStyle(foreground)
            .background {
                shape.fill(checked ? Theme.tertiaryContainer : .clear)
                    .overlay(shape.fill(foreground.opacity(configuration.isPressed ? 0.12 : 0)))
            }
            .contentShape(shape)
    }
}

/// Gruppo di voci con un titolo facoltativo.
struct MenuSection<Content: View>: View {
    var title: String?
    @ViewBuilder let content: () -> Content

    init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    @Environment(\.menuRendering) private var rendering

    var body: some View {
        switch rendering {
        case .system:
            if let title {
                Section(title) { content() }
            } else {
                Section { content() }
            }
        case .material:
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(.m3(12, weight: 650))
                        .tracking(0.4)
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                }
                content()
            }
        }
    }
}

struct MenuDivider: View {
    @Environment(\.menuRendering) private var rendering

    var body: some View {
        switch rendering {
        case .system: Divider()
        case .material:
            Rectangle()
                .fill(Theme.outlineVariant)
                .frame(height: 1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
    }
}

/// Scelta di un valore in un menu: voci con la spunta.
struct MenuPicker<Value: Hashable>: View {
    var title: String?
    @Binding var selection: Value
    let options: [(value: Value, title: String, icon: String?)]

    @Environment(\.menuRendering) private var rendering

    var body: some View {
        switch rendering {
        case .system:
            Picker(selection: $selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    if let icon = option.icon {
                        SwiftUI.Label { Text(option.title) } icon: { Image.m(icon) }.tag(option.value)
                    } else {
                        Text(option.title).tag(option.value)
                    }
                }
            } label: {
                Text(title ?? "")
            }
            .pickerStyle(.inline)
        case .material:
            MenuSection(title) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    MenuItem(option.title, icon: option.icon, checked: option.value == selection) {
                        Haptics.selection()
                        selection = option.value
                    }
                }
            }
        }
    }
}

/// Sottomenu (di sistema) o sezione con titolo (Material 3).
struct SubMenu<Content: View>: View {
    let title: String
    var icon: String?
    @ViewBuilder let content: () -> Content

    @Environment(\.menuRendering) private var rendering

    var body: some View {
        switch rendering {
        case .system:
            Menu {
                content()
            } label: {
                if let icon {
                    SwiftUI.Label { Text(title) } icon: { Image.m(icon) }
                } else {
                    Text(title)
                }
            }
        case .material:
            MenuDivider()
            MenuSection(title, content: content)
        }
    }
}

private struct MenuPanel: View {
    let menu: OverlayHost.MenuPresentation
    let container: CGSize
    let origin: CGPoint
    let close: () -> Void
    /// Misura del contenuto alla sua larghezza ideale (da una copia invisibile).
    @State private var ideal: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let anchor = menu.anchor.offsetBy(dx: -origin.x, dy: -origin.y)
        let width = min(max(ideal.width, 200), min(320, container.width - 16))
        // Spazio sotto e sopra il pulsante. Se il menu non entra da nessuna parte (elenchi lunghi,
        // fogli bassi come i moduli dell'iPad) sta dal lato più ampio, alto quanto quello spazio, e
        // scorre: prima partiva sotto il pulsante alto quanto tutto il contenitore e usciva dal fondo.
        let spaceBelow = container.height - 8 - (anchor.maxY + 4)
        let spaceAbove = anchor.minY - 4 - 8
        let fitsBelow = ideal.height <= spaceBelow
        let below = fitsBelow || (ideal.height > spaceAbove && spaceBelow >= spaceAbove)
        let maxHeight = max(below ? spaceBelow : spaceAbove, min(ideal.height, 120))
        let height = min(ideal.height, maxHeight)
        let x = menu.alignment == .leading ? anchor.minX : anchor.maxX - width
        let y = below ? anchor.maxY + 4 : anchor.minY - 4 - height
        ZStack(alignment: .topLeading) {
            // Larghezza e altezza ideali del contenuto (copia invisibile), entro i limiti del menu.
            items
                .fixedSize()
                .hidden()
                .allowsHitTesting(false)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { ideal = $0 }
            if ideal != .zero {
                Group {
                    // Lo scorrimento solo se serve: dentro uno scorrimento i tocchi brevi arrivano in ritardo.
                    if ideal.height > maxHeight {
                        ScrollViewReader { proxy in
                            ScrollView {
                                items
                                    .frame(width: width, alignment: .leading)
                            }
                            .scrollBounceBehavior(.basedOnSize)
                            .onAppear { proxy.scrollTo(CheckedMenuItemAnchor.id, anchor: .center) }
                        }
                    } else {
                        items
                            .frame(width: width, alignment: .leading)
                    }
                }
                .frame(width: width, height: height)
                .background(colorScheme == .dark ? Theme.surfaceContainerHigh : Theme.surfaceContainerLow,
                            in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
                .clipShape(.rect(cornerRadius: Theme.radii.l, style: .continuous))
                .shadow(color: Theme.shadow.opacity(0.22), radius: 2, y: 1)
                .shadow(color: Theme.shadow.opacity(0.12), radius: 8, y: 3)
                .offset(x: min(max(8, x), container.width - width - 8), y: max(8, y))
                .transition(.scale(scale: 0.85, anchor: menu.alignment == .leading ? .topLeading : .topTrailing)
                    .combined(with: .opacity))
            }
        }
        .animation(Motion.spatialFast, value: ideal == .zero)
    }

    private var items: some View {
        VStack(alignment: .leading, spacing: 2) {
            menu.content
                .environment(\.menuRendering, .material)
                .environment(\.closeMenu, close)
        }
        .padding(6)
    }
}

// MARK: - Dialoghi

private struct DialogPanel: View {
    let dialog: OverlayHost.DialogPresentation
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dialog.title)
                .font(.m3(24, weight: 450, rounded: true))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
            if let message = dialog.message {
                Text(message)
                    .font(.m3(14))
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
                .padding(.top, 24)
        }
        .padding(24)
        .frame(maxWidth: 400, alignment: .leading)
        .background(Theme.surfaceContainerHigh, in: .rect(cornerRadius: Theme.radii.xl, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.22), radius: 3, y: 1)
        .shadow(color: Theme.shadow.opacity(0.1), radius: 10, y: 4)
    }

    @ViewBuilder private var actions: some View {
        if dialog.stacked {
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(dialog.actions) { button($0) }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(dialog.actions) { button($0) }
            }
        }
    }

    private func button(_ action: DialogAction) -> some View {
        Button {
            close()
            action.action()
        } label: {
            Text(action.title)
                .fontWeight(action.style == .strong ? .bold : nil)
                .multilineTextAlignment(.trailing)
        }
        .buttonStyle(.m3(action.style == .destructive ? .dangerText : .text))
        .keyboardShortcut(action.style == .cancel ? .cancelAction : (action.style == .strong || action.style == .destructive ? .defaultAction : nil))
    }
}

extension View {
    /// Dialogo di conferma di Material 3, al posto di `alert` e `confirmationDialog`.
    func m3Dialog(_ title: String, isPresented: Binding<Bool>, message: String? = nil, stacked: Bool = false,
                  actions: @escaping () -> [DialogAction]) -> some View {
        modifier(DialogModifier(title: title, isPresented: isPresented, message: message, stacked: stacked, actions: actions))
    }
}

private struct DialogModifier: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let message: String?
    let stacked: Bool
    let actions: () -> [DialogAction]
    @Environment(OverlayHost.self) private var host: OverlayHost?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, presented in
                guard presented, let host else { return }
                let wrapped = actions().map { action in
                    DialogAction(title: action.title, style: action.style) {
                        isPresented = false
                        action.action()
                    }
                }
                host.showDialog(.init(title: title, message: message, actions: wrapped, stacked: stacked))
            }
            .onChange(of: host?.dialog == nil) { _, closed in
                if closed, isPresented { isPresented = false }
            }
    }
}

// MARK: - Avvisi (snackbar)

private struct ToastView: View {
    let toast: OverlayHost.ToastPresentation

    var body: some View {
        HStack(spacing: 12) {
            Icon(toast.icon, size: 20)
                .foregroundStyle(Theme.inversePrimary)
            Text(toast.message)
                .font(.m3(14))
                .foregroundStyle(Theme.inverseOnSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .frame(maxWidth: 600)
        .background(Theme.inverseSurface, in: .rect(cornerRadius: Theme.radii.m, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.2), radius: 8, y: 3)
    }
}
