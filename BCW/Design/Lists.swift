import SwiftUI

// MARK: - Liste segmentate

/// Lista segmentata di Material 3 Expressive: voci separate da 2 punti, la prima e l'ultima
/// con gli angoli ampi (`--r-li`), le altre con angoli piccoli (`--r-xs`). Ogni voce ha lo
/// sfondo delle card. Con un titolo (nel colore primario) e una nota in fondo facoltativi.
struct ListGroup<Content: View>: View {
    var header: String?
    var footer: String?
    var background: Color?
    @ViewBuilder let content: () -> Content

    init(_ header: String? = nil, footer: String? = nil, background: Color? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.footer = footer
        self.background = background
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                ListHeader(header)
            }
            VStack(spacing: 2) {
                Group(subviews: content()) { subviews in
                    ForEach(subviews.indices, id: \.self) { index in
                        let first = index == subviews.startIndex
                        let last = index == subviews.index(before: subviews.endIndex)
                        let corners = ListCellCorners(top: first ? Theme.radii.li : Theme.radii.xs,
                                                      bottom: last ? Theme.radii.li : Theme.radii.xs)
                        // Gli angoli si passano anche direttamente: un modificatore applicato fuori da
                        // `.environment` leggerebbe ancora quelli predefiniti.
                        subviews[index]
                            .environment(\.listCellCorners, corners)
                            .modifier(ListCellBackground(color: background, corners: corners))
                    }
                }
            }
            if let footer {
                ListFooter(footer)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ListCellCorners: Equatable {
    var top: CGFloat
    var bottom: CGFloat

    var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom,
                               topTrailingRadius: top, style: .continuous)
    }
}

extension EnvironmentValues {
    @Entry var listCellCorners = ListCellCorners(top: 20, bottom: 20)
    /// Le voci disegnano da sé lo sfondo (es. quelle scelte nel contenitore secondario).
    @Entry var listCellOwnsBackground = false
}

private struct ListCellBackground: ViewModifier {
    var color: Color?
    var corners: ListCellCorners

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color ?? Theme.card, in: corners.shape)
            .clipShape(corners.shape)
    }
}

/// Titolo di una lista (14 punti, nel colore primario).
struct ListHeader: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.m3(14, weight: 650))
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Nota sotto una lista.
struct ListFooter: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.m3(12))
            .tracking(0.3)
            .foregroundStyle(Theme.onSurfaceVariant)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }
}

/// Voce di una lista: icona (facoltativa), titolo, sottotitolo e un elemento a destra.
struct ListRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    var titleColor: Color?
    var minHeight: CGFloat = 56
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, titleColor: Color? = nil, minHeight: CGFloat = 56,
         @ViewBuilder leading: @escaping () -> Leading, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.minHeight = minHeight
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 16) {
            leading()
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.m3(16, weight: 500))
                    .foregroundStyle(titleColor ?? Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.m3(14))
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: minHeight)
        .contentShape(Rectangle())
    }
}

extension ListRow where Leading == EmptyView {
    init(_ title: String, subtitle: String? = nil, titleColor: Color? = nil, minHeight: CGFloat = 56,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title, subtitle: subtitle, titleColor: titleColor, minHeight: minHeight,
                  leading: { EmptyView() }, trailing: trailing)
    }
}

extension ListRow where Leading == EmptyView, Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, titleColor: Color? = nil, minHeight: CGFloat = 56) {
        self.init(title, subtitle: subtitle, titleColor: titleColor, minHeight: minHeight,
                  leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

/// Stile delle voci toccabili di una lista: velo alla pressione nella forma della voce.
struct ListRowButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        ListRowButtonBody(configuration: configuration, selected: selected)
    }
}

private struct ListRowButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    @Environment(\.listCellCorners) private var corners
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let shape = pressed || selected
            ? ListCellCorners(top: Theme.radii.l, bottom: Theme.radii.l).shape
            : corners.shape
        configuration.label
            .foregroundStyle(selected ? Theme.onSecondaryContainer : Theme.ink)
            .background {
                if selected { shape.fill(Theme.secondaryContainer) }
            }
            .overlay {
                shape.fill(Theme.onSurface.opacity(pressed ? 0.1 : (hovering ? 0.06 : 0)))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.5)
            .animation(Motion.spatialFast, value: pressed)
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == ListRowButtonStyle {
    static var listRow: ListRowButtonStyle { ListRowButtonStyle() }
}

/// Icona di una voce di modulo (24 punti, nel colore secondario del testo).
struct FormIcon: View {
    let name: String
    var color: Color?
    init(_ name: String, color: Color? = nil) {
        self.name = name
        self.color = color
    }

    var body: some View {
        Icon(name, size: 22)
            .foregroundStyle(color ?? Theme.onSurfaceVariant)
            .frame(width: 24)
    }
}

/// Voce con un interruttore (tutta la voce lo cambia).
struct ToggleRow: View {
    let title: String
    var subtitle: String?
    var icon: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, icon: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 16) {
                if let icon { FormIcon(icon) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.m3(16, weight: 500))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.m3(14))
                            .foregroundStyle(Theme.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .toggleStyle(.m3)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
    }
}

/// Voce con un valore scelto da un elenco (pulsante che apre un menu).
struct SelectRow<Value: Hashable>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    @Binding var selection: Value
    let options: [(value: Value, title: String, icon: String?)]

    init(_ title: String, subtitle: String? = nil, icon: String? = nil, selection: Binding<Value>,
         options: [(value: Value, title: String, icon: String?)]) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        _selection = selection
        self.options = options
    }

    var body: some View {
        ListRow(title, subtitle: subtitle) {
            if let icon { FormIcon(icon) }
        } trailing: {
            SelectButton(selection: $selection, options: options, label: title)
        }
    }
}

/// Scelta da un elenco: un pulsante con il valore che apre un menu (`.select-btn`).
struct SelectButton<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String, icon: String?)]
    var label: String = ""
    var fill: Color?
    var minHeight: CGFloat = 36
    /// Occupa tutta la larghezza, con la freccia a destra (campi dei moduli, `.field .select-btn`).
    var expands = false

    var body: some View {
        let current = options.first { $0.value == selection }?.title ?? ""
        AppMenu {
            MenuPicker(title: nil, selection: $selection, options: options)
        } label: {
            HStack(spacing: 4) {
                Text(current)
                    .lineLimit(1)
                    .foregroundStyle(Theme.ink)
                if expands { Spacer(minLength: 0) }
                Icon("chevronUpDown", size: 18)
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
            .font(.m3(expands ? 15 : 14, weight: 550))
            .padding(.leading, expands ? 12 : 14)
            .padding(.trailing, 8)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: minHeight)
            .background(fill ?? Theme.surfaceContainerHigh,
                        in: .rect(cornerRadius: expands ? Theme.radii.l : Theme.radii.m, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        // Il valore resta intero: semmai va a capo il titolo della voce.
        .fixedSize(horizontal: !expands, vertical: true)
        .accessibilityLabel(label)
        .accessibilityValue(current)
    }
}

/// Campo di un modulo con l'etichetta sopra (`.field`), come nei fogli della versione web.
struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.m3(13, weight: 600))
                .foregroundStyle(Theme.onSurfaceVariant)
                .padding(.leading, 4)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Valore di sola lettura in un campo (`.field-value`).
struct FormFieldValue: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.m3(15).monospacedDigit())
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.surfaceContainer, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
    }
}

/// Voce che apre un'altra pagina o esegue un'azione, con la freccia a destra.
struct NavigationRow: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var tint: Color = Theme.onSurfaceVariant
    var badge: Int = 0
    /// Freccia a destra (no nelle voci di un elenco con il dettaglio accanto, sull'iPad).
    var showsChevron = true

    init(_ title: String, subtitle: String? = nil, icon: String? = nil, tint: Color = Theme.onSurfaceVariant, badge: Int = 0,
         showsChevron: Bool = true) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.badge = badge
        self.showsChevron = showsChevron
    }

    var body: some View {
        ListRow(title, subtitle: subtitle) {
            if let icon {
                IconBadge(icon: icon, tint: tint, size: 40)
            }
        } trailing: {
            HStack(spacing: 12) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.m3(12, weight: 650))
                        .monospacedDigit()
                        .foregroundStyle(Theme.error)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 24, minHeight: 22)
                        .background(Theme.error.opacity(0.15), in: .capsule)
                }
                if showsChevron {
                    Icon("chevronRight", size: 20)
                        .foregroundStyle(Theme.onSurfaceVariant)
                }
            }
        }
    }
}

/// Voce che è un pulsante (testo nel colore primario, o rosso se distruttiva).
struct ButtonRow: View {
    let title: String
    var icon: String?
    var destructive = false
    var subtitle: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, destructive: Bool = false, subtitle: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.destructive = destructive
        self.subtitle = subtitle
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ListRow(title, subtitle: subtitle, titleColor: destructive ? Theme.error : Theme.primary, leading: {
                if let icon { FormIcon(icon, color: destructive ? Theme.error : Theme.primary) }
            }, trailing: { EmptyView() })
        }
        .buttonStyle(.listRow)
    }
}

/// Voce con titolo e valore a destra.
struct ValueRow: View {
    let title: String
    let value: String
    var icon: String?

    init(_ title: String, value: String, icon: String? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
    }

    var body: some View {
        ListRow(title) {
            if let icon { FormIcon(icon) }
        } trailing: {
            Text(value)
                .font(.m3(14))
                .foregroundStyle(Theme.onSurfaceVariant)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 220, alignment: .trailing)
        }
    }
}

/// Voce con un contatore.
struct StepperRow<Value: Strideable & Comparable>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    @Binding var value: Value
    let range: ClosedRange<Value>
    var step: Value.Stride
    let format: (Value) -> String

    var body: some View {
        ListRow(title, subtitle: subtitle) {
            if let icon { FormIcon(icon) }
        } trailing: {
            M3Stepper(value: $value, range: range, step: step, format: format)
        }
    }
}

/// Separatore di Material 3 (1 punto, `outline-variant`).
struct M3Divider: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Theme.outlineVariant)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// Voce con un campo di testo (icona facoltativa a sinistra).
struct TextFieldRow: View {
    let prompt: String
    @Binding var text: String
    var icon: String?

    init(_ prompt: String, text: Binding<String>, icon: String? = nil) {
        self.prompt = prompt
        _text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 16) {
            if let icon { FormIcon(icon) }
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.m3(16))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 56)
    }
}
