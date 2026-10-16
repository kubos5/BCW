import SwiftUI

// MARK: - Pulsanti

/// Stili dei pulsanti di M3 Expressive (`.btn` nella versione web).
enum M3ButtonKind {
    case filled, tonal, outlined, text, elevated, danger, dangerText
}

/// Taglie dei pulsanti di M3 Expressive: XS 32, S 40, M 56.
enum M3ButtonSize {
    case xs, s, m

    var height: CGFloat {
        switch self {
        case .xs: 32
        case .s: 40
        case .m: 56
        }
    }

    var pressedRadius: CGFloat { self == .m ? 12 : 8 }
    var padding: CGFloat {
        switch self {
        case .xs: 12
        case .s: 16
        case .m: 24
        }
    }

    var fontSize: CGFloat { self == .m ? 16 : 14 }
    var iconSize: CGFloat { self == .m ? 24 : 20 }
}

/// Pulsante di Material 3: pillola che alla pressione stringe gli angoli (molla veloce), con il
/// velo dello stato premuto. Gli angoli sono continui (supercerchi).
struct M3ButtonStyle: ButtonStyle {
    var kind: M3ButtonKind = .tonal
    var size: M3ButtonSize = .s
    var wide = false

    func makeBody(configuration: Configuration) -> some View {
        M3ButtonBody(configuration: configuration, kind: kind, size: size, wide: wide)
    }
}

private struct M3ButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: M3ButtonKind
    let size: M3ButtonSize
    let wide: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let radius = pressed ? size.pressedRadius : size.height / 2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .labelStyle(M3ButtonLabelStyle(iconSize: size.iconSize))
            .font(.m3(size.fontSize, weight: 600))
            .tracking(0.1)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .text || kind == .dangerText ? 12 : size.padding)
            .frame(minWidth: 48, maxWidth: wide ? .infinity : nil, minHeight: size.height)
            .background {
                ZStack {
                    shape.fill(background)
                    if kind == .outlined {
                        shape.strokeBorder(Theme.outlineVariant, lineWidth: 1)
                    }
                    shape.fill(foreground.opacity(pressed ? 0.12 : (hovering ? 0.08 : 0)))
                }
                .shadow(color: kind == .elevated && isEnabled ? Theme.shadow.opacity(0.18) : .clear, radius: 2, y: 1)
            }
            .contentShape(shape)
            .animation(Motion.spatialFast, value: pressed)
            .animation(Motion.effects, value: isEnabled)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.onSurface.opacity(0.38) }
        switch kind {
        case .filled: return Theme.onPrimary
        case .tonal: return Theme.onSecondaryContainer
        case .outlined: return Theme.onSurfaceVariant
        case .text, .elevated: return Theme.primary
        case .danger: return Theme.onError
        case .dangerText: return Theme.error
        }
    }

    private var background: Color {
        switch kind {
        case .text, .outlined, .dangerText: return .clear
        default: break
        }
        guard isEnabled else { return Theme.onSurface.opacity(0.1) }
        switch kind {
        case .filled: return Theme.primary
        case .tonal: return Theme.secondaryContainer
        case .elevated: return Theme.surfaceContainerLow
        case .danger: return Theme.error
        default: return .clear
        }
    }
}

/// Icona e testo affiancati nei pulsanti (8 punti tra icona e testo).
struct M3ButtonLabelStyle: LabelStyle {
    var iconSize: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .frame(width: iconSize, height: iconSize)
            configuration.title
        }
    }
}

extension ButtonStyle where Self == M3ButtonStyle {
    static func m3(_ kind: M3ButtonKind = .tonal, size: M3ButtonSize = .s, wide: Bool = false) -> M3ButtonStyle {
        M3ButtonStyle(kind: kind, size: size, wide: wide)
    }
}

// MARK: - Pulsanti a icona

enum M3IconButtonKind {
    case standard, filled, tonal, outlined, selected, danger
}

/// Pulsante a icona di Material 3 (40 punti): alla pressione il cerchio diventa un quadrato
/// con gli angoli continui.
struct M3IconButtonStyle: ButtonStyle {
    var kind: M3IconButtonKind = .standard
    var size: CGFloat = 40

    func makeBody(configuration: Configuration) -> some View {
        M3IconButtonBody(configuration: configuration, kind: kind, size: size)
    }
}

private struct M3IconButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: M3IconButtonKind
    let size: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let radius = pressed ? 10 : (kind == .selected ? Theme.radii.m : size / 2)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .labelStyle(.iconOnly)
            .font(.m3(14, weight: 600))
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background {
                ZStack {
                    shape.fill(background)
                    if kind == .outlined { shape.strokeBorder(Theme.outlineVariant, lineWidth: 1) }
                    shape.fill(foreground.opacity(pressed ? 0.12 : (hovering ? 0.08 : 0)))
                }
            }
            .contentShape(shape)
            .animation(Motion.spatialFast, value: pressed)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        guard isEnabled else { return Theme.onSurface.opacity(0.38) }
        switch kind {
        case .filled: return Theme.onPrimary
        case .tonal, .selected: return Theme.onSecondaryContainer
        case .danger: return Theme.error
        default: return Theme.onSurfaceVariant
        }
    }

    private var background: Color {
        switch kind {
        case .filled: Theme.primary
        case .tonal, .selected: Theme.secondaryContainer
        default: .clear
        }
    }
}

extension ButtonStyle where Self == M3IconButtonStyle {
    static func m3Icon(_ kind: M3IconButtonKind = .standard, size: CGFloat = 40) -> M3IconButtonStyle {
        M3IconButtonStyle(kind: kind, size: size)
    }
}

/// Pulsante a icona con un'icona di Material Symbols.
struct IconButton: View {
    let icon: String
    let label: String
    var kind: M3IconButtonKind = .standard
    var size: CGFloat = 40
    var iconSize: CGFloat?
    let action: () -> Void

    init(_ icon: String, label: String, kind: M3IconButtonKind = .standard, size: CGFloat = 40,
         iconSize: CGFloat? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.kind = kind
        self.size = size
        self.iconSize = iconSize
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Icon(icon, size: iconSize ?? (size <= 32 ? 20 : 24))
        }
        .buttonStyle(.m3Icon(kind, size: size))
        .accessibilityLabel(label)
        .help(label)
    }
}

// MARK: - Pulsante d'azione flottante

/// FAB di Material 3 (56 punti, contenitore primario, angoli `--r-l` che si stringono premendo).
struct FABStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: configuration.isPressed ? Theme.radii.m : Theme.radii.l, style: .continuous)
        configuration.label
            .labelStyle(M3ButtonLabelStyle(iconSize: 24))
            .font(.m3(16, weight: 600))
            .foregroundStyle(Theme.onPrimaryContainer)
            .padding(.horizontal, 16)
            .frame(minWidth: 56, minHeight: 56)
            .background {
                shape.fill(Theme.primaryContainer)
                    .overlay(shape.fill(Theme.onPrimaryContainer.opacity(configuration.isPressed ? 0.12 : 0)))
                    .shadow(color: Theme.shadow.opacity(0.22), radius: 3, y: 1)
                    .shadow(color: Theme.shadow.opacity(0.1), radius: 8, y: 4)
            }
            .contentShape(shape)
            .animation(Motion.spatialFast, value: configuration.isPressed)
    }
}

struct FAB: View {
    let icon: String
    let label: String
    var text: String?
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            if let text {
                Label { Text(text) } icon: { Icon(icon) }
            } else {
                Icon(icon)
            }
        }
        .buttonStyle(FABStyle())
        .accessibilityLabel(label)
        .help(label)
        .transition(.scale(scale: 0.2).combined(with: .opacity))
    }
}

// MARK: - Gruppi di pulsanti collegati

/// Gruppo di pulsanti collegati (sostituisce i controlli segmentati): il pulsante scelto
/// diventa una pillola piena, quello premuto stringe gli angoli interni.
struct SegmentedButtons<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String, icon: String?)]
    /// Della larghezza del contenuto (non dell'intera riga).
    var compact = false
    /// Solo icone.
    var iconsOnly = false
    var height: CGFloat = 40
    var selectedColor: Color?
    var selectedForeground: Color?
    var background: Color?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                SegmentButton(
                    title: option.title, icon: option.icon, selected: option.value == selection,
                    position: options.count == 1 ? .only : (index == 0 ? .first : (index == options.count - 1 ? .last : .middle)),
                    compact: compact, iconsOnly: iconsOnly, height: height,
                    selectedColor: selectedColor, selectedForeground: selectedForeground, background: background
                ) {
                    guard selection != option.value else { return }
                    Haptics.selection()
                    withAnimation(Motion.spatialFast) { selection = option.value }
                }
            }
        }
        .frame(maxWidth: compact ? nil : .infinity)
    }
}

private struct SegmentButton: View {
    enum Position { case first, middle, last, only }

    let title: String
    let icon: String?
    let selected: Bool
    let position: Position
    let compact: Bool
    let iconsOnly: Bool
    let height: CGFloat
    let selectedColor: Color?
    let selectedForeground: Color?
    let background: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if iconsOnly, let icon {
                    Icon(icon, size: 20)
                } else {
                    if selected && !compact {
                        Icon("check", size: 20)
                            .transition(.scale.combined(with: .opacity))
                    } else if let icon {
                        Icon(icon, size: 20)
                    }
                    Text(title)
                        .lineLimit(1)
                }
            }
            .font(.m3(14, weight: selected ? 650 : 550))
            .padding(.horizontal, iconsOnly ? 14 : (compact ? 16 : 12))
            .frame(minWidth: compact ? 48 : 0, maxWidth: compact ? nil : .infinity)
            .frame(height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(SegmentStyle(selected: selected, position: position, height: height,
                                  selectedColor: selectedColor, selectedForeground: selectedForeground,
                                  background: background))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(title)
        .help(iconsOnly ? title : "")
    }

    private struct SegmentStyle: ButtonStyle {
        let selected: Bool
        let position: Position
        let height: CGFloat
        let selectedColor: Color?
        let selectedForeground: Color?
        let background: Color?

        func makeBody(configuration: Configuration) -> some View {
            let full = height / 2
            let inner: CGFloat = configuration.isPressed && !selected ? 4 : 8
            let leading = selected || position == .first || position == .only ? full : inner
            let trailing = selected || position == .last || position == .only ? full : inner
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: leading, bottomLeadingRadius: leading,
                bottomTrailingRadius: trailing, topTrailingRadius: trailing, style: .continuous)
            let foreground = selected ? (selectedForeground ?? Theme.onPrimary) : Theme.onSurfaceVariant
            configuration.label
                .foregroundStyle(foreground)
                .background {
                    shape.fill(selected ? (selectedColor ?? Theme.primary) : (background ?? Theme.surfaceContainerHigh))
                        .overlay(shape.fill(foreground.opacity(configuration.isPressed ? 0.12 : 0)))
                }
                .contentShape(shape)
                .animation(Motion.spatialFast, value: configuration.isPressed)
                .animation(Motion.spatialFast, value: selected)
        }
    }
}

// MARK: - Chip

/// Chip di filtro: quando è scelto mostra il segno di spunta al posto dell'icona.
struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    var trailingIcon: String?
    let action: () -> Void

    init(title: String, icon: String? = nil, isSelected: Bool, trailingIcon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.trailingIcon = trailingIcon
        self.action = action
    }

    var body: some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 8) {
                if isSelected && trailingIcon == nil {
                    Icon("check", size: 18)
                        .transition(.scale.combined(with: .opacity))
                } else if let icon {
                    Icon(icon, size: 18)
                }
                Text(title)
                    .lineLimit(1)
                if let trailingIcon {
                    Icon(trailingIcon, size: 18)
                }
            }
            .font(.m3(14, weight: 550))
            .padding(.leading, (isSelected && trailingIcon == nil) || icon != nil ? 8 : 16)
            .padding(.trailing, trailingIcon != nil ? 8 : 16)
            .frame(height: 32)
        }
        .buttonStyle(ChipStyle(selected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ChipStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: configuration.isPressed ? Theme.radii.m : Theme.radii.s, style: .continuous)
        let foreground = selected ? Theme.onSecondaryContainer : Theme.onSurfaceVariant
        configuration.label
            .foregroundStyle(foreground)
            .background {
                ZStack {
                    shape.fill(selected ? Theme.secondaryContainer : .clear)
                    if !selected { shape.strokeBorder(Theme.outlineVariant, lineWidth: 1) }
                    shape.fill(foreground.opacity(configuration.isPressed ? 0.12 : 0))
                }
            }
            .contentShape(shape)
            .animation(Motion.spatialFast, value: configuration.isPressed)
            .animation(Motion.effects, value: selected)
    }
}

/// Etichetta su una riga (es. "Verifica"): resta sempre su una riga e se lo spazio non basta
/// usa la versione abbreviata (`short`).
struct Pill: View {
    let text: String
    var short: String?
    var color: Color = Theme.accent
    var filled = false
    var bold = false
    var small = false

    var body: some View {
        if let short {
            ViewThatFits(in: .horizontal) {
                label(text)
                label(short)
            }
            .accessibilityElement()
            .accessibilityLabel(text)
        } else {
            label(text)
        }
    }

    private func label(_ string: String) -> some View {
        Text(string)
            .font(.m3(small ? 11 : 12, weight: bold ? 750 : 650))
            .tracking(0.3)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, small ? 6 : 8)
            .frame(height: small ? 20 : 22)
            .background(filled ? color : color.opacity(0.15), in: .rect(cornerRadius: Theme.radii.s, style: .continuous))
            .foregroundStyle(filled ? Theme.surface : color)
    }
}

/// Numero rosso su un'icona (badge).
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.m3(11, weight: 650))
            .monospacedDigit()
            .foregroundStyle(Theme.onError)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(Theme.error, in: .capsule)
    }
}

// MARK: - Interruttori

/// Interruttore di Material 3: traccia 52 × 32, pallino che cresce da acceso con la spunta.
struct M3ToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        M3Switch(configuration: configuration)
    }
}

private struct M3Switch: View {
    let configuration: ToggleStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled
    @State private var pressed = false

    var body: some View {
        let on = configuration.isOn
        Button {
            Haptics.selection()
            withAnimation(Motion.spatialFast) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 16) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                track(on: on)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressReportingStyle(pressed: $pressed))
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }

    private func track(on: Bool) -> some View {
        let thumb: CGFloat = pressed ? 28 : (on ? 24 : 16)
        return ZStack {
            Capsule(style: .continuous)
                .fill(on ? Theme.primary : Theme.surfaceContainerHighest)
                .overlay {
                    if !on { Capsule(style: .continuous).strokeBorder(Theme.outline, lineWidth: 2) }
                }
            Circle()
                .fill(on ? Theme.onPrimary : Theme.outline)
                .frame(width: thumb, height: thumb)
                .overlay {
                    Icon("check", size: 16)
                        .foregroundStyle(Theme.onPrimaryContainer)
                        .opacity(on ? 1 : 0)
                        .scaleEffect(on ? 1 : 0.4)
                }
                .offset(x: on ? 10 : -10)
        }
        .frame(width: 52, height: 32)
        .opacity(isEnabled ? 1 : 0.38)
        .animation(Motion.spatialFast, value: on)
        .animation(Motion.spatialFast, value: pressed)
    }
}

/// Stile che non cambia l'aspetto ma riferisce se il pulsante è premuto.
struct PressReportingStyle: ButtonStyle {
    @Binding var pressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, value in pressed = value }
    }
}

extension ToggleStyle where Self == M3ToggleStyle {
    static var m3: M3ToggleStyle { M3ToggleStyle() }
}

// MARK: - Contatore

/// Contatore con i pulsanti tonali − e +.
struct M3Stepper<Value: Strideable & Comparable>: View {
    @Binding var value: Value
    let range: ClosedRange<Value>
    var step: Value.Stride
    let format: (Value) -> String

    var body: some View {
        HStack(spacing: 6) {
            IconButton("minus", label: "Diminuisci", kind: .tonal, size: 32) {
                Haptics.selection()
                value = max(range.lowerBound, value.advanced(by: -step))
            }
            .disabled(value <= range.lowerBound)
            Text(format(value))
                .font(.numeral(16))
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 44)
                .contentTransition(.numericText())
            IconButton("plus", label: "Aumenta", kind: .tonal, size: 32) {
                Haptics.selection()
                value = min(range.upperBound, value.advanced(by: step))
            }
            .disabled(value >= range.upperBound)
        }
        .animation(Motion.effects, value: value)
    }
}

// MARK: - Campi di testo

/// Campo di testo pieno di Material 3 (angoli `--r-l`, bordo primario quando è attivo).
struct M3TextFieldStyle: TextFieldStyle {
    var icon: String?
    var focused = false
    var minHeight: CGFloat = 56

    func _body(configuration: TextField<Self._Label>) -> some View {
        let shape = RoundedRectangle(cornerRadius: focused ? Theme.radii.m : Theme.radii.l, style: .continuous)
        HStack(spacing: 12) {
            if let icon {
                Icon(icon)
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
            configuration
                .textFieldStyle(.plain)
                .font(.m3(16))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: minHeight)
        .background(Theme.surfaceContainerHighest, in: shape)
        .overlay(shape.strokeBorder(Theme.primary, lineWidth: focused ? 2 : 0))
        .animation(Motion.spatial, value: focused)
    }
}

/// Barra di ricerca (56 punti, angoli pieni).
struct M3SearchBar: View {
    @Binding var text: String
    let prompt: String
    var height: CGFloat = 56
    var focus: FocusState<Bool>.Binding?
    var onSubmit: () -> Void = {}

    @FocusState private var ownFocus: Bool

    var body: some View {
        HStack(spacing: 12) {
            Icon("search")
                .foregroundStyle(Theme.onSurfaceVariant)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.m3(16))
                .foregroundStyle(Theme.ink)
                .focused(focus ?? $ownFocus)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .autocorrectionDisabled()
            if !text.isEmpty {
                IconButton("x", label: "Cancella", size: 32) { text = "" }
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: height)
        .background(Theme.surfaceContainerHigh, in: .rect(cornerRadius: height / 2, style: .continuous))
        .contentShape(.rect)
        .onTapGesture { (focus ?? $ownFocus).wrappedValue = true }
    }
}

// MARK: - Sezioni comprimibili

/// Freccia in un cerchio che ruota aprendo e chiudendo una sezione.
struct Chevron: View {
    let collapsed: Bool
    /// Ruota verso l'alto da aperta (invece che verso sinistra da chiusa).
    var rotateUp = false

    var body: some View {
        Icon("chevronDown", size: 20)
            .foregroundStyle(Theme.onSurfaceVariant)
            .rotationEffect(.degrees(rotateUp ? (collapsed ? 0 : 180) : (collapsed ? -90 : 0)))
            .frame(width: 32, height: 32)
            .background(Theme.surfaceContainerHighest, in: .circle)
            .animation(Motion.spatial, value: collapsed)
    }
}

/// Stile per le intestazioni toccabili: nessuna attenuazione alla pressione.
struct HeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Velo dello stato premuto per card e righe toccabili: gli angoli si stringono e compare un
/// velo leggero (come `button.card:active` nella versione web).
struct PressableStyle: ButtonStyle {
    var radius: CGFloat?
    var pressedRadius: CGFloat?
    var overlay: Color?

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, radius: radius, pressedRadius: pressedRadius, overlay: overlay)
    }
}

private struct PressableBody: View {
    let configuration: ButtonStyle.Configuration
    let radius: CGFloat?
    let pressedRadius: CGFloat?
    let overlay: Color?
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let pressed = configuration.isPressed && isEnabled
        let shape = RoundedRectangle(cornerRadius: pressed ? (pressedRadius ?? Theme.radii.m) : (radius ?? Theme.radii.li),
                                     style: .continuous)
        configuration.label
            .clipShape(shape)
            .overlay(shape.fill((overlay ?? Theme.onSurface).opacity(pressed ? 0.1 : (hovering ? 0.05 : 0))).allowsHitTesting(false))
            .contentShape(shape)
            .animation(Motion.spatialFast, value: pressed)
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
    static func pressable(radius: CGFloat?, pressed: CGFloat? = nil) -> PressableStyle {
        PressableStyle(radius: radius, pressedRadius: pressed)
    }
}

// MARK: - Collegamenti e date

/// Pulsante come collegamento (testo nel colore primario, 14 punti).
struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.m3(14, weight: 600))
            .foregroundStyle(Theme.primary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// Campo con una data (pillola `surface-container-high`): toccandolo si apre il selettore di sistema.
struct DateField: View {
    @Binding var date: Date
    var range: ClosedRange<Date>?

    var body: some View {
        ZStack {
            Text(date.longDay)
                .font(.m3(15))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Theme.surfaceContainerHigh, in: .capsule)
            // Il selettore di sistema sta sopra, quasi invisibile: lo apre un tocco sul campo.
            Group {
                if let range {
                    DatePicker("Giorno", selection: $date, in: range, displayedComponents: .date)
                } else {
                    DatePicker("Giorno", selection: $date, displayedComponents: .date)
                }
            }
            .labelsHidden()
            .environment(\.locale, Locale(identifier: "it_IT"))
            .frame(maxWidth: .infinity, minHeight: 40)
            .scaleEffect(x: 3, y: 1)
            .opacity(0.011)
            .clipped()
        }
        .accessibilityElement(children: .contain)
    }
}
