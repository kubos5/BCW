import Foundation

struct Grade: Decodable, Identifiable, Hashable {
    let id: Int
    let subjectId: Int
    let subjectName: String
    let code: String
    let date: Date
    let value: Double?
    let displayValue: String
    let notes: String?
    let color: String
    let canceled: Bool
    let underlined: Bool
    let periodPosition: Int
    let periodName: String
    let componentName: String?
    let weight: Double?
    let noAverage: Bool
    let teacherName: String?
    let skillDescription: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        subjectId = c.int("subjectId") ?? 0
        subjectName = (c.string("subjectDesc") ?? "Materia").sentenceCased
        code = c.string("evtCode") ?? ""
        date = CVDate.parse(c.string("evtDate")) ?? .distantPast
        value = c.double("decimalValue")
        displayValue = c.string("displayValue") ?? "–"
        notes = c.string("notesForFamily")?.nilIfEmpty
        color = c.string("color") ?? ""
        canceled = c.bool("canceled")
        underlined = c.bool("underlined")
        periodPosition = c.int("periodPos") ?? 0
        periodName = (c.string("periodDesc") ?? "").sentenceCased
        componentName = c.string("componentDesc")?.nilIfEmpty?.sentenceCased
        weight = c.double("weightFactor")
        noAverage = c.bool("noAverage")
        teacherName = c.string("teacherName")?.nilIfEmpty?.nameCased
        skillDescription = c.string("skillDesc")?.nilIfEmpty
        id = c.int("evtId") ?? StableID.make(subjectName, displayValue, CVDate.dayKey(date))
    }

    /// Un voto concorre alla media se ha un valore numerico e non è annullato,
    /// "blu" (non fa media) o una prova con punteggio (GRT1, es. "35/50").
    var countsTowardAverage: Bool {
        value != nil && !canceled && !noAverage && color != "blue" && code != "GRT1"
    }

    var kind: String {
        if let componentName { return componentName }
        switch code {
        case "GRV0": return "Scritto"
        case "GRV1": return "Orale"
        case "GRV2": return "Pratico"
        case "GRT1": return "Prova"
        default: return "Voto"
        }
    }
}

struct GradesResponse: Decodable {
    let grades: [Grade]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        grades = c.array("grades")
    }
}
