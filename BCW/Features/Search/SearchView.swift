import SwiftUI

/// Ricerca globale su compiti, voti, comunicazioni, materiale e note.
struct SearchView: View {
    static let prompt = "Compiti, voti, altro…"

    @Environment(AppModel.self) private var model
    /// Testo cercato (appartiene a chi mostra la pagina).
    @Binding var query: String
    /// Aperta dalla barra di ricerca della Dashboard (senza Liquid Glass): sta nella pila della
    /// Dashboard e il campo è nella barra in alto.
    var embedded = false

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    @FocusState private var fieldFocused: Bool
    @Environment(\.windowClass) private var windowClass

    /// Risultati della ricerca, calcolati una volta per aggiornamento (a ogni lettera digitata):
    /// prima ogni elenco veniva rifiltrato e riordinato più volte, anche una per ogni riga.
    private struct Results {
        let agenda: [AgendaEvent]
        let grades: [Grade]
        let notices: [Notice]
        let notes: [DisciplinaryNote]
        let files: [(DidacticTeacher, DidacticContent)]

        var isEmpty: Bool {
            agenda.isEmpty && grades.isEmpty && notices.isEmpty && notes.isEmpty && files.isEmpty
        }

        init(model: AppModel, query trimmed: String) {
            let now = Date()
            agenda = model.agenda.filter { $0.notes.localizedCaseInsensitiveContains(trimmed)
                || ($0.subjectName ?? "").localizedCaseInsensitiveContains(trimmed) }
                .sorted { abs($0.begin.timeIntervalSince(now)) < abs($1.begin.timeIntervalSince(now)) }
            grades = model.grades.filter { $0.subjectName.localizedCaseInsensitiveContains(trimmed)
                || ($0.notes ?? "").localizedCaseInsensitiveContains(trimmed) }
            notices = model.notices.filter { $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.category.localizedCaseInsensitiveContains(trimmed) }
            notes = model.notes.filter { $0.text.localizedCaseInsensitiveContains(trimmed)
                || $0.authorName.localizedCaseInsensitiveContains(trimmed) }
            files = model.didactics.flatMap { teacher in
                teacher.folders.flatMap(\.contents)
                    .filter { $0.name.localizedCaseInsensitiveContains(trimmed) || teacher.name.localizedCaseInsensitiveContains(trimmed) }
                    .map { (teacher, $0) }
            }
        }
    }

    var body: some View {
        if embedded {
            page
        } else {
            PlatformNavigationStack { page }
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Sull'iPad largo il campo è nella barra superiore della finestra.
                if !ThemeStore.shared.liquidGlass && !embedded && windowClass == .compact {
                    PageLargeTitle()
                        .padding(.bottom, -4)
                    M3SearchBar(text: $query, prompt: Self.prompt, focus: $fieldFocused)
                        .padding(.bottom, 4)
                }
                if trimmed.isEmpty {
                    suggestions
                } else {
                    let results = Results(model: model, query: trimmed)
                    if results.isEmpty {
                        EmptyState("Nessun risultato per \"\(trimmed)\"", icon: "search",
                                   description: "Controlla l'ortografia o prova con un'altra ricerca.")
                    } else if windowClass == .regular {
                        // Sull'iPad largo i gruppi di risultati stanno in colonne (come la versione web).
                        AdaptiveColumns(minimum: 360, spacing: 20) { resultGroups(results) }
                    } else {
                        resultGroups(results)
                    }
                }
            }
            .pagePadding()
            .padding(.top, embedded ? 4 : 0)
            .padding(.bottom, 32)
            // Sull'iPad largo i suggerimenti sono più stretti della pagina: senza, l'intera pagina si
            // stringeva attorno a loro e ai lati restava lo sfondo bianco di sistema (verificato).
            .frame(maxWidth: windowClass == .regular ? .infinity : nil, alignment: .leading)
            .animation(Motion.spatial, value: trimmed.isEmpty)
        }
        .tracksPageScroll()
        .scrollDismissesKeyboard(.immediately)
        .themedBackground()
        .modifier(SearchChrome(query: $query, embedded: embedded, focus: $fieldFocused))
        .task { if model.didactics.isEmpty { await model.loadDidactics() } }
    }

    /// Prima di scrivere: scorciatoie per tipo e suggerimenti dalle materie.
    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                ListHeader("Cerca per tipo")
                FlowLayout(spacing: 8) {
                    ForEach([("Verifica", "test"), ("Interrogazione", "person"), ("Compiti", "book"),
                             ("Comunicazione", "megaphone")], id: \.0) { item in
                        Button {
                            query = item.0
                            fieldFocused = true
                        } label: {
                            Label { Text(item.0) } icon: { Icon(item.1, size: 18) }
                                .labelStyle(M3ButtonLabelStyle(iconSize: 18))
                                .font(.m3(14, weight: 600))
                                .padding(.leading, 12)
                                .padding(.trailing, 16)
                                .frame(height: 40)
                        }
                        .buttonStyle(.m3(.tonal, size: .s))
                    }
                }
                .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                ListHeader("Materie")
                FlowChips(items: Array(Set(model.grades.map(\.subjectName))).sorted().prefix(10).map { $0 }) {
                    query = $0
                    fieldFocused = true
                }
                .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private func resultGroups(_ results: Results) -> some View {
        let agenda = results.agenda
        let grades = results.grades
        let notices = results.notices
        let notes = results.notes
        let files = results.files
        if !agenda.isEmpty {
            ListGroup(header(for: "Agenda", count: agenda.count)) {
                ForEach(agenda.prefix(15)) { event in
                    SegmentCell {
                        AgendaEventRow(event: event, showsDate: true)
                    }
                }
            }
        }
        if !grades.isEmpty {
            ListGroup(header(for: "Voti", count: grades.count)) {
                ForEach(grades.prefix(15)) { grade in
                    HStack(spacing: 14) {
                        GradeBadge(grade: grade, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            SubjectTag(name: grade.subjectName, id: grade.subjectId)
                            Text("\(grade.kind) · \(grade.date.shortDay)\(grade.notes.map { " · \($0)" } ?? "")")
                                .font(.m3(13))
                                .foregroundStyle(Theme.secondaryInk)
                                .lineLimit(2)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        if !notices.isEmpty {
            ListGroup(header(for: "Bacheca", count: notices.count)) {
                ForEach(notices.prefix(10)) { notice in
                    NavigationLink {
                        NoticeDetailView(notice: notice)
                            .pageChrome("", style: .inline)
                    } label: {
                        NavigationRow(notice.title, subtitle: notice.category, icon: "megaphone", tint: Theme.primary)
                    }
                    .buttonStyle(.listRow)
                }
            }
        }
        if !files.isEmpty {
            ListGroup(header(for: "Materiale didattico", count: files.count)) {
                ForEach(files.prefix(10), id: \.1.id) { teacher, content in
                    NavigationLink {
                        DidacticsView()
                    } label: {
                        NavigationRow(content.name, subtitle: teacher.name, icon: content.icon, tint: Theme.tertiary)
                    }
                    .buttonStyle(.listRow)
                }
            }
        }
        if !notes.isEmpty {
            ListGroup(header(for: "Note", count: notes.count)) {
                ForEach(notes.prefix(10)) { note in
                    ListRow(note.text, subtitle: "\(note.category.singular) · \(note.date.shortDay)") {
                        IconBadge(icon: "messageAlert", tint: Theme.poor, size: 40)
                    } trailing: {
                        EmptyView()
                    }
                }
            }
        }
    }

    private func header(for title: String, count: Int) -> String {
        count > 15 ? "\(title) · \(count)" : title
    }
}

/// Barra della ricerca. Con Liquid Glass il campo è quello di sistema (nella barra delle schede);
/// nella Dashboard (Material) il campo è la barra di ricerca sospesa della Dashboard; altrimenti il
/// titolo con il campo nel contenuto.
private struct SearchChrome: ViewModifier {
    @Binding var query: String
    let embedded: Bool
    var focus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if ThemeStore.shared.liquidGlass {
            content
                .pageChrome("Cerca")
                .searchable(text: $query, prompt: SearchView.prompt)
                // Con la tastiera aperta il titolo "Cerca" resta visibile.
                .searchPresentationToolbarBehavior(.avoidHidingContent)
        } else if embedded {
            content
        } else {
            content.pageChrome("Cerca")
        }
    }
}

/// Chip che vanno a capo automaticamente.
struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                FilterChip(title: item, isSelected: false) { onTap(item) }
            }
        }
    }
}

/// Elementi su più righe, andando a capo quando non ci stanno. Le righe si calcolano allo stesso
/// modo nelle due fasi (dalla larghezza proposta, partendo da 0, con mezzo punto di tolleranza):
/// prima `placeSubviews` usava le coordinate assolute e la larghezza restituita, e con una fila
/// piena al punto l'ultimo elemento saltava tra la riga e una riga a capo durante lo scorrimento.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    /// Posizione di ogni elemento rispetto all'angolo in alto a sinistra, e misura totale.
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], sizes: [CGSize], size: CGSize) {
        var origins: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width + 0.5 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            sizes.append(size)
            maxX = max(maxX, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (origins, sizes, CGSize(width: maxX, height: y + rowHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(subviews, width: proposal.width ?? bounds.width)
        for (index, view) in subviews.enumerated() {
            let origin = layout.origins[index]
            view.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                       proposal: ProposedViewSize(layout.sizes[index]))
        }
    }
}
