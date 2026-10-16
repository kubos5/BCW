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
        ScrollView {
            VStack(spacing: 20) {
                ListGroup(footer: seriesNote) {
                    Button {
                        color = nil
                    } label: {
                        ListRow("Automatico",
                                subtitle: entry.isBreak ? "Il colore degli intervalli" : "Il colore della materia nella sezione Lezioni",
                                leading: { Swatch(color: Theme.defaultTimetableColor(entry), isSelected: color == nil, size: 32) },
                                trailing: { EmptyView() })
                    }
                    .buttonStyle(.listRow)
                }

                ListGroup("Suggeriti") {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(0..<12, id: \.self) { index in
                            Button { color = .pastel(index) } label: {
                                Swatch(color: Theme.subjectColor(index), isSelected: color == .pastel(index))
                            }
                            .buttonStyle(SwatchStyle())
                            .accessibilityLabel("Colore suggerito \(index + 1)")
                        }
                    }
                    .padding(16)
                }

                ListGroup("Personalizzati", footer: "I colori salvati restano disponibili per tutti gli eventi. \(Platform.isMac ? "Fai clic con il tasto destro" : "Tieni premuto") su un colore per eliminarlo.") {
                    if !store.timetable.customColors.isEmpty {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(store.timetable.customColors, id: \.self) { hex in
                                Button { color = .custom(hex) } label: {
                                    Swatch(color: Theme.timetableHex(hex), isSelected: color == .custom(hex))
                                }
                                .buttonStyle(SwatchStyle())
                                .contextMenu {
                                    Button(role: .destructive) {
                                        withAnimation(Motion.spatial) { store.deleteCustomColor(hex) }
                                    } label: { Label("Elimina colore", icon: "trash") }
                                }
                                .accessibilityLabel(String(format: "Colore personalizzato %06X", hex))
                            }
                        }
                        .padding(16)
                    }
                    ListRow("Scegli un colore", leading: { FormIcon("colorize") }, trailing: {
                        ColorPicker("Scegli un colore", selection: $customColor, supportsOpacity: false)
                            .labelsHidden()
                    })
                    HStack(spacing: 8) {
                        Button("Usa questo colore") {
                            if let hex = customColor.rgbHex { color = .custom(hex) }
                        }
                        .buttonStyle(.m3(.text, size: .xs))
                        Spacer()
                        Button {
                            if let hex = customColor.rgbHex {
                                withAnimation(Motion.spatial) { store.saveCustomColor(hex) }
                                color = .custom(hex)
                            }
                        } label: {
                            Label { Text("Salva colore") } icon: { Icon("add") }
                        }
                        .buttonStyle(.m3(.tonal, size: .xs))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                ListGroup("Dalle palette", footer: "Tocca un colore per usarlo. Per colorare un'intera giornata con una sfumatura usa \"Colora una giornata\" nel menu dell'orario.") {
                    ForEach(store.allPalettes) { palette in
                        PaletteSwatchRow(palette: palette, selected: color) { picked in
                            color = picked
                        } onEdit: {
                            editingPalette = palette
                        }
                    }
                    ButtonRow("Nuova palette", icon: "plus") {
                        editingPalette = ColorPalette(name: "", colors: [0xA6D8F2, 0x2F6FB5])
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .themedBackground()
        .pageChrome("Colore", style: .inline, showsBack: true)
        .sheet(item: $editingPalette) { palette in
            PaletteEditor(palette: palette)
        }
    }

    private var seriesNote: String? {
        guard case let .series(id, _, _)? = color else { return nil }
        return "Colorato con la palette «\(store.palette(id: id)?.name ?? "")» insieme alla sua giornata. Scegliendo un altro colore l'evento esce dalla serie."
    }
}

/// Campioni che si rimpiccioliscono alla pressione.
private struct SwatchStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.spatialFast, value: configuration.isPressed)
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
                    .font(.m3(14, weight: 600))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if !palette.isBuiltIn {
                    Button("Modifica", action: onEdit)
                        .buttonStyle(.m3(.text, size: .xs))
                }
            }
            .frame(minHeight: 32)
            // A capo se i colori non stanno su una riga (la palette Pastello ne ha 12).
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 40), spacing: 6)], alignment: .leading, spacing: 6) {
                let samples = palette.samples(6)
                ForEach(Array(samples.enumerated()), id: \.offset) { index, hex in
                    let value: EntryColor = palette.id == ColorPalette.pastelID ? .pastel(index) : .custom(hex)
                    Button { onPick(value) } label: {
                        Swatch(color: palette.id == ColorPalette.pastelID ? Theme.subjectColor(index) : Theme.timetableHex(hex),
                               isSelected: selected == value, size: 30)
                    }
                    .buttonStyle(SwatchStyle())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct Swatch: View {
    let color: Color
    var isSelected = false
    var size: CGFloat = 36

    var body: some View {
        let radius = isSelected ? size * 0.3 : size / 2
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.shadow.opacity(0.1), lineWidth: 1))
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    Icon("check", size: size * 0.6)
                        .foregroundStyle(Theme.surfaceContainerLowest)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                }
            }
            .padding(3)
            .overlay {
                RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                    .strokeBorder(isSelected ? Theme.ink : Color.clear, lineWidth: 2)
            }
            .contentShape(.rect)
            .animation(Motion.spatialFast, value: isSelected)
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
        .clipShape(.capsule(style: .continuous))
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
            ScrollView {
                VStack(spacing: 20) {
                    ListGroup(footer: palette.isGradient
                              ? "Con la sfumatura, applicando la palette a una serie di eventi i colori intermedi vengono calcolati in base al numero di eventi."
                              : "Senza sfumatura gli eventi di una serie prendono i colori uno dopo l'altro.") {
                        TextFieldRow("Nome della palette", text: $palette.name, icon: "edit")
                        ToggleRow("Sfumatura", icon: "colorStyle", isOn: $palette.isGradient)
                        PaletteStrip(palette: resolved, height: 22)
                            .padding(16)
                    }

                    ListGroup("Colori") {
                        ForEach(colors.indices, id: \.self) { index in
                            HStack(spacing: 16) {
                                Circle().fill(colors[index]).frame(width: 24, height: 24)
                                Text("Colore \(index + 1)")
                                    .font(.m3(16, weight: 500))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                ColorPicker("Colore \(index + 1)", selection: $colors[index], supportsOpacity: false)
                                    .labelsHidden()
                                if colors.count > 2 {
                                    IconButton("minusCircle", label: "Rimuovi colore \(index + 1)", kind: .danger, size: 32) {
                                        withAnimation(Motion.spatial) { _ = colors.remove(at: index) }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .frame(minHeight: 56)
                        }
                        if colors.count < 12 {
                            ButtonRow("Aggiungi colore", icon: "plus") {
                                withAnimation(Motion.spatial) { colors.append(colors.last ?? Color(hex: 0x8FA3B8)) }
                            }
                        }
                    }

                    if !isNew && !palette.isBuiltIn {
                        ListGroup {
                            ButtonRow("Elimina palette", icon: "trash", destructive: true) { confirmingDelete = true }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .sheetChrome(isNew ? "Nuova palette" : "Modifica palette", leading: .cancel { dismiss() },
                         trailing: [.confirm("Salva", disabled: resolved.colors.count < 2) {
                             var saved = resolved
                             if saved.name.isEmpty { saved.name = "La mia palette" }
                             model.timetable.savePalette(saved)
                             dismiss()
                         }])
            .m3Dialog("Eliminare la palette «\(palette.name)»?", isPresented: $confirmingDelete,
                      message: "Gli eventi colorati con questa palette torneranno al colore automatico.") {
                [.cancel(), DialogAction(title: "Elimina", style: .destructive) {
                    model.timetable.deletePalette(palette.id)
                    dismiss()
                }]
            }
        }
        .m3Sheet()
        .sheetFrame(width: 460, height: 600)
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
            ScrollView {
                VStack(spacing: 20) {
                    ListGroup {
                        SelectRow("Giorno", icon: "calendar", selection: $weekday,
                                  options: (1...7).map { ($0, Weekday.name($0), nil) })
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        ListHeader("Palette")
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(store.allPalettes) { item in
                                        let selected = item.id == paletteID
                                        Button { paletteID = item.id } label: {
                                            VStack(alignment: .leading, spacing: 6) {
                                                PaletteStrip(palette: item, height: 18)
                                                Text(item.name)
                                                    .font(.m3(12, weight: selected ? 700 : 400))
                                                    .foregroundStyle(Theme.ink)
                                                    .lineLimit(1)
                                            }
                                            .padding(8)
                                            .frame(width: 112, alignment: .leading)
                                            .background(Theme.surfaceContainer,
                                                        in: .rect(cornerRadius: selected ? 22 : Theme.radii.l, style: .continuous))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: selected ? 22 : Theme.radii.l, style: .continuous)
                                                    .strokeBorder(selected ? Theme.primary : Theme.outlineVariant, lineWidth: selected ? 2 : 1)
                                            }
                                            .contentShape(.rect)
                                        }
                                        .buttonStyle(SwatchStyle())
                                        .id(item.id)
                                        .contextMenu {
                                            if !item.isBuiltIn {
                                                Button { editingPalette = item } label: { Label("Modifica", icon: "edit") }
                                            }
                                        }
                                    }
                                    Button {
                                        editingPalette = ColorPalette(name: "", colors: [0x8BCF7E, 0x2B5C9E])
                                    } label: {
                                        VStack(spacing: 4) {
                                            Icon("plus")
                                            Text("Nuova").font(.m3(12, weight: 600))
                                        }
                                        .foregroundStyle(Theme.primary)
                                        .frame(width: 112, height: 58)
                                        .background(Theme.surfaceContainer, in: .rect(cornerRadius: Theme.radii.l, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: Theme.radii.l, style: .continuous)
                                            .strokeBorder(Theme.outlineVariant, lineWidth: 1))
                                    }
                                    .buttonStyle(SwatchStyle())
                                }
                                .padding(2)
                                .padding(.bottom, 6)
                            }
                            // La palette scelta resta in vista.
                            .onAppear { proxy.scrollTo(paletteID, anchor: .center) }
                            .onChange(of: paletteID) { _, id in withAnimation(Motion.spatial) { proxy.scrollTo(id, anchor: .center) } }
                        }
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            ListHeader("Eventi")
                            Spacer()
                            HStack(spacing: 4) {
                                Button("Tutti") { selection = Set(lessons.map(\.id)) }
                                Button("Nessuno") { selection = []; rangeAnchor = nil }
                            }
                            .buttonStyle(.m3(.text, size: .xs))
                            .padding(.bottom, 6)
                        }
                        ListGroup(footer: "\(Platform.isMac ? "Fai clic sugli eventi per sceglierli (con ⇧ prendi tutti quelli di seguito)." : "Tocca gli eventi per sceglierli: una serie di seguito o tutta la giornata.") Gli eventi uguali accostati prendono lo stesso colore. La palette vale solo per il \(Weekday.name(weekday).lowercased()): gli eventi con lo stesso nome negli altri giorni restano come sono.") {
                            if lessons.isEmpty {
                                ListRow("Nessuna lezione il \(Weekday.name(weekday).lowercased()).", titleColor: Theme.secondaryInk)
                            }
                            ForEach(lessons) { entry in
                                let offset = chosen.firstIndex { $0.id == entry.id }
                                let previewColor: Color = offset.map { index in
                                    palette.id == ColorPalette.pastelID
                                        ? Theme.subjectColor(positions.index[index])
                                        : Theme.timetableHex(palette.color(at: positions.index[index], of: positions.count))
                                } ?? Theme.timetableColor(entry, store: store)
                                let isSelected = selection.contains(entry.id)
                                Button { toggle(entry, in: lessons) } label: {
                                    ListRow(entry.displayTitle, subtitle: entry.timeRange, leading: {
                                        HStack(spacing: 12) {
                                            Icon(isSelected ? "checkCircleFill" : "circle")
                                                .foregroundStyle(isSelected ? Theme.primary : Theme.secondaryInk)
                                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                                .fill(previewColor)
                                                .frame(width: 6, height: 30)
                                        }
                                    }, trailing: { EmptyView() })
                                }
                                .buttonStyle(.listRow)
                            }
                        }
                    }

                    ListGroup {
                        ButtonRow("Togli i colori", icon: "x", destructive: true) {
                            withAnimation(Motion.spatial) { store.applyPalette(nil, to: chosen.map(\.id)) }
                            dismiss()
                        }
                        .disabled(chosen.isEmpty)
                        .help("Riporta gli eventi scelti al colore automatico")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .sheetChrome("Colora una giornata", leading: .cancel { dismiss() },
                         trailing: [.confirm("Applica", disabled: chosen.isEmpty) {
                             withAnimation(Motion.spatial) { store.applyPalette(paletteID, to: chosen.map(\.id)) }
                             dismiss()
                         }])
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
        .m3Sheet()
        .sheetFrame(width: 520, height: 680)
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

