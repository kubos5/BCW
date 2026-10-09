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

    // Account salvati
    private(set) var accounts: [SavedAccount] = []
    private(set) var activeAccountID: String?

    // Dati
    var loginName: String?
    var card: Card?
    var grades: [Grade] = []
    var periods: [Period] = []
    var subjects: [Subject] = []
    var agenda: [AgendaEvent] = [] {
        didSet { eventsByDay = Dictionary(grouping: agenda) { CVDate.dayKey($0.begin) } }
    }
    var absences: [AbsenceEvent] = [] {
        didSet { absencesByDay = Dictionary(grouping: absences) { CVDate.dayKey($0.date) } }
    }
    var notices: [Notice] = []
    var notes: [DisciplinaryNote] = []
    var didactics: [DidacticTeacher] = []
    var documents: DocumentsResponse?
    var calendarDays: [CalendarDay] = [] {
        didSet { calendarByDay = Dictionary(calendarDays.map { (CVDate.dayKey($0.date), $0) }) { first, _ in first } }
    }
    var schoolbooks: [SchoolbookCourse] = []
    private(set) var lessonsByDay: [String: [Lesson]] = [:]
    /// Indici per giorno (chiave `CVDate.dayKey`), ricostruiti quando cambiano i dati: la
    /// Dashboard chiede gli eventi di un giorno per ogni cella del calendario a ogni
    /// aggiornamento, e confrontare le date una per una con il calendario è lento.
    private(set) var eventsByDay: [String: [AgendaEvent]] = [:]
    private(set) var absencesByDay: [String: [AbsenceEvent]] = [:]
    private(set) var calendarByDay: [String: CalendarDay] = [:]
    private var loadedLessonDays: Set<String> = []

    // Stato
    var isRefreshing = false
    var isOffline = false
    var lastUpdated: Date?
    var lastError: String?
    /// Client per cui è in corso un aggiornamento completo (cambia quando si cambia account).
    @ObservationIgnored private var refreshingClient: ClassevivaClient?
    /// Cambia a ogni cambio di sessione (account, demo, uscita): le viste lo usano per ricaricare.
    private(set) var sessionID = UUID()
    /// `true` mentre l'app sfuma per cambiare account: l'interfaccia scompare, i dati cambiano
    /// mentre non si vede e poi riappare (`RootView`), invece di trasformarsi davanti all'utente.
    private(set) var isChangingSession = false
    /// Cambio richiesto durante una dissolvenza già in corso: vale l'ultimo.
    @ObservationIgnored private var pendingSessionChange: (() -> Void)?
    /// Archivi degli anni passati caricati in questa sessione.
    @ObservationIgnored private var archives: [Int: ArchiveModel] = [:]

    private static let demoKey = "demoMode"
    private static let activeAccountKey = "activeAccount"
    static let gradePaths = ["grades", "grades2324", "grades2"]

    // MARK: Sessione

    var activeAccount: SavedAccount? {
        accounts.first { $0.id == activeAccountID }
    }

    /// Account a cui si torna uscendo dalla demo: quello da cui è stata aperta, o il primo salvato.
    var accountAfterDemo: SavedAccount? {
        activeAccount ?? accounts.first
    }

    /// Spiegazione per la conferma di uscita dalla demo.
    var demoExitMessage: String {
        if let account = accountAfterDemo {
            return "Stai usando la modalità demo. Uscendo tornerai a \(account.name)."
        }
        return "Stai usando la modalità demo."
    }

    func bootstrap() {
        accounts = Keychain.loadAccounts()
        // Cache delle versioni precedenti: ora ogni account (e la demo) ha la sua.
        DiskCache.remove(namespace: "live")
        for year in ArchiveModel.availableStartYears {
            DiskCache.remove(namespace: "archive-\(year)")
            DiskCache.remove(namespace: "archive-\(year)-demo")
        }
        let storedID = UserDefaults.standard.string(forKey: Self.activeAccountKey)
        if UserDefaults.standard.bool(forKey: Self.demoKey) {
            // La demo può essere aperta da un account: uscendo si torna a quello.
            activeAccountID = accounts.first { $0.id == storedID }?.id
            startDemo()
            return
        }
        guard let account = accounts.first(where: { $0.id == storedID }) ?? accounts.first else {
            phase = .signedOut
            return
        }
        activate(account)
    }

    /// Accede con le credenziali e aggiunge (o aggiorna) l'account tra quelli salvati,
    /// rendendolo quello attivo. Lancia `APIError.needsProfileChoice` per gli account
    /// genitore con più figli: in quel caso richiamare passando `ident`.
    func signIn(username: String, password: String, ident: String? = nil) async throws {
        let credentials = Credentials(username: username.trimmingCharacters(in: .whitespaces),
                                      password: password, ident: ident)
        let probe = ClassevivaClient(transport: URLSessionTransport(baseURL: ClassevivaClient.officialBaseURL),
                                     cacheNamespace: "login", credentials: credentials)
        let response = try await probe.login()
        var stored = credentials
        stored.ident = ident ?? response.ident
        let name = [response.firstName, response.lastName].compactMap { $0 }.joined(separator: " ").nameCased

        var account: SavedAccount
        if let index = accounts.firstIndex(where: { $0.matches(stored) }) {
            accounts[index].credentials = stored
            if !name.isEmpty { accounts[index].name = name }
            account = accounts[index]
        } else {
            account = SavedAccount(credentials: stored, name: name.isEmpty ? stored.username : name)
            accounts.append(account)
        }
        Keychain.saveAccounts(accounts)
        if phase == .signedIn {
            // Account aggiunto mentre l'app è aperta: stessa dissolvenza del cambio di account.
            let added = account
            changeSession {
                self.activate(added, refresh: false)
                self.client?.adoptSession(from: probe)
                Task { await self.refreshAll() }
            }
            return
        }
        activate(account, refresh: false)
        client?.adoptSession(from: probe)
        await refreshAll()
    }

    /// Passa a un altro account salvato.
    func switchAccount(to id: String) {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        guard isDemo || account.id != activeAccountID else { return }
        changeSession { self.activate(account) }
    }

    /// Cambia sessione con una dissolvenza: l'interfaccia scompare, i dati cambiano senza
    /// animazioni (nessun elemento si ridimensiona per accogliere i nuovi contenuti) e poi
    /// riappare. Fuori dall'app già avviata (avvio, schermata di accesso) cambia subito: lì
    /// c'è già la transizione tra le schermate.
    private func changeSession(_ change: @escaping () -> Void) {
        guard phase == .signedIn else { change(); return }
        let alreadyFading = pendingSessionChange != nil
        pendingSessionChange = change
        guard !alreadyFading else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            isChangingSession = true
        } completion: {
            guard let change = self.pendingSessionChange else { return }
            self.pendingSessionChange = nil
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { change() }
            Task { @MainActor in
                await self.waitForSessionContent()
                // Un attimo per disegnare i nuovi dati mentre l'interfaccia è ancora nascosta.
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeIn(duration: 0.25)) { self.isChangingSession = false }
            }
        }
    }

    /// Rende attivo un account: azzera i dati, mostra subito la cache e aggiorna.
    private func activate(_ account: SavedAccount, refresh: Bool = true) {
        resetData()
        isDemo = false
        UserDefaults.standard.set(false, forKey: Self.demoKey)
        activeAccountID = account.id
        UserDefaults.standard.set(account.id, forKey: Self.activeAccountKey)
        loginName = account.name
        client = ClassevivaClient(transport: URLSessionTransport(baseURL: ClassevivaClient.officialBaseURL),
                                  cacheNamespace: "live-\(account.id)", credentials: account.credentials)
        loadFromCache()
        withAnimation { phase = .signedIn }
        if refresh { Task { await refreshAll() } }
    }

    /// Durante il cambio di sessione l'interfaccia riappare quando ci sono i dati: subito se
    /// c'è la cache dell'account, altrimenti (demo, account mai aperto) a fine aggiornamento,
    /// così i contenuti non compaiono a pezzi trasformando la pagina. Al massimo 3 secondi.
    private func waitForSessionContent() async {
        guard card == nil, agenda.isEmpty, grades.isEmpty else { return }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, lastUpdated == nil, lastError == nil {
            try? await Task.sleep(for: .milliseconds(40))
        }
    }

    /// Apre la demo. Si può aprire anche con un account collegato: `activeAccountID` resta
    /// impostato, così uscendo dalla demo si torna a quell'account.
    func startDemo() {
        changeSession { self.beginDemo() }
    }

    private func beginDemo() {
        resetData()
        isDemo = true
        UserDefaults.standard.set(true, forKey: Self.demoKey)
        client = ClassevivaClient(transport: DemoTransport(), cacheNamespace: "demo",
                                  credentials: Credentials(username: "demo", password: "demo"))
        withAnimation { phase = .signedIn }
        Task { await refreshAll() }
    }

    /// Esce dall'account attivo (o dalla demo). Se ci sono altri account salvati
    /// passa al successivo, altrimenti torna alla schermata di accesso.
    func signOut() {
        if isDemo {
            if let next = accountAfterDemo {
                changeSession {
                    self.leaveDemo()
                    self.activate(next)
                }
            } else {
                leaveDemo()
                endSession()
            }
            return
        }
        if let id = activeAccountID {
            removeAccount(id)
        } else {
            endSession()
        }
    }

    private func leaveDemo() {
        resetData()
        removeCaches(owner: "demo")
        UserDefaults.standard.set(false, forKey: Self.demoKey)
        isDemo = false
    }

    /// Rimuove un account salvato e la sua cache. Se è quello attivo si passa al successivo
    /// con la stessa dissolvenza del cambio di account.
    func removeAccount(_ id: String) {
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        if id == activeAccountID, !isDemo, accounts.count > 1 {
            changeSession { self.performRemoval(of: account) }
        } else {
            performRemoval(of: account)
        }
    }

    private func performRemoval(of account: SavedAccount) {
        let id = account.id
        guard accounts.contains(where: { $0.id == id }) else { return }
        if id == activeAccountID, !isDemo { resetData() }
        removeCaches(owner: account.id)
        accounts.removeAll { $0.id == id }
        Keychain.saveAccounts(accounts)
        guard id == activeAccountID, !isDemo else { return }
        if let next = accounts.first {
            activate(next)
        } else {
            endSession()
        }
    }

    private func endSession() {
        resetData()
        activeAccountID = nil
        UserDefaults.standard.removeObject(forKey: Self.activeAccountKey)
        Task { await Reminders.reschedule(events: [], hour: 18, enabled: false, completed: []) }
        withAnimation { phase = .signedOut }
    }

    private func resetData() {
        client?.signOut(clearingCache: false)
        client = nil
        archives = [:]
        sessionID = UUID()
        refreshingClient = nil
        isRefreshing = false
        isOffline = false
        lastError = nil
        card = nil
        loginName = nil
        grades = []; periods = []; subjects = []; agenda = []; absences = []
        notices = []; notes = []; didactics = []; documents = nil; calendarDays = []; schoolbooks = []
        lessonsByDay = [:]; loadedLessonDays = []
        lastUpdated = nil
    }

    /// Aggiorna nome e scuola dell'account salvato con i dati della scheda.
    private func updateActiveAccount(from card: Card) {
        guard !isDemo, let index = accounts.firstIndex(where: { $0.id == activeAccountID }) else { return }
        let name = card.fullName.trimmingCharacters(in: .whitespaces)
        let school = card.schoolDescription
        guard (!name.isEmpty && accounts[index].name != name) || accounts[index].school != school else { return }
        if !name.isEmpty { accounts[index].name = name }
        accounts[index].school = school
        Keychain.saveAccounts(accounts)
    }

    var credentialsForArchive: Credentials? { client?.credentials }

    /// Proprietario della cache su disco della sessione attuale.
    private var cacheOwner: String { isDemo ? "demo" : (activeAccountID ?? "live") }

    /// Archivio di un anno passato per la sessione attuale (viene azzerato cambiando sessione).
    func archive(for startYear: Int) -> ArchiveModel {
        _ = sessionID
        if let archive = archives[startYear] { return archive }
        let archive = ArchiveModel(startYear: startYear, owner: cacheOwner)
        archives[startYear] = archive
        return archive
    }

    /// Scarta l'archivio di un anno (e la sua cache) per ricaricarlo da capo.
    func reloadArchive(for startYear: Int) -> ArchiveModel {
        archives[startYear] = nil
        DiskCache.remove(namespace: ArchiveModel.cacheNamespace(owner: cacheOwner, startYear: startYear))
        return archive(for: startYear)
    }

    /// Elimina tutti i dati salvati su disco di un account (o della demo): risposte, archivi e file scaricati.
    private func removeCaches(owner: String) {
        DiskCache.remove(namespace: owner == "demo" ? "demo" : "live-\(owner)")
        for year in ArchiveModel.availableStartYears {
            DiskCache.remove(namespace: ArchiveModel.cacheNamespace(owner: owner, startYear: year))
        }
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory
            .appendingPathComponent("BCWFiles", isDirectory: true))
    }

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
        guard let client, refreshingClient !== client else { return }
        refreshingClient = client
        isRefreshing = true
        lastError = nil
        defer {
            if refreshingClient === client {
                refreshingClient = nil
                isRefreshing = false
            }
        }

        // Il primo login serve a tutte le richieste successive.
        do {
            if client.token == nil { try await client.login() }
        } catch let error as URLError {
            guard client === self.client else { return }
            isOffline = true
            lastError = offlineMessage(error)
            return
        } catch {
            guard client === self.client else { return }
            if let api = error as? APIError, case .wrongCredentials = api {
                lastError = "Le credenziali di \(displayName) non sono più valide. Accedi di nuovo da Tu › Account › Aggiungi account."
            } else {
                lastError = error.localizedDescription
            }
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
        guard client === self.client else { return }
        lessonsByDay = [:]
        loadedLessonDays = []
        lastUpdated = .now
    }

    private func offlineMessage(_ error: URLError) -> String {
        "Sei offline: stai vedendo gli ultimi dati salvati."
    }

    /// Scarica un endpoint e applica il risultato. Gli errori delle sezioni principali
    /// finiscono nel banner globale; quelli delle sezioni secondarie (`global: false`)
    /// vengono solo restituiti, così non compaiono in Dashboard o in Voti.
    @discardableResult
    private func run<T: Decodable>(_ type: T.Type, _ path: String, method: HTTPMethod = .get,
                                   global: Bool = true, apply: (T) -> Void) async -> String? {
        guard let client else { return nil }
        do {
            let result = try await client.fetch(type, path, method: method)
            guard client === self.client else { return nil }
            apply(result.value)
            if global {
                if result.fromCache {
                    isOffline = true
                    lastError = "Sei offline: stai vedendo gli ultimi dati salvati."
                } else {
                    isOffline = false
                }
            }
            return nil
        } catch {
            guard client === self.client else { return nil }
            if global, lastError == nil { lastError = error.localizedDescription }
            return error.localizedDescription
        }
    }

    func loadCard() async {
        await run(CardResponse.self, "card") {
            self.card = $0.card
            if let card = $0.card { self.updateActiveAccount(from: card) }
        }
    }

    func loadGrades() async {
        async let p: String? = run(PeriodsResponse.self, "periods") { self.periods = $0.periods }
        async let s: String? = run(SubjectsResponse.self, "subjects") { self.subjects = $0.subjects }
        async let g: Void = loadGradeList()
        _ = await (p, s, g)
    }

    private func loadGradeList() async {
        guard let client else { return }
        do {
            let result = try await client.fetchFirst(GradesResponse.self, Self.gradePaths) { !$0.grades.isEmpty }
            guard client === self.client else { return }
            grades = result.value.grades.sorted { $0.date > $1.date }
            if result.fromCache { isOffline = true }
        } catch {
            guard client === self.client else { return }
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

    @discardableResult
    func loadDidactics() async -> String? {
        await run(DidacticsResponse.self, "didactics", global: false) { self.didactics = $0.teachers }
    }

    @discardableResult
    func loadDocuments() async -> String? {
        await run(DocumentsResponse.self, "documents", method: .post, global: false) { self.documents = $0 }
    }

    func loadCalendar() async {
        await run(CalendarResponse.self, "calendar/all") { self.calendarDays = $0.days }
    }

    @discardableResult
    func loadSchoolbooks() async -> String? {
        await run(SchoolbooksResponse.self, "schoolbooks", global: false) { self.schoolbooks = $0.courses }
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
            guard client === self.client else { return }
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
        // Per la sola lettura si invia un corpo vuoto: `{}` viene rifiutato dal server.
        var body: [String: Any] = [:]
        if let join { body["join"] = join }
        if let sign { body["sign"] = sign }
        if let text { body["text"] = text }
        let data = body.isEmpty ? nil : try JSONSerialization.data(withJSONObject: body)
        let path = "noticeboard/read/\(notice.eventCode)/\(notice.pubId)/101"
        let detail = try await client.fetch(NoticeDetail.self, path, method: .post, body: data, useCache: false).value
        if let index = notices.firstIndex(where: { $0.id == notice.id }) {
            notices[index].isRead = true
        }
        return detail
    }

    func downloadAttachment(_ attachment: NoticeAttachment, of notice: Notice) async throws -> URL {
        guard let client else { throw APIError.notAuthenticated }
        // Classeviva risponde "item must first be read" se la comunicazione non è stata aperta.
        if notices.first(where: { $0.id == notice.id })?.isRead != true {
            _ = try await openNotice(notice)
        }
        let path = "noticeboard/attach/\(notice.eventCode)/\(notice.pubId)/\(attachment.number)"
        return try await client.download(path, suggestedName: attachment.fileName)
    }

    var unreadNoticesCount: Int { notices.filter { !$0.isRead }.count }

    // MARK: Note

    func readNote(_ note: DisciplinaryNote) async {
        guard let client, !note.isRead else { return }
        let path = "notes/\(note.category.rawValue)/read/\(note.id)"
        if let response = try? await client.fetch(NoteReadResponse.self, path, method: .post, useCache: false).value,
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
                                           method: .post, useCache: false).value
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
        eventsByDay[CVDate.dayKey(day)] ?? []
    }

    func absences(on day: Date) -> [AbsenceEvent] {
        absencesByDay[CVDate.dayKey(day)] ?? []
    }

    func calendarStatus(on day: Date) -> CalendarDay? {
        calendarByDay[CVDate.dayKey(day)]
    }

    var unjustifiedAbsences: [AbsenceEvent] { absences.filter { !$0.isJustified } }
}
