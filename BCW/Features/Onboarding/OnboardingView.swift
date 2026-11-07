import SwiftUI
import UIKit

/// I passaggi dell'introduzione, con la forma e l'icona in cima a ognuno.
enum OnboardingStep: Int, CaseIterable {
    case welcome, colors, interface, feel, dashboard, features, classeviva, bcw, timetable, done

    var shape: MaterialShapeName {
        switch self {
        case .welcome: .cookie12Sided
        case .colors: .flower
        case .interface: .softBurst
        case .feel: .clover8Leaf
        case .dashboard: .gem
        case .features: .puffy
        case .classeviva: .cookie9Sided
        case .bcw: .sunny
        case .timetable: .cookie7Sided
        case .done: .verySunny
        }
    }

    var icon: String? {
        switch self {
        case .welcome: nil
        case .colors: "palette"
        case .interface: "sparkles"
        case .feel: "corners"
        case .dashboard: "dashboard"
        case .features: "tune"
        case .classeviva: "graduationCap"
        case .bcw: "cloud"
        case .timetable: "wand"
        case .done: "check"
        }
    }

    /// Quanto è grande la forma: più piccola dove sotto c'è molto da leggere.
    var heroSize: CGFloat {
        switch self {
        case .welcome, .done: 196
        case .colors: 104
        default: 84
        }
    }
}

/// L'introduzione a tutta pagina: una forma che si trasforma da un passaggio all'altro e, sotto, il
/// contenuto che scorre di lato (asse condiviso di Material 3).
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step: OnboardingStep
    /// Verso del passaggio, fissato un giro prima del cambio (vedi `DaySwipe.go`).
    @State private var forward = true
    @State private var keyboardVisible = false
    @State private var skipFrame = CGRect.zero

    init() {
        var initial = OnboardingStep.welcome
        #if DEBUG
        // Per le prove: `-BCWOnboardingStep N` parte da quel passaggio.
        if let start = OnboardingStep(rawValue: UserDefaults.standard.integer(forKey: "BCWOnboardingStep")) {
            initial = start
            if start.rawValue > OnboardingStep.colors.rawValue { ThemeStore.shared.isMonochrome = false }
        }
        #endif
        _step = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if !keyboardVisible {
                OnboardingHero(step: step)
                    .padding(.top, step == .welcome ? 24 : 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
            page
                .id(step)
                .transition(.sharedAxisX(forward: forward, distance: 64))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        // Copre tutto: sotto può esserci già l'app.
        .contentShape(.rect)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(Motion.spatial) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(Motion.spatial) { keyboardVisible = false }
        }
    }

    // MARK: Barra in alto

    @ViewBuilder
    private var topBar: some View {
        if step != .welcome && step != .done {
            HStack(spacing: 8) {
                IconButton("arrowBack", label: "Indietro") { go(by: -1) }
                WavyProgress(value: Double(steps.firstIndex(of: step) ?? step.rawValue), total: Double(max(1, steps.count - 1)))
                    .animation(Motion.spatial, value: step)
                    .padding(.horizontal, 4)
                Button("Salta") { skip(from: skipFrame) }
                    .buttonStyle(.m3(.text, size: .xs))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { skipFrame = $0 }
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            Color.clear.frame(height: 8)
        }
    }

    // MARK: Pagine

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: OnboardingWelcomePage(next: { go(by: 1) }, skip: skip)
        case .colors: OnboardingColorsPage(next: { go(by: 1) })
        case .interface: OnboardingInterfacePage(next: { go(by: 1) })
        case .feel: OnboardingFeelPage(next: { go(by: 1) })
        case .dashboard: OnboardingDashboardPage(next: { go(by: 1) })
        case .features: OnboardingFeaturesPage(next: { go(by: 1) })
        case .classeviva: OnboardingClassevivaPage(next: { go(by: 1) })
        case .bcw: OnboardingBCWPage(next: { go(by: 1) })
        case .timetable: OnboardingTimetablePage(next: { go(by: 1) })
        case .done: OnboardingDonePage { Onboarding.shared.finish(from: $0) }
        }
    }

    /// I passaggi che si vedono: l'orario dalle lezioni solo con la scheda Orario (scelta in "Cosa ti
    /// serve?") e con un account da cui leggere le lezioni.
    private var steps: [OnboardingStep] {
        OnboardingStep.allCases.filter { candidate in
            candidate != .timetable || (model.preferences.showsTimetableTab && model.phase == .signedIn)
        }
    }

    private func go(by delta: Int) {
        let target = delta > 0 ? steps.first { $0.rawValue > step.rawValue } : steps.last { $0.rawValue < step.rawValue }
        guard let target else { return }
        Haptics.selection()
        forward = delta > 0
        hideKeyboard()
        DispatchQueue.main.async {
            withAnimation(Motion.spatialSlow) { step = target }
        }
    }

    private func skip(from frame: CGRect) {
        hideKeyboard()
        Onboarding.shared.finish(from: frame == .zero ? nil : CGPoint(x: frame.midX, y: frame.midY))
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Forma in cima

/// La forma di ogni passaggio, che si trasforma nella successiva e ruota lentamente, con l'icona al
/// centro e altre due forme più piccole attorno. Nell'accoglienza al centro c'è il logo.
private struct OnboardingHero: View {
    let step: OnboardingStep
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le due forme piccole: forma e posizione (in frazioni della misura) per ogni passaggio.
    private var satellites: [(shape: MaterialShapeName, x: CGFloat, y: CGFloat, size: CGFloat, fill: Color)] {
        let index = step.rawValue
        let a: [MaterialShapeName] = [.pill, .gem, .cookie6Sided, .pentagon, .sunny, .clover4Leaf, .puffyDiamond, .arch, .pill, .flower]
        let b: [MaterialShapeName] = [.cookie9Sided, .pill, .sunny, .gem, .puffy, .softBoom, .pill, .cookie7Sided, .clover4Leaf, .clover8Leaf]
        let side: CGFloat = index.isMultiple(of: 2) ? 1 : -1
        // Con la forma grande più vicine e più piccole: non devono toccare i bordi dello schermo.
        if step.heroSize >= 190 {
            return [(a[index], 0.56 * side, -0.42, 0.24, Theme.secondaryContainer),
                    (b[index], -0.6 * side, 0.36, 0.3, Theme.tertiaryContainer)]
        }
        return [(a[index], 0.62 * side, -0.42, 0.3, Theme.secondaryContainer),
                (b[index], -0.66 * side, 0.34, 0.38, Theme.tertiaryContainer)]
    }

    var body: some View {
        let size = step.heroSize
        ZStack {
            ForEach(Array(satellites.enumerated()), id: \.offset) { _, item in
                MorphShape(item.shape)
                    .fill(item.fill)
                    .frame(width: size * item.size, height: size * item.size)
                    .rotationEffect(.degrees(turning ? -360 : 0))
                    .animation(.linear(duration: 26).repeatForever(autoreverses: false), value: turning)
                    .offset(x: size * item.x, y: size * item.y)
            }
            MorphShape(step.shape)
                .fill(Theme.primaryContainer)
                .rotationEffect(.degrees(turning ? 360 : 0))
                .animation(.linear(duration: 40).repeatForever(autoreverses: false), value: turning)
                .frame(width: size, height: size)
            if let icon = step.icon {
                Icon(icon, size: size * 0.4)
                    .foregroundStyle(Theme.onPrimaryContainer)
                    .id(icon)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                BCWLogo(size: 46, stacked: true)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(height: size + 8)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion, ThemeStore.shared.motion != .reduced else { return }
            turning = true
        }
    }
}

// MARK: - Comparsa a scaglioni

/// Gli elementi di una pagina salgono e compaiono uno dopo l'altro.
private struct Staggered: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 22)
            .scaleEffect(shown ? 1 : 0.97)
            .onAppear {
                withAnimation(Motion.spatialSlow.delay(0.05 + Double(index) * 0.055)) { shown = true }
            }
    }
}

private extension View {
    func staggered(_ index: Int) -> some View { modifier(Staggered(index: index)) }
}

// MARK: - Parti comuni

/// Titolo, spiegazione e contenuto che scorrono, con le azioni ferme in fondo.
private struct OnboardingPage<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.m3(32, weight: 500, rounded: true))
                            .tracking(-0.3)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle)
                            .font(.m3(15))
                            .foregroundStyle(Theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .staggered(0)
                    content()
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            VStack(spacing: 8) {
                actions()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }
}

/// Il pulsante principale: "Continua" con la freccia.
private struct NextButton: View {
    var title = "Continua"
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                Icon("arrowBack", size: 22)
                    .rotationEffect(.degrees(180))
                    .accessibilityHidden(true)
            }
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading { LoadingIndicator(size: 24, color: Theme.onPrimary) }
            }
        }
        .buttonStyle(.m3(.filled, size: .m, wide: true))
        .accessibilityLabel(title)
    }
}

// MARK: - Benvenuto

private struct OnboardingWelcomePage: View {
    let next: () -> Void
    let skip: (CGRect) -> Void
    @State private var skipFrame = CGRect.zero

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            VStack(spacing: 12) {
                Text("Ciao! Questa è BCW")
                    .font(.m3(36, weight: 500, rounded: true))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .staggered(0)
                Text("Better ClasseViVa: voti, compiti, orario e comunicazioni di Classeviva, in un'app fatta su misura per te.")
                    .font(.m3(16))
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggered(1)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 16)
            VStack(spacing: 8) {
                NextButton(title: "Inizia", action: next)
                    .staggered(2)
                Button("Salta introduzione") { skip(skipFrame) }
                    .buttonStyle(.m3(.text, size: .m, wide: true))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { skipFrame = $0 }
                    .staggered(3)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        // Prepara i colori: il primo calcolo carica JavaScriptCore e farebbe aspettare il primo tocco.
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            OnboardingColorsPage.prepare()
        }
    }
}

// MARK: - Colori

private struct OnboardingColorsPage: View {
    @Environment(\.colorScheme) private var colorScheme
    let next: () -> Void
    /// Le forme dei campioni: ogni colore la sua.
    private static let shapes: [MaterialShapeName] = [.cookie9Sided, .sunny, .clover4Leaf, .cookie6Sided, .gem,
                                                      .softBurst, .flower, .puffy, .cookie12Sided, .pentagon]
    @State private var chosen = !ThemeStore.shared.isMonochrome
    @State private var pickingColor = false
    @State private var customColor: Color = .blue
    @State private var customFrame = CGRect.zero

    static func prepare() {
        for preset in accentPresets {
            _ = ThemeStore.shared.swatch(preset.hex, dark: false)
            _ = ThemeStore.shared.swatch(preset.hex, dark: true)
        }
        ThemeStore.shared.prepareScheme(accents: accentPresets.map(\.hex))
    }

    var body: some View {
        let theme = ThemeStore.shared
        let accent = ThemeStore.normalize(theme.accentColor) ?? defaultAccent
        let isCustom = !accentPresets.contains { $0.hex == accent }
        OnboardingPage(title: "Scegli i tuoi colori",
                       subtitle: "Da qui comincia tutto: l'app prende il colore che tocchi. Potrai cambiarlo quando vuoi in Impostazioni › Aspetto.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 6)], alignment: .center, spacing: 14) {
                ForEach(Array(accentPresets.enumerated()), id: \.element.hex) { index, preset in
                    ThemeSwatchButton(title: preset.name.replacingOccurrences(of: " (BCW)", with: ""),
                                      shape: Self.shapes[index % Self.shapes.count],
                                      colors: theme.swatch(preset.hex, dark: colorScheme == .dark),
                                      selected: chosen && preset.hex == accent) { frame in
                        choose(preset.hex, from: frame)
                    }
                    .staggered(index + 1)
                }
                ThemeSwatchButton(title: "Altro", shape: .arch, colors: nil, selected: chosen && isCustom) { frame in
                    customFrame = frame
                    pickingColor = true
                }
                .staggered(accentPresets.count + 1)
            }
        } actions: {
            NextButton(action: next)
                .disabled(!chosen)
        }
        .sheet(isPresented: $pickingColor, onDismiss: chooseCustom) {
            SystemColorPicker(color: $customColor)
                .ignoresSafeArea()
        }
        .onAppear {
            if chosen { customColor = Color(platformColor: PlatformColor(hex: Int(accent.dropFirst(), radix: 16) ?? 0)) }
        }
    }

    private func choose(_ hex: String, from frame: CGRect) {
        ThemeReveal.perform(from: CGPoint(x: frame.midX, y: frame.midY)) {
            ThemeStore.shared.isMonochrome = false
            ThemeStore.shared.accentColor = hex
            chosen = true
        }
    }

    private func chooseCustom() {
        guard let hex = customColor.hexString else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { choose(hex, from: customFrame) }
    }
}

/// Un colore del tema: una forma di M3 Expressive con il primario sopra, il secondario e il terziario
/// sotto. Il cerchio dei colori parte da qui.
private struct ThemeSwatchButton: View {
    let title: String
    let shape: MaterialShapeName
    /// Primario, secondario, terziario; `nil` = arcobaleno (un colore qualsiasi).
    let colors: [Color]?
    let selected: Bool
    let action: (CGRect) -> Void
    @State private var frame = CGRect.zero

    var body: some View {
        Button {
            action(frame)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    swatch
                        .clipShape(MaterialShape(shape))
                        .frame(width: selected ? 60 : 54, height: selected ? 60 : 54)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
                    if selected {
                        Icon("check", size: 20)
                            .foregroundStyle(Theme.ink)
                            .frame(width: 28, height: 28)
                            .background(Theme.surfaceContainerLowest, in: .circle)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .frame(width: 62, height: 62)
                Text(title)
                    .font(.m3(12, weight: selected ? 700 : 500))
                    .foregroundStyle(selected ? Theme.ink : Theme.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(SwatchPressStyle())
        .animation(Motion.spatial, value: selected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var swatch: some View {
        if let colors, colors.count == 3 {
            VStack(spacing: 0) {
                colors[0]
                HStack(spacing: 0) {
                    colors[1]
                    colors[2]
                }
            }
        } else {
            AngularGradient(colors: (0..<9).map { Theme.subject([0, 3, 6, 1, 9, 5, 2, 4, 0][$0]) }, center: .center)
        }
    }

    private struct SwatchPressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(Motion.spatialFast, value: configuration.isPressed)
        }
    }
}

// MARK: - Interfaccia

private struct OnboardingInterfacePage: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void
    @State private var modeFrame = CGRect.zero

    var body: some View {
        OnboardingPage(title: "Com'è la tua app?",
                       subtitle: "Chiara o scura, e con quale stile. Si cambia anche dopo, in Impostazioni › Aspetto.") {
            VStack(alignment: .leading, spacing: 8) {
                ListHeader("Tema")
                ConnectedButtonGroup(selection: appearance, values: AppearanceMode.allCases, height: 64) { mode, _ in
                    VStack(spacing: 2) {
                        Icon(icon(mode), size: 22)
                        Text(mode.title)
                            .font(.m3(13, weight: 600))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(mode.title)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { modeFrame = $0 }
            }
            .staggered(1)

            VStack(alignment: .leading, spacing: 8) {
                ListHeader("Stile dell'interfaccia")
                HStack(spacing: 10) {
                    PreviewChoice(title: "Material 3", subtitle: "Espressivo", selected: !ThemeStore.shared.liquidGlass) {
                        setGlass(false)
                    } preview: {
                        InterfaceStylePreview(isGlass: false)
                    }
                    PreviewChoice(title: "Liquid Glass", subtitle: "Vetro nativo", selected: ThemeStore.shared.liquidGlass) {
                        setGlass(true)
                    } preview: {
                        InterfaceStylePreview(isGlass: true)
                    }
                }
            }
            .staggered(2)
        } actions: {
            NextButton(action: next)
        }
    }

    private func icon(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: "contrast"
        case .light: "sun"
        case .dark: "circleFill"
        }
    }

    /// Anche chiaro e scuro arrivano con il cerchio, dal pulsante toccato.
    private var appearance: Binding<AppearanceMode> {
        Binding { model.preferences.appearance } set: { mode in
            let index = AppearanceMode.allCases.firstIndex(of: mode) ?? 0
            let width = modeFrame.width / CGFloat(AppearanceMode.allCases.count)
            ThemeReveal.perform(from: CGPoint(x: modeFrame.minX + width * (CGFloat(index) + 0.5), y: modeFrame.midY)) {
                model.preferences.appearance = mode
            }
        }
    }

    private func setGlass(_ glass: Bool) {
        guard ThemeStore.shared.liquidGlass != glass else { return }
        Haptics.selection()
        withAnimation(Motion.spatial) { ThemeStore.shared.liquidGlass = glass }
    }
}

/// Una scelta tra due, in una card grande con un'anteprima stilizzata.
private struct PreviewChoice<Preview: View>: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                preview()
                    .frame(height: 124)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surfaceContainerHigh, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
                    .clipShape(.rect(cornerRadius: Theme.radii.l, style: .continuous))
                // Titolo e sottotitolo centrati sotto l'anteprima (richiesta dell'utente).
                VStack(alignment: .center, spacing: 2) {
                    Text(title)
                        .font(.m3(15, weight: 650))
                        .foregroundStyle(selected ? Theme.onSecondaryContainer : Theme.ink)
                    Text(subtitle)
                        .font(.m3(12))
                        .foregroundStyle(selected ? Theme.onSecondaryContainer.opacity(0.85) : Theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 4)
            }
            .padding(10)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(selected ? Theme.secondaryContainer : Theme.surfaceContainerLow,
                        in: .rect(cornerRadius: Theme.radii.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radii.xl, style: .continuous)
                    .strokeBorder(selected ? Theme.primary : .clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Icon("checkCircleFill", size: 24)
                        .foregroundStyle(Theme.primary)
                        .background(Theme.surfaceContainerLowest, in: .circle)
                        .padding(16)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .contentShape(.rect(cornerRadius: Theme.radii.xl))
        }
        .buttonStyle(.pressable(radius: Theme.radii.xl, pressed: Theme.radii.l))
        .animation(Motion.spatial, value: selected)
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Anteprima di uno stile dell'interfaccia: righe finte e, in basso, la barra (pillola piena o vetro).
private struct InterfaceStylePreview: View {
    let isGlass: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.onSurfaceVariant.opacity(0.35)).frame(width: 52, height: 8)
                RoundedRectangle(cornerRadius: 8).fill(Theme.primaryContainer).frame(height: 30)
                RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceContainerHighest).frame(height: 30)
                RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceContainerHighest).frame(height: 30)
            }
            .padding(10)
            .frame(maxHeight: .infinity, alignment: .top)
            if isGlass {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle().fill(index == 0 ? Theme.primary : Theme.onSurfaceVariant.opacity(0.55)).frame(width: 12, height: 12)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 8)
            } else {
                HStack(spacing: 6) {
                    Capsule().fill(Theme.primary).frame(width: 30, height: 20)
                    ForEach(0..<2, id: \.self) { _ in
                        Capsule().fill(Theme.onSurfaceVariant.opacity(0.45)).frame(width: 16, height: 6)
                    }
                }
                .padding(.horizontal, 5)
                .frame(height: 30)
                .background {
                    Capsule().fill(Theme.surfaceContainerLowest)
                        .shadow(color: Theme.shadow.opacity(0.2), radius: 5, y: 2)
                }
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Forme e movimento

private struct OnboardingFeelPage: View {
    let next: () -> Void

    var body: some View {
        @Bindable var theme = ThemeStore.shared
        OnboardingPage(title: "Forme e movimento",
                       subtitle: "Quanto arrotondare, come muovere e con che accostamenti di colore. L'anteprima cambia mentre scegli.") {
            ListGroup {
                ThemePreview()
            }
            .staggered(1)
            ListGroup {
                SelectRow("Angoli", icon: "corners", selection: animated($theme.corners),
                          options: CornerStyle.allCases.map { ($0, $0.title, nil) })
                SelectRow("Animazioni", icon: "motion", selection: $theme.motion,
                          options: MotionStyle.allCases.map { ($0, $0.title, nil) })
                SelectRow("Stile dei colori", subtitle: theme.colorStyle.subtitle, icon: "colorStyle",
                          selection: animated($theme.colorStyle), options: ColorStyle.allCases.map { ($0, $0.title, nil) })
                SelectRow("Caratteri arrotondati", icon: "textStyle", selection: $theme.roundedText,
                          options: RoundedText.allCases.map { ($0, $0.title, nil) })
            }
            .staggered(2)
        } actions: {
            NextButton(action: next)
        }
    }

    private func animated<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        binding.animation(Motion.spatial)
    }
}

// MARK: - Dashboard

private struct OnboardingDashboardPage: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void

    var body: some View {
        OnboardingPage(title: "Come vuoi la Dashboard?",
                       subtitle: "È la prima cosa che vedi: i prossimi compiti, le verifiche e gli eventi. Si cambia anche dopo, in Impostazioni › Dashboard.") {
            HStack(spacing: 10) {
                PreviewChoice(title: "Lista", subtitle: "Vista compatta", selected: model.preferences.dashboardMode == .list) {
                    choose(.list)
                } preview: {
                    DashboardModePreview(mode: .list)
                }
                PreviewChoice(title: "Calendario", subtitle: "Vista estesa", selected: model.preferences.dashboardMode == .calendar) {
                    choose(.calendar)
                } preview: {
                    DashboardModePreview(mode: .calendar)
                }
            }
            .staggered(1)
        } actions: {
            NextButton(action: next)
        }
    }

    private func choose(_ mode: DashboardMode) {
        guard model.preferences.dashboardMode != mode else { return }
        Haptics.selection()
        withAnimation(Motion.spatial) { model.preferences.dashboardMode = mode }
    }
}

/// Anteprima della Dashboard: la settimana con gli elementi del giorno, o il mese.
private struct DashboardModePreview: View {
    let mode: DashboardMode

    var body: some View {
        VStack(spacing: 6) {
            switch mode {
            case .list:
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: index == 2 ? 11 : 5, style: .continuous)
                            .fill(index == 2 ? Theme.primary : Theme.surfaceContainerHighest)
                            .frame(height: 22)
                    }
                }
                RoundedRectangle(cornerRadius: 3).fill(Theme.onSurfaceVariant.opacity(0.35)).frame(width: 44, height: 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                row(Theme.primaryContainer)
                row(Theme.surfaceContainerHighest)
                row(Theme.surfaceContainerHighest)
            case .calendar:
                VStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { week in
                        HStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { day in
                                let selected = week == 1 && day == 3
                                RoundedRectangle(cornerRadius: selected ? 8 : 3, style: .continuous)
                                    .fill(selected ? Theme.primary : Theme.surfaceContainerHighest)
                                    .frame(height: 16)
                            }
                        }
                    }
                }
                row(Theme.primaryContainer)
                row(Theme.surfaceContainerHighest)
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func row(_ fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill).frame(height: 16)
    }
}

// MARK: - Funzioni

private struct OnboardingFeaturesPage: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void
    @State private var notificationsDenied = false

    var body: some View {
        @Bindable var preferences = model.preferences
        OnboardingPage(title: "Cosa ti serve?",
                       subtitle: "Puoi tenere tutto così com'è: ogni scelta si cambia in Impostazioni.") {
            ListGroup("Orario") {
                ToggleRow("Scheda Orario", subtitle: "Il tuo orario settimanale, tra Dashboard e Voti", icon: "timetable",
                          isOn: $preferences.showsTimetableTab)
                if model.liveActivities.areActivitiesEnabled {
                    ToggleRow("Attività in diretta", subtitle: "La lezione in corso nella schermata di blocco", icon: "lockClock",
                              isOn: $preferences.liveActivities)
                }
                ToggleRow("Verifiche nell'orario", subtitle: "Segna nella lista le verifiche di Classeviva", icon: "test",
                          isOn: $preferences.timetableShowsTests)
            }
            .staggered(1)
            ListGroup("Notifiche") {
                ToggleRow("Promemoria", subtitle: "La sera prima di compiti e verifiche", icon: "bell",
                          isOn: permission($preferences.homeworkReminders))
                ToggleRow("Novità", subtitle: "Voti, comunicazioni, note e assenze", icon: "bellActive", isOn: newsBinding)
            }
            .staggered(2)
            ListGroup("Sicurezza") {
                ToggleRow("Blocca con \(BiometricLock.biometryName)", subtitle: "Ogni volta che torni nell'app", icon: "lock",
                          isOn: $preferences.useBiometrics)
            }
            .staggered(3)
        } actions: {
            NextButton(action: next)
        }
        .onChange(of: model.preferences.liveActivities) { model.liveActivities.sync() }
        .m3Dialog("Notifiche disattivate", isPresented: $notificationsDenied,
                  message: "Per ricevere le notifiche consentile a BCW nelle Impostazioni di iOS.") {
            [.cancel("OK"), DialogAction(title: "Apri Impostazioni", style: .strong) { Platform.openNotificationSettings() }]
        }
    }

    /// Accendendo una notifica iOS chiede il permesso; se viene negato, si rispegne.
    private func permission(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding { binding.wrappedValue } set: { isOn in
            binding.wrappedValue = isOn
            guard isOn else { return }
            Task {
                if !(await Reminders.requestAuthorization()) {
                    binding.wrappedValue = false
                    notificationsDenied = true
                }
            }
        }
    }

    private var newsBinding: Binding<Bool> {
        permission(Binding {
            !model.preferences.newsNotifications.isEmpty
        } set: { isOn in
            model.preferences.newsNotifications = isOn ? Set(NewsKind.allCases) : []
        })
    }
}

// MARK: - Classeviva

/// L'accesso a Classeviva, spiegato. Chi ha già un account vede chi è e può aggiungerne un altro.
private struct OnboardingClassevivaPage: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var choices: [LoginChoice] = []
    @State private var addingAccount = false
    @FocusState private var focused: Field?

    private enum Field { case username, password }

    private var isSignedIn: Bool { model.phase == .signedIn && !model.isDemo }

    var body: some View {
        OnboardingPage(title: isSignedIn ? "Hai già effettuato l'accesso" : "Accedi a Classeviva",
                       subtitle: isSignedIn ? "Puoi aggiungere altri account, per esempio quello di un fratello o di una sorella."
                           : "Usa le stesse credenziali del registro: codice utente (o email) e password. Restano solo su questo dispositivo, nel Portachiavi, e vanno soltanto ai server di Classeviva.") {
            if isSignedIn {
                accountSummary
                    .staggered(1)
            } else {
                form
                    .staggered(1)
            }
        } actions: {
            if isSignedIn {
                NextButton(action: next)
            } else {
                NextButton(title: model.isCloud ? "Abbina" : "Accedi", isLoading: isLoading, action: signIn)
                    .disabled(username.isEmpty || password.isEmpty || isLoading)
                if !keyboardOpen {
                    HStack(spacing: 8) {
                        Button {
                            model.startDemo()
                            next()
                        } label: {
                            Label { Text("Prova la demo") } icon: { Icon("sparkles") }
                        }
                        .buttonStyle(.m3(.tonal, size: .s, wide: true))
                        Button("Più tardi", action: next)
                            .buttonStyle(.m3(.text, size: .s, wide: true))
                    }
                }
            }
        }
        .animation(Motion.spatial, value: errorMessage)
        .sheet(isPresented: Binding(get: { !choices.isEmpty }, set: { if !$0 { choices = [] } })) {
            ProfileChoiceSheet(choices: choices) { choice in
                choices = []
                signIn(ident: choice.ident)
            }
            .m3Detents([.medium, .large])
        }
        .sheet(isPresented: $addingAccount) {
            AddAccountSheet { addingAccount = false }
        }
    }

    private var keyboardOpen: Bool { focused != nil }

    private var form: some View {
        VStack(spacing: 10) {
            LoginField(icon: "person", focused: focused == .username) {
                TextField("Codice utente o email", text: $username)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
            }
            LoginField(icon: "key", focused: focused == .password) {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(signIn)
            }
            if let errorMessage {
                OnboardingError(message: errorMessage)
            }
            Text("BCW non è affiliata a Gruppo Spaggiari Parma.")
                .font(.m3(12))
                .foregroundStyle(Theme.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }

    private var accountSummary: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Avatar(initials: model.card?.initials ?? String(model.displayName.prefix(1)), size: 56, shape: .cookie9Sided)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.m3(18, weight: 600))
                        .foregroundStyle(Theme.ink)
                    Text(model.accounts.count == 1 ? "1 account" : "\(model.accounts.count) account")
                        .font(.m3(14))
                        .foregroundStyle(Theme.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .card(padding: 14, color: Theme.surfaceContainerLow, radius: Theme.radii.xl)
            Button {
                addingAccount = true
            } label: {
                Label { Text(model.isCloud ? "Abbina un altro account" : "Aggiungi un altro account") } icon: { Icon("userPlus") }
            }
            .buttonStyle(.m3(.tonal, size: .s, wide: true))
        }
    }

    private func signIn() {
        signIn(ident: nil)
    }

    private func signIn(ident: String?) {
        guard !username.isEmpty, !password.isEmpty, !isLoading else { return }
        focused = nil
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                try await model.signIn(username: username, password: password, ident: ident)
                Haptics.success()
                next()
            } catch APIError.needsProfileChoice(let options) {
                choices = options
            } catch let error as URLError {
                errorMessage = error.code == .notConnectedToInternet
                    ? "Nessuna connessione a Internet."
                    : "Impossibile contattare Classeviva."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct OnboardingError: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Icon("alertTriangleFill", size: 20)
            Text(message)
                .font(.m3(14))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.onPoorContainer)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.poorContainer, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Account BCW

/// L'account BCW, facoltativo: a cosa serve, e crearlo o accedere.
private struct OnboardingBCWPage: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void

    private enum Choice: Hashable { case none, create, signIn }

    @State private var choice: Choice = .none
    @State private var username = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var editingServer = false
    @FocusState private var focused: Field?

    private enum Field { case username, password, confirm }

    var body: some View {
        OnboardingPage(title: model.isCloud ? "Sei nel tuo account BCW" : "Vuoi un account BCW?",
                       subtitle: model.isCloud ? "Impostazioni, orario e account abbinati ti seguono su ogni dispositivo."
                           : "È facoltativo. Con un nome utente e una password ritrovi tutto su ogni dispositivo.") {
            if model.isCloud {
                HStack(spacing: 14) {
                    Shaped(shape: .cookie9Sided, fill: Theme.secondaryContainer, size: 52) {
                        Icon("cloud")
                            .foregroundStyle(Theme.onSecondaryContainer)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.cloud?.user.username ?? "")
                            .font(.m3(18, weight: 600))
                            .foregroundStyle(Theme.ink)
                        Text(BCWServer.host)
                            .font(.m3(13))
                            .foregroundStyle(Theme.secondaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .card(padding: 14, color: Theme.surfaceContainerLow, radius: Theme.radii.xl)
                .staggered(1)
            } else {
                if choice == .none {
                    benefits
                        .staggered(1)
                } else {
                    form
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        } actions: {
            if model.isCloud {
                NextButton(action: next)
            } else if choice == .none {
                Button {
                    withAnimation(Motion.spatial) { choice = .create }
                } label: {
                    Label { Text("Crea un account BCW") } icon: { Icon("userPlus") }
                }
                .buttonStyle(.m3(.filled, size: .m, wide: true))
                HStack(spacing: 8) {
                    Button("Ho già un account") {
                        withAnimation(Motion.spatial) { choice = .signIn }
                    }
                    .buttonStyle(.m3(.tonal, size: .s, wide: true))
                    Button("No, grazie", action: next)
                        .buttonStyle(.m3(.text, size: .s, wide: true))
                }
            } else {
                NextButton(title: choice == .create ? "Crea account" : "Accedi", isLoading: isLoading, action: submit)
                    .disabled(username.isEmpty || password.isEmpty || (choice == .create && confirm.isEmpty) || isLoading)
                if focused == nil {
                    Button("Indietro") {
                        withAnimation(Motion.spatial) {
                            choice = .none
                            errorMessage = nil
                        }
                    }
                    .buttonStyle(.m3(.text, size: .s, wide: true))
                }
            }
        }
        .animation(Motion.spatial, value: errorMessage)
        .sheet(isPresented: $editingServer) { CloudServerSheet() }
        .onAppear {
            if username.isEmpty { username = model.lastCloudUsername ?? "" }
        }
    }

    private var benefits: some View {
        ListGroup {
            benefit("users", "Tutti i tuoi account insieme", "Più account Classeviva, un solo accesso")
            benefit("timetable", "Orario e impostazioni ovunque", "Su iPhone, iPad e nella versione web")
            benefit("lock", "Credenziali cifrate", "Salvate cifrate sul server di BCW")
        }
    }

    private func benefit(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        ListRow(title, subtitle: subtitle) {
            FormIcon(icon)
        } trailing: {
            EmptyView()
        }
    }

    private var form: some View {
        VStack(spacing: 10) {
            LoginField(icon: "person", focused: focused == .username) {
                TextField("Nome utente BCW", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
            }
            LoginField(icon: "key", focused: focused == .password) {
                SecureField("Password", text: $password)
                    .textContentType(choice == .create ? UITextContentType.newPassword : UITextContentType.password)
                    .focused($focused, equals: .password)
                    .submitLabel(choice == .create ? SubmitLabel.next : SubmitLabel.go)
                    .onSubmit { if choice == .create { focused = .confirm } else { submit() } }
            }
            if choice == .create {
                LoginField(icon: "key", focused: focused == .confirm) {
                    SecureField("Ripeti la password", text: $confirm)
                        .textContentType(.newPassword)
                        .focused($focused, equals: .confirm)
                        .submitLabel(.go)
                        .onSubmit(submit)
                }
                Text("Da 3 a 32 caratteri tra lettere, cifre, punto, trattino e trattino basso. La password deve avere almeno 8 caratteri.")
                    .font(.m3(12))
                    .foregroundStyle(Theme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let errorMessage {
                OnboardingError(message: errorMessage)
            }
            HStack(spacing: 6) {
                Icon("cloud", size: 16)
                Text("Server BCW: \(BCWServer.host)")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("·")
                Button("Modifica") { editingServer = true }
                    .buttonStyle(LinkButtonStyle())
            }
            .font(.m3(12))
            .foregroundStyle(Theme.secondaryInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
    }

    private func submit() {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !password.isEmpty, !isLoading else { return }
        if choice == .create {
            guard password.count >= 8 else {
                errorMessage = "La password deve avere almeno 8 caratteri."
                return
            }
            guard password == confirm else {
                errorMessage = "Le due password non coincidono."
                return
            }
        }
        focused = nil
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                try await model.cloudSignIn(username: name, password: password, register: choice == .create)
                password = ""
                confirm = ""
                Haptics.success()
                next()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Orario

/// L'orario ricavato dalle lezioni già registrate, passo per passo: quando cominciano le ore, un'anteprima
/// della settimana e la scelta se applicarla. Si vede solo con la scheda Orario e con un account.
private struct OnboardingTimetablePage: View {
    @Environment(AppModel.self) private var model
    let next: () -> Void
    @State private var settings = GenerationSettings()
    @State private var draft: TimetableDraft?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var confirmingApply = false
    @State private var prepared = false
    /// Verso del passaggio tra le impostazioni e l'anteprima.
    @State private var forward = true

    private var store: TimetableStore { model.timetable }

    var body: some View {
        ZStack {
            if let draft {
                previewPage(draft)
                    .transition(.sharedAxisX(forward: forward, distance: 64))
            } else {
                setupPage
                    .transition(.sharedAxisX(forward: forward, distance: 64))
            }
        }
        .animation(Motion.spatial, value: errorMessage)
        .onAppear {
            guard !prepared else { return }
            prepared = true
            settings = store.timetable.generation
        }
        .m3Dialog("Hai già un orario", isPresented: $confirmingApply,
                  message: "Sostituendolo, eventi, note, file e verifiche segnate a mano dell'orario attuale verranno eliminati.",
                  stacked: true) {
            [DialogAction(title: "Sostituisci l'orario attuale", style: .destructive) { apply(replacing: true) },
             DialogAction(title: "Aggiungi solo dove è libero") { apply(replacing: false) },
             .cancel()]
        }
    }

    // MARK: Impostazioni

    private var setupPage: some View {
        let events = store.timetable.entries.count
        return OnboardingPage(title: "Crea il tuo orario",
                              subtitle: (events > 0 ? "Hai già un orario con \(events == 1 ? "1 evento" : "\(events) eventi"). Puoi ricavarne un altro" : "BCW può ricavarlo")
                                  + " dalle lezioni già registrate su Classeviva, che però dice solo in quale ora si svolge una lezione: indica quando comincia la prima e quanto dura. Prima di applicarlo vedrai un'anteprima.") {
            VStack(spacing: 20) {
                TimetableGenerationFields(settings: $settings, hoursFooter: hoursFooter)
            }
            .staggered(1)
            if let errorMessage {
                OnboardingError(message: errorMessage)
            }
        } actions: {
            Button {
                Task { await generate() }
            } label: {
                Label {
                    Text("Crea l'anteprima")
                } icon: {
                    if isGenerating { InlineProgress(tint: Theme.onPrimary) } else { Icon("wand") }
                }
            }
            .buttonStyle(.m3(.filled, size: .m, wide: true))
            .disabled(isGenerating)
            Button("Lo farò dopo", action: next)
                .buttonStyle(.m3(.text, size: .s, wide: true))
        }
    }

    private var isAligned: Bool {
        settings.firstHourStart % 30 == 0 && (settings.hourLength == 30 || settings.hourLength == 60)
    }

    private var hoursFooter: String {
        if store.alignment == .automatic && !isAligned {
            return "Con ore così BCW tiene gli orari esatti: applicando l'orario passerà da solo all'allineamento libero, che si cambia in Modifica orario."
        }
        return "Le trovi sul diario o sul sito della scuola. Se sbagli, potrai cambiarle e rigenerare."
    }

    private func generate() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            let result = try await model.makeTimetableDraft(settings: settings)
            Haptics.success()
            forward = true
            DispatchQueue.main.async {
                withAnimation(Motion.spatialSlow) { draft = result }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Anteprima

    private func previewPage(_ draft: TimetableDraft) -> some View {
        let lessons = draft.entries.filter { !$0.isBreak }.count
        return OnboardingPage(title: "Ecco la tua settimana",
                              subtitle: "\(lessons == 1 ? "1 lezione ricavata" : "\(lessons) lezioni ricavate") da \(draft.analyzedDays) giorni di registro. Controlla che torni: potrai cambiarla quando vuoi nella scheda Orario.") {
            DraftWeekGlance(draft: draft)
                .staggered(1)
        } actions: {
            NextButton(title: "Applica l'orario") {
                if store.timetable.isEmpty {
                    apply(replacing: true)
                } else {
                    confirmingApply = true
                }
            }
            HStack(spacing: 8) {
                Button("Cambia le ore") {
                    forward = false
                    DispatchQueue.main.async {
                        withAnimation(Motion.spatialSlow) { self.draft = nil }
                    }
                }
                .buttonStyle(.m3(.tonal, size: .s, wide: true))
                Button("Non ora", action: next)
                    .buttonStyle(.m3(.text, size: .s, wide: true))
            }
        }
    }

    private func apply(replacing: Bool) {
        guard let draft else { return }
        Haptics.success()
        store.draft = draft
        // Con ore fuori dalle mezz'ore passa da sé all'allineamento libero.
        store.applyDraft(replacing: replacing)
        next()
    }
}

/// La settimana dell'anteprima: una colonna per giorno, con le lezioni come pillole nella loro tinta e
/// l'onda di luce dell'anteprima dell'orario.
private struct DraftWeekGlance: View {
    @Environment(AppModel.self) private var model
    let draft: TimetableDraft

    private static let hourHeight: CGFloat = 40

    var body: some View {
        let days = (1...7).map { (weekday: $0, entries: draft.entries(weekday: $0)) }.filter { !$0.entries.isEmpty }
        let starts = draft.entries.map(\.start), ends = draft.entries.map(\.end)
        let first = (starts.min() ?? 8 * 60) / 60 * 60
        let last = max(first + 60, ((ends.max() ?? 14 * 60) + 59) / 60 * 60)
        let height = CGFloat(last - first) / 60 * Self.hourHeight
        HStack(alignment: .top, spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.element.weekday) { column, day in
                VStack(spacing: 8) {
                    Text(Weekday.shortName(day.weekday))
                        .font(.m3(12, weight: 650))
                        .foregroundStyle(Theme.secondaryInk)
                    dayColumn(day.entries, column: column, first: first)
                        .frame(height: height, alignment: .top)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .background(Theme.surfaceContainerLow, in: .rect(cornerRadius: Theme.radii.xl, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Anteprima della settimana")
    }

    private func dayColumn(_ entries: [TimetableEntry], column: Int, first: Int) -> some View {
        let layout = TimetableLayout(entries: entries)
        let lanes = layout.clusters.flatMap { cluster in cluster.blocks.map { (block: $0.block, lane: $0.column, lanes: cluster.columns) } }
        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(Array(lanes.enumerated()), id: \.element.block.id) { row, item in
                    let width = proxy.size.width / CGFloat(item.lanes)
                    block(item.block)
                        .frame(width: width - 2, height: max(14, CGFloat(item.block.end - item.block.start) / 60 * Self.hourHeight - 3))
                        .offset(x: width * CGFloat(item.lane), y: CGFloat(item.block.start - first) / 60 * Self.hourHeight)
                        .staggered(column + row)
                }
            }
        }
    }

    private func block(_ block: TimetableLayout.Block) -> some View {
        let entry = block.entries[0]
        let tint = Theme.timetableColor(entry, store: model.timetable)
        let shape = RoundedRectangle(cornerRadius: Theme.radii.m, style: .continuous)
        return ZStack {
            shape.fill(tint.mix(Theme.surface, 0.34))
            DraftSheen()
                .clipShape(shape)
            Text(entry.displayTitle)
                .font(.m3(11, weight: 650))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 3)
        }
    }
}

// MARK: - Fine

private struct OnboardingDonePage: View {
    @Environment(AppModel.self) private var model
    let finish: (CGPoint?) -> Void
    @State private var frame = CGRect.zero
    @State private var burst = false

    private var isSignedIn: Bool { model.phase == .signedIn }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)
            VStack(spacing: 12) {
                Text(isSignedIn && !model.isDemo ? "Tutto pronto, \(firstName)!" : "Tutto pronto!")
                    .font(.m3(40, weight: 500, rounded: true))
                    .tracking(-0.5)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .staggered(0)
                Text(isSignedIn ? "BCW è fatta su misura per te. Puoi rivedere questa introduzione quando vuoi, in Impostazioni › Generale."
                     : "Manca solo l'accesso a Classeviva: lo trovi nella prossima schermata.")
                    .font(.m3(16))
                    .foregroundStyle(Theme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .staggered(1)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 16)
            NextButton(title: isSignedIn ? "Apri BCW" : "Vai all'accesso") {
                Haptics.success()
                finish(frame == .zero ? nil : CGPoint(x: frame.midX, y: frame.midY))
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .staggered(2)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        // Forme che escono dal centro e svaniscono.
        .overlay(alignment: .top) {
            ShapeBurst()
                .offset(y: -116)
                .allowsHitTesting(false)
        }
        .sensoryFeedback(.success, trigger: burst)
        .onAppear { burst = true }
    }

    private var firstName: String {
        model.displayName.split(separator: " ").first.map(String.init) ?? model.displayName
    }
}

/// Coriandoli di forme di M3 Expressive: escono dal centro con una molla, ruotano e svaniscono.
private struct ShapeBurst: View {
    private struct Piece: Identifiable {
        let id: Int
        let shape: MaterialShapeName
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let spin: Double
    }

    private static let shapes: [MaterialShapeName] = [.cookie9Sided, .sunny, .pill, .clover4Leaf, .gem, .flower, .puffy, .pentagon]
    private static let pieces: [Piece] = (0..<18).map { index in
        Piece(id: index, shape: shapes[index % shapes.count], angle: Double(index) * 20 + (index.isMultiple(of: 2) ? 6 : -6),
              distance: index.isMultiple(of: 3) ? 190 : (index.isMultiple(of: 2) ? 150 : 120),
              size: index.isMultiple(of: 3) ? 26 : 16, spin: index.isMultiple(of: 2) ? 180 : -220)
    }

    @State private var flying = false
    @State private var gone = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion, ThemeStore.shared.motion != .reduced {
                ForEach(Self.pieces) { piece in
                    MaterialShape(piece.shape)
                        .fill(color(piece.id))
                        .frame(width: piece.size, height: piece.size)
                        .rotationEffect(.degrees(flying ? piece.spin : 0))
                        .offset(x: flying ? cos(piece.angle * .pi / 180) * piece.distance : 0,
                                y: flying ? sin(piece.angle * .pi / 180) * piece.distance : 0)
                        .scaleEffect(flying ? 1 : 0.2)
                        .opacity(gone ? 0 : (flying ? 1 : 0))
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.72).delay(0.12)) { flying = true }
            withAnimation(.easeOut(duration: 0.7).delay(1)) { gone = true }
        }
    }

    private func color(_ index: Int) -> Color {
        [Theme.primary, Theme.tertiary, Theme.secondary, Theme.primaryContainer, Theme.tertiaryContainer][index % 5]
    }
}
