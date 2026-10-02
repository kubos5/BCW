import Foundation
import SwiftUI

enum DidacticItem {
    case file(URL)
    case link(URL)
    case text(String)
}

/// Stato globale dell'app: sessione, dati del registro e operazioni.
@Observable
final class AppModel {
    enum Phase { case launching, signedOut, signedIn }

    var phase: Phase = .launching
    private(set) var isDemo = false
    private(set) var client: ClassevivaClient?
    let preferences = Preferences()

    // Dati
    var loginName: String?
    var card: Card?
    var grades: [Grade] = []
    var periods: [Period] = []
    var subjects: [Subject] = []
    var agenda: [AgendaEvent] = []
    var absences: [AbsenceEvent] = []
    var notices: [Notice] = []
    var notes: [DisciplinaryNote] = []
    var didactics: [DidacticTeacher] = []
    var documents: DocumentsResponse?
    var calendarDays: [CalendarDay] = []
    var schoolbooks: [SchoolbookCourse] = []
    private(set) var lessonsByDay: [String: [Lesson]] = [:]
    private var loadedLessonDays: Set<String> = []

    // Stato
    var isRefreshing = false
    var isOffline = false
    var lastUpdated: Date?
    var lastError: String?

    private static let demoKey = "demoMode"
    static let gradePaths = ["grades", "grades2324", "grades2"]

    // MARK: Sessione

    func bootstrap() {
        if UserDefaults.standard.bool(forKey: Self.demoKey) {
            startDemo()
            return
        }
        guard let credentials = Keychain.load() else {
            phase = .signedOut
            return
        }
        client = ClassevivaClient(transport: URLSessionTransport(baseURL: ClassevivaClient.officialBaseURL),
                                  cacheNamespace: "live", credentials: credentials)
        loadFromCache()
        phase = .signedIn
        Task { await refreshAll() }
    }

    /// Accede con le credenziali. Lancia `APIError.needsProfileChoice` per gli
    /// account genitore con più figli: in quel caso richiamare passando `ident`.
    func signIn(username: String, password: String, ident: String? = nil) async throws {
        let credentials = Credentials(username: username.trimmingCharacters(in: .whitespaces),
                                      password: password, ident: ident)
        let client = ClassevivaClient(transport: URLSessionTransport(baseURL: ClassevivaClient.officialBaseURL),
                                      cacheNamespace: "live", credentials: credentials)
        let response = try await client.login()
        var stored = credentials
        stored.ident = ident ?? response.ident
        client.credentials = stored
        Keychain.save(stored)
        UserDefaults.standard.set(false, forKey: Self.demoKey)
        loginName = [response.firstName, response.lastName].compactMap { $0 }.joined(separator: " ").nameCased
        self.client = client
        isDemo = false
        withAnimation { phase = .signedIn }
        await refreshAll()
    }

    func startDemo() {
        isDemo = true
        UserDefaults.standard.set(true, forKey: Self.demoKey)
        client = ClassevivaClient(transport: DemoTransport(), cacheNamespace: "demo",
                                  credentials: Credentials(username: "demo", password: "demo"))
        withAnimation { phase = .signedIn }
        Task { await refreshAll() }
    }

    func signOut() {
        client?.signOut()
        client = nil
        Keychain.delete()
        UserDefaults.standard.set(false, forKey: Self.demoKey)
        isDemo = false
        card = nil
        loginName = nil
        grades = []; periods = []; subjects = []; agenda = []; absences = []
        notices = []; notes = []; didactics = []; documents = nil; calendarDays = []; schoolbooks = []
        lessonsByDay = [:]; loadedLessonDays = []
        lastUpdated = nil
        Task { await Reminders.reschedule(events: [], hour: 18, enabled: false, completed: []) }
        withAnimation { phase = .signedOut }
    }

    var credentialsForArchive: Credentials? { client?.credentials }

    // MARK: Caricamento

    private var schoolYear: (start: Date, end: Date, startYear: Int) { CVDate.schoolYear() }

    private var agendaPath: String {
        "agenda/all/\(CVDate.apiString(schoolYear.start))/\(CVDate.apiString(schoolYear.end))"
    }

    /// Mostra subito gli ultimi dati salvati, prima che arrivi la risposta di rete.
    private func loadFromCache() {
        guard let client else { return }
        card = client.cached(CardResponse.self, "card")?.card
        grades = Self.gradePaths.lazy.compactMap { client.cached(GradesResponse.self, $0) }.first?.grades ?? []
        periods = client.cached(PeriodsResponse.self, "periods")?.periods ?? []
        subjects = client.cached(SubjectsResponse.self, "subjects")?.subjects ?? []
        agenda = client.cached(AgendaResponse.self, agendaPath)?.events ?? []
        absences = client.cached(AbsencesResponse.self, "absences/details")?.events ?? []
        notices = client.cached(NoticeboardResponse.self, "noticeboard")?.items ?? []
        notes = client.cached(NotesResponse.self, "notes/all")?.notes ?? []
        calendarDays = client.cached(CalendarResponse.self, "calendar/all")?.days ?? []
    }

    func refreshAll() async {
        guard client != nil, !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        // Il primo login serve a tutte le richieste successive.
        do {
            if client?.token == nil { try await client?.login() }
        } catch let error as URLError {
            isOffline = true
            lastError = offlineMessage(error)
            return
        } catch {
            lastError = error.localizedDescription
            if let api = error as? APIError, case .wrongCredentials = api { signOut() }
            return
        }

        async let a: Void = loadCard()
        async let b: Void = loadGrades()
        async let c: Void = loadAgenda()
        async let d: Void = loadAbsences()
        async let e: Void = loadNotices()
        async let f: Void = loadNotes()
        async let g: Void = loadCalendar()
        _ = await (a, b, c, d, e, f, g)
        lessonsByDay = [:]
        loadedLessonDays = []
        lastUpdated = .now
    }

    private func offlineMessage(_ error: URLError) -> String {
        "Sei offline: stai vedendo gli ultimi dati salvati."
    }

    private func run<T: Decodable>(_ type: T.Type, _ path: String, method: HTTPMethod = .get,
                                   apply: (T) -> Void) async {
        guard let client else { return }
        do {
            let result = try await client.fetch(type, path, method: method,
                                                body: method == .post ? Data("{}".utf8) : nil)
            apply(result.value)
            if result.fromCache {
                isOffline = true
                lastError = "Sei offline: stai vedendo gli ultimi dati salvati."
            } else {
                isOffline = false
            }
        } catch {
            if lastError == nil { lastError = error.localizedDescription }
        }
    }

    func loadCard() async {
        await run(CardResponse.self, "card") { self.card = $0.card }
    }

    func loadGrades() async {
        async let p: Void = run(PeriodsResponse.self, "periods") { self.periods = $0.periods }
        async let s: Void = run(SubjectsResponse.self, "subjects") { self.subjects = $0.subjects }
        async let g: Void = loadGradeList()
        _ = await (p, s, g)
    }

    private func loadGradeList() async {
        guard let client else { return }
        do {
            let result = try await client.fetchFirst(GradesResponse.self, Self.gradePaths)
            grades = result.value.grades.sorted { $0.date > $1.date }
            if result.fromCache { isOffline = true }
        } catch {
            if lastError == nil { lastError = error.localizedDescription }
        }
    }

    func loadAgenda() async {
        await run(AgendaResponse.self, agendaPath) { self.agenda = $0.events.sorted { $0.begin < $1.begin } }
        await rescheduleReminders()
    }

    func loadAbsences() async {
        await run(AbsencesResponse.self, "absences/details") { self.absences = $0.events.sorted { $0.date > $1.date } }
    }

    func loadNotices() async {
        await run(NoticeboardResponse.self, "noticeboard") {
            self.notices = $0.items.filter { !$0.isDeleted }.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
        }
    }

    func loadNotes() async {
        await run(NotesResponse.self, "notes/all") { self.notes = $0.notes }
    }

    func loadDidactics() async {
        await run(DidacticsResponse.self, "didactics") { self.didactics = $0.teachers }
    }

    func loadDocuments() async {
        await run(DocumentsResponse.self, "documents", method: .post) { self.documents = $0 }
    }

    func loadCalendar() async {
        await run(CalendarResponse.self, "calendar/all") { self.calendarDays = $0.days }
    }

    func loadSchoolbooks() async {
        await run(SchoolbooksResponse.self, "schoolbooks") { self.schoolbooks = $0.courses }
    }

    func rescheduleReminders() async {
        await Reminders.reschedule(events: agenda, hour: preferences.reminderHour,
                                   enabled: preferences.homeworkReminders,
                                   completed: preferences.completedHomework)
    }

    // MARK: Lezioni

    func lessons(on day: Date) -> [Lesson] {
        lessonsByDay[CVDate.dayKey(day)] ?? []
    }

    func hasLoadedLessons(on day: Date) -> Bool {
        loadedLessonDays.contains(CVDate.dayKey(day))
    }

    /// Scarica le lezioni dei giorni non ancora caricati nell'intervallo (solo giorni passati e oggi).
    func ensureLessons(from: Date, to: Date) async {
        guard let client else { return }
        let end = min(to.startOfDay, Date().startOfDay)
        var start = from.startOfDay
        while start <= end, loadedLessonDays.contains(CVDate.dayKey(start)) { start = start.adding(days: 1) }
        guard start <= end else { return }
        let path = "lessons/\(CVDate.apiString(start))/\(CVDate.apiString(end))"
        do {
            let result = try await client.fetch(LessonsResponse.self, path)
            var day = start
            while day <= end {
                let key = CVDate.dayKey(day)
                loadedLessonDays.insert(key)
                lessonsByDay[key] = []
                day = day.adding(days: 1)
            }
            for lesson in result.value.lessons {
                lessonsByDay[CVDate.dayKey(lesson.date), default: []].append(lesson)
            }
            for key in lessonsByDay.keys {
                lessonsByDay[key]?.sort { $0.hour < $1.hour }
            }
        } catch {
            // Le lezioni non sono essenziali: in caso di errore restano vuote.
        }
    }

    /// Lezioni di un intervallo, senza salvarle (usato dal registro per materia).
    func fetchLessons(from: Date, to: Date) async throws -> [Lesson] {
        guard let client else { return [] }
        let path = "lessons/\(CVDate.apiString(from))/\(CVDate.apiString(to))"
        return try await client.fetch(LessonsResponse.self, path).value.lessons
    }

    // MARK: Bacheca

    /// Apre una comunicazione (segnandola come letta) ed eventualmente aderisce, firma o risponde.
    func openNotice(_ notice: Notice, join: Bool? = nil, sign: Bool? = nil, text: String? = nil) async throws -> NoticeDetail {
        guard let client else { throw APIError.notAuthenticated }
        var body: [String: Any] = [:]
        if let join { body["join"] = join }
        if let sign { body["sign"] = sign }
        if let text { body["text"] = text }
        let data = try JSONSerialization.data(withJSONObject: body)
        let path = "noticeboard/read/\(notice.eventCode)/\(notice.pubId)/101"
        let detail = try await client.fetch(NoticeDetail.self, path, method: .post, body: data, useCache: false).value
        if let index = notices.firstIndex(where: { $0.id == notice.id }) {
            notices[index].isRead = true
        }
        return detail
    }

    func downloadAttachment(_ attachment: NoticeAttachment, of notice: Notice) async throws -> URL {
        guard let client else { throw APIError.notAuthenticated }
        let path = "noticeboard/attach/\(notice.eventCode)/\(notice.pubId)/\(attachment.number)"
        return try await client.download(path, suggestedName: attachment.fileName)
    }

    var unreadNoticesCount: Int { notices.filter { !$0.isRead }.count }

    // MARK: Note

    func readNote(_ note: DisciplinaryNote) async {
        guard let client, !note.isRead else { return }
        let path = "notes/\(note.category.rawValue)/read/\(note.id)"
        if let response = try? await client.fetch(NoteReadResponse.self, path, method: .post,
                                                  body: Data("{}".utf8), useCache: false).value,
           let index = notes.firstIndex(where: { $0.id == note.id && $0.category == note.category }) {
            notes[index].isRead = true
            if let text = response.text, !text.isEmpty { notes[index].text = text }
        }
    }

    // MARK: Didattica

    func openDidacticContent(_ content: DidacticContent) async throws -> DidacticItem {
        guard let client else { throw APIError.notAuthenticated }
        let result = try await client.raw(.get, "didactics/item/\(content.id)")
        if result.isJSON, let json = try? JSONSerialization.jsonObject(with: result.data) as? [String: Any] {
            let item = json["item"] as? [String: Any] ?? json
            if let link = item["link"] as? String, let url = URL(string: link.hasPrefix("http") ? link : "https://\(link)") {
                return .link(url)
            }
            if let text = item["text"] as? String { return .text(text) }
        }
        let url = try ClassevivaClient.writeTemporary(result.data, name: result.fileName ?? content.name,
                                                      contentType: result.contentType)
        return .file(url)
    }

    // MARK: Documenti

    func downloadDocument(_ document: ReportDocument) async throws -> URL {
        guard let client else { throw APIError.notAuthenticated }
        let check = try await client.fetch(DocumentCheckResponse.self, "documents/check/\(document.documentHash)",
                                           method: .post, body: Data("{}".utf8), useCache: false).value
        guard check.available else {
            throw APIError.unavailable("Il documento non è ancora disponibile.")
        }
        return try await client.download("documents/read/\(document.documentHash)", method: .post,
                                         suggestedName: document.title + ".pdf")
    }

    // MARK: Dati derivati

    var gradeBook: GradeBook {
        GradeBook(grades: grades, periods: periods, mode: preferences.averageMode,
                  weighted: preferences.weightedAverage)
    }

    var displayName: String {
        card?.fullName ?? loginName ?? (isDemo ? "Giulia Esposito" : "Studente")
    }

    /// Classe dello studente, ricavata da agenda/lezioni (la scheda non la include).
    var classDescription: String? {
        agenda.lazy.compactMap(\.classDescription).first
            ?? lessonsByDay.values.lazy.flatMap { $0 }.compactMap(\.classDescription).first
    }

    func events(on day: Date) -> [AgendaEvent] {
        agenda.filter { $0.begin.isSameDay(as: day) }
    }

    func absences(on day: Date) -> [AbsenceEvent] {
        absences.filter { $0.date.isSameDay(as: day) }
    }

    func calendarStatus(on day: Date) -> CalendarDay? {
        calendarDays.first { $0.date.isSameDay(as: day) }
    }

    var unjustifiedAbsences: [AbsenceEvent] { absences.filter { !$0.isJustified } }
}
