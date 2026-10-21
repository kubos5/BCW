import SwiftUI

// MARK: - Icona dell'app (Impostazioni › Aspetto › Icona dell'app)

/// Pagina dell'icona: anteprima nelle tre modalità delle icone di iOS, forma, colore e aspetto.
/// Le scelte si sincronizzano con l'account BCW (`ThemeStore`) e le applica `AppIconController`.
struct AppIconSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AppIconSettingsSection()
            }
            .pagePadding()
            .padding(.bottom, Theme.bottomInset)
        }
        .tracksPageScroll()
        .themedBackground()
        .pageChrome("Icona dell'app", style: .inline)
    }
}

private struct AppIconSettingsSection: View {
    var body: some View {
        @Bindable var theme = ThemeStore.shared
        let choice = theme.appIconChoice

        ListGroup {
            AppIconHero(choice: choice)
        }

        ListGroup("Forma", footer: "La forma di Material 3 Expressive che contiene la barra di BCW. Classica è l'icona di prima, con la sola barra su sfondo crema.") {
            AppIconShapeGrid(choice: choice, selection: $theme.appIconShape)
        }

        ListGroup("Colore", footer: colorFooter(theme: theme, choice: choice)) {
            AppIconColorGrid(choice: choice, selection: $theme.appIconColor)
        }
        .disabled(theme.appIconShape == .classic)
        .opacity(theme.appIconShape == .classic ? 0.38 : 1)

        ListGroup("Aspetto", footer: "Con le icone colorate e trasparenti di iOS l'icona è sempre tinta da iOS, qualunque sia l'aspetto scelto: forma e barra restano due livelli distinti.") {
            ForEach(AppIconAppearance.allCases) { appearance in
                AppIconAppearanceRow(appearance: appearance, selected: theme.appIconAppearance == appearance) {
                    withAnimation(Motion.spatialFast) { theme.appIconAppearance = appearance }
                }
            }
        }

        let darkDisabled = theme.appIconAppearance == .light
        ListGroup("Sfondo scuro", footer: darkDisabled
                  ? "Con Sempre chiaro l'icona non è mai scura."
                  : "Material: lo sfondo scuro del tema, come nell'app. iOS: lo sfondo scuro standard delle icone di iOS. A ogni cambio d'icona iOS mostra un avviso.") {
            SegmentedButtons(selection: $theme.appIconDarkBackground,
                             options: AppIconDarkBackground.allCases.map { ($0, $0.title, nil) })
                .padding(16)
                .disabled(darkDisabled)
                .opacity(darkDisabled ? 0.38 : 1)
        }

        if !theme.appIconIsDefault {
            ListGroup {
                ButtonRow("Ripristina l'icona di BCW", icon: "refresh") {
                    withAnimation(Motion.spatial) { theme.resetAppIcon() }
                }
            }
        }
    }

    private func colorFooter(theme: ThemeStore, choice: AppIconChoice) -> String {
        if theme.appIconShape == .classic { return "L'icona classica ha sempre i colori di BCW." }
        let current = "Ora: \(choice.color.title)."
        if theme.appIconColor == .theme {
            return "Tema dell'app: l'icona prende il colore proposto più vicino al colore d'accento, e cambia con lui. \(current)"
        }
        return "Con Tema dell'app l'icona prende il colore proposto più vicino al colore d'accento. \(current)"
    }
}

/// Anteprima grande: l'icona con le icone chiare, scure e colorate di iOS, come sulla Home.
private struct AppIconHero: View {
    let choice: AppIconChoice

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            column(.light, "Chiare")
            column(.dark, "Scure")
            column(.tinted, "Colorate")
        }
        .padding(.horizontal, 12)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .animation(Motion.spatial, value: choice)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Anteprima dell'icona: \(choice.shape.title), \(choice.color.title)")
    }

    private func column(_ mode: AppIconPreview.Mode, _ label: String) -> some View {
        VStack(spacing: 8) {
            AppIconPreview(choice: choice, mode: mode, size: 84, tint: Self.tint)
                .shadow(color: Theme.shadow.opacity(0.18), radius: 6, y: 2)
            Text(label)
                .font(.m3(13, weight: 550))
                .foregroundStyle(Theme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
    }

    /// Tinta delle icone colorate in anteprima (un giallo caldo, come quella proposta da iOS).
    static let tint = Color(platformColor: PlatformColor(hex: 0xF6D58A))
}

/// Celle delle forme: ogni forma con la barra, nei colori scelti e nel tema in uso.
private struct AppIconShapeGrid: View {
    let choice: AppIconChoice
    @Binding var selection: AppIconShape
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 76), spacing: 10)], spacing: 14) {
                ForEach(AppIconShape.allCases) { shape in
                    let selected = shape == selection
                    Button {
                        guard !selected else { return }
                        Haptics.selection()
                        withAnimation(Motion.spatial) { selection = shape }
                    } label: {
                        AppIconPreview(choice: AppIconChoice(shape: shape, color: choice.color, variant: choice.variant),
                                       mode: colorScheme == .dark ? .dark : .light, size: 54)
                            .padding(4)
                            .overlay {
                                if selected {
                                    RoundedRectangle(cornerRadius: 54 * AppIconGeometry.mask + 4, style: .continuous)
                                        .strokeBorder(Theme.primary, lineWidth: 2.5)
                                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(.rect)
                    }
                    .buttonStyle(AppIconCellButtonStyle())
                    .accessibilityLabel(shape.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text(selection.title)
                .font(.m3(14, weight: 550))
                .foregroundStyle(Theme.onSurfaceVariant)
                .contentTransition(.opacity)
                .padding(.leading, 4)
        }
        .padding(16)
    }
}

/// Colori: "Tema dell'app" e i dieci colori proposti, ognuno con la forma e la barra nei suoi colori.
private struct AppIconColorGrid: View {
    let choice: AppIconChoice
    @Binding var selection: AppIconColor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 60), spacing: 8)], spacing: 12) {
            ForEach(AppIconColor.allCases) { color in
                let selected = color == selection
                // Il tema mostra il colore a cui corrisponde ora.
                let shown = color == .theme ? AppIconColor.nearest(to: ThemeStore.shared.accentColor) : color
                Button {
                    guard !selected else { return }
                    Haptics.selection()
                    withAnimation(Motion.spatial) { selection = color }
                } label: {
                    AppIconColorSwatch(color: shown, dark: colorScheme == .dark, selected: selected,
                                       icon: color == .theme ? "palette" : (selected ? "check" : nil))
                }
                .buttonStyle(AppIconCellButtonStyle())
                .accessibilityLabel(color == .theme ? "Tema dell'app (\(shown.title))" : color.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(16)
    }
}

/// Campione di un colore dell'icona: la forma e la barra nei colori dell'icona chiara o scura.
private struct AppIconColorSwatch: View {
    let color: AppIconColor
    let dark: Bool
    let selected: Bool
    let icon: String?

    var body: some View {
        let colors = AppIconPalette.colors(for: AppIconChoice(shape: .circle, color: color, variant: .auto),
                                           rendition: dark ? .dark : .light)
        let shape = RoundedRectangle(cornerRadius: selected ? Theme.radii.l : 22, style: .continuous)
        ZStack {
            colors.shape
            if let icon {
                Icon(icon, size: 18)
                    .foregroundStyle(Theme.ink)
                    .frame(width: 26, height: 26)
                    .background(Theme.surfaceContainerLowest, in: .circle)
            } else {
                Capsule(style: .circular)
                    .fill(colors.bar)
                    .frame(width: 26, height: 26 * AppIconGeometry.barAspect)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.ink.opacity(0.12), lineWidth: 1))
        .padding(3)
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: Theme.radii.l + 3, style: .continuous)
                    .strokeBorder(Theme.ink, lineWidth: 2)
            }
        }
        .padding(-3)
        .animation(Motion.spatial, value: selected)
    }
}

/// Voce di un aspetto dell'icona: selezionata, ha lo sfondo del contenitore secondario e la spunta.
private struct AppIconAppearanceRow: View {
    let appearance: AppIconAppearance
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            guard !selected else { return }
            Haptics.selection()
            action()
        } label: {
            ListRow(appearance.title, subtitle: appearance.subtitle) {
                if selected {
                    Icon("check", size: 22)
                        .foregroundStyle(Theme.onSecondaryContainer)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(ListRowButtonStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct AppIconCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.spatialFast, value: configuration.isPressed)
    }
}

/// Voce di Impostazioni › Aspetto che apre la pagina dell'icona, con l'icona scelta a sinistra.
struct AppIconSettingsLink: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = ThemeStore.shared
        let choice = theme.appIconChoice
        NavigationLink {
            AppIconSettingsView()
        } label: {
            ListRow("Icona dell'app", subtitle: subtitle(theme: theme, choice: choice)) {
                AppIconPreview(choice: choice, mode: colorScheme == .dark ? .dark : .light, size: 40)
            } trailing: {
                Icon("chevronRight", size: 20)
                    .foregroundStyle(Theme.onSurfaceVariant)
            }
        }
        .buttonStyle(.listRow)
    }

    private func subtitle(theme: ThemeStore, choice: AppIconChoice) -> String {
        if choice.shape == .classic { return "Classica" }
        let color = theme.appIconColor == .theme ? "Tema dell'app" : choice.color.title
        return "\(choice.shape.title) · \(color)"
    }
}
