#if DEBUG
import Foundation
import WidgetKit

/// Autotest dei widget (solo sviluppo): `-BCWWidgetSelfTest YES` prova la regola del giorno
/// predefinito dell'orario (`TimetableDefaultDay`, la stessa di app e widget), le voci della linea
/// temporale, la lezione in corso e la prossima, i collegamenti `bcw://`, la codifica
/// dell'istantanea e il contenitore dell'App Group. Stampa `BCW-WIDGET-SELFTEST` con l'esito ed esce.
enum WidgetSelfTest {
    static func runIfRequested() {
        guard UserDefaults.standard.bool(forKey: "BCWWidgetSelfTest") else { return }
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }

        let calendar = BCWShared.calendar
        // Mercoledì 21 ottobre 2026 (giorno della settimana 3).
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21))!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: wednesday)! }
        func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date { BCWShared.date(day(offset), minute: hour * 60 + minute) }
        check(BCWShared.weekday(of: wednesday) == 3, "giorno della settimana")

        // Regola del giorno predefinito: lezioni dal lunedì al venerdì, 8:00–14:00.
        let school: (Date) -> [TimetableDefaultDay.Span] = { date in
            BCWShared.weekday(of: date) <= 5 ? [.init(start: 8 * 60, end: 11 * 60), .init(start: 11 * 60, end: 14 * 60)] : []
        }
        func rule(_ now: Date, _ spans: (Date) -> [TimetableDefaultDay.Span] = school) -> Int {
            WidgetDates.offset(of: TimetableDefaultDay.day(now: now, spans: spans), from: wednesday)
        }
        check(rule(at(0, 7)) == 0, "prima delle lezioni: oggi")
        check(rule(at(0, 13, 59)) == 0, "durante l'ultima lezione: oggi")
        check(rule(at(0, 14)) == 1, "finita l'ultima lezione: domani")
        check(rule(at(2, 15)) == 5, "venerdì pomeriggio: lunedì")
        check(rule(at(3, 10)) == 5, "sabato senza lezioni: lunedì")
        check(rule(at(0, 15)) { _ in [] } == 0, "orario vuoto: oggi")
        check(rule(at(0, 15)) { date in
            WidgetDates.offset(of: date, from: wednesday) == 8 ? [.init(start: 480, end: 540)] : []
        } == 0, "nessun evento entro 7 giorni: oggi")
        check(rule(at(0, 15)) { date in
            WidgetDates.offset(of: date, from: wednesday) == 7 ? [.init(start: 480, end: 540)] : []
        } == 7, "evento fra 7 giorni: quel giorno")

        // Gli intervalli non contano: dopo l'ultima lezione resta solo un intervallo.
        var snapshot = WidgetSnapshot.sample(now: at(0, 9, 30))
        if let index = snapshot.days.firstIndex(where: { $0.key == BCWShared.dayKey(wednesday) }) {
            snapshot.days[index].events.append(.init(id: "pausa", title: "Intervallo", start: 13 * 60 + 10, end: 13 * 60 + 30,
                                                     kind: .breakTime, tint: .init(light: 0, dark: 0)))
        }
        check(WidgetDates.offset(of: snapshot.defaultTimetableDay(at: at(0, 13, 15)), from: wednesday) == 1,
              "un intervallo rimasto non tiene il giorno")

        // Lezione in corso e prossima (lezioni dell'esempio: 8, 9, 10, 11:10, 12:10, un'ora ciascuna).
        let morning = TimetableWidgetDay(snapshot: snapshot, now: at(0, 9, 30))
        check(morning.isToday && morning.current?.start == 9 * 60, "lezione in corso alle 9:30")
        check(morning.next?.start == 10 * 60, "prossima lezione alle 10")
        let evening = TimetableWidgetDay(snapshot: snapshot, now: at(0, 15))
        check(!evening.isToday && WidgetDates.offset(of: evening.day, from: wednesday) == 1, "la sera si mostra domani")
        check(evening.current == nil && evening.next?.start == 8 * 60, "domani dalla prima lezione")

        // Voci della linea temporale: adesso, ogni inizio e fine futuri, le mezzanotti.
        let now = at(0, 9, 30)
        let dates = BCWWidgetKind.timetable.timelineDates(snapshot: snapshot, now: now)
        check(dates.first == now, "la prima voce è adesso")
        check(Array(dates.dropFirst()) == dates.dropFirst().sorted() && dates.dropFirst().allSatisfy { $0 > now },
              "voci future e in ordine")
        for expected in [at(0, 10), at(0, 11), at(0, 13, 10), at(1, 8), at(1, 0), at(2, 0)] {
            check(dates.contains(expected), "manca la voce \(BCWShared.dayKey(expected)) \(WidgetDates.time(expected))")
        }
        check(!dates.contains(at(0, 9)), "voce passata")
        check(BCWWidgetKind.agenda.timelineDates(snapshot: snapshot, now: now) == [now, at(1, 0), at(2, 0)],
              "compiti: adesso e le mezzanotti")
        let signedOut = WidgetSnapshot(generatedAt: now, signedIn: false)
        check(BCWWidgetKind.now.timelineDates(snapshot: signedOut, now: now).count == 3, "senza account solo le mezzanotti")

        // Collegamenti.
        check(DeepLink.timetable(wednesday).url.absoluteString == "bcw://orario?giorno=2026-10-21", "collegamento all'orario")
        check(DeepLink(url: URL(string: "bcw://orario?giorno=2026-10-21")!) == .timetable(wednesday), "lettura dell'orario")
        check(DeepLink(url: URL(string: "bcw://dashboard?giorno=2026-10-26")!) == .dashboard(day(5)), "lettura della Dashboard")
        check(DeepLink(url: URL(string: "bcw://voti")!) == .grades, "lettura dei voti")
        check(DeepLink(url: URL(string: "bcw://orario")!) == .timetable(nil), "orario senza giorno")
        check(DeepLink(url: URL(string: "bcw://altro")!) == nil, "collegamento sconosciuto")
        check(DeepLink(url: URL(string: "https://bcw.example/orario")!) == nil, "schema diverso")

        // Istantanea: codifica e decodifica, e i giorni oltre quelli risolti dall'orario settimanale.
        if let data = try? JSONEncoder().encode(snapshot), let decoded = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            check(decoded == snapshot, "istantanea diversa dopo la decodifica")
        } else {
            failures.append("istantanea non codificata")
        }
        check(snapshot.events(on: day(14)) == snapshot.week[2], "giorni lontani dall'orario settimanale")
        check(WidgetSnapshot.fileURL != nil, "contenitore dell'App Group non disponibile")

        print(failures.isEmpty ? "BCW-WIDGET-SELFTEST PASS" : "BCW-WIDGET-SELFTEST FAIL\n- " + failures.joined(separator: "\n- "))
        exit(failures.isEmpty ? 0 : 1)
    }
}
#endif
