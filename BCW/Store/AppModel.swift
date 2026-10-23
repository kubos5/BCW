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
    /// Orario settimanale dell'account attivo (sul dispositivo; con l'account BCW anche sul server).
    let timetable = TimetableStore()
    /// Sincronizzazione di impostazioni e orario con l'account BCW.
    let cloudSync = CloudSync()
    /// Istantanea dei dati per i widget (nel contenitore dell'App Group).
    let widgets = WidgetExporter()
    /// Attività in diretta "Orario di oggi" (segue le istantanee dei widget).
    let liveActivities = LiveActivityManager()
    /// Collegamento `bcw://` aperto da un widget, in attesa che la scheda giusta lo usi.
    var openedLink: DeepLink?

    // Account BCW
    /// Sessione dell'account BCW. Con l'account BCW `accounts` sono gli account Classeviva
    /// abbinati sul server (con il loro id), altrimenti quelli salvati sul dispositivo.
    private(set) var cloud: BCWSession?
    /// Avviso per la schermata di accesso (es. sessione BCW scaduta).
    var cloudNotice: String?
    /// Nome utente dell'ultimo account BCW, per riempire il campo dopo l'uscita.
    private(set) var lastCloudUsername: String?
    /// Account del dispositivo da proporre di abbinare dopo l'accesso con l'account BCW.
    var localAccountsToLink: [SavedAccount] = []
    /// Account del dispositivo che non è stato possibile abbinare, con il motivo.
    var linkFailureMessage: String?
    @ObservationIgnored private var cloudRefreshedAt = Date.distantPast
    @ObservationIgnored private var cloudRefreshing = false
    /// `bootstrap` già fatto (una seconda finestra dell'iPad lo richiamerebbe).
    @ObservationIgnored private var didBootstrap = false

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
    private static let activeCloudAccountKey = "activeCloudAccount"
    static let gradePaths = ["grades", "grades2324", "grades2"]

    init() {
        cloudSync.model = self
        preferences.onSyncedChange = { [weak self] in self?.cloudSync.settingsChanged() }
        timetable.onSaved = { [weak self] owner in self?.cloudSync.timetableChanged(owner: owner) }
    }

    /// Account attivo salvato: separato per gli account del dispositivo e per l'account BCW.
    private var activeKey: String { cloud == nil ? Self.activeAccountKey : Self.activeCloudAccountKey }

    private func saveAccounts() {
        if cloud == nil {
            Keychain.saveAccounts(accounts)
        } else {
            Keychain.saveCloudAccounts(accounts)
        }
    }

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
        // Su iPad ogni finestra in più ripasserebbe di qui (`RootView.task`): l'avvio si fa una volta.
        guard !didBootstrap else { return }
        didBootstrap = true
        // L'aspetto è in `ThemeStore`: anche i suoi cambi vanno all'account BCW.
        ThemeStore.shared.onSyncedChange = { [weak self] in self?.cloudSync.settingsChanged() }
        defer {
            liveActivities.start(model: self)
            widgets.start(model: self)
        }
        cloud = Keychain.loadCloudSession()
        accounts = cloud == nil ? Keychain.loadAccounts() : Keychain.loadCloudAccounts()
        // Con l'account BCW gli account abbinati arrivano dal server: intanto si usano quelli salvati.
        if cloud != nil { Task { await refreshCloud(force: true) } }
        // Cache delle versioni precedenti: ora ogni account (e la demo) ha la sua.
        DiskCache.remove(namespace: "live")
        for year in ArchiveModel.availableStartYears {
            DiskCache.remove(namespace: "archive-\(year)")
            DiskCache.remove(namespace: "archive-\(year)-demo")
        }
        let storedID = UserDefaults.standard.string(forKey: activeKey)
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
        if let cloud {
            // Con l'account BCW l'account viene abbinato sul server, che verifica le credenziali.
            let linked = try await linkOnServer(stored, token: cloud.token)
            account = upsertCloudAccount(linked)
        } else if let index = accounts.firstIndex(where: { $0.matches(stored) }) {
            accounts[index].credentials = stored
            if !name.isEmpty { accounts[index].name = name }
            account = accounts[index]
        } else {
            account = SavedAccount(credentials: stored, name: name.isEmpty ? stored.username : name)
            accounts.append(account)
        }
        saveAccounts()
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
        withAnimation(Motion.effects) {
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
        UserDefaults.standard.set(account.id, forKey: activeKey)
        loginName = account.name
        timetable.load(owner: account.id)
        if cloud != nil { cloudSync.pullTimetable(account.id) }
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
        timetable.load(owner: "demo")
        client = ClassevivaClient(transport: DemoTransport(), cacheNamespace: "demo",
                                  credentials: Credentials(username: "demo", password: "demo"))
        withAnimation { phase = .signedIn }
        Task { await refreshAll() }
    }

    /// Esce dall'account attivo (o dalla demo). Se ci sono altri account salvati
    /// passa al successivo, altrimenti torna alla schermata di accesso.
    func signOut() {
        if cloud != nil, !isDemo {
            Task { await cloudSignOut() }
            return
        }
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
        // L'orario della demo è di prova: uscendo si cancella come il resto.
        timetable.load(owner: nil)
        TimetableStore.removeData(owner: "demo")
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
        if cloud != nil {
            // L'orario di un account abbinato è sul server: dal dispositivo se ne va con l'account.
            TimetableStore.removeData(owner: account.id)
            cloudSync.forgetTimetable(account.id)
        }
        accounts.removeAll { $0.id == id }
        saveAccounts()
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
        timetable.load(owner: nil)
        UserDefaults.standard.removeObject(forKey: activeKey)
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
        saveAccounts()
        if let cloud {
            let account = accounts[index]
            Task { try? await BCWAPI.updateAccount(token: cloud.token, id: account.id, name: account.name, school: account.school) }
        }
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

    // MARK: Collegamenti

    /// Apre un collegamento `bcw://` (dai widget): `MainTabView` sceglie la scheda e la scheda il
    /// giorno. All'avvio dell'app da un widget può arrivare prima della sessione: resta in attesa
    /// finché le schede non compaiono. Senza account non fa nulla.
    func open(_ url: URL) {
        guard let link = DeepLink(url: url), phase != .signedOut else { return }
        openedLink = link
    }

    // MARK: Account BCW

    var isCloud: Bool { cloud != nil }

    /// Accede all'account BCW (o lo crea con `register`) e passa agli account Classeviva abbinati.
    /// Gli account del dispositivo non ancora abbinati finiscono in `localAccountsToLink`.
    func cloudSignIn(username: String, password: String, register: Bool) async throws {
        let session = try await BCWAPI.signIn(username: username.trimmingCharacters(in: .whitespaces),
                                              password: password, register: register)
        let remote = try await BCWAPI.accounts(token: session.token).compactMap(\.savedAccount)
        let local = cloud == nil ? Keychain.loadAccounts() : []
        let candidates = local.filter { account in !remote.contains { $0.isSameProfile(as: account) } }
        cloudNotice = nil
        cloudRefreshedAt = .now
        changeSession {
            if self.isDemo { self.leaveDemo() }
            self.cloudSync.reset()
            self.cloud = session
            Keychain.saveCloudSession(session)
            self.accounts = remote
            self.saveAccounts()
            if let first = remote.first {
                self.activate(first)
            } else {
                self.endSession()
            }
            self.cloudSync.pullSettings()
            // La proposta arriva quando l'account BCW è già aperto (dopo la dissolvenza).
            self.localAccountsToLink = candidates
        }
    }

    private func linkOnServer(_ credentials: Credentials, token: String) async throws -> SavedAccount {
        do {
            let remote = try await BCWAPI.link(token: token, credentials: credentials)
            guard let account = remote.savedAccount else {
                throw BCWError(code: "decoding", message: "Risposta inattesa dal server BCW.")
            }
            return account
        } catch let error as BCWError where error.isUnauthorized {
            cloudSessionExpired()
            throw error
        }
    }

    /// Aggiunge o aggiorna un account abbinato (stesso id del server).
    @discardableResult
    private func upsertCloudAccount(_ remote: SavedAccount) -> SavedAccount {
        guard let index = accounts.firstIndex(where: { $0.id == remote.id }) else {
            accounts.append(remote)
            return remote
        }
        accounts[index].credentials = remote.credentials
        accounts[index].name = remote.name
        if let school = remote.school { accounts[index].school = school }
        return accounts[index]
    }

    /// Abbina all'account BCW gli account del dispositivo, copiandone l'orario.
    func linkLocalAccounts(_ locals: [SavedAccount]) async {
        var failures: [String] = []
        for local in locals {
            guard let cloud else { return }
            do {
                let linked = try await linkOnServer(local.credentials, token: cloud.token)
                let account = upsertCloudAccount(linked)
                saveAccounts()
                TimetableStore.copyData(from: local.id, to: account.id)
                cloudSync.pullTimetable(account.id)
            } catch {
                guard self.cloud != nil else { return }
                failures.append("\(local.name): \(error.localizedDescription)")
            }
        }
        if phase == .signedOut, let first = accounts.first { activate(first) }
        if !failures.isEmpty { linkFailureMessage = failures.joined(separator: "\n") }
    }

    /// Aggiorna gli account abbinati e sincronizza impostazioni e orario dell'account attivo
    /// (all'avvio, aggiornando, tornando nell'app; al massimo ogni 30 secondi senza `force`).
    func refreshCloud(force: Bool = false) async {
        guard let session = cloud, !cloudRefreshing else { return }
        guard force || Date().timeIntervalSince(cloudRefreshedAt) > 30 else { return }
        cloudRefreshing = true
        defer { cloudRefreshing = false }
        do {
            let remote = try await BCWAPI.accounts(token: session.token).compactMap(\.savedAccount)
            guard cloud == session else { return }
            cloudRefreshedAt = .now
            applyRemoteAccounts(remote)
        } catch let error as BCWError where error.isUnauthorized {
            if cloud == session { cloudSessionExpired() }
            return
        } catch {
            // Senza rete restano gli account salvati; si riprova al prossimo aggiornamento.
            return
        }
        cloudSync.pullSettings()
        if let active = activeAccount, !isDemo { cloudSync.pullTimetable(active.id) }
    }

    /// Allinea gli account abbinati a quelli del server (aggiunti o tolti da un altro dispositivo).
    private func applyRemoteAccounts(_ list: [SavedAccount]) {
        let active = isDemo ? nil : activeAccount
        let removed = accounts.filter { account in !list.contains { $0.id == account.id } }
        var next: [SavedAccount] = []
        for remote in list {
            if var existing = accounts.first(where: { $0.id == remote.id }) {
                existing.credentials = remote.credentials
                existing.name = remote.name
                if let school = remote.school { existing.school = school }
                next.append(existing)
            } else {
                next.append(remote)
            }
        }
        if next != accounts {
            accounts = next
            saveAccounts()
        }
        for account in removed {
            removeCaches(owner: account.id)
            TimetableStore.removeData(owner: account.id)
            cloudSync.forgetTimetable(account.id)
        }
        // Password cambiata da un altro dispositivo: il prossimo accesso usa quella nuova.
        if let active, let fresh = next.first(where: { $0.id == active.id }), fresh.credentials != active.credentials {
            client?.credentials = fresh.credentials
        }
        guard !isDemo else { return }
        if let active, !next.contains(where: { $0.id == active.id }) {
            if let first = next.first {
                changeSession { self.activate(first) }
            } else {
                endSession()
            }
        } else if phase == .signedOut, let first = next.first {
            activate(first)
        }
    }

    /// Scollega un account Classeviva dall'account BCW (con il suo orario sul server).
    func unlinkAccount(_ id: String) async throws {
        guard let cloud else {
            removeAccount(id)
            return
        }
        do {
            try await BCWAPI.unlink(token: cloud.token, id: id)
        } catch let error as BCWError where error.isUnauthorized {
            cloudSessionExpired()
            return
        } catch let error as BCWError where error.code == "not_found" {
            // Già scollegato, ad esempio da un altro dispositivo.
        }
        removeAccount(id)
    }

    /// Esce dall'account BCW: gli account abbinati, le loro cache e i loro orari spariscono dal
    /// dispositivo (restano sul server) e tornano quelli salvati sul dispositivo.
    func cloudSignOut() async {
        guard let session = cloud else { return }
        // Le ultime modifiche in attesa partono prima di uscire (al massimo 3 secondi).
        await cloudSync.flush(timeout: .seconds(3))
        Task { try? await BCWAPI.signOut(token: session.token) }
        leaveCloud()
    }

    func cloudSessionExpired() {
        guard cloud != nil else { return }
        leaveCloud(notice: "La sessione dell'account BCW è scaduta o è stata chiusa: accedi di nuovo.")
    }

    private func leaveCloud(notice: String? = nil) {
        guard let session = cloud else { return }
        let cloudAccounts = accounts
        cloudNotice = notice
        lastCloudUsername = session.user.username
        localAccountsToLink = []
        changeSession {
            guard self.cloud != nil else { return }
            if self.isDemo { self.leaveDemo() } else { self.resetData() }
            for account in cloudAccounts {
                self.removeCaches(owner: account.id)
                TimetableStore.removeData(owner: account.id)
            }
            Keychain.saveCloudSession(nil)
            Keychain.saveCloudAccounts([])
            UserDefaults.standard.removeObject(forKey: Self.activeCloudAccountKey)
            self.cloudSync.reset()
            self.cloud = nil
            self.accounts = Keychain.loadAccounts()
            let storedID = UserDefaults.standard.string(forKey: Self.activeAccountKey)
            if let next = self.accounts.first(where: { $0.id == storedID }) ?? self.accounts.first {
                self.activate(next)
            } else {
                self.endSession()
            }
        }
    }

    func changeCloudPassword(current: String, new: String) async throws {
        guard let session = cloud else { return }
        let token = try await BCWAPI.changePassword(token: session.token, current: current, new: new)
        let updated = BCWSession(token: token, user: session.user)
        cloud = updated
        Keychain.saveCloudSession(updated)
    }

    func deleteCloudAccount(password: String) async throws {
        guard let session = cloud else { return }
        try await BCWAPI.deleteAccount(token: session.token, password: password)
        leaveCloud()
    }

    /// Le impostazioni sono cambiate da un altro dispositivo.
    func settingsApplied() {
        guard phase == .signedIn else { return }
        Task { await rescheduleReminders() }
    }

    // MARK: Lato Classeviva

    /// Profilo e token di Classeviva dell'account attivo, che provano a BCW-api l'accesso.
    private func classevivaIdentity() async throws -> (ident: String, token: String) {
        guard let client, !isDemo else { throw BCWError(code: "demo", message: "Non disponibile nella demo.") }
        return try await client.currentSession()
    }

    /// Gli account BCW a cui è abbinato il profilo Classeviva attivo.
    func classevivaLinks() async throws -> [BCWLink] {
        let identity = try await classevivaIdentity()
        return try await BCWAPI.links(ident: identity.ident, classevivaToken: identity.token)
    }

    /// Scollega il profilo attivo da un account BCW (`nil` = da tutti).
    func removeClassevivaLink(_ id: String?) async throws {
        let identity = try await classevivaIdentity()
        try await BCWAPI.removeLink(id: id, ident: identity.ident, classevivaToken: identity.token)
        // Se era un abbinamento di questo account BCW, l'elenco degli account cambia.
        if cloud != nil { await refreshCloud(force: true) }
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
        if cloud != nil { Task { await refreshCloud() } }
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
        await NewsNotifications.process(model: self)
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
