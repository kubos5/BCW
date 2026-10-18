import Foundation
import UniformTypeIdentifiers

/// Server degli account BCW (BCW-api, https://github.com/kubos5/BCW-api): account BCW, account
/// Classeviva abbinati e sincronizzazione di impostazioni e orario.
enum BCWServer {
    /// Indirizzo predefinito: il Worker `bcw-api` pubblicato su Cloudflare.
    static let defaultURL = URL(string: "https://bcw-api.romeo-ca1211.workers.dev")!
    private static let key = "bcwServerURL"

    /// Indirizzo in uso: quello scelto dall'utente o quello predefinito.
    static var baseURL: URL {
        if let text = UserDefaults.standard.string(forKey: key), let url = normalized(text) { return url }
        return defaultURL
    }

    static var isCustom: Bool { UserDefaults.standard.string(forKey: key) != nil }

    static var host: String { baseURL.host() ?? baseURL.absoluteString }

    /// "bcw-api.esempio.workers.dev/" → "https://bcw-api.esempio.workers.dev"; `nil` se non è un indirizzo.
    static func normalized(_ text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        guard !value.isEmpty else { return nil }
        let lower = value.lowercased()
        if !lower.hasPrefix("https://") && !lower.hasPrefix("http://") { value = "https://" + value }
        guard let url = URL(string: value), url.host() != nil else { return nil }
        return url
    }

    /// Imposta l'indirizzo (vuoto = quello predefinito). `false` se il testo non è un indirizzo.
    @discardableResult
    static func set(_ text: String) -> Bool {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return true
        }
        guard let url = normalized(text) else { return false }
        UserDefaults.standard.set(url.absoluteString, forKey: key)
        return true
    }
}

/// Errore dell'API di BCW: `code` è quello del server (es. `conflict`) oppure `offline`.
struct BCWError: LocalizedError {
    let code: String
    let message: String
    var status = 0
    /// Documento attuale sul server (JSON), in caso di conflitto di versione.
    var document: Data?
    var version: Int?
    /// Profili tra cui scegliere (genitore con più figli).
    var choices: [LoginChoice] = []

    var errorDescription: String? { message }

    var isUnauthorized: Bool { code == "unauthorized" }
    var isOffline: Bool { code == "offline" }
}

struct BCWUser: Codable, Equatable {
    let id: String
    let username: String
}

/// Sessione dell'account BCW, salvata nel Portachiavi.
struct BCWSession: Codable, Equatable {
    var token: String
    var user: BCWUser
}

/// Account Classeviva abbinato, come lo restituisce il server.
struct RemoteAccount: Decodable {
    struct RemoteCredentials: Decodable {
        let username: String
        let password: String
        let ident: String?
    }

    let id: String
    let ident: String?
    let name: String?
    let school: String?
    let credentials: RemoteCredentials?

    /// Nel formato degli account salvati sul dispositivo, con lo stesso id del server.
    var savedAccount: SavedAccount? {
        guard let remote = credentials, !remote.username.isEmpty else { return nil }
        let credentials = Credentials(username: remote.username, password: remote.password, ident: remote.ident ?? ident)
        return SavedAccount(id: id, credentials: credentials, name: name?.nilIfEmpty ?? remote.username, school: school)
    }
}

/// Account BCW a cui è abbinato un profilo Classeviva.
struct BCWLink: Decodable, Identifiable, Equatable {
    let id: String
    let username: String
    /// Millisecondi dall'epoca Unix.
    let linkedAt: Double

    var date: Date { Date(timeIntervalSince1970: linkedAt / 1000) }
}

/// Richieste all'API di BCW (gli stessi percorsi della versione web, `js/cloud.js`).
enum BCWAPI {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Documento sincronizzato: il JSON dell'oggetto (`nil` se non c'è ancora) e la sua versione.
    struct Document {
        let data: Data?
        let version: Int
    }

    private struct AuthResponse: Decodable {
        let token: String
        let user: BCWUser
    }

    // MARK: Trasporto

    /// Esegue una richiesta. `json` è un oggetto da serializzare, `body` un corpo già pronto (file).
    static func send(_ method: String, _ path: String, token: String? = nil, json: [String: Any]? = nil,
                     body: Data? = nil, contentType: String? = nil, headers: [String: String] = [:],
                     timeout: TimeInterval = 25) async throws -> Data {
        guard let url = URL(string: BCWServer.baseURL.absoluteString + path) else {
            throw BCWError(code: "invalid_request", message: "Indirizzo del server BCW non valido.")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-BCW-Client")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let json {
            // Un oggetto non valido farebbe chiudere l'app (eccezione di Objective-C), non un errore.
            guard JSONSerialization.isValidJSONObject(json) else {
                throw BCWError(code: "invalid_request", message: "Dati non validi per il server BCW.")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let body {
            request.httpBody = body
            request.setValue(contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
        }

        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let failure as URLError where failure.code == .notConnectedToInternet {
            throw BCWError(code: "offline", message: "Nessuna connessione a Internet.")
        } catch {
            throw BCWError(code: "offline", message: "Impossibile contattare il server BCW (\(BCWServer.host)).")
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else {
            throw BCWError(code: "offline", message: "Impossibile contattare il server BCW (\(BCWServer.host)).")
        }
        // Il server di BCW segna ogni risposta: senza il segno all'indirizzo risponde altro.
        guard http.value(forHTTPHeaderField: "X-BCW-API") != nil else {
            throw BCWError(code: "not_configured",
                           message: "All'indirizzo \(BCWServer.host) non risponde il server BCW. Controlla l'indirizzo in Impostazioni › Account › Server BCW.")
        }
        guard (200..<300).contains(http.statusCode) else { throw failure(from: data, status: http.statusCode) }
        return data
    }

    private static func failure(from data: Data, status: Int) -> BCWError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        var error = BCWError(code: json?["error"] as? String ?? "server_error",
                             message: json?["message"] as? String ?? "Errore del server BCW (\(status)).",
                             status: status)
        error.version = json?["version"] as? Int
        if let document = json?["data"] as? [String: Any], JSONSerialization.isValidJSONObject(document) {
            error.document = try? JSONSerialization.data(withJSONObject: document)
        }
        if let choices = json?["choices"] as? [[String: Any]], JSONSerialization.isValidJSONObject(choices),
           let encoded = try? JSONSerialization.data(withJSONObject: choices) {
            error.choices = (try? JSONDecoder().decode([LoginChoice].self, from: encoded)) ?? []
        }
        return error
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw BCWError(code: "decoding", message: "Risposta inattesa dal server BCW.")
        }
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: Account BCW

    /// Accede (o crea l'account con `register`).
    static func signIn(username: String, password: String, register: Bool) async throws -> BCWSession {
        let data = try await send("POST", register ? "/auth/register" : "/auth/login",
                                  json: ["username": username, "password": password, "client": "BCW per iPhone e iPad"])
        let response = try decode(AuthResponse.self, data)
        return BCWSession(token: response.token, user: response.user)
    }

    static func signOut(token: String) async throws {
        _ = try await send("POST", "/auth/logout", token: token)
    }

    /// Cambia la password: le altre sessioni vengono chiuse, questa riceve un token nuovo.
    static func changePassword(token: String, current: String, new: String) async throws -> String {
        let data = try await send("PUT", "/me/password", token: token,
                                  json: ["currentPassword": current, "newPassword": new, "client": "BCW per iPhone e iPad"])
        return try decode(AuthResponse.self, data).token
    }

    static func deleteAccount(token: String, password: String) async throws {
        _ = try await send("DELETE", "/me", token: token, json: ["password": password])
    }

    // MARK: Account Classeviva abbinati

    static func accounts(token: String) async throws -> [RemoteAccount] {
        struct Body: Decodable { let accounts: [RemoteAccount] }
        let data = try await send("GET", "/accounts", token: token)
        return try decode(Body.self, data).accounts
    }

    /// Abbina un account (il server verifica le credenziali su Classeviva).
    static func link(token: String, credentials: Credentials) async throws -> RemoteAccount {
        struct Body: Decodable { let account: RemoteAccount }
        var json: [String: Any] = ["username": credentials.username, "password": credentials.password]
        json["ident"] = credentials.ident ?? NSNull()
        let data = try await send("POST", "/accounts", token: token, json: json)
        return try decode(Body.self, data).account
    }

    static func unlink(token: String, id: String) async throws {
        _ = try await send("DELETE", "/accounts/\(id)", token: token)
    }

    static func updateAccount(token: String, id: String, name: String, school: String?) async throws {
        var json: [String: Any] = ["name": name]
        json["school"] = school ?? NSNull()
        _ = try await send("PATCH", "/accounts/\(id)", token: token, json: json)
    }

    // MARK: Lato Classeviva

    private static func classevivaHeaders(ident: String, token: String) -> [String: String] {
        ["X-Classeviva-Ident": ident, "X-Classeviva-Token": token]
    }

    /// Gli account BCW a cui è abbinato un profilo, provando l'accesso con il token di Classeviva.
    static func links(ident: String, classevivaToken: String) async throws -> [BCWLink] {
        struct Body: Decodable { let links: [BCWLink] }
        let data = try await send("GET", "/classeviva/links", headers: classevivaHeaders(ident: ident, token: classevivaToken))
        return try decode(Body.self, data).links
    }

    /// Scollega il profilo da un account BCW (`nil` = da tutti).
    static func removeLink(id: String?, ident: String, classevivaToken: String) async throws {
        let path = id.map { "/classeviva/links/\($0)" } ?? "/classeviva/links"
        _ = try await send("DELETE", path, headers: classevivaHeaders(ident: ident, token: classevivaToken))
    }

    // MARK: Sincronizzazione

    static func document(token: String, path: String) async throws -> Document {
        let response = try await send("GET", path, token: token)
        let json = object(response)
        var data: Data?
        if let document = json?["data"] as? [String: Any], JSONSerialization.isValidJSONObject(document) {
            data = try? JSONSerialization.data(withJSONObject: document)
        }
        return Document(data: data, version: json?["version"] as? Int ?? 0)
    }

    /// Salva un documento partendo da `baseVersion`; se il server ne ha uno più recente lancia
    /// `BCWError` con codice `conflict`, il documento attuale e la sua versione.
    static func putDocument(token: String, path: String, data: Data, baseVersion: Int) async throws -> Int {
        guard let document = object(data) else {
            throw BCWError(code: "invalid_request", message: "Documento non valido.")
        }
        let body: [String: Any] = ["data": document, "baseVersion": baseVersion]
        let response = try await send("PUT", path, token: token, json: body)
        return object(response)?["version"] as? Int ?? baseVersion + 1
    }

    // MARK: File dell'orario

    static func fileNames(token: String, accountID: String) async throws -> Set<String> {
        struct Body: Decodable {
            struct File: Decodable { let name: String }
            let files: [File]
        }
        let data = try await send("GET", "/files/\(accountID)", token: token)
        let body = try decode(Body.self, data)
        return Set(body.files.map(\.name))
    }

    static func upload(token: String, accountID: String, name: String, data: Data) async throws {
        let ext = (name as NSString).pathExtension
        let type = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        _ = try await send("PUT", "/files/\(accountID)/\(escaped(name))", token: token, body: data, contentType: type, timeout: 120)
    }

    static func download(token: String, accountID: String, name: String) async throws -> Data {
        try await send("GET", "/files/\(accountID)/\(escaped(name))", token: token, timeout: 120)
    }

    private static func escaped(_ name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._"))) ?? name
    }
}
