import SwiftUI

// MARK: - Banner delle Impostazioni

/// Banner in cima a Tu › Impostazioni (richiesta dell'utente, 4.0), in uno di tre stati:
/// - "Acquista BCW+" con il prezzo (build dell'App Store senza acquisto): apre la schermata
///   dell'acquisto e non si può nascondere;
/// - "Grazie per il supporto" con un cuore (forma di Material nel colore del testo), dopo l'acquisto;
/// - "Build GitHub" (la build di GitHub, tutto sbloccato).
/// Gli ultimi due si nascondono con la X e si rimostrano da Impostazioni › Generale.
struct PlusBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(OverlayHost.self) private var host: OverlayHost?

    private enum Kind { case buy, thanks, github }

    private var kind: Kind? {
        let plus = PlusStore.shared
        if BuildVariant.isAppStore && !plus.isPurchased { return .buy }
        guard model.preferences.showsPlusBanner else { return nil }
        return BuildVariant.isAppStore ? .thanks : .github
    }

    var body: some View {
        ZStack {
            switch kind {
            case .buy: buyBanner.transition(.scale(scale: 0.96).combined(with: .opacity))
            case .thanks: thanksBanner.transition(.scale(scale: 0.96).combined(with: .opacity))
            case .github: githubBanner.transition(.scale(scale: 0.96).combined(with: .opacity))
            case nil: EmptyView()
            }
        }
        .animation(Motion.spatial, value: kind)
    }

    // MARK: Stati

    private var buyBanner: some View {
        Button {
            Haptics.tap()
            PlusStore.shared.presentPaywall()
        } label: {
            BannerCard(container: Theme.primaryContainer, accent: Theme.primary,
                       decoration: .cookie12Sided, decorationTint: Theme.primary) {
                Shaped(shape: .cookie9Sided, fill: Theme.primary, size: 52) {
                    Icon("plus", size: 32)
                        .foregroundStyle(Theme.onPrimary)
                }
            } text: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Acquista BCW+")
                        .font(.m3(20, weight: 650, rounded: true))
                    Text("Orario, attività in diretta e widget con un pagamento unico")
                        .font(.m3(13))
                        .opacity(0.82)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.onPrimaryContainer)
            } trailing: {
                Text(PlusStore.shared.price)
                    .font(.m3(15, weight: 700))
                    .monospacedDigit()
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Theme.primary, in: .capsule)
                    .fixedSize()
            }
        }
        .buttonStyle(.pressable(radius: Theme.radii.xl, pressed: Theme.radii.l))
        .accessibilityLabel("Acquista BCW+, \(PlusStore.shared.price)")
        .accessibilityHint("Apre la schermata di BCW+")
    }

    private var thanksBanner: some View {
        BannerCard(container: Theme.tertiaryContainer, accent: Theme.tertiary,
                   decoration: .heart, decorationTint: Theme.tertiary) {
            Shaped(shape: .sunny, fill: Theme.tertiary, size: 52) {
                Icon("volunteer", size: 28)
                    .foregroundStyle(Theme.onTertiary)
            }
        } text: {
            VStack(alignment: .leading, spacing: 2) {
                // Il cuore è una forma di Material 3 dello stesso colore del testo, dentro il testo: va a
                // capo con l'ultima parola invece di restare sulla prima riga.
                Text("Grazie per il supporto\u{00A0}\(Image(uiImage: MaterialShape.templateImage(.heart, size: 18)))")
                    .font(.m3(20, weight: 650, rounded: true))
                    .accessibilityLabel("Grazie per il supporto")
                Text("BCW+ è attiva: orario, attività in diretta e widget sono sbloccati")
                    .font(.m3(13))
                    .opacity(0.82)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.onTertiaryContainer)
        } trailing: {
            hideButton(tint: Theme.onTertiaryContainer)
        }
        .accessibilityElement(children: .contain)
    }

    private var githubBanner: some View {
        BannerCard(container: Theme.secondaryContainer, accent: Theme.secondary,
                   decoration: .clover8Leaf, decorationTint: Theme.secondary) {
            Shaped(shape: .cookie12Sided, fill: Theme.secondary, size: 52) {
                Icon("github", size: 26)
                    .foregroundStyle(Theme.onSecondary)
            }
        } text: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Build GitHub")
                    .font(.m3(20, weight: 650, rounded: true))
                Text("In questa build, tutte le funzioni sono sbloccate")
                    .font(.m3(13))
                    .opacity(0.82)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Theme.onSecondaryContainer)
        } trailing: {
            hideButton(tint: Theme.onSecondaryContainer)
        }
        .accessibilityElement(children: .contain)
    }

    private func hideButton(tint: Color) -> some View {
        Button {
            Haptics.selection()
            withAnimation(Motion.spatial) { model.preferences.showsPlusBanner = false }
            host?.showToast("Banner nascosto: lo ritrovi in Impostazioni › Generale", icon: "visibilityOff")
        } label: {
            Icon("x", size: 20)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.1), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.pressable(radius: 18, pressed: 12))
        .accessibilityLabel("Nascondi il banner")
    }
}

/// La card del banner: contenitore con angoli ampi, una forma grande che sporge dall'angolo in basso a
/// destra (ritagliata), l'icona in una forma, i testi e un elemento a destra.
private struct BannerCard<Leading: View, TextContent: View, Trailing: View>: View {
    let container: Color
    let accent: Color
    let decoration: MaterialShapeName
    let decorationTint: Color
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let text: () -> TextContent
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            leading()
            text()
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 96)
        .background {
            ZStack(alignment: .bottomTrailing) {
                container
                SpinningShape(shape: decoration, color: decorationTint.opacity(0.1), period: 60)
                    .frame(width: 150, height: 150)
                    .offset(x: 46, y: 58)
                MaterialShape(.clover4Leaf)
                    .fill(decorationTint.opacity(0.08))
                    .frame(width: 44, height: 44)
                    .offset(x: -96, y: -60)
            }
        }
        .clipShape(.rect(cornerRadius: Theme.radii.xl, style: .continuous))
    }
}

// MARK: - Impostazioni › Generale

/// BCW+ o la build GitHub in Impostazioni › Generale: il banner da rimostrare, il ripristino degli
/// acquisti e (build GitHub) gli avvisi delle nuove versioni.
struct PlusSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(OverlayHost.self) private var host: OverlayHost?
    @State private var checking = false

    var body: some View {
        @Bindable var preferences = model.preferences
        let plus = PlusStore.shared
        if BuildVariant.isAppStore {
            ListGroup("BCW+", footer: plus.isPurchased
                      ? "Grazie per aver sostenuto BCW! BCW+ resta tua su tutti i dispositivi con lo stesso Apple ID."
                      : "Orario, attività in diretta e widget con un pagamento unico di \(plus.price), senza abbonamento.") {
                if plus.isPurchased {
                    ToggleRow("Mostra il banner nelle Impostazioni", icon: "favorite", isOn: $preferences.showsPlusBanner)
                } else {
                    Button {
                        PlusStore.shared.presentPaywall()
                    } label: {
                        NavigationRow("Scopri BCW+", subtitle: plus.price, icon: "workspacePremium", tint: Theme.primary)
                    }
                    .buttonStyle(.listRow)
                }
                ButtonRow("Ripristina acquisti", icon: "refresh") {
                    Task {
                        let found = await plus.restore()
                        host?.showToast(found ? "BCW+ è attiva" : "Nessun acquisto di BCW+ trovato su questo Apple ID",
                                        icon: found ? "checkCircle" : "alertCircle")
                    }
                }
                .disabled(plus.isRestoring)
            }
        } else {
            ListGroup("Build GitHub", footer: "In questa build tutto è sbloccato. All'apertura BCW controlla su GitHub se c'è una versione più recente.") {
                ToggleRow("Mostra il banner nelle Impostazioni", icon: "github", isOn: $preferences.showsPlusBanner)
                ToggleRow("Avvisa delle nuove versioni", icon: "systemUpdate", isOn: $preferences.updateAlerts)
                ButtonRow("Cerca aggiornamenti", icon: "update") {
                    guard !checking else { return }
                    checking = true
                    Task {
                        let result = await UpdateChecker.shared.checkNow()
                        checking = false
                        switch result {
                        case .upToDate: host?.showToast("Hai già l'ultima versione di BCW", icon: "checkCircle")
                        case .available: break // si apre il foglio della nuova versione
                        case .failed: host?.showToast("Non riesco a contattare GitHub: riprova più tardi", icon: "wifiOff")
                        }
                    }
                }
                .disabled(checking)
            }
        }
    }
}

// MARK: - Scheda Orario bloccata

/// La scheda Orario nella build dell'App Store senza BCW+: solo una scritta con il prezzo, il pulsante
/// per scoprire BCW+ e quello per nascondere la scheda dalla barra (richiesta dell'utente, 4.0).
struct TimetableLockedView: View {
    @Environment(AppModel.self) private var model
    @Environment(OverlayHost.self) private var host: OverlayHost?

    var body: some View {
        PlatformNavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Shaped(shape: .cookie12Sided, fill: Theme.primaryContainer, size: 104) {
                        Icon("lock", size: 44)
                            .foregroundStyle(Theme.onPrimaryContainer)
                    }
                    VStack(spacing: 8) {
                        Text("L'orario richiede BCW+")
                            .font(.m3(24, weight: 550, rounded: true))
                            .foregroundStyle(Theme.ink)
                        Text("L'orario, con l'attività in diretta e i widget, si sblocca con un pagamento unico di \(PlusStore.shared.price).")
                            .font(.m3(.bodyL))
                            .foregroundStyle(Theme.onSurfaceVariant)
                    }
                    .multilineTextAlignment(.center)
                    VStack(spacing: 6) {
                        Button {
                            Haptics.tap()
                            PlusStore.shared.presentPaywall()
                        } label: {
                            Label { Text("Scopri BCW+") } icon: { Icon("lockOpen") }
                        }
                        .buttonStyle(.m3(.filled, size: .m))
                        Button {
                            Haptics.selection()
                            withAnimation(Motion.spatial) { model.preferences.showsTimetableTab = false }
                            host?.showToast("Scheda nascosta: la rimetti in Impostazioni › Orario", icon: "visibilityOff")
                        } label: {
                            Label { Text("Nascondi la scheda") } icon: { Icon("visibilityOff") }
                        }
                        .buttonStyle(.m3(.text, size: .s))
                    }
                    .padding(.top, 6)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical) { height, _ in height * 0.9 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .themedBackground()
            .pageChrome("Orario", style: .inline)
        }
    }
}

extension MaterialShape {
    /// Una forma di Material come immagine modello (prende il colore del testo), da mettere dentro un
    /// `Text`.
    static func templateImage(_ name: MaterialShapeName, size: CGFloat) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        let image = UIGraphicsImageRenderer(size: rect.size).image { context in
            context.cgContext.addPath(MaterialShape(name).path(in: rect).cgPath)
            context.cgContext.setFillColor(UIColor.black.cgColor)
            context.cgContext.fillPath()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
