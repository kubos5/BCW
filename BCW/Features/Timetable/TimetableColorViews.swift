import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Colore di un evento

/// Scelta del colore di un evento: automatico, colori suggeriti (quelli della sezione Lezioni),
/// colori personalizzati salvati e colori presi dalle palette.
struct EntryColorPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var color: EntryColor?
    let entry: TimetableEntry

    @State private var customColor = Color(hex: 0x4F7FA6)
    @State private var editingPalette: ColorPalette?

    private var store: TimetableStore { model.timetable }
    private let columns = [GridItem(.adaptive(minimum: 40, maximum: 52), spacing: 10)]

    var body: some View {
        Form {
            Section {
                Button {
                    color = nil
                } label: {
                    HStack(spacing: 12) {
                        Swatch(color: Theme.defaultTimetableColor(entry), isSelected: color == nil)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatico")
                                .foregroundStyle(Theme.ink)
                            Text(entry.isBreak ? "Il colore degli intervalli" : "Il colore della materia nella sezione Lezioni")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryInk)
                        }
                    }
                }
                .buttonStyle(.plain)
                if case let .series(id, _, _)? = color {
                    Label("Colorato con la palette «\(store.palette(id: id)?.name ?? "")» insieme alla sua giornata. Scegliendo un altro colore l'evento esce dalla serie.",
                          systemImage: "paintpalette")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
            .listRowBackground(Theme.surface)

            Section("Suggeriti") {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(0..<12, id: \.self) { index in
                        Button { color = .pastel(index) } label: {
                            Swatch(color: Theme.subjectColor(index), isSelected: color == .pastel(index))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Colore suggerito \(index + 1)")
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Theme.surface)

            Section {
                if !store.timetable.customColors.isEmpty {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(store.timetable.customColors, id: \.self) { hex in
                            Button { color = .custom(hex) } label: {
                                Swatch(color: Theme.timetableHex(hex), isSelected: color == .custom(hex))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Elimina colore", systemImage: "trash", role: .destructive) {
                                    withAnimation { store.deleteCustomColor(hex) }
                                }
                            }
                            .accessibilityLabel(String(format: "Colore personalizzato %06X", hex))
                        }
                    }
                    .padding(.vertical, 4)
                }
                ColorPicker("Scegli un colore", selection: $customColor, supportsOpacity: false)
                HStack {
                    Button("Usa questo colore") {
                        if let hex = customColor.rgbHex { color = .custom(hex) }
                    }
                    Spacer()
                    Button("Salva colore", systemImage: "plus.circle") {
                        if let hex = customColor.rgbHex {
                            withAnimation { store.saveCustomColor(hex) }
                            color = .custom(hex)
                        }
                    }
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Personalizzati")
            } footer: {
                Text("I colori salvati restano disponibili per tutti gli eventi. \(Platform.isMac ? "Fai clic con il tasto destro" : "Tieni premuto") su un colore per eliminarlo.")
            }
            .listRowBackground(Theme.surface)

            Section {
                ForEach(store.allPalettes) { palette in
                    PaletteSwatchRow(palette: palette, selected: color) { picked in
                        color = picked
                    } onEdit: {
                        editingPalette = palette
                    }
                }
                Button("Nuova palette", systemImage: "plus") {
                    editingPalette = ColorPalette(name: "", colors: [0xA6D8F2, 0x2F6FB5])
                }
            } header: {
                Text("Dalle palette")
            } footer: {
                Text("Tocca un colore per usarlo. Per colorare un'intera giornata con una sfumatura usa \"Colora una giornata\" nel menu dell'orario.")
            }
            .listRowBackground(Theme.surface)
        }
        .formStyle(.grouped)
        .themedList()
        .navigationTitle("Colore")
        .inlineTitleDisplay()
        .sheet(item: $editingPalette) { palette in
            PaletteEditor(palette: palette)
        }
    }
}

/// Riga di una palette: nome e colori da toccare.
private struct PaletteSwatchRow: View {
    let palette: ColorPalette
    let selected: EntryColor?
    let onPick: (EntryColor) -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(palette.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !palette.isBuiltIn {
                    Button("Modifica", action: onEdit)
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
            // A capo se i colori non stanno su una riga (la palette Pastello ne ha 12).
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 40), spacing: 6)], alignment: .leading, spacing: 6) {
                let samples = palette.samples(6)
                ForEach(Array(samples.enumerated()), id: \.offset) { index, hex in
                    let value: EntryColor = palette.id == ColorPalette.pastelID ? .pastel(index) : .custom(hex)
                    Button { onPick(value) } label: {
                        Swatch(color: palette.id == ColorPalette.pastelID ? Theme.subjectColor(index) : Theme.timetableHex(hex),
                               isSelected: selected == value, size: 30)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct Swatch: View {
    let color: Color
    var isSelected = false
    var size: CGFloat = 36

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.4, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(3)
            .overlay {
                Circle().strokeBorder(isSelected ? Theme.ink : Color.clear, lineWidth: 2)
            }
            .contentShape(.circle)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Striscia con i colori di una palette.
struct PaletteStrip: View {
    let palette: ColorPalette
    var height: CGFloat = 14

    var body: some View {
        let colors = palette.isGradient && palette.colors.count > 1
            ? palette.samples(12) : palette.colors
        HStack(spacing: palette.isGradient ? 0 : 2) {
            ForEach(Array(colors.enumerated()), id: \.offset) { index, hex in
                Rectangle().fill(palette.id == ColorPalette.pastelID ? Theme.subjectColor(index) : Theme.timetableHex(hex))
            }
        }
        .frame(height: height)
        .clipShape(.capsule)
    }
}

// MARK: - Palette personalizzate

/// Crea o modifica una palette: nome, colori scelti uno per uno, sfumatura o colori distinti.
struct PaletteEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var palette: ColorPalette
    @State private var colors: [Color]
    @State private var confirmingDelete = false

    init(palette: ColorPalette) {
        _palette = State(initialValue: palette)
        _colors = State(initialValue: palette.colors.map { Color(hex: $0) })
    }

    private var isNew: Bool {
        !model.timetable.timetable.customPalettes.contains { $0.id == palette.id }
    }

    private var resolved: ColorPalette {
        var result = palette
        result.colors = colors.compactMap(\.rgbHex)
        result.name = palette.name.trimmingCharacters(in: .whitespaces)
        return result
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome della palette", text: $palette.name)
                    Toggle("Sfumatura", isOn: $palette.isGradient)
                    PaletteStrip(palette: resolved, height: 22)
                        .padding(.vertical, 4)
                } footer: {
                    Text(palette.isGradient
                         ? "Con la sfumatura, applicando la palette a una serie di eventi i colori intermedi vengono calcolati in base al numero di eventi."
                         : "Senza sfumatura gli eventi di una serie prendono i colori uno dopo l'altro.")
                }
                .listRowBackground(Theme.surface)

                Section("Colori") {
                    ForEach(colors.indices, id: \.self) { index in
                        HStack {
                            ColorPicker("Colore \(index + 1)", selection: $colors[index], supportsOpacity: false)
                            if colors.count > 2 {
                                Button {
                                    colors.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(Theme.poor)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Rimuovi colore \(index + 1)")
                            }
                        }
                    }
                    .onMove { colors.move(fromOffsets: $0, toOffset: $1) }
                    if colors.count < 12 {
                        Button("Aggiungi colore", systemImage: "plus") {
                            colors.append(colors.last ?? Color(hex: 0x8FA3B8))
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                if !isNew && !palette.isBuiltIn {
                    Section {
                        Button("Elimina palette", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                            .foregroundStyle(Theme.poor)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .formStyle(.grouped)
            .themedList()
            .navigationTitle(isNew ? "Nuova palette" : "Modifica palette")
            .inlineTitleDisplay()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", systemImage: "checkmark") {
                        var saved = resolved
                        if saved.name.isEmpty { saved.name = "La mia palette" }
                        model.timetable.savePalette(saved)
                        dismiss()
                    }
                    .disabled(resolved.colors.count < 2)
                }
            }
            .confirmationDialog("Eliminare la palette «\(palette.name)»?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    model.timetable.deletePalette(palette.id)
                    dismiss()
                }
            } message: {
                Text("Gli eventi colorati con questa palette torneranno al colore automatico.")
            }
        }
        .sheetFrame(width: 440, height: 560)
    }
}

// MARK: - Palette su una serie di eventi

/// Colora una serie di eventi della stessa giornata con una palette: gli eventi scelti prendono
/// i colori della palette nell'ordine della giornata. Vale solo per quel giorno della settimana.
struct PaletteSeriesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var weekday: Int
    @State private var selection: Set<UUID> = []
    @State private var paletteID: String = "builtin.lagoon"
    @State private var editingPalette: ColorPalette?
    /// Primo evento toccato per la selezione di un intervallo.
    @State private var rangeAnchor: UUID?

    init(weekday: Int) {
        _weekday = State(initialValue: weekday)
    }

    private var store: TimetableStore { model.timetable }
    private var lessons: [TimetableEntry] { store.entries(weekday: weekday, includingDraft: false).filter { !$0.isBreak } }

    var body: some View {
        let lessons = lessons
        let palette = store.palette(id: paletteID) ?? ColorPalette.builtIn[1]
        let chosen = lessons.filter { selection.contains($0.id) }
        let positions = TimetableStore.seriesPositions(chosen)
        NavigationStack {
            Form {
                Section {
                    Picker("Giorno", selection: $weekday) {
                        ForEach(1...7, id: \.self) { Text(Weekday.name($0)).tag($0) }
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(store.allPalettes) { item in
                                Button { paletteID = item.id } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        PaletteStrip(palette: item, height: 18)
                                            .frame(width: 96)
                                        Text(item.name)
                                            .font(.caption.weight(item.id == paletteID ? .semibold : .regular))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(1)
                                    }
                                    .padding(8)
                                    .background {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(item.id == paletteID ? Theme.accent : Theme.separator,
                                                          lineWidth: item.id == paletteID ? 2 : 0.5)
                                    }
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                                .contextMenu {
                                    if !item.isBuiltIn {
                                        Button("Modifica", systemImage: "pencil") { editingPalette = item }
                                    }
                                }
                            }
                            Button {
                                editingPalette = ColorPalette(name: "", colors: [0x8BCF7E, 0x2B5C9E])
                            } label: {
                                Label("Nuova", systemImage: "plus")
                                    .font(.caption.weight(.semibold))
                                    .padding(12)
                            }
                            .glassButton()
                        }
                        .padding(.vertical, 4)
                    }
                    // La palette scelta resta in vista.
                    .onAppear { proxy.scrollTo(paletteID, anchor: .center) }
                    .onChange(of: paletteID) { _, id in withAnimation { proxy.scrollTo(id, anchor: .center) } }
                    }
                } header: {
                    Text("Palette")
                }
                .listRowBackground(Theme.surface)

                Section {
                    if lessons.isEmpty {
                        Text("Nessuna lezione il \(Weekday.name(weekday).lowercased()).")
                            .foregroundStyle(Theme.secondaryInk)
                    }
                    ForEach(lessons) { entry in
                        let offset = chosen.firstIndex { $0.id == entry.id }
                        let previewColor: Color = offset.map { index in
                            palette.id == ColorPalette.pastelID
                                ? Theme.subjectColor(positions.index[index])
                                : Theme.timetableHex(palette.color(at: positions.index[index], of: positions.count))
                        } ?? Theme.timetableColor(entry, store: store)
                        Button { toggle(entry, in: lessons) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selection.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selection.contains(entry.id) ? Theme.accent : Theme.secondaryInk)
                                RoundedRectangle(cornerRadius: 3).fill(previewColor).frame(width: 6, height: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.displayTitle).foregroundStyle(Theme.ink)
                                    Text(entry.timeRange)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.secondaryInk)
                                }
                                Spacer()
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Eventi")
                        Spacer()
                        Button("Tutti") { selection = Set(lessons.map(\.id)) }
                        Button("Nessuno") { selection = []; rangeAnchor = nil }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .textCase(nil)
                } footer: {
                    Text("\(Platform.isMac ? "Fai clic sugli eventi per sceglierli (con ⇧ prendi tutti quelli di seguito)." : "Tocca gli eventi per sceglierli: una serie di seguito o tutta la giornata.") Gli eventi uguali accostati prendono lo stesso colore. La palette vale solo per il \(Weekday.name(weekday).lowercased()): gli eventi con lo stesso nome negli altri giorni restano come sono.")
                }
                .listRowBackground(Theme.surface)
            }
            .formStyle(.grouped)
            .themedList()
            .navigationTitle("Colora una giornata")
            .inlineTitleDisplay()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Applica", systemImage: "checkmark") {
                        withAnimation(.snappy) { store.applyPalette(paletteID, to: chosen.map(\.id)) }
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                }
                ToolbarItem(placement: .destructiveActionPlacement) {
                    Button("Togli i colori") {
                        withAnimation(.snappy) { store.applyPalette(nil, to: chosen.map(\.id)) }
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                    .help("Riporta gli eventi scelti al colore automatico")
                }
            }
            .onChange(of: weekday) {
                selection = []
                rangeAnchor = nil
            }
            .onAppear {
                // Di partenza tutta la giornata; se è già colorata con una palette, quella.
                selection = Set(lessons.map(\.id))
                if let id = lessons.compactMap(\.color?.paletteID).first { paletteID = id }
            }
            .sheet(item: $editingPalette) { palette in
                PaletteEditor(palette: palette)
            }
        }
        .sheetFrame(width: 500, height: 640)
    }

    /// Un clic aggiunge o toglie un evento; su Mac con ⇧ sceglie tutti quelli tra l'ultimo
    /// scelto e questo.
    private func toggle(_ entry: TimetableEntry, in lessons: [TimetableEntry]) {
        #if os(macOS)
        if NSEvent.modifierFlags.contains(.shift), let anchor = rangeAnchor {
            selectRange(from: anchor, to: entry.id, in: lessons)
            rangeAnchor = entry.id
            return
        }
        #endif
        if selection.contains(entry.id) {
            selection.remove(entry.id)
        } else {
            selection.insert(entry.id)
            rangeAnchor = entry.id
        }
    }

    private func selectRange(from anchor: UUID, to id: UUID, in lessons: [TimetableEntry]) {
        guard let a = lessons.firstIndex(where: { $0.id == anchor }),
              let b = lessons.firstIndex(where: { $0.id == id }) else { return }
        selection.formUnion(lessons[min(a, b)...max(a, b)].map(\.id))
    }
}

extension ToolbarItemPlacement {
    /// Azione distruttiva in fondo al foglio (su Mac a sinistra dei pulsanti).
    static var destructiveActionPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .destructiveAction
        #else
        .bottomBar
        #endif
    }
}
