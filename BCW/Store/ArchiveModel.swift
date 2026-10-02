import Foundation

/// Dati dell'anno scolastico precedente.
/// Classeviva archivia gli anni passati su un host dedicato (`webYY.spaggiari.eu`),
/// dove si accede con le stesse credenziali.
@Observable
final class ArchiveModel {
    enum State { case idle, loading, loaded, failed(String) }

    let startYear: Int
    var state: State = .idle
    var grades: [Grade] = []
    var periods: [Period] = []
    var absences: [AbsenceEvent] = []
    var notes: [DisciplinaryNote] = []
    var documents: [ReportDocument] = []
    var card: Card?
    private var client: ClassevivaClient?

    init() {
        startYear = CVDate.schoolYear().startYear - 1
    }

    var title: String { Self.title(startYear: startYear) }

    static var defaultTitle: String { title(startYear: CVDate.schoolYear().startYear - 1) }

    static func title(startYear: Int) -> String { "\(startYear)/\(String(startYear + 1).suffix(2))" }

    func load(credentials: Credentials?, demo: Bool) async {
        if case .loaded = state { return }
        state = .loading
        let transport: Transport
        if demo {
            transport = DemoTransport(yearOffset: -1)
        } else {
            transport = URLSessionTransport(baseURL: ClassevivaClient.archiveBaseURL(startYear: startYear))
        }
        // Per l'archivio non riutilizziamo l'ident: lo studente potrebbe avere un codice diverso.
        var archiveCredentials = credentials
        archiveCredentials?.ident = nil
        let client = ClassevivaClient(transport: transport, cacheNamespace: "archive-\(startYear)\(demo ? "-demo" : "")",
                                      credentials: archiveCredentials)
        self.client = client
        do {
            try await client.login()
            async let g = client.fetchFirst(GradesResponse.self, AppModel.gradePaths)
            async let p = client.fetch(PeriodsResponse.self, "periods")
            async let a = client.fetch(AbsencesResponse.self, "absences/details")
            async let n = client.fetch(NotesResponse.self, "notes/all")
            grades = try await g.value.grades.sorted { $0.date > $1.date }
            periods = (try? await p.value.periods) ?? []
            absences = (try? await a.value.events.sorted { $0.date > $1.date }) ?? []
            notes = (try? await n.value.notes) ?? []
            card = try? await client.fetch(CardResponse.self, "card").value.card
            documents = (try? await client.fetch(DocumentsResponse.self, "documents", method: .post,
                                                 body: Data("{}".utf8)).value.documents) ?? []
            state = .loaded
        } catch let error as APIError {
            switch error {
            case .wrongCredentials, .notAuthenticated:
                state = .failed("Non è stato possibile accedere all'archivio \(title). La scuola potrebbe non averlo reso disponibile.")
            default:
                state = .failed(error.localizedDescription)
            }
        } catch let error as URLError where error.code == .cannotFindHost || error.code == .cannotConnectToHost {
            state = .failed("L'archivio \(title) non è raggiungibile.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func downloadDocument(_ document: ReportDocument) async throws -> URL {
        guard let client else { throw APIError.notAuthenticated }
        return try await client.download("documents/read/\(document.documentHash)", method: .post,
                                         suggestedName: document.title + ".pdf")
    }
}
