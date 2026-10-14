import Foundation
import UserNotifications
#if os(iOS)
import BackgroundTasks
#endif

/// Tipi di novità per cui si può ricevere una notifica (Impostazioni › Notifiche).
enum NewsKind: String, CaseIterable, Identifiable {
    case grades, notices, notes, absences, agenda

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grades: "Nuovi voti"
        case .notices: "Nuove comunicazioni"
        case .notes: "Note e annotazioni"
        case .absences: "Assenze e ritardi"
        case .agenda: "Nuovi compiti e verifiche"
        }
    }

    var symbol: String {
        switch self {
        case .grades: "graduationcap"
        case .notices: "megaphone"
        case .notes: "exclamationmark.bubble"
        case .absences: "person.badge.clock"
        case .agenda: "checklist"
        }
    }
}

/// Notifiche delle novità: dopo ogni aggiornamento (in primo piano o, su iPhone, in background)
/// si confrontano voti, comunicazioni, note, assenze e agenda con quelli già visti per l'account e
/// si manda una notifica per quelli nuovi, solo per i tipi attivati. La prima volta che un tipo si
/// vede per un account si ricorda tutto senza notificare (altrimenti arriverebbe l'intero anno).
/// Gli id visti sono in `UserDefaults`, separati per account; la demo non manda notifiche.
enum NewsNotifications {
    /// Identificativo dell'aggiornamento in background (anche in `Config/Info-iOS.plist`).
    static let refreshTaskID = "com.bcw.app.refresh"
    private static let prefix = "bcw.news."
    /// Oltre questo numero di novità dello stesso tipo arriva una notifica sola, riassuntiva.
    private static let maxSingle = 4

    private struct Item {
        let id: Int
        let title: String
        let body: String
    }

    @MainActor
    static func process(model: AppModel) async {
        #if DEBUG
        // Per provarle: `-BCWNewsDemo YES` le manda anche nella demo e, la seconda volta, finge
        // che l'ultimo elemento di ogni tipo sia nuovo.
        let debugDemo = model.isDemo && UserDefaults.standard.bool(forKey: "BCWNewsDemo")
        #else
        let debugDemo = false
        #endif
        guard !model.isDemo || debugDemo, let owner = debugDemo ? "demo" : model.activeAccountID else { return }
        let enabled = model.preferences.newsNotifications
        let items = currentItems(model: model)
        var toSend: [(NewsKind, [Item])] = []
        for kind in NewsKind.allCases {
            let current = items[kind] ?? []
            let key = "seenNews.\(owner).\(kind.rawValue)"
            let stored = UserDefaults.standard.array(forKey: key) as? [Int]
            let ids = current.map(\.id)
            // Prima volta (o dati non ancora scaricati): si ricorda e basta.
            guard let stored else {
                if !ids.isEmpty { UserDefaults.standard.set(ids, forKey: key) }
                continue
            }
            var seen = Set(stored)
            if debugDemo, let last = current.last { seen.remove(last.id) }
            let fresh = current.filter { !seen.contains($0.id) }
            guard !fresh.isEmpty else { continue }
            // Si tengono gli ultimi 3000 id: abbastanza per un anno scolastico.
            UserDefaults.standard.set(Array((stored + fresh.map(\.id)).suffix(3000)), forKey: key)
            if enabled.contains(kind) { toSend.append((kind, fresh)) }
        }
        guard !toSend.isEmpty else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for (kind, fresh) in toSend {
            await send(kind: kind, items: fresh, account: model.displayName, multipleAccounts: model.accounts.count > 1)
        }
    }

    @MainActor
    private static func currentItems(model: AppModel) -> [NewsKind: [Item]] {
        var result: [NewsKind: [Item]] = [:]
        result[.grades] = model.grades.filter { !$0.canceled }.map { grade in
            Item(id: grade.id, title: "\(grade.subjectName.sentenceCased): \(grade.displayValue)",
                 body: [grade.componentName, grade.notes].compactMap { $0?.nilIfEmpty }.joined(separator: " · "))
        }
        result[.notices] = model.notices.map { Item(id: $0.id, title: $0.title, body: $0.category) }
        result[.notes] = model.notes.map { note in
            Item(id: note.id, title: "\(note.category.title) · \(note.authorName)", body: note.text)
        }
        result[.absences] = model.absences.map { absence in
            Item(id: absence.id, title: "\(absence.kind.title) del \(absence.date.shortDay)",
                 body: absence.isJustified ? "Giustificata" : "Da giustificare")
        }
        // Solo compiti e verifiche futuri: quelli passati aggiunti in ritardo non servono.
        let today = Date().startOfDay
        result[.agenda] = model.agenda.filter { $0.kind != .event && $0.begin >= today }.map { event in
            Item(id: event.id, title: "\(event.kind == .test ? "Verifica" : "Compiti") di \(event.title.lowercased()) · \(event.begin.shortDay)",
                 body: event.notes)
        }
        return result
    }

    private static func send(kind: NewsKind, items: [Item], account: String, multipleAccounts: Bool) async {
        let center = UNUserNotificationCenter.current()
        let subtitle = multipleAccounts ? account : nil
        if items.count > maxSingle {
            let content = UNMutableNotificationContent()
            content.title = "\(kind.title): \(items.count)"
            if let subtitle { content.subtitle = subtitle }
            content.body = items.prefix(5).map(\.title).joined(separator: "\n") + (items.count > 5 ? "\n…" : "")
            content.sound = .default
            content.threadIdentifier = kind.rawValue
            try? await center.add(UNNotificationRequest(identifier: prefix + kind.rawValue + ".\(UUID().uuidString)",
                                                        content: content, trigger: nil))
            return
        }
        for item in items {
            let content = UNMutableNotificationContent()
            content.title = item.title
            if let subtitle { content.subtitle = subtitle }
            content.body = item.body.isEmpty ? kind.title : item.body
            content.sound = .default
            content.threadIdentifier = kind.rawValue
            try? await center.add(UNNotificationRequest(identifier: prefix + kind.rawValue + ".\(item.id)",
                                                        content: content, trigger: nil))
        }
    }

    #if os(iOS)
    /// Chiede a iOS un aggiornamento in background (al più presto tra mezz'ora), se qualche tipo
    /// di novità è attivato. iOS sceglie quando eseguirlo, in base a come si usa l'app.
    @MainActor
    static func scheduleBackgroundRefresh(model: AppModel) {
        guard !model.preferences.newsNotifications.isEmpty else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshTaskID)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Aggiornamento in background: carica l'account (se l'app è stata avviata apposta) e aggiorna;
    /// le notifiche partono alla fine dell'aggiornamento.
    @MainActor
    static func runBackgroundRefresh(model: AppModel) async {
        scheduleBackgroundRefresh(model: model)
        if model.phase == .launching { model.bootstrap() }
        guard model.phase == .signedIn, !model.isDemo else { return }
        // `bootstrap` può aver già avviato un aggiornamento: si aspetta che finisca.
        for _ in 0..<50 where model.isRefreshing { try? await Task.sleep(for: .milliseconds(200)) }
        await model.refreshAll()
    }
    #endif
}

/// Mostra le notifiche anche con BCW aperta: senza un delegato iOS e macOS le scartano (non
/// compaiono né come banner né nel Centro notifiche).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
