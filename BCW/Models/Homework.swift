import Foundation

/// Un compito del modulo Compiti di Classeviva (`homeworks/index`, codice NEWDC).
///
/// I docenti ora possono assegnare i compiti come compiti veri e propri, non più solo come annotazioni
/// dell'agenda: questi non compaiono in `agenda/all` e arrivano solo da `homeworks/index` (issue 16 su
/// GitHub; formato da https://github.com/open-viva/endpoints#compiti). In BCW diventano eventi
/// dell'agenda di tipo compito (`AgendaEvent(homework:)`), così compaiono ovunque ci siano i compiti:
/// Dashboard, Agenda, ricerca, promemoria, notifiche e widget.
struct Homework: Decodable, Hashable {
    let id: Int
    let text: String
    let teacherName: String
    let subjectId: Int?
    let subjectName: String?
    let assignedOn: Date?
    /// Giorno di consegna (con l'ora, se il docente l'ha indicata).
    let due: Date
    let hasDueTime: Bool
    /// Segnato come fatto su Classeviva (`homeworkMarkedDone`) o chiuso (`homeworkDone`).
    let isDone: Bool
    /// File e link del docente: BCW non li apre, sono sul sito di Classeviva.
    let attachments: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let day = CVDate.parse(c.string("expiryDate")) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Compito senza data di consegna"))
        }
        text = (c.string("homeworkDesc") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        teacherName = (c.string("teacherName") ?? "").nameCased
        subjectId = c.int("subjectId")
        subjectName = c.string("subjectDesc")?.nilIfEmpty?.sentenceCased
        assignedOn = CVDate.parse(c.string("assignmentDate"))
        if let time = Self.minutes(c.string("expiryTime")) {
            due = day.startOfDay.addingTimeInterval(TimeInterval(time * 60))
            hasDueTime = true
        } else {
            due = day.startOfDay
            hasDueTime = false
        }
        isDone = c.bool("homeworkMarkedDone") || c.bool("homeworkDone")
        attachments = c.array("teacherFiles", of: Anything.self).count + c.array("teacherLinks", of: Anything.self).count
        id = c.int("evtId") ?? StableID.make("NEWDC", text, CVDate.dayKey(day))
    }

    /// "14:30" o "14:30:00" → minuti dalla mezzanotte.
    private static func minutes(_ string: String?) -> Int? {
        guard let parts = string?.split(separator: ":"), parts.count >= 2,
              let hours = Int(parts[0]), let minutes = Int(parts[1]),
              (0..<24).contains(hours), (0..<60).contains(minutes) else { return nil }
        return hours * 60 + minutes
    }

    /// Consuma un valore qualsiasi: serve solo a contare gli elementi di un array.
    private struct Anything: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

struct HomeworksResponse: Decodable {
    let items: [Homework]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let items: [Homework] = c.array("items")
        self.items = items.isEmpty ? c.array("homeworks") : items
    }

    /// Una risposta di `homeworks/index`: un oggetto con l'elenco dei compiti, anche vuoto. Distingue
    /// i compiti da una risposta qualsiasi (una pagina di errore, un JSON d'altro tipo).
    static func isValid(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["items"] is [Any] || object["homeworks"] is [Any]
    }
}

extension AgendaEvent {
    /// Codice degli eventi che vengono dal modulo Compiti.
    static let homeworkModuleCode = "NEWDC"

    /// Id in BCW di un compito del modulo Compiti: il suo id con il segno meno, perché gli id dei
    /// compiti e quelli degli eventi dell'agenda sono numerati a parte e potrebbero coincidere (i compiti
    /// fatti, sincronizzati con l'account BCW, sono un elenco di id).
    static func homeworkEventID(_ id: Int) -> Int { -abs(id) }

    var isFromHomeworkModule: Bool { code == Self.homeworkModuleCode }
}
