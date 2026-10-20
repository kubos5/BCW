import SwiftUI
import UIKit

/// Applica l'icona scelta in Impostazioni › Aspetto › Icona dell'app (`setAlternateIconName`).
///
/// iOS mostra un avviso a ogni cambio d'icona, quindi i cambi ravvicinati si uniscono (si applica
/// dopo una breve pausa) e l'icona cambia solo se cambia davvero il suo nome: con "Tema dell'app"
/// solo quando il colore proposto più vicino all'accento è un altro, non a ogni tocco sui colori.
/// Mentre è aperta Impostazioni › Aspetto i cambi dovuti al solo colore d'accento aspettano l'uscita
/// dalla pagina (`holdThemeChanges`), così provando i colori compare al massimo un avviso.
/// Si applica solo con l'app attiva; tornando nell'app si ricontrolla (es. dopo una
/// sincronizzazione arrivata in secondo piano).
@Observable
final class AppIconController {
    static let shared = AppIconController()

    /// Messaggio dell'ultimo errore, mostrato in un avviso da `AppIconFailureReporter`.
    var failure: String?

    @ObservationIgnored private var started = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var applying = false
    /// Nome che iOS ha rifiutato: non si riprova finché le opzioni non cambiano.
    @ObservationIgnored private var refusedName: String??
    /// Opzioni scelte a mano all'ultimo controllo (per distinguerle dai cambi del solo accento).
    @ObservationIgnored private var lastOptions = ""
    /// Pagine aperte che trattengono i cambi del solo colore del tema (Impostazioni › Aspetto).
    @ObservationIgnored private var holds = 0
    /// Un cambio del colore del tema aspetta che le pagine lo lascino passare.
    @ObservationIgnored private var heldChange = false

    private init() {}

    /// Avvia il controllo (all'avvio dell'interfaccia).
    func start() {
        guard !started else { return }
        started = true
        lastOptions = options
        observe()
        schedule(after: .seconds(1))
    }

    /// L'app è tornata attiva: se l'icona non è quella scelta, la cambia.
    func sceneBecameActive() {
        guard started, holds == 0 else { return }
        schedule(after: .milliseconds(600))
    }

    /// Trattiene (`true`, all'apertura della pagina) o lascia passare (`false`, all'uscita) i cambi
    /// d'icona dovuti al solo colore d'accento.
    func holdThemeChanges(_ hold: Bool) {
        holds = max(0, holds + (hold ? 1 : -1))
        guard holds == 0, heldChange else { return }
        heldChange = false
        schedule(after: .milliseconds(500))
    }

    private var options: String {
        let theme = ThemeStore.shared
        return [theme.appIconShape.rawValue, theme.appIconColor.rawValue, theme.appIconAppearance.rawValue,
                theme.appIconDarkBackground.rawValue].joined(separator: "|")
    }

    private func observe() {
        withObservationTracking {
            // Legge l'accento solo con "Tema dell'app".
            _ = ThemeStore.shared.appIconChoice
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observe()
                self.refusedName = nil
                let options = self.options
                // Scelte nella pagina dell'icona (o arrivate dall'account BCW): dopo una breve pausa,
                // che unisce i tocchi ravvicinati. Colore del tema: all'uscita da Aspetto, se è aperta,
                // altrimenti dopo una pausa più lunga.
                let manual = options != self.lastOptions
                self.lastOptions = options
                if !manual && self.holds > 0 {
                    self.pending?.cancel()
                    self.heldChange = true
                    return
                }
                self.schedule(after: manual ? .seconds(1) : .seconds(2))
            }
        }
    }

    private func schedule(after delay: Duration) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.apply()
        }
    }

    private func apply() async {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.applicationState == .active, !applying else { return }
        let name = ThemeStore.shared.appIconChoice.assetName
        guard name != app.alternateIconName, refusedName != .some(name) else { return }
        applying = true
        defer { applying = false }
        do {
            try await app.setAlternateIconName(name)
        } catch {
            refusedName = .some(name)
            failure = "Non è stato possibile cambiare l'icona dell'app."
            print("BCW-APPICON:", name ?? "principale", error.localizedDescription)
            return
        }
        // Le opzioni sono cambiate mentre iOS cambiava l'icona: si ricontrolla.
        if ThemeStore.shared.appIconChoice.assetName != name { schedule(after: .milliseconds(700)) }
    }
}

/// Mostra in un avviso gli errori del cambio d'icona (va messo dentro `overlayHost()`).
struct AppIconFailureReporter: ViewModifier {
    @Environment(OverlayHost.self) private var host: OverlayHost?

    func body(content: Content) -> some View {
        content
            .onChange(of: AppIconController.shared.failure) { _, message in
                guard let message else { return }
                host?.showToast(message, icon: "alertCircle")
                AppIconController.shared.failure = nil
            }
    }
}
