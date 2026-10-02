import Foundation

struct LoginChoice: Decodable, Identifiable, Hashable {
    var id: String { ident }
    let ident: String
    let name: String
    let school: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        ident = c.string("ident") ?? ""
        name = c.string("name") ?? ""
        school = c.string("school") ?? ""
    }
}

/// Risposta di `/auth/login`. Per gli account genitore con più figli
/// Classeviva restituisce `choices` invece del token.
struct LoginResponse: Decodable {
    let ident: String?
    let firstName: String?
    let lastName: String?
    let token: String?
    let expire: Date?
    let choices: [LoginChoice]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        ident = c.string("ident")
        firstName = c.string("firstName")
        lastName = c.string("lastName")
        token = c.string("token")
        expire = CVDate.parse(c.string("expire"))
        choices = c.array("choices")
    }
}

struct Card: Decodable, Hashable {
    let ident: String
    let usrType: String
    let firstName: String
    let lastName: String
    let birthDate: Date?
    let fiscalCode: String?
    let schoolCode: String?
    let schoolName: String?
    let schoolDedication: String?
    let schoolCity: String?
    let schoolProvince: String?
    let miurSchoolCode: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        ident = c.string("ident") ?? ""
        usrType = c.string("usrType") ?? "S"
        firstName = c.string("firstName") ?? ""
        lastName = c.string("lastName") ?? ""
        birthDate = CVDate.parse(c.string("birthDate"))
        fiscalCode = c.string("fiscalCode")
        schoolCode = c.string("schCode")
        schoolName = c.string("schName")
        schoolDedication = c.string("schDedication")
        schoolCity = c.string("schCity")
        schoolProvince = c.string("schProv")
        miurSchoolCode = c.string("miurSchoolCode")
    }

    var fullName: String { "\(firstName) \(lastName)".nameCased }

    var initials: String {
        let f = firstName.first.map(String.init) ?? ""
        let l = lastName.first.map(String.init) ?? ""
        return (f + l).uppercased()
    }

    var schoolDescription: String? {
        let parts = [schoolName, schoolDedication].compactMap { $0?.nilIfEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ").nameCased
    }

    var userTypeDescription: String {
        switch usrType {
        case "G": "Genitore"
        case "S": "Studente"
        default: "Utente"
        }
    }
}

struct CardResponse: Decodable {
    let card: Card?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        card = c.object("card") ?? c.array("cards", of: Card.self).first
    }
}

struct Subject: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let order: Int
    let teachers: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.int("id") ?? 0
        name = (c.string("description") ?? "").sentenceCased
        order = c.int("order") ?? 0
        teachers = c.array("teachers", of: TeacherDTO.self).map(\.name)
    }

    private struct TeacherDTO: Decodable {
        let name: String
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            name = (c.string("teacherName") ?? "").nameCased
        }
    }
}

struct SubjectsResponse: Decodable {
    let subjects: [Subject]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        subjects = c.array("subjects")
    }
}

struct Period: Decodable, Identifiable, Hashable {
    var id: Int { position }
    let code: String
    let position: Int
    let name: String
    let label: String?
    let isFinal: Bool
    let start: Date?
    let end: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        code = c.string("periodCode") ?? ""
        position = c.int("periodPos") ?? 0
        name = (c.string("periodDesc") ?? "Periodo").sentenceCased
        label = c.string("periodLabel")
        isFinal = c.bool("isFinal")
        start = CVDate.parse(c.string("dateStart"))
        end = CVDate.parse(c.string("dateEnd"))
    }

    func contains(_ date: Date) -> Bool {
        guard let start, let end else { return false }
        return date >= start.startOfDay && date < end.adding(days: 1).startOfDay
    }
}

struct PeriodsResponse: Decodable {
    let periods: [Period]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        periods = c.array("periods")
    }
}

struct CalendarDay: Decodable, Hashable {
    let date: Date
    let status: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        date = CVDate.parse(c.string("dayDate")) ?? .distantPast
        status = c.string("dayStatus") ?? "US"
    }

    var isSchoolDay: Bool { status == "SD" }
    var isHoliday: Bool { status == "HD" || status == "NW" }
}

struct CalendarResponse: Decodable {
    let days: [CalendarDay]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        days = c.array("calendar")
    }
}
