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
    private static let service = "com.bcw.app.credentials"
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
    /// Su macOS si usa il Portachiavi "moderno", lo stesso di iOS, che però richiede un'app
    /// firmata con un team di sviluppo. Con la firma locale si ripiega sul portachiavi di login.
    private static var usesDataProtection = true
    #endif

    private static func query(_ account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        if usesDataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        #endif
        return query
    }

    /// Esegue un'operazione e, se su macOS manca l'autorizzazione al Portachiavi moderno,
    /// la ripete sul portachiavi di login.
    private static func withFallback(_ operation: () -> OSStatus) -> OSStatus {
        let status = operation()
        #if os(macOS)
        if status == errSecMissingEntitlement && usesDataProtection {
            usesDataProtection = false
            return operation()
        }
        #endif
        return status
    }

    private static func write(_ data: Data, for account: String) {
        remove(account)
        _ = withFallback {
            var item = query(account)
            item[kSecValueData as String] = data
            #if os(macOS)
            if usesDataProtection {
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
            #else
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            #endif
            return SecItemAdd(item as CFDictionary, nil)
        }
    }

    private static func read(_ account: String) -> Data? {
        var result: AnyObject?
        let status = withFallback {
            var search = query(account)
            search[kSecReturnData as String] = true
            search[kSecMatchLimit as String] = kSecMatchLimitOne
            return SecItemCopyMatching(search as CFDictionary, &result)
        }
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func remove(_ account: String) {
        _ = withFallback { SecItemDelete(query(account) as CFDictionary) }
    }
}
