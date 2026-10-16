import SwiftUI

/// Azioni sugli eventi, comuni alle tre viste dell'orario.
struct TimetableActions {
    var open: (TimetableEntry, Date) -> Void = { _, _ in }
    var edit: (TimetableEntry) -> Void = { _ in }
    var duplicate: (TimetableEntry) -> Void = { _ in }
    var delete: (TimetableEntry) -> Void = { _ in }
    var colorDay: (Int) -> Void = { _ in }
    /// Nuovo evento: giorno della settimana e minuto d'inizio.
    var create: (Int, Int?) -> Void = { _, _ in }
    var generate: () -> Void = {}
}

/// Elenco degli eventi di un giorno (viste Lista e Calendario): gli eventi uguali accostati sono
/// uniti in un gruppo, quelli contemporanei affiancati, gli intervalli in una riga a parte.
struct TimetableDayList: View {
    @Environment(AppModel.self) private var model
    let content: TimetableDayContent
    let actions: TimetableActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if showsTests && !content.unmatchedTests.isEmpty {
                unmatchedTests
            }
            if content.entries.isEmpty {
                emptyState
            } else {
                // Qui gli intervalli sono righe tra gli eventi: dividono i gruppi che attraversano.
                let items = TimetableLayout(entries: content.entries, splitAtBreaks: true).listItems
                ForEach(items) { item in
                    switch item {
                    case let .cluster(cluster): clusterView(cluster)
                    case let .pause(entry): BreakRow(entry: entry, day: content.day, isDraft: content.isDraft, actions: actions)
                    case let .gap(start, end): gapRow(start: start, end: end)
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.day.longDay)
                .font(.m3(22, weight: 500, rounded: true))
                .foregroundStyle(Theme.ink)
            if let summary {
                Text(summary)
                    .font(.m3(14))
                    .foregroundStyle(Theme.secondaryInk)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private var summary: String? {
        var parts: [String] = []
        let lessons = content.entries.filter { !$0.isBreak }.count
        if lessons > 0 { parts.append(lessons == 1 ? "1 lezione" : "\(lessons) lezioni") }
        if let span = content.layout.span { parts.append("\(TimeOfDay.string(span.start))–\(TimeOfDay.string(span.end))") }
        let tests = content.badges.values.filter(\.isTest).count + content.unmatchedTests.count
        if showsTests && tests > 0 { parts.append(tests == 1 ? "1 verifica" : "\(tests) verifiche") }
        if model.calendarStatus(on: content.day)?.isHoliday == true { parts.append("Giorno di vacanza") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func clusterView(_ cluster: TimetableLayout.Cluster) -> some View {
        if cluster.columns == 1, let placed = cluster.blocks.first {
            EntryBlockCard(block: placed.block, content: content, compact: false, actions: actions)
        } else {
            // Eventi contemporanei: uno accanto all'altro.
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<cluster.columns, id: \.self) { column in
                    VStack(spacing: 8) {
                        ForEach(cluster.blocks.filter { $0.column == column }) { placed in
                            EntryBlockCard(block: placed.block, content: content, compact: true, actions: actions)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
    }

    /// Le verifiche nella lista si vedono solo se attivate (Impostazioni o menu dell'orario).
    private var showsTests: Bool { model.preferences.timetableShowsTests }

    private func gapRow(start: Int, end: Int) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.outlineVariant).frame(height: 1)
            Text("Libero · \(TimeOfDay.duration(end - start))")
                .font(.m3(12))
                .foregroundStyle(Theme.secondaryInk)
                .fixedSize()
            Rectangle().fill(Theme.outlineVariant).frame(height: 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        let weekday = content.day.timetableWeekday
        return EmptyState("Nessuna lezione il \(Weekday.name(weekday).lowercased())",
                          icon: content.day.isWeekend ? "sun" : "calendarPlus",
                          description: model.timetable.timetable.isEmpty
                          ? "Aggiungi le materie a mano o crea una bozza dell'orario dalle lezioni registrate."
                          : "Aggiungi un evento per questo giorno della settimana.") {
            if !content.isDraft {
                Button { actions.create(weekday, nil) } label: { Label { Text("Aggiungi") } icon: { Icon("plus") } }
                    .buttonStyle(.m3(.tonal))
                if model.timetable.timetable.isEmpty {
                    Button { actions.generate() } label: { Label { Text("Genera") } icon: { Icon("wand") } }
                        .buttonStyle(.m3(.filled))
                }
            }
        }
        .card(padding: 0)
    }

    private var unmatchedTests: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Icon("alertTriangle", size: 20)
                Text("Verifiche senza lezione in orario")
                    .font(.m3(14, weight: 650))
            }
            .foregroundStyle(Theme.secondaryInk)
            ForEach(content.unmatchedTests) { test in
                RegisterTestRow(test: test, isHidden: false, unmatched: true)
                if test.id != content.unmatchedTests.last?.id { M3Divider() }
            }
        }
        .card()
    }
}

/// Per `.equatable()`: le azioni sono chiusure che cambiano a ogni aggiornamento dell'orario ma
/// fanno sempre la stessa cosa. Confrontandole, ogni cambiamento della pagina (es. il giorno
/// accanto scorrendo di lato) ricalcolava tutte le righe di tutti i giorni mostrati.
extension TimetableDayList: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.content == rhs.content }
}

/// Uno o più eventi uguali accostati: una card unica, divisa in righe.
struct EntryBlockCard: View {
    @Environment(AppModel.self) private var model
    let block: TimetableLayout.Block
    let content: TimetableDayContent
    /// Versione stretta per gli eventi affiancati.
    let compact: Bool
    let actions: TimetableActions

    private var radius: CGFloat { Theme.radii.li }

    /// Senza l'opzione "Mostra le verifiche" la lista non segna le verifiche (si vedono comunque
    /// nel dettaglio dell'evento e nella vista Giorno).
    private func badges(for entry: TimetableEntry) -> EntryBadges {
        var badges = content.badges[entry.id] ?? EntryBadges()
        if !model.preferences.timetableShowsTests { badges.isTest = false }
        return badges
    }

    var body: some View {
        let entries = block.entries
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let tint = Theme.timetableColor(entry, store: model.timetable)
                EntryRow(entry: entry, badges: badges(for: entry), compact: compact,
                         showsTitle: index == 0 || !compact, tint: tint, isDraft: content.isDraft)
                    .modifier(EntryFill(tint: tint, isDraft: content.isDraft))
                    .overlay(alignment: .top) {
                        if index > 0 {
                            // Separatore tra le ore di un gruppo.
                            Line()
                                .stroke(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(height: 1)
                                .padding(.leading, compact ? 10 : 70)
                        }
                    }
                    .contentShape(.rect)
                    .onTapGesture { actions.open(entry, content.day) }
                    .contextMenu { EntryContextMenu(entry: entry, isDraft: content.isDraft, actions: actions) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
            }
        }
        .clipShape(.rect(cornerRadius: radius, style: .continuous))
        .overlay {
            if content.isDraft {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.timetableColor(block.entries[0], store: model.timetable),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            }
        }
    }
}

/// Riga di un evento nella lista.
struct EntryRow: View {
    let entry: TimetableEntry
    let badges: EntryBadges
    let compact: Bool
    var showsTitle = true
    let tint: Color
    var isDraft = false

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 8 : 12) {
            if !compact {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(TimeOfDay.string(entry.start))
                        .font(.m3(15, weight: 650).monospacedDigit())
                        .foregroundStyle(Theme.ink)
                    Text(TimeOfDay.string(entry.end))
                        .font(.m3(12).monospacedDigit())
                        .foregroundStyle(Theme.secondaryInk)
                }
                .padding(.top, 1)
                .frame(width: 46, alignment: .trailing)
            }
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint.opacity(isDraft ? 0.6 : 1))
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                if compact {
                    Text(entry.timeRange)
                        .font(.m3(12).monospacedDigit())
                        .foregroundStyle(Theme.secondaryInk)
                }
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.displayTitle)
                        .font(.m3(compact ? 14 : 16, weight: 600))
                        .foregroundStyle(Theme.ink.opacity(showsTitle ? 1 : 0.55))
                        .lineLimit(compact ? 3 : 2)
                        .minimumScaleFactor(compact ? 0.75 : 1)
                    Spacer(minLength: 0)
                    if badges.isTest && !compact {
                        Pill(text: "Verifica", color: Theme.primary, bold: true)
                    }
                }
                if badges.isTest && compact {
                    Pill(text: "Verifica", color: Theme.primary, bold: true, small: true)
                }
                let details = [entry.teacher, entry.room].filter { !$0.isEmpty }
                if !details.isEmpty || (!compact && entry.duration != 60) {
                    Text((details + (compact || entry.duration == 60 ? [] : [TimeOfDay.duration(entry.duration)]))
                        .joined(separator: " · "))
                        .font(.m3(12))
                        .foregroundStyle(Theme.secondaryInk)
                        .lineLimit(compact ? 2 : 1)
                }
                if badges.hasNote || badges.attachmentCount > 0 {
                    HStack(spacing: 10) {
                        if badges.hasNote {
                            HStack(spacing: 3) { Icon("note", size: 14); Text("Nota") }
                        }
                        if badges.attachmentCount > 0 {
                            HStack(spacing: 3) { Icon("paperclip", size: 14); Text("\(badges.attachmentCount)") }
                        }
                    }
                    .font(.m3(12))
                    .foregroundStyle(Theme.secondaryInk)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, compact ? 10 : 12)
        .padding(.leading, compact ? 10 : 12)
        .padding(.trailing, compact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Intervallo nella lista: una riga sottile con le righe diagonali.
struct BreakRow: View {
    @Environment(AppModel.self) private var model
    let entry: TimetableEntry
    let day: Date
    let isDraft: Bool
    let actions: TimetableActions

    /// Intervallo nella lista: fa parte dello sfondo, come le ore libere, ma con l'orario e una
    /// linea ondulata più evidente ai lati.
    var body: some View {
        let tint = Theme.timetableColor(entry, store: model.timetable)
        HStack(spacing: 10) {
            wave
            HStack(spacing: 6) {
                Icon("coffeeFill", size: 18)
                    .foregroundStyle(tint)
                Text("\(entry.displayTitle) · \(entry.timeRange)")
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryInk)
            }
            .font(.m3(12))
            .fixedSize()
            wave
        }
        .opacity(isDraft ? 0.6 : 1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(.rect)
        .onTapGesture { actions.open(entry, day) }
        .contextMenu { EntryContextMenu(entry: entry, isDraft: isDraft, actions: actions) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var wave: some View {
        WavyLine()
            .stroke(Theme.secondaryInk.opacity(0.55), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            .frame(height: 6)
            .frame(maxWidth: .infinity)
    }
}

/// Linea ondulata orizzontale (separatore degli intervalli).
struct WavyLine: Shape {
    var amplitude: CGFloat = 2
    var wavelength: CGFloat = 11

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard rect.width > 0 else { return path }
        // Comincia e finisce a metà altezza, con onde intere centrate nello spazio disponibile.
        let waves = max(1, (rect.width / wavelength).rounded(.down))
        let length = waves * wavelength
        let start = rect.minX + (rect.width - length) / 2
        path.move(to: CGPoint(x: start, y: rect.midY))
        var x: CGFloat = 0
        while x < length {
            x = min(x + 1, length)
            path.addLine(to: CGPoint(x: start + x, y: rect.midY - sin(x / wavelength * 2 * .pi) * amplitude))
        }
        return path
    }
}

struct EntryContextMenu: View {
    let entry: TimetableEntry
    let isDraft: Bool
    let actions: TimetableActions

    var body: some View {
        if !isDraft {
            Button { actions.edit(entry) } label: { Label("Modifica", icon: "edit") }
            Button { actions.duplicate(entry) } label: { Label("Duplica", icon: "duplicate") }
            Button { actions.colorDay(entry.weekday) } label: { Label("Colora la giornata…", icon: "palette") }
            Divider()
            Button(role: .destructive) { actions.delete(entry) } label: { Label("Elimina", icon: "trash") }
        }
    }
}

/// Verifica di Classeviva collegata (o non collegata, `unmatched`) all'orario.
struct RegisterTestRow: View {
    @Environment(AppModel.self) private var model
    let test: AgendaEvent
    let isHidden: Bool
    var unmatched = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon("test")
                .foregroundStyle(isHidden ? Theme.secondaryInk : Theme.primary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(test.title)
                    .font(.m3(15, weight: 600))
                    .foregroundStyle(Theme.ink)
                Text(test.notes.isEmpty ? "Verifica" : test.notes)
                    .font(.m3(14))
                    .foregroundStyle(isHidden ? Theme.secondaryInk : Theme.ink)
                    .strikethrough(isHidden, color: Theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                if !test.authorName.isEmpty {
                    Text("Segnata da \(test.authorName) su Classeviva")
                        .font(.m3(12))
                        .foregroundStyle(Theme.secondaryInk)
                }
                if isHidden, let reason = model.timetable.hiddenReason(for: test, unmatched: unmatched) {
                    Text(reason.description)
                        .font(.m3(12))
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            Spacer(minLength: 4)
            Button(isHidden ? "Mostra" : "Nascondi") {
                withAnimation(Motion.spatial) { model.timetable.setTestHidden(!isHidden, test: test, unmatched: unmatched) }
            }
            .buttonStyle(.m3(.text, size: .xs))
            .help(isHidden ? "Mostra di nuovo la verifica nell'orario"
                  : "Nasconde la verifica dall'orario (resta su Classeviva)")
        }
    }
}

/// Linea orizzontale (per i separatori tratteggiati).
struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
