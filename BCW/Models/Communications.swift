import Foundation

// MARK: - Bacheca

struct NoticeAttachment: Decodable, Hashable, Identifiable {
    var id: Int { number }
    let fileName: String
    let number: Int

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        fileName = c.string("fileName") ?? "Allegato"
        number = c.int("attachNum") ?? 1
    }
}

struct Notice: Decodable, Identifiable, Hashable {
    var id: Int { pubId }
    let pubId: Int
    let publishedAt: Date?
    var isRead: Bool
    let eventCode: String
    let contentId: Int
    let validFrom: Date?
    let validTo: Date?
    let isValid: Bool
    let status: String
    let title: String
    let category: String
    let hasChanged: Bool
    let hasAttachments: Bool
    let needsJoin: Bool
    let needsReply: Bool
    let needsFile: Bool
    let needsSign: Bool
    let attachments: [NoticeAttachment]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        pubId = c.int("pubId") ?? 0
        publishedAt = CVDate.parse(c.string("pubDT"))
        isRead = c.bool("readStatus")
        eventCode = c.string("evtCode") ?? "CF"
        contentId = c.int("cntId") ?? 0
        validFrom = CVDate.parse(c.string("cntValidFrom"))
        validTo = CVDate.parse(c.string("cntValidTo"))
        isValid = c.bool("cntValidInRange")
        status = c.string("cntStatus") ?? ""
        title = (c.string("cntTitle") ?? "Comunicazione").trimmingCharacters(in: .whitespacesAndNewlines)
        category = (c.string("cntCategory") ?? "Altro").nilIfEmpty ?? "Altro"
        hasChanged = c.bool("cntHasChanged")
        hasAttachments = c.bool("cntHasAttach")
        needsJoin = c.bool("needJoin")
        needsReply = c.bool("needReply")
        needsFile = c.bool("needFile")
        needsSign = c.bool("needSign")
        attachments = c.array("attachments")
    }

    var requiresAction: Bool { needsJoin || needsSign || needsReply }
    var isDeleted: Bool { status == "deleted" }
}

struct NoticeboardResponse: Decodable {
    let items: [Notice]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        items = c.array("items")
    }
}

/// Risposta di `noticeboard/read`: testo completo e stato di adesione/firma.
struct NoticeDetail: Decodable {
    let title: String?
    let text: String?
    let joined: Bool
    let signed: Bool
    let replyText: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let item = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("item"))
        title = item?.string("title")
        text = item?.string("text")
        let reply = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("reply"))
        joined = reply?.bool("replJoin") ?? false
        signed = reply?.bool("replSign") ?? false
        replyText = reply?.string("replText")?.nilIfEmpty
    }
}

// MARK: - Note disciplinari

struct DisciplinaryNote: Identifiable, Hashable {
    let id: Int
    let category: Category
    var text: String
    let date: Date
    let authorName: String
    var isRead: Bool

    enum Category: String, CaseIterable, Identifiable {
        case annotation = "NTTE"
        case disciplinary = "NTCL"
        case warning = "NTWN"
        case sanction = "NTST"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .annotation: "Annotazioni"
            case .disciplinary: "Note disciplinari"
            case .warning: "Richiami"
            case .sanction: "Sanzioni"
            }
        }

        var singular: String {
            switch self {
            case .annotation: "Annotazione"
            case .disciplinary: "Nota disciplinare"
            case .warning: "Richiamo"
            case .sanction: "Sanzione disciplinare"
            }
        }

        var symbol: String {
            switch self {
            case .annotation: "note.text"
            case .disciplinary: "exclamationmark.bubble"
            case .warning: "hand.raised"
            case .sanction: "exclamationmark.octagon"
            }
        }
    }
}

private struct NoteDTO: Decodable {
    let id: Int
    let text: String
    let date: Date
    let author: String
    let read: Bool
    let code: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        text = c.string("evtText") ?? ""
        date = CVDate.parse(c.string("evtDate")) ?? .distantPast
        author = (c.string("authorName") ?? "").nameCased
        read = c.bool("readStatus")
        code = c.string("evtCode")
        id = c.int("evtId") ?? StableID.make(text, CVDate.dayKey(date))
    }
}

/// `notes/all` restituisce un oggetto con una lista per categoria.
struct NotesResponse: Decodable {
    let notes: [DisciplinaryNote]

    init(from decoder: Decoder) throws {
        var result: [DisciplinaryNote] = []
        if let c = try? decoder.container(keyedBy: AnyKey.self) {
            for category in DisciplinaryNote.Category.allCases {
                for dto in c.array(category.rawValue, of: NoteDTO.self) {
                    result.append(DisciplinaryNote(id: dto.id, category: category, text: dto.text,
                                                   date: dto.date, authorName: dto.author, isRead: dto.read))
                }
            }
        } else if let list = try? decoder.singleValueContainer().decode(LossyArray<NoteDTO>.self) {
            for dto in list.elements {
                let category = DisciplinaryNote.Category(rawValue: dto.code ?? "") ?? .annotation
                result.append(DisciplinaryNote(id: dto.id, category: category, text: dto.text,
                                               date: dto.date, authorName: dto.author, isRead: dto.read))
            }
        }
        notes = result.sorted { $0.date > $1.date }
    }
}

struct NoteReadResponse: Decodable {
    let text: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let event = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("event"))
        text = event?.string("evtText")
    }
}

// MARK: - Materiale didattico

struct DidacticContent: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let objectType: String
    let sharedAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.int("contentId") ?? 0
        name = (c.string("contentName") ?? "Contenuto").trimmingCharacters(in: .whitespaces)
        objectType = c.string("objectType") ?? "file"
        sharedAt = CVDate.parse(c.string("shareDT"))
    }

    enum Kind { case file, link, text }

    var kind: Kind {
        switch objectType.lowercased() {
        case "link": .link
        case "text": .text
        default: .file
        }
    }

    var symbol: String {
        switch kind {
        case .link: return "link"
        case .text: return "text.alignleft"
        case .file:
            let ext = (name as NSString).pathExtension.lowercased()
            switch ext {
            case "pdf": return "doc.richtext"
            case "jpg", "jpeg", "png", "heic", "gif": return "photo"
            case "ppt", "pptx", "key": return "rectangle.on.rectangle"
            case "xls", "xlsx", "csv", "numbers": return "tablecells"
            case "mp3", "m4a", "wav": return "waveform"
            case "mp4", "mov": return "film"
            case "zip", "rar": return "archivebox"
            default: return "doc"
            }
        }
    }
}

struct DidacticFolder: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let lastShare: Date?
    let contents: [DidacticContent]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.int("folderId") ?? 0
        let raw = (c.string("folderName") ?? "").trimmingCharacters(in: .whitespaces)
        name = raw.isEmpty || raw == "Uncategorized" ? "Senza cartella" : raw
        lastShare = CVDate.parse(c.string("lastShareDT"))
        contents = c.array("contents")
    }
}

struct DidacticTeacher: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let folders: [DidacticFolder]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let first = c.string("teacherFirstName") ?? ""
        let last = c.string("teacherLastName") ?? ""
        let full = c.string("teacherName") ?? "\(first) \(last)"
        name = full.trimmingCharacters(in: .whitespaces).nameCased
        id = c.string("teacherId") ?? String(StableID.make(full))
        folders = c.array("folders")
    }

    var lastShare: Date? { folders.compactMap(\.lastShare).max() }
}

struct DidacticsResponse: Decodable {
    let teachers: [DidacticTeacher]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        // Il campo si chiama davvero "didacticts" nell'API.
        let primary: [DidacticTeacher] = c.array("didacticts")
        teachers = primary.isEmpty ? c.array("didactics") : primary
    }
}

// MARK: - Scrutini e documenti

struct ReportDocument: Decodable, Identifiable, Hashable {
    var id: String { documentHash }
    let documentHash: String
    let title: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        documentHash = c.string("hash") ?? ""
        title = c.string("desc") ?? "Documento"
    }
}

struct SchoolReport: Decodable, Identifiable, Hashable {
    var id: String { title + (viewLink ?? "") }
    let title: String
    let viewLink: String?
    let confirmLink: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        title = c.string("desc") ?? "Pagella"
        viewLink = c.string("viewLink")?.nilIfEmpty
        confirmLink = c.string("confirmLink")?.nilIfEmpty
    }
}

struct DocumentsResponse: Decodable {
    let documents: [ReportDocument]
    let schoolReports: [SchoolReport]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        documents = c.array("documents")
        schoolReports = c.array("schoolReports")
    }
}

struct DocumentCheckResponse: Decodable {
    let available: Bool
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let doc = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("document"))
        available = doc?.bool("available") ?? false
    }
}

// MARK: - Libri di testo

struct Schoolbook: Decodable, Identifiable, Hashable {
    let id: Int
    let isbn: String
    let title: String
    let subtitle: String?
    let volume: String?
    let author: String?
    let publisher: String?
    let subject: String
    let price: Double?
    let toBuy: Bool
    let alreadyOwned: Bool
    let inUse: Bool
    let recommended: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        isbn = c.string("isbnCode") ?? ""
        title = (c.string("title") ?? "Libro").sentenceCased
        subtitle = c.string("subheading")?.nilIfEmpty ?? c.string("subtitle")?.nilIfEmpty
        volume = c.string("volume")?.nilIfEmpty
        author = c.string("author")?.nilIfEmpty?.nameCased
        publisher = c.string("publisher")?.nilIfEmpty?.nameCased
        subject = (c.string("subjectDesc") ?? "Altro").sentenceCased
        price = c.double("price")
        toBuy = c.bool("toBuy")
        alreadyOwned = c.bool("alreadyOwned")
        inUse = c.bool("alreadyInUse")
        recommended = c.bool("recommended")
        id = c.int("bookId") ?? StableID.make(isbn, title)
    }
}

struct SchoolbookCourse: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let books: [Schoolbook]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.int("courseId") ?? 0
        name = (c.string("courseDesc") ?? "Corso").sentenceCased
        books = c.array("books")
    }
}

struct SchoolbooksResponse: Decodable {
    let courses: [SchoolbookCourse]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        courses = c.array("schoolbooks")
    }
}
