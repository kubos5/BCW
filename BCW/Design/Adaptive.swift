import SwiftUI

// Mattoni per le pagine dell'iPad con la finestra larga (`WindowClass.regular`): soglie di
// larghezza con isteresi, pagine in due colonne (come `.split` della versione web), griglie
// adattive e larghezza di lettura. Con la finestra stretta (e sempre su iPhone) non cambiano
// nulla: la pagina resta quella del telefono.

/// Misure delle pagine affiancate, come `.split` della versione web adattato all'app.
enum SplitMetrics {
    /// Larghezza della pagina da cui si affiancano le colonne (768 per tornare in colonna).
    static let threshold: CGFloat = 792
    /// Isteresi delle soglie: si spegne sotto soglia − 24.
    static let hysteresis: CGFloat = 24
    /// Colonna laterale: margini in alto, verso la principale, in fondo.
    static let sideTop: CGFloat = 8
    static let sideTrailing: CGFloat = 12
    static let bottom: CGFloat = 40
    /// Colonna principale: margine verso la laterale e larghezza massima del contenuto.
    static let mainLeading: CGFloat = 12
    static let mainMaxWidth: CGFloat = 980
}

extension View {
    /// Accende `isOn` quando la vista è larga almeno `threshold` punti e lo spegne sotto
    /// `threshold − 24`. Con la finestra stretta (o su iPhone) resta spento: nessuna pagina si divide.
    /// Si misura un `Bool`, non la larghezza: la pagina si ricalcola solo al passaggio della soglia.
    func widthAtLeast(_ threshold: CGFloat, isOn: Binding<Bool>) -> some View {
        modifier(WidthThreshold(threshold: threshold, isOn: isOn))
    }

    /// Larghezza di lettura sull'iPad largo: il contenuto resta largo al massimo `max` punti,
    /// allineato all'inizio (come `.readable` della versione web). Altrove non cambia nulla.
    func readableWidth(_ max: CGFloat = 860) -> some View {
        modifier(ReadableWidth(max: max))
    }

    /// Per il dettaglio aperto nella pila quando una pagina con elenco e dettaglio torna in colonna
    /// (es. ruotando l'iPad): se lo spazio torna abbastanza per affiancare, la pagina si chiude e il
    /// dettaglio ricompare accanto all'elenco. La pagina sotto non lo può fare da sé: finché è
    /// coperta non si ridimensiona.
    func dismissesWhenSplit() -> some View {
        modifier(DismissWhenSplit())
    }

    /// Margini del contenuto della colonna principale di una pagina affiancata composta a mano
    /// (Dashboard, Orario), come in `SplitPage`: 12 verso la colonna laterale, il margine della
    /// pagina a destra, largo al massimo `maxWidth` e allineato all'inizio.
    func splitMainPadding(maxWidth: CGFloat = SplitMetrics.mainMaxWidth, top: CGFloat = SplitMetrics.sideTop,
                          bottom: CGFloat = SplitMetrics.bottom) -> some View {
        modifier(SplitMainPadding(maxWidth: maxWidth, top: top, bottom: bottom))
    }
}

private struct SplitMainPadding: ViewModifier {
    let maxWidth: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    @Environment(\.pageGutter) private var gutter

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.leading, SplitMetrics.mainLeading)
            .padding(.trailing, gutter)
            .padding(.top, top)
            .padding(.bottom, bottom)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DismissWhenSplit: ViewModifier {
    @State private var wide = false
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .widthAtLeast(SplitMetrics.threshold, isOn: $wide)
            .onChange(of: wide) { _, wide in
                if wide { dismiss() }
            }
    }
}

private struct WidthThreshold: ViewModifier {
    let threshold: CGFloat
    @Binding var isOn: Bool
    @Environment(\.windowClass) private var windowClass
    /// Ultima larghezza, per ricalcolare quando cambia solo la classe della finestra.
    @State private var width = UnobservedValue<CGFloat>(0)

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Bool.self) { proxy in
                resolve(proxy.size.width, regular: windowClass == .regular)
            } action: { value in
                set(value)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width.value = $0 }
            .onChange(of: windowClass) { _, windowClass in
                set(resolve(width.value, regular: windowClass == .regular))
            }
    }

    private func resolve(_ width: CGFloat, regular: Bool) -> Bool {
        guard regular else { return false }
        return width >= (isOn ? threshold - SplitMetrics.hysteresis : threshold)
    }

    private func set(_ value: Bool) {
        guard value != isOn else { return }
        // Senza animazione: la pagina cambia disposizione di colpo, come ruotando lo schermo.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isOn = value }
    }
}

private struct ReadableWidth: ViewModifier {
    let max: CGFloat
    @Environment(\.windowClass) private var windowClass

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: windowClass == .regular ? max : .infinity, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pagina in due colonne che scorrono ciascuna per conto suo: a sinistra una colonna laterale
/// larga `sideWidth` (con una parte ferma in cima, es. la settimana), a destra il contenuto
/// principale, largo al massimo `mainMaxWidth`. Il ritorno in cima e l'aggiornamento tirando
/// verso il basso valgono per la colonna principale. Da usare solo quando la pagina è affiancata
/// (`widthAtLeast(SplitMetrics.threshold, …)`).
struct SplitPage<SideHeader: View, Side: View, Main: View>: View {
    var sideWidth: CGFloat = 380
    var mainMaxWidth: CGFloat = SplitMetrics.mainMaxWidth
    var refresh: (() async -> Void)?
    @ViewBuilder let sideHeader: () -> SideHeader
    @ViewBuilder let side: () -> Side
    @ViewBuilder let main: () -> Main

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SplitSide(width: sideWidth, header: sideHeader, content: side)
            ScrollView {
                main()
                    .splitMainPadding(maxWidth: mainMaxWidth)
            }
            .tracksPageScroll()
            .scrollsToTopOnReselect()
            .modifier(OptionalRefresh(action: refresh))
        }
    }
}

extension SplitPage where SideHeader == EmptyView {
    init(sideWidth: CGFloat = 380, mainMaxWidth: CGFloat = SplitMetrics.mainMaxWidth,
         refresh: (() async -> Void)? = nil,
         @ViewBuilder side: @escaping () -> Side, @ViewBuilder main: @escaping () -> Main) {
        self.init(sideWidth: sideWidth, mainMaxWidth: mainMaxWidth, refresh: refresh,
                  sideHeader: { EmptyView() }, side: side, main: main)
    }
}

/// Colonna laterale di una pagina affiancata: una parte ferma in cima (facoltativa) e sotto un
/// contenuto che scorre, con i margini del web (a sinistra quello della pagina, 12 verso la
/// colonna principale). Usata da `SplitPage` e dalle pagine che compongono le colonne a mano
/// (Dashboard, Orario).
struct SplitSide<Header: View, Content: View>: View {
    let width: CGFloat
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content
    @Environment(\.pageGutter) private var gutter

    var body: some View {
        VStack(spacing: 0) {
            header()
                .padding(.leading, gutter)
                .padding(.trailing, SplitMetrics.sideTrailing)
            ScrollView {
                content()
                    .padding(.leading, gutter)
                    .padding(.trailing, SplitMetrics.sideTrailing)
                    .padding(.top, SplitMetrics.sideTop)
                    .padding(.bottom, SplitMetrics.bottom)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            // La barra di sistema (Liquid Glass) segue lo scorrimento principale, non questo.
            .scrollEdgeEffectHidden(true, for: .top)
        }
        .frame(width: width + gutter + SplitMetrics.sideTrailing)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

extension SplitSide where Header == EmptyView {
    init(width: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.init(width: width, header: { EmptyView() }, content: content)
    }
}

/// `.refreshable` solo se c'è un'azione.
private struct OptionalRefresh: ViewModifier {
    let action: (() async -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content.refreshable { await action() }
        } else {
            content
        }
    }
}

/// Elementi in colonne adattive sull'iPad largo (ognuna larga almeno `minimum` punti, allineate
/// in alto); altrove una colonna sola, come sul telefono.
struct AdaptiveColumns<Content: View>: View {
    var minimum: CGFloat = 380
    var spacing: CGFloat = 20
    @ViewBuilder let content: () -> Content
    @Environment(\.windowClass) private var windowClass

    var body: some View {
        if windowClass == .regular {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: spacing, alignment: .top)],
                      alignment: .leading, spacing: spacing, content: content)
        } else {
            VStack(alignment: .leading, spacing: spacing, content: content)
        }
    }
}
