#if DEBUG
import Foundation
import WidgetKit

/// Autotest dei widget (solo sviluppo): `-BCWWidgetSelfTest YES` prova la regola del giorno
/// predefinito dell'orario (`TimetableDefaultDay`, la stessa di app e widget), le voci della linea
/// temporale, la lezione in corso e la prossima, i collegamenti `bcw://`, la codifica
/// dell'istantanea, il contenitore dell'App Group e le fasi dell'attività in diretta. Stampa `BCW-WIDGET-SELFTEST` con l'esito ed esce.
enum WidgetSelfTest {
    /// `-BCWWidgetProbe N`: elenca i widget installati e li fa ridisegnare N volte, ogni 6 secondi,
    /// scrivendo quante linee temporali e quanti disegni ha fatto l'estensione. Per contare i crash
    /// sul telefono (i `BCWWidgets-*.ips` in `systemCrashLogs`), che sul simulatore non si vedono.
    static func probeIfRequested() {
        let rounds = UserDefaults.standard.integer(forKey: "BCWWidgetProbe")
        guard rounds > 0 else { return }
        WidgetCenter.shared.getCurrentConfigurations { result in
            switch result {
            case let .success(widgets): print("BCW-WIDGET-PROBE installati \(widgets.count): \(widgets.map { "\($0.kind)/\($0.family)" })")
            case let .failure(error): print("BCW-WIDGET-PROBE errore: \(error)")
            }
        }
        Task { @MainActor in
            for round in 1...rounds {
                WidgetCenter.shared.reloadAllTimelines()
                try? await Task.sleep(for: .seconds(6))
                print("BCW-WIDGET-PROBE giro \(round): linee temporali \(WidgetProbe.count("probeTimelines")), disegni \(WidgetProbe.count("probeRenders"))")
            }
            print("BCW-WIDGET-PROBE fine")
        }
    }

    static func runIfRequested() {
        probeIfRequested()
        guard UserDefaults.standard.bool(forKey: "BCWWidgetSelfTest") else { return }
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }

        let calendar = BCWShared.calendar
        // Mercoledì 21 ottobre 2026 (giorno della settimana 3).
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 21))!
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: wednesday)! }
        func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date { BCWShared.date(day(offset), minute: hour * 60 + minute) }
        check(BCWShared.weekday(of: wednesday) == 3, "giorno della settimana")
        // Domenica 25 ottobre 2026 si torna all'ora solare (giornata di 25 ore): le 8:00 restano le 8:00.
        check(BCWShared.minutes(of: at(4, 8)) == 8 * 60 && BCWShared.minutes(of: at(4, 14, 30)) == 14 * 60 + 30,
              "orari nel giorno del cambio dell'ora")
        check(BCWShared.date(day(4), minute: 24 * 60) == day(5), "le 24:00 sono la mezzanotte dopo")

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
        // Ore uguali di seguito: una lezione sola, come nelle righe e nell'attività in diretta.
        var doubled = snapshot
        let italian = WidgetSnapshot.Tint(light: 0x9E412B, dark: 0xFFB4A3)
        if let index = doubled.days.firstIndex(where: { $0.key == BCWShared.dayKey(wednesday) }) {
            doubled.days[index].events = [
                .init(id: "ita1", title: "Italiano", room: "2B", start: 10 * 60, end: 11 * 60, tint: italian),
                .init(id: "ita2", title: "Italiano", start: 11 * 60, end: 12 * 60, isTest: true, tint: italian),
                .init(id: "sto", title: "Storia", start: 12 * 60, end: 13 * 60, tint: .init(light: 1, dark: 2)),
            ]
        }
        let double = TimetableWidgetDay(snapshot: doubled, now: at(0, 10, 30))
        check(double.current?.id == "ita1" && double.current?.end == 12 * 60 && double.current?.isTest == true
              && double.current?.room == "2B", "due ore di seguito: in corso fino alle 12")
        check(double.next?.title == "Storia" && double.following.map(\.id) == ["sto"], "dopo due ore uguali la materia dopo")
        let beforeDouble = TimetableWidgetDay(snapshot: doubled, now: at(0, 9))
        check(beforeDouble.current == nil && beforeDouble.next?.end == 12 * 60 && beforeDouble.following.map(\.id) == ["sto"],
              "prossima lezione di due ore")

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

        // Attività in diretta: fasi della giornata dell'esempio (8, 9, 10, intervallo 11–11:10, 11:10, 12:10).
        if let plan = TimetableActivityPlan(snapshot: snapshot, day: wednesday) {
            let theme = TimetableActivityTheme(snapshot.theme)
            check(plan.lessons.count == 5 && plan.autoStart == at(0, 7, 30) && plan.end == at(0, 13, 10), "piano della giornata")
            check(plan.phases.map(\.kind) == [.before, .lesson, .lesson, .lesson, .pause, .lesson, .lesson, .finished],
                  "fasi: \(plan.phases.map(\.kind.rawValue))")
            let early = plan.content(at: at(0, 7), theme: theme)
            check(early?.state.phases.first?.kind == .before && early?.staleDate == at(0, 8), "prima dell'inizio")
            let lesson = plan.content(at: at(0, 9, 30), theme: theme)
            check(lesson?.state.phases.map(\.start) == [at(0, 9), at(0, 10), at(0, 11), at(0, 11, 10)]
                  && lesson?.staleDate == at(0, 10), "lezione in corso e successive")
            check(lesson?.state.phase(isStale: false, now: at(0, 9, 45))?.start == at(0, 9), "non scaduta: la fase in corso")
            check(lesson?.state.phase(isStale: false, now: at(0, 10, 1))?.start == at(0, 10),
                  "disegnata dopo la fine della fase ma non ancora scaduta: la fase in corso, non quella finita")
            check(lesson?.state.phase(isStale: true, now: at(0, 9, 59))?.start == at(0, 10), "scaduta: la fase successiva")
            check(lesson?.state.phase(isStale: true, now: at(0, 11, 5))?.kind == .pause,
                  "scaduta e ridisegnata più tardi: la fase in corso")
            let pause = plan.content(at: at(0, 11, 5), theme: theme)?.state.phases.first
            check(pause?.kind == .pause && pause?.title == "Intervallo" && pause?.lesson?.start == at(0, 11, 10)
                  && pause?.position == 4, "intervallo con la lezione dopo")
            let last = plan.content(at: at(0, 12, 30), theme: theme)?.state.phases
            check(last?.first?.next == nil && last?.last?.kind == .finished, "ultima lezione, poi lezioni finite")
            check(plan.content(at: at(0, 13, 10), theme: theme) == nil, "finita l'ultima lezione: niente attività")
            check(plan.nextChange(after: at(0, 9, 30)) == at(0, 9, 50) && plan.nextChange(after: at(0, 9, 50)) == at(0, 10)
                  && plan.nextChange(after: at(0, 13)) == at(0, 13, 10), "prossimo passaggio di fase o di cifre")
            // Il tempo perde delle cifre a un'ora e a 10 minuti dalla fine: lo stato cambia e l'app ridisegna l'isola.
            check(lesson?.state.timerStep == 1 && plan.content(at: at(0, 9, 55), theme: theme)?.state.timerStep == 2
                  && early?.state.timerStep == 0, "tratti del conto alla rovescia")
            check(lesson?.staleDate == plan.content(at: at(0, 9, 55), theme: theme)?.staleDate,
                  "il contenuto scade sempre alla fine della fase")
            check(plan.content(at: at(0, 9, 30), theme: theme, compactTime: true)?.state.compactTime == true,
                  "formato compatto nello stato")
            if let first = lesson?.state, let second = plan.content(at: at(0, 9, 55), theme: theme)?.state {
                check(second.differsOnlyInTimerStep(from: first) && !first.differsOnlyInTimerStep(from: early?.state ?? first),
                      "differenza del solo tratto del conto alla rovescia")
            }
            if let state = lesson?.state, let data = try? JSONEncoder().encode(state) {
                check(data.count < 4096, "stato dell'attività troppo grande: \(data.count) byte")
            }
            check(plan.nextPhaseStart(after: at(0, 9, 30)) == at(0, 10), "prossimo passaggio di fase (aggiornamento in background)")
        } else {
            failures.append("piano dell'attività mancante")
        }

        // Attività in diretta per evento: "Non mostrare" toglie l'evento dal piano, "Mostra" lo tiene anche
        // con l'avvio automatico spento (che allora segue solo quello).
        func choosing(_ choices: [Int: LiveActivityChoice]) -> WidgetSnapshot {
            var copy = snapshot
            func apply(_ events: [WidgetSnapshot.Event]) -> [WidgetSnapshot.Event] {
                events.map { event in
                    var event = event
                    if !event.isBreak, let choice = choices[event.start] { event.liveActivity = choice }
                    return event
                }
            }
            copy.days = copy.days.map { day in
                var day = day
                day.events = apply(day.events)
                return day
            }
            copy.week = copy.week.map(apply)
            return copy
        }
        let hiddenLast = TimetableActivityPlan(snapshot: choosing([12 * 60 + 10: .hide]), day: wednesday)
        check(hiddenLast?.lessons.count == 4 && hiddenLast?.end == at(0, 12, 10), "ultima lezione nascosta: finisce prima")
        let hiddenMiddle = TimetableActivityPlan(snapshot: choosing([9 * 60: .hide]), day: wednesday)
        check(hiddenMiddle?.phases.map(\.kind) == [.before, .lesson, .pause, .lesson, .pause, .lesson, .lesson, .finished],
              "lezione in mezzo nascosta: al suo posto l'attesa della successiva (\(hiddenMiddle?.phases.map(\.kind.rawValue) ?? []))")
        let onlyShown = TimetableActivityPlan(snapshot: choosing([9 * 60: .show]), day: wednesday, showsByDefault: false)
        check(onlyShown?.lessons.map(\.start) == [at(0, 9)] && onlyShown?.autoStart == at(0, 8, 30) && onlyShown?.end == at(0, 10),
              "avvio automatico spento: solo la lezione con \"Mostra\"")
        check(TimetableActivityPlan(snapshot: snapshot, day: wednesday, showsByDefault: false) == nil,
              "avvio automatico spento e nessun evento con \"Mostra\": niente attività")
        let defaults = TimetableActivityPlan(snapshot: choosing([8 * 60: .show]), day: wednesday)
        check(defaults?.lessons.count == 5, "\"Mostra\" con l'avvio automatico acceso: come prima")
        let tint = WidgetSnapshot.Tint(light: 1, dark: 2)
        let merged = TimetableActivityPlan(day: wednesday, items: [
            .init(title: "Matematica", start: at(0, 8), end: at(0, 9), tint: tint),
            .init(title: "Matematica", start: at(0, 9), end: at(0, 10), tint: tint, isTest: true),
            .init(title: "Storia", start: at(0, 9, 30), end: at(0, 11), tint: tint),
            .init(title: "Gita", start: at(0, 10), end: at(0, 10, 30), tint: tint),
        ])
        check(merged?.lessons.map(\.title) == ["Matematica", "Storia"] && merged?.lessons.first?.isTest == true
              && merged?.lessons.last?.start == at(0, 10), "ore uguali unite, sovrapposizioni tagliate")
        check(TimetableActivityPlan(day: wednesday, items: [.init(title: "Intervallo", start: at(0, 11), end: at(0, 12),
                                                                    tint: tint, isBreak: true)]) == nil,
              "senza lezioni niente piano")
        // Intervalli: al posto della lezione in corso, anche sovrapposti. Uno in mezzo a due ore
        // uguali di seguito, uno sul passaggio tra due ore uguali, uno dopo l'ultima lezione.
        let breaks = TimetableActivityPlan(day: wednesday, items: [
            .init(title: "Matematica", start: at(0, 8), end: at(0, 9), tint: tint),
            .init(title: "Matematica", start: at(0, 9), end: at(0, 10), tint: tint),
            .init(title: "Intervallo", start: at(0, 9, 30), end: at(0, 9, 40), tint: tint, isBreak: true),
            .init(title: "Storia", start: at(0, 10), end: at(0, 11), tint: tint),
            .init(title: "Storia", start: at(0, 11), end: at(0, 12), tint: tint),
            .init(title: "Ricreazione", start: at(0, 10, 55), end: at(0, 11, 5), tint: tint, isBreak: true),
            .init(title: "Dopo", start: at(0, 12), end: at(0, 12, 10), tint: tint, isBreak: true),
        ])
        if let breaks {
            let theme = TimetableActivityTheme(snapshot.theme)
            check(breaks.lessons.map(\.start) == [at(0, 8), at(0, 9, 40), at(0, 10), at(0, 11, 5)]
                  && breaks.lessons.map(\.end) == [at(0, 9, 30), at(0, 10), at(0, 10, 55), at(0, 12)],
                  "lezioni divise dagli intervalli")
            check(breaks.phases.map(\.kind) == [.before, .lesson, .pause, .lesson, .lesson, .pause, .lesson, .finished],
                  "fasi con gli intervalli: \(breaks.phases.map(\.kind.rawValue))")
            check(breaks.end == at(0, 12), "un intervallo dopo l'ultima lezione non conta")
            let before = breaks.content(at: at(0, 9, 20), theme: theme)
            check(before?.state.phases.first?.kind == .lesson && before?.staleDate == at(0, 9, 30), "lezione fino all'intervallo")
            let during = breaks.content(at: at(0, 9, 35), theme: theme)
            check(during?.state.phases.first?.kind == .pause && during?.state.phases.first?.title == "Intervallo"
                  && during?.staleDate == at(0, 9, 40) && during?.state.phases.first?.lesson?.start == at(0, 9, 40)
                  && during?.state.phases.first?.position == 2, "intervallo al posto della lezione in corso")
            check(breaks.content(at: at(0, 11), theme: theme)?.state.phases.first?.title == "Ricreazione",
                  "intervallo sul passaggio tra due ore uguali")
            check(during?.state.phases.dropFirst().first?.kind == .lesson, "dopo l'intervallo la lezione riprende")
        } else {
            failures.append("piano con gli intervalli mancante")
        }
        // Un'ora libera con un intervallo in mezzo e intervalli sovrapposti.
        let gap2 = TimetableActivityPlan(day: wednesday, items: [
            .init(title: "A", start: at(0, 8), end: at(0, 9), tint: tint),
            .init(title: "B", start: at(0, 10), end: at(0, 11), tint: tint),
            .init(title: "Intervallo", start: at(0, 9, 20), end: at(0, 9, 30), tint: tint, isBreak: true),
            .init(title: "Altro", start: at(0, 9, 25), end: at(0, 9, 35), tint: tint, isBreak: true),
        ])
        check(gap2?.phases.map(\.kind) == [.before, .lesson, .pause, .pause, .pause, .pause, .lesson, .finished]
              && gap2?.phases[2].title == nil && gap2?.phases[3].title == "Intervallo" && gap2?.phases[4].title == "Altro"
              && gap2?.phases[4].start == at(0, 9, 30) && gap2?.phases[5].title == nil, "ora libera con intervalli")
        // Un intervallo che copre l'ultima lezione e ne scavalca la fine; uno prima della prima lezione.
        let covered = TimetableActivityPlan(day: wednesday, items: [
            .init(title: "A", start: at(0, 8), end: at(0, 9), tint: tint),
            .init(title: "B", start: at(0, 9), end: at(0, 9, 10), tint: tint),
            .init(title: "Lungo", start: at(0, 9), end: at(0, 9, 20), tint: tint, isBreak: true),
            .init(title: "Presto", start: at(0, 7, 40), end: at(0, 7, 50), tint: tint, isBreak: true),
        ])
        check(covered?.lessons.count == 1 && covered?.end == at(0, 9, 20) && covered?.phases.last?.kind == .finished,
              "intervallo sopra l'ultima lezione")
        check(covered?.phases.map(\.kind) == [.before, .pause, .before, .lesson, .pause, .finished]
              && covered?.phases[0].countdownEnd == at(0, 8) && covered?.phases[0].end == at(0, 7, 40)
              && covered?.phases[4].lesson == nil, "intervallo prima della prima lezione")
        check(TimetableActivityPlan(day: wednesday, items: [
            .init(title: "A", start: at(0, 8), end: at(0, 9), tint: tint),
            .init(title: "Tutta", start: at(0, 7), end: at(0, 10), tint: tint, isBreak: true),
        ]) == nil, "lezione tutta coperta: niente piano")

        // Formati del tempo nell'isola, come li scrive iOS (il testo è negativo fino alla fine).
        func remaining(_ seconds: Double) -> Duration { .seconds(-seconds) }
        let compact = ActivityIslandTimer.compactLocale
        check(remaining(2712).formatted(ActivityIslandTimer.unitsStyle(padded: true).locale(compact)) == "-45min",
              "45min: \(remaining(2712).formatted(ActivityIslandTimer.unitsStyle(padded: true).locale(compact)))")
        check(remaining(599).formatted(ActivityIslandTimer.unitsStyle(padded: true).locale(compact)) == "-09min"
              && remaining(599).formatted(ActivityIslandTimer.unitsStyle(padded: false).locale(compact)) == "-9min", "9min")
        check(remaining(61).formatted(ActivityIslandTimer.unitsStyle(padded: false).locale(compact)) == "-1min", "1min")
        check(remaining(59).formatted(ActivityIslandTimer.unitsStyle(padded: false).locale(compact)) == "-59s", "59s")
        check(remaining(15).formatted(ActivityIslandTimer.unitsStyle(padded: true).locale(compact)) == "-15s", "15s")
        let italian2 = Locale(identifier: "it_IT")
        check(remaining(5952).formatted(ActivityIslandTimer.clock(hours: "0").locale(italian2)) == "-1:39:12"
              && remaining(3599).formatted(ActivityIslandTimer.clock(hours: "0").locale(italian2)) == "-0:59:59", "1:39:12 e 0:59:59")
        check(remaining(599).formatted(ActivityIslandTimer.minutesStyle.locale(italian2)) == "-09:59"
              && remaining(2712).formatted(ActivityIslandTimer.minutesStyle.locale(italian2)) == "-45:12", "09:59")

        // Il caso peggiore per i 4 KB di ActivityKit: nomi lunghi in ogni ora, nessuna unita.
        let long = String(repeating: "Lungo nome ", count: 6)
        let crowded = TimetableActivityPlan(day: wednesday, items: (0..<8).map { hour in
            .init(title: "\(long)\(hour)", room: long, teacher: long, start: at(0, 8 + hour), end: at(0, 8 + hour, 50),
                  tint: tint, isTest: true)
        })
        if let state = crowded?.content(at: at(0, 9, 10), theme: TimetableActivityTheme(snapshot.theme))?.state,
           let data = try? JSONEncoder().encode(state) {
            check(state.phases.count == TimetableActivityPlan.carried && data.count < 4096,
                  "stato dell'attività troppo grande con nomi lunghi: \(data.count) byte")
        } else {
            failures.append("piano con nomi lunghi mancante")
        }

        print(failures.isEmpty ? "BCW-WIDGET-SELFTEST PASS" : "BCW-WIDGET-SELFTEST FAIL\n- " + failures.joined(separator: "\n- "))
        exit(failures.isEmpty ? 0 : 1)
    }
}
#endif
