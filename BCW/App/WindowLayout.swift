import SwiftUI
import UIKit

/// Classe della finestra, misurata una volta in `RootView` e passata nell'ambiente.
/// - `compact`: il layout dell'iPhone (sempre su iPhone, anche in orizzontale, e nelle finestre
///   strette dell'iPad).
/// - `regular`: iPad con classe orizzontale regolare e finestra larga almeno 700 punti (si torna
///   `compact` sotto 680): barra laterale, pannello della pagina, pagine affiancate.
/// Tutto ciò che è nuovo per l'iPad dipende da `regular`, così l'iPhone resta com'è.
nonisolated enum WindowClass: Equatable, Sendable {
    case compact, regular

    /// iPad (costante per tutta l'esecuzione): decide le parti della struttura che non possono
    /// cambiare a finestra aperta, come le sezioni di Tu tra le schede di sistema.
    @MainActor static let isPad = UIDevice.current.userInterfaceIdiom == .pad

    /// Larghezza da cui la finestra è larga, e sotto cui torna stretta (isteresi: niente salti
    /// avanti e indietro trascinando il bordo di una finestra attorno alla soglia).
    static let regularWidth: CGFloat = 700
    static let regularExitWidth: CGFloat = 680
    /// Da questa larghezza la barra di navigazione resta espansa accanto al pannello.
    static let railExpandedWidth: CGFloat = 1100
    static let railExpandedExitWidth: CGFloat = 1080
}

/// Ciò che le viste devono sapere della finestra: solo valori che cambiano a scatti, mai la
/// larghezza (che cambierebbe di continuo ridimensionando la finestra).
nonisolated struct WindowLayout: Equatable, Sendable {
    var windowClass: WindowClass = .compact
    /// Finestra abbastanza larga per la barra di navigazione espansa fissa (1100 punti).
    var railExpands = false

    @MainActor static func resolve(width: CGFloat, sizeClass: UserInterfaceSizeClass?, previous: WindowLayout) -> WindowLayout {
        guard WindowClass.isPad else { return WindowLayout() }
        #if DEBUG
        // Per le prove: `-BCWWindowClass compact|regular` forza la classe (solo su iPad), anche a
        // finestra aperta con lo script di prova (`class=compact`).
        let forced = DebugScript.shared.windowClass.map { $0 == .compact ? "compact" : "regular" }
        switch forced ?? UserDefaults.standard.string(forKey: "BCWWindowClass") {
        case "compact": return WindowLayout()
        case "regular": return WindowLayout(windowClass: .regular, railExpands: width >= WindowClass.railExpandedWidth)
        default: break
        }
        #endif
        let wasRegular = previous.windowClass == .regular
        let regular = sizeClass != .compact
            && width >= (wasRegular ? WindowClass.regularExitWidth : WindowClass.regularWidth)
        guard regular else { return WindowLayout() }
        let expands = width >= (previous.railExpands ? WindowClass.railExpandedExitWidth : WindowClass.railExpandedWidth)
        return WindowLayout(windowClass: .regular, railExpands: expands)
    }
}

extension EnvironmentValues {
    /// Classe della finestra (`compact` di serie, quindi anche nei fogli e nelle anteprime).
    @Entry var windowClass: WindowClass = .compact
    /// Finestra larga almeno 1100 punti: la barra di navigazione espansa sta accanto al pannello.
    @Entry var railExpands = false
    /// Margine laterale delle pagine: 16 punti, 24 sull'iPad con la finestra larga.
    @Entry var pageGutter: CGFloat = 16
}

/// Misura la finestra e mette la sua classe nell'ambiente (in `RootView`, dopo `overlayHost`
/// così la vedono anche menu, dialoghi e avvisi).
struct WindowLayoutReader: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var layout = WindowLayout()
    /// Ultima larghezza misurata, per ricalcolare la classe quando cambia solo la classe di
    /// dimensione (non osservata: cambia a ogni passo del ridimensionamento).
    @State private var width = UnobservedValue<CGFloat>(0)

    func body(content: Content) -> some View {
        content
            .environment(\.windowClass, layout.windowClass)
            .environment(\.railExpands, layout.railExpands)
            .onGeometryChange(for: WindowLayout.self) { proxy in
                WindowLayout.resolve(width: proxy.size.width, sizeClass: sizeClass, previous: layout)
            } action: { new in
                update(new)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width.value = $0 }
            .onChange(of: sizeClass) { _, sizeClass in
                update(WindowLayout.resolve(width: width.value, sizeClass: sizeClass, previous: layout))
            }
            #if DEBUG
            .onChange(of: DebugScript.shared.windowClass) {
                update(WindowLayout.resolve(width: width.value, sizeClass: sizeClass, previous: layout))
            }
            #endif
    }

    private func update(_ new: WindowLayout) {
        guard new != layout else { return }
        // Senza animazione: la struttura cambia di colpo, come ruotando lo schermo.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { layout = new }
    }
}

#if DEBUG
/// Per le prove: `-BCWOrientation landscape|portrait` chiede a iOS di ruotare la finestra
/// (`simctl` non sa ruotare il simulatore).
enum DebugOrientation {
    static func applyIfRequested() {
        if let value = UserDefaults.standard.string(forKey: "BCWOrientation") { apply(value) }
    }

    static func apply(_ value: String) {
        let mask: UIInterfaceOrientationMask
        switch value {
        case "landscape": mask = .landscapeRight
        case "portrait": mask = .portrait
        default: return
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                print("BCW-ORIENTATION errore: \(error.localizedDescription)")
            }
        }
    }
}
#endif
