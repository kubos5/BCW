import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Colori

extension Theme {
    /// Colore di un evento dell'orario. Senza un colore scelto si usa quello della materia nella
    /// sezione Lezioni (o, senza materia collegata, uno stabile ricavato dal nome).
    static func timetableColor(_ entry: TimetableEntry, store: TimetableStore) -> Color {
        if let color = entry.color {
            switch color {
            case let .pastel(index):
                return subjectColor(index)
            case let .custom(hex):
                return timetableHex(hex)
            case let .series(paletteID, index, count):
                if let palette = store.palette(id: paletteID) {
                    if palette.id == ColorPalette.pastelID { return subjectColor(index) }
                    return timetableHex(palette.color(at: index, of: count))
                }
            }
        }
        return defaultTimetableColor(entry)
    }

    static func defaultTimetableColor(_ entry: TimetableEntry) -> Color {
        if entry.isBreak { return breakColor }
        return subjectColor(entry.subjectId ?? StableID.make(entry.matchKey))
    }

    static let breakColor = dynamic(light: 0x9A8C78, dark: 0xB8AC98)

    /// Colore scelto dall'utente: al buio si schiarisce un po', come le varianti scure dei
    /// colori delle materie, altrimenti sullo sfondo grafite i colori scuri sparirebbero.
    static func timetableHex(_ hex: Int) -> Color {
        dynamic(light: hex, dark: lightened(hex, by: 0.3))
    }

    static func lightened(_ hex: Int, by amount: Double) -> Int {
        var result = 0
        for shift in [16, 8, 0] {
            let value = Double((hex >> shift) & 0xFF)
            result |= Int((value + (255 - value) * amount).rounded()) << shift
        }
        return result
    }
}

extension Color {
    /// Valore RGB esadecimale (per salvare i colori scelti con il selettore di sistema).
    var rgbHex: Int? {
        #if os(macOS)
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #endif
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    init(hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Sfondo pastello di un evento: il colore molto attenuato sopra la superficie del tema.
struct EntryFill: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color
    var isDraft = false

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Theme.surface
                tint.opacity((colorScheme == .dark ? 0.3 : 0.2) * (isDraft ? 0.5 : 1))
            }
        }
    }
}

/// Righe diagonali per gli intervalli, che stanno sopra le lezioni.
struct DiagonalStripes: Shape {
    var spacing: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

// MARK: - Disposizione di una giornata

/// Come disporre gli eventi di un giorno: gli eventi uguali accostati formano un gruppo, quelli
/// che si sovrappongono nel tempo vanno affiancati in colonne; gli intervalli stanno a parte,
/// sopra tutto il resto, e non influiscono sulle colonne.
struct TimetableLayout {
    /// Eventi uguali (stesso nome) uno dopo l'altro, senza pause tra loro.
    struct Block: Identifiable {
        var entries: [TimetableEntry]
        var id: UUID { entries[0].id }
        var start: Int { entries[0].start }
        var end: Int { entries.last!.end }
        var isGroup: Bool { entries.count > 1 }
    }

    struct Placed: Identifiable {
        let block: Block
        let column: Int
        var id: UUID { block.id }
    }

    /// Blocchi che si sovrappongono (anche a catena): occupano lo stesso numero di colonne.
    struct Cluster: Identifiable {
        let blocks: [Placed]
        let columns: Int
        var id: UUID { blocks[0].id }
        var start: Int { blocks.map(\.block.start).min() ?? 0 }
        var end: Int { blocks.map(\.block.end).max() ?? 0 }
    }

    let clusters: [Cluster]
    let breaks: [TimetableEntry]

    /// - Parameter splitAtBreaks: per le viste Lista e Calendario, dove gli intervalli sono righe
    ///   tra gli eventi: un intervallo che tocca il passaggio tra due eventi uguali di seguito li
    ///   separa, così compare tra i due. Nella vista Giorno gli intervalli stanno sopra le lezioni
    ///   e il gruppo resta unito.
    init(entries: [TimetableEntry], splitAtBreaks: Bool = false) {
        let lessons = entries.filter { !$0.isBreak }.sorted(by: TimetableStore.order)
        let breaks = entries.filter(\.isBreak).sorted(by: TimetableStore.order)
        self.breaks = breaks
        /// Un intervallo cade sul passaggio tra due eventi che si toccano a questo minuto.
        func breakFalls(at junction: Int) -> Bool {
            splitAtBreaks && breaks.contains { $0.start <= junction && junction <= $0.end }
        }

        var blocks: [Block] = []
        for entry in lessons {
            if let index = blocks.lastIndex(where: { $0.end == entry.start && $0.entries[0].matchKey == entry.matchKey }),
               !entry.matchKey.isEmpty, !breakFalls(at: entry.start) {
                blocks[index].entries.append(entry)
            } else {
                blocks.append(Block(entries: [entry]))
            }
        }
        blocks.sort { ($0.start, -$0.end) < ($1.start, -$1.end) }

        var clusters: [Cluster] = []
        var current: [Block] = []
        var currentEnd = Int.min
        func close() {
            guard !current.isEmpty else { return }
            var columnEnds: [Int] = []
            var placed: [Placed] = []
            for block in current {
                if let column = columnEnds.firstIndex(where: { $0 <= block.start }) {
                    columnEnds[column] = block.end
                    placed.append(Placed(block: block, column: column))
                } else {
                    columnEnds.append(block.end)
                    placed.append(Placed(block: block, column: columnEnds.count - 1))
                }
            }
            clusters.append(Cluster(blocks: placed, columns: columnEnds.count))
            current = []
        }
        for block in blocks {
            if !current.isEmpty && block.start >= currentEnd { close() }
            current.append(block)
            currentEnd = current.count == 1 ? block.end : max(currentEnd, block.end)
        }
        close()
        self.clusters = clusters
    }

    /// Una riga delle viste Lista e Calendario.
    enum ListItem: Identifiable {
        case cluster(Cluster)
        case pause(TimetableEntry)
        case gap(start: Int, end: Int)

        var id: String {
            switch self {
            case let .cluster(cluster): "c-\(cluster.id)"
            case let .pause(entry): "b-\(entry.id)"
            case let .gap(start, end): "g-\(start)-\(end)"
            }
        }
    }

    /// Gruppi e intervalli in ordine di inizio, con le ore libere (almeno mezz'ora) tra le lezioni.
    /// Un intervallo che comincia insieme a un evento va prima di quello: è tra l'evento
    /// precedente e questo, come nella vista Giorno.
    var listItems: [ListItem] {
        var items: [ListItem] = []
        var pending = breaks[...]
        var lastEnd: Int?
        for cluster in clusters {
            while let pause = pending.first, pause.start <= cluster.start {
                items.append(.pause(pause))
                pending.removeFirst()
            }
            if let lastEnd, cluster.start - lastEnd >= 30 {
                items.append(.gap(start: lastEnd, end: cluster.start))
            }
            items.append(.cluster(cluster))
            lastEnd = max(lastEnd ?? cluster.end, cluster.end)
        }
        items += pending.map { .pause($0) }
        return items
    }

    /// Prima ora e ultima ora occupate.
    var span: (start: Int, end: Int)? {
        let starts = clusters.map(\.start) + breaks.map(\.start)
        let ends = clusters.map(\.end) + breaks.map(\.end)
        guard let start = starts.min(), let end = ends.max() else { return nil }
        return (start, end)
    }
}

// MARK: - Contenuto di un giorno

/// Segni da mostrare su un evento in un certo giorno.
struct EntryBadges: Equatable {
    var isTest = false
    /// La verifica viene da Classeviva (non segnata a mano).
    var isRegisterTest = false
    var hasNote = false
    var attachmentCount = 0
}

/// Tutto ciò che serve per disegnare un giorno dell'orario, calcolato una volta per aggiornamento.
struct TimetableDayContent: Equatable {
    let day: Date
    let entries: [TimetableEntry]
    let layout: TimetableLayout
    let isDraft: Bool
    /// Verifiche di Classeviva collegate agli eventi (quelle non nascoste).
    let registerTests: [UUID: [AgendaEvent]]
    /// Verifiche nascoste (a mano o dalle regole), per poterle mostrare di nuovo.
    let hiddenTests: [UUID: [AgendaEvent]]
    /// Verifiche del giorno che non corrispondono a nessuna materia dell'orario.
    let unmatchedTests: [AgendaEvent]
    let badges: [UUID: EntryBadges]

    init(day: Date, model: AppModel) {
        let store = model.timetable
        self.day = day
        entries = store.entries(on: day)
        layout = TimetableLayout(entries: entries)
        isDraft = store.draft != nil

        let tests = model.events(on: day).filter { $0.kind == .test }
        let match = Self.match(tests, to: entries)
        var visible: [UUID: [AgendaEvent]] = [:]
        var hidden: [UUID: [AgendaEvent]] = [:]
        for (id, events) in match.matched {
            let shown = events.filter { store.hiddenReason(for: $0, unmatched: false) == nil }
            let concealed = events.filter { store.hiddenReason(for: $0, unmatched: false) != nil }
            if !shown.isEmpty { visible[id] = shown }
            if !concealed.isEmpty { hidden[id] = concealed }
        }
        registerTests = visible
        hiddenTests = hidden
        unmatchedTests = match.unmatched.filter { store.hiddenReason(for: $0, unmatched: true) == nil }

        var badges: [UUID: EntryBadges] = [:]
        for entry in entries {
            let info = isDraft ? OccurrenceInfo() : store.occurrence(entry.id, on: day)
            let manual = !isDraft && store.isManualTest(entry, on: day)
            badges[entry.id] = EntryBadges(
                isTest: manual || visible[entry.id] != nil,
                isRegisterTest: visible[entry.id] != nil,
                hasNote: !entry.note.isEmpty || !info.note.isEmpty,
                attachmentCount: entry.attachments.count + info.attachments.count
            )
        }
        self.badges = badges
    }

    /// `layout` non si confronta: deriva dagli eventi.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.day == rhs.day && lhs.entries == rhs.entries && lhs.isDraft == rhs.isDraft
            && lhs.registerTests == rhs.registerTests && lhs.hiddenTests == rhs.hiddenTests
            && lhs.unmatchedTests == rhs.unmatchedTests && lhs.badges == rhs.badges
    }

    /// Collega le verifiche agli eventi della stessa materia: a quello in corso all'ora della
    /// verifica, se c'è, altrimenti al primo della giornata.
    static func match(_ tests: [AgendaEvent], to entries: [TimetableEntry])
        -> (matched: [UUID: [AgendaEvent]], unmatched: [AgendaEvent]) {
        var matched: [UUID: [AgendaEvent]] = [:]
        var unmatched: [AgendaEvent] = []
        let lessons = entries.filter { !$0.isBreak }.sorted(by: TimetableStore.order)
        for test in tests {
            let candidates = lessons.filter { subjectMatches($0, test) }
            guard let first = candidates.first else {
                unmatched.append(test)
                continue
            }
            let minute = TimeOfDay.minutes(of: test.begin)
            let timed = !test.isFullDay && minute > 0
                ? candidates.first { $0.start <= minute && minute < $0.end } : nil
            matched[(timed ?? first).id, default: []].append(test)
        }
        return (matched, unmatched)
    }

    static func subjectMatches(_ entry: TimetableEntry, _ event: AgendaEvent) -> Bool {
        if let a = entry.subjectId, let b = event.subjectId { return a == b }
        let entryName = entry.matchKey
        let eventName = TimetableEntry.normalized(event.subjectName ?? "")
        guard !entryName.isEmpty, !eventName.isEmpty else { return false }
        if entryName == eventName { return true }
        // "Inglese" e "Lingua e cultura straniera (inglese)".
        return (entryName.count >= 4 && eventName.contains(entryName))
            || (eventName.count >= 4 && entryName.contains(eventName))
    }

    /// Lezioni del giorno (i gruppi contano una volta) per l'intestazione.
    var lessonCount: Int {
        layout.clusters.reduce(0) { $0 + $1.blocks.count }
    }
}
