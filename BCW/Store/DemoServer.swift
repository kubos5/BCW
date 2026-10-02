import Foundation
import UIKit

/// Server finto che risponde come l'API di Classeviva con dati plausibili e
/// generati in modo deterministico rispetto alla data di oggi.
/// Usato dalla modalità "Prova la demo" e dalle anteprime di Xcode.
final class DemoTransport: Transport {
    /// Spostamento in anni (0 = anno corrente, -1 = anno precedente).
    let yearOffset: Int

    init(yearOffset: Int = 0) {
        self.yearOffset = yearOffset
    }

    private struct DemoSubject {
        let id: Int
        let name: String
        let teacher: String
        let topics: [String]
    }

    private let subjects: [DemoSubject] = [
        DemoSubject(id: 101, name: "ITALIANO", teacher: "BIANCHI LAURA",
                    topics: ["Dante, Inferno: canto V", "Il Dolce Stil Novo", "Analisi del testo: Petrarca",
                             "Boccaccio, Decameron", "Tipologia B: testo argomentativo"]),
        DemoSubject(id: 102, name: "LINGUA E CULTURA LATINA", teacher: "BIANCHI LAURA",
                    topics: ["Cicerone, De Officiis", "Sintassi dei casi: il genitivo", "Lucrezio, De rerum natura"]),
        DemoSubject(id: 103, name: "MATEMATICA", teacher: "ROSSI GIORGIO",
                    topics: ["Funzioni esponenziali", "Logaritmi e proprietà", "Equazioni logaritmiche",
                             "Goniometria: archi associati", "Esercitazione in vista della verifica"]),
        DemoSubject(id: 104, name: "FISICA", teacher: "ROSSI GIORGIO",
                    topics: ["Termodinamica: primo principio", "Trasformazioni adiabatiche", "Macchine termiche"]),
        DemoSubject(id: 105, name: "LINGUA E CULTURA STRANIERA (INGLESE)", teacher: "SMITH JANE",
                    topics: ["The Romantic Age", "William Wordsworth", "Past perfect continuous", "Listening practice"]),
        DemoSubject(id: 106, name: "STORIA", teacher: "VERDI ANDREA",
                    topics: ["La guerra dei Trent'anni", "L'assolutismo di Luigi XIV", "La rivoluzione inglese"]),
        DemoSubject(id: 107, name: "FILOSOFIA", teacher: "VERDI ANDREA",
                    topics: ["Cartesio: il metodo", "Spinoza", "Leibniz e le monadi"]),
        DemoSubject(id: 108, name: "SCIENZE NATURALI", teacher: "GALLI FRANCESCA",
                    topics: ["Il DNA e la replicazione", "Sintesi proteica", "Equilibrio chimico"]),
        DemoSubject(id: 109, name: "DISEGNO E STORIA DELL'ARTE", teacher: "MORETTI PAOLO",
                    topics: ["Il Rinascimento a Firenze", "Brunelleschi", "Proiezioni assonometriche"]),
        DemoSubject(id: 110, name: "SCIENZE MOTORIE E SPORTIVE", teacher: "CONTI MARCO",
                    topics: ["Pallavolo: fondamentali", "Test di resistenza", "Atletica: salto in lungo"]),
        DemoSubject(id: 111, name: "RELIGIONE CATTOLICA", teacher: "DE LUCA ANNA",
                    topics: ["Etica e responsabilità", "Il dialogo interreligioso"]),
    ]

    /// Orario settimanale (lun–ven), indici in `subjects`.
    private let timetable: [[Int]] = [
        [2, 2, 0, 4, 5, 9],
        [0, 1, 3, 7, 6, 8],
        [2, 4, 0, 0, 7, 10],
        [3, 2, 5, 6, 1, 8],
        [4, 0, 2, 7, 9, 6],
    ]

    private var calendar: Calendar { CVDate.calendar }

    private var referenceDate: Date {
        calendar.date(byAdding: .year, value: yearOffset, to: Date())!.startOfDay
    }

    private var schoolYear: (start: Date, end: Date, startYear: Int) {
        CVDate.schoolYear(containing: referenceDate)
    }

    private var firstSchoolDay: Date {
        calendar.date(from: DateComponents(year: schoolYear.startYear, month: 9, day: 14))!
    }

    private var lastSchoolDay: Date {
        calendar.date(from: DateComponents(year: schoolYear.startYear + 1, month: 6, day: 8))!
    }

    /// Per l'anno corrente i dati arrivano fino a oggi; per l'archivio, tutto l'anno.
    private var gradesUntil: Date {
        yearOffset < 0 ? lastSchoolDay : min(Date().startOfDay, lastSchoolDay)
    }

    // MARK: Routing

    func send(_ method: HTTPMethod, path: String, body: Data?, token: String?) async throws -> HTTPResult {
        try? await Task.sleep(for: .milliseconds(Int.random(in: 150...450)))

        if path == "/auth/login" {
            return json([
                "ident": "S1234567X", "firstName": "GIULIA", "lastName": "ESPOSITO",
                "token": "demo-token", "release": iso(Date()),
                "expire": iso(Date().addingTimeInterval(90 * 60)),
            ])
        }

        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[0] == "students" else { return notFound() }
        let route = Array(parts.dropFirst(2))

        switch route.first {
        case "card", "cards": return json(["card": card()])
        case "grades", "grades2", "grades2324": return json(["grades": grades()])
        case "periods": return json(["periods": periods()])
        case "subjects": return json(["subjects": subjectsJSON()])
        case "agenda":
            guard route.count >= 4, let from = parseAPIDate(route[2]), let to = parseAPIDate(route[3]) else {
                return notFound()
            }
            return json(["agenda": agenda(from: from, to: to)])
        case "lessons":
            if route.count >= 3, let from = parseAPIDate(route[1]), let to = parseAPIDate(route[2]) {
                return json(["lessons": lessons(from: from, to: to)])
            }
            return json(["lessons": lessons(from: Date().startOfDay, to: Date().startOfDay)])
        case "absences": return json(["events": absences()])
        case "noticeboard":
            if route.count >= 2, route[1] == "read" {
                // noticeboard/read/{evtCode}/{pubId}/101
                let pubId = route.count >= 4 ? (Int(route[3]) ?? 0) : 0
                return json(noticeDetail(pubId: pubId, body: body))
            }
            if route.count >= 2, route[1] == "attach" {
                return file(pdf(title: "Circolare", body: "Allegato dimostrativo della comunicazione."),
                            name: "circolare.pdf", type: "application/pdf")
            }
            return json(["items": notices()])
        case "notes":
            if route.count >= 4, route[2] == "read" {
                let id = Int(route[3]) ?? 0
                let note = notesList().first { ($0["evtId"] as? Int) == id }
                return json(["event": ["evtId": id, "evtText": note?["evtText"] ?? "", "readStatus": true] as [String: Any]])
            }
            return json(notes())
        case "didactics":
            if route.count >= 3, route[1] == "item" {
                let id = Int(route[2]) ?? 0
                if id % 10 == 2 { return json(["item": ["link": "https://it.wikipedia.org/wiki/Logaritmo"]]) }
                if id % 10 == 3 {
                    return json(["item": ["text": "Ripassare i capitoli 4 e 5 del libro di testo e svolgere gli esercizi di fine capitolo."]])
                }
                return file(pdf(title: "Dispensa", body: "Materiale didattico dimostrativo di BCW."),
                            name: "dispensa-\(id).pdf", type: "application/pdf")
            }
            return json(["didacticts": didactics()])
        case "documents":
            if route.count >= 3, route[1] == "check" { return json(["document": ["available": true]]) }
            if route.count >= 3, route[1] == "read" {
                return file(pdf(title: "Pagella", body: "Documento di valutazione dimostrativo."),
                            name: "pagella.pdf", type: "application/pdf")
            }
            return json(documents())
        case "calendar": return json(["calendar": calendarDays()])
        case "schoolbooks": return json(["schoolbooks": schoolbooks()])
        default: return notFound()
        }
    }

    // MARK: Generatori

    private func card() -> [String: Any] {
        [
            "ident": "S1234567X", "usrType": "S", "usrId": 1234567,
            "firstName": "GIULIA", "lastName": "ESPOSITO", "birthDate": "2009-03-21",
            "fiscalCode": "SPSGLI09C61F205X", "schCode": "MIPS00000", "schName": "LICEO SCIENTIFICO STATALE",
            "schDedication": "ALESSANDRO VOLTA", "schCity": "MILANO", "schProv": "MI",
            "miurSchoolCode": "MIPS00000X", "miurDivisionCode": "4B",
        ]
    }

    private func periods() -> [[String: Any]] {
        let y = schoolYear.startYear
        return [
            ["periodCode": "Q1", "periodPos": 1, "periodDesc": "TRIMESTRE", "isFinal": false,
             "dateStart": "\(y)-09-01", "dateEnd": "\(y)-12-22"],
            ["periodCode": "Q3", "periodPos": 3, "periodDesc": "PENTAMESTRE", "isFinal": true,
             "dateStart": "\(y)-12-23", "dateEnd": "\(y + 1)-06-30"],
        ]
    }

    private func subjectsJSON() -> [[String: Any]] {
        subjects.enumerated().map { index, s -> [String: Any] in
            ["id": s.id, "description": s.name, "order": index + 1,
             "teachers": [["teacherId": "T\(s.id)", "teacherName": s.teacher]]]
        }
    }

    private func schoolDays(from: Date, to: Date) -> [Date] {
        var days: [Date] = []
        var day = max(from.startOfDay, firstSchoolDay)
        let end = min(to.startOfDay, lastSchoolDay)
        while day <= end {
            if !day.isWeekend && !isHoliday(day) { days.append(day) }
            day = day.adding(days: 1)
        }
        return days
    }

    private func isHoliday(_ day: Date) -> Bool {
        let c = calendar.dateComponents([.month, .day], from: day)
        switch (c.month ?? 0, c.day ?? 0) {
        case (11, 1), (12, 8), (4, 25), (5, 1), (6, 2): return true
        case (12, 23...31), (1, 1...6): return true
        default: return false
        }
    }

    private func grades() -> [[String: Any]] {
        var rng = SeededRandom(seed: UInt64(schoolYear.startYear))
        var result: [[String: Any]] = []
        var id = 900_000
        let trimesterEnd = calendar.date(from: DateComponents(year: schoolYear.startYear, month: 12, day: 22))!
        for day in schoolDays(from: firstSchoolDay.adding(days: 3), to: gradesUntil) {
            let count = rng.next(upTo: 3) + 1
            for _ in 0..<count {
                let sIndex = timetable[(calendar.component(.weekday, from: day) + 5) % 7 % 5][rng.next(upTo: 6)]
                let s = subjects[sIndex]
                if s.id == 111 { continue }
                let base = [7.5, 6.5, 6.8, 7.0, 8.0, 7.2, 7.8, 7.4, 8.3, 8.8, 0][sIndex]
                let raw = min(10, max(3.5, base + (Double(rng.next(upTo: 9)) - 4) * 0.5))
                let value = (raw * 4).rounded() / 4
                let isOral = rng.next(upTo: 3) == 0
                let code = s.id == 110 ? "GRV2" : (isOral ? "GRV1" : "GRV0")
                let isBlue = rng.next(upTo: 18) == 0
                let isFirst = day <= trimesterEnd
                id += 1
                result.append([
                    "subjectId": s.id, "subjectCode": "", "subjectDesc": s.name, "evtId": id, "evtCode": code,
                    "evtDate": CVDate.dayKey(day), "decimalValue": value, "displayValue": display(value),
                    "displaPos": 1,
                    "notesForFamily": rng.next(upTo: 3) == 0 ? s.topics[rng.next(upTo: s.topics.count)] : "",
                    "color": isBlue ? "blue" : (value >= 6 ? "green" : "red"),
                    "canceled": false, "underlined": false,
                    "periodPos": isFirst ? 1 : 3, "periodDesc": isFirst ? "TRIMESTRE" : "PENTAMESTRE",
                    "componentPos": 1, "componentDesc": code == "GRV0" ? "Scritto" : (code == "GRV1" ? "Orale" : "Pratico"),
                    "weightFactor": 1.0, "noAverage": isBlue,
                    "teacherName": s.teacher,
                ])
            }
        }
        return result.reversed()
    }

    private func display(_ value: Double) -> String {
        let whole = Int(value)
        switch value - Double(whole) {
        case 0.25: return "\(whole)+"
        case 0.5: return "\(whole)½"
        case 0.75: return "\(whole + 1)-"
        default: return "\(whole)"
        }
    }

    private func agenda(from: Date, to: Date) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for day in schoolDays(from: from, to: to) {
            var rng = SeededRandom(seed: UInt64(day.timeIntervalSince1970 / 86_400))
            let row = timetable[(calendar.component(.weekday, from: day) + 5) % 7 % 5]
            let homeworkCount = rng.next(upTo: 3)
            for i in 0..<homeworkCount {
                let s = subjects[row[rng.next(upTo: row.count)]]
                let tasks = ["Esercizi da pag. \(rng.next(upTo: 200) + 20) n. \(rng.next(upTo: 30) + 1)–\(rng.next(upTo: 20) + 31)",
                             "Studiare: \(s.topics[rng.next(upTo: s.topics.count)])",
                             "Leggere e riassumere il capitolo \(rng.next(upTo: 12) + 1)",
                             "Ripassare gli appunti della lezione"]
                result.append(event(id: Int(day.timeIntervalSince1970 / 60) + i, code: "AGHW", day: day,
                                    hour: 8, notes: tasks[rng.next(upTo: tasks.count)], subject: s))
            }
            if rng.next(upTo: 5) == 0 {
                let s = subjects[row[rng.next(upTo: row.count)]]
                let kinds = ["Verifica scritta: \(s.topics[rng.next(upTo: s.topics.count)])",
                             "Interrogazioni programmate", "Compito in classe"]
                result.append(event(id: Int(day.timeIntervalSince1970 / 60) + 10, code: "AGNT", day: day,
                                    hour: 9 + rng.next(upTo: 3), notes: kinds[rng.next(upTo: kinds.count)], subject: s))
            }
            if rng.next(upTo: 9) == 0 {
                let events = ["Uscita didattica al Museo della Scienza", "Assemblea di classe",
                              "Incontro di orientamento universitario", "Consiglio di classe (solo docenti)"]
                result.append(event(id: Int(day.timeIntervalSince1970 / 60) + 20, code: "AGNT", day: day,
                                    hour: 11, notes: events[rng.next(upTo: events.count)], subject: nil))
            }
        }
        return result
    }

    private func event(id: Int, code: String, day: Date, hour: Int, notes: String, subject: DemoSubject?) -> [String: Any] {
        let begin = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
        var e: [String: Any] = [
            "evtId": id, "evtCode": code, "evtDatetimeBegin": iso(begin),
            "evtDatetimeEnd": iso(begin.addingTimeInterval(3600)), "isFullDay": false, "notes": notes,
            "authorName": subject?.teacher ?? "SEGRETERIA DIDATTICA", "classDesc": "4B LICEO SCIENTIFICO",
        ]
        if let subject {
            e["subjectId"] = subject.id
            e["subjectDesc"] = subject.name
        }
        return e
    }

    private func lessons(from: Date, to: Date) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for day in schoolDays(from: from, to: min(to, Date().startOfDay)) {
            var rng = SeededRandom(seed: UInt64(day.timeIntervalSince1970 / 86_400) &+ 7)
            let row = timetable[(calendar.component(.weekday, from: day) + 5) % 7 % 5]
            var hour = 1
            var index = 0
            while index < row.count {
                var duration = 1
                while index + duration < row.count && row[index + duration] == row[index] { duration += 1 }
                let s = subjects[row[index]]
                result.append([
                    "evtId": Int(day.timeIntervalSince1970 / 60) + hour, "evtDate": CVDate.dayKey(day),
                    "evtCode": "LSF0", "evtHPos": hour, "evtDuration": duration,
                    "classDesc": "4B LICEO SCIENTIFICO", "authorName": s.teacher, "subjectId": s.id,
                    "subjectCode": "", "subjectDesc": s.name,
                    "lessonType": rng.next(upTo: 4) == 0 ? "Esercitazione" : "Lezione",
                    "lessonArg": s.topics[rng.next(upTo: s.topics.count)],
                ])
                hour += duration
                index += duration
            }
        }
        return result
    }

    private func absences() -> [[String: Any]] {
        let days = schoolDays(from: firstSchoolDay, to: gradesUntil)
        guard days.count > 6 else { return [] }
        var rng = SeededRandom(seed: 42 &+ UInt64(schoolYear.startYear))
        var result: [[String: Any]] = []
        let picks = Set((0..<max(3, days.count / 12)).map { _ in rng.next(upTo: days.count) })
        for (n, index) in picks.sorted().enumerated() {
            let code = ["ABA0", "ABR0", "ABU0", "ABA0", "ABR1"][n % 5]
            let justified = index < days.count - 4 || n % 2 == 0
            let hour: Any
            switch code {
            case "ABU0": hour = 5
            case "ABA0": hour = NSNull()
            default: hour = 2
            }
            result.append([
                "evtId": 700_000 + n, "evtCode": code, "evtDate": CVDate.dayKey(days[index]),
                "evtHPos": hour,
                "evtValue": 1, "isJustified": justified,
                "justifReasonCode": justified ? "A" : "", "justifReasonDesc": justified ? "Motivi di salute" : "",
                "hoursAbsence": [],
            ])
        }
        return result
    }

    private let demoNotices: [(String, String, Bool, Bool)] = [
        ("Circ. 45 – Uscita didattica al Museo della Scienza", "Circolare", true, false),
        ("Circ. 41 – Elezioni dei rappresentanti di classe", "Circolare", false, false),
        ("Sciopero del comparto scuola", "Comunicazione", false, true),
        ("Circ. 38 – Corsi di recupero pomeridiani", "Circolare", false, false),
        ("Orario definitivo delle lezioni", "Avviso", false, false),
        ("Autorizzazione uscita anticipata", "Modulistica", true, false),
    ]

    private func notices() -> [[String: Any]] {
        demoNotices.enumerated().map { index, n -> [String: Any] in
            let date = Date().adding(days: -index * 4 - 1)
            return [
                "pubId": 5000 + index, "pubDT": iso(date), "readStatus": index > 2, "evtCode": "CF",
                "cntId": 9000 + index, "cntValidFrom": CVDate.dayKey(date),
                "cntValidTo": CVDate.dayKey(date.adding(days: 60)), "cntValidInRange": true,
                "cntStatus": "active", "cntTitle": n.0, "cntCategory": n.1, "cntHasChanged": false,
                "cntHasAttach": index % 2 == 0, "needJoin": n.2, "needReply": false, "needFile": false,
                "needSign": n.3, "evento_id": "\(index)",
                "attachments": index % 2 == 0 ? [["fileName": "circolare_\(index + 1).pdf", "attachNum": 1] as [String: Any]] : [],
            ]
        }
    }

    private func noticeDetail(pubId: Int, body: Data?) -> [String: Any] {
        let index = max(0, min(demoNotices.count - 1, pubId - 5000))
        var joined = false
        var signed = false
        if let body, let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            joined = json["join"] as? Bool ?? false
            signed = json["sign"] as? Bool ?? false
        }
        return [
            "item": ["title": demoNotices[index].0,
                     "text": "Si comunica alle famiglie e agli studenti quanto segue.\n\nLe attività si svolgeranno secondo il calendario allegato. Si raccomanda la puntualità.\n\nIl Dirigente Scolastico"],
            "reply": ["replJoin": joined, "replSign": signed, "replText": NSNull()] as [String: Any],
        ]
    }

    private func notesList() -> [[String: Any]] {
        [
            ["evtId": 801, "evtCode": "NTTE", "evtText": "Lo studente ha dimenticato il materiale di disegno.",
             "evtDate": CVDate.dayKey(Date().adding(days: -6)), "authorName": "MORETTI PAOLO", "readStatus": true],
            ["evtId": 802, "evtCode": "NTTE", "evtText": "Ottima partecipazione al dibattito in classe.",
             "evtDate": CVDate.dayKey(Date().adding(days: -11)), "authorName": "VERDI ANDREA", "readStatus": false],
            ["evtId": 803, "evtCode": "NTCL", "evtText": "Uso del cellulare durante la lezione.",
             "evtDate": CVDate.dayKey(Date().adding(days: -15)), "authorName": "ROSSI GIORGIO", "readStatus": false],
        ]
    }

    private func notes() -> [String: Any] {
        var grouped: [String: [[String: Any]]] = ["NTTE": [], "NTCL": [], "NTWN": [], "NTST": []]
        for note in notesList() {
            grouped[note["evtCode"] as? String ?? "NTTE", default: []].append(note)
        }
        return grouped
    }

    private func didactics() -> [[String: Any]] {
        let data: [(String, [(String, [String])])] = [
            ("ROSSI GIORGIO", [("Logaritmi", ["Teoria dei logaritmi.pdf", "Video spiegazione", "Compiti per le vacanze"]),
                               ("Fisica – Termodinamica", ["Formulario termodinamica.pdf", "Esercizi svolti.pdf"])]),
            ("BIANCHI LAURA", [("Dante", ["Inferno – canti scelti.pdf", "Schema canto V.pptx"]),
                               ("Uncategorized", ["Griglia di valutazione.pdf"])]),
            ("SMITH JANE", [("Romanticism", ["Wordsworth poems.pdf", "BBC documentary", "Reading list"])]),
        ]
        var contentId = 40_000
        return data.enumerated().map { tIndex, teacher -> [String: Any] in
            let parts = teacher.0.split(separator: " ")
            return [
                "teacherId": "D\(tIndex)", "teacherName": teacher.0,
                "teacherFirstName": String(parts.last ?? ""), "teacherLastName": String(parts.first ?? ""),
                "folders": teacher.1.enumerated().map { fIndex, folder -> [String: Any] in
                    [
                        "folderId": tIndex * 10 + fIndex, "folderName": folder.0,
                        "lastShareDT": iso(Date().adding(days: -(tIndex * 3 + fIndex * 5 + 1))),
                        "contents": folder.1.enumerated().map { cIndex, name -> [String: Any] in
                            contentId += 10
                            let isLink = name.contains("Video") || name.contains("BBC")
                            let isText = !name.contains(".") && !isLink
                            let id = contentId + (isLink ? 2 : (isText ? 3 : 1))
                            return ["contentId": id, "contentName": name,
                                    "objectId": id, "objectType": isLink ? "link" : (isText ? "text" : "file"),
                                    "shareDT": iso(Date().adding(days: -(tIndex * 3 + fIndex * 5 + cIndex + 1)))]
                        },
                    ]
                },
            ]
        }
    }

    private func documents() -> [String: Any] {
        var docs: [[String: Any]] = []
        if yearOffset < 0 || Date() > calendar.date(from: DateComponents(year: schoolYear.startYear + 1, month: 1, day: 20))! {
            docs.append(["hash": "demo-trimestre", "desc": "Pagella trimestre"])
        }
        if yearOffset < 0 {
            docs.append(["hash": "demo-finale", "desc": "Pagella finale"])
            docs.append(["hash": "demo-certificato", "desc": "Certificato delle competenze"])
        }
        return ["documents": docs, "schoolReports": []]
    }

    private func calendarDays() -> [[String: Any]] {
        var result: [[String: Any]] = []
        var day = schoolYear.start
        while day <= schoolYear.end {
            let status: String
            if day < firstSchoolDay || day > lastSchoolDay { status = "NW" }
            else if day.isWeekend { status = "ND" }
            else if isHoliday(day) { status = "HD" }
            else { status = "SD" }
            result.append(["dayDate": CVDate.dayKey(day),
                           "dayOfWeek": calendar.component(.weekday, from: day), "dayStatus": status])
            day = day.adding(days: 1)
        }
        return result
    }

    private func schoolbooks() -> [[String: Any]] {
        [[
            "courseId": 1, "courseDesc": "LICEO SCIENTIFICO – CLASSE 4ª",
            "books": [
                book(1, "9788808220851", "MATEMATICA.BLU 2.0", "Volume 4", "Bergamini Massimo", "Zanichelli", "MATEMATICA", 34.9, false),
                book(2, "9788808520470", "L'AMALDI PER I LICEI SCIENTIFICI", "Volume 2", "Amaldi Ugo", "Zanichelli", "FISICA", 38.5, false),
                book(3, "9788839536143", "PERFORMER HERITAGE", "Volume 1", "Spiazzi Marina", "Zanichelli", "INGLESE", 31.2, true),
                book(4, "9788822173843", "LA DIVINA COMMEDIA", nil, "Alighieri Dante", "Le Monnier", "ITALIANO", 24.0, false),
            ],
        ]]
    }

    private func book(_ id: Int, _ isbn: String, _ title: String, _ volume: String?, _ author: String,
                      _ publisher: String, _ subject: String, _ price: Double, _ toBuy: Bool) -> [String: Any] {
        ["bookId": id, "isbnCode": isbn, "title": title, "volume": volume ?? "", "author": author,
         "publisher": publisher, "subjectDesc": subject, "price": price, "toBuy": toBuy,
         "alreadyOwned": !toBuy, "alreadyInUse": !toBuy, "recommended": false]
    }

    // MARK: Utility

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = CVDate.calendar.timeZone
        return f.string(from: date)
    }

    private func parseAPIDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = CVDate.calendar.timeZone
        f.dateFormat = "yyyyMMdd"
        return f.date(from: s)
    }

    private func json(_ object: Any) -> HTTPResult {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return HTTPResult(data: data, status: 200, contentType: "application/json", fileName: nil)
    }

    private func file(_ data: Data, name: String, type: String) -> HTTPResult {
        HTTPResult(data: data, status: 200, contentType: type, fileName: name)
    }

    private func notFound() -> HTTPResult {
        HTTPResult(data: Data(#"{"statusCode":404,"message":"Non disponibile nella demo"}"#.utf8),
                   status: 404, contentType: "application/json", fileName: nil)
    }

    private func pdf(title: String, body: String) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        return renderer.pdfData { context in
            context.beginPage()
            let serif = UIFont.systemFont(ofSize: 28, weight: .bold).fontDescriptor.withDesign(.serif)
                .map { UIFont(descriptor: $0, size: 28) } ?? .boldSystemFont(ofSize: 28)
            (title as NSString).draw(at: CGPoint(x: 56, y: 72), withAttributes: [.font: serif])
            let bodyFont = UIFont.systemFont(ofSize: 14)
            (body as NSString).draw(in: CGRect(x: 56, y: 130, width: 483, height: 600),
                                    withAttributes: [.font: bodyFont])
            ("BCW · Modalità demo" as NSString).draw(at: CGPoint(x: 56, y: 790),
                                                     withAttributes: [.font: UIFont.systemFont(ofSize: 10),
                                                                      .foregroundColor: UIColor.gray])
        }
    }
}

/// Generatore pseudo-casuale con seme (SplitMix64), per dati demo stabili.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(upTo bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        return Int(nextUInt64() % UInt64(bound))
    }
}
