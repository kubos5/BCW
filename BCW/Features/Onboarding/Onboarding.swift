import SwiftUI

/// L'introduzione: alla prima apertura dell'app e, a richiesta, da Impostazioni › Generale. Finché non
/// si sceglie un colore l'app è in bianco e nero (`ThemeStore.isMonochrome`). Cambio dell'icona in
/// attesa (`AppIconController`): l'avviso di iOS coprirebbe l'animazione dei colori.
@Observable
final class Onboarding {
    static let shared = Onboarding()

    private static let completedKey = "onboardingCompleted"

    /// È la prima volta: nessuna introduzione finita e nessun segno che l'app fosse già in uso
    /// (account nel Portachiavi, demo). Chi aggiorna l'app non la vede.
    ///
    /// Dopo il riavvio del dispositivo iOS può avviare l'app in background prima del primo sblocco
    /// (attività in diretta programmata, aggiornamento in background): fino ad allora preferenze e
    /// Portachiavi non si leggono, quindi sembrava la prima volta e l'introduzione ricompariva a ogni
    /// riavvio (segnalato dall'utente). Senza dati leggibili non è mai la prima volta
    /// (`ProtectedData.isAvailableAtLaunch`).
    static let isFirstRun: Bool = {
        let defaults = UserDefaults.standard
        #if DEBUG
        // Per le prove: `-BCWOnboarding YES` la mostra sempre, `NO` mai.
        if defaults.object(forKey: "BCWOnboarding") != nil { return defaults.bool(forKey: "BCWOnboarding") }
        #endif
        guard ProtectedData.isAvailableAtLaunch else { return false }
        if defaults.bool(forKey: completedKey) { return false }
        let firstRun = !defaults.bool(forKey: "demoMode") && Keychain.loadAccounts().isEmpty
            && Keychain.loadCloudSession() == nil
        if !firstRun { defaults.set(true, forKey: completedKey) }
        return firstRun
    }()

    private(set) var isPresented = Onboarding.isFirstRun
    /// Riaperta dalle Impostazioni: "Salta" chiude e basta.
    private(set) var isReplay = false

    private init() {}

    /// La riapre dalle Impostazioni: un cerchio svuota l'app dei colori e sotto c'è l'introduzione.
    func present() {
        guard !isPresented else { return }
        isReplay = true
        ThemeReveal.perform {
            ThemeStore.shared.isMonochrome = true
            isPresented = true
        }
    }

    /// Fine dell'introduzione (anche saltandola): un cerchio da `point` mostra quello che c'è sotto,
    /// l'accesso o l'app, con i colori veri.
    func finish(from point: CGPoint?) {
        guard isPresented else { return }
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        ThemeReveal.perform(from: point) {
            ThemeStore.shared.isMonochrome = false
            isPresented = false
        }
        AppIconController.shared.onboardingFinished()
    }
}

/// Dati protetti del dispositivo (preferenze, Portachiavi, file dell'app): prima del primo sblocco dopo
/// un riavvio non si leggono, e `UserDefaults` risponde come se fosse vuoto.
enum ProtectedData {
    /// Leggibili all'avvio del processo: le preferenze si aprono (o non esistono ancora, cioè la vera
    /// prima apertura). Il file delle preferenze ha la protezione "fino al primo sblocco": prima non si
    /// apre in lettura, anche se esiste.
    static let isAvailableAtLaunch: Bool = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        guard let id = Bundle.main.bundleIdentifier,
              let file = library?.appendingPathComponent("Preferences/\(id).plist"),
              FileManager.default.fileExists(atPath: file.path) else { return true }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return false }
        try? handle.close()
        return true
    }()

    /// Avviata prima del primo sblocco, l'app ha letto preferenze e tema vuoti (`ThemeStore`,
    /// `Preferences`, introduzione): quando i dati diventano leggibili e l'app è ancora in background,
    /// il processo esce, così all'apertura riparte da capo con i dati veri. In primo piano non succede
    /// (l'app non si apre prima dello sblocco).
    static func restartWhenAvailableIfNeeded() {
        guard !isAvailableAtLaunch else { return }
        NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                guard UIApplication.shared.applicationState == .background else { return }
                exit(0)
            }
        }
    }
}
