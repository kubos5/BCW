import Foundation
import SwiftUI

enum DashboardMode: String, CaseIterable, Identifiable {
    case list, calendar
    var id: String { rawValue }
    var title: String { self == .list ? "Lista" : "Calendario" }
    var symbol: String { self == .list ? "list.bullet" : "calendar" }
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

/// Impostazioni dell'app, salvate in `UserDefaults`.
@Observable
final class Preferences {
    private let defaults = UserDefaults.standard

    var averageMode: AverageMode { didSet { defaults.set(averageMode.rawValue, forKey: "averageMode") } }
    var weightedAverage: Bool { didSet { defaults.set(weightedAverage, forKey: "weightedAverage") } }
    var targetAverage: Double { didSet { defaults.set(targetAverage, forKey: "targetAverage") } }
    var useBiometrics: Bool { didSet { defaults.set(useBiometrics, forKey: "useBiometrics") } }
    var homeworkReminders: Bool { didSet { defaults.set(homeworkReminders, forKey: "homeworkReminders") } }
    var reminderHour: Int { didSet { defaults.set(reminderHour, forKey: "reminderHour") } }
    var dashboardMode: DashboardMode { didSet { defaults.set(dashboardMode.rawValue, forKey: "dashboardMode") } }
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var hideCompletedHomework: Bool { didSet { defaults.set(hideCompletedHomework, forKey: "hideCompletedHomework") } }
    var showUpcomingDays: Bool { didSet { defaults.set(showUpcomingDays, forKey: "showUpcomingDays") } }
    var titleAbbreviation: TitleAbbreviation {
        didSet { defaults.set(titleAbbreviation.rawValue, forKey: "titleAbbreviation") }
    }
    var collapsedSections: Set<String> {
        didSet { defaults.set(Array(collapsedSections), forKey: "collapsedSections") }
    }
    var completedHomework: Set<Int> {
        didSet { defaults.set(Array(completedHomework), forKey: "completedHomework") }
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
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        hideCompletedHomework = defaults.bool(forKey: "hideCompletedHomework")
        completedHomework = Set(defaults.array(forKey: "completedHomework") as? [Int] ?? [])
        showUpcomingDays = defaults.object(forKey: "showUpcomingDays") as? Bool ?? true
        titleAbbreviation = TitleAbbreviation(rawValue: defaults.string(forKey: "titleAbbreviation") ?? "") ?? .automatic
        collapsedSections = Set(defaults.stringArray(forKey: "collapsedSections") ?? [])
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
