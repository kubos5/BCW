import Foundation
import UserNotifications

/// Promemoria locali: la sera prima di ogni compito o verifica.
/// Vengono ripianificati ogni volta che l'agenda viene aggiornata,
/// quindi non serve un server di notifiche push.
enum Reminders {
    private static let prefix = "bcw.agenda."

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reschedule(events: [AgendaEvent], hour: Int, enabled: Bool, completed: Set<Int>) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
        guard enabled else { return }

        let now = Date()
        let horizon = now.adding(days: 14)
        let relevant = events
            .filter { $0.kind != .event && $0.begin > now && $0.begin < horizon && !completed.contains($0.id) }
            .sorted { $0.begin < $1.begin }

        let byDay = Dictionary(grouping: relevant, by: \.day)
        for (day, items) in byDay.sorted(by: { $0.key < $1.key }).prefix(40) {
            guard let fireDate = CVDate.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.adding(days: -1)),
                  fireDate > now else { continue }
            let content = UNMutableNotificationContent()
            let tests = items.filter { $0.kind == .test }
            let homework = items.filter { $0.kind == .homework }
            if !tests.isEmpty {
                content.title = tests.count == 1 ? "Domani: verifica di \(tests[0].title.lowercased())" : "Domani: \(tests.count) verifiche"
            } else {
                content.title = homework.count == 1 ? "Compiti per domani" : "\(homework.count) compiti per domani"
            }
            content.body = items.map { "\($0.title): \($0.notes)" }.joined(separator: "\n")
            content.sound = .default
            let comps = CVDate.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: prefix + CVDate.dayKey(day), content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
