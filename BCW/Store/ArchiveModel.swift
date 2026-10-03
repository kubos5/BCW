import Foundation

/// Pagelle e documenti di un anno scolastico passato.
///
/// Classeviva archivia gli anni passati su `webYY.spaggiari.eu` (tutti puntano a
/// `storico.spaggiari.eu`). Lì l'API REST esiste solo per l'anno appena concluso e
/// accetta solo date dell'anno in corso: voti, assenze e note risultano vuoti, mentre
/// i documenti (che non dipendono dalle date) arrivano correttamente. Il resto
/// dell'archivio si consulta sul sito web di Classeviva (vedi `PreviousYearView`).
@Observable
final class ArchiveModel {
    enum State { case idle, loading, loaded, failed(String) }

    let startYear: Int
    var state: State = .idle
    var documents: [ReportDocument] = []
    /// Errore della richiesta dei documenti, mostrato se l'elenco resta vuoto.
    var documentsError: String?
    private var client: ClassevivaClient?
    /// Identifica l'account (o la demo) a cui appartiene la cache su disco.
    private let owner: String

    init(startYear: Int = ArchiveModel.previousStartYear, owner: String) {
        self.startYear = startYear
        self.owner = owner
    }

    static var previousStartYear: Int { CVDate.schoolYear().startYear - 1 }

    /// Anni selezionabili: gli ultimi cinque anni scolastici conclusi.
    static var availableStartYears: [Int] { (0..<5).map { previousStartYear - $0 } }

    var title: String { Self.title(startYear: startYear) }

    static var defaultTitle: String { title(startYear: previousStartYear) }

    static func title(startYear: Int) -> String { "\(startYear)/\(String(startYear + 1).suffix(2))" }

    static func cacheNamespace(owner: String, startYear: Int) -> String { "archive-\(owner)-\(startYear)" }

    /// Indirizzo del sito web di Classeviva: l'archivio si raggiunge da lì con "Vai all'a.s. …".
    static let webURL = URL(string: "https://web.spaggiari.eu/home/app/default/login.php")!

    func load(credentials: Credentials?, demo: Bool) async {
        if case .loaded = state { return }
        state = .loading
        documentsError = nil
        let transport: Transport
        if demo {
            transport = DemoTransport(yearOffset: startYear - CVDate.schoolYear().startYear)
        } else {
            transport = URLSessionTransport(baseURL: ClassevivaClient.archiveBaseURL(startYear: startYear))
        }
        // Per l'archivio non riutilizziamo subito l'ident: lo studente potrebbe avere un codice diverso.
        var archiveCredentials = credentials
        archiveCredentials?.ident = nil
        let client = ClassevivaClient(transport: transport,
                                      cacheNamespace: Self.cacheNamespace(owner: owner, startYear: startYear),
                                      credentials: archiveCredentials)
        self.client = client
        do {
            try await login(client, mainIdent: credentials?.ident)
        } catch let error as APIError {
            switch error {
            case .wrongCredentials:
                state = .failed("Classeviva non ha accettato le credenziali per l'archivio \(title). Se hai cambiato password dopo la fine dell'anno, nell'archivio potrebbe valere ancora quella vecchia.")
            case .decoding:
                // Gli archivi più vecchi non hanno l'API REST: il login risponde senza contenuto.
                state = .failed("Per l'anno \(title) Classeviva non permette di scaricare le pagelle dall'app.")
            default:
                state = .failed(error.localizedDescription)
            }
            return
        } catch let error as URLError where error.code == .cannotFindHost || error.code == .cannotConnectToHost {
            state = .failed("L'archivio \(title) non è raggiungibile.")
            return
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        do {
            documents = try await client.fetch(DocumentsResponse.self, "documents", method: .post).value.documents
        } catch {
            documentsError = error.localizedDescription
        }
        state = .loaded
    }

    /// Accede all'archivio. Per gli account con più profili sceglie quello che
    /// corrisponde all'account attivo; se l'accesso senza profilo fallisce, riprova con quello.
    private func login(_ client: ClassevivaClient, mainIdent: String?) async throws {
        do {
            try await client.login()
        } catch APIError.needsProfileChoice(let choices) {
            let digits = mainIdent?.filter(\.isNumber)
            let choice = choices.first { $0.ident == mainIdent }
                ?? choices.first { digits != nil && $0.ident.filter(\.isNumber) == digits }
                ?? choices.first
            guard let choice else { throw APIError.notAuthenticated }
            client.credentials?.ident = choice.ident
            try await client.login()
        } catch APIError.wrongCredentials(let message) {
            guard let mainIdent else { throw APIError.wrongCredentials(message) }
            client.credentials?.ident = mainIdent
            try await client.login()
        }
    }

    func downloadDocument(_ document: ReportDocument) async throws -> URL {
        guard let client else { throw APIError.notAuthenticated }
        return try await client.download("documents/read/\(document.documentHash)", method: .post,
                                         suggestedName: document.title + ".pdf")
    }
}
