import SwiftUI

// MARK: - Icona dell'app (Impostazioni › Aspetto › Icona dell'app)

/// Pagina dell'icona: anteprima nelle tre modalità delle icone di iOS, colore e aspetto.
/// Le scelte si sincronizzano con l'account BCW (`ThemeStore`) e le applica `AppIconController`.
struct AppIconSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AppIconSettingsSection()
            }
            // Sull'iPad largo larga al massimo 760 punti (le griglie si adattano da sole).
            .readableWidth(760)
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

        ListGroup("Colore", footer: colorFooter(theme: theme, choice: choice)) {
            AppIconColorGrid(choice: choice, selection: $theme.appIconColor)
        }

        ListGroup("Aspetto", footer: appearanceFooter(theme.appIconAppearance)) {
            SegmentedButtons(selection: $theme.appIconAppearance,
                             options: AppIconAppearance.allCases.map { ($0, $0.title, nil) })
                .padding(16)
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
        let current = "Ora: \(choice.color.title)."
        if theme.appIconColor == .theme {
            return "Tema dell'app: l'icona prende il colore più vicino al colore d'accento, e cambia con lui. \(current)"
        }
        return "Con Tema dell'app l'icona prende il colore più vicino al colore d'accento. \(current)"
    }

    private func appearanceFooter(_ appearance: AppIconAppearance) -> String {
        let mode = appearance == .automatic
            ? "Automatico: chiara o scura come le icone di iOS."
            : "Sempre scuro: scura anche con le icone chiare di iOS."
        return "\(mode) Con le icone colorate e trasparenti l'icona è tinta da iOS. A ogni cambio d'icona iOS mostra un avviso."
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
        .accessibilityLabel("Anteprima dell'icona: \(choice.color.title), \(choice.appearance.title.lowercased())")
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

/// Colori: "Tema dell'app" e i sei colori dell'icona, ognuno con il cerchio e la barra.
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
                    AppIconColorSwatch(color: shown, appearance: choice.appearance, dark: colorScheme == .dark,
                                       selected: selected,
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

/// Campione di un colore dell'icona: il cerchio e la barra come nell'icona chiara o scura.
private struct AppIconColorSwatch: View {
    let color: AppIconColor
    let appearance: AppIconAppearance
    let dark: Bool
    let selected: Bool
    let icon: String?

    var body: some View {
        let colors = AppIconPalette.colors(for: AppIconChoice(color: color, appearance: appearance),
                                           mode: dark ? .dark : .light)
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
        let color = theme.appIconColor == .theme ? "Tema dell'app" : choice.color.title
        return choice.appearance == .dark ? "\(color) · Sempre scura" : color
    }
}
