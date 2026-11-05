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
    static let isFirstRun: Bool = {
        let defaults = UserDefaults.standard
        #if DEBUG
        // Per le prove: `-BCWOnboarding YES` la mostra sempre, `NO` mai.
        if defaults.object(forKey: "BCWOnboarding") != nil { return defaults.bool(forKey: "BCWOnboarding") }
        #endif
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
