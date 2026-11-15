import Foundation

/// Le API del sito di Classeviva (`web.spaggiari.eu/rest/w1`): stessi percorsi e formati di quelle
/// dell'app (`rest/v1`), ma per il sito, che entra con il cookie di sessione (PHPSESSID) invece del token
/// (https://github.com/open-viva/endpoints). Servono solo per ciò che l'API dell'app potrebbe non dare:
/// i compiti del modulo Compiti (`homeworks/index`, issue 16).
///
/// Ogni `ClassevivaClient` ha la sua sessione, con i cookie solo in memoria
/// (`URLSessionConfiguration.ephemeral`): gli account non si mescolano e niente resta sul disco. Per
/// entrare usa le credenziali già salvate per l'app, che vanno solo a web.spaggiari.eu, come il login
/// dell'app.
final class ClassevivaWebSession {
    static let restBase = "https://web.spaggiari.eu/rest/w1"
    private static let authURL = "https://web.spaggiari.eu/auth-p7/app/default/AuthApi4.php"
    private static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"

    private let session: URLSession
    private var isSignedIn = false
    private var signInTask: Task<Void, Error>?

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        session = URLSession(configuration: config)
    }

    /// GET sul sito con il token dell'app (`Z-Auth-Token`, senza cookie): se il sito lo accetta non
    /// serve entrare. `nil` se non risponde con un JSON.
    func getWithToken(_ path: String, token: String) async throws -> Data? {
        guard let url = URL(string: Self.restBase + path) else { return nil }
        var request = URLRequest(url: url)
        for (key, value) in URLSessionTransport.defaultHeaders { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue(token, forHTTPHeaderField: "Z-Auth-Token")
        request.httpShouldHandleCookies = false
        let (data, response) = try await session.data(for: request)
        return Self.isJSON(response, status: 200) ? data : nil
    }

    /// GET sul sito con la sua sessione: entra (o rientra, se la sessione è scaduta) con le credenziali.
    func get(_ path: String, credentials: Credentials) async throws -> Data {
        guard let url = URL(string: Self.restBase + path) else { throw APIError.decoding }
        if !isSignedIn { try await signIn(credentials) }
        for attempt in 0..<2 {
            var request = URLRequest(url: url)
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            if Self.isJSON(response, status: 200) { return data }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Sessione scaduta: il sito risponde 401/403 o rimanda alla pagina di accesso (HTML).
            let expired = status == 401 || status == 403 || !Self.isJSON(response, status: status)
            guard expired, attempt == 0 else {
                throw APIError.server(status, ClassevivaClient.errorMessage(from: data) ?? "")
            }
            isSignedIn = false
            try await signIn(credentials)
        }
        throw APIError.notAuthenticated
    }

    // MARK: Accesso

    private func signIn(_ credentials: Credentials) async throws {
        if let signInTask { return try await signInTask.value }
        let task = Task { try await performSignIn(credentials) }
        signInTask = task
        defer { signInTask = nil }
        try await task.value
    }

    private func performSignIn(_ credentials: Credentials) async throws {
        var auth = try await authenticate("aLoginPwd", [
            ("cid", ""), ("uid", credentials.username), ("pwd", credentials.password), ("pin", ""), ("target", ""),
        ])
        // Più profili con le stesse credenziali (genitore con più figli): si sceglie quello dell'app.
        if auth["loggedIn"] as? Bool != true, auth["verified"] as? Bool == true, let ident = credentials.ident {
            auth = try await authenticate("aLoginSam", [("uid", ident)])
        }
        guard auth["loggedIn"] as? Bool == true else {
            throw APIError.unavailable("Il sito di Classeviva non ha accettato l'accesso.")
        }
        isSignedIn = true
    }

    /// Una richiesta ad `AuthApi4.php` (modulo, come il sito): restituisce `data.auth`.
    private func authenticate(_ action: String, _ fields: [(String, String)]) async throws -> [String: Any] {
        guard let url = URL(string: "\(Self.authURL)?a=\(action)") else { throw APIError.decoding }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields)
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let auth = (json["data"] as? [String: Any])?["auth"] as? [String: Any] else {
            throw APIError.unavailable("Risposta inattesa dal sito di Classeviva.")
        }
        return auth
    }

    // MARK: Utilità

    private static func isJSON(_ response: URLResponse, status: Int) -> Bool {
        guard let http = response as? HTTPURLResponse, http.statusCode == status else { return false }
        return http.value(forHTTPHeaderField: "Content-Type")?.contains("json") == true
    }

    /// Corpo `application/x-www-form-urlencoded`: tutto codificato tranne i caratteri non riservati.
    private static func form(_ fields: [(String, String)]) -> Data {
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let body = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")"
        }
        return Data(body.joined(separator: "&").utf8)
    }
}
