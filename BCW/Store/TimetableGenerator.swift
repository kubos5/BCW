import Foundation

/// Ricava una bozza dell'orario settimanale dalle lezioni registrate nei giorni passati.
///
/// Classeviva non dice a che ora inizia una lezione, ma solo in quale ora della giornata
/// (`evtHPos`) e per quante ore. Per ogni giorno della settimana e ogni ora si conta quale
/// materia compare, settimana per settimana:
/// - le settimane recenti pesano di più (dimezzano ogni 4 settimane), perché a inizio anno
///   l'orario provvisorio cambia spesso;
/// - una materia entra nell'orario se occupa quell'ora in almeno un terzo del peso delle
///   settimane osservate, così supplenze e recuperi isolati vengono ignorati;
/// - se due materie occupano stabilmente la stessa ora (es. compresenze, gruppi divisi)
///   entrano entrambe e l'orario le mostra affiancate;
/// - l'orario delle ore si ricava da inizio della prima ora e durata di un'ora.
enum TimetableGenerator {
    struct Result {
        var entries: [TimetableEntry]
        var analyzedDays: Int
    }

    /// Soglia per entrare nell'orario, in frazione del peso delle settimane osservate.
    static let threshold = 0.34
    /// Soglia per una seconda materia nella stessa ora.
    static let parallelThreshold = 0.6
    static let halfLifeWeeks = 4.0

    static func generate(from lessons: [Lesson], settings: GenerationSettings, today: Date = Date()) -> Result {
        struct SubjectKey: Hashable {
            let id: Int?
            let name: String
        }

        // Lezioni per giorno; una materia conta una volta per ora e per giorno.
        let byDay = Dictionary(grouping: lessons.filter { $0.hour > 0 }) { $0.day }
        // weekday → ora → materia → peso
        var scores: [Int: [Int: [SubjectKey: Double]]] = [:]
        // weekday → somma dei pesi dei giorni osservati
        var observed: [Int: Double] = [:]
        var names: [SubjectKey: [String: Int]] = [:]
        var teachers: [SubjectKey: [String: Int]] = [:]

        for (day, dayLessons) in byDay {
            let weekday = day.timetableWeekday
            let weeksAgo = max(0, today.startOfDay.timeIntervalSince(day)) / (7 * 86_400)
            let weight = pow(0.5, weeksAgo / halfLifeWeeks)
            observed[weekday, default: 0] += weight
            var counted = Set<String>()
            for lesson in dayLessons {
                let key = SubjectKey(id: lesson.subjectId,
                                     name: lesson.subjectId == nil ? TimetableEntry.normalized(lesson.subjectName) : "")
                names[key, default: [:]][lesson.subjectName, default: 0] += 1
                if !lesson.authorName.isEmpty { teachers[key, default: [:]][lesson.authorName, default: 0] += 1 }
                let length = max(1, Int(lesson.duration.rounded()))
                for hour in lesson.hour..<(lesson.hour + length) {
                    let mark = "\(hour)|\(key.id ?? 0)|\(key.name)"
                    guard counted.insert(mark).inserted else { continue }
                    scores[weekday, default: [:]][hour, default: [:]][key, default: 0] += weight
                }
            }
        }

        func mostCommon(_ counts: [String: Int]?) -> String {
            counts?.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? ""
        }

        var entries: [TimetableEntry] = []
        for (weekday, hours) in scores {
            guard let total = observed[weekday], total > 0 else { continue }
            for (hour, candidates) in hours {
                let ranked = candidates.sorted {
                    $0.value != $1.value ? $0.value > $1.value : mostCommon(names[$0.key]) < mostCommon(names[$1.key])
                }
                guard let best = ranked.first, best.value >= threshold * total else { continue }
                var chosen = [best.key]
                for other in ranked.dropFirst() where other.value >= parallelThreshold * total {
                    chosen.append(other.key)
                }
                let start = settings.firstHourStart + (hour - 1) * settings.hourLength
                let end = start + settings.hourLength
                guard start >= 0, end <= 24 * 60 else { continue }
                for key in chosen {
                    entries.append(TimetableEntry(weekday: weekday, start: start, end: end, kind: .lesson,
                                                  title: mostCommon(names[key]), subjectId: key.id,
                                                  teacher: mostCommon(teachers[key])))
                }
            }
        }

        // Intervalli fissi, solo nei giorni in cui c'è lezione a quell'ora.
        let lessonDays = Set(entries.map(\.weekday))
        for weekday in lessonDays.sorted() {
            let dayEntries = entries.filter { $0.weekday == weekday }
            for rule in settings.breaks where rule.duration > 0 {
                let end = min(24 * 60, rule.start + rule.duration)
                guard dayEntries.contains(where: { $0.start < end && rule.start < $0.end }) else { continue }
                entries.append(TimetableEntry(weekday: weekday, start: rule.start, end: end, kind: .breakTime,
                                              title: "Intervallo"))
            }
        }

        return Result(entries: entries.sorted { ($0.weekday, $0.start, $0.title) < ($1.weekday, $1.start, $1.title) },
                      analyzedDays: byDay.count)
    }

    /// Intervallo di date da esaminare secondo le impostazioni.
    static func range(for settings: GenerationSettings, today: Date = Date()) -> (from: Date, to: Date) {
        let schoolStart = CVDate.schoolYear(containing: today).start
        let to = today.startOfDay
        guard settings.weeks > 0 else { return (schoolStart, to) }
        return (max(schoolStart, to.adding(days: -7 * settings.weeks)), to)
    }
}
