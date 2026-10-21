import Foundation

/// Orari come minuti dalla mezzanotte (comune all'app e ai widget; le funzioni legate all'ora
/// attuale dell'app sono in `Models/Timetable.swift`).
nonisolated enum TimeOfDay {
    static func string(_ minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 24 * 60)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// Durata leggibile: "1 ora", "30 min", "1 h 20 min".
    static func duration(_ minutes: Int) -> String {
        if minutes == 60 { return "1 ora" }
        if minutes % 60 == 0 { return "\(minutes / 60) ore" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    static func snapped(_ minutes: Int, step: Int) -> Int {
        Int((Double(minutes) / Double(step)).rounded()) * step
    }
}
