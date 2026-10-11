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

    /// Portachiavi da usare, in ordine: `true` è quello "moderno" (data protection), lo stesso di
    /// iOS. Su macOS richiede un'app firmata con un profilo di provisioning; senza, si usa il
    /// portachiavi di login. Attenzione: senza autorizzazione `SecItemAdd` e `SecItemDelete`
    /// rispondono `errSecMissingEntitlement`, ma `SecItemCopyMatching` risponde
    /// `errSecItemNotFound` (verificato). Per questo in lettura si guardano sempre entrambi:
    /// prima si ripiegava solo sull'errore di autorizzazione, la lettura non trovava l'account
    /// salvato nel portachiavi di login e a ogni avvio si tornava alla schermata di accesso.
    private static var stores: [Bool] {
        #if os(macOS)
        [true, false]
        #else
        [true]
        #endif
    }

    private static func query(_ account: String, dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        #endif
        return query
    }

    /// Salva nel primo portachiavi che accetta la voce (e la toglie dagli altri).
    private static func write(_ data: Data, for account: String) {
        remove(account)
        for dataProtection in stores {
            var item = query(account, dataProtection: dataProtection)
            item[kSecValueData as String] = data
            if dataProtection {
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
            if SecItemAdd(item as CFDictionary, nil) == errSecSuccess { return }
        }
    }

    private static func read(_ account: String) -> Data? {
        for dataProtection in stores {
            var search = query(account, dataProtection: dataProtection)
            search[kSecReturnData as String] = true
            search[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess, let data = result as? Data {
                return data
            }
        }
        return nil
    }

    private static func remove(_ account: String) {
        for dataProtection in stores {
            SecItemDelete(query(account, dataProtection: dataProtection) as CFDictionary)
        }
    }
}
