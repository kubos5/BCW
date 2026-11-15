import BackgroundTasks
import OSLog
import UIKit

/// Aggiornamento in background di iOS, uno solo per tutta l'app: notifiche delle novità, widget e
/// attività in diretta.
///
/// iOS tiene in sospeso al massimo **una** richiesta di aggiornamento (`BGAppRefreshTaskRequest`) per
/// app: alla seconda, con un altro identificativo, `submit` risponde `tooManyPendingTaskRequests`.
/// Fino alla 3.3.1 notifiche e attività in diretta ne chiedevano una ciascuna: quella dell'attività
/// (programmata a ogni passaggio di fase) faceva fallire in silenzio quella delle notifiche, che così
/// arrivavano solo aprendo l'app (segnalato dall'utente, 4.0). Ora c'è una richiesta sola, alla prima
/// data che serve all'una o all'altra, e ogni esecuzione fa tutte e due le cose.
///
/// Senza un server che invii notifiche push resta iOS a decidere quando eseguirla (in base a quanto
/// si usa l'app, alla batteria e alla rete), e non la esegue se l'app è stata chiusa dal selettore
/// delle app, con il risparmio energetico o con "Aggiorna app in background" spento.
enum BackgroundRefresh {
    /// Identificativo dell'aggiornamento (in `BGTaskSchedulerPermittedIdentifiers`).
    static let taskID = "com.bcw.app.refresh"
    /// Identificativo dell'attività in diretta fino alla 3.3.1: resta permesso e con il suo gestore per
    /// una richiesta ancora in sospeso dopo l'aggiornamento dell'app, ma non si chiede più.
    static let legacyTaskID = "com.bcw.app.liveactivity"
    /// Al più presto tra quanto si cercano di nuovo le novità (iOS di solito aspetta di più).
    static let newsInterval: TimeInterval = 15 * 60

    private static let log = Logger(subsystem: "com.bcw-classeviva.app", category: "BackgroundRefresh")

    /// Le novità vanno cercate in background: qualche tipo di notifica è acceso e c'è un account vero.
    @MainActor
    static func wantsNews(_ model: AppModel) -> Bool {
        !model.preferences.newsNotifications.isEmpty && model.phase == .signedIn && !model.isDemo
    }

    /// Chiede (o sostituisce) la richiesta di aggiornamento, alla prima data che serve.
    @MainActor
    static func schedule(model: AppModel) {
        let news = wantsNews(model) ? Date(timeIntervalSinceNow: newsInterval) : nil
        let live = model.liveActivities.backgroundRefreshDate
        guard let date = [news, live].compactMap({ $0 }).min() else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = date
        do {
            // Con lo stesso identificativo la richiesta nuova sostituisce quella in sospeso.
            try BGTaskScheduler.shared.submit(request)
        } catch {
            log.error("Aggiornamento in background non programmato: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Esecuzione dell'aggiornamento: prima l'attività in diretta (senza rete, è la più urgente), poi i
    /// dati con le notifiche delle novità, i widget e di nuovo l'attività con i dati nuovi.
    @MainActor
    static func run(model: AppModel) async {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: legacyTaskID)
        // Il prossimo subito: se iOS interrompe questo, il seguente resta chiesto.
        schedule(model: model)
        if model.phase == .launching { model.bootstrap() }
        await model.liveActivities.runBackgroundRefresh(model: model)
        if model.phase == .signedIn, !model.isDemo {
            // `bootstrap` può aver già avviato un aggiornamento: si aspetta che finisca.
            for _ in 0..<50 where model.isRefreshing { try? await Task.sleep(for: .milliseconds(200)) }
            // Le notifiche partono alla fine di `refreshAll` (`NewsNotifications.process`).
            await model.refreshAll()
            // L'app può essere sospesa subito dopo: i widget si aggiornano ora, senza attesa.
            model.widgets.export()
            await model.liveActivities.runBackgroundRefresh(model: model)
        }
        schedule(model: model)
    }

    /// iOS non esegue gli aggiornamenti in background (impostazione spenta o limitata).
    @MainActor
    static var isUnavailable: Bool {
        UIApplication.shared.backgroundRefreshStatus != .available
    }
}
