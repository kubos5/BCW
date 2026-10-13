import Foundation
import Security

struct Credentials: Codable, Equatable {
    var username: String
    var password: String
    /// Profilo scelto (per gli account genitore con più figli).
    var ident: String?
}

/// Un account Classeviva salvato sul dispositivo.
struct SavedAccount: Codable, Identifiable, Equatable {
    /// Identificativo locale stabile, usato anche per separare le cache.
    let id: String
    var credentials: Credentials
    var name: String
    var school: String?

    init(credentials: Credentials, name: String, school: String? = nil) {
        self.id = UUID().uuidString
        self.credentials = credentials
        self.name = name
        self.school = school
    }

    var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    /// Stesso utente e stesso profilo (i genitori possono avere un account per figlio).
    func matches(_ other: Credentials) -> Bool {
        credentials.username.caseInsensitiveCompare(other.username) == .orderedSame
            && (credentials.ident ?? "") == (other.ident ?? "")
    }
}

enum Keychain {
    private static let service: String = {
        #if DEBUG
        // Per le prove: `-BCWKeychainService nome` usa un'altra voce e non tocca gli account veri.
        if let test = UserDefaults.standard.string(forKey: "BCWKeychainService") { return test }
        #endif
        return "com.bcw.app.credentials"
    }()
    /// Voce usata dalle versioni con un solo account (migrata alla prima apertura).
    private static let legacyAccount = "classeviva"
    private static let accountsKey = "classeviva.accounts"

    // MARK: Più account

    static func loadAccounts() -> [SavedAccount] {
        if let data = read(accountsKey), let accounts = try? JSONDecoder().decode([SavedAccount].self, from: data) {
            return accounts
        }
        // Migrazione dal formato a singolo account.
        guard let data = read(legacyAccount),
              let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else { return [] }
        let accounts = [SavedAccount(credentials: credentials, name: credentials.username)]
        saveAccounts(accounts)
        remove(legacyAccount)
        return accounts
    }

    static func saveAccounts(_ accounts: [SavedAccount]) {
        guard !accounts.isEmpty else {
            remove(accountsKey)
            return
        }
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        write(data, for: accountsKey)
    }

    // MARK: Primitive

    #if os(macOS)
    /// Su macOS si usa il Portachiavi "moderno", lo stesso di iOS, che però richiede l'autorizzazione
    /// `application-identifier` (app firmata con un profilo di sviluppo). Senza, si usa il portachiavi
    /// di login. Si capisce all'avvio con una cancellazione di prova: senza autorizzazione cancellare e
    /// salvare rispondono `errSecMissingEntitlement`, mentre leggere risponde solo `errSecItemNotFound`
    /// (verificato su macOS 27). Prima la scelta avveniva solo al primo salvataggio, quindi a ogni
    /// avvio la lettura cercava nel Portachiavi moderno, non trovava gli account e l'app tornava alla
    /// schermata di accesso.
    private static let usesDataProtection: Bool = {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "probe",
            kSecUseDataProtectionKeychain as String: true,
        ]
        return SecItemDelete(probe as CFDictionary) != errSecMissingEntitlement
    }()
    #endif

    /// - Parameter dataProtection: su macOS, se cercare nel Portachiavi moderno o in quello di login.
    private static func query(_ account: String, dataProtection: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        if dataProtection && usesDataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        #endif
        return query
    }

    private static func write(_ data: Data, for account: String) {
        remove(account)
        var item = query(account)
        item[kSecValueData as String] = data
        #if os(macOS)
        if usesDataProtection {
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        #else
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func copy(_ query: [String: Any]) -> Data? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func read(_ account: String) -> Data? {
        if let data = copy(query(account)) { return data }
        #if os(macOS)
        // Con il Portachiavi moderno disponibile, una voce rimasta in quello di login (salvata da
        // una versione firmata senza autorizzazione) viene letta e spostata.
        if usesDataProtection, let data = copy(query(account, dataProtection: false)) {
            write(data, for: account)
            SecItemDelete(query(account, dataProtection: false) as CFDictionary)
            return data
        }
        #endif
        return nil
    }

    private static func remove(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
