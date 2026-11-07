import SwiftUI
import UIKit
import os

/// Applica l'icona scelta in Impostazioni › Aspetto › Icona dell'app (`setAlternateIconName`).
///
/// La richiesta a iOS parte appena cambia l'icona scelta, che sia per un tocco nella pagina
/// dell'icona, per un nuovo colore d'accento con "Tema dell'app" o per una sincronizzazione con
/// l'account BCW; l'icona cambia solo se cambia davvero il suo nome. Si applica solo con l'app
/// attiva; tornando attiva si ricontrolla (es. dopo una sincronizzazione arrivata in secondo piano,
/// o dopo l'avviso di iOS).
///
/// Come si comporta iOS 27 (verificato sul simulatore):
/// - iOS cambia l'icona e mostra il suo avviso, poi risponde solo quando l'utente preme OK: la
///   risposta non dice quando l'icona è cambiata. Lo dice l'app che smette di essere attiva, perché
///   l'avviso sta fuori dall'app.
/// - Finché iOS non risponde, leggere `alternateIconName` blocca il thread principale (aspetta la
///   stessa coda della richiesta): l'app restava ferma fino all'OK. Quindi il nome attuale si tiene
///   in `currentName` e durante una richiesta non si legge mai.
/// - Due richieste insieme fanno rispondere a iOS con l'errore EAGAIN, che resta fino al riavvio:
///   ne parte una alla volta e la scelta si ricontrolla alla risposta, quindi i cambi ravvicinati si
///   uniscono.
///
/// Se dopo un secondo l'avviso di iOS non è ancora comparso, un avviso in basso dice che il cambio è
/// in corso (`isSlow`), e sparisce appena compare quello di iOS.
@Observable
final class AppIconController {
    static let shared = AppIconController()

    /// Dopo quanto l'attesa merita un avviso.
    private static let slowAfter: Duration = .seconds(1)

    /// Messaggio dell'ultimo errore, mostrato in un avviso da `AppIconStatusReporter`.
    var failure: String?
    /// iOS non ha ancora mostrato il suo avviso dopo `slowAfter` ("Cambio dell'icona in corso…").
    private(set) var isSlow = false

    @ObservationIgnored private var started = false
    /// iOS non ha ancora risposto all'ultima richiesta (`alternateIconName` non si può leggere).
    @ObservationIgnored private var isRequesting = false
    /// Nome dell'icona attuale (`nil` finché non si è letto).
    @ObservationIgnored private var currentName: String??
    @ObservationIgnored private var slowTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    /// Nome che iOS ha rifiutato e tentativi falliti: al primo errore si riprova da soli (subito
    /// dopo l'installazione iOS può non avere ancora registrato le icone), al secondo compare
    /// l'avviso e si riprova solo quando cambia la scelta o si torna nell'app.
    @ObservationIgnored private var refusedName: String??
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.bcw-classeviva.app", category: "AppIcon")

    private init() {}

    /// Avvia il controllo (all'avvio dell'interfaccia).
    func start() {
        guard !started else { return }
        started = true
        observe()
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil,
                                               queue: .main) { _ in
            Task { @MainActor in AppIconController.shared.appResignedActive() }
        }
        // All'avvio non subito: l'avviso di iOS non deve coprire l'app che si apre.
        retry(after: .seconds(1))
    }

    /// Finita l'introduzione si applica l'icona del tema scelto, dopo il cerchio dei colori.
    func onboardingFinished() {
        retry(after: .seconds(1.2))
    }

    /// L'app è tornata attiva: se l'icona non è quella scelta, la cambia.
    func sceneBecameActive() {
        guard started else { return }
        if failures > 1 { failures = 1 }
        apply()
    }

    /// Il nome dell'icona scelta.
    private var wantedName: String? {
        #if DEBUG
        // Per le prove sul telefono: `-BCWIconTest verde` chiede quell'icona senza toccare le
        // impostazioni, che con l'account BCW finirebbero sul server (`iconcolor=` e `-BCWAccent` sì).
        if let test = UserDefaults.standard.string(forKey: "BCWIconTest"), let color = AppIconColor(stored: test), color != .theme {
            return AppIconChoice(color: color).assetName
        }
        #endif
        return ThemeStore.shared.appIconChoice.assetName
    }

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
        apply()
    }

    private func retry(after delay: Duration) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.apply()
        }
    }

    /// Chiede a iOS l'icona scelta, se non è quella attuale e non c'è già una richiesta in corso.
    private func apply() {
        let app = UIApplication.shared
        guard started, !isRequesting, app.supportsAlternateIcons, app.applicationState == .active else { return }
        // Durante l'introduzione l'avviso di iOS coprirebbe il cambio di colori: si aspetta la fine.
        guard !Onboarding.shared.isPresented else { return }
        let name = wantedName
        let current = currentName ?? app.alternateIconName
        currentName = .some(current)
        guard name != current, refusedName != .some(name) || failures < 2 else { return }
        retryTask?.cancel()
        isRequesting = true
        // Una riga per ogni richiesta a iOS (quindi per ogni avviso): sul dispositivo si controlla in Console.
        log.info("Cambio d'icona: \(name ?? "principale", privacy: .public)")
        report("richiesta \(name ?? "principale")")
        slowTask = Task { [weak self] in
            try? await Task.sleep(for: Self.slowAfter)
            guard !Task.isCancelled else { return }
            self?.isSlow = true
            self?.report("in ritardo")
        }
        Task { [weak self] in
            #if DEBUG
            // Per le prove: `-BCWIconDelay 3` fa aspettare iOS 3 secondi (l'avviso "in corso").
            try? await Task.sleep(for: .seconds(UserDefaults.standard.double(forKey: "BCWIconDelay")))
            #endif
            do {
                try await app.setAlternateIconName(name)
                self?.finished(name: name, error: nil)
            } catch {
                self?.finished(name: name, error: error)
            }
        }
    }

    /// L'app non è più attiva: iOS mostra il suo avviso (o l'utente ha lasciato l'app). Il nostro
    /// non serve più.
    private func appResignedActive() {
        guard isRequesting else { return }
        report("app non più attiva")
        slowTask?.cancel()
        isSlow = false
    }

    private func finished(name: String?, error: Error?) {
        isRequesting = false
        slowTask?.cancel()
        isSlow = false
        // Sul simulatore di iOS 26 l'avviso non si apre (errore di I/O) ma l'icona cambia lo stesso.
        let actual = UIApplication.shared.alternateIconName
        currentName = .some(actual)
        let refused = error != nil && actual != name
        if refused, let error {
            log.error("Icona \(name ?? "principale", privacy: .public) rifiutata: \(error.localizedDescription, privacy: .public)")
            failures = refusedName == .some(name) ? failures + 1 : 1
            refusedName = .some(name)
        } else {
            refusedName = nil
            failures = 0
        }
        report("risposta: \(error.map { "\($0.localizedDescription)" } ?? "ok"), icona \(actual ?? "principale")")
        // La scelta è cambiata mentre iOS rispondeva: si ricontrolla subito.
        if wantedName != name {
            apply()
        } else if refused {
            if failures == 1 {
                retry(after: .seconds(3))
            } else if failures == 2 {
                failure = "Non è stato possibile cambiare l'icona dell'app."
            }
        }
    }

    private func report(_ message: String) {
        #if DEBUG
        print("BCW-ICON \(Date().timeIntervalSinceReferenceDate) \(message)")
        #endif
    }
}

/// Mostra in un avviso il cambio d'icona in ritardo e gli errori (va messo dentro `overlayHost()`).
struct AppIconStatusReporter: ViewModifier {
    @Environment(OverlayHost.self) private var host: OverlayHost?
    @State private var progressToast: UUID?

    func body(content: Content) -> some View {
        content
            .onChange(of: AppIconController.shared.isSlow) { _, slow in
                if slow {
                    progressToast = host?.showToast("Cambio dell'icona in corso…", inProgress: true,
                                                    duration: .seconds(30))
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
