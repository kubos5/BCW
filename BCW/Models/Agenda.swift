import Foundation

struct AgendaEvent: Decodable, Identifiable, Hashable {
    let id: Int
    let code: String
    let begin: Date
    let end: Date
    let isFullDay: Bool
    let notes: String
    let authorName: String
    let classDescription: String?
    let subjectId: Int?
    let subjectName: String?
    let homeworkId: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        code = c.string("evtCode") ?? "AGNT"
        begin = CVDate.parse(c.string("evtDatetimeBegin")) ?? .distantPast
        end = CVDate.parse(c.string("evtDatetimeEnd")) ?? begin
        isFullDay = c.bool("isFullDay")
        notes = (c.string("notes") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        authorName = (c.string("authorName") ?? "").nameCased
        classDescription = c.string("classDesc")?.nilIfEmpty
        subjectId = c.int("subjectId")
        subjectName = c.string("subjectDesc")?.nilIfEmpty?.sentenceCased
        homeworkId = c.int("homeworkId")
        id = c.int("evtId") ?? StableID.make(code, notes, CVDate.dayKey(begin))
    }

    enum Kind: String, CaseIterable, Identifiable {
        case homework, test, event
        var id: String { rawValue }

        var title: String {
            switch self {
            case .homework: "Compiti"
            case .test: "Verifiche"
            case .event: "Eventi"
            }
        }

        var symbol: String {
            switch self {
            case .homework: "book.closed"
            case .test: "pencil.and.list.clipboard"
            case .event: "calendar"
            }
        }
    }

    /// Classeviva distingue i compiti (AGHW) dagli altri eventi (AGNT/AGCR);
    /// le verifiche non hanno un codice dedicato, quindi le riconosciamo dal testo.
    var kind: Kind {
        if code == "AGHW" { return .homework }
        let text = notes.lowercased()
        let testWords = ["verifica", "compito in classe", "interrogazion", "test ", "prova scritta",
                         "prova orale", "simulazione", "esame", "compito di", "verifiche"]
        if testWords.contains(where: { text.contains($0) }) { return .test }
        let homeworkWords = ["per casa", "esercizi", "studiare", "pag.", "pagina", "leggere", "ripassare"]
        if code == "AGNT" && subjectName != nil && homeworkWords.contains(where: { text.contains($0) }) {
            return .homework
        }
        return .event
    }

    var day: Date { begin.startOfDay }

    var title: String {
        subjectName ?? (authorName.isEmpty ? "Evento" : authorName)
    }

    var timeDescription: String {
        if isFullDay { return "Tutto il giorno" }
        if begin == end { return begin.time }
        return "\(begin.time) – \(end.time)"
    }
}

struct AgendaResponse: Decodable {
    let events: [AgendaEvent]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        events = c.array("agenda")
    }
}

struct Lesson: Decodable, Identifiable, Hashable {
    let id: Int
    let date: Date
    let code: String
    let hour: Int
    let duration: Double
    let classDescription: String?
    let authorName: String
    let subjectId: Int?
    let subjectName: String
    let type: String
    let topic: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        date = CVDate.parse(c.string("evtDate")) ?? .distantPast
        code = c.string("evtCode") ?? ""
        hour = c.int("evtHPos") ?? 0
        duration = c.double("evtDuration") ?? 1
        classDescription = c.string("classDesc")?.nilIfEmpty
        authorName = (c.string("authorName") ?? "").nameCased
        subjectId = c.int("subjectId")
        subjectName = (c.string("subjectDesc") ?? "Lezione").sentenceCased
        type = (c.string("lessonType") ?? "").sentenceCased
        topic = (c.string("lessonArg") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        id = c.int("evtId") ?? StableID.make(subjectName, String(hour), CVDate.dayKey(date))
    }

    var day: Date { date.startOfDay }

    var hoursDescription: String {
        let d = Int(duration.rounded())
        if d <= 1 { return "\(hour)ª ora" }
        return "\(hour)ª–\(hour + d - 1)ª ora"
    }
}

struct LessonsResponse: Decodable {
    let lessons: [Lesson]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        lessons = c.array("lessons")
    }
}

struct AbsenceEvent: Decodable, Identifiable, Hashable {
    let id: Int
    let code: String
    let date: Date
    let hour: Int?
    let value: Int?
    let isJustified: Bool
    let justificationReason: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        code = c.string("evtCode") ?? "ABA0"
        date = CVDate.parse(c.string("evtDate")) ?? .distantPast
        hour = c.int("evtHPos")
        value = c.int("evtValue")
        isJustified = c.bool("isJustified")
        justificationReason = c.string("justifReasonDesc")?.nilIfEmpty
        id = c.int("evtId") ?? StableID.make(code, CVDate.dayKey(date))
    }

    enum Kind: String, CaseIterable, Identifiable {
        case absence, late, shortLate, earlyExit
        var id: String { rawValue }

        var title: String {
            switch self {
            case .absence: "Assenza"
            case .late: "Ritardo"
            case .shortLate: "Ritardo breve"
            case .earlyExit: "Uscita anticipata"
            }
        }

        var pluralTitle: String {
            switch self {
            case .absence: "Assenze"
            case .late: "Ritardi"
            case .shortLate: "Ritardi brevi"
            case .earlyExit: "Uscite"
            }
        }

        var symbol: String {
            switch self {
            case .absence: "person.crop.circle.badge.xmark"
            case .late: "clock.badge.exclamationmark"
            case .shortLate: "clock"
            case .earlyExit: "figure.walk.departure"
            }
        }

        var letter: String {
            switch self {
            case .absence: "A"
            case .late: "R"
            case .shortLate: "Rb"
            case .earlyExit: "U"
            }
        }
    }

    var kind: Kind {
        switch code {
        case "ABR0": .late
        case "ABR1": .shortLate
        case "ABU0": .earlyExit
        default: .absence
        }
    }

    var day: Date { date.startOfDay }

    var detail: String {
        switch kind {
        case .absence: return "Giornata intera"
        case .late, .shortLate:
            if let hour { return "Entrata alla \(hour)ª ora" }
            return "Entrata in ritardo"
        case .earlyExit:
            if let hour { return "Uscita alla \(hour)ª ora" }
            return "Uscita anticipata"
        }
    }
}

struct AbsencesResponse: Decodable {
    let events: [AbsenceEvent]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        events = c.array("events")
    }
}
