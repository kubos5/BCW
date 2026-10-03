import Foundation

enum AverageMode: String, CaseIterable, Identifiable {
    case allGrades
    case subjectAverages

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allGrades: "Media di tutti i voti"
        case .subjectAverages: "Media delle medie per materia"
        }
    }
}

struct SubjectSummary: Identifiable, Hashable {
    var id: Int { subjectId }
    let subjectId: Int
    let name: String
    let grades: [Grade]
    let average: Double?

    var lastGrade: Grade? { grades.max { $0.date < $1.date } }
}

/// Raccolta di voti e periodi con tutti i calcoli sulle medie.
struct GradeBook {
    let grades: [Grade]
    let periods: [Period]
    var mode: AverageMode = .allGrades
    var weighted: Bool = false

    /// Periodi che hanno almeno un voto, ordinati.
    var activePeriods: [Period] {
        let used = Set(grades.map(\.periodPosition))
        var result = periods.filter { used.contains($0.position) }.sorted { $0.position < $1.position }
        // Se l'API non restituisce i periodi, li ricaviamo dai voti stessi.
        if result.isEmpty {
            let names = Dictionary(grouping: grades, by: \.periodPosition)
            result = names.keys.sorted().compactMap { pos in
                guard let name = names[pos]?.first?.periodName else { return nil }
                return Period.synthetic(position: pos, name: name.isEmpty ? "Periodo \(pos)" : name)
            }
        }
        return result
    }

    func grades(in period: Int?) -> [Grade] {
        guard let period else { return grades }
        return grades.filter { $0.periodPosition == period }
    }

    static func average(of grades: [Grade], weighted: Bool) -> Double? {
        let valid = grades.filter(\.countsTowardAverage)
        guard !valid.isEmpty else { return nil }
        if weighted {
            var sum = 0.0
            var weights = 0.0
            for g in valid {
                let w = (g.weight ?? 1) > 0 ? (g.weight ?? 1) : 1
                sum += (g.value ?? 0) * w
                weights += w
            }
            return weights > 0 ? sum / weights : nil
        }
        return valid.compactMap(\.value).reduce(0, +) / Double(valid.count)
    }

    func average(period: Int? = nil) -> Double? {
        let selected = grades(in: period)
        switch mode {
        case .allGrades:
            return Self.average(of: selected, weighted: weighted)
        case .subjectAverages:
            let averages = subjects(in: period).compactMap(\.average)
            guard !averages.isEmpty else { return nil }
            return averages.reduce(0, +) / Double(averages.count)
        }
    }

    func subjects(in period: Int? = nil) -> [SubjectSummary] {
        let grouped = Dictionary(grouping: grades(in: period), by: \.subjectId)
        return grouped.map { id, list in
            SubjectSummary(subjectId: id, name: list.first?.subjectName ?? "Materia",
                           grades: list.sorted { $0.date > $1.date },
                           average: Self.average(of: list, weighted: weighted))
        }
        .sorted { $0.name < $1.name }
    }

    /// Andamento della media nel tempo, con un punto per giorno.
    /// Più voti nello stesso giorno producono un solo punto (la media a fine giornata):
    /// punti con la stessa data fanno impazzire l'interpolazione del grafico.
    func runningAverage(for subjectId: Int? = nil, period: Int? = nil) -> [(date: Date, value: Double)] {
        var list = grades(in: period).filter(\.countsTowardAverage)
        if let subjectId { list = list.filter { $0.subjectId == subjectId } }
        list.sort { $0.date < $1.date }
        var points: [(date: Date, value: Double)] = []
        var running: [Grade] = []
        for g in list {
            running.append(g)
            guard let avg = Self.average(of: running, weighted: weighted) else { continue }
            let day = g.date.startOfDay
            if let last = points.last, last.date == day {
                points[points.count - 1].value = avg
            } else {
                points.append((date: day, value: avg))
            }
        }
        return points
    }

    /// Voto necessario nelle prossime `count` prove per raggiungere `target`.
    static func neededGrade(target: Double, current: [Grade], count: Int = 1, weighted: Bool) -> Double? {
        let valid = current.filter(\.countsTowardAverage)
        let n = Double(count)
        if weighted {
            let sum = valid.reduce(0.0) { $0 + ($1.value ?? 0) * max($1.weight ?? 1, 0.01) }
            let weights = valid.reduce(0.0) { $0 + max($1.weight ?? 1, 0.01) }
            return (target * (weights + n) - sum) / n
        }
        let sum = valid.compactMap(\.value).reduce(0, +)
        return (target * (Double(valid.count) + n) - sum) / n
    }
}

extension Period {
    static func synthetic(position: Int, name: String) -> Period {
        let json = #"{"periodPos":\#(position),"periodDesc":"\#(name.replacingOccurrences(of: "\"", with: ""))"}"#
        return try! JSONDecoder().decode(Period.self, from: Data(json.utf8))
    }
}

enum GradeFormat {
    static func average(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "it_IT")))
    }

    static func short(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "it_IT")))
    }
}
