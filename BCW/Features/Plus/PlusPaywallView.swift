import StoreKit
import SwiftUI
import WidgetKit

/// La schermata di BCW+ (build dell'App Store): cosa sblocca (orario, attività in diretta, widget),
/// con due widget veri in anteprima, e l'acquisto unico. Dopo il pagamento diventa un grazie e tutto
/// è già sbloccato sotto (`PlusStore.isUnlocked` è osservabile). Si apre dal banner delle Impostazioni,
/// dalla scheda Orario, dall'introduzione e dai widget bloccati (`bcw://plus`).
struct PlusPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @Environment(\.colorScheme) private var colorScheme
    @State private var message: Message?
    /// Raggio degli angoli in alto del foglio, letto da UIKit (`SheetCornerReader`).
    @State private var sheetRadius: CGFloat?
    @State private var appeared = false
    /// Grazie mostrato (l'acquisto è appena riuscito, o è arrivato mentre la schermata era aperta).
    @State private var thanked = false

    private struct Message: Equatable {
        let text: String
        let isError: Bool
    }

    private var plus: PlusStore { PlusStore.shared }

    /// Margine della card in alto dal bordo del foglio, uguale in alto, a destra e a sinistra (richiesta
    /// dell'utente, 4.0): il foglio non ha la maniglia, e con lo stesso margine sui tre lati gli angoli in
    /// alto della card sono concentrici con quelli del foglio (con margini diversi non possono esserlo).
    private static let sheetInset: CGFloat = 6
    private static var heroTop: CGFloat { sheetInset }
    /// Pulsante di chiusura: concentrico con l'angolo della card (centro sul centro dell'arco).
    private static let closeInset: CGFloat = 11

    var body: some View {
        ZStack {
            if thanked {
                PlusThanksView { dismiss() }
                    .transition(.sharedAxisY(forward: true))
            } else {
                offer
                    .transition(.sharedAxisY(forward: false))
            }
        }
        .animation(Motion.spatialSlow, value: thanked)
        .overlay(alignment: .topTrailing) {
            IconButton("x", label: "Chiudi", kind: .tonal) { dismiss() }
                .padding(.top, Self.heroTop + Self.closeInset)
                .padding(.trailing, Self.sheetInset + Self.closeInset)
        }
        .m3Sheet(size: .page, dragIndicator: false)
        .task { await plus.loadProduct() }
        .onAppear {
            withAnimation(Motion.spatialSlow.delay(0.05)) { appeared = true }
        }
        // Acquisto arrivato da fuori (approvato con "Chiedi di acquistare", o fatto su un altro dispositivo).
        .onChange(of: plus.isPurchased) { _, purchased in
            if purchased && !thanked { thank() }
        }
    }

    // MARK: Offerta

    private var offer: some View {
        ScrollView {
            VStack(spacing: 28) {
                hero
                    .padding(.horizontal, Self.sheetInset)
                VStack(spacing: 28) {
                    features
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 24)
                    promises
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 32)
                    Text("Tutto il resto di BCW resta gratuito: voti, agenda, bacheca, assenze, note e le altre funzioni. Il tuo acquisto sostiene lo sviluppo di BCW, un progetto indipendente e open source.")
                        .font(.m3(.bodyS))
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: 560)
            }
            .padding(.top, Self.heroTop)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar }
    }

    /// In cima: il marchio di BCW+ su un contenitore primario con forme che ruotano piano e, sopra, due
    /// widget veri (con i colori del tema e i dati di esempio) leggermente inclinati.
    private var hero: some View {
        VStack(spacing: 18) {
            PlusWidgetShowcase(colorScheme: colorScheme)
                .scaleEffect(appeared ? 1 : 0.86)
                .opacity(appeared ? 1 : 0)
                .padding(.top, 36)
            VStack(spacing: 8) {
                PlusWordmark(size: 44)
                Text("L'orario e i widget, per sempre")
                    .font(.m3(.titleM))
                    .foregroundStyle(Theme.onPrimaryContainer.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Theme.primaryContainer
                SpinningShape(shape: .cookie12Sided, color: Theme.primary.opacity(0.14), period: 40)
                    .frame(width: 220, height: 220)
                    .offset(x: 130, y: -90)
                SpinningShape(shape: .flower, color: Theme.tertiary.opacity(0.16), period: 55, reverse: true)
                    .frame(width: 180, height: 180)
                    .offset(x: -140, y: 110)
                SpinningShape(shape: .clover4Leaf, color: Theme.secondary.opacity(0.12), period: 30)
                    .frame(width: 70, height: 70)
                    .offset(x: -120, y: -100)
            }
        }
        .clipShape(heroShape)
        .background(SheetCornerReader(radius: $sheetRadius))
        #if DEBUG
        .background(SheetCornerProbe())
        #endif
    }

    /// In alto concentrici con gli angoli del foglio: il raggio del foglio (letto da UIKit) meno il margine,
    /// con la stessa curva continua; in basso quelli dell'app. Finché UIKit non risponde (al primo disegno)
    /// `ConcentricRectangle`, che dentro il foglio dà lo stesso risultato.
    private var heroShape: AnyShape {
        let bottom = Theme.radii.xli
        guard let sheetRadius, sheetRadius > Self.sheetInset else {
            return AnyShape(ConcentricRectangle(uniformTopCorners: .concentric(minimum: .fixed(bottom)),
                                                uniformBottomCorners: .fixed(bottom)))
        }
        let top = sheetRadius - Self.sheetInset
        return AnyShape(UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                               bottomTrailingRadius: bottom, topTrailingRadius: top,
                                               style: .continuous))
    }

    private var features: some View {
        ListGroup {
            PlusFeatureRow(icon: "timetable", shape: .cookie9Sided, tint: Theme.subject(3),
                           title: "Orario",
                           text: "Tieni traccia delle materie della settimana con note, file, e intervalli. Scegli i tuoi colori con le palette personalizzate, e lascia che BCW inserisca i dati in automatico.")
            PlusFeatureRow(icon: "lockClock", shape: .sunny, tint: Theme.subject(5),
                           title: "Attività in diretta",
                           text: WindowClass.isPad
                               ? "Tieni traccia della lezione in corso direttamente dalla schermata di blocco."
                               : "Tieni traccia della lezione in corso direttamente dalla Dynamic Island o dalla schermata di blocco.")
            PlusFeatureRow(icon: "widgets", shape: .clover4Leaf, tint: Theme.subject(1),
                           title: "Widget",
                           text: "Consulta il tuo orario, le prossime verifiche o i tuoi voti a colpo d'occhio direttamente dalla schermata home.")
            PlusFeatureRow(icon: "cloud", shape: .puffy, tint: Theme.subject(7),
                           title: "Sempre con te",
                           text: "L'orario si sincronizza con il tuo account BCW, insieme agli allegati, su tutti i tuoi dispositivi.")
        }
    }

    private var promises: some View {
        FlowLayout(spacing: 8) {
            StatusChip(text: "Pagamento unico", icon: "check")
            StatusChip(text: "Niente abbonamento", icon: "check")
            StatusChip(text: "Su tutti i tuoi dispositivi", icon: "check")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Acquisto

    /// Il pulsante dell'acquisto, sempre in fondo, sopra il contenuto che scorre.
    private var purchaseBar: some View {
        VStack(spacing: 6) {
            if let message {
                HStack(spacing: 8) {
                    Icon(message.isError ? "alertCircle" : "clock", size: 18)
                    Text(message.text)
                        .font(.m3(13, weight: 500))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(message.isError ? Theme.error : Theme.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Button(action: buy) {
                HStack(spacing: 10) {
                    if plus.isPurchasing {
                        InlineProgress(tint: Theme.onPrimary)
                    } else {
                        Icon("lockOpen", size: 22)
                    }
                    Text("Sblocca per \(plus.price)")
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.m3(.filled, size: .m, wide: true))
            .disabled(plus.isPurchasing || plus.isRestoring)
            .accessibilityHint("Acquisto unico di BCW+")
            HStack(spacing: 4) {
                Button(action: restore) {
                    HStack(spacing: 6) {
                        if plus.isRestoring { InlineProgress(tint: Theme.primary, size: 14) }
                        Text("Ripristina acquisti")
                    }
                }
                .buttonStyle(.m3(.text, size: .xs))
                .disabled(plus.isPurchasing || plus.isRestoring)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 26)
        .padding(.bottom, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background {
            // Il contenuto sfuma sotto il pulsante.
            LinearGradient(colors: [Theme.surfaceContainerLow.opacity(0), Theme.surfaceContainerLow],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.3))
                .ignoresSafeArea()
        }
        .animation(Motion.spatial, value: message)
    }

    private func buy() {
        Haptics.tap()
        message = nil
        Task {
            switch await plus.purchase(with: purchase) {
            case .purchased:
                thank()
            case .pending:
                message = Message(text: "Acquisto in attesa di approvazione: BCW+ si attiverà da sola appena confermato.", isError: false)
            case .cancelled:
                break
            case let .failed(text):
                message = Message(text: text, isError: true)
            }
        }
    }

    private func restore() {
        Haptics.tap()
        message = nil
        Task {
            if await plus.restore() {
                thank()
            } else {
                message = Message(text: "Nessun acquisto di BCW+ trovato su questo Apple ID.", isError: true)
            }
        }
    }

    private func thank() {
        guard !thanked else { return }
        Haptics.success()
        // I widget già aggiunti si ridisegnano subito, senza aspettare l'istantanea.
        WidgetCenter.shared.reloadAllTimelines()
        thanked = true
    }
}

// MARK: - Grazie

/// Dopo l'acquisto: una forma che diventa un cuore, il grazie e, in un gruppo (richiesta dell'utente, 4.0),
/// gli interruttori della scheda Orario e dell'attività in diretta, sempre visibili e accesi all'arrivo
/// (anche se la scheda era stata nascosta), e come aggiungere i widget.
private struct PlusThanksView: View {
    let done: () -> Void
    @Environment(AppModel.self) private var model
    @State private var shape: MaterialShapeName = .cookie12Sided
    @State private var shown = false

    var body: some View {
        @Bindable var preferences = model.preferences
        ScrollView {
            VStack(spacing: 22) {
                MorphShape(shape)
                    .fill(Theme.primary)
                    .frame(width: 148, height: 148)
                    .overlay {
                        Icon("favoriteFill", size: 56)
                            .foregroundStyle(Theme.onPrimary)
                            .opacity(shape == .heart ? 0 : 1)
                    }
                    .scaleEffect(shown ? 1 : 0.4)
                    .rotationEffect(.degrees(shown ? 0 : -40))
                VStack(spacing: 10) {
                    Text("Grazie!")
                        .font(.m3(36, weight: 600, rounded: true))
                        .foregroundStyle(Theme.ink)
                    Text("BCW+ è attiva: l'orario, l'attività in diretta e i widget sono sbloccati.")
                        .font(.m3(.bodyL))
                        .foregroundStyle(Theme.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                }
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 16)
                ListGroup {
                    ToggleRow("Mostra scheda orario", subtitle: "Tra le schede di BCW", icon: "timetable",
                              isOn: $preferences.showsTimetableTab)
                    ToggleRow("Mostra attività in diretta",
                              subtitle: WindowClass.isPad ? "Nella schermata di blocco" : "Nella Dynamic Island e nella schermata di blocco",
                              icon: "lockClock", isOn: $preferences.liveActivities)
                    ListRow("Aggiungi i widget",
                            subtitle: "Tieni premuto uno spazio vuoto della Home, poi Modifica › Aggiungi widget e cerca BCW.") {
                        FormIcon("widgets")
                    } trailing: { EmptyView() }
                }
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 16)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("Inizia", action: done)
                .buttonStyle(.m3(.filled, size: .m, wide: true))
                .opacity(shown ? 1 : 0)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .background(Theme.surfaceContainerLow.ignoresSafeArea())
        }
        .onChange(of: preferences.liveActivities) { model.liveActivities.sync() }
        .onAppear {
            // Accesi all'arrivo: la scheda torna anche se era stata nascosta senza BCW+.
            preferences.showsTimetableTab = true
            if !preferences.liveActivities { preferences.liveActivities = true }
            withAnimation(Motion.spatialSlow) { shown = true }
            // La forma diventa un cuore con la molla, poco dopo che è comparsa.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(Motion.spatialSlow) { shape = .heart }
            }
        }
    }
}

// MARK: - Pezzi

/// Il marchio: "BCW" e un "+" in una forma piena, come la scritta del logo.
struct PlusWordmark: View {
    var size: CGFloat = 44
    var color: Color = Theme.onPrimaryContainer

    var body: some View {
        HStack(spacing: size * 0.16) {
            Text("BCW")
                .font(.m3(size, weight: 800, rounded: true))
                .tracking(-size * 0.01)
                .foregroundStyle(color)
            Shaped(shape: .cookie9Sided, fill: Theme.primary, size: size * 1.02) {
                Icon("plus", size: size * 0.7)
                    .foregroundStyle(Theme.onPrimary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("BCW+")
    }
}

/// Una funzione di BCW+: icona in una forma nella tinta, titolo e spiegazione.
private struct PlusFeatureRow: View {
    let icon: String
    let shape: MaterialShapeName
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Shaped(shape: shape, fill: tint.opacity(0.18), size: 44) {
                Icon(icon, size: 24)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.m3(17, weight: 600))
                    .foregroundStyle(Theme.ink)
                Text(text)
                    .font(.m3(.bodyM))
                    .foregroundStyle(Theme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }
}

/// Due widget veri (Orario piccolo e Lezione in corso piccolo) con i dati di esempio e i colori del
/// tema, inclinati e accavallati come carte.
private struct PlusWidgetShowcase: View {
    let colorScheme: ColorScheme
    private let now = Date()

    private var snapshot: WidgetSnapshot {
        var snapshot = WidgetSnapshot.sample(now: now)
        snapshot.theme = WidgetExporter.themeSnapshot()
        return snapshot
    }

    var body: some View {
        let snapshot = snapshot
        let palette = WidgetPalette(theme: snapshot.theme, colorScheme: colorScheme, look: .fullColor)
        HStack(spacing: -26) {
            widget(.timetable, snapshot: snapshot, palette: palette)
                .rotationEffect(.degrees(-6))
                .offset(y: 6)
            widget(.now, snapshot: snapshot, palette: palette)
                .rotationEffect(.degrees(5))
                .offset(y: -4)
        }
        .scaleEffect(0.82)
        .frame(height: 150)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func widget(_ kind: BCWWidgetKind, snapshot: WidgetSnapshot, palette: WidgetPalette) -> some View {
        kind.content(snapshot: snapshot, now: now, family: .systemSmall, palette: palette)
            .padding(16)
            .frame(width: 164, height: 164)
            .background(kind.background(palette))
            .clipShape(.rect(cornerRadius: 26, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.18), radius: 14, y: 8)
    }
}

/// Forma di Material che ruota piano, all'infinito (ferma con le animazioni ridotte), come le forme
/// attorno a quella dell'introduzione.
struct SpinningShape: View {
    let shape: MaterialShapeName
    let color: Color
    var period: Double = 40
    var reverse = false
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MaterialShape(shape)
            .fill(color)
            .rotationEffect(.degrees(turning ? (reverse ? -360 : 360) : 0))
            .animation(reduceMotion ? nil : .linear(duration: period).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}

/// Il raggio degli angoli in alto del foglio che contiene la vista: quello della prima vista sopra di lei che
/// ritaglia con un raggio (con iOS 26 e 27 `_UIDropShadowClippingView`, 38 punti sull'iPhone 17), da
/// `effectiveRadius(corner:)` o dal raggio del livello.
private struct SheetCornerReader: UIViewRepresentable {
    @Binding var radius: CGFloat?

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.isUserInteractionEnabled = false
        view.onChange = { radius = $0 }
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.onChange = { radius = $0 }
    }

    final class ReaderView: UIView {
        var onChange: ((CGFloat) -> Void)?
        private var reported: CGFloat?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private func report() {
            guard window != nil, let radius = sheetRadius(), radius != reported else { return }
            reported = radius
            // Fuori dall'aggiornamento della vista in corso.
            DispatchQueue.main.async { [weak self] in self?.onChange?(radius) }
        }

        private func sheetRadius() -> CGFloat? {
            var view = superview
            while let current = view {
                if current.clipsToBounds {
                    let radius = max(current.effectiveRadius(corner: .topLeft), current.layer.cornerRadius)
                    if radius > 0 { return radius }
                }
                view = current.superview
            }
            return nil
        }
    }
}

#if DEBUG
/// Prova: elenca nella console le viste sopra la card con il loro raggio (`BCW-SHEET`).
private struct SheetCornerProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) {}

    final class ProbeView: UIView {
        private var printed = 0
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window, printed < 3 else { return }
            printed += 1
            let me = convert(bounds, to: window)
            print("BCW-SHEET card \(me)")
            var view = superview
            while let v = view {
                let f = v.convert(v.bounds, to: window)
                let eff = v.effectiveRadius(corner: .topLeft)
                if v.layer.cornerRadius > 0 || eff > 0 || v.clipsToBounds {
                    print("BCW-SHEET \(type(of: v)) frame=\(f) layer=\(v.layer.cornerRadius) curve=\(v.layer.cornerCurve.rawValue) eff=\(eff) clips=\(v.clipsToBounds) mask=\(v.layer.mask != nil)")
                }
                view = v.superview
            }
        }
    }
}
#endif

#if DEBUG
/// Immagine promozionale dell'acquisto in app per App Store Connect (1024 × 1024): il marchio di BCW+ con il
/// "+" nella forma sotto la scritta. `-BCWGeneratePlusImage <percorso.png>` la scrive ed esce.
enum PlusPromoImage {
    static func generateIfRequested() {
        guard let path = UserDefaults.standard.string(forKey: "BCWGeneratePlusImage") else { return }
        let view = ZStack {
            Theme.primaryContainer
            VStack(spacing: -10) {
                Text("BCW")
                    .font(.m3(300, weight: 800, rounded: true))
                    .tracking(-3)
                    .foregroundStyle(Theme.onPrimaryContainer)
                Shaped(shape: .cookie9Sided, fill: Theme.primary, size: 300) {
                    Icon("plus", size: 260)
                        .foregroundStyle(Theme.onPrimary)
                }
            }
            .offset(y: 10)
        }
        .frame(width: 1024, height: 1024)
        .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let data = renderer.uiImage?.pngData() else { print("BCW-PLUSIMAGE FAIL"); exit(1) }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("BCW-PLUSIMAGE OK \(path)")
        } catch {
            print("BCW-PLUSIMAGE FAIL \(error)")
        }
        exit(0)
    }
}
#endif
