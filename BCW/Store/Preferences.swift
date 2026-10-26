import Foundation
import SwiftUI

enum DashboardMode: String, CaseIterable, Identifiable {
    case list, calendar
    var id: String { rawValue }
    var title: String { self == .list ? "Lista" : "Calendario" }
    var symbol: String { self == .list ? "list.bullet" : "calendar" }
    /// Icona di Material Symbols.
    var icon: String { self == .list ? "list" : "calendar" }
}

/// Vista della scheda Orario.
enum TimetableMode: String, CaseIterable, Identifiable {
    case list, calendar, day
    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: "Lista"
        case .calendar: "Calendario"
        case .day: "Giorno"
        }
    }

    /// Icona di Material Symbols.
    var icon: String {
        switch self {
        case .list: "list"
        case .calendar: "calendar"
        case .day: "dayView"
        }
    }

    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .calendar: "calendar"
        case .day: "calendar.day.timeline.left"
        }
    }

    /// Viste disponibili: la Calendario non c'è (il mese è già nella Dashboard).
    static var available: [TimetableMode] {
        [.list, .day]
    }
}

/// Quando abbreviare il titolo della Dashboard ("Giovedì 1 ottobre" → "Gio 1 ott").
enum TitleAbbreviation: String, CaseIterable, Identifiable {
    case automatic, always, never
    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatica"
        case .always: "Sempre"
        case .never: "Mai"
        }
    }
}

/// Sezioni della Dashboard che si possono comprimere.
enum DashboardSection: String, CaseIterable {
    case testsAndEvents, homework, attendance, lessons, upcoming
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Automatico"
        case .light: "Chiaro"
        case .dark: "Scuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Cosa si sincronizza con l'account BCW (Impostazioni › Account › Da sincronizzare). La scelta
/// vale solo per questo dispositivo.
enum SyncCategory: String, CaseIterable, Identifiable {
    case settings, appearance, appIcon, homework, timetable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: "Impostazioni"
        case .appearance: "Aspetto"
        case .appIcon: "Icona dell'app"
        case .homework: "Compiti fatti"
        case .timetable: "Orario"
        }
    }

    var subtitle: String {
        switch self {
        case .settings: "Voti, Dashboard e Orario"
        case .appearance: "Colori, tema chiaro o scuro, angoli, animazioni e testo"
        case .appIcon: "Colore dell'icona"
        case .homework: "Compiti segnati come fatti"
        case .timetable: "Eventi, colori, note e file di ogni account abbinato"
        }
    }

    var icon: String {
        switch self {
        case .settings: "tune"
        case .appearance: "palette"
        case .appIcon: "sparkles"
        case .homework: "checkCircle"
        case .timetable: "timetable"
        }
    }

    /// La voce di un'impostazione sincronizzata (`Preferences.syncedValues`,
    /// `ThemeStore.syncedValues`); quelle nuove o sconosciute stanno in Impostazioni.
    static func of(key: String) -> SyncCategory {
        switch key {
        case "appearance", "accentColor", "colorStyle", "contrast", "corners", "motion", "roundedText": .appearance
        case "appIconColor", "appIconAppearance", "appIconShape", "appIconDarkBackground": .appIcon
        case "completedHomework": .homework
        default: .settings
        }
    }
}

/// Impostazioni dell'app, salvate in `UserDefaults`.
@Observable
final class Preferences {
    private let defaults = UserDefaults.standard
    /// Avvisato quando cambia un'impostazione sincronizzata con l'account BCW (`CloudSync`).
    @ObservationIgnored var onSyncedChange: (() -> Void)?
    /// `true` mentre si applicano le impostazioni arrivate dal server: niente avvisi.
    @ObservationIgnored private var applyingRemote = false

    var averageMode: AverageMode { didSet { defaults.set(averageMode.rawValue, forKey: "averageMode"); syncedChanged() } }
    var weightedAverage: Bool { didSet { defaults.set(weightedAverage, forKey: "weightedAverage"); syncedChanged() } }
    var targetAverage: Double { didSet { defaults.set(targetAverage, forKey: "targetAverage"); syncedChanged() } }
    var useBiometrics: Bool { didSet { defaults.set(useBiometrics, forKey: "useBiometrics") } }
    var homeworkReminders: Bool { didSet { defaults.set(homeworkReminders, forKey: "homeworkReminders") } }
    var reminderHour: Int { didSet { defaults.set(reminderHour, forKey: "reminderHour") } }
    var dashboardMode: DashboardMode { didSet { defaults.set(dashboardMode.rawValue, forKey: "dashboardMode"); syncedChanged() } }
    /// Verifiche nella vista Lista dell'orario (spente di serie).
    var timetableShowsTests: Bool { didSet { defaults.set(timetableShowsTests, forKey: "timetableShowsTests"); syncedChanged() } }
    var timetableMode: TimetableMode { didSet { defaults.set(timetableMode.rawValue, forKey: "timetableMode"); syncedChanged() } }
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearance"); syncedChanged() } }
    var hideCompletedHomework: Bool { didSet { defaults.set(hideCompletedHomework, forKey: "hideCompletedHomework"); syncedChanged() } }
    var showUpcomingDays: Bool { didSet { defaults.set(showUpcomingDays, forKey: "showUpcomingDays"); syncedChanged() } }
    var titleAbbreviation: TitleAbbreviation {
        didSet { defaults.set(titleAbbreviation.rawValue, forKey: "titleAbbreviation"); syncedChanged() }
    }
    var collapsedSections: Set<String> {
        didSet { defaults.set(Array(collapsedSections), forKey: "collapsedSections"); syncedChanged() }
    }
    var completedHomework: Set<Int> {
        didSet { defaults.set(Array(completedHomework), forKey: "completedHomework"); syncedChanged() }
    }
    /// Attività in diretta "Orario di oggi" avviata da sola nei giorni con lezioni (solo su questo
    /// dispositivo, come le notifiche).
    var liveActivities: Bool { didSet { defaults.set(liveActivities, forKey: "liveActivities") } }
    /// Tipi di novità per cui arriva una notifica (`NewsNotifications`).
    var newsNotifications: Set<NewsKind> {
        didSet { defaults.set(newsNotifications.map(\.rawValue), forKey: "newsNotifications") }
    }
    /// Barra di avanzamento della giornata accanto al giorno in grande dell'Orario e nei widget
    /// "Orario" (Impostazioni › Orario; spenta di serie).
    var showsDayProgress: Bool {
        didSet { defaults.set(showsDayProgress, forKey: "showsDayProgress"); syncedChanged() }
    }
    /// La scheda Orario nella barra delle schede (Impostazioni › Orario). Nascosta, l'orario resta
    /// per widget e attività in diretta.
    var showsTimetableTab: Bool {
        didSet { defaults.set(showsTimetableTab, forKey: "showsTimetableTab"); syncedChanged() }
    }
    /// Voci che non si sincronizzano con l'account BCW (solo su questo dispositivo).
    private(set) var unsyncedCategories: Set<SyncCategory> {
        didSet { defaults.set(unsyncedCategories.map(\.rawValue).sorted(), forKey: "unsyncedCategories") }
    }

    init() {
        let defaults = UserDefaults.standard
        averageMode = AverageMode(rawValue: defaults.string(forKey: "averageMode") ?? "") ?? .allGrades
        weightedAverage = defaults.bool(forKey: "weightedAverage")
        let target = defaults.double(forKey: "targetAverage")
        targetAverage = target == 0 ? 7 : target
        useBiometrics = defaults.bool(forKey: "useBiometrics")
        homeworkReminders = defaults.bool(forKey: "homeworkReminders")
        let hour = defaults.integer(forKey: "reminderHour")
        reminderHour = hour == 0 ? 18 : hour
        dashboardMode = DashboardMode(rawValue: defaults.string(forKey: "dashboardMode") ?? "") ?? .list
        timetableShowsTests = defaults.bool(forKey: "timetableShowsTests")
        timetableMode = TimetableMode(rawValue: defaults.string(forKey: "timetableMode") ?? "") ?? .list
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        hideCompletedHomework = defaults.bool(forKey: "hideCompletedHomework")
        completedHomework = Set(defaults.array(forKey: "completedHomework") as? [Int] ?? [])
        showUpcomingDays = defaults.object(forKey: "showUpcomingDays") as? Bool ?? true
        titleAbbreviation = TitleAbbreviation(rawValue: defaults.string(forKey: "titleAbbreviation") ?? "") ?? .automatic
        collapsedSections = Set(defaults.stringArray(forKey: "collapsedSections") ?? [])
        newsNotifications = Set((defaults.stringArray(forKey: "newsNotifications") ?? []).compactMap(NewsKind.init(rawValue:)))
        // `bool(forKey:)` legge anche i valori passati come argomenti di avvio (`-liveActivities NO`).
        liveActivities = defaults.object(forKey: "liveActivities") == nil || defaults.bool(forKey: "liveActivities")
        showsTimetableTab = defaults.object(forKey: "showsTimetableTab") == nil || defaults.bool(forKey: "showsTimetableTab")
        showsDayProgress = defaults.bool(forKey: "showsDayProgress")
        unsyncedCategories = Set((defaults.stringArray(forKey: "unsyncedCategories") ?? []).compactMap(SyncCategory.init(rawValue:)))
    }

    /// La voce si sincronizza con l'account BCW.
    func syncs(_ category: SyncCategory) -> Bool { !unsyncedCategories.contains(category) }

    func setSyncs(_ category: SyncCategory, _ enabled: Bool) {
        if enabled { unsyncedCategories.remove(category) } else { unsyncedCategories.insert(category) }
    }

    private func syncedChanged() {
        if !applyingRemote { onSyncedChange?() }
    }

    // MARK: Sincronizzazione con l'account BCW

    /// Impostazioni che valgono su tutti i dispositivi, con gli stessi nomi della versione web.
    /// Restano sul dispositivo blocco, promemoria, notifiche e attività in diretta (vogliono un
    /// permesso ciascuno) e le voci da sincronizzare. Le voci spente le toglie `CloudSync`.
    var syncedValues: [String: JSONValue] {
        [
            "averageMode": .string(averageMode.rawValue),
            "weightedAverage": .bool(weightedAverage),
            "targetAverage": .number(targetAverage),
            "dashboardMode": .string(dashboardMode.rawValue),
            "hideCompletedHomework": .bool(hideCompletedHomework),
            "showUpcomingDays": .bool(showUpcomingDays),
            "completedHomework": .array(completedHomework.sorted().map { .number(Double($0)) }),
            "collapsedSections": .array(collapsedSections.sorted().map { .string($0) }),
            "timetableMode": .string(timetableMode.rawValue),
            "timetableShowsTests": .bool(timetableShowsTests),
            "titleAbbreviation": .string(titleAbbreviation.rawValue),
            "appearance": .string(appearance.rawValue),
            "showsTimetableTab": .bool(showsTimetableTab),
            "showsDayProgress": .bool(showsDayProgress),
        ]
    }

    /// Applica le impostazioni arrivate dall'account BCW (i valori non validi si saltano).
    func applySynced(_ values: [String: JSONValue]) {
        applyingRemote = true
        defer { applyingRemote = false }
        if let value = values["averageMode"]?.string.flatMap(AverageMode.init(rawValue:)), value != averageMode {
            averageMode = value
        }
        if let value = values["weightedAverage"]?.bool, value != weightedAverage { weightedAverage = value }
        if let value = values["targetAverage"]?.number, (1...10).contains(value), value != targetAverage {
            targetAverage = value
        }
        if let value = values["dashboardMode"]?.string.flatMap(DashboardMode.init(rawValue:)), value != dashboardMode {
            dashboardMode = value
        }
        if let value = values["hideCompletedHomework"]?.bool, value != hideCompletedHomework { hideCompletedHomework = value }
        if let value = values["showUpcomingDays"]?.bool, value != showUpcomingDays { showUpcomingDays = value }
        if let list = values["completedHomework"]?.array {
            let value = Set(list.compactMap { $0.number.flatMap { Int(exactly: $0) } })
            if value != completedHomework { completedHomework = value }
        }
        if let list = values["collapsedSections"]?.array {
            let value = Set(list.compactMap(\.string))
            if value != collapsedSections { collapsedSections = value }
        }
        if let value = values["timetableMode"]?.string.flatMap(TimetableMode.init(rawValue:)),
           TimetableMode.available.contains(value), value != timetableMode {
            timetableMode = value
        }
        if let value = values["timetableShowsTests"]?.bool, value != timetableShowsTests { timetableShowsTests = value }
        if let value = values["titleAbbreviation"]?.string.flatMap(TitleAbbreviation.init(rawValue:)), value != titleAbbreviation {
            titleAbbreviation = value
        }
        if let value = values["appearance"]?.string.flatMap(AppearanceMode.init(rawValue:)), value != appearance {
            appearance = value
        }
        if let value = values["showsTimetableTab"]?.bool, value != showsTimetableTab { showsTimetableTab = value }
        if let value = values["showsDayProgress"]?.bool, value != showsDayProgress { showsDayProgress = value }
    }

    func isCollapsed(_ section: DashboardSection) -> Bool { collapsedSections.contains(section.rawValue) }

    func toggleCollapsed(_ section: DashboardSection) {
        if collapsedSections.contains(section.rawValue) {
            collapsedSections.remove(section.rawValue)
        } else {
            collapsedSections.insert(section.rawValue)
        }
    }

    func isCompleted(_ event: AgendaEvent) -> Bool { completedHomework.contains(event.id) }

    func toggleCompleted(_ event: AgendaEvent) {
        if completedHomework.contains(event.id) {
            completedHomework.remove(event.id)
        } else {
            completedHomework.insert(event.id)
        }
    }
}
