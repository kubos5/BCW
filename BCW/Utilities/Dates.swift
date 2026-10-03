import Foundation

enum CVDate {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "it_IT")
        cal.timeZone = TimeZone(identifier: "Europe/Rome") ?? .current
        cal.firstWeekday = 2
        return cal
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func fixed(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }

    private static let dayOnly = fixed("yyyy-MM-dd")
    private static let localDateTime = fixed("yyyy-MM-dd'T'HH:mm:ss")
    private static let spaced = fixed("yyyy-MM-dd HH:mm:ss")
    private static let compact = fixed("yyyyMMdd")

    /// Interpreta le date restituite da Classeviva (ISO 8601, solo giorno, ecc.).
    static func parse(_ string: String?) -> Date? {
        guard let s = string?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if let d = iso.date(from: s) { return d }
        if let d = isoFractional.date(from: s) { return d }
        if let d = localDateTime.date(from: s) { return d }
        if let d = spaced.date(from: s) { return d }
        if s.count >= 10, let d = dayOnly.date(from: String(s.prefix(10))) { return d }
        return nil
    }

    /// Formato richiesto nei path delle API: `yyyyMMdd`.
    static func apiString(_ date: Date) -> String { compact.string(from: date) }

    static func dayKey(_ date: Date) -> String { dayOnly.string(from: date) }

    /// Inizio e fine dell'anno scolastico che contiene `date` (1 settembre – 31 agosto).
    static func schoolYear(containing date: Date = .now) -> (start: Date, end: Date, startYear: Int) {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 2025
        let startYear = (comps.month ?? 9) >= 9 ? year : year - 1
        let start = calendar.date(from: DateComponents(year: startYear, month: 9, day: 1))!
        let end = calendar.date(from: DateComponents(year: startYear + 1, month: 8, day: 31))!
        return (start, end, startYear)
    }
}

extension Date {
    var startOfDay: Date { CVDate.calendar.startOfDay(for: self) }

    func adding(days: Int) -> Date {
        CVDate.calendar.date(byAdding: .day, value: days, to: self) ?? self
    }

    func isSameDay(as other: Date) -> Bool {
        CVDate.calendar.isDate(self, inSameDayAs: other)
    }

    var isToday: Bool { CVDate.calendar.isDateInToday(self) }
    var isTomorrow: Bool { CVDate.calendar.isDateInTomorrow(self) }
    var isYesterday: Bool { CVDate.calendar.isDateInYesterday(self) }
    var isWeekend: Bool { CVDate.calendar.isDateInWeekend(self) }

    var startOfWeek: Date {
        CVDate.calendar.dateInterval(of: .weekOfYear, for: self)?.start ?? startOfDay
    }

    var startOfMonth: Date {
        CVDate.calendar.dateInterval(of: .month, for: self)?.start ?? startOfDay
    }

    // MARK: Formattazione in italiano

    private static let itLocale = Locale(identifier: "it_IT")

    private static var formatters: [String: DateFormatter] = [:]

    func it(_ template: String) -> String {
        if let f = Date.formatters[template] { return f.string(from: self) }
        let f = DateFormatter()
        f.locale = Date.itLocale
        f.timeZone = CVDate.calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        Date.formatters[template] = f
        return f.string(from: self)
    }

    /// "Domani", "Oggi", "Ieri" oppure "lunedì 5 ottobre".
    var relativeDayName: String {
        if isToday { return "Oggi" }
        if isTomorrow { return "Domani" }
        if isYesterday { return "Ieri" }
        return it("EEEEdMMMM").capitalizedFirst
    }

    /// Come `relativeDayName`, ma in forma breve: "Gio 1 ott".
    var relativeShortDayName: String {
        if isToday || isTomorrow || isYesterday { return relativeDayName }
        return it("EEEdMMM").replacingOccurrences(of: ".", with: "").capitalizedFirst
    }

    var longDay: String { it("EEEEdMMMM").capitalizedFirst }
    var shortDay: String { it("dMMM") }
    var shortDayWithYear: String { it("dMMMyyyy") }
    var weekdayShort: String { it("EEE").capitalizedFirst }
    var monthYear: String { it("MMMMyyyy").capitalizedFirst }
    var time: String { it("HHmm") }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }

    /// Trasforma "MATEMATICA E FISICA" in "Matematica e fisica".
    var sentenceCased: String {
        let lower = lowercased(with: Locale(identifier: "it_IT"))
        return lower.capitalizedFirst
    }

    /// Trasforma "ROSSI MARIO" in "Rossi Mario".
    var nameCased: String {
        capitalized(with: Locale(identifier: "it_IT"))
    }

    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
