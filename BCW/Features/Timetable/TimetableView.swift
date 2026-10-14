import SwiftUI

/// Scheda Orario: l'orario settimanale dell'utente, in tre viste.
/// - Lista: in alto la settimana (come la vista Lista della Dashboard), sotto gli eventi del giorno.
/// - Calendario: in alto il mese (come la vista Calendario della Dashboard), sotto gli eventi del giorno.
/// - Giorno: le ore della giornata, come in Calendario.
/// Su iPhone la parte superiore resta ferma mentre gli eventi scorrono; su Mac calendario e
/// settimana stanno in una colonna a sinistra e gli eventi a destra.
/// "Modifica orario" (nel menu) apre la modalità di modifica grafica, sempre nella vista Giorno:
/// gli eventi si spostano e si ridimensionano seguendo l'allineamento scelto lì.
struct TimetableView: View {
    @Environment(AppModel.self) private var model
    /// Cambia quando si tocca di nuovo la scheda Orario (iOS): si torna a oggi.
    var reselection = 0

    @State private var selectedDay = Date().startOfDay
    @State private var adjustedInitialDay = false
    @State private var editor: TimetableEditorRequest?
    @State private var detail: TimetableDetailRequest?
    @State private var paletteWeekday: PaletteWeekday?
    @State private var showingGenerator = false
    @State private var showingHiddenTests = false
    @State private var deleting: TimetableEntry?
    /// Modalità di modifica grafica: vista Giorno con eventi trascinabili.
    @State private var isEditing = false
    #if os(iOS)
    /// La settimana, che galleggia sopra gli eventi, è ridotta a una striscia (vista Giorno).
    @State private var headerCollapsed = false
    /// Nella vista Lista la settimana segue invece lo scorrimento.
    @State private var weekScroll = WeekHeaderScroll()
    /// Altezza di ciò che galleggia sotto la settimana (bozza, modifica, avvisi).
    @State private var extrasHeight: CGFloat = 0
    #endif

    struct PaletteWeekday: Identifiable {
        let weekday: Int
        var id: Int { weekday }
    }

    private var store: TimetableStore { model.timetable }
    /// In modifica si usa sempre la vista Giorno; uscendo si torna a quella scelta. Su iPhone la
    /// vista Calendario non c'è (resta nella Dashboard): al suo posto la Lista.
    private var mode: TimetableMode {
        if isEditing { return .day }
        let chosen = model.preferences.timetableMode
        return TimetableMode.available.contains(chosen) ? chosen : .list
    }

    private var actions: TimetableActions {
        TimetableActions(
            open: { entry, day in detail = TimetableDetailRequest(entryID: entry.id, day: day) },
            edit: { entry in editor = TimetableEditorRequest(entry: entry) },
            duplicate: { entry in withAnimation(.snappy) { _ = store.duplicate(entry) } },
            delete: { entry in deleting = entry },
            colorDay: { weekday in paletteWeekday = PaletteWeekday(weekday: weekday) },
            create: { weekday, start in editor = TimetableEditorRequest(weekday: weekday, start: start) },
            generate: { showingGenerator = true }
        )
    }

    var body: some View {
        PlatformNavigationStack {
            content
                // `screenTitle` va prima del `.toolbar` della pagina: su macOS così Aggiorna resta
                // dopo i pulsanti dell'orario, subito prima della ricerca.
                #if os(macOS)
                .screenTitle(isEditing ? "Modifica orario" : "Orario", subtitle: selectedDay.longDay)
                #else
                .screenTitle(isEditing ? "Modifica" : "Orario")
                .inlineLargeTitleDisplay()
                #endif
                .toolbar { toolbar }
                .sheet(item: $editor) { request in
                    TimetableEntryEditor(request: request)
                }
                .sheet(item: $detail) { request in
                    TimetableEntryDetail(request: request) { entry in
                        // Il dettaglio si chiude e si apre l'editor.
                        Task {
                            try? await Task.sleep(for: .milliseconds(Platform.isMac ? 50 : 450))
                            editor = TimetableEditorRequest(entry: entry)
                        }
                    }
                }
                .sheet(item: $paletteWeekday) { request in
                    PaletteSeriesSheet(weekday: request.weekday)
                }
                .sheet(isPresented: $showingGenerator) {
                    TimetableGeneratorSheet()
                }
                .sheet(isPresented: $showingHiddenTests) {
                    TimetableHiddenTestsView()
                }
                .confirmationDialog("Eliminare «\(deleting?.displayTitle ?? "")»?",
                                    isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                    titleVisibility: .visible, presenting: deleting) { entry in
                    Button("Elimina solo questo", role: .destructive) {
                        withAnimation(.snappy) { store.delete([entry.id]) }
                    }
                    let others = store.sameNameEntries(as: entry)
                    if !others.isEmpty {
                        Button("Elimina tutti gli eventi «\(entry.displayTitle)» (\(others.count + 1))", role: .destructive) {
                            withAnimation(.snappy) { store.delete(Set([entry.id] + others.map(\.id))) }
                        }
                    }
                    Button("Annulla", role: .cancel) {}
                }
                .onAppear(perform: adjustInitialDay)
                .onChange(of: reselection) {
                    select(Date().startOfDay)
                    #if os(iOS)
                    withAnimation(FloatingHeaderCollapse.animation) { headerCollapsed = false }
                    weekScroll.open()
                    #endif
                }
                // Con una bozza in anteprima non si modifica l'orario.
                .onChange(of: store.draft == nil) { _, noDraft in if !noDraft { setEditing(false) } }
                #if DEBUG
                .task { await DebugTimetable.prepareIfRequested(model: model) }
                #endif
        }
    }

    /// Nel fine settimana senza lezioni l'orario si apre sul lunedì successivo.
    private func adjustInitialDay() {
        guard !adjustedInitialDay else { return }
        adjustedInitialDay = true
        #if DEBUG
        // Per gli screenshot di sviluppo: `-BCWTimetableEditing YES` apre la modalità di modifica.
        if UserDefaults.standard.bool(forKey: "BCWTimetableEditing") { isEditing = true }
        // `-BCWTimetableSheet generator|hidden` apre il generatore o le verifiche nascoste.
        switch UserDefaults.standard.string(forKey: "BCWTimetableSheet") {
        case "generator": showingGenerator = true
        case "hidden": showingHiddenTests = true
        default: break
        }
        // `-BCWTimetableDay N` apre l'orario N giorni dopo oggi (come argomento solo valori positivi).
        if UserDefaults.standard.object(forKey: "BCWTimetableDay") != nil {
            selectedDay = Date().adding(days: UserDefaults.standard.integer(forKey: "BCWTimetableDay")).startOfDay
            return
        }
        #endif
        let today = Date().startOfDay
        if today.isWeekend && store.entries(on: today).isEmpty && !store.timetable.isEmpty {
            selectedDay = today.startOfWeek.adding(days: 7)
        }
    }

    private func setEditing(_ editing: Bool) {
        guard editing != isEditing else { return }
        withAnimation(.snappy) { isEditing = editing }
    }

    private func select(_ day: Date) {
        guard !day.isSameDay(as: selectedDay) else { return }
        withAnimation(.snappy) { selectedDay = day.startOfDay }
    }

    private var daySelection: Binding<Date> {
        Binding { selectedDay } set: { day in
            guard !day.isSameDay(as: selectedDay) else { return }
            selectedDay = day.startOfDay
        }
    }

    // MARK: Barra

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // "Oggi" c'è solo se il giorno scelto non è oggi, come "Domani" nella Dashboard.
        if !selectedDay.isToday {
            ToolbarItem(placement: .trailingBar) {
                Button("Oggi") { select(Date()) }
                    #if os(macOS)
                    .keyboardShortcut("t")
                    .help("Vai a oggi (⌘T)")
                    #endif
            }
            ToolbarSpacer(.fixed, placement: .trailingBar)
        }
        #if os(macOS)
        if !isEditing {
            ToolbarItem(placement: .trailingBar) {
                Picker("Vista", selection: Bindable(model.preferences).timetableMode) {
                    ForEach(TimetableMode.allCases) { mode in
                        Label(mode == .day ? "Settimana" : mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
                .help("Vista: lista, calendario o settimana")
            }
        }
        ToolbarItemGroup(placement: .trailingBar) {
            Button("Nuovo evento", systemImage: "plus") {
                editor = TimetableEditorRequest(weekday: selectedDay.timetableWeekday)
            }
            .keyboardShortcut("n")
            .help("Nuovo evento (⌘N)")
            .disabled(store.draft != nil)
            if isEditing {
                Button("Fine") { setEditing(false) }
                    .keyboardShortcut(.defaultAction)
                    .help("Esci dalla modifica dell'orario (↩)")
            } else {
                optionsMenu
                    .menuIndicator(.hidden)
                    .help("Modifica, colori e generazione")
            }
        }
        #else
        ToolbarItem(placement: .trailingBar) {
            Button("Nuovo evento", systemImage: "plus") {
                editor = TimetableEditorRequest(weekday: selectedDay.timetableWeekday)
            }
            .disabled(store.draft != nil)
        }
        ToolbarSpacer(.fixed, placement: .trailingBar)
        if isEditing {
            ToolbarItem(placement: .trailingBar) {
                Button("Fine", systemImage: "checkmark") { setEditing(false) }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel("Fine modifica")
            }
        } else {
            ToolbarItem(placement: .trailingBar) {
                optionsMenu
            }
        }
        #endif
    }

    private var optionsMenu: some View {
        Menu {
            Button("Modifica orario", systemImage: "slider.horizontal.below.rectangle") { setEditing(true) }
                .disabled(store.draft != nil)
            Divider()
            #if os(iOS)
            Picker("Vista", selection: Binding(get: { mode }, set: { model.preferences.timetableMode = $0 })) {
                ForEach(TimetableMode.available) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            #endif
            // Cambia ciò che mostra la lista: sta con la scelta della vista.
            Toggle("Mostra le verifiche", systemImage: "pencil.and.list.clipboard",
                   isOn: Bindable(model.preferences).timetableShowsTests)
            Button("Verifiche nascoste…", systemImage: "eye.slash") { showingHiddenTests = true }
            Divider()
            Button("Nuovo intervallo", systemImage: "cup.and.saucer") {
                editor = TimetableEditorRequest(weekday: selectedDay.timetableWeekday, kind: .breakTime)
            }
            .disabled(store.draft != nil)
            Button("Colora una giornata…", systemImage: "paintpalette") {
                paletteWeekday = PaletteWeekday(weekday: selectedDay.timetableWeekday)
            }
            .disabled(store.timetable.isEmpty || store.draft != nil)
            Divider()
            Button("Genera dalle lezioni registrate…", systemImage: "wand.and.stars") { showingGenerator = true }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Opzioni dell'orario")
    }

    // MARK: Contenuto

    private var banner: some View {
        TimetableDraftBanner { showingGenerator = true }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        macContent
        #else
        // La settimana galleggia sopra gli eventi, che le scorrono sotto: così la pagina scorre come
        // le altre schede (con il titolo grande che si riduce) e la settimana si riduce a una
        // striscia scorrendo verso il basso (`FloatingHeaderCollapse`).
        ZStack(alignment: .top) {
            switch mode {
            case .list, .calendar:
                ScrollView {
                    TimetableDayList(content: TimetableDayContent(day: selectedDay, model: model), actions: actions)
                        .id(selectedDay)
                        .transition(.opacity)
                        .pagePadding()
                        .padding(.bottom, Theme.bottomInset)
                        .background { ScrollResistance(range: WeekHeaderScroll.range) }
                }
                .scrollDismissesKeyboard(.immediately)
                .safeAreaPadding(.top, floatingHeight)
                .modifier(WeekHeaderScroll.Tracking(state: weekScroll))
            case .day:
                TimetableTimeline(days: [selectedDay], selectedDay: selectedDay, actions: actions, isEditing: isEditing,
                                  topInset: floatingHeight, headerCollapsed: $headerCollapsed)
            }

            VStack(spacing: 10) {
                WeekHeaderHost(selectedDay: daySelection, scroll: mode == .day ? nil : weekScroll,
                               collapsed: headerCollapsed) {
                    withAnimation(FloatingHeaderCollapse.animation) { headerCollapsed = false }
                }
                floatingExtras
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { extrasHeight = $0 }
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
        .animation(.snappy, value: selectedDay)
        .animation(.snappy, value: isEditing)
        .animation(.snappy, value: store.draft == nil)
        .themedBackground()
        .onChange(of: mode) { headerCollapsed = false; weekScroll.close() }
        .onChange(of: isEditing) { headerCollapsed = false }
        #endif
    }

    #if os(iOS)
    /// La settimana con l'avanzamento giusto per la vista: nella Lista quello dello scorrimento,
    /// letto solo qui (cambia a ogni fotogramma), nella vista Giorno lo stato ridotto.
    private struct WeekHeaderHost: View {
        @Binding var selectedDay: Date
        let scroll: WeekHeaderScroll?
        let collapsed: Bool
        let expandDay: () -> Void

        var body: some View {
            if let scroll {
                TimetableWeekHeader(selectedDay: $selectedDay, progress: scroll.progress, onExpand: scroll.open)
            } else {
                TimetableWeekHeader(selectedDay: $selectedDay, progress: collapsed ? 1 : 0, onExpand: expandDay)
            }
        }
    }

    /// Spazio occupato in cima dagli elementi mobili con la settimana intera: gli eventi cominciano
    /// sotto. Resta lo stesso quando la settimana si riduce, così la pagina non salta.
    private var floatingHeight: CGFloat {
        4 + TimetableWeekHeader.expandedHeight + (extrasHeight > 0 ? 10 + extrasHeight : 0) + 12
    }

    /// Sotto la settimana: bozza in anteprima, modifica dell'orario e, nella vista Giorno, le
    /// verifiche senza lezione in orario.
    @ViewBuilder
    private var floatingExtras: some View {
        let unmatched = mode == .day ? TimetableDayContent(day: selectedDay, model: model).unmatchedTests : []
        if store.draft != nil || isEditing || !unmatched.isEmpty {
            VStack(spacing: 10) {
                if store.draft != nil {
                    banner.glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
                }
                if isEditing {
                    TimetableEditBar()
                        .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if !unmatched.isEmpty {
                    Label(unmatched.count == 1 ? "1 verifica senza lezione in orario: \(unmatched[0].title)"
                          : "\(unmatched.count) verifiche senza lezione in orario",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassEffect(.regular.tint(Theme.fair.opacity(0.2)), in: .capsule)
                }
            }
        }
    }
    #endif

    #if os(macOS)
    /// Giorni mostrati nella vista settimanale su Mac: da lunedì a venerdì, più il fine
    /// settimana se ci sono eventi o se è il giorno scelto.
    private var weekDays: [Date] {
        let start = selectedDay.startOfWeek
        return (0..<7).map { start.adding(days: $0) }.filter { day in
            !day.isWeekend || day.isSameDay(as: selectedDay) || !store.entries(on: day).isEmpty
        }
    }

    @ViewBuilder
    private var macContent: some View {
        switch mode {
        case .list, .calendar:
            SplitColumns(sideWidth: 340) {
                if mode == .list {
                    WeekStrip(selectedDay: daySelection)
                } else {
                    MonthCalendar(selectedDay: daySelection)
                }
                StackAware { stacked in
                    if !stacked {
                        TimetableWeekOverview(selectedDay: selectedDay) { select($0) }
                    }
                }
            } main: {
                banner
                TimetableDayList(content: TimetableDayContent(day: selectedDay, model: model), actions: actions)
                    .id(selectedDay)
                    .transition(.opacity)
            }
            .animation(.snappy, value: selectedDay)
        case .day:
            MacWeekTimeline(selectedDay: daySelection, days: weekDays, actions: actions, isEditing: isEditing,
                            banner: { banner })
                .animation(.snappy, value: isEditing)
        }
    }
    #endif
}

#if os(macOS)
/// Vista settimanale su Mac: il mese a sinistra (con il riepilogo della settimana), le ore della
/// settimana a destra. Sotto i 780 punti resta solo la linea del tempo, con la settimana sopra.
private struct MacWeekTimeline<Banner: View>: View {
    @Binding var selectedDay: Date
    let days: [Date]
    let actions: TimetableActions
    let isEditing: Bool
    @ViewBuilder let banner: () -> Banner
    /// Solo il passaggio conta, non la larghezza (che cambierebbe a ogni fotogramma).
    @State private var wide = true

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if wide {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        MonthCalendar(selectedDay: $selectedDay)
                        TimetableWeekOverview(selectedDay: selectedDay) { day in
                            withAnimation(.snappy) { selectedDay = day }
                        }
                    }
                    .padding(.leading, 28)
                    .padding(.trailing, 10)
                    .padding(.top, 8)
                    .padding(.bottom, Theme.bottomInset)
                }
                .frame(width: 340 + 38)
            }
            VStack(spacing: 10) {
                if !wide {
                    WeekStrip(selectedDay: $selectedDay)
                        .fixedSize(horizontal: false, vertical: true)
                }
                banner()
                if isEditing {
                    TimetableEditBar()
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                TimetableTimeline(days: wide ? days : [selectedDay], selectedDay: selectedDay,
                                  onSelectDay: { day in withAnimation(.snappy) { selectedDay = day } },
                                  actions: actions, isEditing: isEditing)
                    .card(padding: 0)
            }
            .padding(.leading, wide ? 10 : 28)
            .padding(.trailing, 28)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themedBackground()
        .onGeometryChange(for: Bool.self) { $0.size.width >= 780 } action: { wide = $0 }
    }
}
#endif

/// Riepilogo della settimana (su Mac, nella colonna laterale): un riga per giorno con orari,
/// lezioni e verifiche. Un clic porta a quel giorno.
struct TimetableWeekOverview: View {
    @Environment(AppModel.self) private var model
    let selectedDay: Date
    let onSelect: (Date) -> Void

    var body: some View {
        let start = selectedDay.startOfWeek
        let days = (0..<7).map { start.adding(days: $0) }.filter { day in
            !day.isWeekend || !model.timetable.entries(on: day).isEmpty
        }
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Settimana")
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    row(day)
                    if day != days.last { Divider().overlay(Theme.separator) }
                }
            }
            // `.card()` non ritaglia il contenuto: senza, l'evidenziazione del giorno scelto (un
            // rettangolo) sporgerebbe dagli angoli arrotondati sulla prima e sull'ultima riga.
            .frame(maxWidth: .infinity)
            .clipShape(.rect(cornerRadius: Theme.corner, style: .continuous))
            .card(padding: 0)
        }
    }

    private func row(_ day: Date) -> some View {
        let content = TimetableDayContent(day: day, model: model)
        let selected = day.isSameDay(as: selectedDay)
        let lessons = content.layout.clusters.flatMap(\.blocks).map(\.block)
        let tests = content.badges.values.filter(\.isTest).count + content.unmatchedTests.count
        return Button { onSelect(day) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(day.it("EEEEd").capitalizedFirst)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? Theme.accent : Theme.ink)
                        if tests > 0 && model.preferences.timetableShowsTests {
                            Image(systemName: "pencil.and.list.clipboard")
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    if let span = content.layout.span {
                        Text("\(content.entries.filter { !$0.isBreak }.count) lezioni · \(TimeOfDay.string(span.start))–\(TimeOfDay.string(span.end))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.secondaryInk)
                    } else {
                        Text("Nessuna lezione")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryInk)
                    }
                }
                Spacer(minLength: 6)
                // Una barretta per lezione (i gruppi contano una volta), nei loro colori.
                HStack(spacing: 2) {
                    ForEach(lessons.prefix(8)) { block in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.timetableColor(block.entries[0], store: model.timetable)
                                .opacity(content.isDraft ? 0.5 : 1))
                            .frame(width: CGFloat(6 * block.entries.count), height: 14)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(selected ? Theme.accent.opacity(0.08) : Color.clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
/// Per gli screenshot di sviluppo: `-BCWTimetableDemo YES` crea l'orario della demo dalle
/// lezioni (se è vuoto), con un intervallo, note, una verifica e una palette;
/// `-BCWTimetableDraft YES` mostra invece la bozza generata in anteprima.
enum DebugTimetable {
    static func prepareIfRequested(model: AppModel) async {
        await prepareTable(model: model)
        // Le verifiche arrivano con l'agenda, che può non essere ancora pronta.
        for _ in 0..<20 where model.agenda.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
        hideTestsIfRequested(model: model)
    }

    private static func hideTestsIfRequested(model: AppModel) {
        let defaults = UserDefaults.standard
        let store = model.timetable
        // `-BCWHideTests YES`: una regola (il docente della prima verifica) e una verifica nascosta a mano.
        if model.isDemo, defaults.bool(forKey: "BCWHideTests") {
            let tests = model.agenda.filter { $0.kind == .test }.sorted { $0.begin < $1.begin }
            var rules = TestHidingRules()
            if let teacher = tests.first(where: { !$0.authorName.isEmpty })?.authorName { rules.teachers = [teacher] }
            store.setTestRules(rules)
            if let other = tests.first(where: { store.hiddenReason(for: $0, unmatched: false) == nil && $0.begin > Date() }) {
                store.setTestHidden(true, test: other)
            }
        }
    }

    private static func prepareTable(model: AppModel) async {
        let defaults = UserDefaults.standard
        let wantsTable = defaults.bool(forKey: "BCWTimetableDemo")
        let wantsDraft = defaults.bool(forKey: "BCWTimetableDraft")
        guard model.isDemo, wantsTable || wantsDraft else { return }
        let store = model.timetable
        guard store.timetable.isEmpty, store.draft == nil else { return }
        var settings = GenerationSettings()
        settings.breaks = [.init(start: 10 * 60 + 50, duration: 10)]
        let range = TimetableGenerator.range(for: settings)
        guard let lessons = try? await model.fetchLessons(from: range.from, to: range.to) else { return }
        let result = TimetableGenerator.generate(from: lessons, settings: settings)
        store.draft = TimetableDraft(entries: store.alignment == .automatic
                                        ? result.entries.flatMap { $0.alignedPieces() } : result.entries, settings: settings, analyzedDays: result.analyzedDays,
                                     from: range.from, to: range.to)
        guard wantsTable else { return }
        store.applyDraft(replacing: true)
        // Un po' di varietà: due eventi contemporanei, una nota, una verifica a mano, una palette.
        if let first = store.entries(weekday: 1).first(where: { !$0.isBreak }) {
            store.setNote("Portare il libro di testo", for: first, scope: .everyWeek)
            var parallel = TimetableEntry(weekday: 1, start: first.start + 30, end: first.start + 90,
                                          title: "Sportello di fisica", room: "Lab 2")
            parallel.color = .pastel(5)
            store.add([parallel])
        }
        if let wednesday = store.entries(weekday: 3).filter({ !$0.isBreak }).last {
            store.setTest(true, for: wednesday, scope: .everyWeek)
        }
        let thursday = store.entries(weekday: 4).filter { !$0.isBreak }.map(\.id)
        store.applyPalette("builtin.lagoon", to: thursday)
    }
}
#endif

#if DEBUG
/// Autotest del backup (solo sviluppo): `-BCWTimetableSelfTest YES` esporta un orario completo
/// (colori, palette, note, verifiche, file), lo importa su un orario diverso e controlla che il
/// risultato sia identico all'originale, file compresi; controlla anche che i file non validi
/// vengano rifiutati senza toccare l'orario. Stampa `BCW-SELFTEST` con l'esito ed esce.
enum TimetableSelfTest {
    static func runIfRequested() {
        guard UserDefaults.standard.bool(forKey: "BCWTimetableSelfTest") else { return }
        var failures: [String] = []
        func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }

        let ownerA = "selftest-a-\(UUID().uuidString)"
        let ownerB = "selftest-b-\(UUID().uuidString)"
        defer {
            TimetableStore.removeData(owner: ownerA)
            TimetableStore.removeData(owner: ownerB)
        }

        // Orario di partenza, con tutto ciò che un backup deve conservare.
        let source = TimetableStore()
        source.load(owner: ownerA)
        let monday = Date().startOfWeek
        var math = TimetableEntry(weekday: 1, start: 8 * 60, end: 9 * 60, title: "Matematica", subjectId: 103,
                                  teacher: "Rossi Giorgio", room: "2B", color: .pastel(3), note: "Calcolatrice")
        let math2 = TimetableEntry(weekday: 1, start: 9 * 60, end: 10 * 60, title: "Matematica", subjectId: 103)
        let pause = TimetableEntry(weekday: 1, start: 9 * 60 + 50, end: 10 * 60, kind: .breakTime, title: "Intervallo",
                                   color: .custom(0x123456))
        let free = TimetableEntry(weekday: 3, start: 8 * 60 + 52, end: 9 * 60 + 47, title: "Inglese", color: .custom(0xABCDEF))
        math.isWeeklyTest = true
        source.add([math, math2, pause, free])
        source.savePalette(ColorPalette(id: "custom-1", name: "Mia", colors: [0x111111, 0x999999, 0xFFFFFF]))
        source.applyPalette("custom-1", to: [math.id, math2.id])
        source.saveCustomColor(0x445566)
        source.setNote("Interrogazione", for: math, scope: .day(monday))
        source.setTest(false, for: math, scope: .day(monday.adding(days: 7)))
        source.setTestHidden(true, eventID: 4242)
        source.setAlignment(.free)
        var generation = GenerationSettings()
        generation.hourLength = 55
        generation.breaks = [.init(start: 10 * 60 + 50, duration: 10)]
        source.setGeneration(generation)
        let weeklyFile = Data("file settimanale".utf8)
        let dayFile = Data((0..<4096).map { UInt8($0 % 251) })
        do {
            try source.attach(data: weeklyFile, name: "appunti.txt", to: source.entry(id: math.id)!, scope: .everyWeek)
            try source.attach(data: dayFile, name: "foto.jpg", to: source.entry(id: math.id)!, scope: .day(monday))
        } catch {
            failures.append("allegati: \(error)")
        }

        // Orario di destinazione diverso, con un suo file: dopo l'importazione deve sparire.
        let target = TimetableStore()
        target.load(owner: ownerB)
        let old = TimetableEntry(weekday: 2, start: 11 * 60, end: 12 * 60, title: "Vecchia")
        target.add([old])
        try? target.attach(data: Data("vecchio".utf8), name: "vecchio.txt", to: old, scope: .everyWeek)
        let oldFiles = (try? FileManager.default.contentsOfDirectory(atPath: target.filesDirectory!.path)) ?? []
        check(oldFiles.count == 1, "il file del vecchio orario non c'è")
        let before = target.timetable

        // File non validi: rifiutati, orario intatto.
        for (data, label) in [(Data("{}".utf8), "json vuoto"), (Data("non json".utf8), "testo"),
                              (Data(#"{"format":"com.bcw.timetable-backup","version":99}"#.utf8), "versione futura")] {
            do {
                _ = try TimetableStore.readBackup(data)
                failures.append("\(label) accettato")
            } catch {}
        }
        check(target.timetable == before, "un file non valido ha cambiato l'orario")

        // Esportazione e importazione.
        do {
            let data = try source.makeBackup()
            let backup = try TimetableStore.readBackup(data)
            check(backup.files.count == 2, "il backup ha \(backup.files.count) file invece di 2")
            try target.restore(backup)
            check(target.timetable == source.timetable, "l'orario importato è diverso dall'originale")
            for attachment in source.timetable.referencedFiles {
                let a = try? Data(contentsOf: source.filesDirectory!.appendingPathComponent(attachment))
                let b = try? Data(contentsOf: target.filesDirectory!.appendingPathComponent(attachment))
                check(a != nil && a == b, "file \(attachment) diverso dopo l'importazione")
            }
            let files = Set((try? FileManager.default.contentsOfDirectory(atPath: target.filesDirectory!.path)) ?? [])
            check(files == source.timetable.referencedFiles, "file in più o in meno dopo l'importazione: \(files)")

            // Rileggendo dal disco (come al prossimo avvio) è ancora tutto uguale.
            let reloaded = TimetableStore()
            reloaded.load(owner: ownerB)
            check(reloaded.timetable == source.timetable, "l'orario salvato su disco è diverso dopo il riavvio")
            check(reloaded.entries(weekday: 1).count == 3, "indice dei giorni non ricostruito")
            check(reloaded.isManualTest(reloaded.entry(id: math.id)!, on: monday), "verifica settimanale persa")
            check(!reloaded.isManualTest(reloaded.entry(id: math.id)!, on: monday.adding(days: 7)), "eccezione del giorno persa")
            check(reloaded.occurrence(math.id, on: monday).note == "Interrogazione", "nota del giorno persa")
            check(reloaded.isTestHidden(4242), "verifica nascosta persa")
            check(reloaded.alignment == .free, "allineamento perso")
            check(reloaded.timetable.generation.hourLength == 55, "impostazioni di generazione perse")
            check(reloaded.entry(id: free.id)?.start == 8 * 60 + 52, "orario libero cambiato")

            // Esportando di nuovo l'orario importato si ottiene lo stesso contenuto.
            let again = try TimetableStore.readBackup(try reloaded.makeBackup())
            check(again.timetable == backup.timetable, "seconda esportazione diversa")
        } catch {
            failures.append("esportazione/importazione: \(error)")
        }

        // Rimuovendo un allegato il file si cancella solo quando nessuno lo usa più.
        if let entry = target.entry(id: math.id), let attachment = entry.attachments.first {
            target.removeAttachment(attachment, from: entry, scope: .everyWeek)
            check(!FileManager.default.fileExists(atPath: target.url(for: attachment)!.path), "file non più usato non cancellato")
        }

        // Modifiche applicate a tutti gli eventi con lo stesso nome.
        let ownerC = "selftest-c-\(UUID().uuidString)"
        defer { TimetableStore.removeData(owner: ownerC) }
        let shared = TimetableStore()
        shared.load(owner: ownerC)
        let a = TimetableEntry(weekday: 1, start: 8 * 60, end: 9 * 60, title: "Fisica")
        let b = TimetableEntry(weekday: 4, start: 10 * 60, end: 11 * 60, title: " fisica ")
        let c = TimetableEntry(weekday: 4, start: 11 * 60, end: 12 * 60, title: "Chimica")
        shared.add([a, b, c])
        shared.setNote("Laboratorio", for: a, scope: .allSameName)
        shared.setTest(true, for: a, scope: .allSameName)
        try? shared.attach(data: Data("x".utf8), name: "x.txt", to: a, scope: .allSameName)
        check(shared.entry(id: b.id)?.note == "Laboratorio" && shared.entry(id: c.id)?.note == "",
              "nota non applicata solo agli eventi con lo stesso nome")
        check(shared.entry(id: b.id)?.isWeeklyTest == true && shared.entry(id: c.id)?.isWeeklyTest == false,
              "verifica non applicata solo agli eventi con lo stesso nome")
        check(shared.entry(id: b.id)?.attachments.count == 1, "file non allegato agli eventi con lo stesso nome")
        if let file = shared.entry(id: a.id)?.attachments.first {
            shared.removeAttachment(file, from: a, scope: .everyWeek)
            check(FileManager.default.fileExists(atPath: shared.url(for: file)!.path), "file condiviso cancellato troppo presto")
            shared.removeAttachment(file, from: shared.entry(id: b.id)!, scope: .allSameName)
            check(!FileManager.default.fileExists(atPath: shared.url(for: file)!.path), "file condiviso non cancellato")
        }
        var renamed = shared.entry(id: a.id)!
        renamed.title = "Fisica e laboratorio"
        renamed.color = .pastel(2)
        shared.save(renamed, propagatingFrom: shared.entry(id: a.id))
        check(shared.entry(id: b.id)?.title == "Fisica e laboratorio" && shared.entry(id: b.id)?.color == .pastel(2),
              "modifica dell'editor non applicata agli altri eventi")
        check(shared.entry(id: c.id)?.title == "Chimica", "modifica applicata a un evento diverso")

        // Generazione: due ore di fila, una supplenza isolata ignorata.
        let lessonsJSON = (0..<4).flatMap { week -> [[String: Any]] in
            let day = CVDate.dayKey(Date().startOfWeek.adding(days: -7 * (week + 1)))
            var lessons: [[String: Any]] = [
                ["evtDate": day, "evtHPos": 1, "evtDuration": 2, "subjectId": 1, "subjectDesc": "MATEMATICA"],
                ["evtDate": day, "evtHPos": 3, "evtDuration": 1, "subjectId": 2, "subjectDesc": "STORIA"],
            ]
            if week == 0 { lessons[1]["subjectId"] = 3; lessons[1]["subjectDesc"] = "SUPPLENZA" }
            return lessons
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["lessons": lessonsJSON]),
           let lessons = try? JSONDecoder().decode(LessonsResponse.self, from: data).lessons {
            let generated = TimetableGenerator.generate(from: lessons, settings: GenerationSettings()).entries
            check(generated.map(\.title) == ["Matematica", "Matematica", "Storia"], "generazione: \(generated.map(\.title))")
            check(generated.map(\.start) == [480, 540, 600] && generated.allSatisfy { $0.weekday == 1 },
                  "generazione: orari \(generated.map(\.start))")
            let layout = TimetableLayout(entries: generated)
            check(layout.clusters.count == 2 && layout.clusters[0].blocks[0].block.entries.count == 2,
                  "le due ore di matematica non formano un gruppo")
        } else {
            failures.append("lezioni di prova non decodificate")
        }

        // Passaggio dall'allineamento libero all'automatico.
        let ownerD = "selftest-d-\(UUID().uuidString)"
        defer { TimetableStore.removeData(owner: ownerD) }
        let align = TimetableStore()
        align.load(owner: ownerD)
        align.setAlignment(.free)
        let long = TimetableEntry(weekday: 2, start: 10 * 60, end: 12 * 60 + 30, title: "Laboratorio", note: "Camice")
        let odd = TimetableEntry(weekday: 2, start: 8 * 60 + 52, end: 9 * 60 + 47, title: "Inglese")
        let chainA = TimetableEntry(weekday: 3, start: 8 * 60, end: 8 * 60 + 50, title: "Arte")
        let chainB = TimetableEntry(weekday: 3, start: 8 * 60 + 50, end: 9 * 60 + 40, title: "Storia")
        let pause2 = TimetableEntry(weekday: 3, start: 9 * 60 + 35, end: 9 * 60 + 45, kind: .breakTime, title: "Intervallo")
        let fine = TimetableEntry(weekday: 4, start: 9 * 60, end: 10 * 60, title: "Fisica")
        align.add([long, odd, chainA, chainB, pause2, fine])
        align.setNote("Interrogazione", for: long, scope: .day(Date().startOfWeek.adding(days: 1)))
        check(Set(align.unalignedEntries.map(\.id)) == [long.id, odd.id, chainA.id, chainB.id],
              "eventi non allineati: \(align.unalignedEntries.map(\.title))")
        align.setAlignment(.automatic)
        let lab = align.entries(weekday: 2, includingDraft: false).filter { $0.title == "Laboratorio" }
        check(lab.map(\.start) == [600, 660, 720] && lab.map(\.end) == [660, 720, 750], "evento lungo non diviso: \(lab.map(\.timeRange))")
        check(lab.first?.id == long.id && lab.first?.note == "Camice" && lab.dropFirst().allSatisfy { $0.note.isEmpty },
              "nota non rimasta sul primo pezzo")
        check(align.occurrence(long.id, on: Date().startOfWeek.adding(days: 1)).note == "Interrogazione",
              "modifica del giorno persa dividendo")
        let aligned = align.entry(id: odd.id)
        check(aligned?.start == 540 && aligned?.end == 600, "evento libero non allineato")
        let arte = align.entry(id: chainA.id), storia = align.entry(id: chainB.id)
        check(arte?.end == storia?.start && arte?.isAutoAligned == true && storia?.isAutoAligned == true,
              "eventi di seguito non più di seguito: \(arte?.timeRange ?? "") \(storia?.timeRange ?? "")")
        check(align.entry(id: pause2.id)?.start == 9 * 60 + 35, "intervallo spostato dall'allineamento")
        check(align.entry(id: fine.id)?.start == 9 * 60, "evento già allineato cambiato")
        check(align.unalignedEntries.isEmpty, "restano eventi non allineati")
        check(TimetableLayout(entries: lab).clusters.first?.blocks.first?.block.entries.count == 3,
              "i pezzi dell'evento lungo non formano un gruppo")

        // Viste Lista e Calendario: un intervallo tra due eventi uguali di seguito li separa.
        let first = TimetableEntry(weekday: 1, start: 8 * 60, end: 9 * 60, title: "Matematica")
        let second = TimetableEntry(weekday: 1, start: 9 * 60, end: 10 * 60, title: "Matematica")
        let third = TimetableEntry(weekday: 1, start: 10 * 60, end: 11 * 60, title: "Matematica")
        for (pause, label) in [(TimetableEntry(weekday: 1, start: 9 * 60, end: 9 * 60 + 10, kind: .breakTime, title: "Intervallo"), "alle 9:00"),
                               (TimetableEntry(weekday: 1, start: 8 * 60 + 50, end: 9 * 60, kind: .breakTime, title: "Intervallo"), "alle 8:50")] {
            let entries = [first, second, third, pause]
            let order = TimetableLayout(entries: entries, splitAtBreaks: true).listItems.map { item -> String in
                switch item {
                case let .cluster(cluster): cluster.blocks.map { $0.block.entries.map { TimeOfDay.string($0.start) }.joined(separator: "+") }.joined()
                case .pause: "intervallo"
                case .gap: "libero"
                }
            }
            check(order == ["08:00", "intervallo", "09:00+10:00"], "lista con intervallo \(label): \(order)")
            check(TimetableLayout(entries: entries).clusters.first?.blocks.first?.block.entries.count == 3,
                  "vista Giorno: gruppo diviso dall'intervallo \(label)")
        }
        // Un intervallo dentro una lezione (non sul passaggio) non divide il gruppo.
        let inside = TimetableEntry(weekday: 1, start: 9 * 60 + 20, end: 9 * 60 + 30, kind: .breakTime, title: "Intervallo")
        let insideOrder = TimetableLayout(entries: [first, second, inside], splitAtBreaks: true).listItems.count
        check(insideOrder == 2, "intervallo dentro una lezione: \(insideOrder) righe")

        // Verifiche nascoste: a mano, dalle regole, mostrate a mano nonostante le regole.
        let ownerE = "selftest-e-\(UUID().uuidString)"
        defer { TimetableStore.removeData(owner: ownerE) }
        let hiding = TimetableStore()
        hiding.load(owner: ownerE)
        let saturday = Date().startOfWeek.adding(days: 5)
        let testsJSON: [[String: Any]] = [
            ["evtId": 1, "evtCode": "AGNT", "evtDatetimeBegin": CVDate.dayKey(Date().startOfWeek.adding(days: 1)) + "T10:00:00",
             "authorName": "ROSSI GIORGIO", "subjectDesc": "MATEMATICA", "notes": "Verifica scritta"],
            ["evtId": 2, "evtCode": "AGNT", "evtDatetimeBegin": CVDate.dayKey(saturday),
             "authorName": "BIANCHI LAURA", "subjectDesc": "LATINO", "notes": "Verifica di recupero"],
            ["evtId": 3, "evtCode": "AGNT", "evtDatetimeBegin": CVDate.dayKey(Date().startOfWeek.adding(days: 2)) + "T10:00:00",
             "authorName": "VERDI ANDREA", "subjectDesc": "STORIA", "notes": "Interrogazione"],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: testsJSON),
           let tests = try? JSONDecoder().decode([AgendaEvent].self, from: data), tests.count == 3 {
            let (rossi, sabato, verdi) = (tests[0], tests[1], tests[2])
            check(tests.allSatisfy { hiding.hiddenReason(for: $0, unmatched: false) == nil }, "verifiche nascoste senza regole")
            var rules = TestHidingRules()
            rules.teachers = [rossi.authorName]
            rules.weekdays = [6]
            hiding.setTestRules(rules)
            check(hiding.hiddenReason(for: rossi, unmatched: false) == .rule("Docente: \(rossi.authorName)"), "regola del docente")
            check(hiding.hiddenReason(for: sabato, unmatched: false) != nil, "regola del giorno")
            check(hiding.hiddenReason(for: verdi, unmatched: false) == nil, "verifica nascosta da nessuna regola")
            hiding.setTestHidden(false, test: rossi)
            check(hiding.hiddenReason(for: rossi, unmatched: false) == nil, "verifica non mostrata nonostante la regola")
            hiding.setTestHidden(true, test: rossi)
            check(hiding.hiddenReason(for: rossi, unmatched: false) == .rule("Docente: \(rossi.authorName)")
                  && !hiding.isTestHidden(rossi.id), "verifica non restituita alla regola")
            hiding.setTestHidden(true, test: verdi)
            check(hiding.hiddenReason(for: verdi, unmatched: false) == .manual, "verifica nascosta a mano")
            rules.weekdays = []
            rules.keywords = ["recupero"]
            rules.unmatched = true
            hiding.setTestRules(rules)
            check(hiding.hiddenReason(for: sabato, unmatched: false) == .rule("Contiene «recupero»"), "regola delle parole")
            check(hiding.hiddenReason(for: verdi, unmatched: true) == .manual, "a mano prima delle regole")
            if let backup = try? TimetableStore.readBackup(hiding.makeBackup()) {
                check(backup.timetable.testRules == rules, "regole perse nel backup")
            } else {
                failures.append("backup delle regole non riuscito")
            }
        } else {
            failures.append("verifiche di prova non decodificate")
        }

        print(failures.isEmpty ? "BCW-SELFTEST PASS" : "BCW-SELFTEST FAIL\n- " + failures.joined(separator: "\n- "))
        exit(failures.isEmpty ? 0 : 1)
    }
}
#endif
