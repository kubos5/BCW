import SwiftUI
import UIKit
import os

/// Applica l'icona scelta in Impostazioni › Aspetto › Icona dell'app (`setAlternateIconName`).
///
/// iOS mostra un avviso a ogni cambio d'icona, quindi i cambi ravvicinati si uniscono (si applica
/// dopo una breve pausa) e l'icona cambia solo se cambia davvero il suo nome: con "Tema dell'app"
/// solo quando il colore proposto più vicino all'accento è un altro, non a ogni tocco sui colori.
/// Mentre è aperta Impostazioni › Aspetto i cambi dovuti al solo colore d'accento aspettano l'uscita
/// dalla pagina (`holdThemeChanges`), così provando i colori compare al massimo un avviso.
/// Si applica solo con l'app attiva; tornando nell'app si ricontrolla (es. dopo una
/// sincronizzazione arrivata in secondo piano). iOS impiega qualche secondo prima del suo avviso:
/// nel frattempo un avviso in basso dice che il cambio è in corso (`isChanging`).
@Observable
final class AppIconController {
    static let shared = AppIconController()

    /// Messaggio dell'ultimo errore, mostrato in un avviso da `AppIconStatusReporter`.
    var failure: String?
    /// Un cambio d'icona sta per partire o aspetta iOS ("Cambio dell'icona in corso…").
    private(set) var isChanging = false

    @ObservationIgnored private var started = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var applying = false
    /// Nome che iOS ha rifiutato e tentativi falliti: al primo errore si riprova da soli (subito
    /// dopo l'installazione iOS può non avere ancora registrato le icone), al secondo compare
    /// l'avviso e si riprova solo quando cambiano le opzioni o si torna nell'app.
    @ObservationIgnored private var refusedName: String??
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.bcw-classeviva.app", category: "AppIcon")
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
        guard started else { return }
        if failures > 1 { failures = 1 }
        // Con Impostazioni › Aspetto aperta si controlla all'uscita: un cambio arrivato in secondo
        // piano (es. dall'account BCW) altrimenti restava in sospeso fino al ritorno successivo.
        guard holds == 0 else {
            heldChange = true
            return
        }
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

    private var options: String { ThemeStore.shared.appIconColor.rawValue }

    private func observe() {
        withObservationTracking {
            // Legge l'accento solo con "Tema dell'app".
            _ = ThemeStore.shared.appIconChoice
        } onChange: {
            // `shared`, non `self`: la chiusura può partire su un altro thread.
            Task { @MainActor in AppIconController.shared.choiceChanged() }
        }
    }

    private func choiceChanged() {
        observe()
        refusedName = nil
        failures = 0
        // Scelte nella pagina dell'icona (o arrivate dall'account BCW): dopo una breve pausa, che
        // unisce i tocchi ravvicinati. Colore del tema: all'uscita da Aspetto, se è aperta,
        // altrimenti dopo una pausa più lunga.
        let options = options
        let manual = options != lastOptions
        lastOptions = options
        if !manual && holds > 0 {
            pending?.cancel()
            heldChange = true
            return
        }
        // Scelta a mano: l'avviso compare subito e iOS viene chiamato dopo poco.
        if manual, willChange { isChanging = true }
        schedule(after: manual ? .milliseconds(400) : .seconds(2))
    }

    /// L'icona scelta non è quella attuale.
    private var willChange: Bool {
        let app = UIApplication.shared
        return app.supportsAlternateIcons && ThemeStore.shared.appIconChoice.assetName != app.alternateIconName
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
        guard !applying else { return }
        guard app.supportsAlternateIcons, app.applicationState == .active else {
            isChanging = false
            return
        }
        let name = ThemeStore.shared.appIconChoice.assetName
        guard name != app.alternateIconName, refusedName != .some(name) || failures < 2 else {
            isChanging = false
            return
        }
        applying = true
        isChanging = true
        defer {
            applying = false
            isChanging = false
        }
        // Una riga per ogni richiesta a iOS (quindi per ogni avviso): sul dispositivo si controlla in Console.
        log.info("Cambio d'icona: \(name ?? "principale", privacy: .public)")
        do {
            try await app.setAlternateIconName(name)
            refusedName = nil
            failures = 0
        } catch where app.alternateIconName == name {
            // Sul simulatore l'avviso di iOS non si apre (errore di I/O) ma l'icona cambia lo stesso.
            log.info("Icona \(name ?? "principale", privacy: .public) cambiata senza avviso: \(error.localizedDescription, privacy: .public)")
            refusedName = nil
            failures = 0
        } catch {
            log.error("Icona \(name ?? "principale", privacy: .public) rifiutata: \(error.localizedDescription, privacy: .public)")
            failures = refusedName == .some(name) ? failures + 1 : 1
            refusedName = .some(name)
            if failures == 1 {
                schedule(after: .seconds(3))
            } else if failures == 2 {
                failure = "Non è stato possibile cambiare l'icona dell'app."
            }
            return
        }
        // Le opzioni sono cambiate mentre iOS cambiava l'icona: si ricontrolla.
        if ThemeStore.shared.appIconChoice.assetName != name { schedule(after: .milliseconds(700)) }
    }
}

/// Mostra in un avviso il cambio d'icona in corso e gli errori (va messo dentro `overlayHost()`).
struct AppIconStatusReporter: ViewModifier {
    @Environment(OverlayHost.self) private var host: OverlayHost?
    @State private var progressToast: UUID?

    func body(content: Content) -> some View {
        content
            .onChange(of: AppIconController.shared.isChanging) { _, changing in
                if changing {
                    progressToast = host?.showToast("Cambio dell'icona in corso…", inProgress: true,
                                                    duration: .seconds(20))
                } else if let id = progressToast {
                    host?.dismissToast(id)
                    progressToast = nil
                }
            }
            .onChange(of: AppIconController.shared.failure) { _, message in
                guard let message else { return }
                host?.showToast(message, icon: "alertCircle")
                AppIconController.shared.failure = nil
            }
    }
}
