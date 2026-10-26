import ActivityKit
import BackgroundTasks
import Foundation
import SwiftUI
import UIKit

/// Avvia, aggiorna e chiude l'attività in diretta "Orario di oggi" (`TimetableActivityAttributes`),
/// senza server: tutto parte dall'app.
///
/// - I dati sono quelli dei widget: `WidgetExporter` passa ogni istantanea nuova (`update`), così
///   l'attività segue i cambi dell'orario, `refreshAll`, il ritorno nell'app e la mezzanotte.
/// - Lo stato porta la fase attuale e la successiva e scade alla fine della prima: se l'app non si
///   sveglia in tempo, la vista mostra da sola la fase successiva (`isStale`).
/// - Con l'app in esecuzione si aggiorna a ogni passaggio di fase; in secondo piano ci prova
///   l'aggiornamento in background programmato al passaggio successivo (iOS decide se e quando).
/// - Avvio automatico (Impostazioni › Orario): oggi dalla mezz'ora prima della prima lezione fino
///   alla fine dell'ultima; il prossimo giorno di scuola viene programmato in anticipo (iOS 26) e
///   parte da solo anche con l'app chiusa.
/// - Fermata a mano (pulsante della card "Adesso") o tolta dalla schermata di blocco, per quel
///   giorno non riparte da sola; avviata a mano, quel giorno resta anche senza avvio automatico.
/// - Tornando nell'app l'attività di oggi già in corso da un po' viene rifatta da capo
///   (`sceneBecameActive`): se iOS smette di disegnarla (rotella sopra il contenuto) da sola non si
///   riprende nemmeno con gli aggiornamenti, ma solo con un'attività nuova. Con l'app in primo
///   piano non si vede: la Dynamic Island nasconde le attività dell'app aperta.
@Observable
final class LiveActivityManager {
    /// Aggiornamento in background al prossimo passaggio di fase (`BGTaskSchedulerPermittedIdentifiers`).
    static let refreshTaskID = "com.bcw.app.liveactivity"
    /// Giorno (`yyyy-MM-dd`) in cui l'attività è stata fermata a mano o tolta dalla schermata di blocco.
    private static let stoppedKey = "liveActivityStoppedDay"
    /// Giorno in cui l'attività è stata avviata a mano.
    private static let manualKey = "liveActivityManualDay"
    /// Dopo l'ultima lezione "Lezioni finite" resta per poco nella schermata di blocco.
    private static let finishedLinger: TimeInterval = 10 * 60
    /// Tempo minimo tra un rinnovo dell'attività e il successivo (`sceneBecameActive`).
    private static let renewalInterval: TimeInterval = 10 * 60
    /// Un'attività chiusa entro questo tempo dalla richiesta l'ha chiusa iOS (l'estensione non è
    /// riuscita a disegnarla), non l'utente.
    private static let failedStartWindow: TimeInterval = 15

    /// iOS permette le attività in diretta di BCW (Impostazioni di iOS › BCW).
    private(set) var areActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    /// L'attività di oggi è in corso (per il pulsante della card "Adesso").
    private(set) var isRunningToday = false
    /// iOS ha chiuso l'attività appena avviata o non l'ha accettata: messaggio per un avviso.
    var failure: String?

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var snapshot: WidgetSnapshot?
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var isSyncing = false
    @ObservationIgnored private var needsSync = false
    /// Attività di cui si seguono gli stati.
    @ObservationIgnored private var watched: Set<String> = []
    /// Attività chiuse dall'app (le altre chiuse le ha tolte l'utente).
    @ObservationIgnored private var endedByApp: Set<String> = []
    /// Istante dell'aggiornamento in background già richiesto.
    @ObservationIgnored private var refreshDate: Date?
    /// L'attività di oggi va rifatta da capo al prossimo allineamento (`sceneBecameActive`).
    @ObservationIgnored private var renewalRequested = false
    /// Ultima attività di oggi richiesta (nuova o rinnovata).
    @ObservationIgnored private var lastRequest: Date?
    /// Istante della richiesta delle attività avviate subito (per riconoscere quelle chiuse da iOS).
    @ObservationIgnored private var requestedAt: [String: Date] = [:]
    /// Dopo una chiusura da parte di iOS non si riprova fino a questo istante (niente cicli).
    @ObservationIgnored private var retryAfter: Date?
    /// Motivo dell'ultima richiesta non riuscita.
    @ObservationIgnored private var lastRequestError: String?
    #if DEBUG
    /// Orario finto di `-BCWLiveActivityDemo YES`.
    @ObservationIgnored private var demoItems: [TimetableActivityPlan.Item]?
    /// Inizio programmato della prova (`-BCWLiveActivityDemoStart N`).
    @ObservationIgnored private var demoStart: Date?
    #endif

    private typealias TimetableActivity = Activity<TimetableActivityAttributes>

    func start(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        Task { [weak self] in
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                self?.areActivitiesEnabled = enabled
                self?.sync()
            }
        }
        Task { [weak self] in
            for await activity in TimetableActivity.activityUpdates {
                self?.watch(activity)
            }
        }
        for activity in TimetableActivity.activities { watch(activity) }
        #if DEBUG
        prepareDemo()
        #endif
    }

    /// Nuova istantanea dei widget: l'attività si allinea.
    func update(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
        sync()
    }

    /// Avvia o ferma a mano l'attività di oggi e dice com'è andata (per l'avviso della card
    /// "Adesso"): prima l'avviso diceva "avviata" anche quando iOS non l'aveva accettata.
    func toggleToday() async -> (message: String, failed: Bool) {
        let key = BCWShared.dayKey(Date())
        let defaults = UserDefaults.standard
        let stopping = isRunningToday
        if stopping {
            defaults.set(key, forKey: Self.stoppedKey)
            defaults.removeObject(forKey: Self.manualKey)
        } else {
            defaults.removeObject(forKey: Self.stoppedKey)
            defaults.set(key, forKey: Self.manualKey)
            // Avviata a mano: si riprova anche subito dopo una chiusura da parte di iOS.
            retryAfter = nil
            lastRequestError = nil
        }
        sync()
        for _ in 0..<50 where isSyncing { try? await Task.sleep(for: .milliseconds(100)) }
        if stopping { return ("Attività in diretta fermata per oggi", false) }
        if isRunningToday { return ("Attività in diretta avviata: la trovi nella schermata di blocco", false) }
        if let lastRequestError { return ("L'attività in diretta non è partita: \(lastRequestError)", true) }
        return ("L'attività in diretta non è partita: oggi non ci sono più lezioni in orario", true)
    }

    /// L'app è tornata in primo piano: l'attività di oggi, se è in corso da più di 10 minuti, viene
    /// chiusa e richiesta di nuovo con lo stesso contenuto. Quando iOS non riesce più a disegnarla
    /// mostra il contenuto vecchio sbiadito con una rotella e ignora anche gli aggiornamenti
    /// successivi; si riprende solo con un'attività nuova (prima bisognava spegnerla e riaccenderla).
    func sceneBecameActive() {
        guard model != nil else { return }
        if let lastRequest, Date().timeIntervalSince(lastRequest) < Self.renewalInterval { return }
        renewalRequested = true
        sync()
    }

    /// Aggiornamento in background: allinea l'attività all'ora attuale con l'ultima istantanea
    /// salvata (niente rete) e programma il passaggio successivo.
    func runBackgroundRefresh(model: AppModel) async {
        start(model: model)
        refreshDate = nil
        if snapshot == nil { snapshot = WidgetSnapshot.load() }
        sync()
        for _ in 0..<100 where isSyncing { try? await Task.sleep(for: .milliseconds(100)) }
    }

    /// Allinea le attività a quelle volute adesso (le richieste ravvicinate si uniscono).
    func sync() {
        guard !isSyncing else {
            needsSync = true
            return
        }
        isSyncing = true
        Task {
            repeat {
                needsSync = false
                await reconcile(now: Date())
            } while needsSync
            isSyncing = false
        }
    }

    // MARK: Attività volute

    /// Un'attività da avere: subito o programmata.
    private struct Wish {
        let dayKey: String
        /// Inizio programmato (`nil`: adesso).
        let start: Date?
        let plan: TimetableActivityPlan
        let content: ActivityContent<TimetableActivityState>

        func matches(_ activity: TimetableActivity) -> Bool {
            guard activity.attributes.dayKey == dayKey else { return false }
            if let start {
                guard activity.activityState == .pending, let scheduled = activity.attributes.scheduledStart else { return false }
                return abs(scheduled.timeIntervalSince(start)) < 1
            }
            return activity.activityState != .pending
        }
    }

    /// Le attività da avere adesso e il piano di oggi; `nil` finché non ci sono dati (all'avvio non
    /// si tocca nulla).
    private func currentWishes(now: Date) -> (wishes: [Wish], today: TimetableActivityPlan?)? {
        guard let model, let snapshot else { return nil }
        // La prova vale anche senza account (riaperta da iOS in background, senza la demo).
        guard areActivitiesEnabled, snapshot.signedIn || isDemo else { return ([], nil) }
        let theme = TimetableActivityTheme(snapshot.theme)
        let calendar = BCWShared.calendar
        let today = calendar.startOfDay(for: now)
        let todayKey = BCWShared.dayKey(today)
        let defaults = UserDefaults.standard
        let stopped = defaults.string(forKey: Self.stoppedKey)
        // La prova parte da sola, ma si ferma con il pulsante della card come le altre.
        let manual = defaults.string(forKey: Self.manualKey) == todayKey || (isDemo && stopped != todayKey)
        // Con "Prova la demo" niente avvio automatico (né programmato, con il suo avviso, per il
        // giorno dopo): l'orario è di prova e la demo resta aperta anche riaprendo l'app. A mano sì.
        let automatic = model.preferences.liveActivities && !isDemo && !snapshot.isDemo
        var wishes: [Wish] = []

        let todayPlan = plan(for: today, snapshot: snapshot)
        #if DEBUG
        // `-BCWLiveActivityDemoStart N`: la prova parte da sola tra N secondi, anche con l'app chiusa.
        if let plan = todayPlan, let start = demoStart, now < start.addingTimeInterval(-5),
           let content = plan.content(at: start, theme: theme) {
            return ([Wish(dayKey: todayKey, start: start, plan: plan, content: content)], todayPlan)
        }
        #endif
        let waiting = retryAfter.map { now < $0 } ?? false
        if let plan = todayPlan, manual || (automatic && stopped != todayKey), !waiting,
           let content = plan.content(at: now, theme: theme) {
            let running = TimetableActivity.activities.contains {
                $0.attributes.dayKey == todayKey && ($0.activityState == .active || $0.activityState == .stale)
            }
            if manual || running || now >= plan.autoStart.addingTimeInterval(-60) {
                wishes.append(Wish(dayKey: todayKey, start: nil, plan: plan, content: content))
            } else if let content = plan.content(at: plan.autoStart, theme: theme) {
                wishes.append(Wish(dayKey: todayKey, start: plan.autoStart, plan: plan, content: content))
            }
        }
        // Il prossimo giorno di scuola parte da solo mezz'ora prima della prima lezione.
        if automatic {
            for offset in 1...TimetableDefaultDay.lookahead {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      let plan = plan(for: day, snapshot: snapshot) else { continue }
                let key = BCWShared.dayKey(day)
                if stopped != key, plan.autoStart > now.addingTimeInterval(60),
                   let content = plan.content(at: plan.autoStart, theme: theme) {
                    wishes.append(Wish(dayKey: key, start: plan.autoStart, plan: plan, content: content))
                }
                break
            }
        }
        return (wishes, todayPlan)
    }

    private func plan(for day: Date, snapshot: WidgetSnapshot) -> TimetableActivityPlan? {
        #if DEBUG
        if let demoItems {
            return BCWShared.calendar.isDateInToday(day) ? TimetableActivityPlan(day: day, items: demoItems) : nil
        }
        #endif
        guard snapshot.hasTimetable, !snapshot.isHoliday(day) else { return nil }
        return TimetableActivityPlan(snapshot: snapshot, day: day)
    }

    private var isDemo: Bool {
        #if DEBUG
        demoItems != nil
        #else
        false
        #endif
    }

    // MARK: Allineamento

    private func reconcile(now: Date) async {
        guard let current = currentWishes(now: now) else { return }
        let (wishes, todayPlan) = current
        // Il rinnovo vale solo con l'app in primo piano (le richieste da lì sono sempre permesse).
        let renew = renewalRequested && UIApplication.shared.applicationState == .active
        renewalRequested = false
        var satisfied = Set<Int>()
        for activity in TimetableActivity.activities {
            let state = activity.activityState
            guard state == .active || state == .stale || state == .pending else { continue }
            if let index = wishes.indices.first(where: { !satisfied.contains($0) && wishes[$0].matches(activity) }) {
                // Non quella appena richiesta (il ritorno nell'app può arrivare durante la richiesta).
                let recent = requestedAt[activity.id].map { now.timeIntervalSince($0) < Self.renewalInterval } ?? false
                if renew, wishes[index].start == nil, state != .pending, !recent {
                    // Chiusa subito e richiesta di nuovo qui sotto, come spegnendo e riaccendendo.
                    endedByApp.insert(activity.id)
                    await activity.end(nil, dismissalPolicy: .immediate)
                    log("rinnovata \(activity.attributes.dayKey)")
                    continue
                }
                satisfied.insert(index)
                let content = wishes[index].content
                if activity.content.state != content.state || activity.content.staleDate != content.staleDate {
                    await activity.update(content)
                    log("aggiornata \(activity.attributes.dayKey): \(content.state.phases.map(\.kind.rawValue))")
                }
                continue
            }
            endedByApp.insert(activity.id)
            if let plan = todayPlan, activity.attributes.dayKey == BCWShared.dayKey(plan.day), now >= plan.end,
               state != .pending, let theme = snapshot.map({ TimetableActivityTheme($0.theme) }) {
                // Finite le lezioni: "Lezioni finite" per qualche minuto, poi via.
                let until = plan.end.addingTimeInterval(Self.finishedLinger)
                await activity.end(plan.finalContent(theme: theme), dismissalPolicy: now < until ? .after(until) : .immediate)
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            log("chiusa \(activity.attributes.dayKey)\(state == .pending ? " (in attesa)" : "")")
        }
        for (index, wish) in wishes.enumerated() where !satisfied.contains(index) {
            request(wish)
        }
        updateRunning()
        scheduleNextChange(wishes: wishes, now: now)
    }

    private func request(_ wish: Wish) {
        let attributes = TimetableActivityAttributes(dayKey: wish.dayKey, scheduledStart: wish.start)
        do {
            if let start = wish.start {
                let first = wish.plan.lessons[0]
                var body = "Alle \(WidgetDates.time(first.start))"
                if !first.room.isEmpty { body += " · \(first.room)" }
                let alert = AlertConfiguration(title: LocalizedStringResource(stringLiteral: first.title),
                                               body: LocalizedStringResource(stringLiteral: body), sound: .default)
                _ = try TimetableActivity.request(attributes: attributes, content: wish.content, pushType: nil,
                                                  style: .standard, alertConfiguration: alert, start: start)
            } else {
                let activity = try TimetableActivity.request(attributes: attributes, content: wish.content, pushType: nil)
                lastRequest = Date()
                requestedAt[activity.id] = Date()
            }
            lastRequestError = nil
            log("richiesta \(wish.dayKey) \(wish.start.map { "programmata alle \(WidgetDates.time($0))" } ?? "subito")")
        } catch {
            lastRequestError = Self.describe(error)
            log("richiesta \(wish.dayKey) non riuscita: \(error)")
        }
    }

    /// Al prossimo cambio di contenuto: subito se l'app è in esecuzione, in background se iOS lo
    /// concede.
    private func scheduleNextChange(wishes: [Wish], now: Date) {
        let next = wishes.compactMap { wish -> Date? in
            // In attesa: il contenuto preparato vale fino alla prima lezione.
            wish.plan.nextChange(after: max(now, wish.start ?? now))
        }.min()
        changeTask?.cancel()
        changeTask = nil
        if let next {
            changeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow + 1)))
                guard !Task.isCancelled else { return }
                self?.sync()
            }
        }
        guard next != refreshDate else { return }
        refreshDate = next
        if let next {
            let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
            request.earliestBeginDate = next
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                log("aggiornamento in background non programmato: \(error)")
            }
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskID)
        }
    }

    // MARK: Stati

    private func watch(_ activity: TimetableActivity) {
        guard watched.insert(activity.id).inserted else { return }
        updateRunning()
        let id = activity.id
        let day = activity.attributes.dayKey
        Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard let self else { return }
                if state == .dismissed || state == .ended, !self.endedByApp.contains(id),
                   let requested = self.requestedAt[id], Date().timeIntervalSince(requested) < Self.failedStartWindow {
                    // Chiusa da iOS appena avviata (l'estensione non è riuscita a disegnarla): non è
                    // l'utente, quindi niente "fermata per oggi"; si riprova solo più tardi.
                    self.requestedAt[id] = nil
                    self.retryAfter = Date().addingTimeInterval(Self.renewalInterval)
                    self.failure = "iOS ha chiuso l'attività in diretta appena avviata. Riprova più tardi."
                    self.log("chiusa da iOS appena avviata: \(day)")
                } else if state == .dismissed, !self.endedByApp.contains(id) {
                    // Tolta dalla schermata di blocco: quel giorno non riparte da sola.
                    UserDefaults.standard.set(day, forKey: Self.stoppedKey)
                    if UserDefaults.standard.string(forKey: Self.manualKey) == day {
                        UserDefaults.standard.removeObject(forKey: Self.manualKey)
                    }
                    self.log("tolta dall'utente: \(day)")
                }
                self.updateRunning()
            }
        }
    }

    private func updateRunning() {
        let key = BCWShared.dayKey(Date())
        let running = TimetableActivity.activities.contains {
            $0.attributes.dayKey == key && ($0.activityState == .active || $0.activityState == .stale)
        }
        if running != isRunningToday { isRunningToday = running }
    }

    /// Motivo di una richiesta rifiutata da ActivityKit, per l'avviso.
    private static func describe(_ error: Error) -> String {
        if let error = error as? ActivityAuthorizationError {
            switch error {
            case .denied: return "le attività in diretta di BCW sono spente nelle Impostazioni di iOS."
            case .globalMaximumExceeded, .targetMaximumExceeded: return "ci sono già troppe attività in diretta aperte."
            case .visibility: return "BCW non era in primo piano."
            default: break
            }
        }
        return error.localizedDescription
    }

    private func log(_ message: String) {
        #if DEBUG
        print("BCW-LIVE \(message)")
        #endif
    }

    // MARK: Prova

    #if DEBUG
    /// Solo DEBUG, `-BCWLiveActivityDemo YES`: un orario finto attorno a adesso con fasi brevi
    /// (`-BCWLiveActivitySeconds N`, 60 di serie): prima lezione tra N secondi, lezioni da 2N,
    /// un intervallo da N, la seconda lezione con una verifica. Con `-BCWLiveActivityDemoStart S`
    /// l'attività viene programmata (iOS 26) e parte da sola tra S secondi, prima lezione N
    /// secondi dopo.
    ///
    /// La prova resta salvata finché non finisce: quando parte un'attività programmata (o arriva
    /// l'aggiornamento in background) iOS riapre l'app senza gli argomenti di avvio, e senza la
    /// prova l'app avrebbe chiuso l'attività come non più voluta (verificato).
    private func prepareDemo() {
        let defaults = UserDefaults.standard
        let now = Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded())
        let start: Date, unit: TimeInterval
        if defaults.bool(forKey: "BCWLiveActivityDemo") {
            unit = TimeInterval(defaults.integer(forKey: "BCWLiveActivitySeconds") > 0
                ? defaults.integer(forKey: "BCWLiveActivitySeconds") : 60)
            // Secondi interi: le date tornano uguali da ActivityKit.
            let delay = TimeInterval(max(0, defaults.integer(forKey: "BCWLiveActivityDemoStart")))
            demoStart = delay > 0 ? now.addingTimeInterval(delay) : nil
            start = now.addingTimeInterval(delay + unit)
            defaults.set([start.timeIntervalSinceReferenceDate, unit,
                          demoStart?.timeIntervalSinceReferenceDate ?? 0], forKey: Self.demoKey)
            // Una prova nuova parte anche se oggi l'attività è stata fermata.
            defaults.removeObject(forKey: Self.stoppedKey)
        } else if let saved = defaults.array(forKey: Self.demoKey) as? [Double], saved.count == 3 {
            start = Date(timeIntervalSinceReferenceDate: saved[0])
            unit = saved[1]
            // Lezioni finite (7 unità) e "Lezioni finite" rimasto per un po': la prova è finita.
            guard now < start.addingTimeInterval(7 * unit + Self.finishedLinger) else {
                defaults.removeObject(forKey: Self.demoKey)
                return
            }
            demoStart = saved[2] > 0 ? Date(timeIntervalSinceReferenceDate: saved[2]) : nil
        } else {
            // `-BCWLiveActivityDemoPlan '()'`: la prova salvata si cancella (l'argomento vale solo
            // per questo avvio; senza, riaprendo l'app la prova ripartiva).
            if defaults.array(forKey: Self.demoKey)?.isEmpty == true {
                defaults.removeObject(forKey: Self.demoKey)
            }
            return
        }
        demoItems = TimetableActivityPlan.sampleItems(start: start, unit: unit)
        log("prova: prima lezione alle \(WidgetDates.time(start)), fasi da \(Int(unit)) s")
    }

    /// La prova in corso: prima lezione, durata delle fasi, inizio programmato (0 se subito).
    private static let demoKey = "BCWLiveActivityDemoPlan"
    #endif
}

/// Mostra in un avviso le attività in diretta chiuse da iOS appena avviate (va messo dentro
/// `overlayHost()`).
struct LiveActivityFailureReporter: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(OverlayHost.self) private var host: OverlayHost?

    func body(content: Content) -> some View {
        content
            .onChange(of: model.liveActivities.failure) { _, message in
                guard let message else { return }
                host?.showToast(message, icon: "alertCircle")
                model.liveActivities.failure = nil
            }
    }
}
