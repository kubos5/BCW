import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

struct HTTPResult {
    let data: Data
    let status: Int
    let contentType: String?
    let fileName: String?

    var isJSON: Bool { contentType?.contains("json") ?? false }
}

/// Livello di trasporto: permette di sostituire il server reale con quello demo.
protocol Transport: AnyObject {
    func send(_ method: HTTPMethod, path: String, body: Data?, token: String?) async throws -> HTTPResult
}

enum APIError: LocalizedError {
    case wrongCredentials(String)
    case needsProfileChoice([LoginChoice])
    case notAuthenticated
    case server(Int, String)
    case unavailable(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .wrongCredentials(let message): message
        case .needsProfileChoice: "Scegli il profilo a cui accedere."
        case .notAuthenticated: "Sessione scaduta. Accedi di nuovo."
        case .server(let code, let message): message.isEmpty ? "Errore del server (\(code))." : message
        case .unavailable(let message): message
        case .decoding: "Risposta inattesa da Classeviva."
        }
    }
}

final class URLSessionTransport: Transport {
    let baseURL: URL
    private let session: URLSession

    /// Header usati dall'app ufficiale Classeviva: senza questi l'API rifiuta le richieste.
    static let defaultHeaders = [
        "User-Agent": "CVVS/std/4.2.3 Android/12",
        "Z-Dev-Apikey": "Tg1NWEwNGIgIC0K",
        "Content-Type": "application/json",
        "Accept": "application/json",
    ]

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    func send(_ method: HTTPMethod, path: String, body: Data?, token: String?) async throws -> HTTPResult {
        guard let url = URL(string: baseURL.absoluteString + path) else { throw APIError.decoding }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        for (key, value) in Self.defaultHeaders { request.setValue(value, forHTTPHeaderField: key) }
        if let token { request.setValue(token, forHTTPHeaderField: "Z-Auth-Token") }
        if let body { request.httpBody = body }
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        return HTTPResult(
            data: data,
            status: http?.statusCode ?? 0,
            contentType: http?.value(forHTTPHeaderField: "Content-Type"),
            fileName: Self.fileName(from: http?.value(forHTTPHeaderField: "Content-Disposition"))
        )
    }

    private static func fileName(from disposition: String?) -> String? {
        guard let disposition else { return nil }
        for part in disposition.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("filename*=") {
                let value = trimmed.dropFirst("filename*=".count)
                if let range = value.range(of: "''") {
                    return String(value[range.upperBound...]).removingPercentEncoding
                }
            }
            if trimmed.lowercased().hasPrefix("filename=") {
                return String(trimmed.dropFirst("filename=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return nil
    }
}

/// Client per le API REST non ufficiali di Classeviva (`web.spaggiari.eu/rest/v1`),
/// le stesse usate dall'app mobile ufficiale.
final class ClassevivaClient {
    static let officialBaseURL = URL(string: "https://web.spaggiari.eu/rest/v1")!

    /// Base URL per l'archivio di un anno scolastico passato (es. `web24` per il 2024/25).
    static func archiveBaseURL(startYear: Int) -> URL {
        URL(string: String(format: "https://web%02d.spaggiari.eu/rest/v1", startYear % 100))!
    }

    let transport: Transport
    let cache: DiskCache
    var credentials: Credentials?

    private(set) var token: String?
    private(set) var tokenExpiry: Date?
    private(set) var ident: String?
    private var loginTask: Task<LoginResponse, Error>?

    init(transport: Transport, cacheNamespace: String, credentials: Credentials?) {
        self.transport = transport
        self.cache = DiskCache(namespace: cacheNamespace)
        self.credentials = credentials
        self.ident = credentials?.ident
    }

    /// ID numerico dello studente: "S1234567X" → "1234567".
    var studentId: String? {
        guard let ident else { return nil }
        let digits = ident.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }

    // MARK: Autenticazione

    @discardableResult
    func login() async throws -> LoginResponse {
        if let loginTask { return try await loginTask.value }
        let task = Task { try await performLogin() }
        loginTask = task
        defer { loginTask = nil }
        return try await task.value
    }

    private func performLogin() async throws -> LoginResponse {
        guard let credentials else { throw APIError.notAuthenticated }
        var body: [String: Any] = ["uid": credentials.username, "pass": credentials.password]
        body["ident"] = credentials.ident ?? NSNull()
        let data = try JSONSerialization.data(withJSONObject: body)
        let result = try await transport.send(.post, path: "/auth/login", body: data, token: nil)

        guard (200..<300).contains(result.status) else {
            let message = Self.errorMessage(from: result.data)
            if result.status == 422 || result.status == 401 || result.status == 400 {
                throw APIError.wrongCredentials(message ?? "Nome utente o password non validi.")
            }
            throw APIError.server(result.status, message ?? "")
        }

        guard let response = try? JSONDecoder().decode(LoginResponse.self, from: result.data) else {
            throw APIError.decoding
        }
        if response.token == nil, !response.choices.isEmpty {
            throw APIError.needsProfileChoice(response.choices)
        }
        guard let token = response.token else { throw APIError.decoding }
        self.token = token
        self.tokenExpiry = response.expire ?? Date().addingTimeInterval(60 * 60)
        self.ident = response.ident ?? credentials.ident
        return response
    }

    private func ensureToken() async throws {
        if let token, !token.isEmpty, let tokenExpiry, tokenExpiry.timeIntervalSinceNow > 120 { return }
        try await login()
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = json["message"] as? String, !message.isEmpty { return message }
        if let error = json["error"] as? String, !error.isEmpty { return error }
        return nil
    }

    // MARK: Richieste

    /// Esegue una richiesta autenticata su un percorso relativo allo studente,
    /// es. `grades` → `/students/1234567/grades`. Rinnova il token se scaduto.
    func raw(_ method: HTTPMethod, _ studentPath: String, body: Data? = nil) async throws -> HTTPResult {
        try await ensureToken()
        guard let studentId else { throw APIError.notAuthenticated }
        let path = "/students/\(studentId)/\(studentPath)"
        var result = try await transport.send(method, path: path, body: body, token: token)
        if result.status == 401 || result.status == 403 {
            token = nil
            try await login()
            result = try await transport.send(method, path: path, body: body, token: token)
        }
        guard (200..<300).contains(result.status) else {
            if result.status == 401 { throw APIError.notAuthenticated }
            throw APIError.server(result.status, Self.errorMessage(from: result.data) ?? "")
        }
        return result
    }

    /// Scarica e decodifica una risposta JSON. In caso di errore di rete
    /// restituisce l'ultima copia salvata (modalità offline).
    func fetch<T: Decodable>(_ type: T.Type, _ studentPath: String, method: HTTPMethod = .get,
                             body: Data? = nil, useCache: Bool = true) async throws -> (value: T, fromCache: Bool) {
        do {
            let result = try await raw(method, studentPath, body: body)
            let value = try JSONDecoder().decode(T.self, from: result.data)
            if useCache { cache.store(result.data, for: studentPath) }
            return (value, false)
        } catch let error as URLError where useCache {
            if let data = cache.load(studentPath), let value = try? JSONDecoder().decode(T.self, from: data) {
                return (value, true)
            }
            throw error
        } catch is DecodingError {
            throw APIError.decoding
        }
    }

    /// Prova più endpoint equivalenti in ordine (Classeviva ne versiona alcuni,
    /// es. `grades` / `grades2324`) e usa il primo che risponde.
    func fetchFirst<T: Decodable>(_ type: T.Type, _ paths: [String]) async throws -> (value: T, fromCache: Bool) {
        var lastError: Error = APIError.decoding
        for path in paths {
            do {
                return try await fetch(type, path)
            } catch APIError.server(let code, let message) where code == 404 || code == 400 || code == 405 {
                lastError = APIError.server(code, message)
            }
        }
        throw lastError
    }

    /// Ultima risposta salvata, per mostrare subito i dati all'avvio.
    func cached<T: Decodable>(_ type: T.Type, _ studentPath: String) -> T? {
        guard let data = cache.load(studentPath) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Scarica un file e lo salva in una cartella temporanea, pronto per Quick Look.
    func download(_ studentPath: String, method: HTTPMethod = .get, suggestedName: String) async throws -> URL {
        let result = try await raw(method, studentPath, body: method == .post ? Data("{}".utf8) : nil)
        return try Self.writeTemporary(result.data, name: result.fileName ?? suggestedName,
                                       contentType: result.contentType)
    }

    static func writeTemporary(_ data: Data, name: String, contentType: String?) throws -> URL {
        var fileName = name.replacingOccurrences(of: "/", with: "-")
        if (fileName as NSString).pathExtension.isEmpty {
            if contentType?.contains("pdf") == true { fileName += ".pdf" }
            else if contentType?.contains("png") == true { fileName += ".png" }
            else if contentType?.contains("jpeg") == true { fileName += ".jpg" }
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BCWFiles", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .atomic)
        return url
    }

    func signOut() {
        token = nil
        tokenExpiry = nil
        credentials = nil
        cache.clear()
    }
}

/// Cache su disco delle risposte JSON, usata per la modalità offline.
final class DiskCache {
    private let folder: URL

    init(namespace: String) {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("BCW/\(namespace)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func url(for key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return folder.appendingPathComponent(String(safe) + ".json")
    }

    func store(_ data: Data, for key: String) {
        try? data.write(to: url(for: key), options: .atomic)
    }

    func load(_ key: String) -> Data? {
        try? Data(contentsOf: url(for: key))
    }

    func clear() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
}
