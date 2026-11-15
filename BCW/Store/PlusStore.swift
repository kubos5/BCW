import OSLog
import StoreKit
import SwiftUI

/// Le due build di BCW, dalla stessa base di codice (richiesta dell'utente, 4.0):
/// - **GitHub** (schema "BCW", configurazioni Debug e Release): tutto sbloccato, con l'avviso delle
///   nuove versioni pubblicate su GitHub (`UpdateChecker`).
/// - **App Store** (schema "BCW App Store", configurazioni Debug-AppStore e Release-AppStore, che
///   aggiungono la condizione di compilazione `APPSTORE`): orario, widget e attività in diretta con
///   BCW+ (acquisto unico, `PlusStore`), niente avviso delle nuove versioni (le installa l'App Store).
enum BuildVariant {
    case github, appStore

    static let current: BuildVariant = {
        #if DEBUG
        // Per le prove: `-BCWVariant appStore` fa da build dell'App Store anche con lo schema "BCW"
        // (senza StoreKit: con `-BCWPlusSimulate YES` l'acquisto riesce dopo un secondo).
        if let value = UserDefaults.standard.string(forKey: "BCWVariant") {
            return value == "appStore" ? .appStore : .github
        }
        #endif
        #if APPSTORE
        return .appStore
        #else
        return .github
        #endif
    }()

    static var isAppStore: Bool { current == .appStore }

    /// Nome mostrato in Impostazioni › Generale.
    var title: String { self == .appStore ? "App Store" : "GitHub" }
}

/// BCW+: l'acquisto unico (non consumabile, 2,99 €) che nella build dell'App Store sblocca la scheda
/// Orario (con l'attività in diretta) e i widget. Nella build GitHub è tutto sbloccato.
///
/// Lo stato viene da StoreKit 2 (`Transaction.currentEntitlements`, poi `Transaction.updates` per
/// acquisti fatti altrove, rimborsi e "Chiedi di acquistare") ed è tenuto anche in UserDefaults, così
/// all'avvio senza rete l'app è subito giusta. Tutto ciò che dipende dall'acquisto legge `isUnlocked`
/// (osservabile): dopo il pagamento la scheda Orario compare, i widget si ridisegnano (l'istantanea dei
/// widget cambia e `WidgetExporter` ricarica le linee temporali) e l'attività in diretta può partire.
@Observable
final class PlusStore {
    static let shared = PlusStore()

    /// Identificativo del prodotto in App Store Connect (non consumabile).
    static let productID = "com.bcw-classeviva.app.plus"
    /// Prezzo mostrato finché l'App Store non risponde (quello di listino in Italia).
    static let fallbackPrice = "2,99\u{00A0}€"
    private static let purchasedKey = "plusPurchased"
    private static let log = Logger(subsystem: "com.bcw-classeviva.app", category: "BCWPlus")

    enum Outcome: Equatable {
        case purchased
        /// In attesa di approvazione ("Chiedi di acquistare" o un pagamento da confermare).
        case pending
        case cancelled
        case failed(String)
    }

    /// Acquisto fatto e non rimborsato.
    private(set) var isPurchased: Bool
    /// Il prodotto dell'App Store (prezzo nella valuta dell'utente), quando è arrivato.
    private(set) var product: Product?
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    /// La schermata dell'acquisto è aperta (`PlusPaywallView`, in `RootView`).
    var isPaywallPresented = false

    @ObservationIgnored private var updates: Task<Void, Never>?

    /// Orario, widget e attività in diretta sono disponibili.
    var isUnlocked: Bool { !BuildVariant.isAppStore || isPurchased }

    /// Prezzo nella valuta dell'utente (o quello di listino finché l'App Store non risponde).
    var price: String { product?.displayPrice ?? Self.fallbackPrice }

    private init() {
        var purchased = UserDefaults.standard.bool(forKey: Self.purchasedKey)
        #if DEBUG
        // Per le prove: `-BCWPlus locked|unlocked` (non salvato, StoreKit non lo cambia).
        if let forced = UserDefaults.standard.string(forKey: "BCWPlus") { purchased = forced == "unlocked" }
        #endif
        isPurchased = purchased
    }

    /// All'avvio (`RootView`): stato dall'App Store, prezzo e aggiornamenti delle transazioni.
    func start() {
        guard BuildVariant.isAppStore, updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task {
            await refreshEntitlements()
            await loadProduct()
        }
    }

    /// Apre la schermata dell'acquisto (banner delle Impostazioni, scheda Orario, introduzione, widget).
    func presentPaywall() {
        guard BuildVariant.isAppStore, !isPurchased else { return }
        isPaywallPresented = true
    }

    func loadProduct() async {
        guard BuildVariant.isAppStore, product == nil else { return }
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            Self.log.error("Prodotto non caricato: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Rilegge dall'App Store gli acquisti validi su questo account.
    func refreshEntitlements() async {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "BCWPlus") != nil { return }
        if UserDefaults.standard.bool(forKey: "BCWPlusSimulate") { return }
        #endif
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result, transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        setPurchased(owned)
    }

    /// Acquisto con l'azione di SwiftUI (`@Environment(\.purchase)`, che sa in che finestra mostrare la
    /// conferma dell'App Store).
    func purchase(with action: PurchaseAction) async -> Outcome {
        guard !isPurchasing else { return .cancelled }
        isPurchasing = true
        defer { isPurchasing = false }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "BCWPlusSimulate") {
            try? await Task.sleep(for: .seconds(1))
            setPurchased(true)
            return .purchased
        }
        #endif
        await loadProduct()
        guard let product else {
            return .failed("L'App Store non risponde. Controlla la connessione e riprova.")
        }
        do {
            switch try await action(product) {
            case let .success(verification):
                guard case let .verified(transaction) = verification else {
                    return .failed("L'App Store non ha potuto verificare l'acquisto. Riprova più tardi.")
                }
                await transaction.finish()
                setPurchased(true)
                return .purchased
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            Self.log.error("Acquisto non riuscito: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// "Ripristina acquisti": sincronizza con l'App Store (può chiedere l'Apple ID). `true` se BCW+ c'è.
    func restore() async -> Bool {
        isRestoring = true
        defer { isRestoring = false }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "BCWPlusSimulate") {
            try? await Task.sleep(for: .seconds(1))
            return isPurchased
        }
        #endif
        try? await AppStore.sync()
        await refreshEntitlements()
        return isPurchased
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case let .verified(transaction) = result, transaction.productID == Self.productID else { return }
        setPurchased(transaction.revocationDate == nil)
        await transaction.finish()
    }

    private func setPurchased(_ purchased: Bool) {
        guard purchased != isPurchased else { return }
        withAnimation(Motion.spatial) { isPurchased = purchased }
        UserDefaults.standard.set(purchased, forKey: Self.purchasedKey)
        Self.log.info("BCW+ \(purchased ? "attiva" : "non attiva", privacy: .public)")
    }
}
