import Foundation
import SwiftUI
import UIKit
import WidgetKit

/// Scrive per i widget l'istantanea dei dati che mostrano (`WidgetSnapshot`, nel contenitore
/// dell'App Group) e chiede a WidgetKit di ridisegnarli.
///
/// L'istantanea si ricostruisce seguendo con l'osservazione tutto ciò che legge (orario, agenda,
/// voti, preferenze, aspetto, sessione): ogni cambiamento la fa ricostruire dopo una breve attesa,
/// così le modifiche ravvicinate (es. le sezioni di `refreshAll`) diventano una sola scrittura.
/// Durante un aggiornamento o un cambio di sessione si aspetta che finisca; si scrive e si
/// ricaricano i widget solo se il contenuto è cambiato. Anche a mezzanotte (i giorni sono
/// relativi a oggi) e tornando nell'app.
@Observable
final class WidgetExporter {
    /// L'ultima istantanea costruita (la galleria di prova la mostra).
    private(set) var current: WidgetSnapshot?

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var pending: Task<Void, Never>?
    /// L'ultima istantanea scritta su disco, per non riscrivere (e ricaricare) lo stesso contenuto.
    @ObservationIgnored private var written: WidgetSnapshot?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Attesa prima di ricostruire: unisce i cambiamenti ravvicinati.
    private static let delay: Duration = .milliseconds(700)

    func start(model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        written = WidgetSnapshot.load()
        // Il giorno cambia a mezzanotte (anche con l'app aperta) e mentre l'app è sospesa.
        for name in [UIApplication.significantTimeChangeNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.schedule() }
            })
        }
        export()
    }

    /// Ricostruisce l'istantanea dopo una breve attesa (le richieste ravvicinate si uniscono).
    func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            self?.export()
        }
    }

    /// Esegue subito un'esportazione in attesa (es. quando l'app va in secondo piano).
    func flush() {
        guard pending != nil else { return }
        export()
    }

    /// Ricostruisce l'istantanea seguendo i dati che legge e la scrive se è cambiata.
    func export() {
        pending?.cancel()
        pending = nil
        guard let model else { return }
        var snapshot: WidgetSnapshot?
        withObservationTracking {
            snapshot = Self.makeSnapshot(model: model)
        } onChange: {
            // L'esportatore vive quanto l'app (in `AppModel`): niente riferimento debole.
            Task { @MainActor in self.schedule() }
        }
        guard let snapshot else { return }
        current = snapshot
        // L'attività in diretta usa gli stessi dati (e controlla da sé se qualcosa è cambiato).
        model.liveActivities.update(snapshot: snapshot)
        if let written, written.hasSameContent(as: snapshot) { return }
        do {
            try snapshot.save()
            written = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            #if DEBUG
            print("BCW-WIDGETS impossibile scrivere l'istantanea: \(error)")
            #endif
        }
    }

    // MARK: Istantanea

    /// L'istantanea dei dati attuali; `nil` finché non è il momento di scriverla (avvio,
    /// aggiornamento o cambio di sessione in corso).
    static func makeSnapshot(model: AppModel, now: Date = Date()) -> WidgetSnapshot? {
        let theme = themeSnapshot()
        switch model.phase {
        case .launching:
            return nil
        case .signedOut:
            // Senza account i widget non mostrano più i dati di prima.
            return WidgetSnapshot(generatedAt: now, signedIn: false, theme: theme)
        case .signedIn:
            break
        }
        guard !model.isRefreshing, !model.isChangingSession else { return nil }

        let calendar = BCWShared.calendar
        let today = calendar.startOfDay(for: now)
        let store = model.timetable
        // Come nella vista Lista: le verifiche si segnano solo con "Mostra le verifiche".
        let showsTests = model.preferences.timetableShowsTests

        var days: [WidgetSnapshot.Day] = []
        for offset in 0..<WidgetSnapshot.dayCount {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            let entries = store.entries(weekday: day.timetableWeekday, includingDraft: false)
            // L'attività in diretta segna le verifiche anche senza "Mostra le verifiche".
            let tests = testIDs(entries: entries, on: day, model: model)
            days.append(WidgetSnapshot.Day(
                key: BCWShared.dayKey(day),
                events: entries.map {
                    event($0, store: store, isTest: showsTests && tests.contains($0.id), hasTest: tests.contains($0.id))
                },
                isHoliday: model.calendarStatus(on: day)?.isHoliday ?? false))
        }
        var week = (1...7).map { weekday in
            store.entries(weekday: weekday, includingDraft: false)
                .map { event($0, store: store, isTest: showsTests && $0.isWeeklyTest, hasTest: $0.isWeeklyTest) }
        }

        applyTestShift(days: &days, week: &week, now: now)

        return WidgetSnapshot(
            generatedAt: now,
            signedIn: true,
            isDemo: model.isDemo,
            accountName: model.displayName,
            lastUpdated: model.lastUpdated,
            hasTimetable: !store.timetable.entries.isEmpty,
            days: days,
            week: week,
            agenda: agenda(model: model, from: today),
            grades: grades(model: model, now: now),
            theme: theme)
    }

    /// Solo DEBUG, `-BCWWidgetNowLesson YES`: per provare i widget veri a qualsiasi ora, gli orari
    /// dell'istantanea si spostano in modo che la prima lezione di oggi sia cominciata da 20 minuti.
    private static func applyTestShift(days: inout [WidgetSnapshot.Day], week: inout [[WidgetSnapshot.Event]], now: Date) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "BCWWidgetNowLesson"),
              let first = days.first?.events.filter({ !$0.isBreak }).map(\.start).min() else { return }
        let shift = BCWShared.minutes(of: now) - 20 - first
        func shifted(_ events: [WidgetSnapshot.Event]) -> [WidgetSnapshot.Event] {
            events.compactMap { event in
                var event = event
                event.start = min(max(event.start + shift, 0), 24 * 60)
                event.end = min(max(event.end + shift, 0), 24 * 60)
                return event.end > event.start ? event : nil
            }
        }
        for index in days.indices { days[index].events = shifted(days[index].events) }
        week = week.map(shifted)
        #endif
    }

    /// Eventi del giorno con una verifica: segnata a mano o di Classeviva (non nascosta),
    /// collegata come in `TimetableDayContent`.
    private static func testIDs(entries: [TimetableEntry], on day: Date, model: AppModel) -> Set<UUID> {
        let store = model.timetable
        var ids = Set(entries.filter { store.isManualTest($0, on: day) }.map(\.id))
        let tests = model.events(on: day).filter { $0.kind == .test }
        for (id, events) in TimetableDayContent.match(tests, to: entries).matched
        where events.contains(where: { store.hiddenReason(for: $0, unmatched: false) == nil }) {
            ids.insert(id)
        }
        return ids
    }

    private static func event(_ entry: TimetableEntry, store: TimetableStore, isTest: Bool,
                              hasTest: Bool? = nil) -> WidgetSnapshot.Event {
        WidgetSnapshot.Event(id: entry.id.uuidString, title: entry.displayTitle, room: entry.room,
                             teacher: entry.teacher, start: entry.start, end: entry.end,
                             kind: entry.isBreak ? .breakTime : .lesson, isTest: isTest,
                             hasTest: hasTest == true ? true : nil,
                             tint: tint(Theme.timetableColor(entry, store: store)))
    }

    /// Compiti, verifiche ed eventi dei prossimi giorni (senza i compiti fatti, se nascosti).
    private static func agenda(model: AppModel, from today: Date) -> [WidgetSnapshot.AgendaItem] {
        guard let end = BCWShared.calendar.date(byAdding: .day, value: WidgetSnapshot.agendaDays, to: today) else { return [] }
        let preferences = model.preferences
        return model.agenda
            .filter { $0.begin >= today && $0.begin < end }
            .filter { !(preferences.hideCompletedHomework && preferences.isCompleted($0)) }
            .sorted { $0.begin < $1.begin }
            .prefix(60)
            .map { event in
                let kind: WidgetSnapshot.AgendaItem.Kind = switch event.kind {
                case .homework: .homework
                case .test: .test
                case .event: .event
                }
                return WidgetSnapshot.AgendaItem(
                    id: event.id, kind: kind, begin: event.begin, end: event.end, isFullDay: event.isFullDay,
                    title: event.title, text: event.notes, author: event.authorName,
                    isDone: event.kind == .homework && preferences.isCompleted(event),
                    tint: tint(Theme.subjectColor(event.subjectId)))
            }
    }

    /// Medie come nei Voti (stesso modo di calcolo scelto nelle Impostazioni).
    private static func grades(model: AppModel, now: Date) -> WidgetSnapshot.Grades? {
        guard !model.grades.isEmpty else { return nil }
        let book = model.gradeBook
        let periods = book.activePeriods
        // Il periodo in corso, o l'ultimo con dei voti.
        let current = periods.first { $0.contains(now) } ?? periods.last
        func average(_ period: Period) -> WidgetSnapshot.Grades.PeriodAverage {
            .init(position: period.position, name: period.name, average: book.average(period: period.position))
        }
        return WidgetSnapshot.Grades(
            average: book.average(),
            current: current.map(average),
            periods: periods.map(average),
            countingGrades: model.grades.filter(\.countsTowardAverage).count,
            insufficientSubjects: book.subjects(in: current?.position).filter { ($0.average ?? 10) < 6 }.count)
    }

    /// Ruoli del tema scelto in Impostazioni › Aspetto (più i toni degli stati).
    static func themeSnapshot() -> WidgetSnapshot.ThemeSnapshot {
        let store = ThemeStore.shared
        let tones = ThemeDefaults.toneRoles
        return WidgetSnapshot.ThemeSnapshot(
            light: store.values.light.roles.merging(tones.light) { role, _ in role },
            dark: store.values.dark.roles.merging(tones.dark) { role, _ in role },
            corners: store.corners.rawValue,
            rond: store.rond,
            rondBody: store.rondBody)
    }

    /// Un colore dinamico dell'app risolto per il tema chiaro e per quello scuro.
    static func tint(_ color: Color) -> WidgetSnapshot.Tint {
        let ui = UIColor(color)
        func rgb(_ style: UIUserInterfaceStyle) -> Int {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            ui.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
            func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
            return byte(r) << 16 | byte(g) << 8 | byte(b)
        }
        return WidgetSnapshot.Tint(light: rgb(.light), dark: rgb(.dark))
    }
}
